// dma.S - tests the DMA (RTL-15) in soc_top built with ENABLE_DMA = 1, on tb/soc/tb_soc.v.
//   - Registers: reset values, LEN = 0 sets DONE at once, STATUS write-1-to-clear.
//   - DMEM -> DMEM copy of 64 words, compared with a CPU copy loop of the same words.
//     Both cycle counts (mcycle) are printed on the UART and the DMA must be faster.
//   - DMEM -> accelerator A/B buffers, accelerator run, accelerator C_BUF -> DMEM by DMA,
//     compared with precomputed results (data moves between SRAM and accelerator without CPU).
//   - DMA writes into IMEM through the IMEM data port.
//   - The CPU loads and stores DMEM while a long DMA transfer shares the bus.
//   - Writes to SRC while BUSY are ignored.
//   - DMA done interrupt through IRQC bit 4 (mcause = 0x8000000B).
//   - A bus error stops the transfer with ERR = 1, an unknown DMA offset is an access fault.
//
// Trap handler: records mcause -> s2, mepc -> s3, mtval -> s4, increments s5.
// On an exception it returns to s6. On an external interrupt it reads IRQC PENDING and
// clears DONE at the DMA. The handler uses t0..t2.
#include "test_macros.h"

// gp holds TESTNUM, so the linker must not turn la into gp-relative addressing
// (the .bss buffers sit next to __global_pointer$)
    .option norelax

#define UART        0x20001000
#define IRQC        0x20006000
#define ACCEL       0x30000000
#define DMA         0x40000000
#define IMEM_SPARE  0x00003F00          // Unused end of IMEM

#define D_SRC       0x00
#define D_DST       0x04
#define D_LEN       0x08
#define D_CTRL      0x0C
#define D_STATUS    0x10

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

// Start a transfer of n words from src to dst (registers or immediates through a0..a2)
#define DMA_START(src, dst, n)   \
    li   a0, src;                \
    sw   a0, D_SRC(s0);          \
    li   a0, dst;                \
    sw   a0, D_DST(s0);          \
    li   a0, n;                  \
    sw   a0, D_LEN(s0);          \
    li   a0, 1;                  \
    sw   a0, D_CTRL(s0)

TEST_CODE_BEGIN
    la   t0, handler
    csrw mtvec, t0
    li   s0, DMA
    li   s8, ACCEL
    li   s9, UART
    li   s10, IRQC
    li   a0, 1
    sw   a0, 0xC(s9)                    // UART BAUDDIV = 1 for a fast printout

    // ---- Registers ------------------------------------------------------------------
    lw   a0, D_STATUS(s0)
    CHECK(40, a0, 0)
    lw   a0, D_CTRL(s0)
    CHECK(41, a0, 0)
    sw   zero, D_LEN(s0)
    li   a0, 1
    sw   a0, D_CTRL(s0)                 // LEN = 0: DONE at once
    lw   a0, D_STATUS(s0)
    CHECK(42, a0, 2)
    li   a0, 2
    sw   a0, D_STATUS(s0)
    lw   a0, D_STATUS(s0)
    CHECK(43, a0, 0)

    // ---- Fill the source buffer -----------------------------------------------------
    la   a1, src_buf
    li   a2, 128
    li   a3, 0x13579BDF
3:  sw   a3, 0(a1)
    slli a4, a3, 1                      // Simple LFSR-like pattern
    srli a3, a3, 31
    or   a3, a3, a4
    xori a3, a3, 0x5A5
    addi a1, a1, 4
    addi a2, a2, -1
    bnez a2, 3b

    // ---- DMEM -> DMEM by DMA, timed ---------------------------------------------------
    la   a1, src_buf
    sw   a1, D_SRC(s0)
    la   a1, dst_buf
    sw   a1, D_DST(s0)
    li   a1, 64
    sw   a1, D_LEN(s0)
    li   a1, 1
    csrr s1, mcycle
    sw   a1, D_CTRL(s0)
4:  lw   a1, D_STATUS(s0)
    andi a1, a1, 2
    beqz a1, 4b
    csrr a1, mcycle
    sub  s1, a1, s1                     // s1 = DMA cycles
    li   a1, 2
    sw   a1, D_STATUS(s0)
    li   TESTNUM, 44
    la   a1, src_buf
    la   a2, dst_buf
    li   a3, 64
    jal  ra, cmp_words

    // ---- The same copy by the CPU, timed ----------------------------------------------
    la   a1, src_buf
    la   a2, cpu_buf
    li   a3, 64
    csrr s7, mcycle
