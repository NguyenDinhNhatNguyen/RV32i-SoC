// wfi.S - WFI sleep (docs/spec/core.md section 4.11).
// Also runs with ENABLE_WFI_SLEEP = 0 (WFI is a NOP, read from the tb CFG register).
// When sleep is enabled it checks:
//   - MIE = 0: the core sleeps until an interrupt enabled in mie arrives, then continues
//     after the WFI and the handler does not run. A pending interrupt that is disabled in
//     mie does not wake the core.
//   - MIE = 1: wake up, then take the interrupt on the instruction after WFI (mepc = PC(WFI)+4).
//   - The sleep cycle count (tb counts core_sleep_o) roughly matches the wait for the interrupt,
//     mcycle keeps running while asleep, and an already pending interrupt gives almost no sleep.
// tb_core also checks that there is no fetch, no bus access and an empty WB for the
// whole sleep.
//
// s0 = 1 if sleep is enabled. The handler (uses only t3-t6, s10, s11) increments s10,
// copies mepc -> s11 and lowers every interrupt line.
#include "test_macros.h"

#define WAIT 200                    // Cycles from the write until the interrupt rises

// a0 = current sleep cycle count
#define READ_SLEEP(r)               \
    li   t0, TB_CTRL;               \
    lw   r, TB_SLEEP(t0)

// The interrupt rises after WAIT cycles
#define IRQ_LATER(val)              \
    li   t0, TB_CTRL;               \
    li   t1, TB_DELAY(WAIT) | (val); \
    sw   t1, TB_IRQ(t0)

#define SET_IRQ(val)                \
    li   t0, TB_CTRL;               \
    li   t1, val;                   \
    sw   t1, TB_IRQ(t0);            \
    lw   t1, TB_IRQ(t0);            \
    lw   t1, TB_IRQ(t0)

// The sleep cycle count d (a register) must be in (lo, hi] when sleep is enabled,
// and 0 otherwise.
#define CHECK_SLEEP(n, d, lo, hi)   \
    li   TESTNUM, n;                \
    bnez s0, 1f;                    \
    bnez d, fail;                   \
    j    2f;                        \
1:  li   x7, lo;                    \
    bgeu x7, d, fail;               \
    li   x7, hi;                    \
    bltu x7, d, fail;               \
2:

TEST_CODE_BEGIN
    la   t0, irq_handler
    csrw mtvec, t0
    li   t0, TB_CTRL
    lw   s0, TB_CFG(t0)
    srli s0, s0, 1
    andi s0, s0, 1

    // ---- MIE = 0: sleep until MTI rises, then continue ------------------------------
    li   s10, 0
    li   t0, 0x80
    csrw mie, t0
    READ_SLEEP(s1)
    csrr s2, mcycle
    IRQ_LATER(TB_IRQ_MTI)
    wfi
    csrr s3, mcycle
    READ_SLEEP(s4)
    sub  a0, s4, s1
    CHECK_SLEEP(2, a0, WAIT / 2, WAIT + 2)
    beqz s0, 1f                     // After sleeping, mip.MTIP must be high
    csrr a0, mip
    CHECK(3, a0, 0x80)
    sub  a0, s3, s2                 // mcycle runs while asleep
    li   TESTNUM, 4
    li   x7, WAIT
    bltu a0, x7, fail
1:  csrr a0, mip                    // WFI is a NOP: wait for the interrupt
    beqz a0, 1b
    CHECK(5, s10, 0)                // MIE = 0: the handler is not entered
    SET_IRQ(0)

    // ---- A pending interrupt disabled in mie does not wake the core -------------------
    li   t0, 0x80                   // MTIE only
    csrw mie, t0
    SET_IRQ(TB_IRQ_MSI | TB_IRQ_MEI)
    READ_SLEEP(s1)
    IRQ_LATER(TB_IRQ_MSI | TB_IRQ_MEI | TB_IRQ_MTI)
    wfi
    READ_SLEEP(s4)
    sub  a0, s4, s1
    CHECK_SLEEP(10, a0, WAIT / 2, WAIT + 2)
1:  csrr a0, mip
    andi a0, a0, 0x80
    beqz a0, 1b
    CHECK(11, s10, 0)
    SET_IRQ(0)

    // ---- An interrupt already pending and enabled: almost no sleep --------------------
    SET_IRQ(TB_IRQ_MTI)
    READ_SLEEP(s1)
    wfi
    READ_SLEEP(s4)
    sub  a0, s4, s1
    li   TESTNUM, 20
    li   x7, 2
    bltu x7, a0, fail
    CHECK(21, s10, 0)
    SET_IRQ(0)

    // ---- MIE = 1: wake up and take the interrupt on the instruction after WFI ----------
    li   s10, 0
    li   s11, 0
    li   t0, 0x800                  // MEIE
    csrw mie, t0
    csrsi mstatus, 8
    READ_SLEEP(s1)
    IRQ_LATER(TB_IRQ_MEI)
    wfi
3:  beqz s10, 3b                    // WFI is a NOP: wait for the interrupt here
    csrci mstatus, 8
    CHECK(30, s10, 1)
    READ_SLEEP(s4)
    sub  a0, s4, s1
    CHECK_SLEEP(31, a0, WAIT / 2, WAIT + 2)
    beqz s0, 1f
    la   t0, 3b                     // mepc = PC(WFI) + 4
    li   TESTNUM, 32
    bne  s11, t0, fail
1:
    // Again with MSI, WFI right after the write (no instruction in between)
    li   s10, 0
    li   t0, 0x8
    csrw mie, t0
    csrsi mstatus, 8
    li   t0, TB_CTRL
    li   t1, TB_DELAY(WAIT) | TB_IRQ_MSI
    sw   t1, TB_IRQ(t0)
    wfi
3:  beqz s10, 3b
    csrci mstatus, 8
    CHECK(33, s10, 1)
    beqz s0, 1f
    la   t0, 3b
    li   TESTNUM, 34
    bne  s11, t0, fail
1:
    TEST_PASS
TEST_FAIL

irq_handler:
    csrr t3, mcause
    csrr s11, mepc
    addi s10, s10, 1
    bgez t3, fail                   // Unexpected exception
    li   t4, TB_CTRL
    sw   zero, TB_IRQ(t4)
    lw   t3, TB_IRQ(t4)
    lw   t3, TB_IRQ(t4)
    mret

TEST_DATA_BEGIN
    .word 0
