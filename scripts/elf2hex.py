#!/usr/bin/env python3
"""Split an RV32 ELF into IMEM / DMEM images for $readmemh.

Each image covers the whole region, one little-endian 32-bit word per line,
word 0 = the region base (addresses relative to the region). Sections with contents
are placed at their run address (VMA). .bss is left to the memory model, which starts at 0.
Region bases and sizes come from tb/core/core_tb_map.vh (single source).

Prints "tohost=<hex>" when the ELF has a `tohost` symbol (used as +tohost=).

Usage: elf2hex.py prog.elf --imem imem.hex --dmem dmem.hex
                      [--imem-size N] [--dmem-size N]
"""
import argparse
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_FILE = os.path.join(ROOT, "tb", "core", "core_tb_map.vh")

SHF_ALLOC = 0x2
SHT_NOBITS = 8
SHT_SYMTAB = 2


def map_define(name):
    """Value of `define CORE_TB_<name> in core_tb_map.vh (Verilog number syntax)."""
    with open(MAP_FILE, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*`define\s+CORE_TB_%s\s+(\S+)" % name, line)
            if m:
                tok = m.group(1).replace("_", "")
                if "'h" in tok:
                    return int(tok.split("'h")[1], 16)
                return int(tok, 0)
    sys.exit("elf2hex: CORE_TB_%s not found in %s" % (name, MAP_FILE))


def read_elf(path):
    """Returns (sections, symbols), sections = [(name, flags, type, addr, size, bytes)]."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF":
        sys.exit("elf2hex: %s is not an ELF file" % path)
    if data[4] != 1 or data[5] != 1:
        sys.exit("elf2hex: only ELF32 little-endian is supported")
    (e_shoff,) = struct.unpack_from("<I", data, 0x20)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x2E)

    shdrs = []
    for i in range(e_shnum):
        shdrs.append(struct.unpack_from("<IIIIIIIIII", data, e_shoff + i * e_shentsize))

    def cstr(off):
        end = data.index(b"\0", off)
        return data[off:end].decode()

    shstr_off = shdrs[e_shstrndx][4]
    sections, symbols = [], {}
    for sh in shdrs:
        name, stype, flags, addr, off, size, link = sh[0], sh[1], sh[2], sh[3], sh[4], sh[5], sh[6]
        sname = cstr(shstr_off + name)
        body = b"" if stype == SHT_NOBITS else data[off:off + size]
        sections.append((sname, flags, stype, addr, size, body))
        if stype == SHT_SYMTAB:
            str_off = shdrs[link][4]
            for j in range(size // 16):
                st_name, st_value = struct.unpack_from("<II", data, off + j * 16)
                if st_name:
                    symbols[cstr(str_off + st_name)] = st_value
    return sections, symbols


def write_hex(path, image, size):
    """Write the whole region (zero padded) so $readmemh fills the memory exactly."""
    image = image + bytearray(size - len(image))
    with open(path, "w") as f:
        for w in range(size // 4):
            f.write("%08x\n" % struct.unpack_from("<I", image, 4 * w)[0])


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("elf")
    ap.add_argument("--imem", required=True)
    ap.add_argument("--dmem", required=True)
    ap.add_argument("--imem-base", type=lambda v: int(v, 0), default=map_define("IMEM_BASE"))
    ap.add_argument("--imem-size", type=int, default=map_define("IMEM_SIZE"))
    ap.add_argument("--dmem-size", type=int, default=map_define("DMEM_SIZE"))
    args = ap.parse_args()

    regions = {
        "imem": (args.imem_base, args.imem_size, bytearray()),
        "dmem": (map_define("DMEM_BASE"), args.dmem_size, bytearray()),
    }

    sections, symbols = read_elf(args.elf)
    for name, flags, stype, addr, size, body in sections:
        if not (flags & SHF_ALLOC) or size == 0:
            continue
        hit = None
        for rname, (base, rsize, _) in regions.items():
            if base <= addr and addr + size <= base + rsize:
                hit = rname
        if hit is None:
            sys.exit("elf2hex: section %s [0x%08x, +%d] is outside IMEM/DMEM" % (name, addr, size))
        if stype == SHT_NOBITS:
            continue
        base, _, image = regions[hit]
        off = addr - base
        if len(image) < off + size:
            image.extend(bytearray(off + size - len(image)))
        image[off:off + size] = body

    write_hex(args.imem, regions["imem"][2], args.imem_size)
    write_hex(args.dmem, regions["dmem"][2], args.dmem_size)
    if "tohost" in symbols:
        print("tohost=%08x" % symbols["tohost"])


if __name__ == "__main__":
    main()
