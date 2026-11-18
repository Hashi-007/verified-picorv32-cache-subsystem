# Independent instruction and data caches

Validated 18 November 2026. Both cache enable/bypass choices now live inside
`cache_wrapper`. `processor_top` always instantiates that wrapper and passes
`USE_DCACHE` and `USE_ICACHE` through from the testbench. These parameters
select hardware at elaboration time. Defaults remain D-cache enabled,
I-cache disabled, preserving the original processor comparison.

| USE_DCACHE | USE_ICACHE | Configuration |
| ---: | ---: | --- |
| 0 | 0 | Both paths bypass to RAM |
| 1 | 0 | D-cache only |
| 0 | 1 | I-cache only |
| 1 | 1 | Both caches |

Each cache holds 4 KiB, in 256 direct-mapped lines of 16 bytes. The D-cache
uses write-back/write-allocate; the I-cache only reads instructions and has
no dirty bits or writeback. CPU instruction requests select the I-cache
path; CPU loads/stores select the D-cache path. Both share the existing
32-bit RAM port. The CPU holds one native-port request until completion,
so this design does not add parallel instruction/data memory requests.

## Validation

All **52 processor cases pass**: four workloads across all four cache
configurations at RAM waits 1/4/8 (48), plus the smoke program in all four
configurations at wait 1 (4). Every case checks parameter propagation,
completion marker, CPU x3 and result readback. The saved-log audit checks
CPU data-operation totals, D-cache hits/misses, RAM traffic, checker traffic,
source hashes and expected results. The original 24-case comparison was
rerun fresh and preserved every prior cycle count and traffic count.

The original three-read wrapper smoke also passes at 220 ns, with three
CPU completions and five RAM reads. Processor-top compilation/elaboration
passes. Compilers report zero errors/warnings; simulations report zero
errors and only the explained `+acc` debug-visibility warning where used.
The instruction-cache and data-cache core RTL were not changed during this
integration. The earlier standalone I-cache checks additionally cover stalls,
tag replacement, all word offsets and reset after partial refills.

Evidence and reproduction:

- [52-case results with hit rates](results/cache_modes/results.json)
- [52-case metrics CSV](results/cache_modes/metrics.csv)
- [Hit-rate summary CSV](results/cache_modes/hit_rates.csv)
- [Comparison CSV](results/cache_modes/comparisons.csv)
- [Full-matrix runner](../sim/benchmark_cache_modes.do)
- [Saved-log audit](cache_modes.py)
- [Evidence provenance and standalone summaries](results/README.md)

The publication cleanup keeps the original measurements and source RTL intact.
The portable full-matrix runner regenerates all 52 cases and audits their
original cycle, result and traffic baseline into a new local run folder.

## Measured program cycles

Positive percentages mean fewer cycles with both caches than with neither.
All configurations use the same CPU, program images, RAM contents and timing
model. Counts stop at the program's completion-marker store and exclude the
testbench's subsequent result readback.

| Workload | RAM wait | Uncached | D-cache only | I-cache only | Both | Both vs uncached |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| reuse | 1 | 6,947 | 7,001 | 6,992 | 7,046 | -1.43% |
| reuse | 4 | 12,542 | 11,894 | 7,826 | 7,178 | 42.77% |
| reuse | 8 | 20,002 | 18,418 | 8,938 | 7,354 | 63.23% |
| sequential | 1 | 33,331 | 36,229 | 33,376 | 36,274 | -8.83% |
| sequential | 4 | 60,250 | 63,166 | 37,282 | 40,198 | 33.28% |
| sequential | 8 | 96,142 | 99,082 | 42,490 | 45,430 | 52.75% |
| conflict | 1 | 4,267 | 6,589 | 4,303 | 6,625 | -55.26% |
| conflict | 4 | 7,756 | 12,400 | 5,125 | 9,769 | -25.95% |
| conflict | 8 | 12,408 | 20,148 | 6,221 | 13,961 | -12.52% |
| store_heavy | 1 | 6,444 | 6,602 | 6,516 | 6,674 | -3.57% |
| store_heavy | 4 | 11,688 | 11,228 | 7,446 | 6,986 | 40.23% |
| store_heavy | 8 | 18,680 | 17,396 | 8,686 | 7,402 | 60.37% |

## Measured cache hit rates

All 52 cases were rerun with instruction-fetch hit/miss counters and explicit
percentage reporting. The saved-log audit verifies the new counters, unchanged
cycle/traffic totals, source hashes and exclusion of TB readback. These rates
are the same at RAM waits 1/4/8, and the same with or without the other cache
enabled. A bypassed cache has no hit rate and is reported as N/A.

| Workload | I-cache hit % | D-cache hit % (reads + stores) | D-cache read hit % |
| --- | ---: | ---: | ---: |
| reuse | 99.69% | 97.67% | 98.44% |
| sequential | 99.93% | 74.88% | 75.00% |
| conflict | 99.56% | 0.00% | 0.00% |
| store_heavy | 99.46% | 94.96% | 60.00% |

Instruction hit rate is instruction hits divided by completed CPU instruction
requests, including prefetches. Overall data hit rate includes reads and stores;
the read-only column includes reads alone. A four-word refill counts as one
miss for its original CPU request. The sequential test can therefore have 75%
read hits while fetching every input word from RAM once and adding cache
controller overhead. Hit percentage alone does not determine execution time.

The [full-matrix runner](../sim/benchmark_cache_modes.do) and
[audit](cache_modes.py) reproduce these measurements using the current
testbench. Full raw logs and fresh input hashes are written under sim/build/.

## RAM traffic

The I-cache reduces RAM instruction-word reads from 1,607 to 20 in reuse,
7,691 to 20 in sequential, 905 to 16 in conflict, and 1,470 to 32 in
store_heavy. These totals are independent of the RAM wait setting. D-cache
traffic and hit/miss totals retain their previous values in each D-cache mode.

Longer RAM waits make instruction reuse valuable. At wait 1, refill overhead
adds cycles in these workloads. The same-index conflict workload still
thrashes the direct-mapped D-cache; I-cache only is faster than both caches
for that workload. These measurements do not establish a universal speedup.

## Run a configuration

From the `cache_riscv` directory in Questa:

```tcl
do sim/run_processor.do reuse 1 8 1
```

Arguments are `PROGRAM USE_DCACHE RAM_WAIT_CYCLES USE_ICACHE`. The I-cache
argument defaults to 0 for existing commands. Require `PROCESSOR_PROGRAM_PASS`.
See [the PowerShell run guide](../sim/README.md) for VS Code terminal commands.

The original comparison remains `do sim/benchmark_processor.do`, with I-cache
disabled. The current 52-case measurements can be reproduced with
`do sim/benchmark_cache_modes.do`, which runs its saved-log audit automatically.
The committed summaries retain the original measurement provenance.

Program memory stays fixed during execution; this first I-cache version does
not implement FENCE.I or self-modifying code. Cached result/marker stores
may remain dirty at completion; there is no final full-cache drain. This is
simulation evidence, without synthesis, FPGA area, achieved FMax or power
measurements.

The learner developed the I-cache RTL and initial wrapper connections through
review. Mentor contributions here complete the independent bypass switches,
parameter plumbing, runner compatibility, integration checks and reporting.
PicoRV32 remains the pinned third-party CPU IP.
