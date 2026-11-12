/* soc_fw.c - VER-04: C firmware test of soc_top on tb_soc (make fw-soc-c).
 * Built with fw/bench/common/crt0.S (-DBENCH_SOC: UART BAUDDIV = 1, tohost at the end)
 * and fw/common/link.ld, for rv32i (ENABLE_M = 0) and rv32im (ENABLE_M = 1).
 *
 * Checks, in order. Each failing check returns its own code, so tohost = (code << 1) | 1:
 *   1-3   crt0: initialized .data, zeroed .bss, constant table in .rodata
 *   4-7   UART: hello line, TX done, RX loopback of one byte, no error flag
 *   8-10  GPIO: input pads (DIR = 0), output loopback (DIR = 1), restore
 *   11-13 Timer: mtime counts, CSR time matches MTIME, MTIMECMP read back
 *   14-16 Timer interrupt wakes WFI, software interrupt (MSIP), mcause values
 *   17-19 Accelerator: three 4 x 4 int8 products against the C golden model, polling
 *   20-22 Accelerator DONE through IRQC as an external interrupt, golden check
 *   23-25 UART RXNE through IRQC as an external interrupt
 *   26-28 rv32im: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU against a shift and
 *         subtract model, with the special cases (divide by 0, INT_MIN / -1).
 *         rv32i: MUL must raise an illegal instruction exception.
 * tb_soc pads: PAD_IN = 0xA5C3_0F96 on inputs, an output pin reads back its own value,
 * uart_tx loops back to uart_rx. The tb log also shows the two test bytes of the UART
 * checks (0xA7 and '<') at the start of a line.
 */
#include "bench.h"
#include "accel.h"
#include "soc_hw.h"

#define PAD_IN          0xA5C30F96u     /* tb/soc/tb_soc.v */
#define SPIN_MAX        20000u          /* Polling limit, far above any expected wait */

/* ---------------------------------------------------------------- crt0 data */
static uint32_t data_word = 0x600DF00Du;    /* .data or .sdata */
static uint32_t bss_words[4];               /* .bss, cleared by crt0 */
static const uint32_t rodata_tab[4] = { 0x11111111u, 0x22222222u, 0x44444444u, 0x88888888u };

/* ---------------------------------------------------------------- trap handler */
static volatile uint32_t n_trap;            /* Every trap */
static volatile uint32_t last_cause;
static volatile uint32_t n_mti, n_msi, n_mei;
static volatile uint32_t ext_seen;          /* IRQC PENDING bits seen by the handler */
static volatile uint32_t rx_byte;
static volatile uint32_t bad_trap;

/* Interrupts are cleared at the source. A read of the same block after the write gives the
 * level flops (timer irq, IRQC output) time to drop before mret.
 */
__attribute__((interrupt("machine"), aligned(4))) static void trap_handler(void)
{
    uint32_t cause = read_csr(mcause);

    last_cause = cause;
    n_trap = n_trap + 1;
    if (cause == MCAUSE_MTI) {
        TIMER_MTIMECMP_HI = 0xFFFFFFFFu;
        (void)TIMER_MTIMECMP_HI;
        n_mti = n_mti + 1;
    } else if (cause == MCAUSE_MSI) {
        TIMER_MSIP = 0;
        (void)TIMER_MSIP;
        n_msi = n_msi + 1;
    } else if (cause == MCAUSE_MEI) {
        uint32_t p = IRQC_PENDING;
        ext_seen |= p;
        if (p & IRQ_ACCEL)
            ACCEL_STATUS = ACCEL_STATUS_DONE;
        if (p & IRQ_UART)
            rx_byte = UART_DATA;            /* Pop RX, RXNE drops */
        (void)IRQC_PENDING;
        n_mei = n_mei + 1;
    } else if (cause == MCAUSE_ILLEGAL) {
        write_csr(mepc, read_csr(mepc) + 4);  /* Skip the 32-bit instruction */
    } else {
        bad_trap = cause;
        IRQC_ENABLE = 0;
        write_csr(mie, 0);
        write_csr(mepc, read_csr(mepc) + 4);
    }
}

