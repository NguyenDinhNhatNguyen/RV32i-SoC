#!/usr/bin/env python3
"""Gom số PPA từ report Genus và Innovus thành bảng Markdown.

Định dạng report theo các file trong appendix/synth_accel và appendix/pnr_accel.

  --genus NHÃN=THƯ_MỤC     thư mục có qor.rpt, area.rpt, power.rpt (gates.rpt nếu có),
                           lặp lại được, ví dụ cg0=appendix/synth_accel/cg0/synthesis
  --innovus NHÃN=THƯ_MỤC   thư mục report Innovus (area.rpt, power.rpt,
                           postroute_setup/, postroute_hold/, summary/)
  --lib FILE               liberty GPDK45 (.lib hoặc .lib.gz) để lấy diện tích NAND2X1
  --cpi X                  CPI để tính EPI. Bỏ trống thì cột EPI ghi "-"
  --freq MHZ               tần số chạy. Mặc định lấy từ chu kỳ clock trong qor.rpt

GE = diện tích / diện tích NAND2X1. Diện tích NAND2X1 lấy theo thứ tự: --lib,
gates.rpt của Genus (diện tích / số instance NAND2X1), "Gate area" trong area.rpt
của Innovus. Năng lượng mỗi chu kỳ = P / f, EPI = P × CPI / f.

Cách dùng: ppa_table.py --genus cg1=... --innovus pnr=... [--cpi 1.2] > bảng.md
"""
import argparse
import glob
import gzip
import os
import re
import sys

NAND2 = "NAND2X1"


