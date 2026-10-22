#!/usr/bin/env python3
"""Sinh docs/figures/core_microarch.svg (vi kiến trúc rv32_core).

Toạ độ viết tay, sửa ở đây rồi chạy lại thay vì sửa SVG:
    python3 docs/figures/core_microarch.py
Mô tả hình: docs/spec/core.md mục 4.2.
"""
import os
import sys
from xml.sax.saxutils import escape

W, H = 1480, 990
C_DP, C_FWD, C_RED, C_BUS, C_STALL = "#333333", "#1f6fd1", "#d23f31", "#2e8b57", "#e08a00"
FONT = "Helvetica, Arial, sans-serif"
out = []


def add(s):
    out.append(s)


def text(x, y, s, size=12, anchor="start", weight="normal", color="#222", italic=False, rotate=None):
    st = ' font-style="italic"' if italic else ""
    rot = ' transform="rotate(%d %d %d)"' % (rotate, x, y) if rotate is not None else ""
    add('<text x="%g" y="%g" font-size="%g" text-anchor="%s" font-weight="%s" fill="%s"%s%s>%s</text>'
        % (x, y, size, anchor, weight, color, st, rot, escape(s)))


def box(x, y, w, h, title, lines=(), fill="#ffffff", stroke="#555", title_size=12.5, line_size=11, rx=4):
    add('<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s" stroke="%s" stroke-width="1.3"/>'
        % (x, y, w, h, rx, fill, stroke))
    n = 1 + len(lines)
    lh = line_size + 3
    y0 = y + h / 2 - (n - 1) * lh / 2 + 4
    text(x + w / 2, y0, title, title_size, "middle", "bold")
    for i, l in enumerate(lines):
        text(x + w / 2, y0 + (i + 1) * lh, l, line_size, "middle")


def flop(x, y, w, h, name, lines=()):
    """Thanh ghi: nền vàng nhạt, tam giác clock ở cạnh dưới."""
    box(x, y, w, h, name, lines, fill="#fff4cc", stroke="#8a6d00", title_size=11.5, line_size=10)
    cx = x + w / 2
    add('<path d="M%g %g L%g %g L%g %g" fill="none" stroke="#8a6d00" stroke-width="1"/>'
        % (cx - 6, y + h, cx, y + h - 7, cx + 6, y + h))


def mux(x, y, w, h, label=None):
    """Mux hình thang, đầu vào bên trái, đầu ra bên phải."""
    d = h * 0.18
    add('<path d="M%g %g L%g %g L%g %g L%g %g Z" fill="#eef1f5" stroke="#555" stroke-width="1.3"/>'
        % (x, y, x + w, y + d, x + w, y + h - d, x, y + h))
    if label:
        text(x + w / 2, y - 4, label, 9.5, "middle", color="#555")


def wire(pts, color=C_DP, width=1.6, dash=None, arrow=True, both=False):
    d = "M" + " L".join("%g %g" % p for p in pts)
    da = ' stroke-dasharray="%s"' % dash if dash else ""
    mk = ' marker-end="url(#a_%s)"' % color[1:] if arrow else ""
    ms = ' marker-start="url(#s_%s)"' % color[1:] if both else ""
    add('<path d="%s" fill="none" stroke="%s" stroke-width="%g"%s%s%s/>' % (d, color, width, da, mk, ms))


def dot(x, y, color=C_DP):
    add('<circle cx="%g" cy="%g" r="3" fill="%s"/>' % (x, y, color))


# ---------------------------------------------------------------------------
add('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" font-family="%s">'
    % (W, H, W, H, FONT))
add('<defs>')
for c in (C_DP, C_FWD, C_RED, C_BUS, C_STALL):
    add('<marker id="a_%s" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">'
        '<path d="M0 0 L10 5 L0 10 Z" fill="%s"/></marker>' % (c[1:], c))
    add('<marker id="s_%s" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" markerHeight="7" orient="auto">'
        '<path d="M10 0 L0 5 L10 10 Z" fill="%s"/></marker>' % (c[1:], c))
add('</defs>')
add('<rect width="%d" height="%d" fill="#ffffff"/>' % (W, H))

text(20, 32, "rv32_core: vi kiến trúc pipeline 3 tầng IF / EX / WB", 20, weight="bold")
text(20, 54, "RV32I + Zicsr + Zicntr + Zifencei, M-mode, RV32M khi ENABLE_M = 1 (docs/spec/core.md mục 4)", 12, color="#555")

