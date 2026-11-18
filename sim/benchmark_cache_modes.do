# Run and audit all four cache modes: 48 workload cases plus four smoke cases.
onerror {quit -code 1 -force}
source sim/tools.tcl
set rates_build [file join sim build cache_modes_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
set rates_cmd [list {*}[cache_tools::python] verification/cache_modes.py $rates_build]
puts [exec {*}$rates_cmd --prepare]
set rates_plan {}
foreach rates_program {smoke reuse sequential conflict store_heavy} {
    if {$rates_program eq "smoke"} {
        set rates_waits {1}
    } else {
        set rates_waits {1 4 8}
    }
    foreach rates_d {0 1} {
        foreach rates_i {0 1} {
            foreach rates_wait $rates_waits {
                lappend rates_plan [list $rates_program $rates_d $rates_wait $rates_i]
            }
        }
    }
}
set rates_results {}
foreach rates_case $rates_plan {
    lassign $rates_case rates_program rates_d rates_wait rates_i
    do sim/run_processor.do $rates_program $rates_d $rates_wait $rates_i
    set rates_values [list [format {"program":"%s","use_dcache":%d,"use_icache":%d,"ram_wait_cycles":%d} \
        $rates_program $rates_d $rates_i $rates_wait]]
    foreach rates_field {ram_instr_reads ram_data_reads ram_data_writes cache_hits cache_misses \
            cpu_data_reads cpu_data_stores cache_read_hits cache_read_misses tb_ram_reads tb_ram_writes \
            cpu_instr_fetches icache_hits icache_misses program_completed readback_passed \
            request_had_refill instr_request_had_refill} {
        set rates_value [string trim [examine -radix unsigned sim:/processor_tb/$rates_field]]
        if {![string is integer -strict $rates_value]} {
            error "Unknown $rates_field"
        }
        lappend rates_values "\"$rates_field\":$rates_value"
    }
    quit -sim
    set rates_name "${rates_program}_d${rates_d}_i${rates_i}_wait${rates_wait}"
    set rates_log [file join $rates_build "${rates_name}.log"]
    file copy -force $processor_sim_log $rates_log
    file copy -force [file join $processor_build compile.log] [file join $rates_build "${rates_name}_compile.log"]
    set rates_file [open $rates_log r]
    set rates_text [read $rates_file]
    close $rates_file
    if {![regexp {USE_CACHE=[01] cycles=([0-9]+)} $rates_text unused rates_cycles]} {
        error "Missing cycle count: $rates_name"
    }
    lappend rates_values "\"program_cycles\":$rates_cycles"
    lappend rates_results "{[join $rates_values ,]}"
    set rates_file [open [file join $rates_build new_results.json] w]
    puts $rates_file "{\"cases\":\[[join $rates_results ,]\]}"
    close $rates_file
    puts "CACHE_HIT_RATE_CASE_PASS: $rates_name cycles=$rates_cycles"
}
puts {CACHE_HIT_RATE_MATRIX_PASS: 52 cases}

puts [exec {*}$rates_cmd]
puts "CACHE_MODES_RESULTS_DIR=$rates_build"
