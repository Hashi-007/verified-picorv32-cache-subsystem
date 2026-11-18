# Start in the cache_riscv project folder. Compile once, run all 16 cases.
onerror {quit -code 1 -force}
set regression_root [file normalize [pwd]]
set regression_dir [file join $regression_root sim build regression_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
file mkdir $regression_dir
set regression_cases {{cache_test 1 1}}
for {set delay 1} {$delay <= 8} {incr delay} {
    lappend regression_cases [list cache_wait_test $delay 1]
}
lappend regression_cases {cache_reset_test 4 1} {cache_stream_test 4 1} \
    {cache_reset_sweep_test 4 1} {cache_reset_sweep_test random 7} \
    {cache_random_test random 1} {cache_random_test random 7} {cache_random_test random 23}
set cache_skip_compile 0
foreach regression_case $regression_cases {
    cd $regression_root
    do sim/run.do {*}$regression_case
    file copy -force $cache_sim_log [file join $regression_dir $cache_sim_log]
    file copy -force [file rootname $cache_sim_log].ucdb $regression_dir
    file copy -force compile.log [file join $regression_dir compile.log]
    quit -sim
    set cache_skip_compile 1
}
cd $regression_root
do sim/report_regression.do $regression_dir
quit -code 0 -force
