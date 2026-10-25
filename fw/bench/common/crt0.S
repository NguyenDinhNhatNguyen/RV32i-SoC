// crt0.S - startup for C benchmarks running on tb_core (fw/common/link.ld).
// Sets sp and gp, clears .bss, calls main. Ends by writing tohost:
// 1 (PASS) when main returns 0, otherwise (code << 1) | 1 (FAIL).
// mtvec is not installed, so an unexpected trap makes tb_core report FAIL at once.
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
2:  li   a0, 0
    li   a1, 0
    call main
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