def read_text(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as f:
        return f.read()


def find(pattern, text, cast=float):
    m = re.search(pattern, text, re.M)
    return cast(m.group(1)) if m else None


def first_file(d, *names):
    for n in names:
        hits = sorted(glob.glob(os.path.join(d, n)))
        if hits:
            return hits[0]
    return None


def nand2_from_lib(path):
    txt = read_text(path)
    m = re.search(r"cell\s*\(\s*\"?%s\"?\s*\)\s*\{[^}]*?\barea\s*:\s*([0-9.]+)" % NAND2, txt, re.S)
    return float(m.group(1)) if m else None


def nand2_from_gates(path):
    m = re.search(r"^%s\s+(\d+)\s+([0-9.]+)" % NAND2, read_text(path), re.M)
    return float(m.group(2)) / int(m.group(1)) if m and int(m.group(1)) else None


def parse_genus(d):
    r = {"tool": "Genus"}
    qor = first_file(d, "qor.rpt")
    if qor:
        t = read_text(qor)
        r["module"] = find(r"^\s*Module:\s+(\S+)", t, str)
        r["period_ns"] = find(r"^clk\s+([0-9.]+)\s*$", t) / 1000.0  # Genus báo ps
        slack = find(r"^clk\s+(-?[0-9.]+)\s+-?[0-9.]+\s+\d+", t)
        r["slack_ns"] = slack / 1000.0 if slack is not None else None
        r["cells"] = find(r"Leaf Instance Count\s+(\d+)", t, int)
        r["seq"] = find(r"Sequential Instance Count\s+(\d+)", t, int)
        r["area"] = find(r"Total Area \(Cell\+Physical\+Net\)\s+([0-9.]+)", t)
    area = first_file(d, "area.rpt")
    if area and r.get("area") is None:
        r["area"] = find(r"^\S+\s+\S*\s*\d+\s+[0-9.]+\s+[0-9.]+\s+([0-9.]+)", read_text(area))
    pwr = first_file(d, "power.rpt")
    if pwr:
        t = read_text(pwr)
        tot = find(r"^\s*Subtotal\s+\S+\s+\S+\s+\S+\s+(\S+)", t)
        r["power_mw"] = tot * 1e3 if tot is not None else None  # Genus báo W
        clk = find(r"^\s*clock\s+\S+\s+\S+\s+\S+\s+(\S+)", t)
        r["clk_power_mw"] = clk * 1e3 if clk is not None else None
    gates = first_file(d, "gates.rpt")
    r["nand2"] = nand2_from_gates(gates) if gates else None
    r["nand2_src"] = gates
    cg = first_file(d, "clock_gating.rpt")
    if cg:
        r["icg"] = find(r"Total\s+(?:Clock Gating Instances|CG Instances)\s*\|?\s*(\d+)", read_text(cg), int)
    return r


def parse_innovus(d):
    r = {"tool": "Innovus"}
    area = first_file(d, "area.rpt")
    if area:
        t = read_text(area)
        r["nand2"] = find(r"Gate area\s+([0-9.]+)", t)
        r["nand2_src"] = area
        r["module"] = find(r"Level 0 Module\s+(\S+)", t, str)
        r["cells"] = find(r"Level 0 Module.*Cells=\s*(\d+)", t, int)
        r["area"] = find(r"Level 0 Module.*Area=\s*([0-9.]+)", t)
    pwr = first_file(d, "power.rpt")
    if pwr:
        t = read_text(pwr)
        r["power_mw"] = find(r"^Total Power:\s+([0-9.eE+-]+)", t)  # Innovus báo mW
        r["clk_power_mw"] = find(r"^Clock \(Combinational\)\s+\S+\s+\S+\s+\S+\s+(\S+)", t)
    for mode, key in (("setup", "slack_ns"), ("hold", "hold_ns")):
        f = first_file(d, "postroute_%s/*postRoute*.summary*" % mode)
        if f:
            t = read_text(f)
            r[key] = find(r"WNS \(ns\):\|\s*(-?[0-9.]+)", t)
            r["density"] = find(r"^Density:\s+([0-9.]+)%", t)
    summ = first_file(d, "summary/*.main.htm.ascii")
    if summ:
        r["core_area"] = find(r"Total area of Core:\s+([0-9.]+)", read_text(summ))
    return r


def fmt(v, nd=2):
    if v is None:
        return "-"
    # Kiểu viết trong docs/: cách nghìn bằng dấu cách, thập phân bằng dấu phẩy
    if isinstance(v, int):
        return f"{v:,}".replace(",", " ")
    return f"{v:,.{nd}f}".replace(",", " ").replace(".", ",")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--genus", action="append", default=[], metavar="NHÃN=THƯ_MỤC")
    ap.add_argument("--innovus", action="append", default=[], metavar="NHÃN=THƯ_MỤC")
    ap.add_argument("--lib")
    ap.add_argument("--cpi", type=float)
    ap.add_argument("--freq", type=float, help="MHz")
    a = ap.parse_args()
    if not a.genus and not a.innovus:
        ap.error("cần ít nhất một --genus hoặc --innovus")

    runs = []
    for spec, parse in [(s, parse_genus) for s in a.genus] + [(s, parse_innovus) for s in a.innovus]:
        label, _, d = spec.partition("=")
        if not os.path.isdir(d):
            sys.exit(f"không có thư mục {d}")
        r = parse(d)
        r["label"] = label
        runs.append(r)

    nand2, src = None, None
    if a.lib:
        nand2, src = nand2_from_lib(a.lib), a.lib
    for r in runs:
        if nand2 is None and r.get("nand2"):
            nand2, src = r["nand2"], r["nand2_src"]
    period = next((r["period_ns"] for r in runs if r.get("period_ns")), None)
    freq = a.freq or (1000.0 / period if period else None)
    if period is None and freq:
        period = 1000.0 / freq  # chỉ có report Innovus thì lấy chu kỳ từ --freq

    print("| Bước | Công cụ | Module | Cell | Flop | ICG | Diện tích (µm²) | GE (kGE) | Mật độ (%) "
          "| Slack setup (ns) | Slack hold (ns) | F_max (MHz) | P (mW) | P clock (mW) "
          "| E/chu kỳ (pJ) | EPI (pJ) |")
    print("| --- | --- | --- |" + " ---: |" * 13)
    for r in runs:
        ge = r["area"] / nand2 / 1000 if nand2 and r.get("area") else None
        fmax = None
        if period and r.get("slack_ns") is not None:
            fmax = 1000.0 / (period - r["slack_ns"])
        p = r.get("power_mw")
        epc = p / freq * 1e3 if p is not None and freq else None  # mW / MHz = nJ, đổi ra pJ
        epi = epc * a.cpi if epc is not None and a.cpi else None
        print(f"| {r['label']} | {r['tool']} | {r.get('module') or '-'} | {fmt(r.get('cells'))} "
              f"| {fmt(r.get('seq'))} | {fmt(r.get('icg'))} | {fmt(r.get('area'), 1)} | {fmt(ge, 2)} | {fmt(r.get('density'), 1)} "
              f"| {fmt(r.get('slack_ns'), 3)} | {fmt(r.get('hold_ns'), 3)} | {fmt(fmax, 1)} "
              f"| {fmt(p, 4)} | {fmt(r.get('clk_power_mw'), 4)} | {fmt(epc, 3)} | {fmt(epi, 3)} |")
    print()
    print(f"- Tần số tính năng lượng: {fmt(freq, 1)} MHz"
          + (f", chu kỳ clock {fmt(period, 3)} ns" if period else "") + ".")
    print(f"- NAND2X1 = {fmt(nand2, 4)} µm², lấy từ `{src}`." if nand2 else "- Không tìm được diện tích NAND2X1, cột GE để trống.")
    print("- F_max = 1 / (chu kỳ clock − slack setup), chỉ là ước lượng.")
    print(f"- EPI = P × CPI / f với CPI = {fmt(a.cpi, 3)}." if a.cpi else "- Chưa có CPI (`--cpi`) nên cột EPI để trống.")
    print("- Công suất Genus và Innovus tính với hoạt động mặc định của tool nếu không nạp SAIF/VCD.")


if __name__ == "__main__":
    main()
