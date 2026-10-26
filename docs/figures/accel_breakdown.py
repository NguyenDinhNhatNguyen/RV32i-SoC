#!/usr/bin/env python3
"""Generate docs/figures/accel_breakdown.svg (cycles of one 4x4 block on the accelerator).

Numbers are copied from docs/bench_soc.md (section Speedup accelerator). Edit them here and rerun:
    python3 docs/figures/accel_breakdown.py
Labels stay in Vietnamese because the figure goes into the report.
"""
import os

from figstyle import BASE, BLUE_RAMP, GRID, INK, INK2, S1, S2, S3, fmt, plt, save

# One block multiply (poll), 235 cycles. START to DONE (24) = 12 compute + 12 APB.
STEPS = [
    ("Nạp A, B\n(8 ghi APB)", 41, BLUE_RAMP[1]),
    ("Ghi START,\nđọc STATUS", 12, BLUE_RAMP[2]),
    ("Tính", 12, S2),
    ("Đọc 16 word C qua APB và cộng dồn", 164, BLUE_RAMP[3]),
    ("Xoá\nDONE", 6, BLUE_RAMP[4]),
]
# Whole 16 x 16 multiply, cycles
TOTAL = {
    "rv32i (ENABLE_M=0)": [("Phần mềm", 577522), ("Accel, poll", 23046), ("Accel, irq", 25471)],
    "rv32im (ENABLE_M=1)": [("Phần mềm", 39039), ("Accel, poll", 23100), ("Accel, irq", 25458)],
}

fig = plt.figure(figsize=(11, 5.4))
gs = fig.add_gridspec(2, 2, height_ratios=[1, 1.25], hspace=0.75, wspace=0.35)
a0 = fig.add_subplot(gs[0, :])
left = 0
for name, n, c in STEPS:
    a0.barh(0, n, left=left, height=0.8, color=c, edgecolor="white", linewidth=2)
    mid = left + n / 2
    if n >= 30:
        a0.text(mid, 0, "%s\n%d chu kỳ" % (name, n), ha="center", va="center", fontsize=8.5,
                color="white")
    elif c == S2:
        a0.text(mid, 0.45, "%s\n%d" % (name, n), ha="center", va="bottom", fontsize=8.5,
                color=S2, fontweight="bold")
    else:
        # Small APB steps are labelled under the bar so they do not collide with "Tính"
        a0.text(mid, -0.45, "%s\n%d" % (name, n), ha="center", va="top", fontsize=8,
                color=INK2)
    left += n
a0.set_xlim(0, 235)
a0.set_ylim(-1.15, 1.0)
a0.set_yticks([])
a0.spines["left"].set_visible(False)
a0.set_xlabel("Chu kỳ (tổng 235)")
a0.set_title("(a) Một phép nhân khối 4 × 4 (poll): accelerator chỉ tính 12 / 235 chu kỳ, "
             "còn lại là chuyển dữ liệu qua APB", loc="left", fontsize=11)

for k, (cfg, rows) in enumerate(TOTAL.items()):
    a = fig.add_subplot(gs[1, k])
    names = [r[0] for r in rows][::-1]
    vals = [r[1] for r in rows][::-1]
    cols = [S3, S1, BASE]
    a.barh(names, vals, height=0.6, color=cols, edgecolor="white", linewidth=1.5)
    sw = rows[0][1]
    for y, v in enumerate(vals):
        lab = "{:,}".format(v).replace(",", " ")
        if v != sw:
            lab += "  (%s×)" % fmt(sw / v, 2)
        a.text(v + max(vals) * 0.01, y, lab, va="center", fontsize=8.5, color=INK)
    a.set_xlim(0, max(vals) * 1.35)
    a.xaxis.set_major_locator(plt.MaxNLocator(4))
    a.xaxis.grid(True, color=GRID, linewidth=0.8)
    a.set_axisbelow(True)
    a.tick_params(axis="y", length=0)
    a.xaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: "{:,.0f}".format(v).replace(",", " ")))
    a.set_xlabel("Chu kỳ cho cả phép nhân 16 × 16")
    a.set_title("(%s) %s" % ("bc"[k], cfg), loc="left", fontsize=11, color=INK2)

save(fig, os.path.join(os.path.dirname(os.path.abspath(__file__)), "accel_breakdown.svg"))