# Biên core và các tầng
add('<rect x="170" y="80" width="1160" height="800" fill="none" stroke="#444" stroke-width="2" rx="6"/>')
for x0, x1, xl, name, sub, fill in ((170, 400, 285, "IF", "lấy lệnh", "#eaf2fb"),
                                    (400, 1000, 700, "EX", "giải mã, thực thi, phát yêu cầu bus", "#eef7ea"),
                                    (1000, 1330, 1068, "WB", "ghi rd, CSR, trap", "#fbf1e6")):
    add('<rect x="%d" y="81" width="%d" height="798" fill="%s"/>' % (x0 + 1, x1 - x0 - 2, fill))
    add('<text x="%g" y="100" text-anchor="middle" fill="#333"><tspan font-size="15" font-weight="bold">%s</tspan>'
        '<tspan font-size="11.5" fill="#555" dx="8">%s</tspan></text>' % (xl, name, escape(sub)))
add('<line x1="400" y1="81" x2="400" y2="879" stroke="#999" stroke-dasharray="5 4"/>')
add('<line x1="1000" y1="81" x2="1000" y2="879" stroke="#999" stroke-dasharray="5 4"/>')
add('<rect x="170" y="80" width="1160" height="800" fill="none" stroke="#444" stroke-width="2" rx="6"/>')

# ---------------------------------------------------------------- ngoài core
box(20, 170, 120, 570, "IMEM", ["boot ROM", "", "SRAM đọc", "đồng bộ:", "lệnh có ở", "chu kỳ sau"], fill="#f4f4f4")
box(430, 915, 880, 50, "Bus dữ liệu valid/ready (mục 5.1) → sys_bus",
    ["DMEM, IMEM qua imem_port, cầu APB (Timer, UART, GPIO, accelerator)"], fill="#f4f4f4")

# ---------------------------------------------------------------- IF
flop(200, 110, 80, 32, "sleep_q")
wire([(200, 126), (80, 126), (80, 170)], C_BUS)
text(20, 120, "if_req_o = ~sleep_q", 10.5, color=C_BUS)
wire([(240, 110), (240, 66)], C_BUS)
text(246, 72, "core_sleep_o", 10.5, color=C_BUS)

box(180, 400, 90, 46, "if_fire", ["req & gnt"], title_size=11, line_size=10)
wire([(140, 423), (180, 423)], C_BUS)
text(143, 416, "if_gnt_i", 10.5, color=C_BUS)

box(185, 560, 120, 110, "Chọn PC kế", ["1. wb_target (WB)", "2. ex_target (EX)", "3. if_pc_q + 4", "4. giữ khi dừng"],
    title_size=11.5, line_size=10.5)
flop(315, 595, 70, 40, "if_pc_q")
wire([(305, 615), (315, 615)])
# if_pc_q -> IMEM, +4, ex_pc_q
wire([(350, 635), (350, 730), (140, 730)], C_BUS)
text(143, 724, "if_addr_o", 10.5, color=C_BUS)
dot(350, 640)
add('<circle cx="270" cy="700" r="14" fill="#fff" stroke="#555" stroke-width="1.3"/>')
text(270, 704, "+4", 11, "middle", "bold")
wire([(270, 730), (270, 714)], arrow=False)
dot(270, 730, C_BUS)
wire([(270, 686), (270, 670)])
wire([(385, 615), (410, 615), (410, 288), (430, 288)])
text(180, 850, "Không có thanh ghi IF/EX: ngõ ra IMEM", 10.5, color="#555", italic=True)
text(180, 863, "đọc đồng bộ là ranh giới hai tầng", 10.5, color="#555", italic=True)

# ---------------------------------------------------------------- EX cột 1
flop(430, 205, 90, 40, "ex_instr_hold_q", ["giữ lệnh khi dừng"])
flop(430, 270, 90, 36, "ex_pc_q")
flop(430, 318, 90, 36, "ex_fetch_q", ["ex_hold_q"])
mux(540, 170, 18, 80)
wire([(140, 185), (540, 185)], C_BUS)
text(143, 179, "if_rdata_i, if_err_i", 10.5, color=C_BUS)
dot(470, 185, C_BUS)
wire([(470, 185), (470, 205)], C_BUS)
wire([(520, 228), (540, 228)])
wire([(558, 210), (580, 210)])
text(549, 264, "ex_instr", 10, "middle", color="#555")

