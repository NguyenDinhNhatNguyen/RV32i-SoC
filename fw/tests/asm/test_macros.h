// test_macros.h - macro cho test assembly tự kiểm tra (kiểu riscv-tests).
// Thanh ghi: gp (x3) = số thứ tự test hiện tại, t0/t1 (x5/x6) bị PASS/FAIL
// ghi đè, x7 chứa giá trị kỳ vọng, x14 chứa kết quả.
// Kết thúc: ghi vào `tohost` (1 = PASS, (test << 1) | 1 = FAIL) rồi lặp tại chỗ.
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

// Ghi `init` vào word tại `base`, ghi `val` bằng lệnh `st` vào base + off,
// rồi kiểm tra cả word (các làn không được chọn phải giữ nguyên).
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

// So thanh ghi r với một hằng số
#define CHECK(n, r, exp)         \
    li   TESTNUM, n;             \
    li   x7, exp;                \
    bne  r, x7, fail

#endif
