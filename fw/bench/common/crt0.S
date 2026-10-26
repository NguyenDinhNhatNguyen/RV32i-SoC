// crt0.S - startup for C benchmarks running on tb_core (fw/common/link.ld).
// Sets sp and gp, clears .bss, calls main. Ends by writing tohost:
// 1 (PASS) when main returns 0, otherwise (code << 1) | 1 (FAIL).
// mtvec is not installed, so an unexpected trap makes tb_core report FAIL at once.
// With -DBENCH_SOC (soc_top on tb_soc): the UART runs at BAUDDIV = 1 (16 cycles per bit)
// to keep the simulation short, and the end waits until the UART has sent every byte,
// because tb_soc stops at the tohost write.
#ifdef BENCH_SOC
#define UART_BASE 0x20001000
#endif
    .section .text.init, "ax"
    .globl _start
_start:
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop
    la   sp, __stack_top
    la   t0, __bss_start
    la   t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
#ifdef BENCH_SOC
    li   t0, UART_BASE
    li   t1, 1
    sw   t1, 0xC(t0)                // BAUDDIV = 1
#endif
    li   a0, 0
    li   a1, 0
    call main
#ifdef BENCH_SOC
    li   t0, UART_BASE
5:  lw   t1, 4(t0)                  // STATUS: wait for TXE = 1 and TXB = 0
    andi t1, t1, 6
    xori t1, t1, 2
    bnez t1, 5b
#endif
    li   t0, 1
    beqz a0, 3f
    slli t0, a0, 1
    ori  t0, t0, 1
3:  la   t1, tohost
    sw   t0, 0(t1)
4:  j    4b

    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .word 0
    .align 6