box(430, 420, 130, 140, "Ngoại lệ, ngắt", ["lỗi lấy lệnh, illegal,", "CSR sai (cổng kiểm", "tra của rv32_csr),", "ECALL, EBREAK,", "nhảy/load/store lệch,", "ngắt: MIE, mip & mie", "→ ex_trap gắn cờ"],
    title_size=11.5, line_size=10)
box(430, 600, 130, 90, "Dừng IF và EX", ["pipe_stall =", "wb_wait | ex_wait", "(bus chưa nhận,", "M-unit chưa xong)"],
    title_size=11.5, line_size=10, stroke=C_STALL)
wire([(430, 645), (370, 645), (370, 635)], C_STALL, dash="5 3")
text(375, 658, "giữ", 10, color=C_STALL)

# ---------------------------------------------------------------- EX cột 2-6
box(580, 180, 110, 60, "rv32_decoder", ["rs1, rs2, rd, imm_type,", "chọn ALU, cờ lệnh"], title_size=11.5, line_size=10)
box(580, 270, 110, 100, "rv32_regfile", ["31 × 32 bit", "2 cổng đọc tổ hợp", "ghi ở WB"], title_size=11.5, line_size=10)
wire([(635, 240), (635, 270)])
box(580, 385, 110, 40, "rv32_imm_gen", [], title_size=11.5)
wire([(690, 282), (715, 282)])
wire([(690, 342), (715, 342)])
mux(715, 270, 20, 40, "fwd")
mux(715, 330, 20, 40, "fwd")
mux(770, 262, 18, 50, "A: rs1, pc, 0")
mux(770, 330, 18, 50, "B: rs2, imm")
wire([(735, 290), (770, 290)])
wire([(735, 350), (770, 350)])
wire([(756, 271), (770, 271)], arrow=True, width=1)
wire([(690, 405), (762, 405), (762, 368), (770, 368)])
text(722, 418, "imm", 10, "middle", color="#555")

box(795, 180, 70, 50, "So sánh", ["nhánh"], title_size=11, line_size=10)
text(830, 244, "rs1, rs2", 9.5, "middle", color="#555")
box(830, 260, 70, 120, "ALU", ["cộng", "địa chỉ,", "đích nhảy"], title_size=13, line_size=10)
wire([(788, 287), (830, 287)])
wire([(788, 355), (830, 355)])

mux(930, 250, 20, 190, "ex_result")
wire([(900, 320), (930, 320)])
text(908, 272, "pc+4", 9.5, color="#555")
wire([(906, 280), (930, 280)], width=1)
text(905, 391, "CSR", 9.5, color="#555")
wire([(906, 398), (930, 398)], width=1)
wire([(950, 345), (1010, 345)])
text(975, 337, "ex_result", 10, "middle", color="#555")

box(712, 470, 112, 90, "rv32_muldiv", ["ENABLE_M = 1", "MUL*: dừng 1", "DIV/REM: dừng 33"],
    title_size=11.5, line_size=10)
dot(752, 350)
wire([(752, 350), (752, 470)])
text(756, 462, "rs1, rs2", 9.5, color="#555")
wire([(824, 515), (940, 515), (940, 440)])

box(830, 560, 160, 60, "Làn byte (lsu_align)", ["byte enable, lặp dữ liệu,", "kiểm tra lệch"], title_size=11, line_size=10)
dot(865, 380)
wire([(865, 380), (865, 560)])
text(869, 458, "địa chỉ", 9.5, color="#555")
wire([(910, 620), (910, 915)], C_BUS)
wire([(950, 915), (950, 620)], C_BUS)
text(905, 900, "d_req_valid_o, d_addr_o, d_we_o, d_be_o, d_wdata_o", 10.5, "end", color=C_BUS)
text(955, 900, "d_req_ready_i", 10.5, color=C_BUS)

# ---------------------------------------------------------------- EX -> WB, chuyển hướng EX
wire([(870, 680), (1010, 680)])
text(865, 676, "pc, instr, rd,", 9.5, "end", color="#555")
text(865, 688, "cờ trap/CSR/MRET/WFI", 9.5, "end", color="#555")
# ex_target
wire([(885, 260), (885, 160), (290, 160), (290, 560)], C_RED, width=2)
wire([(865, 205), (885, 205)], C_RED, arrow=False)
text(600, 154, "ex_target, ex_redirect: nhánh/JAL/JALR nhảy, phạt 1 chu kỳ", 11, color=C_RED)

