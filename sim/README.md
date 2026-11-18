# Running the simulations

Validated with **Questa 2024.1**, Python 3 and the installed precompiled
**UVM 1.1d** library. The processor and standalone I-cache tests use plain
SystemVerilog. Python audits use only the standard library.

Run all commands from the repository root. Put the Questa executable
directory on PATH, or replace `vsim` below with your executable's full path:

~~~powershell
& 'C:/path/to/questa/win64/vsim.exe' -c -do 'do sim/run_processor.do reuse 1 8 1; quit -code 0'
~~~

The scripts discover the running Questa installation. Optional environment
overrides are `QUESTA_HOME` (installation root), `UVM_HOME` (matching UVM
headers' src directory) and `PYTHON` (Python 3.9+ executable).
Otherwise Python is found on PATH.

## Full four-mode processor comparison

~~~powershell
vsim -c -do 'do sim/benchmark_cache_modes.do; quit -code 0'
~~~

This runs **52 fresh cases**: four workloads × four cache configurations ×
RAM waits 1/4/8, plus all four smoke modes at wait 1.
Require:

~~~text
CACHE_MODES_BENCHMARK_PASS: configurations=52
CACHE_MODES_RESULTS_DIR=sim/build/cache_modes_TIMESTAMP
~~~

The PASS line includes the audited checks after the configuration count.
The timestamped folder contains results.json, metrics.csv, hit_rates.csv,
input hashes and every compile/simulation log. The audit checks expected
results, the recorded cycle/traffic baseline, counter relationships and
unchanged run inputs. Errors cause a nonzero batch exit.

To rerun the audit independently:

~~~powershell
python verification/cache_modes.py sim/build/cache_modes_TIMESTAMP
~~~

The committed [result summaries](../verification/results/README.md) are
separate from new local runs.

## One processor program

~~~powershell
vsim -c -do 'do sim/run_processor.do reuse 1 8 1; quit -code 0'
~~~

Arguments: `PROGRAM USE_DCACHE RAM_WAIT_CYCLES USE_ICACHE`.
Defaults: `smoke 1 1 0`. RAM wait is an integer from 1 through 8.
Cache parameters select hardware at elaboration time.

| D-cache | I-cache | Configuration |
| ---: | ---: | --- |
| 0 | 0 | Neither cache |
| 1 | 0 | D-cache only |
| 0 | 1 | I-cache only |
| 1 | 1 | Both caches |

| Program | Expected x3 / result | Result address | Run limit |
| --- | --- | --- | --- |
| smoke | 0x11223345 | 0x1004 | 20 us |
| reuse | 2176 | 0x1100 | 300 us |
| sequential | 819840 | 0x3000 | 2000 us |
| conflict | 384 | 0x3000 | 500 us |
| store_heavy | 256 | 0x3000 | 500 us |

Require `PROCESSOR_PROGRAM_PASS`. For `reuse 1 8 1`, expect **7,354 program
cycles**. Logs and waves are under `sim/build/processor_program/`.
Individual runs overwrite the same configuration's files; the full comparison
archives separate copies.

## Counter definitions

| Label | Meaning |
| --- | --- |
| `CACHE_CONFIG` | Both cache enable parameters |
| `USE_CACHE=... cycles=...` | Historical D-cache mode label and program cycles |
| `RAM_TRAFFIC` | Workload RAM instruction reads, data reads and data writes |
| `CACHE_ACCESS` | D-cache hits and misses, counting original CPU requests |
| `CPU_DATA` | CPU reads/stores and D-cache read hits/misses |
| `ICACHE_ACCESS` | Completed CPU instruction fetches and I-cache hits/misses |
| `ICACHE_HIT_RATE` | Instruction hits / completed CPU instruction fetches |
| `DCACHE_HIT_RATE` | Overall data hit rate and read-only hit rate |
| `CHECKER_READBACK` | Separate final testbench result-read traffic |

Disabled caches report N/A. Four refill words count as one original request's
miss. Instruction fetches include prefetches. Counts end at the CPU completion
store of 1 at `0x10FFC`, before testbench readback. Dirty result/marker lines
may remain cached.

## Standalone instruction cache

~~~powershell
vsim -c -do 'do sim/run_instruction_cache.do; quit -code 0'
~~~

Require `ICACHE_STANDALONE_SUITE_PASS`. Waits 1/4/8 cover cold fills, word
selection, hits, replacement, stalls, reset and partial-refill cancellation.
Output is under `sim/build/instruction_cache/`.

## Standalone data cache: UVM regression

~~~powershell
vsim -c -do 'do sim/regression.do'
~~~

This runner exits Questa after auditing 16 positive DUT cases, the separate
negative checker probe and merged functional coverage. Require the final
audited `PASS` and `REGRESSION_DIR` output. The milestone is 442/442 defined
functional bins; it is not RTL code coverage.

Individual examples:

~~~powershell
vsim -c -do 'do sim/run.do cache_wait_test 4; quit -code 0'
vsim -c -do 'do sim/run.do cache_random_test random 7; quit -code 0'
vsim -c -do 'do sim/run.do cache_reset_sweep_test random 7; quit -code 0'
~~~

`run.do` takes `TEST_NAME {1..8|random} SEED`. See the
[test plan](../verification/TEST_PLAN.md) and
[standalone report](../verification/REPORT.md).

## Supporting checks

~~~powershell
vsim -c -do 'do sim/run_wrapper.do; quit -code 0'
vsim -c -do 'do sim/check_processor_top.do; quit -code 0'
~~~

The wrapper check requires `WRAPPER_SMOKE_PASS cpu=3 ram_reads=5 ram_writes=0`.
The top-level compilation/elaboration check requires `PROCESSOR_TOP_ELAB_PASS`.
The original 24-case, I-cache-disabled benchmark remains available as
`do sim/benchmark_processor.do`.

For waveform inspection, open Questa in the repository root and enter
`do sim/run_processor.do reuse 1 8 1`. GUI runs leave the finished simulation
open. The explained `vopt-10587` warning comes from `+acc` preserving debug
visibility; positive DUT logs must have no functional errors.
