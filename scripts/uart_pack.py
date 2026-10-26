#!/usr/bin/env python3
"""Pack a program (ELF or raw .bin) for the UART bootloader (docs/boot.md), or send it to a board.

Stream: MAGIC, then one packet per segment:
  SYNC, addr (4 B LE), len (4 B LE), entry (4 B LE), data (len B), crc (4 B LE)
crc = CRC-32 (zlib) of addr, len, entry and data. entry = 0xFFFFFFFF on every packet but the
last, the last one carries the jump address.

ELF: one packet per allocated section with contents (.text, .rodata, .data, ...), at its run
address, in address order. .bss is not sent (crt0 clears it). Jump address = ELF entry.
.bin: one packet at --addr, jump address = --addr.
Each segment must be word aligned and inside IMEM or inside DMEM (rtl/bus/soc_map.vh), the
jump address word aligned inside IMEM. len is rounded up to 4 bytes.

  uart_pack.py prog.elf -o prog.uart                     raw stream (bytes)
  uart_pack.py prog.bin --addr 0x0 --hex prog.hex        one byte per line, for $readmemh
  uart_pack.py prog.elf --port /dev/ttyUSB0              send with pyserial: repeat MAGIC until
                                                         READY, then wait for each ACK
Test options: --entry A (other jump address), --pad N (pad .bin data to N bytes), --bad-crc,
--no-check (allow segments or jump addresses that the bootloader must NAK).
"""
import argparse
import os
import struct
import sys
import time
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from elf2hex import SHF_ALLOC, SHT_NOBITS, read_elf  # noqa: E402
from gen_boot_rom import soc_define  # noqa: E402

MAGIC, READY, SYNC, ACK, NAK = 0xA5, 0x3E, 0x5A, 0x06, 0x15
NO_JUMP = 0xFFFFFFFF


def elf_segments(path):
    """Returns ([(addr, data)], entry) from an ELF file."""
    with open(path, "rb") as f:
        (entry,) = struct.unpack_from("<I", f.read(0x1C), 0x18)
    sections, _ = read_elf(path)
    segs = [(addr, bytes(body)) for name, flags, stype, addr, sz, body in sections
            if flags & SHF_ALLOC and stype != SHT_NOBITS and sz > 0]
    if not segs:
        sys.exit("ERROR: uart_pack: %s has no section to load" % path)
    return sorted(segs), entry


def check(segs, entry):
    """Same rules as the bootloader, stops with an error on the first bad segment."""
    imem = soc_define("IMEM_SIZE")
    dbase, dsize = soc_define("DMEM_BASE"), soc_define("DMEM_SIZE")
    for addr, data in segs:
        inside = any(base <= addr and addr + len(data) <= base + size
                     for base, size in ((0, imem), (dbase, dsize)))
        if addr % 4 or not data or not inside:
            sys.exit("ERROR: uart_pack: segment [0x%08x, +%d] is not word aligned inside IMEM"
                     " (%d bytes) or DMEM (%d bytes at 0x%08x)"
                     % (addr, len(data), imem, dsize, dbase))
    if entry % 4 or entry >= imem:
        sys.exit("ERROR: uart_pack: jump address 0x%08x is not word aligned inside IMEM" % entry)


def pack(addr, data, entry, bad_crc=False):
    """Returns (header from SYNC, body = data + crc)."""
    hdr = struct.pack("<III", addr, len(data), entry)
    crc = zlib.crc32(hdr + data) ^ (1 if bad_crc else 0)
    return bytes([SYNC]) + hdr, data + struct.pack("<I", crc)


def send(port, baud, packets):
    try:
        import serial  # pyserial
    except ImportError:
        sys.exit("ERROR: uart_pack: --port needs pyserial (pip install pyserial)")
    t0 = time.time()
    with serial.Serial(port, baud, timeout=0.002) as s:
        print("Waiting for the bootloader, press reset on the board")
        s.reset_input_buffer()
        while True:                     # One MAGIC, then a gap so the receiver can resync
            s.write(bytes([MAGIC]))
            if READY in s.read(16):
                break
        s.timeout = 2.0
        t1 = time.time()
        for i, (hdr, body) in enumerate(packets):
            for part, what in ((hdr, "header"), (body, "data")):
                s.write(part)
                r = s.read(1)
                if r != bytes([ACK]):
                    sys.exit("ERROR: uart_pack: segment %d %s rejected (%s)"
                             % (i, what, "NAK" if r == bytes([NAK]) else "no answer"))
        print("Loaded %d bytes in %.2f s (%.2f s waiting for reset)"
              % (sum(len(b) - 4 for _, b in packets), time.time() - t1, t1 - t0))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("prog", help="ELF file, or a raw .bin with --addr")
    ap.add_argument("--addr", type=lambda v: int(v, 0), default=0, help=".bin load address")
    ap.add_argument("--entry", type=lambda v: int(v, 0), help="jump address (test)")
    ap.add_argument("-o", "--out", help="raw stream file")
    ap.add_argument("--hex", help="stream as hex, one byte per line")
    ap.add_argument("--port", help="serial port to send to")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--pad", type=int, default=0, help="pad .bin data with zeros to this many bytes")
    ap.add_argument("--bad-crc", action="store_true", help="flip one CRC bit of the last packet")
    ap.add_argument("--no-check", action="store_true", help="skip the address checks (test)")
    args = ap.parse_args()

    with open(args.prog, "rb") as f:
        is_elf = f.read(4) == b"\x7fELF"
    if is_elf:
        segs, entry = elf_segments(args.prog)
    else:
        with open(args.prog, "rb") as f:
            data = f.read()
        data += bytes(max(args.pad - len(data), 0))
        segs, entry = [(args.addr, data)], args.addr
    segs = [(addr, data + bytes(-len(data) % 4)) for addr, data in segs]
    if args.entry is not None:
        entry = args.entry
    if not args.no_check:
        check(segs, entry)

    packets = [pack(addr, data, entry if i == len(segs) - 1 else NO_JUMP,
                    args.bad_crc and i == len(segs) - 1)
               for i, (addr, data) in enumerate(segs)]
    stream = bytes([MAGIC]) + b"".join(h + b for h, b in packets)
    if args.out:
        with open(args.out, "wb") as f:
            f.write(stream)
    if args.hex:
        with open(args.hex, "w", encoding="utf-8") as f:
            f.write("".join("%02x\n" % b for b in stream))
    for addr, data in segs:
        print("uart_pack: segment 0x%08x, %d bytes" % (addr, len(data)))
    print("uart_pack: %d segments, %d data bytes, jump 0x%08x, %d stream bytes, %.3f s at %d baud"
          % (len(segs), sum(len(d) for _, d in segs), entry, len(stream),
             len(stream) * 10.0 / args.baud, args.baud))
    if args.port:
        send(args.port, args.baud, packets)


if __name__ == "__main__":
    main()