5:  lw   a4, 0(a1)
    sw   a4, 0(a2)
    addi a1, a1, 4
    addi a2, a2, 4
    addi a3, a3, -1
    bnez a3, 5b
    csrr a1, mcycle
    sub  s7, a1, s7                     // s7 = CPU cycles
    li   TESTNUM, 45
    la   a1, src_buf
    la   a2, cpu_buf
    li   a3, 64
    jal  ra, cmp_words
    li   TESTNUM, 46
    bgeu s1, s7, fail                   // The DMA must be faster than the CPU loop

    la   a1, msg_dma
    jal  ra, put_str
    mv   a0, s1
    jal  ra, put_hex
    la   a1, msg_cpu
    jal  ra, put_str
    mv   a0, s7
    jal  ra, put_hex
    la   a1, msg_nl
    jal  ra, put_str

    // ---- DMEM -> accelerator, run, accelerator -> DMEM ----------------------------------
    la   a1, mat_a
    sw   a1, D_SRC(s0)
    li   a1, ACCEL + 0x100
    sw   a1, D_DST(s0)
    li   a1, 4
    sw   a1, D_LEN(s0)
    li   a1, 1
    sw   a1, D_CTRL(s0)
    jal  ra, dma_wait
    la   a1, mat_b
    sw   a1, D_SRC(s0)
    li   a1, ACCEL + 0x200
    sw   a1, D_DST(s0)
    li   a1, 1
    sw   a1, D_CTRL(s0)                 // LEN is still 4
    jal  ra, dma_wait
    li   a1, 1
    sw   a1, 0(s8)                      // Accelerator START
    li   TESTNUM, 47
    li   a4, 100
6:  addi a4, a4, -1
    beqz a4, fail
    lw   a1, 4(s8)
    andi a1, a1, 2                      // Accelerator DONE
    beqz a1, 6b
    li   a1, ACCEL + 0x300
    sw   a1, D_SRC(s0)
    la   a1, res_buf
    sw   a1, D_DST(s0)
    li   a1, 16
    sw   a1, D_LEN(s0)
    li   a1, 1
    sw   a1, D_CTRL(s0)
    jal  ra, dma_wait
    li   a1, 2
    sw   a1, 4(s8)                      // Clear accelerator DONE
    li   TESTNUM, 48
    la   a1, mat_c
    la   a2, res_buf
    li   a3, 16
    jal  ra, cmp_words

    // ---- DMA into IMEM through the IMEM data port ----------------------------------------
    la   a1, src_buf
    sw   a1, D_SRC(s0)
    li   a1, IMEM_SPARE
    sw   a1, D_DST(s0)
    li   a1, 4
    sw   a1, D_LEN(s0)
    li   a1, 1
    sw   a1, D_CTRL(s0)
    jal  ra, dma_wait
    li   TESTNUM, 49
    la   a1, src_buf
    li   a2, IMEM_SPARE
    li   a3, 4
    jal  ra, cmp_words

    // ---- CPU traffic on the bus while the DMA runs, SRC write while BUSY ignored ---------
    la   a1, src_buf
    sw   a1, D_SRC(s0)
    la   a1, dst_buf
    sw   a1, D_DST(s0)
    li   a1, 128
    sw   a1, D_LEN(s0)
    li   a1, 1
    sw   a1, D_CTRL(s0)
    la   a1, cpu_buf
    sw   a1, D_SRC(s0)                  // Ignored while busy
    li   a2, 16
    li   a3, 0x1111
7:  sw   a3, 0(a1)                      // CPU stores and loads DMEM during the transfer
    lw   a4, 0(a1)
    li   TESTNUM, 50
    bne  a4, a3, fail
    addi a3, a3, 0x101
    addi a1, a1, 4
    addi a2, a2, -1
    bnez a2, 7b
    lw   a1, D_STATUS(s0)
    andi a1, a1, 1
    li   TESTNUM, 51
    beqz a1, fail                       // Still busy, so the CPU loop really ran in parallel
    jal  ra, dma_wait
    lw   a1, D_SRC(s0)
    la   a2, src_buf
    li   TESTNUM, 52
    bne  a1, a2, fail                   // SRC kept its value
    li   TESTNUM, 53
    la   a1, src_buf
    la   a2, dst_buf
    li   a3, 128
    jal  ra, cmp_words

    // ---- DMA done interrupt through IRQC bit 4 -------------------------------------------
    li   s5, 0
    li   a1, 0x10
    sw   a1, 4(s10)                     // IRQC ENABLE = DMA
    li   a1, 0x800
    csrw mie, a1                        // MEIE
    csrsi mstatus, 8
    la   a1, src_buf
    sw   a1, D_SRC(s0)
    la   a1, cpu_buf
    sw   a1, D_DST(s0)
    li   a1, 8
    sw   a1, D_LEN(s0)
    li   a1, 3
    sw   a1, D_CTRL(s0)                 // START | IRQ_EN
