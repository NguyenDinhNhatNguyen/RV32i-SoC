// soc.S - tests soc_top (RTL-09) on tb/soc/tb_soc.v. It cannot run on tb_core
// or tb_core_bus because it needs the Timer, the GPIO and the tb_soc GPIO pads.
//   - Timer: mtime is running, CSR time and timeh match mtime (mtime_o goes to the core).
//   - The timer interrupt (mtime >= mtimecmp) wakes WFI, software interrupt through MSIP.
//   - GPIO: DIR, DATA_OUT, DATA_IN through the tb pads, a write to DATA_IN fails.
//   - Accelerator: 4x4 matrix multiply, compared with precomputed results.
//   - UART: reset values, send a string over TX, the tb loops uart_tx back to uart_rx so
//     the whole string comes back on RX with no error flags.
//   - A slot without RTL (IRQC), partial-word UART accesses and unknown offsets of
//     the Timer and UART become access faults.
//
// Trap handler: records mcause -> s2, mepc -> s3, mtval -> s4, increments s5.
// On an exception it returns to s6. On an interrupt it clears the source (MTIMECMP_HI = -1
// or MSIP = 0) and returns to mepc. The handler uses t0..t2, so the main program keeps
// no values in these registers while interrupts are enabled.
#include "test_macros.h"

#define TIMER       0x20000000
#define GPIO        0x20002000
#define UART        0x20001000
#define ACCEL       0x30000000
#define PAD_IN_LO   0x0F96              // Low half of the tb_soc PAD_IN

// The instruction at label 2 must trap with mcause = cause, mtval = tval
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

TEST_CODE_BEGIN
    la   t0, handler
    csrw mtvec, t0
    li   s0, TIMER
    li   s1, GPIO
    li   s8, ACCEL

    // ---- Timer ---------------------------------------------------------------
    li   TESTNUM, 2                     // mtime is running
    lw   a0, 0(s0)
    nop
    nop
    lw   a1, 0(s0)
    bgeu a0, a1, fail

    li   TESTNUM, 3                     // CSR time matches mtime
    lw   a0, 0(s0)
    csrr a1, time
    sub  a2, a1, a0
    bltz a2, fail
    li   x7, 32
    bgeu a2, x7, fail

    li   TESTNUM, 4                     // Write MTIME_LO, time follows
    li   a0, 0x00100000
    sw   a0, 0(s0)
    csrr a1, time
    sub  a2, a1, a0
    bltz a2, fail
    li   x7, 32
    bgeu a2, x7, fail

    li   a0, 5                          // Write MTIME_HI, timeh follows
    sw   a0, 4(s0)
    csrr a1, timeh
    CHECK(5, a1, 5)
    sw   zero, 4(s0)

    // ---- Timer interrupt wakes WFI ----------------------------------------
    li   TESTNUM, 6
    li   s5, 0
    li   a0, -1
    sw   a0, 0xC(s0)                    // MTIMECMP_HI = -1 first to avoid a false interrupt
    lw   a0, 0(s0)
    addi a0, a0, 300
    sw   a0, 8(s0)                      // MTIMECMP_LO = mtime + 300
    lw   a1, 4(s0)
    sw   a1, 0xC(s0)                    // MTIMECMP_HI = mtime_hi
    li   a0, 0x80
    csrw mie, a0                        // MTIE
    csrsi mstatus, 8                    // MIE
3:  wfi
    beqz s5, 3b
    csrci mstatus, 8
    csrw mie, zero
    li   x7, 1
    bne  s5, x7, fail
    li   x7, 0x80000007
    bne  s2, x7, fail
    lw   a0, 0xC(s0)                    // The handler cleared the source
    CHECK(7, a0, 0xFFFFFFFF)

    // ---- Software interrupt through MSIP -------------------------------------------
    li   TESTNUM, 8
    li   s5, 0
    li   a0, 0x8
    csrw mie, a0                        // MSIE
    csrsi mstatus, 8
    li   a0, 1
    sw   a0, 0x10(s0)                   // MSIP = 1
4:  beqz s5, 4b
    csrci mstatus, 8
    csrw mie, zero
    li   x7, 1
    bne  s5, x7, fail
    li   x7, 0x80000003
    bne  s2, x7, fail
    lw   a0, 0x10(s0)
    CHECK(9, a0, 0)

    // ---- GPIO --------------------------------------------------------------
    li   a0, 0xFFFF0000
    sw   a0, 8(s1)                      // DIR: the high half is output
    li   a1, 0x12345678
    sw   a1, 0(s1)                      // DATA_OUT
    nop
    nop
    lw   a2, 4(s1)                      // DATA_IN through the 2-flop synchronizer
    CHECK(10, a2, 0x12340000 | PAD_IN_LO)
    lw   a3, 0(s1)
    CHECK(11, a3, 0x12345678)
    lw   a3, 8(s1)
    CHECK(12, a3, 0xFFFF0000)
    EXPECT_TRAP(13, 7, 0x20002004, sw a0, 4(s1))        // DATA_IN is read only

    // ---- Accelerator --------------------------------------------------------
    lw   a0, 8(s8)
    CHECK(14, a0, 0x0408140A)           // INFO = {N, DW, AW, LAT}
    la   a1, mat_a
    la   a2, mat_b
    li   a3, 0
