"""Audit saved Questa logs and independently count required coverage tuples.

Usage: python verification/check_regression.py sim/build/regression_TIMESTAMP
Requires only the Python standard library. Does not accept a simulator exit code
as proof of a pass: checks all 16 logs, totals, errors, coverage and DUT hash.
"""

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DUT_HASH = "8D36B33ADD806779B7F3E0F4EBF40DBA38FC90D3B28648639969B730A3BFDCDE"


def audit(directory):
    expected = {"simulation.log": (61, 56, 5, 20, 8)}
    expected.update({f"cache_wait_test_wait{n}.log": (8, 3, 5, 20, 12) for n in range(1, 9)})
    expected.update(
        {
            "cache_reset_test_wait4.log": (10, 7, 3, 14, 2),
            "cache_stream_test_wait4.log": (301, 30, 271, 1084, 0),
            "cache_reset_sweep_test_wait4.log": (45, 35, 10, 50, 10),
            "cache_reset_sweep_test_random_seed7.log": (45, 35, 10, 50, 10),
        }
    )
    for seed in (1, 7, 23):
        expected[f"cache_random_test_random_seed{seed}.log"] = None
    bins = {
        name: set()
        for name in (
            "kind_hit",
            "indices",
            "words",
            "masks",
            "mask_hit",
            "kind_victim",
            "pairs",
            "ram",
            "reset",
        )
    }
    rows = []
    assert "Errors: 0, Warnings: 0" in (directory / "compile.log").read_text(encoding="utf-8")
    for name, target in expected.items():
        data = (directory / name).read_text(encoding="utf-8", errors="replace")
        for severity in ("UVM_WARNING", "UVM_ERROR", "UVM_FATAL"):
            assert re.search(rf"{severity}\s*:\s*0\b", data), (name, severity)
            assert not re.search(rf"{severity}\s+(?!:)", data), (name, severity)
        assert not re.search(r"\*\*\s+(?:Error|Fatal):", data), name
        warnings = re.findall(r"\*\* Warning: (.*)", data)
        assert all("vopt-10587" in warning for warning in warnings), (name, warnings)
        counts = tuple(
            map(
                int,
                re.search(
                    r"\[CACHE_POLICY\] cpu=(\d+) hits=(\d+) misses=(\d+) ram_reads=(\d+) ram_writes=(\d+)",
                    data,
                ).groups(),
            )
        )
        if target is not None:
            assert counts == target, (name, counts, target)
        else:
            assert counts[0] == 1000 and counts[1] + counts[2] == 1000, (name, counts)
        previous = None
        requests = []
        for line in data.splitlines():
            reset = re.search(r"RESET_COV_OBS phase=(\d+) progress=(\d+)", line)
            if reset:
                phase, progress = map(int, reset.groups())
                bins["reset"].add((phase, progress if phase else 0))
                previous = None
            cpu = re.search(
                r"\[CPU_COV_OBS\] addr=([\da-f]+) strb=([\da-f]) hit=(\d) victim=(\d)", line
            )
            if cpu:
                address, mask = (int(value, 16) for value in cpu.groups()[:2])
                hit, victim = map(int, cpu.groups()[2:])
                kind = int(mask != 0)
                bins["kind_hit"].add((kind, hit))
                bins["indices"].add((address >> 4) & 255)
                bins["words"].add((address >> 2) & 3)
                if mask:
                    bins["masks"].add(mask)
                    bins["mask_hit"].add((mask, hit))
                if not hit:
                    bins["kind_victim"].add((kind, victim))
                current = 2 * kind + hit
                if previous is not None:
                    bins["pairs"].add((previous, current))
                previous = current
                requests.append((address, mask))
            ram = re.search(r"RAM_WAIT_OBS addr=([\da-f]+) strb=([\da-f]) cycles=(\d+)", line)
            if ram:
                address, mask = (int(value, 16) for value in ram.groups()[:2])
                latency = int(ram.group(3))
                assert 1 <= latency <= 8, (name, latency)
                if "_wait" in name or name == "simulation.log":
                    fixed = int(re.search(r"_wait(\d+)", name).group(1)) if "_wait" in name else 1
                    assert latency == fixed, (name, latency, fixed)
                bins["ram"].add((int(mask != 0), (address >> 2) & 3, latency))
        assert len(requests) == counts[0], (name, "CPU observation count")
        assert len(re.findall(r"RAM_WAIT_OBS", data)) == counts[3] + counts[4], name
        continuous = [int(n) for n in re.findall(r"CPU_CONTINUOUS_OBS count=(\d+)", data)]
        if "cache_stream_test" in name or "cache_random_test" in name:
            assert continuous == list(range(1, counts[0])), (name, "driver bubble or duplicate")
        if "cache_stream_test" in name:
            stimulus = [(0x1000 + 16 * i + 4 * (i % 4), 0) for i in range(256)]
            for mask in range(1, 16):
                stimulus += [(0x2000 + 16 * mask, mask)] * 2 + [(0x2000 + 16 * mask, 0)]
            assert requests == stimulus, "Continuous request order differs from stimulus"
        finish = re.search(r"Time:\s+([\d.]+) ns", data)
        rows.append(
            dict(
                log=name,
                cpu=counts[0],
                hits=counts[1],
                misses=counts[2],
                ram_reads=counts[3],
                ram_writes=counts[4],
                continuous=len(continuous),
                finish_ns=float(finish.group(1)),
            )
        )
    targets = dict(
        kind_hit=4,
        indices=256,
        words=4,
        masks=15,
        mask_hit=30,
        kind_victim=6,
        pairs=16,
        ram=64,
        reset=11,
    )
    assert {name: len(values) for name, values in bins.items()} == targets
    native = (directory / "coverage_summary.txt").read_text(encoding="utf-8")
    assert re.search(r"Covergroup Bins\s+442\s+442\s+0\s+1\s+100.00%", native)
    assert hashlib.sha256((ROOT / "rtl/data_cache.sv").read_bytes()).hexdigest().upper() == DUT_HASH
    probe = (directory / "checker_probe.log").read_text(encoding="utf-8", errors="replace")
    assert "CHECKER_NEGATIVE_PASS: 20 expected errors; golden images unchanged" in probe
    assert len(re.findall(r"UVM_ERROR\s+[^:]", probe)) == 20
    assert not re.search(r"\*\*\s+(?:Error|Fatal):|UVM_FATAL\s+[^:]", probe)
    assert "Errors: 0, Warnings: 0" in (directory / "checker_probe_compile.log").read_text(
        encoding="utf-8"
    )
    result = dict(
        status="PASS",
        runs=rows,
        functional_bins="442/442",
        negative_probe="PASS: exactly 20 intended checker errors, no golden-image contamination",
        observed_coverage={
            name: dict(hit=len(bins[name]), target=count) for name, count in targets.items()
        },
        dut_sha256=DUT_HASH,
        total_cpu=sum(row["cpu"] for row in rows),
        total_ram=sum(row["ram_reads"] + row["ram_writes"] for row in rows),
        source_sha256={
            str(file.relative_to(ROOT)): hashlib.sha256(file.read_bytes()).hexdigest()
            for folder in ("rtl", "tb", "sim", "verification")
            for file in (ROOT / folder).glob("*")
            if file.is_file()
        },
    )
    (directory / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(
        f"PASS: {len(rows)} runs, {result['total_cpu']} CPU completions, "
        f"{result['total_ram']} RAM transfers, native functional coverage 442/442"
    )


if __name__ == "__main__":
    audit(Path(sys.argv[1]).resolve())
