# From the project root in the Questa Transcript: do sim/run.do
onerror {abort}

set cache_test_name cache_test
set cache_ram_wait 1
set cache_seed 1
if {[info exists 1]} {
    set cache_test_name [set 1]
}
if {[info exists 2]} {
    set cache_ram_wait [set 2]
}
if {[info exists 3]} {
    set cache_seed [set 3]
}
if {$cache_ram_wait ne "random" && (![string is integer -strict $cache_ram_wait] || $cache_ram_wait < 1 || $cache_ram_wait > 8)} {
    error "RAM wait must be 1 through 8, or random"
}
if {![string is integer -strict $cache_seed] || $cache_seed < 1} {
    error "Seed must be a positive integer"
}
set cache_sim_log simulation.log
if {$cache_test_name ne "cache_test" || $cache_ram_wait != 1} {
    set cache_sim_log "${cache_test_name}_wait${cache_ram_wait}.log"
}
if {$cache_ram_wait eq "random"} {
    set cache_sim_log "${cache_test_name}_random_seed${cache_seed}.log"
}
set cache_run_args [list "+UVM_TESTNAME=$cache_test_name" -sv_seed $cache_seed]
if {$cache_ram_wait eq "random"} {
    lappend cache_run_args +RAM_RANDOM
} else {
    lappend cache_run_args "+RAM_WAIT=$cache_ram_wait"
}
if {$cache_test_name in {cache_stream_test cache_random_test}} {
    lappend cache_run_args +CPU_STREAM
}

set cache_project_dir [file normalize [pwd]]
if {![file exists [file join $cache_project_dir tb cache_pkg.sv]]} {
    error "First cd to the cache_riscv project folder, then enter: do sim/run.do"
}
set cache_sim_dir [file join $cache_project_dir sim]
set cache_build_dir [file join $cache_sim_dir build]
source [file join $cache_project_dir sim tools.tcl]
set cache_questa_dir [cache_tools::questa_home]
set cache_uvm_dir [cache_tools::uvm_home]
set cache_tb_dir [file join $cache_project_dir tb]

file mkdir $cache_build_dir
cd $cache_build_dir

# Keep this run's library mapping inside the project build directory.
set cache_ini [file join $cache_build_dir modelsim.ini]
if {![file exists $cache_ini]} {
    set cache_ini_handle [open $cache_ini w]
    puts $cache_ini_handle {[Library]}
    puts $cache_ini_handle {work = work}
    puts $cache_ini_handle "others = [file join $cache_questa_dir modelsim.ini]"
    close $cache_ini_handle
}
if {![file isdirectory [file join $cache_build_dir work]]} {
    vlib work
}

# Classes are included through cache_pkg.sv; compile the interface first.
if {![info exists cache_skip_compile] || !$cache_skip_compile} {
    vlog -modelsimini modelsim.ini -sv -work work -L mtiUvm -l compile.log \
        "+incdir+$cache_uvm_dir" "+incdir+$cache_tb_dir" \
        [file join $cache_tb_dir cache_if.sv] \
        [file join $cache_tb_dir cache_pkg.sv] \
        [file join $cache_project_dir rtl data_cache.sv] \
        [file join $cache_tb_dir ram_model.sv] \
        [file join $cache_tb_dir cache_stall_checks.sv] \
        [file join $cache_tb_dir cache_tb_top.sv]
}

# SV covergroups/assertions are collected by default. Code coverage is outside
# this functional signoff; -coverage would request uninstrumented code counters.
vsim -modelsimini modelsim.ini -t 1ps -voptargs=+acc -onfinish stop \
    -l $cache_sim_log work.cache_tb_top \
    {*}$cache_run_args

if {![batch_mode]} {
    view wave
    add wave -group CPU sim:/cache_tb_top/clk
    foreach cache_signal {rst_n cpu_valid cpu_ready cpu_addr cpu_wstrb cpu_wdata cpu_rdata} {
        add wave -group CPU sim:/cache_tb_top/vif/$cache_signal
    }
    foreach cache_signal {mem_valid mem_ready mem_addr mem_wstrb mem_wdata mem_rdata} {
        add wave -group RAM sim:/cache_tb_top/vif/$cache_signal
    }
}

run -all
coverage save [file rootname $cache_sim_log].ucdb

if {![batch_mode]} {
    wave zoom full
}
puts "Compile log: [file join $cache_build_dir compile.log]"
puts "Simulation log: [file join $cache_build_dir $cache_sim_log]"
