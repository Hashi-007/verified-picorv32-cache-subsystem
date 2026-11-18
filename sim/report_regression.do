# Called after all positive runs. May also finalize an existing result folder:
# do sim/report_regression.do sim/build/regression_TIMESTAMP
onerror {abort}
source [file join [pwd] sim tools.tcl]
set report_root [file normalize [pwd]]
set report_dir [file normalize [set 1]]
do sim/run_checker_probe.do
foreach report_file {checker_probe.log checker_probe_compile.log} {
    file copy -force [file join $report_root sim build $report_file] $report_dir
}
set report_vcover [cache_tools::vcover]
set report_inputs {}
foreach report_input [glob -directory $report_dir *.ucdb] {
    if {[file tail $report_input] ne "merged.ucdb"} {
        lappend report_inputs $report_input
    }
}
exec $report_vcover merge [file join $report_dir merged.ucdb] {*}$report_inputs \
    > [file join $report_dir merge.log] 2>@1
exec $report_vcover report -summary -output [file join $report_dir coverage_summary.txt] \
    [file join $report_dir merged.ucdb] > [file join $report_dir coverage_report.log] 2>@1
exec $report_vcover report -cvg -details -output [file join $report_dir coverage_details.txt] \
    [file join $report_dir merged.ucdb] >> [file join $report_dir coverage_report.log] 2>@1
set report_python [cache_tools::python]
puts [exec {*}$report_python [file join $report_root verification check_regression.py] $report_dir]
puts "REGRESSION_DIR=$report_dir"
