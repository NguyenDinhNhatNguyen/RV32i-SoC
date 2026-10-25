// trap.S - CSRs and exceptions (docs/spec/core.md sections 4.7, 4.8).
// Checks the reset value and read/write mask of each CSR, unknown CSRs
// and writes to read-only CSRs, every kind of synchronous exception (mcause, mepc, mtval, rd
// not written, memory unchanged), mstatus on trap and MRET, the mcycle and
// minstret counters (trapped instructions do not count), and time.
//
// The trap handler records mcause -> s2, mepc -> s3, mtval -> s4,
// mstatus -> s7, increments s5, then returns to the address in s6.
#include "test_macros.h"

// The instruction in `...` (placed at label 2) must trap with mcause = cause, mtval = tval.
#define EXPECT_TRAP(n, cause, tval, ...) \
    li   TESTNUM, n;             \
    li   s5, 0;                  \
    la   s6, 1f;                 \
2:  __VA_ARGS__;                 \
    j    fail;                   \
1:  li   x7, 1;                  \
    bne  s5, x7, fail;           \
    li   x7, cause;              \
    bne  s2, x7, fail;           \
    la   x7, 2b;                 \
    bne  s3, x7, fail;           \
    li   x7, tval;               \
    bne  s4, x7, fail

// Like EXPECT_TRAP, but mtval must equal the PC of the trapping instruction (ebreak)
#define EXPECT_TRAP_PC(n, cause, ...) \
    li   TESTNUM, n;             \
    li   s5, 0;                  \
    la   s6, 1f;                 \
2:  __VA_ARGS__;                 \
    j    fail;                   \
1:  li   x7, 1;                  \
    bne  s5, x7, fail;           \
    li   x7, cause;              \
    bne  s2, x7, fail;           \
    la   x7, 2b;                 \
    bne  s3, x7, fail;           \
    bne  s4, x7, fail

// CSR instructions as fixed machine code (to check mtval = instruction bits)
#define CSRRS_A0_7C0      0x7c002573      // csrrs a0, 0x7c0, x0  (CSR does not exist)
#define CSRRW_X0_CYCLE_A0 0xc0051073      // csrrw x0, cycle, a0  (write to a read-only CSR)
#define CSRRSI_A0_MVID_1  0xf110e573      // csrrsi a0, mvendorid, 1
#define ILLEGAL_WORD      0x12345677      // Opcode 1110111 is not supported

