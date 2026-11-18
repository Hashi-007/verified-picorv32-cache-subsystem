# From cache_riscv: do sim/run_processor.do PROGRAM USE_DCACHE RAM_WAIT_CYCLES USE_ICACHE
# Defaults: smoke, D-cache enabled, one-cycle RAM wait, I-cache disabled.
onerror {quit -code 1 -force}
source [file join [pwd] sim tools.tcl]
set processor_program smoke
set processor_use_cache 1
set processor_ram_wait 1
set processor_use_icache 0
if {[info exists 1]} {
    set processor_program [set 1]
}
if {[info exists 2]} {
    set processor_use_cache [set 2]
}
if {[info exists 3]} {
    set processor_ram_wait [set 3]
}
if {[info exists 4]} {
    set processor_use_icache [set 4]
}
if {[info exists 5]} {
    error "Usage: do sim/run_processor.do PROGRAM USE_DCACHE RAM_WAIT_CYCLES USE_ICACHE"
}
if {$processor_use_cache ni {0 1}} {
    error "USE_DCACHE must be 0 or 1"
}
if {$processor_use_icache ni {0 1}} {
    error "USE_ICACHE must be 0 or 1"
}
if {![string is integer -strict $processor_ram_wait] || $processor_ram_wait < 1 || $processor_ram_wait > 8} {
    error "RAM wait must be an integer from 1 through 8"
}
switch -- $processor_program {
    smoke {
        set processor_program_hex programs/cache_smoke.hex
        set processor_result_addr [expr {0x1004}]
        set processor_expected_result [expr {0x11223345}]
        set processor_timeout_us 20
    }
    reuse {
        set processor_program_hex programs/cache_reuse.hex
        set processor_result_addr [expr {0x1100}]
        set processor_expected_result 2176
        set processor_timeout_us 300
    }
    sequential {
        set processor_program_hex programs/cache_sequential.hex
        set processor_result_addr [expr {0x3000}]
        set processor_expected_result 819840
        set processor_timeout_us 2000
    }
    conflict {
        set processor_program_hex programs/cache_conflict.hex
        set processor_result_addr [expr {0x3000}]
        set processor_expected_result 384
        set processor_timeout_us 500
    }
    store_heavy {
        set processor_program_hex programs/cache_store_heavy.hex
        set processor_result_addr [expr {0x3000}]
        set processor_expected_result 256
        set processor_timeout_us 500
    }
    default {error "Program must be smoke, reuse, sequential, conflict or store_heavy"}
}
set processor_expected_hex [format %08x $processor_expected_result]
set processor_root [file normalize [pwd]]
if {![file isfile [file join $processor_root $processor_program_hex]]} {
    error "Start in the cache_riscv project folder; $processor_program_hex is required"
}
# Questa's Windows loader needs a space-free relative -modelsimini argument.
set processor_build [file join sim build processor_program]
file mkdir $processor_build
set processor_run_name "${processor_program}_cache${processor_use_cache}_wait${processor_ram_wait}"
if {$processor_use_icache} {
    append processor_run_name _icache1
}
set processor_sim_log [file join $processor_build "${processor_run_name}.log"]
set processor_waves [file join $processor_build "${processor_run_name}.wlf"]
if {$processor_program eq "smoke" && $processor_use_cache == 1 && $processor_ram_wait == 1 && !$processor_use_icache} {
    set processor_sim_log [file join $processor_build simulation.log]
    set processor_waves [file join $processor_build waves.wlf]
}
set processor_library [file normalize [file join $processor_build work]]
set processor_ini [file join $processor_build modelsim.ini]
set processor_ini_file [open $processor_ini w]
puts $processor_ini_file {[Library]}
puts $processor_ini_file "work = $processor_library"
puts $processor_ini_file "others = [file join [cache_tools::questa_home] modelsim.ini]"
close $processor_ini_file
if {![file isdirectory $processor_library]} {
    vlib $processor_library
}

# Keep the project working directory so relative $readmemh paths resolve.
vlog -modelsimini $processor_ini -sv -timescale 1ns/1ps -work work \
    -l [file join $processor_build compile.log] \
    [file join $processor_root third_party picorv32 picorv32.v] \
    [file join $processor_root rtl data_cache.sv] \
    [file join $processor_root rtl instruction_cache.sv] \
    [file join $processor_root rtl cache_wrapper.sv] \
    [file join $processor_root rtl processor_top.sv] \
    [file join $processor_root tb wrapper_ram_model.sv] \
    [file join $processor_root tb processor_tb.sv]

# Keep the completion/readback flags and CPU registers visible for final checks.
vsim -modelsimini $processor_ini -t 1ps -voptargs=+acc -onfinish stop \
    -gUSE_DCACHE=$processor_use_cache -gUSE_ICACHE=$processor_use_icache \
    -gRAM_WAIT_CYCLES=$processor_ram_wait \
    -gPROGRAM_HEX=$processor_program_hex -gRESULT_ADDR=$processor_result_addr \
    -gEXPECTED_RESULT=$processor_expected_result \
    -wlf $processor_waves -l $processor_sim_log work.processor_tb
foreach {processor_path processor_value} [list \
    sim:/processor_tb/USE_DCACHE $processor_use_cache \
    sim:/processor_tb/USE_ICACHE $processor_use_icache \
    sim:/processor_tb/dut/USE_DCACHE $processor_use_cache \
    sim:/processor_tb/dut/USE_ICACHE $processor_use_icache \
    sim:/processor_tb/dut/cache/USE_DCACHE $processor_use_cache \
    sim:/processor_tb/dut/cache/USE_ICACHE $processor_use_icache] {
    if {[string trim [examine -radix unsigned $processor_path]] ne "$processor_value"} {
        error "Cache parameter did not propagate: $processor_path expected $processor_value"
    }
}
if {![batch_mode]} {
    view wave
    add wave sim:/processor_tb/*
    add wave sim:/processor_tb/dut/mem_*
}

# A finite limit also catches a missing marker or stalled program/readback.
run $processor_timeout_us us
if {[string trim [examine -radix unsigned sim:/processor_tb/program_completed]] ne "1"} {
    error "Processor program did not complete within $processor_timeout_us us"
}
if {[string trim [examine -radix unsigned sim:/processor_tb/readback_passed]] ne "1"} {
    error "Processor result readback did not pass within $processor_timeout_us us"
}
set processor_result [string tolower [string trim \
    [examine -radix hexadecimal {sim:/processor_tb/dut/cpu/cpuregs[3]}]]]
if {$processor_result ne $processor_expected_hex} {
    error "CPU x3 readback mismatch: expected $processor_expected_hex, got $processor_result"
}
puts "PROCESSOR_PROGRAM_PASS: program=$processor_program dcache=$processor_use_cache icache=$processor_use_icache wait=$processor_ram_wait; marker=1 at 00010FFC; x3=$processor_result; result readback passed"
puts "Processor compile log: [file join $processor_build compile.log]"
puts "Processor simulation log: $processor_sim_log"
if {![batch_mode]} {
    wave zoom full
}
