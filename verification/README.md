# Verification and evidence

The project has three distinct verification layers.

| Layer | Recorded outcome | Main checks |
| --- | --- | --- |
| Standalone D-cache, UVM | 16 passing DUT cases; 3,526 CPU completions; 11,584 RAM transfers | Data, byte masks, hit/miss policy, ordered writeback/refill, stalls and reset |
| Standalone I-cache, directed SV | RAM waits 1/4/8; 96 completed fetches; 174 RAM reads | Cold fills, all word offsets, hits, replacement, stalls and partial-refill reset |
| Integrated processor | 52 passing configurations | Completion marker, CPU x3, result readback, cycles, hit/miss counters and RAM traffic |

The D-cache regression covers **442/442 defined functional bins**. This is
coverage of the stated functional targets, not RTL code coverage or a proof
of exhaustive correctness. The isolated checker fault probe deliberately
produces 20 errors to verify detection; these are separate from positive DUT
tests.

## Read the evidence

- [Four-mode performance and correctness report](CACHE_MODES_REPORT.md)
- [Detailed standalone D-cache report](REPORT.md)
- [Standalone D-cache test plan](TEST_PLAN.md)
- [Curated measured results](results/README.md)
- [Current source fingerprints and cleanup validation](source_manifest.json)
- [Run instructions](../sim/README.md)

## Reproduce

Run from the repository root in Questa:

~~~tcl
do sim/benchmark_cache_modes.do
~~~

Require `CACHE_MODES_BENCHMARK_PASS: configurations=52`. This runs all 52
cases fresh, then audits the saved compile/simulation logs, original expected
results, counter relationships, cycle baselines and input hashes. New output
goes to a timestamped folder under `sim/build/`.

The standalone suites are:

~~~tcl
do sim/run_instruction_cache.do
do sim/regression.do
~~~

The D-cache regression exits Questa after its final audit, so run it in a
separate invocation. It uses the installed precompiled UVM 1.1d library and
matching headers.

The committed summaries document the measured milestones. Full simulator
libraries, waveforms, transcripts and raw run archives are generated locally
and excluded from the source archive.
