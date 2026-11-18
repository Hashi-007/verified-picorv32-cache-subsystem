# Standalone cache verification map

Status: STANDALONE MILESTONE PASS (2026-11-13). See REPORT.md for the
current complete result and coverage scope; earlier incremental notes below
are historical and their pending-work statements are superseded.
All C01-C10 targets below have passing runtime evidence: 16 DUT runs,
three random seeds x 1,000 requests, 3,526 total CPU completions,
11,584 RAM transfers, 442/442 defined native functional bins, zero positive
checker/assertion errors. Final evidence: sim/build/regression_20261113_204757/.
The separate checker fault probe detects exactly 20 intended errors.
Continuous request boundaries, random 1-8 waits and reset progress 0-4 in
both refill/writeback are now covered. Field guards and canceled-miss RAM
prefix checks are active. PicoRV32 integration is next.

## Earlier incremental evidence and original test mapping

Earlier status: DIRECTED FUNCTIONAL/POLICY AND THREE RESET PHASE CASES PASS.
Project sequence has 61 CPU completions, 56 hits/5 misses, 20 RAM reads and
8 writes, covering cold/repeated reads, masked store miss, all 15 store
masks and dirty-victim read/store misses with retained old-data readback.
The connected RAM policy subscriber checks count/address/strobes per CPU
request. Temporary helper validation also checks dirty/clean eviction and
reload. A separate wait test now passes fixed RAM latencies 1-8 with
request/counter stability assertions. Idle/partial-refill/dirty-writeback
reset cases pass, including retained completed RAM writes and CPU-image
reset reconciliation. Direct RAM-read comparisons are enabled and pass.
Full suite completion is not claimed; field guards, per-transfer random delays, random regression,
back-to-back traffic and coverage are pending.
Recorded 2026-11-10 from SPEC.md and the original project map, page 12,
to trace requirements to checks and coverage targets.

| ID | Requirement / stimulus | Independent check | Coverage target |
| --- | --- | --- | --- |
| C01 | Cold read, repeat read, all four word offsets | Correct returned word; first access refills four words, repeats hit | Read miss/hit; offsets 0-3 |
| C02 | Clean same-index conflict | Correct new block, no unnecessary writeback | Distinct tags at same index; clean eviction |
| C03 | Dirty conflict and reread, for both read and store misses | Old victim addresses/data written before new refill; reread returns modified contents | Dirty eviction crossed with read/store miss |
| C04 | Store hit | Architectural masked-store update; no immediate RAM write | Store hit; deferred writeback |
| C05 | Store miss | Full refill before applying pending store; untouched bytes preserved | Store miss; write allocation |
| C06 | All 15 nonzero CPU byte masks | Only enabled bytes change in independent architectural memory | Every nonzero mask; byte preservation |
| C07 | Consecutive CPU requests | Exactly one completion per request, correct ordering and data | Read/store sequences; hit/miss transitions |
| C08 | RAM waits during writeback and refill | Stable stalled fields/counter; four completed words per phase | Wait values 1-8; both phases; word offsets |
| C09 | Reset idle / partial refill / partial writeback | Invalidate/cancel, retain already completed RAM writes, no stale completion | Reset phase; partial progress |
| C10 | Constrained-random legal traffic | Independent data scoreboard plus separate RAM policy checks | Reads/stores, hits/misses, indices, offsets, masks, waits and reset phases |

Use an independent architectural byte memory for completed CPU loads/stores.
Separately check RAM traffic and retain an independently checked RAM image.
Reset can discard dirty cached data; reconcile expected post-reset contents
with that retained RAM image rather than keeping every prior CPU store.

Use two passive observation points, sampling rising-edge completions while
rst_n is high. The CPU-side cache_monitor records cpu_valid && cpu_ready,
including address, strobes and write/read data, for architectural checking.
A separate RAM-side monitor records mem_valid && mem_ready and the mem_*
fields for refill/writeback policy and retained-memory checking. The RAM
response model drives replies; its behavior is checked through observation.
Do not pair CPU/RAM transactions 1:1: a hit has no RAM transfer, while a miss
refills four words and may first write back four dirty victim words.

Regression: seeds 1, 7 and 23, each with 1,000 completed CPU requests and RAM
waits of 1-8 cycles. Add bounded timeouts and assertions for stalled request
stability, legal completion and reset cancellation. Define justified coverage
exclusions and save test commands, seeds, logs and coverage evidence.

