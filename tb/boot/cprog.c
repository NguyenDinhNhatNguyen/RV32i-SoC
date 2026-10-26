/* cprog.c - C program that tb_boot loads from its ELF through the bootloader (docs/boot.md).
 * Built with fw/bench/common/crt0.S (-DBENCH_SOC) and fw/common/link.ld: .text in IMEM,
 * .rodata and .data in DMEM, so each one arrives as its own segment.
 * Checks a non-zero initialized global (.data/.sdata), a constant table and the message
 * (.rodata) and a zeroed global (.bss), then prints "boot ok\n". main returns 0 (tohost 1)
 * only when every check passes.
 */
#define UART_DATA   (*(volatile unsigned *)0x20001000)
#define UART_STATUS (*(volatile unsigned *)0x20001004)
#define ST_TXF      0x01

#define TABLE_SUM   0xC2293C9Au        /* Sum of table[], mod 2^32 */

int seed = 0x12345678;                  /* .sdata */
int lut_hits;                           /* .sbss, cleared by crt0 */
const unsigned table[8] = {             /* .rodata */
    0x01020304u, 0x10203040u, 0xCAFEF00Du, 0x0BADBEEFu,
    0x5A5A5A5Au, 0x00000001u, 0x7FFFFFFFu, 0u
};
const char msg[] = "boot ok\n";         /* .rodata */

static void putc_uart(char c)
{
    while (UART_STATUS & ST_TXF)
        ;
    UART_DATA = (unsigned char)c;
}

int main(void)
{
    const unsigned *t = table;
    const char *m = msg;
    unsigned sum = 0;
    int i;

    /* Hide the pointers from the compiler so it reads DMEM instead of folding constants */
    __asm__ volatile ("" : "+r"(t), "+r"(m) : : "memory");
    for (i = 0; i < 8; i++)
        sum += t[i];
    if (sum != TABLE_SUM)
        return 1;
    if (seed != 0x12345678)
        return 2;
    if (lut_hits != 0)
        return 3;
    for (; *m; m++)
        putc_uart(*m);
    return 0;
}
