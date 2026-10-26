/* boot.S - UART bootloader in the 1 KB boot ROM at 0x0001_0000 (P8). Spec: docs/boot.md.
 *
 * Pure assembly that runs from registers only. It uses no stack and no DMEM, because the
 * data port cannot read the boot ROM and nothing in DMEM is set up yet.
 *
 *   0. Boot strap gpio_i[0] (GPIO DATA_IN bit 0). 0: jump to 0x0000_0000 at once, the UART
 *      is not touched (same as the base ROM, used by tb_soc). 1: UART boot.
 *      mtvec points to that jump while the bootloader runs, so a bus error (a build or a
 *      testbench without GPIO, such as tb_core_bus) also ends in IMEM.
 *   1. Set up the UART (BAUDDIV from CLK_HZ and BAUD, TX and RX on), drain RX, clear flags.
 *   2. Wait for MAGIC for TIMEOUT_CYCLES (mcycle). Other bytes are ignored.
 *      No MAGIC in time: jump to 0x0000_0000 (program already in IMEM).
 *   3. Send READY, then wait for SYNC (extra MAGIC bytes from the host are skipped).
 *   4. Header: addr, len, entry (4 bytes each, little endian). addr and len word aligned,
 *      len > 0 and [addr, addr + len) inside IMEM or inside DMEM (not across a region end).
 *      entry = NO_JUMP (0xFFFF_FFFF): more segments follow. Any other entry ends the load
 *      and must be word aligned inside IMEM. Otherwise NAK and back to step 3. Else ACK.
 *   5. Data: len bytes, stored word by word through the data port.
 *      Then crc (4 bytes) = CRC-32 (zlib) of addr, len, entry and data.
 *      Mismatch: NAK and back to step 3. Match: ACK. With entry = NO_JUMP back to step 3
 *      for the next segment. Else wait until the ACK is on the line, fence.i, jump to entry.
 * After MAGIC there is no timeout, a failed load waits for the host to retry.
 * On every jump mtvec and the registers used here are cleared, except t0 = jump target.
 *
 * Build parameters (gcc -D, set by make boot-gen):
 *   CLK_HZ, BAUD        UART speed, BAUDDIV = round(CLK_HZ / (16 * BAUD))
 *   TIMEOUT_CYCLES      wait for MAGIC, at most 2^31
 *   IMEM_SIZE           bytes, from SOC_IMEM_SIZE in rtl/bus/soc_map.vh
 *   DMEM_BASE, DMEM_SIZE  from SOC_DMEM_BASE and SOC_DMEM_SIZE in rtl/bus/soc_map.vh
 */

#ifndef CLK_HZ
#define CLK_HZ          50000000
#endif
#ifndef BAUD
#define BAUD            115200
#endif
#ifndef TIMEOUT_CYCLES
#define TIMEOUT_CYCLES  50000000        // 1 s at 50 MHz
#endif
#ifndef IMEM_SIZE
#define IMEM_SIZE       16384
#endif
#ifndef DMEM_BASE
#define DMEM_BASE       0x10000000
#endif
#ifndef DMEM_SIZE
#define DMEM_SIZE       16384
#endif

#define BAUD_DIV        ((CLK_HZ + 8 * BAUD) / (16 * BAUD))

#define GPIO_BASE       0x20002000
#define GPIO_DATA_IN    0x04
#define STRAP_UART      0x01            // gpio_i[0] = 1: UART boot

#define UART_BASE       0x20001000
#define UART_DATA       0x00
#define UART_STATUS     0x04
#define UART_CTRL       0x08
#define UART_BAUDDIV    0x0C
#define ST_TXF          0x01
#define ST_TXE          0x02
#define ST_TXB          0x04
#define ST_RXNE         0x10
#define ST_STICKY       0xE0            // OVR, FE, TXOVF: write 1 to clear
#define CTRL_RESET      0x03            // TXEN, RXEN, no interrupts (reset value)

