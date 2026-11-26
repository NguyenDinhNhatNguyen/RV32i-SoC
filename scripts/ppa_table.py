#!/usr/bin/env python3
"""Collect PPA numbers from Genus and Innovus reports into a Markdown table.

Report formats follow the files in appendix/synth_accel and appendix/pnr_accel.
The table text stays in Vietnamese because it goes straight into the report.

  --genus LABEL=DIR        folder with qor.rpt, area.rpt, power.rpt (and gates.rpt if present),
                           can repeat, for example cg0=appendix/synth_accel/cg0/synthesis
  --innovus LABEL=DIR      Innovus report folder (area.rpt, power.rpt,
                           postroute_setup/, postroute_hold/, summary/)
  --lib FILE               GPDK45 liberty (.lib or .lib.gz) to read the NAND2X1 area
  --cpi X                  CPI used for EPI. When empty the EPI column shows "-"
  --freq MHZ               Frequency for energy and EPI. Default is the clock period of each run
  --saif FILE              summary.md of make power-soc (appendix/power_soc_pre), adds a
                           power and EPI table per testcase
  --instret NAME=N         Instructions of a testcase for the --saif table, can repeat

Area is split into standard cells and macros (8 SRAM). GE uses the standard cell
area only, because a macro is not made of gates. In an Innovus folder the
standard cell area, core area and density outside macros come from summary/
(physical cells such as fillers not counted). Timing comes from eco/ when the
folder has one.

GE = area / NAND2X1 area. The NAND2X1 area is taken in this order: --lib,
Genus gates.rpt (area / NAND2X1 instance count), "Gate area" in the Innovus
area.rpt. Energy per cycle = P / f, EPI = P x CPI / f. In the --saif table
CPI = cycles / instret, so EPI = P x CPI / f equals energy / instret.

Usage: ppa_table.py --genus cg1=... --innovus pnr=... [--cpi 1.2] > table.md
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
        r["period_ns"] = find(r"^clk\s+([0-9.]+)\s*$", t) / 1000.0  # Genus reports ps
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
        r["power_mw"] = tot * 1e3 if tot is not None else None  # Genus reports W
        clk = find(r"^\s*clock\s+\S+\s+\S+\s+\S+\s+(\S+)", t)
        r["clk_power_mw"] = clk * 1e3 if clk is not None else None
    gates = first_file(d, "gates.rpt")
    r["nand2"] = nand2_from_gates(gates) if gates else None
    r["nand2_src"] = gates
    if gates:
        t = read_text(gates)
        # Type table: "sequential" is flops only, ICG and macros have their own rows
        r["seq"] = find(r"^sequential\s+(\d+)\s+[0-9.]+", t, int) or r.get("seq")
        r["macro_area"] = find(r"^timing_model\s+\d+\s+([0-9.]+)", t) or 0.0
    if r.get("area") is not None:
        r["std_area"] = r["area"] - r.get("macro_area", 0.0)
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
        r["power_mw"] = find(r"^Total Power:\s+([0-9.eE+-]+)", t)  # Innovus reports mW
        r["clk_power_mw"] = find(r"^Clock \(Combinational\)\s+\S+\s+\S+\s+\S+\s+(\S+)", t)
        per_us = find(r"^Clock Period:\s+([0-9.]+)\s*usec", t)
        r["period_ns"] = per_us * 1000.0 if per_us else None
    # Timing after ECO when present, the same layout otherwise
    tdir = os.path.join(d, "eco") if os.path.isdir(os.path.join(d, "eco")) else d
    r["timing_src"] = tdir
    for mode, key in (("setup", "slack_ns"), ("hold", "hold_ns")):
        f = first_file(tdir, "postroute_%s/*postRoute*.summary*" % mode)
        if f:
            r[key] = find(r"WNS \(ns\):\|\s*(-?[0-9.]+)", read_text(f))
    summ = first_file(d, "summary/*.main.htm.ascii")
    if summ:
        t = read_text(summ)
        r["core_area"] = find(r"Total area of Core:\s+([0-9.]+)", t)
        r["std_area"] = find(r"Total area of Standard cells\(Subtracting Physical Cells\):"
                             r"\s+([0-9.]+)", t)
        r["density"] = find(r"Pure Gate Density #4 \(Subtracting MACROS and Physical Cells\):"
                            r"\s+([0-9.]+)%", t)
        m = re.search(r"Macro Cells in Netlist(.*?)# Std Cells", t, re.S)
        if m:
            rows = re.findall(r"^\s*\S+\s+\d+\s+([0-9.]+)\s+[0-9.]+%", m.group(1), re.M)
            r["macro_area"] = sum(float(x) for x in rows)
    if r.get("std_area") is None and r.get("area") is not None:
        r["std_area"] = r["area"] - r.get("macro_area", 0.0)
    return r


def saif_table(path, instret, freq):
    """Power per testcase from make power-soc, with EPI computed two ways."""
    t = read_text(path)
    per = find(r"clock\s+([0-9.]+)\s*ns", t)
    f = freq or (1000.0 / per if per else None)
    print()
    print("| Testcase | Chu kỳ | Instret | CPI | P (mW) | Năng lượng (µJ) | EPI = E / instret (pJ) "
          "| EPI = P × CPI / f (pJ) |")
    print("| --- |" + " ---: |" * 7)
    # Row: case | SAIF | cycles | leakage | internal | switching | total | energy
    row = r"^\|\s*(\S+)\s*\|\s*SAIF\s*\|\s*(\d+)\s*\|(?:[^|]*\|){3}\s*([0-9.]+)\s*\|"
    for m in re.finditer(row, t, re.M):
        name, cyc, p = m.group(1), int(m.group(2)), float(m.group(3))
        n = instret.get(name)
        e_uj = p * 1e-3 * cyc / (f * 1e6) * 1e6 if f else None  # mW x cycles / f
        cpi = cyc / n if n else None
        epi_e = e_uj * 1e6 / n if n and e_uj is not None else None
        epi_f = p * cpi / f * 1e3 if cpi and f else None  # mW / MHz = nJ, converted to pJ
        print(f"| `{name}` | {fmt(cyc)} | {fmt(n)} | {fmt(cpi, 3)} | {fmt(p, 4)} | {fmt(e_uj, 4)} "
              f"| {fmt(epi_e, 2)} | {fmt(epi_f, 2)} |")
    print()
    print(f"- Bảng công suất theo testcase lấy từ `{path}`, f = {fmt(f, 1)} MHz.")
    print("- CPI = chu kỳ GLS / instret RTL của cả chương trình (không chỉ vùng đo benchmark).")


def fmt(v, nd=2):
    if v is None:
        return "-"
    # Number style used in docs/: space as thousands separator, comma as decimal mark
    if isinstance(v, int):
        return f"{v:,}".replace(",", " ")
    return f"{v:,.{nd}f}".replace(",", " ").replace(".", ",")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--genus", action="append", default=[], metavar="LABEL=DIR")
    ap.add_argument("--innovus", action="append", default=[], metavar="LABEL=DIR")
    ap.add_argument("--lib")
    ap.add_argument("--cpi", type=float)
    ap.add_argument("--freq", type=float, help="MHz")
    ap.add_argument("--saif")
    ap.add_argument("--instret", action="append", default=[], metavar="NAME=N")
    a = ap.parse_args()
    if not a.genus and not a.innovus:
        ap.error("need at least one --genus or --innovus")

    runs = []
    for spec, parse in [(s, parse_genus) for s in a.genus] + [(s, parse_innovus) for s in a.innovus]:
        label, _, d = spec.partition("=")
        if not os.path.isdir(d):
            sys.exit(f"folder not found: {d}")
        r = parse(d)
        r["label"] = label
        runs.append(r)

    nand2, src = None, None
    if a.lib:
        nand2, src = nand2_from_lib(a.lib), a.lib
    for r in runs:
        if nand2 is None and r.get("nand2"):
            nand2, src = r["nand2"], r["nand2_src"]

    print("| Bước | Công cụ | Module | Cell | Flop | ICG | Chu kỳ (ns) | Cell chuẩn (µm²) "
          "| Macro (µm²) "
          "| GE (kGE) | Mật độ (%) | Slack setup (ns) | Slack hold (ns) | F_max (MHz) | P (mW) "
          "| P clock (mW) | E/chu kỳ (pJ) | EPI (pJ) |")
    print("| --- | --- | --- |" + " ---: |" * 15)
    for r in runs:
        period = r.get("period_ns") or (1000.0 / a.freq if a.freq else None)
        freq = a.freq or (1000.0 / period if period else None)
        ge = r["std_area"] / nand2 / 1000 if nand2 and r.get("std_area") else None
        fmax = None
        if period and r.get("slack_ns") is not None:
            fmax = 1000.0 / (period - r["slack_ns"])
        p = r.get("power_mw")
        epc = p / freq * 1e3 if p is not None and freq else None  # mW / MHz = nJ, converted to pJ
        epi = epc * a.cpi if epc is not None and a.cpi else None
        print(f"| {r['label']} | {r['tool']} | {r.get('module') or '-'} | {fmt(r.get('cells'))} "
              f"| {fmt(r.get('seq'))} | {fmt(r.get('icg'))} | {fmt(period, 1)} "
              f"| {fmt(r.get('std_area'), 1)} | {fmt(r.get('macro_area'), 1)} | {fmt(ge, 2)} "
              f"| {fmt(r.get('density'), 1)} | {fmt(r.get('slack_ns'), 3)} "
              f"| {fmt(r.get('hold_ns'), 3)} "
              f"| {fmt(fmax, 1)} | {fmt(p, 4)} | {fmt(r.get('clk_power_mw'), 4)} | {fmt(epc, 3)} "
              f"| {fmt(epi, 3)} |")
    print()
    print("- Năng lượng tính ở tần số " + (f"{fmt(a.freq, 1)} MHz." if a.freq
                                           else "của chu kỳ clock từng dòng."))
    print(f"- NAND2X1 = {fmt(nand2, 4)} µm², lấy từ `{src}`. GE chỉ tính cell chuẩn." if nand2
          else "- Không tìm được diện tích NAND2X1, cột GE để trống.")
    print("- F_max = 1 / (chu kỳ clock − slack setup), chỉ là ước lượng của tool.")
    print(f"- EPI = P × CPI / f với CPI = {fmt(a.cpi, 3)}." if a.cpi
          else "- Chưa có CPI (`--cpi`) nên cột EPI để trống.")
    print("- Công suất Genus và Innovus tính với hoạt động mặc định của tool nếu không nạp SAIF/VCD.")
    if a.saif:
        instret = {}
        for spec in a.instret:
            k, _, v = spec.partition("=")
            instret[k] = int(v)
        saif_table(a.saif, instret, a.freq)


if __name__ == "__main__":
    main()
