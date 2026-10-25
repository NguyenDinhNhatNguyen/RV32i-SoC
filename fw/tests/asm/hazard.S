// hazard.S - 3-stage pipeline hazards (docs/spec/core.md sections 4.3-4.6).
// Every dependency is back to back (the consumer right after the producer), so the value
// must go through the WB -> EX forward. With +strict_timing, tb_core also checks
// that there is no load-use stall and exactly one bubble after a taken jump. Runs
// with injected bus stalls check the hold register.
#include "test_macros.h"

TEST_CODE_BEGIN
    nop                         // First word = 0x00000013, read back in test 90

    // ---- Forward ALU -> ALU -----------------------------------------------
    li   TESTNUM, 2             // rs1
    li   x10, 5
    addi x11, x10, 3
    CHECK(2, x11, 8)
    li   x10, 5                 // rs2
    li   x12, 100
    sub  x11, x12, x10
    CHECK(3, x11, 95)
    li   x10, 21                // Both operands from the same instruction
    add  x11, x10, x10
    CHECK(4, x11, 42)
    li   x10, 1                 // Chain: this result feeds the next instruction
    addi x10, x10, 1
    addi x10, x10, 1
    slli x10, x10, 4
    xori x10, x10, 0x7
    CHECK(5, x10, 0x37)
    li   x10, 1                 // The newest value wins (WB over regfile)
    li   x10, 2
    add  x11, x10, x0
    CHECK(6, x11, 2)
    li   x10, 9                 // A write to x0 is never forwarded
    addi x0, x10, 1
    add  x11, x0, x0
    CHECK(7, x11, 0)
    li   x10, 3                 // Forward into a compare
    slt  x11, x10, x0
    sltu x12, x0, x10
    add  x11, x11, x12
    CHECK(8, x11, 1)

    // ---- Load -> immediate use (no stall, data forwarded from the bus) -----------
    la   x1, hdat
    lw   x10, 0(x1)             // 0x11111111
    addi x11, x10, 1
    CHECK(10, x11, 0x11111112)
    lw   x10, 4(x1)             // 0x22222222, used as rs2
    sub  x11, x0, x10
    CHECK(11, x11, 0xddddddde)
    lw   x10, 0(x1)             // Used as both rs1 and rs2
    add  x11, x10, x10
    CHECK(12, x11, 0x22222222)
    lb   x10, 8(x1)             // 0x80 sign-extended, then used
    addi x11, x10, 0
    CHECK(13, x11, 0xffffff80)
    lhu  x10, 10(x1)            // 0xbeef zero-extended, then used
    srli x11, x10, 8
    CHECK(14, x11, 0xbe)

    // ---- Load -> load (address dependency), back-to-back loads ---------------
    la   x1, ptr0
    lw   x10, 0(x1)             // ptr1
    lw   x11, 0(x10)            // ptr2
    lw   x12, 0(x11)            // 0x5a5a1234
    CHECK(20, x12, 0x5a5a1234)
    la   x1, hdat               // Four loads in four cycles, then add
    lw   x10, 0(x1)
    lw   x11, 4(x1)
    lw   x12, 12(x1)
    lw   x13, 16(x1)
    add  x10, x10, x11
    add  x10, x10, x12
    add  x10, x10, x13
    CHECK(21, x10, 0x33333333 + 0x01020304 + 0x10203040)

    // ---- Load -> store (data and address) -----------------------------------------
    la   x1, hdat
    la   x2, scratch
    lw   x10, 0(x1)             // Store data comes from a load
    sw   x10, 0(x2)
    lw   x11, 0(x2)
    CHECK(30, x11, 0x11111111)
    la   x1, pscratch
    lw   x10, 0(x1)             // Store address comes from a load (-> scratch + 4)
    li   x12, 0x600dcafe
    sw   x12, 0(x10)
    lw   x11, 4(x2)
    CHECK(31, x11, 0x600dcafe)
    lw   x10, 0(x1)             // Same register as address and data
    sw   x10, 0(x10)
    lw   x11, 4(x2)
    bne  x11, x10, fail_31
    li   x10, 0x77              // ALU result straight into store data
    sb   x10, 1(x2)
    lw   x11, 0(x2)
    CHECK(32, x11, 0x11117711)

    // ---- Store -> load to the same address, back to back ---------------------
    la   x2, scratch
    li   x10, 0x01234567
    sw   x10, 8(x2)
    lw   x11, 8(x2)
    CHECK(40, x11, 0x01234567)
    li   x10, 0xabcd
    sh   x10, 10(x2)
    lh   x11, 10(x2)
    CHECK(41, x11, 0xffffabcd)
    lw   x11, 8(x2)
    CHECK(42, x11, 0xabcd4567)

    // ---- Branches with forwarded operands --------------------------------------
    li   TESTNUM, 50
    li   x10, 3
    li   x11, 3
    bne  x10, x11, fail         // Operand from WB (ALU)
    la   x1, hdat
    lw   x10, 0(x1)
    li   x11, 0x11111111
    bne  x10, x11, fail         // Not taken: operand from a load
    lw   x10, 0(x1)
    beq  x10, x11, 1f           // Taken: operand from a load
    j    fail