#define MAGIC           0xA5            // Host to device, repeated until READY
#define READY           0x3E            // '>'
#define SYNC            0x5A            // Start of a packet
#define ACK             0x06
#define NAK             0x15
#define NO_JUMP         0xFFFFFFFF      // Header entry: more segments follow
#define CRC_POLY        0xEDB88320      // CRC-32, reflected

#if TIMEOUT_CYCLES > 0x7FFFFFFF
#error "TIMEOUT_CYCLES must fit in 31 bits"
#endif
#if BAUD_DIV < 1 || BAUD_DIV > 0xFFFF
#error "BAUDDIV out of range, check CLK_HZ and BAUD"
#endif

/* Absolute symbols, read by scripts/gen_boot_rom.py for the header of boot_rom_init.vh */
    .globl  BOOT_TIMEOUT, BOOT_BAUDDIV, BOOT_CLK_HZ, BOOT_BAUD, BOOT_IMEM_SIZE
    .globl  BOOT_DMEM_BASE, BOOT_DMEM_SIZE
    .set    BOOT_TIMEOUT,   TIMEOUT_CYCLES
    .set    BOOT_BAUDDIV,   BAUD_DIV
    .set    BOOT_CLK_HZ,    CLK_HZ
    .set    BOOT_BAUD,      BAUD
    .set    BOOT_IMEM_SIZE, IMEM_SIZE
    .set    BOOT_DMEM_BASE, DMEM_BASE
    .set    BOOT_DMEM_SIZE, DMEM_SIZE

/* Registers
 *   s0  UART base          s1  IMEM size          s2  link for getw
 *   s3  mcycle at start    s4  timeout            s5  load address
 *   s6  length             s7  computed CRC       s8  entry
 *   a0  byte for getc / putc                      a1  word from getw
 *   a2  running CRC        a3  CRC polynomial
 *   t0..t6 scratch, ra link for the leaf routines
 */
    .section .text.init, "ax"
    .globl  _start
_start:
    la      t0, run_imem
    csrw    mtvec, t0
    li      t1, GPIO_BASE
    li      s0, UART_BASE
    li      s1, IMEM_SIZE
    li      a3, CRC_POLY
    lw      t0, GPIO_DATA_IN(t1)        // The pin synchronizer has settled by now
    andi    t0, t0, STRAP_UART
    beqz    t0, run_imem                // Strap 0: run IMEM, no UART boot
    li      t0, BAUD_DIV
    sw      t0, UART_BAUDDIV(s0)
    li      t0, CTRL_RESET
    sw      t0, UART_CTRL(s0)
drain:                                  // Drop bytes that arrived during reset
    lw      t0, UART_STATUS(s0)
    andi    t0, t0, ST_RXNE
    beqz    t0, 1f
    lw      t0, UART_DATA(s0)
    j       drain
1:  li      t0, ST_STICKY
    sw      t0, UART_STATUS(s0)

    csrr    s3, mcycle
    li      s4, TIMEOUT_CYCLES
wait_magic:
    csrr    t0, mcycle
    sub     t0, t0, s3                  // Wraps correctly, timeout < 2^31
    bgeu    t0, s4, run_imem
    lw      t0, UART_STATUS(s0)
    andi    t0, t0, ST_RXNE
    beqz    t0, wait_magic
    lw      t0, UART_DATA(s0)
    andi    t0, t0, 0xFF
    li      t1, MAGIC
    bne     t0, t1, wait_magic
    li      a0, READY
    jal     putc

