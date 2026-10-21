// wfi.S - WFI ngủ (docs/spec/core.md mục 4.11).
// Chạy được cả khi ENABLE_WFI_SLEEP = 0 (WFI là NOP, đọc từ thanh ghi CFG
// của tb). Khi ngủ được bật, kiểm tra:
//   - MIE = 0: core ngủ đến khi có ngắt được bật trong mie rồi chạy tiếp lệnh
//     sau WFI, trình xử lý không chạy. Ngắt đang chờ nhưng bị tắt trong mie
//     không đánh thức core.
//   - MIE = 1: thức dậy rồi nhận ngắt ngay ở lệnh sau WFI (mepc = PC(WFI)+4).
//   - Số chu kỳ ngủ (tb đếm core_sleep_o) xấp xỉ thời gian chờ ngắt, mcycle
//     vẫn chạy trong lúc ngủ, ngắt đã chờ sẵn thì gần như không ngủ.
// tb_core còn kiểm tra không lấy lệnh, không truy cập bus và WB trống trong
// suốt thời gian ngủ.
//
// s0 = 1 nếu ngủ được bật. Trình xử lý (chỉ dùng t3-t6, s10, s11) tăng s10,
// mepc -> s11, hạ mọi đường ngắt.
#include "test_macros.h"

#define WAIT 200                    // số chu kỳ từ lúc ghi tới lúc ngắt lên

// a0 = số chu kỳ ngủ hiện tại
#define READ_SLEEP(r)               \
    li   t0, TB_CTRL;               \
    lw   r, TB_SLEEP(t0)

// Ngắt lên sau WAIT chu kỳ
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

// Số chu kỳ ngủ d (thanh ghi) phải nằm trong (lo, hi] khi ngủ được bật,
// bằng 0 khi không.
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

    // ---- MIE = 0: ngủ đến khi MTI lên, rồi chạy tiếp -------------------------------
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
    beqz s0, 1f                     // đã ngủ thì mip.MTIP phải đang lên
    csrr a0, mip
    CHECK(3, a0, 0x80)
    sub  a0, s3, s2                 // mcycle chạy trong lúc ngủ
    li   TESTNUM, 4
    li   x7, WAIT
    bltu a0, x7, fail
1:  csrr a0, mip                    // WFI là NOP: chờ ngắt lên
    beqz a0, 1b
    CHECK(5, s10, 0)                // MIE = 0: không vào trình xử lý
    SET_IRQ(0)

    // ---- Ngắt chờ nhưng bị tắt trong mie không đánh thức -----------------------------
    li   t0, 0x80                   // chỉ MTIE
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

    // ---- Ngắt đã chờ sẵn và được bật: gần như không ngủ ----------------------------
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

    // ---- MIE = 1: thức dậy và nhận ngắt ở lệnh sau WFI -------------------------------
    li   s10, 0
    li   s11, 0
    li   t0, 0x800                  // MEIE
    csrw mie, t0
    csrsi mstatus, 8
    READ_SLEEP(s1)
    IRQ_LATER(TB_IRQ_MEI)
    wfi
3:  beqz s10, 3b                    // WFI là NOP: chờ ngắt ở đây
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
    // Lần nữa với MSI, WFI ngay sau lệnh ghi (không có lệnh chen giữa)
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
    bgez t3, fail                   // ngoại lệ không mong đợi
    li   t4, TB_CTRL
    sw   zero, TB_IRQ(t4)
    lw   t3, TB_IRQ(t4)
    lw   t3, TB_IRQ(t4)
    mret

TEST_DATA_BEGIN
    .word 0