TEST_CODE_BEGIN
    // ---- Values after reset ------------------------------------------------
    csrr a0, mtvec
    CHECK(2, a0, 0)
    csrr a0, mstatus
    CHECK(3, a0, 0x1800)            // MPP = 11, MIE = MPIE = 0
    csrr a0, mie
    CHECK(4, a0, 0)
    csrr a0, mip
    CHECK(5, a0, 0)
    csrr a0, mhartid
    CHECK(6, a0, 0)
    csrr a0, mvendorid
    CHECK(7, a0, 0)
    csrr a0, marchid
    CHECK(8, a0, 0)
    csrr a0, mimpid
    CHECK(9, a0, 0)

    // misa = 0x40000100, plus the M bit with ENABLE_M
    li   t0, TB_CTRL
    lw   t1, TB_CFG(t0)
    andi t1, t1, 1
    slli t1, t1, 12
    li   t2, 0x40000100
    or   t2, t2, t1
    csrr a0, misa
    li   TESTNUM, 10
    bne  a0, t2, fail
    li   a1, -1                     // Writes to misa are ignored
    csrw misa, a1
    csrr a0, misa
    li   TESTNUM, 11
    bne  a0, t2, fail

    // ---- Read/write masks -----------------------------------------------------
    li   a1, -1
    csrw mstatus, a1
    csrr a0, mstatus
    CHECK(12, a0, 0x1888)           // Only MIE and MPIE are writable
    csrw mstatus, zero
    csrr a0, mstatus
    CHECK(13, a0, 0x1800)
    csrw mie, a1
    csrr a0, mie
    CHECK(14, a0, 0x888)
    csrw mie, zero
    csrw mip, a1                    // mip is read only and follows the interrupt pins
    csrr a0, mip
    CHECK(15, a0, 0)
    li   a1, 0x12345677
    csrw mtvec, a1
    csrr a0, mtvec
    CHECK(16, a0, 0x12345674)       // Direct mode, bits 1:0 = 0
    csrw mepc, a1
    csrr a0, mepc
    CHECK(17, a0, 0x12345674)
    csrw mscratch, a1
    csrr a0, mscratch
    CHECK(18, a0, 0x12345677)
    csrw mtval, a1
    csrr a0, mtval
    CHECK(19, a0, 0x12345677)
    li   a1, 0x8000000b
    csrw mcause, a1
    csrr a0, mcause
    CHECK(20, a0, 0x8000000b)
    csrrwi a0, mscratch, 0x15       // CSRRWI returns the old value
    CHECK(21, a0, 0x12345677)
    csrrsi a0, mscratch, 0x0a
    CHECK(22, a0, 0x15)
    csrrci a0, mscratch, 0x05
    CHECK(23, a0, 0x1f)
    csrr a0, mscratch
    CHECK(24, a0, 0x1a)
    li   a1, 0xf0
    csrrs a0, mscratch, a1          // Forward the CSR value to the next instruction
    addi a0, a0, 1
    CHECK(25, a0, 0x1b)
    csrr a0, mscratch
    CHECK(26, a0, 0xfa)

    // ---- Install the trap handler -------------------------------------------------
    la   t0, handler
    csrw mtvec, t0

    // ---- Synchronous exceptions -------------------------------------------------------
    EXPECT_TRAP(30, 11, 0, ecall)
    EXPECT_TRAP_PC(31, 3, ebreak)   // mtval = PC of the ebreak (D-035)
    EXPECT_TRAP(32, 2, ILLEGAL_WORD, .word ILLEGAL_WORD)
    EXPECT_TRAP(33, 2, 0, .word 0)

    li   a0, 0x55                   // rd is not written on a bad CSR
    EXPECT_TRAP(34, 2, CSRRS_A0_7C0, .word CSRRS_A0_7C0)
    CHECK(35, a0, 0x55)
    EXPECT_TRAP(36, 2, CSRRW_X0_CYCLE_A0, .word CSRRW_X0_CYCLE_A0)
    EXPECT_TRAP(37, 2, CSRRSI_A0_MVID_1, .word CSRRSI_A0_MVID_1)
    CHECK(38, a0, 0x55)
    csrrsi a0, mvendorid, 0         // Reading a read-only CSR (no write) is legal
    CHECK(39, a0, 0)
    csrrs x0, cycle, x0

    // Misaligned load/store: mtval = address, rd and memory unchanged
    la   s1, tdat
    li   a0, 0x66
    EXPECT_TRAP(40, 4, 0x10000002, lw a0, 2(s1))
    CHECK(41, a0, 0x66)
    EXPECT_TRAP(42, 4, 0x10000003, lhu a0, 3(s1))
    EXPECT_TRAP(43, 6, 0x10000001, sh a0, 1(s1))
    EXPECT_TRAP(44, 6, 0x10000006, sw a0, 6(s1))
    lw   a1, 0(s1)
    CHECK(45, a1, 0x11223344)
    lw   a1, 4(s1)
    CHECK(46, a1, 0x55667788)

    // Bus error: unmapped address
    li   s1, 0x40000000
    EXPECT_TRAP(47, 5, 0x40000004, lw a0, 4(s1))
    CHECK(48, a0, 0x66)
    EXPECT_TRAP(49, 7, 0x40000008, sb a0, 8(s1))

    // Misaligned jump: mepc = the jump, mtval = the target, rd is not written
    li   a0, 0x77
    EXPECT_TRAP(50, 0, 2, jalr a0, 2(zero))
    CHECK(51, a0, 0x77)
    // Fetch error: mepc = mtval = the bad address, the jump still writes rd
    li   TESTNUM, 52
    li   s5, 0
    la   s6, 1f
    li   s1, 0x40000000
    la   a1, 3f
