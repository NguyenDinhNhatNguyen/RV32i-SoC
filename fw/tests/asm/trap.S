// trap.S - CSR và ngoại lệ (docs/spec/core.md mục 4.7, 4.8).
// Kiểm tra giá trị reset và mặt nạ đọc/ghi của từng CSR, CSR không tồn tại
// và ghi CSR chỉ đọc, mọi loại ngoại lệ đồng bộ (mcause, mepc, mtval, rd
// không bị ghi, bộ nhớ không đổi), mstatus khi trap và MRET, bộ đếm mcycle,
// minstret (lệnh bị trap không tính), time.
//
// Trình xử lý trap ghi lại mcause -> s2, mepc -> s3, mtval -> s4,
// mstatus -> s7, tăng s5, rồi quay về địa chỉ trong s6.
#include "test_macros.h"

// Lệnh trong `...` (đặt ở nhãn 2) phải trap với mcause = cause, mtval = tval.
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

// Lệnh csr bằng mã máy cố định (để kiểm tra mtval = mã lệnh)
#define CSRRS_A0_7C0      0x7c002573      // csrrs a0, 0x7c0, x0  (CSR không tồn tại)
#define CSRRW_X0_CYCLE_A0 0xc0051073      // csrrw x0, cycle, a0  (ghi CSR chỉ đọc)
#define CSRRSI_A0_MVID_1  0xf110e573      // csrrsi a0, mvendorid, 1
#define ILLEGAL_WORD      0x12345677      // opcode 1110111 không hỗ trợ

TEST_CODE_BEGIN
    // ---- Giá trị sau reset ------------------------------------------------
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

    // misa = 0x40000100, thêm bit M khi ENABLE_M
    li   t0, TB_CTRL
    lw   t1, TB_CFG(t0)
    andi t1, t1, 1
    slli t1, t1, 12
    li   t2, 0x40000100
    or   t2, t2, t1
    csrr a0, misa
    li   TESTNUM, 10
    bne  a0, t2, fail
    li   a1, -1                     // ghi misa bị bỏ qua
    csrw misa, a1
    csrr a0, misa
    li   TESTNUM, 11
    bne  a0, t2, fail

    // ---- Mặt nạ đọc/ghi -----------------------------------------------------
    li   a1, -1
    csrw mstatus, a1
    csrr a0, mstatus
    CHECK(12, a0, 0x1888)           // chỉ MIE, MPIE ghi được
    csrw mstatus, zero
    csrr a0, mstatus
    CHECK(13, a0, 0x1800)
    csrw mie, a1
    csrr a0, mie
    CHECK(14, a0, 0x888)
    csrw mie, zero
    csrw mip, a1                    // mip chỉ đọc theo cổng ngắt
    csrr a0, mip
    CHECK(15, a0, 0)
    li   a1, 0x12345677
    csrw mtvec, a1
    csrr a0, mtvec
    CHECK(16, a0, 0x12345674)       // chế độ direct, bit 1:0 = 0
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
    csrrwi a0, mscratch, 0x15       // CSRRWI trả giá trị cũ
    CHECK(21, a0, 0x12345677)
    csrrsi a0, mscratch, 0x0a
    CHECK(22, a0, 0x15)
    csrrci a0, mscratch, 0x05
    CHECK(23, a0, 0x1f)
    csrr a0, mscratch
    CHECK(24, a0, 0x1a)
    li   a1, 0xf0
    csrrs a0, mscratch, a1          // forward giá trị CSR sang lệnh kế
    addi a0, a0, 1
    CHECK(25, a0, 0x1b)
    csrr a0, mscratch
    CHECK(26, a0, 0xfa)

    // ---- Cài trình xử lý trap -------------------------------------------------
    la   t0, handler
    csrw mtvec, t0

    // ---- Ngoại lệ đồng bộ -------------------------------------------------------
    EXPECT_TRAP(30, 11, 0, ecall)
    EXPECT_TRAP(31, 3, 0, ebreak)
    EXPECT_TRAP(32, 2, ILLEGAL_WORD, .word ILLEGAL_WORD)
    EXPECT_TRAP(33, 2, 0, .word 0)

    li   a0, 0x55                   // rd không bị ghi khi CSR sai
    EXPECT_TRAP(34, 2, CSRRS_A0_7C0, .word CSRRS_A0_7C0)
    CHECK(35, a0, 0x55)
    EXPECT_TRAP(36, 2, CSRRW_X0_CYCLE_A0, .word CSRRW_X0_CYCLE_A0)
    EXPECT_TRAP(37, 2, CSRRSI_A0_MVID_1, .word CSRRSI_A0_MVID_1)
    CHECK(38, a0, 0x55)
    csrrsi a0, mvendorid, 0         // đọc CSR chỉ đọc (không ghi) là hợp lệ
    CHECK(39, a0, 0)
    csrrs x0, cycle, x0

    // Load/store lệch địa chỉ: mtval = địa chỉ, rd và bộ nhớ không đổi
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

    // Lỗi bus: địa chỉ không ánh xạ
    li   s1, 0x40000000
    EXPECT_TRAP(47, 5, 0x40000004, lw a0, 4(s1))
    CHECK(48, a0, 0x66)
    EXPECT_TRAP(49, 7, 0x40000008, sb a0, 8(s1))

    // Nhảy lệch: mepc = lệnh nhảy, mtval = đích, rd không bị ghi
    li   a0, 0x77
    EXPECT_TRAP(50, 0, 2, jalr a0, 2(zero))
    CHECK(51, a0, 0x77)
    // Lỗi lấy lệnh: mepc = mtval = địa chỉ lỗi, lệnh nhảy vẫn ghi rd
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

    // ---- mstatus khi trap và MRET ------------------------------------------------
    csrsi mstatus, 8                // MIE = 1 (không có ngắt nào đang chờ)
    EXPECT_TRAP(60, 11, 0, ecall)
    CHECK(61, s7, 0x1880)           // trong handler: MIE = 0, MPIE = 1
    csrr a0, mstatus
    CHECK(62, a0, 0x1888)           // MRET: MIE = MPIE, MPIE = 1
    csrw mstatus, zero
    EXPECT_TRAP(63, 11, 0, ecall)
    CHECK(64, s7, 0x1800)
    csrr a0, mstatus
    CHECK(65, a0, 0x1880)

    csrw mstatus, zero              // MRET trực tiếp
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
    // Lệnh bị trap không tính: handler ngắn chỉ có 2 lệnh
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
    bltu a0, x7, fail               // ít nhất 1 chu kỳ mỗi lệnh
    csrr a0, mcycle
    csrr a1, cycle
    li   TESTNUM, 81
    bgeu a0, a1, fail
    csrwi mcycle, 0                 // ghi mcycle thay cho lần tăng
    csrr a0, mcycle
    li   TESTNUM, 82
    li   x7, 20
    bgeu a0, x7, fail
    li   a1, 5                      // nhớ từ nửa thấp sang nửa cao
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
    li   a1, 7                      // minstreth ghi được
    csrw minstreth, a1
    csrr a0, minstreth
    CHECK(85, a0, 7)
    csrw minstreth, zero
    csrr a0, time
    csrr a1, time
    li   TESTNUM, 86
    bgeu a0, a1, fail               // mtime_i tăng mỗi chu kỳ trong tb
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
