#!/usr/bin/env python3
"""Sinh bảng kết quả riscv-tests (markdown) từ tb/core/out/isa-core.summary.

Mỗi ô là số chế độ chạy đạt / tổng số chế độ (nominal, stall1..3) của một
cấu hình tb_core. Cách dùng: isa_status.py [summary] > bảng.md
"""
import collections
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "tb/core/out/isa-core.summary"
res = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0]))
cfgs = set()
for line in open(path, encoding="utf-8"):
    m = re.match(r"\s+(PASS:|\[FAIL\]) (\S+?)/(M\dW\d)/(\w+)", line)
    if not m:
        continue
    ok, test, cfg = m.group(1) == "PASS:", m.group(2), m.group(3)
    cfgs.add(cfg)
    res[test][cfg][1] += 1
    res[test][cfg][0] += ok

cfgs = sorted(cfgs)
print("| Test | " + " | ".join(cfgs) + " | Kết quả |")
print("| --- | " + " | ".join("---" for _ in cfgs) + " | --- |")
for suite in ("rv32ui", "rv32mi", "rv32um"):
    for test in sorted(t for t in res if t.startswith(suite)):
        cells, all_ok = [], True
        for c in cfgs:
            p, n = res[test][c]
            cells.append("%d/%d" % (p, n) if n else "-")
            all_ok &= p == n
        print("| %s | %s | %s |" % (test, " | ".join(cells), "PASS" if all_ok else "**FAIL**"))
