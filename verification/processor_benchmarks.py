"""Plan and audit the fixed PicoRV32/cache comparison. Uses Python's standard library."""

import argparse
import csv
from datetime import date
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "verification/processor_benchmarks.json"
SPEC = json.loads(MANIFEST.read_text(encoding="utf-8"))
INPUTS = [
    "sim/tools.tcl",
    "sim/run_processor.do",
    "tb/processor_tb.sv",
    "tb/wrapper_ram_model.sv",
    "rtl/data_cache.sv",
    "rtl/instruction_cache.sv",
    "rtl/cache_wrapper.sv",
    "rtl/processor_top.sv",
    "sim/benchmark_processor.do",
    "verification/processor_benchmarks.py",
    "third_party/picorv32/picorv32.v",
    "programs/cache_smoke.hex",
    "verification/processor_benchmarks.json",
]
for program in SPEC["profiles"]:
    INPUTS.extend([f"programs/cache_{program}.S", f"programs/cache_{program}.hex"])


def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in INPUTS}


def key(case):
    return case["program"], case["use_cache"], case["ram_wait_cycles"]


def load_seed(path):
    if path is None:
        return [], None
    path = path.resolve()
    seed = json.loads(path.read_text(encoding="utf-8-sig"))
    assert seed["status"] == "pass", "Seed evidence is not passing"
    for name, sha in seed["source_sha256"].items():
        assert (
            hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == sha
        ), f"Stale seed input: {name}"
    cases = [case for case in seed["cases"] if case["program"] in SPEC["profiles"]]
    assert len({key(case) for case in cases}) == len(cases), "Duplicate seed configurations"
    return cases, path.parent


def rows():
    for program, profile in SPEC["profiles"].items():
        for mode in (1, 0):
            for wait in SPEC["waits"]:
                mode_name = "cached" if mode else "uncached"
                yield dict(
                    name=f"{program}_{mode_name}_wait{wait}",
                    program=program,
                    use_cache=mode,
                    ram_wait_cycles=wait,
                    program_cycles=profile["cycles"][f"{mode}/{wait}"],
                    ram_instr_reads=profile["instruction_reads"],
                    ram_data_reads=profile[f"{mode_name}_reads"],
                    ram_data_writes=profile[f"{mode_name}_writes"],
                    cache_hits=profile["hits"] if mode else 0,
                    cache_misses=profile["misses"] if mode else 0,
                    cpu_data_reads=profile["cpu_reads"],
                    cpu_data_stores=profile["cpu_stores"],
                    cache_read_hits=profile["read_hits"] if mode else 0,
                    cache_read_misses=profile["read_misses"] if mode else 0,
                    tb_ram_reads=0 if mode else 1,
                    tb_ram_writes=0,
                )


def audit_case(case, expected, folder, output):
    for field, value in expected.items():
        assert case[field] == value, f'{case["name"]}: {field} expected {value}, got {case[field]}'
    assert case["program_completed"] == case["readback_passed"] == 1, case["name"]
    assert case["post_readback_counters_unchanged"] is True, case["name"]
    name = case["name"]
    sim_log = (folder / f"{name}.log").read_text(encoding="utf-8-sig")
    compile_log = (folder / f"{name}_compile.log").read_text(encoding="utf-8-sig")
    assert re.search(r"Errors:\s*0,\s*Warnings:\s*0", compile_log), name
    assert not re.search(r"\*\*\s+(?:Error|Fatal):", compile_log + sim_log), name
    warnings = re.findall(r"^#?\s*\*\* Warning:.*$", sim_log, re.M)
    assert len(warnings) <= 1 and all("vopt-10587" in item for item in warnings), name
    assert f'USE_CACHE={case["use_cache"]} cycles={case["program_cycles"]}' in sim_log, name
    assert f'CACHE_CONFIG dcache_enabled={case["use_cache"]} icache_enabled=0' in sim_log, name
    assert "Program completed: CPU stored 1 at 0x00010FFC" in sim_log, name
    profile = SPEC["profiles"][case["program"]]
    assert re.search(rf'^#\s+{profile["expected_result"]:08x}\s*$', sim_log, re.M | re.I), name
    for pattern, fields in [
        (
            r"RAM_TRAFFIC instr_reads=(\d+) data_reads=(\d+) data_writes=(\d+)",
            ("ram_instr_reads", "ram_data_reads", "ram_data_writes"),
        ),
        (
            r"CACHE_ACCESS cache_enabled=([01]) hits=(\d+) misses=(\d+)",
            ("use_cache", "cache_hits", "cache_misses"),
        ),
        (
            r"CPU_DATA reads=(\d+) stores=(\d+) read_hits=(\d+) read_misses=(\d+)",
            ("cpu_data_reads", "cpu_data_stores", "cache_read_hits", "cache_read_misses"),
        ),
    ]:
        match = re.search(pattern, sim_log)
        assert match and tuple(map(int, match.groups())) == tuple(
            case[field] for field in fields
        ), name
    readback = re.search(r"CHECKER_READBACK requests=1 ram_reads=(\d+) ram_writes=(\d+)", sim_log)
    assert readback and tuple(map(int, readback.groups())) == (
        case["tb_ram_reads"],
        case["tb_ram_writes"],
    ), name
    assert case["cpu_data_reads"] + case["cpu_data_stores"] == profile["cpu_data_requests"], name
    if case["use_cache"]:
        assert case["cache_hits"] + case["cache_misses"] == profile["cpu_data_requests"], name
        assert case["cache_read_hits"] + case["cache_read_misses"] == case["cpu_data_reads"], name
        assert case["ram_data_reads"] == 4 * case["cache_misses"], name
    for suffix in (".log", "_compile.log"):
        src, dst = folder / f"{name}{suffix}", output / f"{name}{suffix}"
        if src.resolve() != dst.resolve():
            shutil.copy2(src, dst)
    result = {
        **expected,
        "program_completed": 1,
        "readback_passed": 1,
        "post_readback_counters_unchanged": True,
        "cpu_data_requests": profile["cpu_data_requests"],
        "expected_result": profile["expected_result"],
        "result_address": profile["result_address"],
        "compile_errors": 0,
        "compile_warnings": 0,
        "simulation_errors": 0,
        "simulation_warnings": len(warnings),
        "evidence_source": str(folder.relative_to(ROOT)).replace("\\", "/"),
    }
    result["ram_total_words"] = sum(
        result[f"ram_{part}"] for part in ("instr_reads", "data_reads", "data_writes")
    )
    if not case["use_cache"]:
        result.update(
            cache_hits=None,
            cache_misses=None,
            cache_read_hits=None,
            cache_read_misses=None,
            read_hit_rate_percent=None,
            hit_rate_percent=None,
            hit_miss_status="not_applicable_cache_bypassed",
        )
    else:
        result.update(
            hit_rate_percent=round(100 * case["cache_hits"] / profile["cpu_data_requests"], 2),
            read_hit_rate_percent=round(100 * case["cache_read_hits"] / case["cpu_data_reads"], 2),
            hit_miss_status="applicable",
        )
    return result


