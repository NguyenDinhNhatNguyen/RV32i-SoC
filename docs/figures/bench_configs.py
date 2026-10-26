#!/usr/bin/env python3
"""Generate docs/figures/bench_configs.svg (CPI and gain of the branch prediction options).

Numbers are copied from docs/btb_eval.md section 3 (soc_top). Edit them here and rerun:
    python3 docs/figures/bench_configs.py
Labels stay in Vietnamese because the figure goes into the report.
"""
import os

import numpy as np
from figstyle import BASE, GRID, INK2, S1, S2, S3, fmt, plt, save

BENCH = ["Dhrystone\nrv32i", "Dhrystone\nrv32im", "CoreMark\nrv32i", "CoreMark\nrv32im"]
CFG = ["Base (ENABLE_BTB=0)", "BTB 8 entry", "BTB 16 entry", "Tĩnh (ENABLE_BTB=2)"]
COLORS = [BASE, S1, S2, S3]
# CPI on soc_top, one row per config
CPI = [
    [1.220, 1.286, 1.204, 1.158],
    [1.141, 1.201, 1.096, 1.076],
    [1.137, 1.190, 1.088, 1.067],
    [1.105, 1.165, 1.085, 1.075],
]
# DMIPS/MHz (Dhrystone) and CoreMark/MHz (CoreMark) on soc_top
PERF = [
    [0.800, 0.800, 1.112, 2.755],
    [0.856, 0.857, 1.223, 2.967],
    [0.858, 0.865, 1.232, 2.992],
    [0.884, 0.884, 1.235, 2.969],
]

x = np.arange(len(BENCH))
w = 0.2
fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4.2), gridspec_kw={"wspace": 0.22})

for i, (row, c) in enumerate(zip(CPI, COLORS)):
    a1.bar(x + (i - 1.5) * w, row, w, color=c, edgecolor="white", linewidth=1.5, label=CFG[i])
for j, v in enumerate(CPI[0]):
    a1.text(x[j] - 1.5 * w, v + 0.01, fmt(v), ha="center", va="bottom", fontsize=8, color=INK2)
a1.set_ylim(1.0, 1.32)
a1.set_ylabel("CPI trên soc_top (thấp hơn là tốt)")
a1.set_title("(a) CPI", loc="left", fontsize=11)

for i in range(1, 4):
    gain = [100.0 * (p / b - 1) for p, b in zip(PERF[i], PERF[0])]
    bars = a2.bar(x + (i - 2) * w, gain, w, color=COLORS[i], edgecolor="white", linewidth=1.5)
    for b, g in zip(bars, gain):
        a2.text(b.get_x() + w / 2, g + 0.2, fmt(g, 1), ha="center", va="bottom", fontsize=8,
                color=INK2)
a2.set_ylim(0, 13)
a2.set_ylabel("Tăng so với base (%)")
a2.set_title("(b) DMIPS/MHz (Dhrystone) và CoreMark/MHz (CoreMark)", loc="left", fontsize=11)

for a in (a1, a2):
    a.set_xticks(x)
    a.set_xticklabels(BENCH)
    a.yaxis.grid(True, color=GRID, linewidth=0.8)
    a.set_axisbelow(True)
    a.tick_params(axis="x", length=0)
    a.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: fmt(v, 2 if v < 2 else 0)))
a2.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: "%d" % v))

fig.legend(*a1.get_legend_handles_labels(), loc="upper center", ncol=4, bbox_to_anchor=(0.5, 1.03))
save(fig, os.path.join(os.path.dirname(os.path.abspath(__file__)), "bench_configs.svg"))
