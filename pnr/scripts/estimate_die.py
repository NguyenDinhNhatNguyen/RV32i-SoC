#!/usr/bin/env python3
"""Estimate the die size for the floorplan (PD-02).

Inputs: standard cell area from the Genus report_area, the SRAM macro size from its LEF
(printed by check_server.sh), and the target utilization.

Example:
  python3 pnr/scripts/estimate_die.py --std-area 45000 --macro 120x80 --macro 120x80 --util 0.70
"""
import argparse
import math


def parse_macro(s):
    w, h = s.lower().split("x")
    return float(w), float(h)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--std-area", type=float, required=True, help="Total standard cell area (um^2) from Genus")
    p.add_argument("--macro", action="append", default=[], type=parse_macro,
                   help="Macro size WxH (um), repeat for each macro")
    p.add_argument("--util", type=float, default=0.70, help="Target standard cell density (0..1)")
    p.add_argument("--halo", type=float, default=5.0, help="Halo quanh macro (um)")
    p.add_argument("--aspect", type=float, default=1.0, help="Core height/width ratio")
    p.add_argument("--margin", type=float, default=15.0, help="Core to die edge (um), room for the power ring")
    p.add_argument("--row", type=float, default=1.71, help="Cell row height (um), GPDK45 gsclib045 = 1.71")
    a = p.parse_args()

    macro_area = sum((w + 2 * a.halo) * (h + 2 * a.halo) for w, h in a.macro)
    std_need = a.std_area / a.util
    core_area = std_need + macro_area
    core_w = math.sqrt(core_area / a.aspect)
    core_h = core_w * a.aspect
    # Round the height up to a whole number of cell rows
    core_h = math.ceil(core_h / a.row) * a.row
    core_w = math.ceil(core_area / core_h)

    for w, h in a.macro:
        if w + 2 * a.halo > core_w or h + 2 * a.halo > core_h:
            print(f"WARNING: Macro {w}x{h} does not fit the core. Increase the size or change the aspect")

    die_w = core_w + 2 * a.margin
    die_h = core_h + 2 * a.margin
    print(f"Std cell area        : {a.std_area:,.0f} um^2  (util {a.util:.0%} -> needs {std_need:,.0f} um^2)")
    print(f"Macro+halo area      : {macro_area:,.0f} um^2  ({len(a.macro)} macros)")
    print(f"Core                 : {core_w:,.1f} x {core_h:,.1f} um = {core_w*core_h:,.0f} um^2")
    print(f"Die (margin {a.margin} um) : {die_w:,.1f} x {die_h:,.1f} um = {die_w*die_h/1e6:.4f} mm^2")
    print(f"Innovus command      : floorPlan -site CoreSite -s {core_w:.1f} {core_h:.1f} "
          f"{a.margin} {a.margin} {a.margin} {a.margin}")


if __name__ == "__main__":
    main()