/* Wait until *cnt reaches target without a race: MIE is off between the check and WFI.
 * WFI still wakes on a pending enabled interrupt, then MIE = 1 takes it.
 */
static void wait_count(volatile uint32_t *cnt, uint32_t target)
{
    for (;;) {
        clear_csr(mstatus, MSTATUS_MIE);
        if (*cnt >= target)
            break;
        __asm__ __volatile__ ("wfi" ::: "memory");
        set_csr(mstatus, MSTATUS_MIE);
    }
}

/* ---------------------------------------------------------------- 1-3 crt0 */
static int test_crt0(void)
{
    const uint32_t *t = rodata_tab;
    uint32_t sum = 0;
    int i;

    __asm__ __volatile__ ("" : "+r"(t) : : "memory");   /* Read DMEM, do not fold */
    if (data_word != 0x600DF00Du)
        return 1;
    for (i = 0; i < 4; i++)
        if (bss_words[i] != 0)
            return 2;
    for (i = 0; i < 4; i++)
        sum += t[i];
    if (sum != 0xFFFFFFFFu)
        return 3;
    return 0;
}

/* ---------------------------------------------------------------- 4-7 UART */
static int uart_tx_idle(void)
{
    uint32_t n;
    for (n = 0; n < SPIN_MAX; n++)
        if ((UART_STATUS & (UART_ST_TXE | UART_ST_TXB)) == UART_ST_TXE)
            return 1;
    return 0;
}

/* Every byte sent also arrives on RX (loopback). Empty RX and clear the error flags. */
static void uart_rx_flush(void)
{
    while (UART_STATUS & UART_ST_RXNE)
        (void)UART_DATA;
    UART_STATUS = UART_ST_ERR;
}

static int test_uart(void)
{
    uint32_t n;

    bench_printf("soc_fw: hello from soc_top, %s build\n",
#ifdef __riscv_mul
                 "rv32im"
#else
                 "rv32i"
#endif
                 );
    if (!uart_tx_idle())
        return 4;
    /* The stop bit of the last byte on RX ends before TXB drops. Read STATUS a few more
     * times anyway, then empty RX.
     */
    for (n = 0; n < 8; n++)
        (void)UART_STATUS;
    uart_rx_flush();
    if (UART_STATUS & (UART_ST_RXNE | UART_ST_ERR))
        return 5;

    UART_DATA = 0xA7;
    for (n = 0; n < SPIN_MAX && !(UART_STATUS & UART_ST_RXNE); n++)
        ;
    if (!(UART_STATUS & UART_ST_RXNE))
        return 6;
    if (UART_DATA != 0xA7 || (UART_STATUS & (UART_ST_RXNE | UART_ST_ERR)))
        return 7;
    return 0;
}

/* ---------------------------------------------------------------- 8-10 GPIO */
/* DATA_IN goes through 2 flops. A few APB reads cover that delay. */
static uint32_t gpio_in(void)
{
    (void)GPIO_DATA_IN;
    (void)GPIO_DATA_IN;
    return GPIO_DATA_IN;
}

static int test_gpio(void)
{
    if (GPIO_DIR != 0 || gpio_in() != PAD_IN)
        return 8;
    GPIO_DATA_OUT = 0x00005A3Cu;
    GPIO_DIR = 0x0000FFFFu;                 /* Low half output, high half input */
    if (GPIO_DATA_OUT != 0x00005A3Cu || gpio_in() != ((PAD_IN & 0xFFFF0000u) | 0x5A3Cu))
        return 9;
    GPIO_DATA_OUT = 0xFFFFFFFFu;
    GPIO_DIR = 0xFFFFFFFFu;
    if (gpio_in() != 0xFFFFFFFFu)
        return 10;
    GPIO_DIR = 0;
    GPIO_DATA_OUT = 0;
    if (gpio_in() != PAD_IN)
        return 10;
    return 0;
}

