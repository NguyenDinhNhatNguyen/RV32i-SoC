// irq.S - ngắt (docs/spec/core.md mục 4.8).
// Kiểm tra: mip phản ánh cổng ngắt, MIE và từng bit mie chặn ngắt, thứ tự
// ưu tiên MEI > MSI > MTI, mcause bit 31, ngắt chính xác (chạy một đoạn
// tính toán có load/store/nhánh/gọi hàm với ngắt rơi vào mọi vị trí, kết
// quả không đổi và ngắt được nhận đúng một lần), và không nhận ngắt ở lệnh
// sau lệnh tắt MIE / mie.
//
// Trình xử lý chỉ dùng t3-t6, s10, s11: ghi mcause vào irq_log[s10], tăng
// s10, mepc -> s11, rồi hạ đường ngắt của nguồn vừa nhận qua khối điều khiển
// của tb. Ngoại lệ đồng bộ (mcause bit 31 = 0) là lỗi.
#include "test_macros.h"

#define MCAUSE_MSI 0x80000003
#define MCAUSE_MTI 0x80000007
#define MCAUSE_MEI 0x8000000b

// Đặt mức ngắt (delay 0) rồi đọc lại để chờ mức mới có hiệu lực
#define SET_IRQ(val)                \
    li   t0, TB_CTRL;               \
    li   t1, val;                   \
    sw   t1, TB_IRQ(t0);            \
    lw   t1, TB_IRQ(t0);            \
    lw   t1, TB_IRQ(t0)

TEST_CODE_BEGIN
    la   t0, irq_handler
    csrw mtvec, t0
    li   s10, 0

    // ---- mip theo cổng, MIE = 0 chặn mọi ngắt ---------------------------------
    li   t0, 0x888
    csrw mie, t0
    SET_IRQ(TB_IRQ_MSI | TB_IRQ_MTI | TB_IRQ_MEI)
    csrr a0, mip
    CHECK(2, a0, 0x888)
    nop
    nop
    nop
    CHECK(3, s10, 0)

    // ---- Bit mie chặn từng nguồn ----------------------------------------------------
    csrw mie, zero
    csrsi mstatus, 8
    nop
    nop
    nop
    CHECK(4, s10, 0)
    csrci mstatus, 8

    // ---- Ưu tiên MEI > MSI > MTI (cả ba đang chờ) -------------------------------
    li   t0, 0x888
    csrw mie, t0
    csrsi mstatus, 8
1:  li   t0, 3
    bltu s10, t0, 1b
    csrci mstatus, 8
    CHECK(5, s10, 3)
    la   t0, irq_log
    lw   a0, 0(t0)
    CHECK(6, a0, MCAUSE_MEI)
    lw   a0, 4(t0)
    CHECK(7, a0, MCAUSE_MSI)
    lw   a0, 8(t0)
    CHECK(8, a0, MCAUSE_MTI)
    csrr a0, mip
    CHECK(9, a0, 0)
    csrr a0, mstatus                // MRET trả MIE = 1, rồi csrci xoá
    CHECK(10, a0, 0x1880)

    // ---- Từng nguồn riêng với đúng bit mie ------------------------------------------
    li   s10, 0
    li   t0, 0x80                   // chỉ MTIE: MSI và MEI đang chờ không gây ngắt
    csrw mie, t0
    SET_IRQ(TB_IRQ_MSI | TB_IRQ_MEI)
    csrsi mstatus, 8
    nop
    nop
    nop
    CHECK(11, s10, 0)
    SET_IRQ(TB_IRQ_MSI | TB_IRQ_MEI | TB_IRQ_MTI)
1:  beqz s10, 1b
    CHECK(12, s10, 1)
    la   t0, irq_log
    lw   a0, 0(t0)
    CHECK(13, a0, MCAUSE_MTI)
    csrci mstatus, 8
    SET_IRQ(0)

    // ---- Bật MIE khi ngắt đang chờ: nhận trong vòng 2 lệnh --------------------------
    li   s10, 0
    li   t0, 0x8                    // MSIE
    csrw mie, t0
    SET_IRQ(TB_IRQ_MSI)
    csrsi mstatus, 8
