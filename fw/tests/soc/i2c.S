// i2c.S - tests the I2C master (RTL-14, slot 4) of soc_top on tb/soc/tb_soc.v.
// Register map as in rtl/periph/i2c_apb.v (docs/spec/periph.md section 10).
// The tb puts tb/models/i2c_slave_model.v (address 0x50, 16-byte memory with a pointer) on
// the open-drain SCL/SDA pins, so these tests also check the pins of soc_top.
//   - Reset values, CTRL read back.
//   - Write frame: START, 0xA0 (0x50, W), pointer 5, 0x3C, 0xC3, STOP. Every byte gets an ACK.
//   - Read frame: START, 0xA0, pointer 5, repeated START, 0xA1 (0x50, R), read 0x3C with ACK,
//     read 0xC3 with NACK and STOP. Reads back what the write frame stored.
//   - Address 0x77: the slave NACKs, STATUS.ack_in = 1.
//   - Unknown offset and byte write become access faults.
//
// Trap handler: records mcause -> s2, mepc -> s3, mtval -> s4, increments s5 and returns to s6.
#include "test_macros.h"

#define I2C         0x20004000

#define I_DATA      0x00
#define I_CMD       0x04                // Write: [0] START [1] STOP [2] READ [3] WRITE
                                        // [4] ACK_OUT (1 = NACK). Read: [0] busy [1] ack_in
#define I_CTRL      0x08                // [15:0] clock divider

#define C_START     0x01
#define C_STOP      0x02
#define C_READ      0x04
#define C_WRITE     0x08
#define C_NACK      0x10

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

// Load DATA with b, start command c, wait until STATUS.busy = 0 (or fail after a timeout).
// a0 = STATUS.ack_in
#define I2C_XFER(n, b, c)        \
    li   TESTNUM, n;             \
    li   a0, b;                  \
    sw   a0, I_DATA(s0);         \
    li   a0, c;                  \
    sw   a0, I_CMD(s0);          \
    li   a1, 20000;              \
3:  lw   a0, I_CMD(s0);          \
    andi a2, a0, 1;              \
    beqz a2, 4f;                 \
    addi a1, a1, -1;             \
    bnez a1, 3b;                 \
    j    fail;                   \
4:  srli a0, a0, 1;              \
    andi a0, a0, 1

TEST_CODE_BEGIN
    la   t0, handler
    csrw mtvec, t0
    li   s0, I2C

    lw   a0, I_CTRL(s0)
    CHECK(90, a0, 0)
    lw   a0, I_CMD(s0)
    CHECK(91, a0, 2)                    // busy = 0, ack_in = 1 after reset
    li   a0, 2                          // SCL tick every 3 cycles
    sw   a0, I_CTRL(s0)
    lw   a0, I_CTRL(s0)
    CHECK(92, a0, 2)

    // Write frame
    I2C_XFER(93, 0xA0, C_START | C_WRITE)
    CHECK(93, a0, 0)
    I2C_XFER(94, 0x05, C_WRITE)
    CHECK(94, a0, 0)
    I2C_XFER(95, 0x3C, C_WRITE)
    CHECK(95, a0, 0)
    I2C_XFER(96, 0xC3, C_WRITE | C_STOP)
    CHECK(96, a0, 0)

    // Read frame with a repeated START
    I2C_XFER(97, 0xA0, C_START | C_WRITE)
    CHECK(97, a0, 0)
    I2C_XFER(98, 0x05, C_WRITE)
    CHECK(98, a0, 0)
    I2C_XFER(99, 0xA1, C_START | C_WRITE)
    CHECK(99, a0, 0)
    I2C_XFER(100, 0, C_READ)
    lw   a0, I_DATA(s0)
    CHECK(100, a0, 0x3C)
    I2C_XFER(101, 0, C_READ | C_NACK | C_STOP)
    lw   a0, I_DATA(s0)
    CHECK(101, a0, 0xC3)

    // Nobody at address 0x77
    I2C_XFER(102, 0xEE, C_START | C_WRITE | C_STOP)
    CHECK(102, a0, 1)

    EXPECT_TRAP(103, 5, 0x2000400C, lw a0, 0xC(s0))      // Unknown offset: PSLVERR
    EXPECT_TRAP(104, 7, 0x20004000, sb a0, 0(s0))        // Byte write: err from apb_bridge

    TEST_PASS
    TEST_FAIL

handler:
    csrr s2, mcause
    csrr s3, mepc
    csrr s4, mtval
    addi s5, s5, 1
    csrw mepc, s6                       // Exception: return to the label in s6
    mret

TEST_DATA_BEGIN
