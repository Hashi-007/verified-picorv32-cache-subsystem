"""Generate the GitHub benchmark SVG from the recorded measurements.

Uses only Python's standard library. Run from any working directory.
"""

from html import escape
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "verification/results/cache_modes/results.json"
OUTPUT = ROOT / "diagrams/cache_modes_results.svg"
MODES = [
    (0, 0, "Neither", "#64748b", ""),
    (1, 0, "D-cache only", "#b45309", "6 3"),
    (0, 1, "I-cache only", "#2563eb", "2 3"),
    (1, 1, "Both", "#047857", ""),
]
TITLES = {
    "reuse": "Repeated reuse",
    "sequential": "Sequential scan",
    "conflict": "Same-index conflicts",
    "store_heavy": "Repeated stores",
}


def main():
    data = json.loads(RESULTS.read_text(encoding="utf-8"))
    assert data["status"] == "pass" and data["configurations"] == 52
    cases = {
        (c["program"], c["use_dcache"], c["use_icache"], c["ram_wait_cycles"]): c
        for c in data["cases"]
    }
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="720" viewBox="0 0 1000 720" role="img" aria-labelledby="title desc">',
        '<title id="title">Measured program cycles across RAM waits and cache configurations</title>',
        '<desc id="desc">Four workloads at RAM waits 1, 4 and 8. Lower cycles are better. All 48 plotted cases passed. Hit rates describe enabled caches; bypassed caches have no hit rate.</desc>',
        '<rect width="1000" height="720" fill="#ffffff"/>',
    ]

    def text(x, y, label, size=12, color="#334155", anchor="start", bold=False):
        parts.append(
            f'<text x="{x}" y="{y}" fill="{color}" font-family="Arial, sans-serif" font-size="{size}" text-anchor="{anchor}" font-weight="{700 if bold else 400}">{escape(str(label))}</text>'
        )

    def line(x1, y1, x2, y2, color="#dbe2ea", width=1, dash=""):
        parts.append(
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}" stroke-dasharray="{dash}"/>'
        )

    text(40, 34, "Program cycles across memory latencies", 24, "#0f172a", bold=True)
    text(40, 56, "Four cache configurations · fixed CPU and programs · lower is better", 13)
    for i, (_, _, name, color, dash) in enumerate(MODES):
        x = 42 + i * 235
        line(x, 81, x + 28, 81, color, 2.5, dash)
        text(x + 37, 85, name, 13)

    for panel, (program, title) in enumerate(TITLES.items()):
        x = 80 + (panel % 2) * 490
        top = 123 + (panel // 2) * 292
        width, height = 350, 172
        y = top + 44
        sample = cases[program, 1, 1, 8]
        text(x, top, title, 17, "#0f172a", bold=True)
        text(
            x,
            top + 20,
            f'I hits {sample["icache_hit_rate_percent"]:.2f}%  ·  D hits {sample["dcache_hit_rate_percent"]:.2f}%  ·  D-read {sample["dcache_read_hit_rate_percent"]:.2f}%',
            11,
        )
        maximum = max(
            cases[program, d, i, wait]["program_cycles"] for d, i, *_ in MODES for wait in (1, 4, 8)
        )
        step = 10 ** math.floor(math.log10(maximum / 4))
        step *= next(f for f in (1, 2, 5, 10) if maximum / (4 * step) <= f)
        ceiling = math.ceil(maximum / step) * step
        px = lambda wait: x + (wait - 1) / 7 * width
        py = lambda cycles: y + height * (1 - cycles / ceiling)
        for tick in range(0, ceiling + 1, step):
            tick_y = py(tick)
            line(x, tick_y, x + width, tick_y)
            text(x - 10, tick_y + 4, f"{tick:,}", 11, anchor="end")
        line(x, y, x, y + height, "#94a3b8")
        line(x, y + height, x + width, y + height, "#94a3b8")
        for wait in (1, 4, 8):
            tick_x = px(wait)
            line(tick_x, y + height, tick_x, y + height + 4, "#94a3b8")
            text(tick_x, y + height + 19, wait, 11, anchor="middle")
        text(x + width / 2, y + height + 38, "RAM wait (cycles per word)", 11, anchor="middle")
        for d, i, name, color, dash in MODES:
            points = [
                (px(wait), py(cases[program, d, i, wait]["program_cycles"])) for wait in (1, 4, 8)
            ]
            coords = " ".join(f"{a:.2f},{b:.2f}" for a, b in points)
            parts.append(
                f'<polyline points="{coords}" fill="none" stroke="{color}" stroke-width="2.5" stroke-dasharray="{dash}"/>'
            )
            for wait, (a, b) in zip((1, 4, 8), points):
                cycles = cases[program, d, i, wait]["program_cycles"]
                parts.append(
                    f'<circle cx="{a:.2f}" cy="{b:.2f}" r="3.4" fill="{color}"><title>{escape(f"{title}: {name}, RAM wait {wait}, {cycles:,} program cycles")}</title></circle>'
                )
    text(
        40,
        700,
        "Measured simulation cycles, 18 Nov 2026. Checker readback and final dirty-line drain excluded.",
        11,
    )
    parts.append("</svg>")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print("RESULTS_FIGURE_WRITTEN:", OUTPUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