2:  nop
    nop
    nop
    CHECK(14, s10, 1)
    la   t0, 2b
    addi t0, t0, 4
    li   TESTNUM, 15
    bltu t0, s11, fail              // mepc <= nhãn 2 + 4
    csrci mstatus, 8

    // ---- Ngắt chính xác: ngắt rơi vào mọi vị trí của đoạn tính toán -------------
    li   t0, 0x80
    csrw mie, t0
    li   s0, 0                      // delay
precise_loop:
    li   TESTNUM, 20
    li   s10, 0
    csrsi mstatus, 8
    li   t0, TB_CTRL
    slli t1, s0, 16
    ori  t1, t1, TB_IRQ_MTI
    sw   t1, TB_IRQ(t0)
    // out[i] = arr[0] + ... + arr[i], arr = 1..8 (gọi hàm cho phép cộng)
    li   a0, 0
    la   a1, arr
    li   a2, 8
1:  lw   a3, 0(a1)
    jal  ra, accumulate
    sw   a0, 32(a1)
    addi a1, a1, 4
    addi a2, a2, -1
    bnez a2, 1b
2:  beqz s10, 2b                    // ngắt rơi sau đoạn tính toán thì chờ ở đây
    csrci mstatus, 8
    CHECK(21, s10, 1)
    CHECK(22, a0, 36)
    la   a1, arr
    li   a0, 0                      // tổng của out[] = 1+3+6+...+36 = 120
    li   a2, 8
3:  lw   a3, 32(a1)
    sw   zero, 32(a1)
    add  a0, a0, a3
    addi a1, a1, 4
    addi a2, a2, -1
    bnez a2, 3b
    CHECK(23, a0, 120)
    addi s0, s0, 1
    li   t0, 90
    bltu s0, t0, precise_loop

    // ---- Không nhận ngắt ở lệnh sau lệnh tắt MIE --------------------------------
    // Quét thời điểm đường ngắt lên quanh lúc csrci mstatus tới WB. Nếu ngắt
    // được nhận thì mepc phải <= địa chỉ csrci.
    li   s0, 0
block_mstatus:
    li   TESTNUM, 30
    li   s10, 0
    li   t0, 0x80
    csrw mie, t0
    csrsi mstatus, 8
    li   t0, TB_CTRL
    slli t1, s0, 16
    ori  t1, t1, TB_IRQ_MTI
    sw   t1, TB_IRQ(t0)
4:  csrci mstatus, 8
    addi a0, a0, 1
    nop
    nop
    nop
    nop
    nop
    nop
    beqz s10, 1f
    la   t0, 4b
    bltu t0, s11, fail
1:  SET_IRQ(0)
    addi s0, s0, 1
    li   t0, 12
    bltu s0, t0, block_mstatus

    // Tương tự với lệnh xoá mie
    li   s0, 0
block_mie:
    li   TESTNUM, 31
    li   s10, 0
    li   t0, 0x80
    csrw mie, t0
    csrsi mstatus, 8
    li   t0, TB_CTRL
    slli t1, s0, 16
    ori  t1, t1, TB_IRQ_MTI
    sw   t1, TB_IRQ(t0)
4:  csrw mie, zero
    addi a0, a0, 1
    nop
    nop
    nop
    nop
    nop
    nop
    beqz s10, 1f
    la   t0, 4b
    bltu t0, s11, fail
1:  csrci mstatus, 8
    SET_IRQ(0)
    addi s0, s0, 1
    li   t0, 12
    bltu s0, t0, block_mie

    TEST_PASS
TEST_FAIL

accumulate:
    add  a0, a0, a3
    ret

irq_handler:
    csrr t3, mcause
    csrr s11, mepc
    la   t4, irq_log
    slli t5, s10, 2
    add  t4, t4, t5
    sw   t3, 0(t4)
    addi s10, s10, 1
    bgez t3, fail
    andi t3, t3, 31                 // hạ đường ngắt (1 << mã ngắt)
    li   t5, 1
    sll  t5, t5, t3
    not  t5, t5
    li   t4, TB_CTRL
    lw   t6, TB_IRQ(t4)
    and  t6, t6, t5
    sw   t6, TB_IRQ(t4)
    lw   t6, TB_IRQ(t4)
    mret

TEST_DATA_BEGIN
arr:
    .word 1, 2, 3, 4, 5, 6, 7, 8
out:
    .word 0, 0, 0, 0, 0, 0, 0, 0
irq_log:
    .word 0, 0, 0, 0, 0, 0, 0, 0
