// muldiv.S - RV32M trong pipeline (docs/spec/core.md mục 4.9).
// Kết quả từng phép đã có riscv-tests rv32um. Test này kiểm tra phần nối với
// pipeline: forward vào và ra khỏi M-unit, load ngay trước lệnh M, lệnh M
// liên tiếp, kết quả vào x0, nhánh dùng kết quả M, ngắt rơi vào giữa phép
// chia (phép bị huỷ rồi chạy lại sau MRET, kết quả không đổi).
// Với ENABLE_M = 0 (đọc từ thanh ghi CFG của tb) lệnh M phải là illegal với
// mtval = mã lệnh và rd không bị ghi.
//
// Trình xử lý (chỉ dùng t3-t6, s10, s11): ngoại lệ -> mcause vào s11 rồi
// quay về s6. Ngắt -> tăng s10, hạ mọi đường ngắt.
#include "test_macros.h"

    .option arch, +m

TEST_CODE_BEGIN
    la   t0, handler
    csrw mtvec, t0
    li   t0, TB_CTRL
    lw   s0, TB_CFG(t0)
    andi s0, s0, 1
    bnez s0, with_m

    // ---- ENABLE_M = 0: lệnh M là illegal --------------------------------------
    li   TESTNUM, 2
    li   a0, 0x55
    li   a1, 3
    li   a2, 5
    la   s6, 1f
2:  mul  a0, a1, a2
    j    fail
1:  CHECK(3, s11, 2)
    CHECK(4, a0, 0x55)
    csrr a3, mtval
    la   t0, 2b
    lw   t1, 0(t0)
    li   TESTNUM, 5
    bne  a3, t1, fail
    la   s6, 1f
    divu a0, a1, a2
    j    fail
1:  CHECK(6, s11, 2)
    CHECK(7, a0, 0x55)
    TEST_PASS

with_m:
    // ---- Forward vào và ra khỏi M-unit ----------------------------------------
    li   a1, 7
    li   a2, 6
    mul  a0, a1, a2                 // 42
    mul  a0, a0, a0                 // 1764, toán hạng forward từ lệnh M
    addi a0, a0, 1                  // 1765, ALU dùng kết quả M ngay
    CHECK(10, a0, 1765)
    li   a1, 100
    div  a3, a0, a1                 // 17
    rem  a4, a0, a1                 // 65
    add  a5, a3, a4                 // 82
    CHECK(11, a5, 82)
    li   a1, -7
    li   a2, 3
    div  a3, a1, a2                 // -2
    rem  a4, a1, a2                 // -1
    mulh a5, a1, a2                 // -1 (nửa cao của -21)
    CHECK(12, a3, -2)
    CHECK(13, a4, -1)
    CHECK(14, a5, -1)

    // Load ngay trước lệnh M (toán hạng forward từ dữ liệu load)
    la   s1, tdat
    lw   a1, 0(s1)
    mul  a0, a1, a1
    CHECK(15, a0, 0xe89)            // 0x3d * 0x3d
    lw   a1, 4(s1)
    divu a0, a1, a1
    CHECK(16, a0, 1)
    lw   a1, 0(s1)
    lw   a2, 4(s1)
    remu a0, a2, a1                 // 0x12345 % 0x3d
    CHECK(17, a0, 0x17)
    // Kết quả M làm dữ liệu store và địa chỉ load
    li   a1, 4
    li   a2, 2
    mul  a0, a1, a2                 // 8
    add  a3, s1, a0
    sw   a0, 0(a3)
    lw   a4, 8(s1)
    CHECK(18, a4, 8)
    // Nhánh dùng kết quả M
    li   TESTNUM, 19
    li   a1, 9
    li   a2, 3
    div  a0, a1, a2
    li   a3, 3
    bne  a0, a3, fail
    // Lệnh M ghi x0 không đổi gì, lệnh sau không bị forward giá trị
    li   a1, 5
    mul  x0, a1, a1
    add  a0, x0, x0
    CHECK(20, a0, 0)
    div  x0, a1, a1
    add  a0, x0, a1
    CHECK(21, a0, 5)

    // ---- Ngắt rơi vào giữa phép chia ----------------------------------------------
    // a0 = 1000003 / 7 + 1000003 % 7 + 123 * 457, chạy lại với 60 thời điểm ngắt.
    li   t0, 0x80
    csrw mie, t0
    li   s2, 0
irq_loop:
    li   TESTNUM, 30
    li   s10, 0
    csrsi mstatus, 8
    li   t0, TB_CTRL
    slli t1, s2, 16
    ori  t1, t1, TB_IRQ_MTI
    sw   t1, TB_IRQ(t0)
    li   a1, 1000003
    li   a2, 7
    li   a3, 123
    li   a4, 457
    div  a5, a1, a2
    rem  a6, a1, a2
    mul  a7, a3, a4
    add  a0, a5, a6
    add  a0, a0, a7
1:  beqz s10, 1b
    csrci mstatus, 8
    CHECK(31, s10, 1)
    CHECK(32, a0, 142857 + 4 + 56211)
    addi s2, s2, 1
    li   t0, 60
    bltu s2, t0, irq_loop

    TEST_PASS
TEST_FAIL

handler:
    csrr t3, mcause
    bltz t3, 1f
    mv   s11, t3                    // ngoại lệ
    csrw mepc, s6
    mret
1:  addi s10, s10, 1                // ngắt
    li   t4, TB_CTRL
    sw   zero, TB_IRQ(t4)
    lw   t3, TB_IRQ(t4)
    lw   t3, TB_IRQ(t4)
    mret

TEST_DATA_BEGIN
tdat:
    .word 0x3d
    .word 0x12345
    .word 0