/* ---------------------------------------------------------------- 11-16 Timer */
static void timer_set_cmp(uint32_t lo, uint32_t hi)
{
    TIMER_MTIMECMP_HI = 0xFFFFFFFFu;        /* No spurious match while LO changes */
    TIMER_MTIMECMP_LO = lo;
    TIMER_MTIMECMP_HI = hi;
}

static int test_timer(void)
{
    uint32_t t0, t1, t2, c;

    t0 = TIMER_MTIME_LO;
    c  = read_csr(time);
    t1 = TIMER_MTIME_LO;
    if (t1 <= t0)
        return 11;
    if (c < t0 || c > t1)
        return 12;
    if (TIMER_MTIMECMP_LO != 0xFFFFFFFFu || TIMER_MTIMECMP_HI != 0xFFFFFFFFu)
        return 13;

    /* Timer interrupt 300 cycles ahead, wait in WFI */
    write_csr(mtvec, (uint32_t)trap_handler);
    t2 = TIMER_MTIME_LO;
    timer_set_cmp(t2 + 300, TIMER_MTIME_HI);
    write_csr(mie, MIE_MTIE);
    wait_count(&n_mti, 1);
    write_csr(mie, 0);
    if (n_mti != 1 || last_cause != MCAUSE_MTI)
        return 14;
    if (TIMER_MTIME_LO - t2 < 300)
        return 14;

    /* Software interrupt: MSIP = 1, the handler clears it */
    write_csr(mie, MIE_MSIE);
    TIMER_MSIP = 1;
    wait_count(&n_msi, 1);
    write_csr(mie, 0);
    if (n_msi != 1 || last_cause != MCAUSE_MSI || TIMER_MSIP != 0)
        return 15;
    if (n_trap != 2 || bad_trap)
        return 16;
    return 0;
}

/* ---------------------------------------------------------------- 17-22 Accelerator */
static int8_t  mat_a[ACCEL_N * ACCEL_N] __attribute__((aligned(4)));
static int8_t  mat_b[ACCEL_N * ACCEL_N] __attribute__((aligned(4)));
static int32_t c_hw[ACCEL_N * ACCEL_N];
static int32_t c_sw[ACCEL_N * ACCEL_N];

static void matmul_golden(void)
{
    int i, j, k;
    for (i = 0; i < ACCEL_N; i++)
        for (j = 0; j < ACCEL_N; j++) {
            int32_t s = 0;
            for (k = 0; k < ACCEL_N; k++)
                s += (int32_t)mat_a[i * ACCEL_N + k] * (int32_t)mat_b[k * ACCEL_N + j];
            c_sw[i * ACCEL_N + j] = s;
        }
}

static uint32_t lfsr = 0xACE1u;
static uint32_t rnd(void)
{
    lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB4BCD35Cu);
    return lfsr;
}

/* Set 0: random, set 1: extremes -128 and 127, set 2: identity times random */
static void fill(int set)
{
    int i;
    for (i = 0; i < ACCEL_N * ACCEL_N; i++) {
        if (set == 0) {
            mat_a[i] = (int8_t)rnd();
            mat_b[i] = (int8_t)rnd();
        } else if (set == 1) {
            mat_a[i] = (i & 1) ? 127 : -128;
            mat_b[i] = (i & 2) ? -128 : 127;
        } else {
            mat_a[i] = (i % (ACCEL_N + 1) == 0) ? 1 : 0;
            mat_b[i] = (int8_t)rnd();
        }
    }
}

static int same(void)
{
    int i;
    for (i = 0; i < ACCEL_N * ACCEL_N; i++)
        if (c_hw[i] != c_sw[i])
            return 0;
    return 1;
}

static int test_accel_poll(void)
{
    int set;
    for (set = 0; set < 3; set++) {
        fill(set);
        matmul_golden();
        accel_matmul(mat_a, mat_b, c_hw);
        if (!same()) {
            bench_printf("soc_fw: accel set %d c[0] hw %d sw %d\n", set, c_hw[0], c_sw[0]);
            return 17 + set;
        }
    }
    return 0;
}

