# Optional first argument selects the RAM response latency; default is four cycles.
if {[info exists 1]} {
    do sim/run.do cache_wait_test [set 1]
} else {
    do sim/run.do cache_wait_test 4
}
