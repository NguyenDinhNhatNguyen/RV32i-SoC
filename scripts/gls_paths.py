#!/usr/bin/env python3
"""gls_paths.py - find the 8 sram_2k_macro instances of a soc_top netlist (VER-07).

Usage: gls_paths.py <netlist.v> [-o gls_paths.vh] [--top soc_top]

Reads a gate-level netlist (Genus write_hdl, or Yosys write_verilog for the home check),
follows the instances from the top module down to every sram_2k_macro, and writes the
hierarchical names for tb_soc -DGLS:

    `define GLS_I0 dut.<path of IMEM bank 0>   ... GLS_I3
    `define GLS_D0 dut.<path of DMEM bank 0>   ... GLS_D3

Works with a flat netlist (one escaped name per macro) and with a netlist that keeps the
hierarchy. IMEM or DMEM comes from "imem" or "dmem" in the path, the bank from the last
"bank" followed by a number. Exits 1 if it does not find exactly 4 IMEM and 4 DMEM banks.
"""
import argparse
import re
import sys

MACRO = "sram_2k_macro"
KEYWORDS = {
    "module", "endmodule", "input", "output", "inout", "wire", "reg", "assign", "supply0",
    "supply1", "tri", "wand", "wor", "parameter", "localparam", "specify", "endspecify",
    "initial", "always", "function", "endfunction", "task", "endtask", "defparam",
}
IDENT = r"(\\\S+|[A-Za-z_][\w$]*)"
INST_RE = re.compile(r"^\s*" + IDENT + r"\s*(?:#\s*\(.*?\)\s*)?" + IDENT + r"\s*\(", re.S)


def parse(text):
    """Return {module: [(cell, instance), ...]} for every module in the netlist."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    mods = {}
    for m in re.finditer(r"\bmodule\s+" + IDENT + r"(.*?)\bendmodule\b", text, re.S):
        name, body = m.group(1), m.group(2)
        insts = []
        # Skip the port list header, then look at each statement
        hdr = body.find(";")
        for stmt in body[hdr + 1:].split(";"):
            im = INST_RE.match(stmt)
            if im and im.group(1) not in KEYWORDS:
                insts.append((im.group(1), im.group(2)))
        mods[name] = insts
    return mods


def ref(name):
    """An escaped identifier needs a space before the next '.' of a hierarchical name."""
    return name + " " if name.startswith("\\") else name


def walk(mods, mod, path, found):
    for cell, inst in mods.get(mod, []):
        p = path + [inst]
        if cell == MACRO:
            found.append(p)
        elif cell in mods:
            walk(mods, cell, p, found)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("netlist")
    ap.add_argument("-o", "--out", default="-")
    ap.add_argument("--top", default="soc_top")
    a = ap.parse_args()

    mods = parse(open(a.netlist, errors="replace").read())
    if a.top not in mods:
        sys.exit(f"ERROR: no module {a.top} in {a.netlist}")
    found = []
    walk(mods, a.top, [], found)

    banks = {}
    for p in found:
        flat = " ".join(p).lower()
        kind = "I" if "imem" in flat else "D" if "dmem" in flat else None
        nums = re.findall(r"bank\D{0,4}?(\d+)", flat)
        if kind is None or not nums:
            sys.exit(f"ERROR: cannot tell IMEM/DMEM or bank of {'.'.join(p)}")
        key = f"{kind}{nums[-1]}"
        if key in banks:
            sys.exit(f"ERROR: two macros for {key}: {'.'.join(banks[key])} and {'.'.join(p)}")
        banks[key] = p

    want = [f"{k}{b}" for k in "ID" for b in range(4)]
    if sorted(banks) != sorted(want):
        names = "\n  ".join(".".join(p) for p in found)
        sys.exit(f"ERROR: expected 4 IMEM and 4 DMEM macros, found {len(found)}:\n  {names}")

    # tb_soc writes `GLS_D0 .CEN (space before the dot), so a last escaped name still ends
    # at whitespace even if the preprocessor drops trailing spaces of the define.
    lines = [f"// Written by scripts/gls_paths.py from {a.netlist}. Do not edit."]
    for k in want:
        lines.append(f"`define GLS_{k} dut." + ".".join(ref(n) for n in banks[k]).rstrip())
    out = "\n".join(lines) + "\n"
    if a.out == "-":
        sys.stdout.write(out)
    else:
        open(a.out, "w").write(out)
    for k in want:
        print(f"gls_paths: {k} -> {'.'.join(banks[k])}", file=sys.stderr)


if __name__ == "__main__":
    main()
