"""Audit the fixed 52-case processor matrix using saved logs and input hashes."""

import argparse
from datetime import datetime, timezone
import csv
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "folder", type=Path, help="Result folder, relative to the repository root or absolute"
)
parser.add_argument("--prepare", action="store_true", help="Snapshot inputs before simulation")
args = parser.parse_args()
build = args.folder if args.folder.is_absolute() else root / args.folder
if args.prepare:
    build.mkdir(parents=True, exist_ok=False)
    inputs = [
        "sim/tools.tcl",
        "sim/run_processor.do",
        "sim/benchmark_cache_modes.do",
        "verification/cache_modes.py",
        "verification/results/cache_modes/results.json",
        "third_party/picorv32/picorv32.v",
        "tb/processor_tb.sv",
        "tb/wrapper_ram_model.sv",
    ]
    inputs += [p.relative_to(root).as_posix() for p in sorted((root / "rtl").glob("*.sv"))]
    inputs += [
        p.relative_to(root).as_posix()
        for p in sorted((root / "programs").glob("cache_*"))
        if p.suffix in {".S", ".hex"}
    ]
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in inputs}
    (build / "input_hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    print("CACHE_MODES_INPUTS_SAVED:", build.relative_to(root))
    raise SystemExit(0)
golden = json.loads(
    (root / "verification/results/cache_modes/results.json").read_text(encoding="utf-8")
)
hashes = json.loads((build / "input_hashes.json").read_text(encoding="utf-8-sig"))
for name, expected in hashes.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name


def key(c):
    return c["program"], c["use_dcache"], c["use_icache"], c["ram_wait_cycles"]


previous = {key(c): c for c in golden["cases"]}
fresh = json.loads((build / "new_results.json").read_text(encoding="utf-8"))["cases"]
assert len(fresh) == len(previous) == 52 and {key(c) for c in fresh} == set(previous)
cases = []
for raw in fresh:
    old = previous[key(raw)]
    name = (
        f'{raw["program"]}_d{raw["use_dcache"]}_i{raw["use_icache"]}_wait{raw["ram_wait_cycles"]}'
    )
    log = (build / f"{name}.log").read_text(encoding="utf-8-sig")
    compile_log = (build / f"{name}_compile.log").read_text(encoding="utf-8-sig")
    assert "Errors: 0, Warnings: 0" in compile_log, name
    assert not re.search(r"\*\* (?:Error|Fatal)", log + compile_log), name
    warnings = re.findall(r"^#?\s*\*\* Warning:.*$", log, re.M)
    assert len(warnings) <= 1 and all("vopt-10587" in warning for warning in warnings), name
    for field in (
        "program_cycles",
        "cpu_data_reads",
        "cpu_data_stores",
        "ram_instr_reads",
        "ram_data_reads",
        "ram_data_writes",
        "cache_hits",
        "cache_misses",
        "cache_read_hits",
        "cache_read_misses",
        "tb_ram_reads",
        "tb_ram_writes",
    ):
        assert raw[field] == (old[field] or 0), (name, field, raw[field], old[field])
    assert raw["program_completed"] == raw["readback_passed"] == 1, name
    assert raw["request_had_refill"] == raw["instr_request_had_refill"] == 0, name
    assert (
        f'CACHE_CONFIG dcache_enabled={raw["use_dcache"]} icache_enabled={raw["use_icache"]}' in log
    )
    assert f'USE_CACHE={raw["use_dcache"]} cycles={raw["program_cycles"]}' in log
    assert re.search(rf'^#\s+{old["expected_result"]:08x}\s*$', log, re.M | re.I), name
    match = re.search(
        r"ICACHE_ACCESS cache_enabled=([01]) fetches=(\d+) hits=(\d+) misses=(\d+)", log
    )
    assert match and tuple(map(int, match.groups())) == tuple(
        raw[f] for f in ("use_icache", "cpu_instr_fetches", "icache_hits", "icache_misses")
    ), name
    # For this fixed program, completed CPU fetches match the uncached trace.
    uncached = previous[raw["program"], 0, 0, raw["ram_wait_cycles"]]
    assert raw["cpu_instr_fetches"] == uncached["ram_instr_reads"], name
    if raw["use_icache"]:
        assert raw["icache_hits"] + raw["icache_misses"] == raw["cpu_instr_fetches"], name
        assert 4 * raw["icache_misses"] == raw["ram_instr_reads"], name
        i_percent = round(100 * raw["icache_hits"] / raw["cpu_instr_fetches"], 2)
        assert f"ICACHE_HIT_RATE percent={i_percent:.2f}" in log, name
    else:
        assert raw["icache_hits"] == raw["icache_misses"] == 0, name
        assert "ICACHE_HIT_RATE percent=N/A" in log, name
        i_percent = None
    if raw["use_dcache"]:
        d_percent = round(
            100 * raw["cache_hits"] / (raw["cpu_data_reads"] + raw["cpu_data_stores"]), 2
        )
        read_percent = round(100 * raw["cache_read_hits"] / raw["cpu_data_reads"], 2)
        assert (
            f"DCACHE_HIT_RATE all_percent={d_percent:.2f} read_percent={read_percent:.2f}" in log
        ), name
    else:
        d_percent = read_percent = None
        assert "DCACHE_HIT_RATE all_percent=N/A read_percent=N/A" in log, name
    case = dict(
        raw,
        icache_hit_rate_percent=i_percent,
        dcache_hit_rate_percent=d_percent,
        dcache_read_hit_rate_percent=read_percent,
        expected_result=old["expected_result"],
        simulation_log=(build / f"{name}.log").relative_to(root).as_posix(),
    )
    if not raw["use_icache"]:
        case["icache_hits"] = case["icache_misses"] = None
    if not raw["use_dcache"]:
        for field in ("cache_hits", "cache_misses", "cache_read_hits", "cache_read_misses"):
            case[field] = None
    cases.append(case)

summary = []
for program in ("reuse", "sequential", "conflict", "store_heavy"):
    selected = [c for c in cases if c["program"] == program]
    for field, flag in (
        ("icache_hit_rate_percent", "use_icache"),
        ("dcache_hit_rate_percent", "use_dcache"),
        ("dcache_read_hit_rate_percent", "use_dcache"),
    ):
        assert len({c[field] for c in selected if c[flag]}) == 1, (program, field)
    both = next(
        c for c in selected if c["use_dcache"] and c["use_icache"] and c["ram_wait_cycles"] == 8
    )
    summary.append(
        {
            field: both[field]
            for field in (
                "program",
                "cpu_instr_fetches",
                "icache_hits",
                "icache_misses",
                "icache_hit_rate_percent",
                "cache_hits",
                "cache_misses",
                "dcache_hit_rate_percent",
                "cache_read_hits",
                "cache_read_misses",
                "dcache_read_hit_rate_percent",
            )
        }
    )
result = dict(
    date=datetime.now(timezone.utc).date().isoformat(),
    status="pass",
    configurations=52,
    cases=cases,
    hit_rate_summary=summary,
    comparisons=golden["comparisons"],
    source_sha256=hashes,
    scope="Accepted CPU requests through completion marker; TB checker traffic excluded. Instruction fetches include prefetches.",
    definitions={
        "instruction": "icache_hits / cpu_instr_fetches",
        "data_all": "cache_hits / (cpu_data_reads + cpu_data_stores)",
        "data_reads": "cache_read_hits / cpu_data_reads",
        "bypass": "null (N/A); no cache accesses",
    },
)
(build / "results.json").write_text(json.dumps(result, indent=2) + "\n")
for filename, rows in (("metrics.csv", cases), ("hit_rates.csv", summary)):
    with (build / filename).open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
table = [
    "| Workload | I-cache hit % | D-cache hit % (reads + stores) | D-cache read hit % |",
    "| --- | ---: | ---: | ---: |",
]
for row in summary:
    table.append(
        f'| {row["program"]} | {row["icache_hit_rate_percent"]:.2f}% | '
        f'{row["dcache_hit_rate_percent"]:.2f}% | {row["dcache_read_hit_rate_percent"]:.2f}% |'
    )
(build / "hit_rates.md").write_text("\n".join(table) + "\n")
print(
    "CACHE_MODES_BENCHMARK_PASS: configurations=52; cycles, results, traffic, hit rates and input hashes verified"
)
print("\n".join(table))
