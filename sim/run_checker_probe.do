# Isolated checker fault injection. Twenty UVM errors are EXPECTED in this log.
onerror {abort}
set probe_root [file normalize [pwd]]
cd [file join $probe_root sim build]
vlog -modelsimini modelsim.ini -sv -work work -L mtiUvm -l checker_probe_compile.log \
    [file join $probe_root verification cache_checker_probe.sv]
vsim -modelsimini modelsim.ini -t 1ps -onfinish stop -l checker_probe.log work.cache_checker_probe
run -all
quit -sim
cd $probe_root
