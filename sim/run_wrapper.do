# From cache_riscv: do sim/run_wrapper.do
# Plain SystemVerilog; independent of the standalone UVM compile/run scripts.
onerror {quit -code 1 -force}
source [file join [pwd] sim tools.tcl]
set wrapper_root [file normalize [pwd]]
if {![file exists [file join $wrapper_root rtl cache_wrapper.sv]]} {
    error "Start in the cache_riscv project folder"
}
set wrapper_build [file join $wrapper_root sim build wrapper]
file mkdir $wrapper_build
cd $wrapper_build

if {![file exists modelsim.ini]} {
    set wrapper_ini [open modelsim.ini w]
    puts $wrapper_ini {[Library]}
    puts $wrapper_ini {work = work}
    puts $wrapper_ini "others = [file join [cache_tools::questa_home] modelsim.ini]"
    close $wrapper_ini
}
if {![file isdirectory work]} {
    vlib work
}
vlog -modelsimini modelsim.ini -sv -work work -l compile.log \
    [file join $wrapper_root rtl data_cache.sv] \
    [file join $wrapper_root rtl instruction_cache.sv] \
    [file join $wrapper_root rtl cache_wrapper.sv] \
    [file join $wrapper_root tb wrapper_ram_model.sv] \
    [file join $wrapper_root tb cache_wrapper_tb.sv]

# Keep test_passed visible to the final Tcl check, including batch runs.
set wrapper_load [list -modelsimini modelsim.ini -t 1ps -voptargs=+acc -onfinish stop -l simulation.log]
vsim {*}$wrapper_load work.cache_wrapper_tb
if {![batch_mode]} {
    view wave
    add wave sim:/cache_wrapper_tb/*
}
run -all
if {[string trim [examine -radix unsigned sim:/cache_wrapper_tb/test_passed]] ne "1"} {
    error "Wrapper test did not reach its checked PASS condition"
}
puts "Wrapper compile log: [file join $wrapper_build compile.log]"
puts "Wrapper simulation log: [file join $wrapper_build simulation.log]"
if {![batch_mode]} {
    wave zoom full
}
