"""Check and package the portfolio source without generated or learning files."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOP = {
    ".editorconfig",
    ".gitattributes",
    ".gitignore",
    "README.md",
    "SPEC.md",
    "ARCHITECTURE.md",
    "ATTRIBUTION.md",
}
VERIFY = {
    "README.md",
    "REPORT.md",
    "CACHE_MODES_REPORT.md",
    "TEST_PLAN.md",
    "cache_checker_probe.sv",
    "check_regression.py",
    "cache_modes.py",
    "processor_benchmarks.py",
    "processor_benchmarks.json",
    "source_manifest.json",
}


def publication_files():
    """An explicit source selection keeps local history intact."""
    files = [ROOT / name for name in TOP]
    for directory, extensions in {
        "rtl": {".sv"},
        "tb": {".sv"},
        "programs": {".S", ".hex"},
        "sim": {".do", ".tcl"},
        "tools": {".py"},
    }.items():
        files.extend(
            p for p in (ROOT / directory).iterdir() if p.is_file() and p.suffix in extensions
        )
    files.append(ROOT / "sim/README.md")
    files.append(ROOT / "docs/README.md")
    files.extend(ROOT / "verification" / name for name in VERIFY)
    files.extend(p for p in (ROOT / "verification/results").rglob("*") if p.is_file())
    files.append(ROOT / "diagrams/cache_modes_results.svg")
    files.extend(
        ROOT / "third_party/picorv32" / name for name in ("picorv32.v", "COPYING", "UPSTREAM.md")
    )
    return sorted(set(files))


def check(files):
    names = {p.relative_to(ROOT).as_posix() for p in files}
    for p in files:
        assert p.is_file(), f"Missing publication file: {p}"
        if p.suffix == ".md":
            content = p.read_text(encoding="utf-8")
            assert not re.search(r"C:[/\\]Users[/\\]|\.codex[/\\]", content), p
            for target in re.findall(r"!?\[[^\]]*\]\(([^)\n]+)\)", content):
                target = target.split("#", 1)[0].strip("<>")
                if not target or re.match(r"[a-zA-Z]+:", target):
                    continue
                resolved = (p.parent / target).resolve()
                try:
                    name = resolved.relative_to(ROOT).as_posix()
                except ValueError:
                    raise AssertionError(f"Link leaves repository: {p.name}: {target}")
                assert (
                    name in names
                ), f"Link missing from archive: {p.relative_to(ROOT)} -> {target}"
    result = json.loads(
        (ROOT / "verification/results/cache_modes/results.json").read_text(encoding="utf-8")
    )
    assert result["status"] == "pass" and len(result["cases"]) == result["configurations"] == 52
    assert (
        len(
            {
                (c["program"], c["use_dcache"], c["use_icache"], c["ram_wait_cycles"])
                for c in result["cases"]
            }
        )
        == 52
    )
    assert all(c["program_completed"] == c["readback_passed"] == 1 for c in result["cases"])
    # Dated measurements retain their original source hashes. Check the current
    # release against the manifest written after its cleanup regression instead.
    current = json.loads((ROOT / "verification/source_manifest.json").read_text(encoding="utf-8"))
    assert current["status"] == "PASS"
    assert current["validation"]["processor_configurations"] == 52
    assert current["validation"]["dcache_cases"] == 16
    assert current["validation"]["functional_bins"] == "442/442"
    assert current["validation"]["icache_waits"] == [1, 4, 8]
    for name, expected in current["source_sha256"].items():
        assert name in names, f"Validated source missing from archive: {name}"
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, name
    for path in files:
        if path.suffix in {".sv", ".v", ".S", ".hex", ".py", ".do", ".tcl"}:
            assert path.relative_to(ROOT).as_posix() in current["source_sha256"], path
    dcache = json.loads(
        (ROOT / "verification/results/dcache/results.json").read_text(encoding="utf-8")
    )
    assert dcache["status"] == "PASS" and len(dcache["runs"]) == 16
    assert dcache["functional_bins"] == "442/442"
    assert all(row["hit"] == row["target"] for row in dcache["observed_coverage"].values())
    assert "sim/benchmark_cache_modes.do" in names and "sim/tools.tcl" in names
    assert not any("/build/" in name or name.startswith("reference/") for name in names)
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    files = publication_files()
    check(files)
    if args.check_only:
        print(
            f"PUBLICATION_CHECK_PASS: {len(files)} files; links, evidence and protected sources verified"
        )
        return
    output = ROOT / "dist/verified-picorv32-cache-subsystem.zip"
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for p in files:
            archive.write(p, "verified-picorv32-cache-subsystem/" + p.relative_to(ROOT).as_posix())
    print(f"PUBLICATION_PACKAGE_PASS: {len(files)} files; {output.stat().st_size:,} bytes")
    print(output)


if __name__ == "__main__":
    main()
