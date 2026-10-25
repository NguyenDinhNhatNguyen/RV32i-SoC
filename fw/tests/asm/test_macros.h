// test_macros.h - macros for self-checking assembly tests (riscv-tests style).
// Registers: gp (x3) = current test number, t0/t1 (x5/x6) are clobbered by PASS/FAIL,
// x7 holds the expected value and x14 the result.
// End: write to `tohost` (1 = PASS, (test << 1) | 1 = FAIL), then loop in place.
#ifndef TEST_MACROS_H
#define TEST_MACROS_H

#define TESTNUM gp

#define TEST_CODE_BEGIN          \
    .section .text.init, "ax";   \
    .globl _start;               \
_start:

#define TEST_PASS                \
    li   t0, 1;                  \
    la   t1, tohost;             \
    sw   t0, 0(t1);              \
1:  j    1b

#define TEST_FAIL                \
fail:                            \
    slli t0, TESTNUM, 1;         \
    ori  t0, t0, 1;              \
    la   t1, tohost;             \
    sw   t0, 0(t1);              \
1:  j    1b

#define TEST_DATA_BEGIN          \
    .section .tohost, "aw", @progbits; \
    .align 6;                    \
    .globl tohost;               \
tohost: .word 0;                 \
    .align 6;                    \
    .data

// rd = inst(v1, v2)
#define TEST_RR(n, inst, exp, v1, v2) \
    li   TESTNUM, n;             \
    li   x1, v1;                 \
    li   x2, v2;                 \
    inst x14, x1, x2;            \
    li   x7, exp;                \
    bne  x14, x7, fail

// rd = inst(v1, imm)
#define TEST_RI(n, inst, exp, v1, imm) \
    li   TESTNUM, n;             \
    li   x1, v1;                 \
    inst x14, x1, imm;           \
    li   x7, exp;                \
    bne  x14, x7, fail

// rd = inst(imm) (LUI)
#define TEST_U(n, inst, exp, imm) \
    li   TESTNUM, n;             \
    inst x14, imm;               \
    li   x7, exp;                \
    bne  x14, x7, fail

#define TEST_BR_TAKEN(n, inst, v1, v2) \
    li   TESTNUM, n;             \
    li   x1, v1;                 \
    li   x2, v2;                 \
    inst x1, x2, 1f;             \
    j    fail;                   \
1:

#define TEST_BR_NOT_TAKEN(n, inst, v1, v2) \
    li   TESTNUM, n;             \
    li   x1, v1;                 \
    li   x2, v2;                 \
    inst x1, x2, fail

// rd = load(base + off)
#define TEST_LD(n, inst, exp, off, base) \
    li   TESTNUM, n;             \
    la   x1, base;               \
    inst x14, off(x1);           \
    li   x7, exp;                \
    bne  x14, x7, fail

// Write `init` to the word at `base`, write `val` with the `st` instruction to base + off,
// then check the whole word (lanes not selected must keep their value).
#define TEST_ST(n, st, init, val, off, base, exp_word) \
    li   TESTNUM, n;             \
    la   x1, base;               \
    li   x2, init;               \
    sw   x2, 0(x1);              \
    li   x2, val;                \
    st   x2, off(x1);            \
    lw   x14, 0(x1);             \
    li   x7, exp_word;           \
    bne  x14, x7, fail

// tb_core control block, simulation only (matches CORE_TB_CTRL_BASE
// in tb/core/core_tb_map.vh)
#define TB_CTRL         0x2FFF0000
#define TB_IRQ          0x0     // Write: interrupt level + wait cycles, read: current level
#define TB_SLEEP        0x4     // Read: total cycles with core_sleep_o = 1
#define TB_CFG          0x8     // Read: bit 0 = ENABLE_M, bit 1 = ENABLE_WFI_SLEEP
#define TB_IRQ_MSI      (1 << 3)
#define TB_IRQ_MTI      (1 << 7)
#define TB_IRQ_MEI      (1 << 11)
#define TB_DELAY(n)     ((n) << 16)

// Compare register r with a constant
#define CHECK(n, r, exp)         \
    li   TESTNUM, n;             \
    li   x7, exp;                \
    bne  r, x7, fail

#endif