def write_csv(path, cases, columns):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(cases)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--seed", type=Path)
    args = parser.parse_args()
    output = args.run_dir.resolve()
    seed, seed_dir = load_seed(args.seed)
    seed_map = {key(case): case for case in seed}
    planned = list(rows())
    current_hashes = hashes()
    if args.plan:
        output.mkdir(parents=True, exist_ok=True)
        (output / "input_hashes.json").write_text(json.dumps(current_hashes, indent=2) + "\n")
        fields = tuple(planned[0])
        print(
            " ".join(
                "{" + " ".join(str(row[field]) for field in fields) + "}"
                for row in planned
                if key(row) not in seed_map
            )
        )
        return
    assert (
        json.loads((output / "input_hashes.json").read_text(encoding="utf-8")) == current_hashes
    ), "Inputs changed during run"
    fresh = json.loads((output / "new_results.json").read_text(encoding="utf-8"))
    assert fresh["status"] == "pass"
    fresh_map = {key(case): case for case in fresh["cases"]}
    assert len(fresh_map) == len(fresh["cases"]), "Duplicate new configurations"
    assert not seed_map.keys() & fresh_map.keys(), "Seed/new overlap"
    assert seed_map.keys() | fresh_map.keys() == {
        key(case) for case in planned
    }, "Incomplete 24-case matrix"
    cases = []
    for row in planned:
        reused = key(row) in seed_map
        case = seed_map[key(row)] if reused else fresh_map[key(row)]
        cases.append(audit_case(case, row, seed_dir if reused else output, output))
    comparisons = []
    indexed = {key(case): case for case in cases}
    for program in SPEC["profiles"]:
        for wait in SPEC["waits"]:
            c, u = indexed[program, 1, wait], indexed[program, 0, wait]
            comparisons.append(
                dict(
                    program=program,
                    ram_wait_cycles=wait,
                    cached_cycles=c["program_cycles"],
                    uncached_cycles=u["program_cycles"],
                    cycle_reduction_percent=round(
                        100 * (u["program_cycles"] - c["program_cycles"]) / u["program_cycles"], 2
                    ),
                    speedup=round(u["program_cycles"] / c["program_cycles"], 4),
                )
            )
    result = dict(
        date=str(date.today()),
        status="pass",
        configurations=len(cases),
        reused_cases=len(seed),
        new_cases=len(fresh_map),
        cases=cases,
        comparisons=comparisons,
        source_sha256=current_hashes,
        scope="CPU execution through completion marker, including workload verification and marker; TB readback excluded",
        limitations="Fixed four workloads and RAM model; native functional evidence, no synthesis/FMax or exhaustive correctness claim. No final full-cache drain.",
    )
    (output / "metrics.json").write_text(json.dumps(result, indent=2) + "\n")
    write_csv(
        output / "metrics.csv",
        cases,
        [
            "program",
            "use_cache",
            "ram_wait_cycles",
            "program_cycles",
            "cpu_data_requests",
            "cpu_data_reads",
            "cpu_data_stores",
            "cache_read_hits",
            "cache_read_misses",
            "read_hit_rate_percent",
            "cache_hits",
            "cache_misses",
            "hit_rate_percent",
            "hit_miss_status",
            "ram_instr_reads",
            "ram_data_reads",
            "ram_data_writes",
            "ram_total_words",
            "tb_ram_reads",
            "tb_ram_writes",
            "expected_result",
        ],
    )
    write_csv(output / "comparisons.csv", comparisons, list(comparisons[0]))
    table = [
        "| Workload | RAM wait | Cached cycles | Uncached cycles | Cycle reduction |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for row in comparisons:
        table.append(
            f'| {row["program"]} | {row["ram_wait_cycles"]} | {row["cached_cycles"]:,} | '
            f'{row["uncached_cycles"]:,} | {row["cycle_reduction_percent"]:.2f}% |'
        )
    (output / "tables.md").write_text("\n".join(table) + "\n")
    print(
        f"PROCESSOR_BENCHMARK_PASS: configurations={len(cases)} reused={len(seed)} new={len(fresh_map)}"
    )
    print(f"PROCESSOR_METRICS_DIR={output}")


if __name__ == "__main__":
    main()