wait_sync:
    jal     getc
    li      t1, SYNC
    bne     a0, t1, wait_sync           // Skips MAGIC and noise

    li      a2, -1                      // CRC start value
    jal     s2, getw
    mv      s5, a1                      // addr
    jal     s2, getw
    mv      s6, a1                      // len
    jal     s2, getw
    mv      s8, a1                      // entry
    or      t0, s5, s6
    andi    t0, t0, 3
    bnez    t0, nak                     // Not word aligned
    beqz    s6, nak                     // Empty
    mv      t1, s5                      // t1 = offset in the region, t0 = region size
    mv      t0, s1
    bltu    s5, s1, 1f                  // addr inside IMEM
    li      t1, DMEM_BASE
    sub     t1, s5, t1
    li      t0, DMEM_SIZE
    bgeu    t1, t0, nak                 // addr outside IMEM and DMEM
1:  sub     t0, t0, t1
    bltu    t0, s6, nak                 // addr + len past the end of the region
    li      t0, NO_JUMP
    beq     s8, t0, 2f                  // Not the last segment
    andi    t0, s8, 3
    bnez    t0, nak                     // entry not word aligned
    bgeu    s8, s1, nak                 // entry outside IMEM
2:  li      a0, ACK
    jal     putc

    mv      t2, s5                      // Write pointer
    add     t3, s5, s6                  // End
data:
    jal     s2, getw
    sw      a1, 0(t2)
    addi    t2, t2, 4
    bne     t2, t3, data
    not     s7, a2                      // Final CRC = ~running CRC
    jal     s2, getw                    // CRC from the host (also runs through a2, unused)
    bne     a1, s7, nak

    li      a0, ACK
    jal     putc
    li      t0, NO_JUMP
    beq     s8, t0, wait_sync           // Next segment
tx_wait:                                // ACK fully sent: TX FIFO empty, shifter idle
    lw      t0, UART_STATUS(s0)
    andi    t0, t0, ST_TXE | ST_TXB
    li      t1, ST_TXE
    bne     t0, t1, tx_wait
    fence.i
    mv      t0, s8
    j       handoff

nak:
    li      a0, NAK
    jal     putc
    j       wait_sync

    .balign 4                           // mtvec target
run_imem:
    li      t0, 0
    // Fall through

/* Clear mtvec and the registers used here so the program starts as after reset
 * (t0 = target). mcause, mepc and mstatus keep a trap from a missing GPIO. */
handoff:
    csrw    mtvec, zero
    li      ra, 0
    li      t1, 0
    li      t2, 0
    li      t3, 0
    li      t4, 0
    li      t5, 0
    li      t6, 0
    li      s0, 0
    li      s1, 0
    li      s2, 0
    li      s3, 0
    li      s4, 0
    li      s5, 0
    li      s6, 0
    li      s7, 0
    li      s8, 0
    li      a0, 0
    li      a1, 0
    li      a2, 0
    li      a3, 0
    jr      t0

/* getw: 4 bytes, little endian, into a1, each byte also goes through the CRC.
 * Link register s2 because it calls the leaf routines with ra. Uses t4, t5, t6. */
getw:
    li      a1, 0
    li      t4, 0                       // Shift
1:  jal     getc
    jal     crc8
    sll     t5, a0, t4
    or      a1, a1, t5
    addi    t4, t4, 8
    li      t5, 32
    bne     t4, t5, 1b
    jr      s2

/* getc: wait for a byte, return it in a0. Uses t0. */
getc:
    lw      t0, UART_STATUS(s0)
    andi    t0, t0, ST_RXNE
    beqz    t0, getc
    lw      a0, UART_DATA(s0)
    andi    a0, a0, 0xFF
    ret

/* putc: wait for room in the TX FIFO, send a0. Uses t0. */
putc:
    lw      t0, UART_STATUS(s0)
    andi    t0, t0, ST_TXF
    bnez    t0, putc
    sw      a0, UART_DATA(s0)
    ret

/* crc8: a2 = CRC-32 of a2 updated with byte a0, bit by bit. Uses t5, t6. */
crc8:
    xor     a2, a2, a0
    li      t5, 8
1:  andi    t6, a2, 1
    srli    a2, a2, 1
    beqz    t6, 2f
    xor     a2, a2, a3
2:  addi    t5, t5, -1
    bnez    t5, 1b
    ret