1:  li   TESTNUM, 51
    lw   x10, 4(x1)
    blt  x10, x0, fail          // 0x22222222 > 0
    lb   x10, 8(x1)
    bge  x10, x0, fail          // 0xffffff80 < 0

    // ---- JAL/JALR with forwarding ------------------------------------------------
    li   TESTNUM, 60
    jal  x10, 1f                // The return address is used right away
1:  la   x7, 1b
    bne  x10, x7, fail
    li   TESTNUM, 61
    la   x10, 2f                // The jalr target comes from the addi of `la`
    jalr x11, 0(x10)
    j    fail
2:  li   TESTNUM, 62
    la   x1, jtab
    lw   x10, 0(x1)             // The jalr target comes straight from a load
    jalr x0, 0(x10)
    j    fail
jt_target0:
    li   TESTNUM, 63
    lw   x10, 4(x1)
    jalr x11, 8(x10)            // Load + offset, the return address is forwarded below
    j    fail
    j    fail
jt_after:
    la   x7, jt_target0 + 12    // Address after the jalr
    bne  x11, x7, fail

    // ---- Wrong-path instructions after a jump have no effect --------------
    li   TESTNUM, 70
    li   x10, 0
    la   x2, scratch
    li   x12, 0x0bad0bad
    sw   x0, 12(x2)
    beq  x0, x0, 1f
    sw   x12, 12(x2)            // Must not be written
    addi x10, x10, 1            // Must not execute
1:  lw   x11, 12(x2)
    bnez x11, fail
    bnez x10, fail
    li   TESTNUM, 71
    j    1f
    addi x10, x10, 1
1:  jal  x0, 2f
    lw   x10, 0(x2)
2:  bnez x10, fail

    // ---- Jump to a jump, branch at the target ------------------------
    li   TESTNUM, 72
    li   x10, 0
    j    1f
    j    fail
1:  j    2f
    j    fail
2:  beq  x0, x0, 3f
    j    fail
3:  bne  x10, x0, fail
    addi x10, x10, 1
    beq  x10, x0, fail          // Not taken right after the jump chain
    CHECK(73, x10, 1)

    // ---- Short loop (backward branch after a few cycles) ----------------------
    li   TESTNUM, 80
    li   x10, 0
    li   x11, 16
1:  addi x10, x10, 3
    addi x11, x11, -1
    bnez x11, 1b
    CHECK(80, x10, 48)
    li   x10, 0                 // Load-dependent loop: walk a linked list
    la   x11, node0
1:  lw   x12, 4(x11)            // Value
    add  x10, x10, x12
    lw   x11, 0(x11)            // Next element
    bnez x11, 1b
    CHECK(81, x10, 0x111)

    // ---- Data access to IMEM, then use it or fetch -----------------------------------
    la   x1, _start
    lw   x10, 0(x1)
    addi x11, x10, 0
    li   x7, 0x00000013
    li   TESTNUM, 90
    bne  x11, x7, fail
    lw   x10, 0(x1)             // IMEM access, then a taken branch
    beq  x10, x7, 1f
    j    fail
1:

    TEST_PASS

fail_31:
    li   TESTNUM, 31
    TEST_FAIL

TEST_DATA_BEGIN
    .align 4
hdat:
    .word 0x11111111            // +0
    .word 0x22222222            // +4
    .word 0xbeef0080            // +8: byte 0x80, half 0xbeef at +10
    .word 0x01020304            // +12
    .word 0x10203040            // +16
ptr0:
    .word ptr1
ptr1:
    .word ptr2
ptr2:
    .word 0x5a5a1234
pscratch:
    .word scratch + 4
jtab:
    .word jt_target0
    .word jt_after - 8
node0:
    .word node1, 0x001
node1:
    .word node2, 0x010
node2:
    .word 0, 0x100
scratch:
    .word 0, 0, 0, 0