static int test_accel_irq(void)
{
    const uint32_t *aw = (const uint32_t *)mat_a;
    const uint32_t *bw = (const uint32_t *)mat_b;
    int i;

    fill(0);
    matmul_golden();
    for (i = 0; i < ACCEL_N * ACCEL_N / 4; i++) {
        ACCEL_A_BUF[i] = aw[i];
        ACCEL_B_BUF[i] = bw[i];
    }
    ext_seen = 0;
    IRQC_ENABLE = IRQ_ACCEL;
    write_csr(mie, MIE_MEIE);
    ACCEL_CTRL = ACCEL_CTRL_START | ACCEL_CTRL_IRQ_EN;
    wait_count(&n_mei, 1);
    write_csr(mie, 0);
    IRQC_ENABLE = 0;
    ACCEL_CTRL = 0;
    if (n_mei != 1 || last_cause != MCAUSE_MEI || !(ext_seen & IRQ_ACCEL))
        return 20;
    if (ACCEL_STATUS & ACCEL_STATUS_DONE)           /* Cleared by the handler */
        return 21;
    for (i = 0; i < ACCEL_N * ACCEL_N; i++)
        c_hw[i] = ACCEL_C_BUF[i];
    if (!same())
        return 22;
    return 0;
}

/* ---------------------------------------------------------------- 23-25 UART interrupt */
static int test_uart_irq(void)
{
    uint32_t ctrl = UART_CTRL;

    if (!uart_tx_idle())
        return 23;
    uart_rx_flush();
    ext_seen = 0;
    rx_byte = 0xFFFFFFFFu;
    UART_CTRL = ctrl | UART_CTRL_RXIE;
    IRQC_ENABLE = IRQ_UART;
    write_csr(mie, MIE_MEIE);
    UART_DATA = 0x3C;
    wait_count(&n_mei, 2);
    write_csr(mie, 0);
    IRQC_ENABLE = 0;
    UART_CTRL = ctrl;
    if (n_mei != 2 || !(ext_seen & IRQ_UART))
        return 24;
    if (rx_byte != 0x3C || (UART_STATUS & (UART_ST_RXNE | UART_ST_ERR)) || IRQC_PENDING)
        return 25;
    return 0;
}

/* ---------------------------------------------------------------- 26-28 M extension */
#ifdef __riscv_mul
#define OP_RR(op, a, b) ({ uint32_t __r; \
    __asm__ __volatile__ (op " %0, %1, %2" : "=r"(__r) : "r"(a), "r"(b)); __r; })

/* Shift and add / shift and subtract models, no M instruction inside */
static uint64_t umul64(uint32_t a, uint32_t b)
{
    uint64_t r = 0;
    int i;
    for (i = 0; i < 32; i++)
        if ((b >> i) & 1u)
            r += (uint64_t)a << i;
    return r;
}

static uint32_t neg_hi(uint64_t p, int neg)
{
    if (neg)
        p = ~p + 1;
    return (uint32_t)(p >> 32);
}

static uint32_t udivrem(uint32_t n, uint32_t d, uint32_t *rem)
{
    uint32_t q = 0, r = 0;
    int i;
    for (i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) {
            r -= d;
            q |= 1u << i;
        }
    }
    *rem = r;
    return q;
}

