# Standalone cache verification report

**Result: PASS — ready for PicoRV32 integration.** 2026-11-13.

The standalone milestone in SPEC.md is complete for the defined functional
test plan. All 16 DUT runs pass, totaling **3,526 CPU completions** and
**11,584 RAM transfers**, with zero UVM errors/fatals or assertion failures.
The three random seeds each complete 1,000 requests. Merged native Questa
coverage hits **442/442 defined functional bins (100%)**. These results describe the standalone D-cache milestone; integrated
processor measurements are reported separately.

## Configuration and reproduction

Questa 2024.1, precompiled UVM 1.1d and matching headers; one 10 ns clock.
The DUT is the existing 4 KiB direct-mapped, blocking, write-back/write-allocate
cache. No cache RTL changed during this verification batch. Its SHA256 is:

```text
F36382F54A76FA742E8D66DFF655E9A2901C24A7864040F04E7AD4E1E8550277
```

From the VS Code PowerShell terminal:

```powershell
# Run from the repository root, with Questa on PATH.
vsim -c -do 'quit -sim; do sim/regression.do'
```

The runner compiles once, executes all cases, runs an isolated checker fault
probe, merges native UCDBs, writes coverage reports and audits the logs with
verification/check_regression.py. It prints PASS only after the audit succeeds.
Python 3.9+ is required; the runner uses PYTHON when set, then Python on PATH. The final console line identifies the new
result folder under sim/build/regression_TIMESTAMP/.

The saved passing run is **sim/build/regression_20261113_204757/**:

- compile.log; one log and native UCDB per DUT run.
- merged.ucdb, coverage_summary.txt and coverage_details.txt.
- checker_probe.log and checker_probe_compile.log.
- results.json: counts, coverage tuple totals and SHA256 source manifest.

The complete launcher transcript is sim/build/final_regression_console.log.
The ordinary run.do command and original fixed-delay tests remain available.

## Test results

| Test | Runs | CPU completions per run | Checks |
| --- | ---: | ---: | --- |
| Original cache_test, RAM wait 1 | 1 | 61 | Reads, stores, masks, clean/dirty conflicts, retained data |
| cache_wait_test, fixed waits 1–8 | 8 | 8 | Exact observed latency, stalled fields/counter, ordered RAM traffic |
| Original cache_reset_test, wait 4 | 1 | 10 | Existing idle/refill/writeback reset examples |
| cache_stream_test, wait 4 | 1 | 301 | Every index; every mask on hit/miss; 300 immediate replacements |
| cache_reset_sweep_test, wait 4 and random seed 7 | 2 | 45 | Refill/WB reset after 0–4 completed words; retained prefix; canceled CPU requests |
| cache_random_test, seeds 1/7/23 | 3 | 1,000 | Constrained legal traffic, locality/conflicts, random per-transfer RAM waits |

Random requests balance read/store selection and mix same-line reuse (40%),
same-index conflicts (30%) and whole-region traffic (30%). These are selection
weights, not promises about the observed hit rate. Every request randomizes
data and strobes. RAM independently selects one wait from 1–8 at each new
transfer and holds that choice through the stall.

Streaming mode makes the next item available at the first falling edge after
completion. Independent rising-edge observation confirms a request is present
on the next edge: 300/300 boundaries in the directed stream and 999/999 per
random seed. The cache still takes its own IDLE/LOOKUP cycles. The Python audit
also checks the complete directed stream address/strobe order and totals.

## Independent checking

CPU and RAM monitors observe only completed rising-edge handshakes. The byte
scoreboard checks CPU loads/stores against architectural memory, checks RAM
reads against a separate golden RAM image and checks writeback bytes before
committing their expected values to that image. Reset restores architectural
expectations from retained RAM, permitting cache-only dirty data to be lost.

The policy checker independently predicts resident lines and dirty victims
from completed CPU requests. It checks RAM count, address, direction and word
order; a hit must have no RAM traffic. On reset it also checks the observed
prefix of an aborted miss before clearing pending traffic and metadata.
Neither data oracle uses DUT data/tag arrays or the controller state.

Field guards reject unknown, misaligned or out-of-range addresses, unknown
strobes/results/enabled write bytes, and partial RAM-write strobes before
checker array access. Six concurrent assertions check CPU/RAM stability,
counter hold, known controls, legal CPU completion and reset outputs. A
separate clock observer measures actual RAM latency. Requests have a 100-cycle
driver timeout; the whole test has a 2 ms watchdog.

## Coverage closure

| Independently observed target | Hit / target |
| --- | ---: |
| Read/store × hit/miss | 4 / 4 |
| Cache index | 256 / 256 |
| CPU word offset | 4 / 4 |
| Nonzero CPU store mask | 15 / 15 |
| Store mask × hit/miss | 30 / 30 |
| Read/store miss × invalid/clean/dirty victim | 6 / 6 |
| Adjacent request classes (read/store × hit/miss) | 16 / 16 |
| RAM direction × word offset × observed wait | 64 / 64 |
| Reset idle plus refill/WB × completed words 0–4 | 11 / 11 |

The Python audit counts these tuples from saved observations separately from
the SystemVerilog covergroups. Native UCDB reports additionally include their
component coverpoints: four covergroups, 19 coverpoints/crosses, 442 hit bins,
zero missed bins. Reset progress four means reset after the final RAM word and
before CPU completion; it is a phase boundary, not a partial line.

Coverage is functional coverage of these defined targets. RTL code coverage,
all combinations of index/tag/data/mask/reset timing, misaligned CPU accesses,
out-of-map requests as supported operations, multiclock behavior, associativity,
flush and processor integration are outside this milestone. Startup reset is
checked but excluded from operational reset coverage. Idle reset progress is
undefined and its cross bins are explicitly ignored. Illegal fields are tested
against checker guards, rather than added as supported cache transactions.

## Fault detection and debug evidence

The isolated cache_checker_probe injects eight malformed CPU observations,
nine malformed RAM observations, one wrong CPU read, one wrong RAM read and
one corrupt RAM writeback. It produces exactly 20 intended UVM errors with
the required IDs, no fatal/simulator error, and leaves both golden images
unchanged. These expected errors occur only in checker_probe.log; the 16
positive DUT logs have zero errors. Previous isolated stability/policy fault
probes remain documented in TEST_PLAN.md and their saved evidence folders.

The first new probe elaboration lacked a static cache_if instance required by
Questa to resolve the package's virtual-interface types. Adding that instance
fixed the harness; this was not a DUT failure. The initial diagnostic is
preserved in sim/build/regression_20261113_204218/
checker_probe_initial_elaboration_error.log. Final probe compile/runtime pass.
The initial +acc optimizer warning vopt-10587 is expected for waveform access;
no unexplained simulator warnings remain. An exploratory -coverage run also
requested uninstrumented code coverage; that option was removed because these
reports use native functional covergroups, which are collected by default.

## Processor integration

The verified standalone cache is integrated with the third-party PicoRV32
RV32I CPU. See the [project overview](../README.md) and
[cache configuration report](CACHE_MODES_REPORT.md) for the completed
integration and workload comparisons at RAM waits of 1, 4 and 8 cycles.
