#!/usr/bin/env python3
"""Generate docs/figures/boot_fsm.svg (state diagram of the UART bootloader in fw/boot/boot.S).

Same states as docs/boot.md section 4. Coordinates are hand-written, edit them here and rerun:
    python3 docs/figures/boot_fsm.py
Labels stay in Vietnamese because the figure goes into the report.
"""
import os

from matplotlib.patches import FancyArrowPatch, FancyBboxPatch
from figstyle import BLUE_RAMP, INK, INK2, MUTED, S2, S3, plt, save

C_OK, C_ERR, C_EXIT = INK2, "#d03b3b", S3
fig, ax = plt.subplots(figsize=(10, 8.2))
ax.set_xlim(-5.2, 6.2)
ax.set_ylim(-0.9, 10.6)
ax.axis("off")

# name: (x, y, width, title, detail)
S = {
    "reset": (0, 10.1, 2.4, "Reset", "PC = 0x0001_0000"),
    "strap": (0, 8.8, 2.6, "STRAP", "đọc gpio_i[0]"),
    "init": (0, 7.5, 3.4, "INIT UART", "BAUDDIV, CTRL, bỏ byte cũ"),
    "magic": (0, 6.2, 3.4, "WAIT_MAGIC", "chờ 0xA5, đếm mcycle"),
    "sync": (0, 4.6, 3.4, "WAIT_SYNC", "chờ 0x5A, bỏ byte khác"),
    "hdr": (0, 3.3, 3.4, "HEADER", "addr, len, entry (12 byte)"),
    "data": (0, 2.0, 3.4, "DATA + CRC", "ghi IMEM/DMEM từng word"),
    "jump": (0, 0.2, 3.4, "NHẢY TỚI ENTRY", "xoá thanh ghi, fence.i"),
    "imem": (4.4, 7.5, 2.6, "CHẠY IMEM", "nhảy tới 0x0000_0000"),
    "nak": (4.4, 2.65, 1.8, "Gửi NAK", "0x15"),
}
H = 0.82


def node(k, fill="#ffffff", edge=MUTED):
    x, y, w, t, d = S[k]
    ax.add_patch(FancyBboxPatch((x - w / 2, y - H / 2), w, H, boxstyle="round,pad=0.02,rounding_size=0.12",
                                fc=fill, ec=edge, lw=1.4))
    ax.text(x, y + 0.13, t, ha="center", va="center", fontsize=10.5, fontweight="bold", color=INK)
    ax.text(x, y - 0.19, d, ha="center", va="center", fontsize=8.5, color=INK2)


def edge(k, side):
    x, y, w = S[k][0], S[k][1], S[k][2]
    return {"t": (x, y + H / 2), "b": (x, y - H / 2), "l": (x - w / 2, y), "r": (x + w / 2, y)}[side]


def path(pts, color=C_OK, label=None, lpos=None, ha="left", lcolor=None):
    """Polyline, arrow head on the last segment."""
    xs, ys = zip(*pts)
    ax.plot(xs[:-1] + (xs[-1],), ys[:-1] + (ys[-1],), color=color, lw=1.5, solid_capstyle="butt")
    ax.add_patch(FancyArrowPatch(pts[-2], pts[-1], arrowstyle="-|>", mutation_scale=13, color=color,
                                 lw=1.5, shrinkA=0, shrinkB=0))
    if label:
        ax.text(lpos[0], lpos[1], label, ha=ha, va="center", fontsize=8.5, color=lcolor or color)


for k in S:
    if k == "imem" or k == "jump":
        node(k, fill="#e6f6ef", edge=C_EXIT)
    elif k == "nak":
        node(k, fill="#fbeaea", edge=C_ERR)
    elif k == "reset":
        node(k, fill="#f0efec")
    else:
        node(k, fill="#eef4fc", edge=BLUE_RAMP[2])

path([edge("reset", "b"), edge("strap", "t")])
path([edge("strap", "b"), edge("init", "t")], label="gpio_i[0] = 1", lpos=(0.12, 8.15))
path([edge("init", "b"), edge("magic", "t")])
path([edge("magic", "b"), edge("sync", "t")], label="nhận MAGIC, gửi READY 0x3E", lpos=(0.12, 5.4))
path([edge("sync", "b"), edge("hdr", "t")], label="nhận SYNC", lpos=(0.12, 3.95))
path([edge("hdr", "b"), edge("data", "t")], label="header đúng, gửi ACK", lpos=(0.12, 2.65))
path([edge("data", "b"), edge("jump", "t")], color=C_EXIT,
     label="CRC đúng, gửi ACK, entry hợp lệ (gói cuối)", lpos=(0.12, 1.1), lcolor=INK2)

# Exits to IMEM
xs, ys = edge("strap", "r")
path([(xs, ys), (S["imem"][0], ys), edge("imem", "t")], color=C_EXIT,
     label="gpio_i[0] = 0\nhoặc lỗi bus (trap)", lpos=(xs + 0.15, ys + 0.35), lcolor=INK2)
xm, ym = edge("magic", "r")
path([(xm, ym), (S["imem"][0], ym), edge("imem", "b")], color=C_EXIT,
     label="hết TIMEOUT_CYCLES\n(1 s ở 50 MHz)", lpos=(xm + 0.15, ym - 0.38), lcolor=INK2)

# Errors to NAK, then back to WAIT_SYNC
xn = S["nak"][0]
xh, yh = edge("hdr", "r")
path([(xh, yh), (xn, yh), (xn, S["nak"][1] + H / 2)], color=C_ERR,
     label="sai vùng, lệch, len = 0,\nentry sai", lpos=(xh + 0.15, yh + 0.33), lcolor=C_ERR)
xd, yd = edge("data", "r")
path([(xd, yd), (xn, yd), (xn, S["nak"][1] - H / 2)], color=C_ERR,
     label="CRC sai", lpos=(xd + 0.15, yd - 0.22), lcolor=C_ERR)
xr = xn + S["nak"][2] / 2
xq, yq = edge("sync", "r")
path([(xr, S["nak"][1]), (xr + 0.6, S["nak"][1]), (xr + 0.6, yq), (xq, yq)], color=C_ERR,
     label="gửi lại từ SYNC", lpos=(xq + 0.15, yq + 0.2), lcolor=C_ERR)

# More segments: back to WAIT_SYNC
xl, yl = edge("data", "l")
xs2, ys2 = edge("sync", "l")
path([(xl, yl), (xl - 0.9, yl), (xl - 0.9, ys2), (xs2, ys2)], color=BLUE_RAMP[3],
     label="CRC đúng, gửi ACK,\nentry = 0xFFFF_FFFF\n(còn segment sau)", lpos=(xl - 1.0, 3.3),
     ha="right", lcolor=INK2)

ax.text(-5.1, -0.75, "Mọi số nhiều byte là little endian. Sau NAK không còn timeout. "
        "Dữ liệu chỉ được chạy khi CRC đúng.", fontsize=8.5, color=INK2)
save(fig, os.path.join(os.path.dirname(os.path.abspath(__file__)), "boot_fsm.svg"))
