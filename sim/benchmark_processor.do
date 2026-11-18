# From cache_riscv: do sim/benchmark_processor.do
# Run all 24 configurations with the final measurement fields.
onerror {quit -code 1 -force}
source [file join [pwd] sim tools.tcl]
set bench_mode all
if {[info exists 1]} {
    set bench_mode [set 1]
}
if {[info exists 2] || $bench_mode ne "all"} {
    error "Usage: do sim/benchmark_processor.do (optional argument: all)"
}
set bench_build [file join sim build processor_metrics_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
set bench_cmd [list {*}[cache_tools::python] verification/processor_benchmarks.py $bench_build]
set bench_plan [exec {*}$bench_cmd --plan]
set bench_results {}
foreach bench_row $bench_plan {
    lassign $bench_row bench_name bench_program bench_cache bench_wait bench_cycles \
        bench_instr bench_reads bench_writes bench_hits bench_misses \
        bench_cpu_reads bench_cpu_stores bench_read_hits bench_read_misses bench_tb_reads bench_tb_writes
    do sim/run_processor.do $bench_program $bench_cache $bench_wait
    foreach {bench_path bench_value} [list \
        sim:/processor_tb/USE_DCACHE $bench_cache \
        sim:/processor_tb/USE_ICACHE 0 \
        sim:/processor_tb/RAM_WAIT_CYCLES $bench_wait \
        sim:/processor_tb/ram_instr_reads $bench_instr \
        sim:/processor_tb/ram_data_reads $bench_reads \
        sim:/processor_tb/ram_data_writes $bench_writes \
        sim:/processor_tb/cache_hits $bench_hits \
        sim:/processor_tb/cache_misses $bench_misses \
        sim:/processor_tb/cpu_data_reads $bench_cpu_reads \
        sim:/processor_tb/cpu_data_stores $bench_cpu_stores \
        sim:/processor_tb/cache_read_hits $bench_read_hits \
        sim:/processor_tb/cache_read_misses $bench_read_misses \
        sim:/processor_tb/tb_ram_reads $bench_tb_reads \
        sim:/processor_tb/tb_ram_writes $bench_tb_writes \
        sim:/processor_tb/request_had_refill 0 \
        sim:/processor_tb/program_completed 1 \
        sim:/processor_tb/readback_passed 1 \
        sim:/processor_tb/tb_owns_port 1 \
        sim:/processor_tb/tb_valid 0 \
        sim:/processor_tb/trap 0] {
        if {[string trim [examine -radix unsigned $bench_path]] ne "$bench_value"} {
            error "Benchmark mismatch: $bench_name, $bench_path expected $bench_value"
        }
    }
    quit -sim
    set bench_log [file join $bench_build "${bench_name}.log"]
    file copy -force $processor_sim_log $bench_log
    file copy -force [file join $processor_build compile.log] [file join $bench_build "${bench_name}_compile.log"]
    set bench_file [open $bench_log r]
    set bench_text [read $bench_file]
    close $bench_file
    if {![regexp {USE_CACHE=[01] cycles=([0-9]+)} $bench_text unused bench_actual_cycles] ||
        $bench_actual_cycles != $bench_cycles} {error "Cycle count mismatch: $bench_name"}
    if {![regexp {RAM_TRAFFIC instr_reads=([0-9]+) data_reads=([0-9]+) data_writes=([0-9]+)} \
        $bench_text unused report_instr report_reads report_writes] ||
        $report_instr != $bench_instr || $report_reads != $bench_reads || $report_writes != $bench_writes} {
        error "RAM counters changed during TB readback: $bench_name"
    }
    if {![regexp {CACHE_ACCESS cache_enabled=([01]) hits=([0-9]+) misses=([0-9]+)} \
        $bench_text unused report_cache report_hits report_misses] ||
        $report_cache != $bench_cache || $report_hits != $bench_hits || $report_misses != $bench_misses} {
        error "Hit/miss counters changed during TB readback: $bench_name"
    }
    if {![regexp {CPU_DATA reads=([0-9]+) stores=([0-9]+) read_hits=([0-9]+) read_misses=([0-9]+)} \
        $bench_text unused report_cpu_reads report_cpu_stores report_read_hits report_read_misses] ||
        $report_cpu_reads != $bench_cpu_reads || $report_cpu_stores != $bench_cpu_stores ||
        $report_read_hits != $bench_read_hits || $report_read_misses != $bench_read_misses} {
        error "CPU/read-hit counters changed during TB readback: $bench_name"
    }
    if {![regexp {CHECKER_READBACK requests=1 ram_reads=([0-9]+) ram_writes=([0-9]+)} \
        $bench_text unused report_tb_reads report_tb_writes] ||
        $report_tb_reads != $bench_tb_reads || $report_tb_writes != $bench_tb_writes} {
        error "Checker readback traffic mismatch: $bench_name"
    }
    lappend bench_results [format {{"name":"%s","program":"%s","use_cache":%d,"ram_wait_cycles":%d,"program_cycles":%d,"ram_instr_reads":%d,"ram_data_reads":%d,"ram_data_writes":%d,"cache_hits":%d,"cache_misses":%d,"cpu_data_reads":%d,"cpu_data_stores":%d,"cache_read_hits":%d,"cache_read_misses":%d,"tb_ram_reads":%d,"tb_ram_writes":%d,"program_completed":1,"readback_passed":1,"post_readback_counters_unchanged":true}} \
        $bench_name $bench_program $bench_cache $bench_wait $bench_actual_cycles \
        $report_instr $report_reads $report_writes $report_hits $report_misses \
        $report_cpu_reads $report_cpu_stores $report_read_hits $report_read_misses $report_tb_reads $report_tb_writes]
    set bench_file [open [file join $bench_build new_results.json] w]
    puts $bench_file "{\"status\":\"pass\",\"cases\":\[[join $bench_results ,]\]}"
    close $bench_file
    puts "PROCESSOR_BENCHMARK_CASE_PASS: $bench_name cycles=$bench_actual_cycles"
}
# PASS is emitted only after all 24 saved logs and input hashes are audited.
puts [exec {*}$bench_cmd]
