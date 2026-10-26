#!/usr/bin/env python3
"""Pack a raw program (.bin) for the UART bootloader (docs/boot.md), or send it to a board.

Stream: MAGIC, SYNC, addr (4 B LE), len (4 B LE), data (len B), crc (4 B LE)
crc = CRC-32 (zlib) of addr, len and data. len is the .bin size rounded up to 4 bytes.

  uart_pack.py prog.bin --addr 0x0 -o prog.uart          raw stream (bytes)
  uart_pack.py prog.bin --addr 0x0 --hex prog.hex        one byte per line, for $readmemh
  uart_pack.py prog.bin --addr 0x0 --port /dev/ttyUSB0   send with pyserial: repeat MAGIC until
                                                         READY, then wait for each ACK
Test options: --pad N (pad data to N bytes), --bad-crc, --no-check (allow addr/len that the
bootloader must NAK).
"""
import argparse
import os
import re
import struct
import sys
import time
import zlib

MAGIC, READY, SYNC, ACK, NAK = 0xA5, 0x3E, 0x5A, 0x06, 0x15
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def imem_size():
    """SOC_IMEM_SIZE from rtl/bus/soc_map.vh."""
    with open(os.path.join(ROOT, "rtl", "bus", "soc_map.vh"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*`define\s+SOC_IMEM_SIZE\s+32'd(\d+)", line)
            if m:
                return int(m.group(1))
    sys.exit("ERROR: uart_pack: SOC_IMEM_SIZE not found")


def pack(data, addr, bad_crc=False):
    """Returns (header from SYNC, body = data + crc)."""
    hdr = struct.pack("<II", addr, len(data))
    crc = zlib.crc32(hdr + data) ^ (1 if bad_crc else 0)
    return bytes([SYNC]) + hdr, data + struct.pack("<I", crc)


def send(port, baud, hdr, body):
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
        for part, what in ((hdr, "header"), (body, "data")):
            s.write(part)
            r = s.read(1)
            if r != bytes([ACK]):
                sys.exit("ERROR: uart_pack: %s rejected (%s)" % (what, "NAK" if r == bytes([NAK])
                                                                  else "no answer"))
        print("Loaded %d bytes in %.2f s (%.2f s waiting for reset)"
              % (len(body) - 4, time.time() - t1, t1 - t0))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("bin")
    ap.add_argument("--addr", type=lambda v: int(v, 0), default=0, help="load and jump address")
    ap.add_argument("-o", "--out", help="raw stream file")
    ap.add_argument("--hex", help="stream as hex, one byte per line")
    ap.add_argument("--port", help="serial port to send to")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--pad", type=int, default=0, help="pad data with zeros to this many bytes")
    ap.add_argument("--bad-crc", action="store_true", help="flip one CRC bit (test)")
    ap.add_argument("--no-check", action="store_true", help="allow addr/len outside IMEM (test)")
    args = ap.parse_args()

    with open(args.bin, "rb") as f:
        data = f.read()
    data += bytes(max(args.pad - len(data), 0))
    data += bytes(-len(data) % 4)
    size = imem_size()
    if not args.no_check and (args.addr % 4 or not data or args.addr >= size
                              or len(data) > size - args.addr):
        sys.exit("ERROR: uart_pack: [0x%08x, +%d] is not word aligned inside IMEM (%d bytes)"
                 % (args.addr, len(data), size))

    hdr, body = pack(data, args.addr, args.bad_crc)
    stream = bytes([MAGIC]) + hdr + body
    if args.out:
        with open(args.out, "wb") as f:
            f.write(stream)
    if args.hex:
        with open(args.hex, "w", encoding="utf-8") as f:
            f.write("".join("%02x\n" % b for b in stream))
    print("uart_pack: addr 0x%08x, %d data bytes, %d stream bytes, %.3f s at %d baud"
          % (args.addr, len(data), len(stream), len(stream) * 10.0 / args.baud, args.baud))
    if args.port:
        send(args.port, args.baud, hdr, body)


if __name__ == "__main__":
    main()