Pass criteria remain SPEC.md: required directed cases and three seeds pass,
zero checker/assertion errors, zero unexplained simulator/UVM errors, required
coverage evidence, and an explained debugged bug or checker-negative case.
The initial RTL draft now has the directed runtime evidence below; these
smokes do not establish the complete regression or coverage criteria.

UVM environment responsibilities are described in the original project map,
page 11. The signal interface, testbench top and fixed-one-cycle RAM model
were connected on 2026-11-11. All four sources compile, elaborate and pass
the bounded clock/reset smoke. Top no longer drives RAM responses or CPU
request fields. The UVM package, environment and test are integrated through
config_db/run_test. The driver read/write helpers include read-return support.

2026-11-12 runtime evidence (Questa/UVM 1.1d, fixed one-cycle RAM):
- Eight-read project sequence: 350 ns, 8 CPU completions, 4 RAM reads,
  0 writes; data 0/1/2/3 on both passes. Exercises the C01 basic case.
- Temporary helper test: 580 ns, 7 CPU completions, 12 RAM reads and 4
  RAM writes. Checks full store and mask 0010 preservation, dirty conflict,
  clean replacement on return, retained readback and helper output values.
  Provides initial directed evidence for portions of C02/C03/C04/C06.
- Temporary negative test: 350 ns, one deliberately corrupted expected byte
  produces exactly 2 DATA_MISMATCH reports; no unexplained UVM failures.
- Extended project sequence: 590 ns, 13 CPU completions, 8 RAM reads and
  0 RAM writes. Store miss at 0x1014 (AABBCCDD, mask 0010) refills 0x1010
  through 0x101C before CPU store completion. Readback is 0000CC05 and the
  other words remain 4/6/7. This exercises the C05 initial invalid-victim
  masked-store case. Combined event-order/data audit passes, with zero
  UVM errors/fatals. Evidence: tmp/cache_checks/cache_store_miss_20261112/
  compile.log, simulation.log, results.json and check_store_miss.py.
- All-mask extension plus connected project RAM checker: 2030 ns, 58 CPU
  completions, 55 hits/3 misses, 12 RAM reads and 0 writes. All 15 store
  masks have correct readback with nonzero disabled bytes. Checks C06's
  mask values on hits. Policy checker predicts hit/miss independently from
  completed CPU requests and verifies RAM count/address/strobe ordering.
  Existing helper test also passes its dirty/clean-conflict paths (7 CPU
  completions, 4 hits/3 misses, 12 reads/4 writes). Negative extra-on-hit
  and incorrect-writeback-address observations each produce exactly one
  intended policy error. Four logs pass independent combined-event/data/
  report checks in tmp/cache_checks/cache_masks_ram_policy_20261112/.
- Dirty-store extension after correcting the read-output argument:
  2460 ns, 61 CPU completions, 56 hits/5 misses, 20 RAM reads/8 writes.
  Full store to 0x2014 evicts dirty 0x1010; readback returns DEADBEEF.
  Reload of 0x1014 evicts dirty 0x2010 and returns retained 0000CC05.
  All 89 combined CPU/RAM events pass independent address/strobe/data/
  ordering checks, with 0 UVM warnings/errors/fatals. Provides C03's
  dirty read/store-miss evidence. Compile has 0 errors/0 warnings; simulator
  +acc warning is explained. Evidence: tmp/cache_checks/
  cache_dirty_store_20261112/{compile.log,simulation.log,results.json,
  check_dirty_store.py}; the pre-edit source is archived locally in reference/.
- Separate cache_wait_sequence/cache_wait_test: 8 CPU requests, 3 hits/
  5 misses, 20 RAM reads/12 writes at every fixed latency from 1 through 8.
  Finish times are 950/1270/1590/1910/2230/2550/2870/3190 ns respectively.
  Independent clock sampling validates all 32 RAM latencies and address/
  strobe ordering per run. All 64 delay x direction x word-offset tuples
  are observed across runs, supplying C08 directed evidence. Concurrent
  assertions check stalled CPU/RAM fields and internal word-counter hold;
  three isolated negative probes each trigger exactly the intended error.
  Positive runs have zero assertion/UVM errors; original directed test
  still passes at 2460 ns. Compile 0 errors/0 warnings, initial +acc warning
  explained. Evidence: tmp/cache_checks/cache_wait_test_20261112/ logs,
  assertions/, check_wait_logs.py and results.json. This establishes the
  directed wait cases; overall coverage closure is recorded above.