/* Expected results for one pair, in the order mul mulh mulhsu mulhu div divu rem remu */
static void m_model(uint32_t a, uint32_t b, uint32_t *e)
{
    int32_t  sa = (int32_t)a, sb = (int32_t)b;
    uint32_t ma = sa < 0 ? 0u - a : a;
    uint32_t mb = sb < 0 ? 0u - b : b;
    uint32_t q, r;

    e[0] = (uint32_t)umul64(a, b);
    e[1] = neg_hi(umul64(ma, mb), (sa < 0) != (sb < 0));
    e[2] = neg_hi(umul64(ma, b), sa < 0);
    e[3] = (uint32_t)(umul64(a, b) >> 32);
    if (b == 0) {
        e[4] = 0xFFFFFFFFu;
        e[5] = 0xFFFFFFFFu;
        e[6] = a;
        e[7] = a;
        return;
    }
    if (a == 0x80000000u && b == 0xFFFFFFFFu) {
        e[4] = 0x80000000u;
        e[6] = 0;
    } else {
        q = udivrem(ma, mb, &r);
        e[4] = ((sa < 0) != (sb < 0)) ? 0u - q : q;
        e[6] = (sa < 0) ? 0u - r : r;
    }
    e[5] = udivrem(a, b, &e[7]);
}

static int m_pair(uint32_t a, uint32_t b)
{
    uint32_t e[8], g[8];
    int i;

    m_model(a, b, e);
    g[0] = OP_RR("mul", a, b);
    g[1] = OP_RR("mulh", a, b);
    g[2] = OP_RR("mulhsu", a, b);
    g[3] = OP_RR("mulhu", a, b);
    g[4] = OP_RR("div", a, b);
    g[5] = OP_RR("divu", a, b);
    g[6] = OP_RR("rem", a, b);
    g[7] = OP_RR("remu", a, b);
    for (i = 0; i < 8; i++)
        if (g[i] != e[i]) {
            bench_printf("soc_fw: M op %d a %x b %x got %x exp %x\n", i, a, b, g[i], e[i]);
            return 0;
        }
    return 1;
}

static const uint32_t m_special[] = {
    0u, 1u, 2u, 0xFFFFFFFFu, 0xFFFFFFFEu, 0x7FFFFFFFu, 0x80000000u, 0x0000FFFFu, 0x00010000u
};
#define N_SPECIAL   (sizeof(m_special) / sizeof(m_special[0]))

static int test_m(void)
{
    uint32_t i, j;

    for (i = 0; i < N_SPECIAL; i++)
        for (j = 0; j < N_SPECIAL; j++)
            if (!m_pair(m_special[i], m_special[j]))
                return 26;
    for (i = 0; i < 24; i++) {
        uint32_t a = rnd(), b = rnd();
        if (i & 1)
            b >>= (i & 15);                 /* Mix of divisor sizes */
        if (!m_pair(a, b))
            return 27;
    }
    if (n_trap != 2 + 2 || bad_trap)        /* No trap from M instructions */
        return 28;
    return 0;
}
#else
/* ENABLE_M = 0: MUL (OP, funct3 0, funct7 1) is an illegal instruction */
static int test_m(void)
{
    uint32_t r = 0x1234u, n = n_trap;

    __asm__ __volatile__ (".insn r 0x33, 0, 1, %0, %1, %1" : "+r"(r) : "r"(r));
    if (n_trap != n + 1 || last_cause != MCAUSE_ILLEGAL)
        return 26;
    if (r != 0x1234u)                       /* No write to rd */
        return 27;
    if (bad_trap)
        return 28;
    return 0;
}
#endif

/* ---------------------------------------------------------------- main */
typedef int (*test_fn)(void);
static const struct { const char *name; test_fn fn; } tests[] = {
    { "crt0",       test_crt0 },
    { "uart",       test_uart },
    { "gpio",       test_gpio },
    { "timer",      test_timer },
    { "accel",      test_accel_poll },
    { "accel_irq",  test_accel_irq },
    { "uart_irq",   test_uart_irq },
#ifdef __riscv_mul
    { "rv32um",     test_m },
#else
    { "no_m",       test_m },
#endif
};

int main(void)
{
    unsigned i;

    for (i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
        int rc = tests[i].fn();
        if (rc) {
            bench_printf("soc_fw: %s failed, code %d\n", tests[i].name, rc);
            return rc;
        }
        bench_printf("soc_fw: %s ok\n", tests[i].name);
    }
    bench_printf("soc_fw: all %u groups ok\n", i);
    return 0;
}
