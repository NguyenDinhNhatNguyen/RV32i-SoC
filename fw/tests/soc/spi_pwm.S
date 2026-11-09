// spi_pwm.S - tests SPI (slot 3) and PWM (slot 5) of soc_top (RTL-13) on tb/soc/tb_soc.v.
// Register map as in rtl/periph/spi_apb.v and pwm_apb.v (docs/spec/periph.md sections 8, 9).
//   - SPI: reset values, CTRL read back, two transfers (mode 0 and mode 3) through the tb
//     loopback spi_mosi -> spi_miso, so DATA reads back the byte that was sent.
//   - PWM: reset values, the output is sampled through GPIO DATA_IN bit 15 (tb pad):
//     DUTY = 0 stays low, DUTY = PERIOD stays high, DUTY = 3 of 8 toggles, disable goes low.
//   - Unknown offsets and byte accesses become access faults.
//
// Trap handler: records mcause -> s2, mepc -> s3, mtval -> s4, increments s5 and returns to s6.
#include "test_macros.h"

#define GPIO        0x20002000
#define SPI         0x20003000
#define PWM         0x20005000

#define S_DATA      0x00
#define S_STATUS    0x04
#define S_CTRL      0x08                // [15:8] clock divider, [2] CPHA, [1] CPOL, [0] cs_n

#define P_PERIOD    0x00
#define P_DUTY      0x04
#define P_CTRL      0x08                // [0] enable

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

// Send byte b on SPI, wait until STATUS.busy = 0 (or fail after a timeout), a0 = DATA
#define SPI_XFER(n, b)           \
    li   TESTNUM, n;             \
    li   a0, b;                  \
    sw   a0, S_DATA(s0);         \
    li   a1, 2000;               \
3:  lw   a0, S_STATUS(s0);       \
    andi a0, a0, 1;              \
    beqz a0, 4f;                 \
    addi a1, a1, -1;             \
    bnez a1, 3b;                 \
    j    fail;                   \
4:  lw   a0, S_DATA(s0)

TEST_CODE_BEGIN
    la   t0, handler
    csrw mtvec, t0
    li   s0, SPI
    li   s1, GPIO
    li   s7, PWM

    // ---- SPI ------------------------------------------------------------------------
    lw   a0, S_CTRL(s0)
    CHECK(60, a0, 1)                    // cs_n idles high
    lw   a0, S_STATUS(s0)
    CHECK(61, a0, 0)
    li   a0, 0x100                      // Divider 1, mode 0, cs_n = 0
    sw   a0, S_CTRL(s0)
    lw   a0, S_CTRL(s0)
    CHECK(62, a0, 0x100)
    SPI_XFER(63, 0xA5)
    CHECK(63, a0, 0xA5)
    li   a0, 0x206                      // Divider 2, CPOL = 1, CPHA = 1 (mode 3), cs_n = 0
    sw   a0, S_CTRL(s0)
    lw   a0, S_CTRL(s0)
    CHECK(64, a0, 0x206)
    SPI_XFER(65, 0x3C)
    CHECK(65, a0, 0x3C)
    li   a0, 1                          // Release cs_n
    sw   a0, S_CTRL(s0)
    lw   a0, S_CTRL(s0)
    CHECK(66, a0, 1)
    EXPECT_TRAP(67, 5, 0x2000300C, lw a0, 0xC(s0))      // Unknown offset: PSLVERR
    EXPECT_TRAP(68, 7, 0x20003000, sb a0, 0(s0))        // Byte write: err from apb_bridge

    // ---- PWM ------------------------------------------------------------------------
    lw   a0, P_PERIOD(s7)
    CHECK(70, a0, 0)
    lw   a0, P_DUTY(s7)
    CHECK(71, a0, 0)
    lw   a0, P_CTRL(s7)
    CHECK(72, a0, 0)
    li   a0, 8
    sw   a0, P_PERIOD(s7)
    sw   zero, P_DUTY(s7)
    li   a0, 1
    sw   a0, P_CTRL(s7)                 // DUTY = 0: always low
    jal  ra, sample
    CHECK(73, a2, 0)
    li   a0, 8
    sw   a0, P_DUTY(s7)                 // DUTY = PERIOD: always high
    jal  ra, sample
    CHECK(74, a2, 64)
    li   a0, 3
    sw   a0, P_DUTY(s7)                 // DUTY = 3 of 8: both levels show up
    jal  ra, sample
    li   TESTNUM, 75
    beqz a2, fail
    li   x7, 64
    beq  a2, x7, fail
    sw   zero, P_CTRL(s7)               // Disable: output back to low
    jal  ra, sample
    CHECK(76, a2, 0)
    lw   a0, P_PERIOD(s7)
    CHECK(77, a0, 8)
    lw   a0, P_DUTY(s7)
    CHECK(78, a0, 3)
    EXPECT_TRAP(79, 5, 0x2000500C, lw a0, 0xC(s7))      // Unknown offset: PSLVERR

    TEST_PASS
    TEST_FAIL

// Wait a few cycles for the GPIO input synchronizer, then read DATA_IN 64 times.
// a2 = number of reads with bit 15 (the tb PWM pad) high. Uses a0, a1, a3.
sample:
    li   a1, 8
1:  addi a1, a1, -1
    bnez a1, 1b
    li   a1, 64
    li   a2, 0
2:  lw   a0, 4(s1)
    srli a0, a0, 15
    andi a0, a0, 1
    add  a2, a2, a0
    addi a1, a1, -1
    bnez a1, 2b
    ret

handler:
    csrr s2, mcause
    csrr s3, mepc
    csrr s4, mtval
    addi s5, s5, 1
    csrw mepc, s6                       // Exception: return to the label in s6
    mret

TEST_DATA_BEGIN
