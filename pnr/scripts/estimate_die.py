#!/usr/bin/env python3
"""Ước lượng kích thước die cho floorplan (PD-02).

Đầu vào lấy từ: diện tích cell chuẩn trong report_area của Genus, kích thước SRAM macro trong LEF (check_server.sh in ra), utilization mục tiêu.

Ví dụ:
  python3 pnr/scripts/estimate_die.py --std-area 45000 --macro 120x80 --macro 120x80 --util 0.70
"""
import argparse
import math


def parse_macro(s):
    w, h = s.lower().split("x")
    return float(w), float(h)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--std-area", type=float, required=True, help="Tổng diện tích cell chuẩn (um^2) từ Genus")
    p.add_argument("--macro", action="append", default=[], type=parse_macro,
                   help="Kích thước macro WxH (um), lặp lại cho mỗi macro")
    p.add_argument("--util", type=float, default=0.70, help="Mật độ cell chuẩn mục tiêu (0..1)")
    p.add_argument("--halo", type=float, default=5.0, help="Halo quanh macro (um)")
    p.add_argument("--aspect", type=float, default=1.0, help="Tỉ lệ cao/rộng của core")
    p.add_argument("--margin", type=float, default=15.0, help="Core tới biên die (um), chỗ cho power ring")
    p.add_argument("--row", type=float, default=1.71, help="Chiều cao hàng cell (um), GPDK45 gsclib045 = 1.71")
    a = p.parse_args()

    macro_area = sum((w + 2 * a.halo) * (h + 2 * a.halo) for w, h in a.macro)
    std_need = a.std_area / a.util
    core_area = std_need + macro_area
    core_w = math.sqrt(core_area / a.aspect)
    core_h = core_w * a.aspect
    # làm tròn chiều cao theo bội số hàng cell
    core_h = math.ceil(core_h / a.row) * a.row
    core_w = math.ceil(core_area / core_h)

    for w, h in a.macro:
        if w + 2 * a.halo > core_w or h + 2 * a.halo > core_h:
            print(f"WARNING: Macro {w}x{h} không vừa core. Hãy tăng kích thước hoặc đổi aspect")

    die_w = core_w + 2 * a.margin
    die_h = core_h + 2 * a.margin
    print(f"Diện tích cell chuẩn : {a.std_area:,.0f} um^2  (util {a.util:.0%} -> cần {std_need:,.0f} um^2)")
    print(f"Diện tích macro+halo : {macro_area:,.0f} um^2  ({len(a.macro)} macro)")
    print(f"Core                 : {core_w:,.1f} x {core_h:,.1f} um = {core_w*core_h:,.0f} um^2")
    print(f"Die (margin {a.margin} um) : {die_w:,.1f} x {die_h:,.1f} um = {die_w*die_h/1e6:.4f} mm^2")
    print(f"Lệnh Innovus         : floorPlan -site CoreSite -s {core_w:.1f} {core_h:.1f} "
          f"{a.margin} {a.margin} {a.margin} {a.margin}")


if __name__ == "__main__":
    main()
