#!/usr/bin/env python3
"""Estimate the CPI of a 5-stage core from tb_core +trace logs (V2-01).

Run first: make bench-core PLUSARGS=+trace
Usage:     cpi5_estimate.py tb/core/out/bench/*.bench.log > table.md

Only the BENCH region is counted, from the mcycle read of bench_start to the mcycle read of
bench_stop. The measured cycles, instret and redirects come from the BENCH lines of the log.
Extra cycles over the measured 3-stage core:
  - Branch resolved in EX: +1 cycle per redirect (2 bubbles instead of 1). In ID: +0.
  - Load data forwarded from MEM/WB to EX: load-use at distance 1 costs 1 bubble.
    Without that forward the load result is used after WB: 2 bubbles at distance 1 and
    1 bubble at distance 2. A scoreboard counts the stalls, so back-to-back hazards overlap.
  - MUL, DIV, IMEM data access and the BTB keep the timing of the 3-stage core.
"""
import re
import sys

TRACE = re.compile(r'core   0: 3 0x([0-9a-f]{8}) \(0x([0-9a-f]{8})\)')
F_SIGNOFF = 100.0   # MHz, V1 sign-off clock
F_MAX = 110.8       # MHz, V1 F_max (docs/eva03_ppa.md)


def srcs(ins):
    """Return the source registers (non-zero) of an instruction."""
    op, f3 = ins & 0x7f, (ins >> 12) & 7
    rs1, rs2 = (ins >> 15) & 31, (ins >> 20) & 31
    if op in (0x33, 0x23, 0x63):            # R, S, B
        regs = (rs1, rs2)
    elif op in (0x13, 0x03, 0x67):          # OP-IMM, LOAD, JALR
        regs = (rs1,)
    elif op == 0x73 and f3 in (1, 2, 3):    # CSRRW, CSRRS, CSRRC
        regs = (rs1,)
    else:
        regs = ()
    return [r for r in regs if r]


def rd_of(ins):
    op = ins & 0x7f
    if op in (0x33, 0x13, 0x03, 0x67, 0x6f, 0x37, 0x17) or (op == 0x73 and (ins >> 12) & 7):
        return (ins >> 7) & 31
    return 0


def csr_read(ins):
    """Return the CSR address of a CSRRS or CSRRC, else -1."""
    return ins >> 20 if (ins & 0x7f) == 0x73 and (ins >> 12) & 3 else -1


def is_load(ins):
    return ins & 0x7f == 0x03


def is_mul(ins):
    return ins & 0x7f == 0x33 and ins >> 25 == 1 and (ins >> 12) & 7 < 4


def load_stalls(seq, lat):
    """Stall cycles when a load result is ready lat cycles after the load issues."""
    ready = {}
    t = extra = 0
    for ins in seq:
        t += 1
        need = max([t] + [ready.get(r, 0) for r in srcs(ins)])
        extra += need - t
        t = need
        r = rd_of(ins)
        if r:
            ready[r] = t + lat if is_load(ins) else 0
    return extra


def parse(path):
    instrs, console = [], []
    for line in open(path, errors='replace'):
        m = TRACE.search(line)
        if m:
            instrs.append(int(m.group(2), 16))
            console.append(line[:m.start()])   # UART characters printed before the trace text
        else:
            console.append(line)
    text = ''.join(console)
    bench = re.search(r'BENCH (\w+): cycles (\d+), instret (\d+)', text)
    redir = re.search(r'BENCH branch: .*redirect (\d+)', text)
    if not bench or not redir:
        sys.exit(f"ERROR: no BENCH lines in {path}")

    # bench_start reads minstret then mcycle, bench_stop reads mcycle then minstret
    mcycle, minstret = (0xB00, 0xC00), (0xB02, 0xC02)
    start = next(k for k, i in enumerate(instrs) if csr_read(i) in mcycle)
    end = max(k for k in range(len(instrs) - 1)
              if csr_read(instrs[k]) in mcycle and csr_read(instrs[k + 1]) in minstret)
    seq = instrs[start + 1:end]

    d1 = sum(1 for k in range(len(seq) - 1)
             if is_load(seq[k]) and rd_of(seq[k]) and rd_of(seq[k]) in srcs(seq[k + 1]))
    d2 = sum(1 for k in range(len(seq) - 2)
             if is_load(seq[k]) and rd_of(seq[k])
             and rd_of(seq[k]) not in srcs(seq[k + 1]) and rd_of(seq[k + 1]) != rd_of(seq[k])
             and rd_of(seq[k]) in srcs(seq[k + 2]))
    mul_use = sum(1 for k in range(len(seq) - 1)
                  if is_mul(seq[k]) and rd_of(seq[k]) and rd_of(seq[k]) in srcs(seq[k + 1]))
    return {
        'name': path.split('/')[-1].split('.')[0],
        'cycles': int(bench.group(2)), 'instret': int(bench.group(3)),
        'redirect': int(redir.group(1)), 'counted': len(seq),
        'load': sum(1 for i in seq if is_load(i)), 'mul': sum(1 for i in seq if is_mul(i)),
        'd1': d1, 'd2': d2, 'mul_use': mul_use,
        'stall_fwd': load_stalls(seq, 2), 'stall_nofwd': load_stalls(seq, 3),
    }


def main(paths):
    rows = [parse(p) for p in sorted(paths)]
    print('| Bench | Instr (BENCH / counted) | Load | Load-use d1 | Load-use d2 | MUL | '
          'MUL-use d1 | Redirect |')
    print('| --- | --- | --- | --- | --- | --- | --- | --- |')
    for r in rows:
        n = r['instret']
        print(f"| {r['name']} | {n} / {r['counted']} | {r['load']} | "
              f"{r['d1']} ({100 * r['d1'] / n:.2f} %) | {r['d2']} | {r['mul']} | "
              f"{r['mul_use']} | {r['redirect']} |")
    print()
    print('| Bench | CPI V1 | ID, fwd | ID, no fwd | EX, fwd | EX, no fwd |')
    print('| --- | --- | --- | --- | --- | --- |')
    for r in rows:
        c, n = r['cycles'], r['instret']
        cells = [f"{c / n:.3f}"]
        for br in (0, r['redirect']):
            for st in (r['stall_fwd'], r['stall_nofwd']):
                c5 = c + br + st
                cells.append(f"{c5 / n:.3f} ({F_SIGNOFF * c5 / c:.0f} / {F_MAX * c5 / c:.0f})")
        print(f"| {r['name']} | " + ' | '.join(cells) + ' |')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
