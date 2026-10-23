// bus.S - core truy cập ngoại vi qua sys_bus và apb_bridge (RTL-03), chạy trên
// tb/soc/tb_core_bus.v. Không chạy được trên tb_core vì cần accelerator và UART giả.
//   - Đọc INFO của accelerator, nhân ma trận 4x4 bằng accelerator, so với kết quả tính sẵn.
//   - Hai lệnh đọc APB liên tiếp, xoá DONE.
//   - Lỗi bus thành access fault đúng mcause và mtval: địa chỉ không ánh xạ, đọc
//     boot ROM từ bus dữ liệu, ngoài DMEM, khe APB tắt, PSLVERR của accelerator,
//     truy cập byte/half vào APB.
//   - In "bus ok" qua UART giả bằng sw.
//
// Trình xử lý trap ghi lại mcause -> s2, mepc -> s3, mtval -> s4, tăng s5,
// rồi quay về địa chỉ trong s6.
#include "test_macros.h"

#define ACCEL       0x30000000
#define UART        0x20001000

// Lệnh ở nhãn 2 phải trap với mcause = cause, mtval = tval
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

TEST_CODE_BEGIN
    la   t0, handler
    csrw mtvec, t0
    li   s0, ACCEL

    // ---- Accelerator qua APB ----------------------------------------------
    lw   a0, 8(s0)                  // INFO = {N, DW, AW, LAT}
    CHECK(2, a0, 0x0408140A)

    // Nạp A, B (4 word mỗi ma trận, theo hàng)
    la   a1, mat_a
    la   a2, mat_b
    li   a3, 0
3:  add  t2, a1, a3
    lw   t3, 0(t2)
    add  t2, s0, a3
    sw   t3, 0x100(t2)
    add  t2, a2, a3
    lw   t3, 0(t2)
    add  t2, s0, a3
    sw   t3, 0x200(t2)
    addi a3, a3, 4
    li   t2, 16
    bne  a3, t2, 3b

    li   t2, 1
    sw   t2, 0(s0)                  // START
    li   TESTNUM, 3
    li   a4, 100                    // tối đa 100 lần hỏi
4:  addi a4, a4, -1
    beqz a4, fail
    lw   t2, 4(s0)
    andi t2, t2, 2                  // DONE
    beqz t2, 4b

    // So 16 kết quả
    li   TESTNUM, 4
    la   a1, mat_c
    li   a3, 0
5:  add  t2, s0, a3
    lw   t3, 0x300(t2)
    add  t2, a1, a3
    lw   t4, 0(t2)
    bne  t3, t4, fail
    addi a3, a3, 4
    li   t2, 64
    bne  a3, t2, 5b

    // Hai lệnh đọc APB liên tiếp, rồi xoá DONE (ghi 1 để xoá)
    lw   a0, 8(s0)
    lw   a1, 4(s0)
    CHECK(5, a0, 0x0408140A)
    CHECK(6, a1, 2)
    li   t2, 2
    sw   t2, 4(s0)
    lw   a0, 4(s0)
    CHECK(7, a0, 0)

    // ---- Lỗi bus thành access fault ----------------------------------------
    li   a5, 0x50000000
    EXPECT_TRAP(10, 5, 0x50000000, lw a0, 0(a5))        // vùng không ánh xạ
    li   a5, 0x00010000
    EXPECT_TRAP(11, 5, 0x00010000, lw a0, 0(a5))        // boot ROM chỉ cổng lệnh đọc
    EXPECT_TRAP(12, 7, 0x00010000, sw a0, 0(a5))
    li   a5, 0x10004000
    EXPECT_TRAP(13, 7, 0x10004000, sw a0, 0(a5))        // ngay sau DMEM 16 KB
    li   a5, 0x20003000
    EXPECT_TRAP(14, 5, 0x20003000, lw a0, 0(a5))        // khe SPI đang tắt
    li   a5, 0x30000400
    EXPECT_TRAP(15, 5, 0x30000400, lw a0, 0(a5))        // PSLVERR của accel_apb
    EXPECT_TRAP(16, 7, 0x30000300, sw a0, 0x300(s0))    // ghi C_BUF: PSLVERR
    li   a5, UART
    EXPECT_TRAP(17, 7, 0x20001000, sb a0, 0(a5))        // APB chỉ truy cập word
    EXPECT_TRAP(18, 5, 0x20001002, lhu a0, 2(a5))

    // Load bị lỗi không ghi rd
    li   TESTNUM, 19
    li   a0, 0x1234
    li   a5, 0x50000000
    la   s6, 6f
    lw   a0, 0(a5)
6:  li   x7, 0x1234
    bne  a0, x7, fail

    // ---- UART giả ---------------------------------------------------------
    li   a5, UART
    la   a1, msg
7:  lbu  t2, 0(a1)
    beqz t2, 8f
    sw   t2, 0(a5)
    addi a1, a1, 1
    j    7b
8:
    TEST_PASS
    TEST_FAIL

handler:
    csrr s2, mcause
    csrr s3, mepc
    csrr s4, mtval
    addi s5, s5, 1
    csrw mepc, s6
    mret

TEST_DATA_BEGIN
mat_a:
    .word 0x04030201, 0x08070605, 0xfcfdfeff, 0xff00807f
mat_b:
    .word 0xfd010002, 0x05000101, 0x0204f900, 0x01037f80
mat_c:      // tính bằng Python từ mat_a, mat_b (int8 có dấu)
    .word -508, 489, 25, 17, -1008, 973, 57, 37, 508, -489, -25, -17, 254, -255, 124, -1022
msg:
    .asciz "bus ok\n"