- First partial-refill reset at fixed RAM wait 4: 410 ns, one CPU completion,
  zero hits/one miss, six RAM reads/zero writes. Reads 1000/1004 complete
  before reset; reset is low 150-170 ns and sampled at 155/165 ns. The retry
  refills all four words from 1000 again and completes at 405 ns with data
  zero. Independent pre-edge VCD audit checks transfer times/address/data,
  reset controls/state/counter, and absence of a canceled CPU completion.
  Original test still passes 2460 ns. Compile 0 errors/0 warnings, positive
  UVM/assertion errors zero; initial +acc optimizer warning explained.
  Evidence: tmp/cache_checks/cache_reset_refill_20261112/ logs, VCD,
  check_reset_trace.py/results.json. Supplies partial C09 evidence only;
  idle reset, dirty-writeback reset and retained-RAM data remain pending.
- Combined partial-refill/dirty-writeback reset at fixed wait 4 passes
  1010 ns: CPU=9, hits=7, misses=2, RAM reads=10, writes=2. Four CPU stores
  change the line to A1/B2/C3/D4; only WB A1/B2 complete before reset
  660-680 ns. Post-reset CPU reads return A1/B2/2/3. Scoreboard checks
  completed RAM write bytes against architectural CPU memory, updates its
  golden RAM image, and restores CPU expected memory from it on sampled
  reset. Independent pre-edge VCD audit checks all 21 completed CPU/RAM
  events, data/address/strobes/order/times, reset controls/state/counter
  and absence of canceled CPU completions or remaining WB commits.
  Original test also passes 2460 ns. Final compile 0 errors/0 warnings;
  positive UVM/assertion errors zero, expected +acc warning explained.
  Initial misplaced-env-task compile error is preserved and resolved.
  Evidence: tmp/cache_checks/cache_reset_writeback_20261113/ logs, VCD,
  check_reset_trace.py/results.json. C09 idle reset remains open, along
  with further reset progress points and direct RAM read-data checks.
- Idle-reset extension at fixed wait 4 passes with the preceding refill/WB
  scenarios: 1280 ns, CPU=10, hits=7, misses=3, RAM reads=14, writes=2.
  Before idle reset the DUT is IDLE and CPU/RAM requests are low. Reset
  1020-1040 ns invalidates the resident clean line; read 1000 then refills
  four words at 1115/1165/1215/1265 ns and completes at CPU 1275 ns with
  A1, with no new writeback. Independent VCD audit checks all 26 transfers
  plus reset controls/state/counter/cancellation. Compile 0 errors/0 warnings,
  UVM/assertion errors zero, expected +acc warning explained. Evidence:
  tmp/cache_checks/cache_reset_idle_20261113/ logs, VCD, validator/results.
  This covers the three directed phase examples; broader progress-point
  crosses and full verification closure remain pending.
- Direct RAM-read comparison enabled, with syntax and diagnostic fixes.
  Original test passes 2460 ns
  (20 RAM reads); three-phase reset test passes 1280 ns at wait 4 (14 RAM
  reads), including retained data. Both final compiles 0 errors/0 warnings,
  zero positive UVM/assertion errors. Expected initial +acc warning explained.
  Evidence: tmp/cache_checks/cache_ram_read_20261113/ logs/results.json.
  No new mismatch-path fault probe or broader sweep for these two fixes.
- Independent fixed-trace audit checks all CPU/RAM addresses, masks, data
  and counts, and Python verifies the logs/reports. Evidence is under
  tmp/cache_checks/cache_uvm_integrated_20261112/, including results.json,
  compile.log, three simulation logs and validation sources. Compile has
  0 errors/0 warnings. Initial runtime +acc optimization warning and inline
  onerror usage notice are explained; subsequent runs use run.do.

The project RAM-monitor subscriber now checks normal-traffic policy and
reports hit/miss counts. Architectural CPU data stays in its separate model;
the subscriber now clears policy metadata/pending observations on sampled
reset. Driver cancels active requests and gates new launches during reset.
Idle, partial-refill and dirty-writeback reset cases pass. A separate scoreboard
RAM input checks read/write data, maintains golden retained contents and restores
CPU expected memory on sampled reset. Further progress points,
input field guards, per-transfer randomized waits, further
protocol/reset assertions, back-to-back traffic, randomized regression and
coverage are still required before suite completion.
