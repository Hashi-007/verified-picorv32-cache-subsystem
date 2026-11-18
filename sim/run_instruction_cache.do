# From cache_riscv: do sim/run_instruction_cache.do
# Directed standalone checks of the instruction cache, RAM waits 1/4/8.
onerror {quit -code 1 -force}
source [file join [pwd] sim tools.tcl]
set ic_build sim/build/instruction_cache
file mkdir $ic_build
set ic_library [file normalize [file join $ic_build work]]
set ic_ini [file join $ic_build modelsim.ini]
set ic_file [open $ic_ini w]
puts $ic_file {[Library]}
puts $ic_file "work = $ic_library"
puts $ic_file "others = [file join [cache_tools::questa_home] modelsim.ini]"
close $ic_file
if {![file isdirectory $ic_library]} {
    vlib $ic_library
}
vlog -modelsimini $ic_ini -sv -timescale 1ns/1ps -work work \
    -l [file join $ic_build compile.log] \
    rtl/instruction_cache.sv tb/wrapper_ram_model.sv tb/instruction_cache_tb.sv
foreach ic_wait {1 4 8} {
    vsim -modelsimini $ic_ini -t 1ps -voptargs=+acc -onfinish stop \
        -gRAM_WAIT_CYCLES=$ic_wait \
        -wlf [file join $ic_build "wait${ic_wait}.wlf"] \
        -l [file join $ic_build "wait${ic_wait}.log"] work.instruction_cache_tb
    run 100 us
    if {[string trim [examine -radix unsigned sim:/instruction_cache_tb/passed]] ne "1"} {
        error "Instruction-cache standalone checks failed at RAM wait $ic_wait"
    }
    quit -sim
}
puts {ICACHE_STANDALONE_SUITE_PASS: RAM waits 1/4/8}
