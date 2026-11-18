# Curated measured results

These files preserve the measured simulation milestones. They are small,
reviewable exports; generated libraries, waves and complete raw log archives
remain local. New runs do not overwrite these committed summaries.

| Folder | Recorded milestone |
| --- | --- |
| [cache_modes/](cache_modes/results.json) | 18 Nov 2026: all 52 processor configurations and hit-rate measurements |
| [dcache/](dcache/results.json) | 13 Nov 2026: 16 standalone UVM cases, 442/442 defined functional bins |
| [icache/](icache/results.json) | 18 Nov 2026: standalone I-cache directed checks at RAM waits 1/4/8 |

Processor exports:

- [Full JSON](cache_modes/results.json)
- [Per-configuration CSV](cache_modes/metrics.csv)
- [Hit-rate CSV](cache_modes/hit_rates.csv)
- [Configuration comparison CSV](cache_modes/comparisons.csv)

D-cache exports include the native [coverage summary](dcache/coverage_summary.txt)
and [coverage details](dcache/coverage_details.txt).

Source hashes and local log paths inside the dated exports describe those
recorded runs. Some refer to pre-publication runners or local build folders;
they are historical provenance, not a claim that those generated folders are
committed. The subsequent source cleanup changes comments, formatting and line endings
while preserving all SystemVerilog executable tokens and assembly operations.
Python scripts use explicit UTF-8 text reads. The
[current release manifest](../source_manifest.json) records the cleaned source
hashes and rerun validation. Original dated exports remain intact.
The portable runner reproduces the same 52-case cycle, result and traffic
baseline, writing a fresh input manifest and full logs:

~~~tcl
do sim/benchmark_cache_modes.do
~~~

See [the run guide](../../sim/README.md) and
[the full report](../CACHE_MODES_REPORT.md). Bypassed-cache hit rates are
null/N/A. Instruction counts include accepted prefetches, not just retired
instructions. Measurements exclude final checker readback and dirty-line drain.
