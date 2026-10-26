/* hello.S - program that tb_boot loads through the bootloader (docs/boot.md).
 * Position independent, so the same .bin runs at any IMEM address (load tests) and at
 * 0x0000_0000 (preloaded, timeout tests). Prints "boot ok\n" on the UART, then writes 1 to
 * TOHOST (PASS for tb_boot).
 */
#define UART_BASE   0x20001000
#define TOHOST      0x10000000

    .section .text.init, "ax"
    .globl  _start
_start:
    li      s0, UART_BASE
    li      a1, 0x746F6F62              // "boot", first character in the low byte
    jal     putw
    li      a1, 0x0A6B6F20              // " ok\n"
    jal     putw
1:  lw      t0, 4(s0)                   // Wait until the line is idle (TXE = 1, TXB = 0)
    andi    t0, t0, 0x6
    li      t1, 0x2
    bne     t0, t1, 1b
    li      t0, TOHOST
    li      t1, 1
    sw      t1, 0(t0)
2:  j       2b

/* putw: send the 4 bytes of a1, low byte first */
putw:
    li      t2, 4
1:  lw      t0, 4(s0)
    andi    t0, t0, 1                   // TXF
    bnez    t0, 1b
    sw      a1, 0(s0)                   // DATA takes bits [7:0]
    srli    a1, a1, 8
    addi    t2, t2, -1
    bnez    t2, 1b
    ret
