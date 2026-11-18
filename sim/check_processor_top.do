# From cache_riscv: do sim/check_processor_top.do
# Compile and elaborate the processor/cache hierarchy; do not execute a program.
onerror {quit -code 1 -force}
source [file join [pwd] sim tools.tcl]
set processor_root [file normalize [pwd]]
if {![file exists [file join $processor_root third_party picorv32 picorv32.v]]} {
    error "Start in the cache_riscv project folder; the pinned CPU source is required"
}
set processor_build [file join $processor_root sim build processor_top]
file mkdir $processor_build
cd $processor_build
if {![file exists modelsim.ini]} {
    set processor_ini [open modelsim.ini w]
    puts $processor_ini {[Library]}
    puts $processor_ini {work = work}
    puts $processor_ini "others = [file join [cache_tools::questa_home] modelsim.ini]"
    close $processor_ini
}
if {![file isdirectory work]} {
    vlib work
}
vlog -modelsimini modelsim.ini -sv -timescale 1ns/1ps -work work -l compile.log \
    [file join $processor_root third_party picorv32 picorv32.v] \
    [file join $processor_root rtl data_cache.sv] \
    [file join $processor_root rtl instruction_cache.sv] \
    [file join $processor_root rtl cache_wrapper.sv] \
    [file join $processor_root rtl processor_top.sv]
vsim -modelsimini modelsim.ini -t 1ps -l elaboration.log work.processor_top
puts "PROCESSOR_TOP_ELAB_PASS: CPU, wrapper and cache hierarchy loaded; no program executed"
puts "Compile log: [file join $processor_build compile.log]"
puts "Elaboration log: [file join $processor_build elaboration.log]"