# ---------------------------------------------------------------- WB
add('<rect x="1010" y="150" width="40" height="610" rx="4" fill="#fff4cc" stroke="#8a6d00" stroke-width="1.3"/>')
text(1034, 455, "Thanh ghi tầng WB (wb_*_q), chỉ nạp khi có lệnh", 11.5, "middle", rotate=-90)

box(1085, 130, 225, 150, "rv32_csr", ["mstatus, misa, mie, mip, mtvec,", "mepc, mcause, mtval, mscratch,",
                                      "mcycle(h), minstret(h), time(h)", "cổng kiểm tra cho EX,", "đọc/ghi RW/RS/RC ở WB"],
    title_size=12.5, line_size=10.5)
for x in (1160, 1205, 1250, 1295):
    wire([(x, 66), (x, 130)], C_BUS)
text(1155, 62, "irq_software_i, irq_timer_i, irq_external_i, mtime_i", 10.5, color=C_BUS)
box(1085, 310, 150, 110, "Trap / tuần tự hoá", ["trap (cả lỗi bus),", "MRET, FENCE.I, WFI", "→ wb_redirect,", "wb_target = mtvec |", "mepc | pc + 4"],
    title_size=11.5, line_size=10)
wire([(1160, 310), (1160, 280)], both=True)
text(1166, 300, "trap, MRET / mtvec, mepc", 9.5, color="#555")

box(1085, 470, 225, 70, "wb_rd_data", ["load ? dữ liệu load :", "CSR ? giá trị CSR cũ : wb_result_q"], title_size=11.5, line_size=10)
wire([(1295, 280), (1295, 470)])
text(1291, 450, "CSR", 9.5, "end", color="#555")
box(1085, 590, 115, 50, "Căn chỉnh load", ["lsu_align, dấu"], title_size=11, line_size=10)
wire([(1140, 590), (1140, 540)])
wire([(1140, 915), (1140, 640)], C_BUS)
text(1146, 900, "d_rsp_valid_i, d_rsp_rdata_i, d_rsp_err_i", 10.5, color=C_BUS)
for y in (205, 365, 505, 615):
    wire([(1050, y), (1085, y)])

# Forward và ghi register file
wire([(1270, 540), (1270, 750), (570, 750), (570, 355), (580, 355)], C_FWD, width=2)
dot(703, 750, C_FWD)
wire([(703, 750), (703, 300), (715, 300)], C_FWD, width=2)
dot(703, 360, C_FWD)
wire([(703, 360), (715, 360)], C_FWD, width=2)
text(1040, 768, "forward WB → EX (kết quả ALU, CSR, dữ liệu load): không có stall load-use", 11, "middle", color=C_FWD)
text(575, 744, "ghi rd", 10.5, color=C_FWD)

# Chuyển hướng từ WB và WFI
wire([(1085, 400), (1068, 400), (1068, 820), (210, 820), (210, 670)], C_RED, width=2)
text(640, 814, "wb_target, wb_redirect: trap, MRET, FENCE.I, WFI (ưu tiên hơn EX, huỷ lệnh ở EX và lệnh đang lấy, phạt 2 chu kỳ)",
     11, "middle", color=C_RED)
wire([(1085, 330), (1062, 330), (1062, 126), (280, 126)], C_RED, dash="6 3")
text(660, 120, "WFI: sleep_q ← 1, thức khi (mip & mie) ≠ 0", 11, color=C_RED)

# ---------------------------------------------------------------- chú thích
lx, ly = 20, 768
text(lx, ly, "Chú thích", 12, weight="bold")
for i, (c, lab, dash) in enumerate(((C_DP, "dữ liệu", None), (C_FWD, "forward, ghi rd", None),
                                    (C_RED, "chuyển hướng PC", None), (C_BUS, "cổng của core", None),
                                    (C_STALL, "dừng pipeline", "5 3"))):
    y = ly + 18 + i * 18
    wire([(lx, y - 4), (lx + 34, y - 4)], c, dash=dash)
    text(lx + 40, y, lab, 11)
add('<rect x="%d" y="%d" width="22" height="12" fill="#fff4cc" stroke="#8a6d00"/>' % (lx + 6, ly + 104))
text(lx + 40, ly + 114, "thanh ghi", 11)

add('</svg>')
dst = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "core_microarch.svg")
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