5:  add  t2, a1, a3
    lw   t3, 0(t2)
    add  t2, s8, a3
    sw   t3, 0x100(t2)
    add  t2, a2, a3
    lw   t3, 0(t2)
    add  t2, s8, a3
    sw   t3, 0x200(t2)
    addi a3, a3, 4
    li   t2, 16
    bne  a3, t2, 5b
    li   t2, 1
    sw   t2, 0(s8)                      // START
    li   TESTNUM, 15
    li   a4, 100
6:  addi a4, a4, -1
    beqz a4, fail
    lw   t2, 4(s8)
    andi t2, t2, 2                      // DONE
    beqz t2, 6b
    li   TESTNUM, 16
    la   a1, mat_c
    li   a3, 0
7:  add  t2, s8, a3
    lw   t3, 0x300(t2)
    add  t2, a1, a3
    lw   t4, 0(t2)
    bne  t3, t4, fail
    addi a3, a3, 4
    li   t2, 64
    bne  a3, t2, 7b
    li   t2, 2
    sw   t2, 4(s8)                      // Clear DONE

    // ---- UART ---------------------------------------------------------------
    li   s9, UART
    lw   a0, 8(s9)
    CHECK(20, a0, 0x3)                  // CTRL sau reset: TXEN, RXEN
    lw   a0, 0xC(s9)
    CHECK(21, a0, 27)                   // BAUDDIV after reset: 115200 baud at 50 MHz
    li   a0, 1
    sw   a0, 0xC(s9)                    // BAUDDIV = 1: 16 cycles per bit for fast simulation
    la   a1, msg                        // Push the whole string into the TX FIFO (8 bytes)
8:  lbu  t2, 0(a1)
    beqz t2, 9f
    sw   t2, 0(s9)
    addi a1, a1, 1
    j    8b
9:  li   TESTNUM, 22                    // Receive each byte back through uart_tx -> uart_rx
    la   a1, msg
10: lbu  t3, 0(a1)
    beqz t3, 12f
    li   a4, 2000
11: addi a4, a4, -1
    beqz a4, fail
    lw   t2, 4(s9)
    andi t2, t2, 0x10                   // RXNE
    beqz t2, 11b
    lw   t2, 0(s9)
    bne  t2, t3, fail
    addi a1, a1, 1
    j    10b
12: lw   a0, 4(s9)
    andi a0, a0, 0xE0                   // OVR, FE, TXOVF
    CHECK(23, a0, 0)

    // ---- A slot without RTL and bad accesses become access faults -----------------
    li   a5, UART
    EXPECT_TRAP(17, 7, 0x20001000, sb a0, 0(a5))        // APB is word access only
    EXPECT_TRAP(24, 5, 0x20001010, lw a0, 0x10(a5))     // UART: PSLVERR
    li   a5, 0x20006000
    EXPECT_TRAP(18, 5, 0x20006000, lw a0, 0(a5))        // IRQC (RTL-11)
    EXPECT_TRAP(19, 5, 0x20000014, lw a0, 0x14(s0))     // Timer: PSLVERR

    TEST_PASS
    TEST_FAIL

handler:
    csrr s2, mcause
    csrr s3, mepc
    csrr s4, mtval
    addi s5, s5, 1
    bltz s2, 1f
    csrw mepc, s6                       // Exception: return to the label in s6
    mret
1:  li   t0, TIMER
    andi t1, s2, 0x1f
    li   t2, 7
    bne  t1, t2, 2f
    li   t1, -1
    sw   t1, 0xC(t0)                    // Timer interrupt: MTIMECMP_HI = -1
    mret
2:  sw   zero, 0x10(t0)                 // Software interrupt: MSIP = 0
    mret

TEST_DATA_BEGIN
mat_a:
    .word 0x04030201, 0x08070605, 0xfcfdfeff, 0xff00807f
mat_b:
    .word 0xfd010002, 0x05000101, 0x0204f900, 0x01037f80
mat_c:      // Computed in Python from mat_a, mat_b (signed int8)
    .word -508, 489, 25, 17, -1008, 973, 57, 37, 508, -489, -25, -17, 254, -255, 124, -1022
msg:
    .asciz "soc ok\n"
