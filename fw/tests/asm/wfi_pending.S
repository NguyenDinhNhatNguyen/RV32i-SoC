// wfi_pending.S - WFI and MIE writes with an interrupt that is already pending (D-038,
// docs/spec/core.md sections 4.8 and 4.11). Runs with ENABLE_WFI_SLEEP = 0 and 1.
//   - MIE = 0, MEI pending and enabled in mie: WFI goes on like a NOP, no trap, 0 sleep cycles.
//   - "csrs mstatus, MIE" right before WFI: the interrupt is taken on the WFI (mepc = PC(WFI)),
//     with 0 sleep cycles.
//   - "csrs mstatus, MIE" then "csrc mstatus, MIE": the interrupt is taken on the csrc.
//     Before D-038 the core took no interrupt on the instruction after a mstatus write, so
//     this window never took the interrupt.
//   - The race-free wait loop (csrc MIE, check flag, WFI, csrs MIE, loop) ends after one
//     interrupt. Before D-038 it looped forever.
//   - "csrs mie, MEIE" with MIE = 1: the interrupt is taken on the next instruction.
//
// Handler (uses only t3-t6): mcause -> s2, mepc -> s3, increments s10, lowers every interrupt
// line. If mepc = s8, it returns to s8 + 4 (skips the WFI instead of running it again).
#include "test_macros.h"

#define MCAUSE_MEI 0x8000000b

#define SET_IRQ(val)                \
    li   t0, TB_CTRL;               \
    li   t1, val;                   \
    sw   t1, TB_IRQ(t0);            \
    lw   t1, TB_IRQ(t0);            \
    lw   t1, TB_IRQ(t0)

#define READ_SLEEP(r)               \
    li   t0, TB_CTRL;               \
    lw   r, TB_SLEEP(t0)

TEST_CODE_BEGIN
    la   t0, irq_handler
    csrw mtvec, t0
    li   s8, 0
    li   t0, 0x800                  // MEIE
    csrw mie, t0

    // ---- MIE = 0, MEI pending: WFI is a NOP --------------------------------------------
    li   s10, 0
    SET_IRQ(TB_IRQ_MEI)
    READ_SLEEP(s1)
    wfi
    READ_SLEEP(s4)
    sub  a0, s4, s1
    CHECK(2, a0, 0)                 // No sleep at all
    CHECK(3, s10, 0)                // No trap
    csrr a0, mip
    CHECK(4, a0, 0x800)

    // ---- csrs mstatus right before WFI: trap on the WFI --------------------------------
    la   s8, 1f
    READ_SLEEP(s1)
    csrsi mstatus, 8
1:  wfi
    READ_SLEEP(s4)
    csrci mstatus, 8
    sub  a0, s4, s1
    CHECK(5, a0, 0)
    CHECK(6, s10, 1)
    CHECK(7, s2, MCAUSE_MEI)
    la   x7, 1b
    li   TESTNUM, 8
    bne  s3, x7, fail               // mepc = PC(WFI)
    li   s8, 0

    // ---- csrs mstatus then csrc mstatus: trap on the csrc ------------------------------
    li   s10, 0
    SET_IRQ(TB_IRQ_MEI)
    csrsi mstatus, 8
1:  csrci mstatus, 8
    CHECK(9, s10, 1)
    CHECK(10, s2, MCAUSE_MEI)
    la   x7, 1b
    li   TESTNUM, 11
    bne  s3, x7, fail               // mepc = PC(csrc)

    // ---- Race-free wait loop, the interrupt is already pending -------------------------
    li   s10, 0
    li   a1, 8                      // At most 8 rounds
    SET_IRQ(TB_IRQ_MEI)
2:  csrci mstatus, 8
    bnez s10, 3f
    li   TESTNUM, 12
    beqz a1, fail                   // The loop never takes the interrupt
    addi a1, a1, -1
    wfi
    csrsi mstatus, 8
    j    2b
3:  CHECK(13, s10, 1)
    li   x7, 7
    li   TESTNUM, 14
    bne  a1, x7, fail               // Taken in the first round

    // ---- csrs mie with MIE = 1: trap on the next instruction ---------------------------
    li   s10, 0
    csrw mie, zero
    SET_IRQ(TB_IRQ_MEI)
    csrsi mstatus, 8
    nop
    CHECK(15, s10, 0)               // MEIE = 0: no trap
    li   t0, 0x800
    csrs mie, t0
1:  nop
    csrci mstatus, 8
    CHECK(16, s10, 1)
    la   x7, 1b
    li   TESTNUM, 17
    bne  s3, x7, fail               // mepc = PC(nop after csrs mie)

    TEST_PASS
    TEST_FAIL

irq_handler:
    csrr s2, mcause
    csrr s3, mepc
    addi s10, s10, 1
    bgez s2, fail
    li   t4, TB_CTRL                // Lower every interrupt line
    sw   zero, TB_IRQ(t4)
    lw   t6, TB_IRQ(t4)
    bne  s3, s8, 1f
    addi t5, s8, 4                  // Skip the WFI
    csrw mepc, t5
1:  mret

TEST_DATA_BEGIN