3:  jalr a0, 0(s1)
    j    fail
1:  li   x7, 1
    bne  s5, x7, fail
    CHECK(53, s2, 1)
    CHECK(54, s3, 0x40000000)
    CHECK(55, s4, 0x40000000)
    addi a1, a1, 4
    li   TESTNUM, 56
    bne  a0, a1, fail

    // ---- mstatus on trap and MRET ------------------------------------------------
    csrsi mstatus, 8                // MIE = 1 (no interrupt pending)
    EXPECT_TRAP(60, 11, 0, ecall)
    CHECK(61, s7, 0x1880)           // trong handler: MIE = 0, MPIE = 1
    csrr a0, mstatus
    CHECK(62, a0, 0x1888)           // MRET: MIE = MPIE, MPIE = 1
    csrw mstatus, zero
    EXPECT_TRAP(63, 11, 0, ecall)
    CHECK(64, s7, 0x1800)
    csrr a0, mstatus
    CHECK(65, a0, 0x1880)

    csrw mstatus, zero              // Direct MRET
    la   t0, 1f
    csrw mepc, t0
    li   TESTNUM, 66
    mret
    j    fail
1:  csrr a0, mstatus
    CHECK(67, a0, 0x1880)
    csrw mstatus, zero

    // ---- minstret, instret ---------------------------------------------------------
    csrr a0, minstret
    nop
    nop
    nop
    csrr a1, minstret
    sub  a0, a1, a0
    CHECK(70, a0, 4)
    csrr a0, minstret
    csrr a1, instret
    sub  a0, a1, a0
    CHECK(71, a0, 1)
    csrr a0, minstreth
    csrr a1, instreth
    li   TESTNUM, 72
    bne  a0, a1, fail
    // Trapped instructions do not count: a short handler with only 2 instructions
    la   t0, short_handler
    csrw mtvec, t0
    la   s6, 1f
    csrr a0, minstret
    ecall
1:  csrr a1, minstret
    sub  a0, a1, a0
    CHECK(73, a0, 3)                // csrr, csrw (handler), mret
    la   t0, handler
    csrw mtvec, t0

    // ---- mcycle, cycle, time --------------------------------------------------------
    csrr a0, mcycle
    nop
    nop
    nop
    csrr a1, mcycle
    sub  a0, a1, a0
    li   TESTNUM, 80
    li   x7, 4
    bltu a0, x7, fail               // At least 1 cycle per instruction
    csrr a0, mcycle
    csrr a1, cycle
    li   TESTNUM, 81
    bgeu a0, a1, fail
    csrwi mcycle, 0                 // Writing mcycle replaces the increment
    csrr a0, mcycle
    li   TESTNUM, 82
    li   x7, 20
    bgeu a0, x7, fail
    li   a1, 5                      // Carry from the low half into the high half
    csrw mcycleh, a1
    li   a1, -8
    csrw mcycle, a1
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    csrr a0, mcycleh
    CHECK(83, a0, 6)
    csrr a1, cycleh
    CHECK(84, a1, 6)
    li   a1, 7                      // minstreth is writable
    csrw minstreth, a1
    csrr a0, minstreth
    CHECK(85, a0, 7)
    csrw minstreth, zero
    csrr a0, time
    csrr a1, time
    li   TESTNUM, 86
    bgeu a0, a1, fail               // mtime_i increments every cycle in the tb
    csrr a0, timeh
    CHECK(87, a0, 0)

    TEST_PASS
TEST_FAIL

handler:
    csrr s2, mcause
    csrr s3, mepc
    csrr s4, mtval
    csrr s7, mstatus
    addi s5, s5, 1
    csrw mepc, s6
    mret

short_handler:
    csrw mepc, s6
    mret

TEST_DATA_BEGIN
tdat:
    .word 0x11223344
    .word 0x55667788