8:  beqz s5, 8b
    csrci mstatus, 8
    csrw mie, zero
    li   TESTNUM, 54
    li   x7, 1
    bne  s5, x7, fail
    li   x7, 0x8000000B
    bne  s2, x7, fail
    lw   a1, D_STATUS(s0)
    CHECK(55, a1, 0)                    // The handler cleared DONE
    sw   zero, D_CTRL(s0)               // IRQ_EN off
    sw   zero, 4(s10)

    // ---- Bus error and bad offset ----------------------------------------------------------
    DMA_START(0x10000000, 0x50000000, 4)    // Unmapped destination
    jal  ra, dma_wait_any
    lw   a1, D_STATUS(s0)
    CHECK(56, a1, 6)                    // ERR | DONE
    li   a1, 6
    sw   a1, D_STATUS(s0)
    lw   a1, D_STATUS(s0)
    CHECK(57, a1, 0)
    EXPECT_TRAP(58, 5, 0x40000014, lw a0, 0x14(s0))

    // Let the UART finish the printout before ending the test
    li   TESTNUM, 59
    li   a4, 20000
9:  addi a4, a4, -1
    beqz a4, fail
    lw   a1, 4(s9)
    andi a1, a1, 6                      // TXE | TXB
    li   x7, 2
    bne  a1, x7, 9b

    TEST_PASS
    TEST_FAIL

// Wait until the DMA is not busy and check that it ended with DONE and no ERR, then clear DONE
dma_wait:
    li   a4, 20000
1:  addi a4, a4, -1
    beqz a4, fail
    lw   a5, D_STATUS(s0)
    andi a6, a5, 1
    bnez a6, 1b
    li   a6, 2
    bne  a5, a6, fail
    sw   a6, D_STATUS(s0)
    ret

// Wait until the DMA is not busy, without checking the result
dma_wait_any:
    li   a4, 20000
1:  addi a4, a4, -1
    beqz a4, fail
    lw   a5, D_STATUS(s0)
    andi a5, a5, 1
    bnez a5, 1b
    ret

// Compare a3 words at a1 and a2, jump to fail on a difference
cmp_words:
1:  lw   a4, 0(a1)
    lw   a5, 0(a2)
    bne  a4, a5, fail
    addi a1, a1, 4
    addi a2, a2, 4
    addi a3, a3, -1
    bnez a3, 1b
    ret

// Send one byte in a0 on the UART, wait while the TX FIFO is full
put_char:
1:  lw   t3, 4(s9)
    andi t3, t3, 1                      // TXF
    bnez t3, 1b
    sw   a0, 0(s9)
    ret

// Send the zero terminated string at a1
put_str:
    mv   t5, ra
1:  lbu  a0, 0(a1)
    beqz a0, 2f
    jal  ra, put_char
    addi a1, a1, 1
    j    1b
2:  mv   ra, t5
    ret

// Send a0 as 8 hex digits
put_hex:
    mv   t5, ra
    mv   t4, a0
    li   t6, 8
1:  srli a0, t4, 28
    li   t3, 10
    blt  a0, t3, 2f
    addi a0, a0, 'a' - 10 - '0'
2:  addi a0, a0, '0'
    jal  ra, put_char
    slli t4, t4, 4
    addi t6, t6, -1
    bnez t6, 1b
    mv   ra, t5
    ret

handler:
    csrr s2, mcause
    csrr s3, mepc
    csrr s4, mtval
    addi s5, s5, 1
    bltz s2, 1f
    csrw mepc, s6                       // Exception: return to the label in s6
    mret
1:  li   t0, IRQC                       // External interrupt: clear at the peripheral
    lw   t1, 0(t0)                      // PENDING
    andi t1, t1, 0x10
    beqz t1, 2f
    li   t0, DMA
    li   t2, 2
    sw   t2, D_STATUS(t0)               // DMA: clear DONE
2:  mret

TEST_DATA_BEGIN
mat_a:
    .word 0x04030201, 0x08070605, 0xfcfdfeff, 0xff00807f
mat_b:
    .word 0xfd010002, 0x05000101, 0x0204f900, 0x01037f80
mat_c:      // Computed in Python from mat_a, mat_b (signed int8)
    .word -508, 489, 25, 17, -1008, 973, 57, 37, 508, -489, -25, -17, 254, -255, 124, -1022
msg_dma:
    .asciz "dma 64 words: "
msg_cpu:
    .asciz " cycles, cpu loop: "
msg_nl:
    .asciz " cycles\n"

    .section .bss
    .align 4
src_buf:
    .space 512
dst_buf:
    .space 512
cpu_buf:
    .space 256
res_buf:
    .space 64
