// accel_bench.c - EVA-01: speedup of the matrix multiply accelerator on soc_top (tb_soc).
// Problem: C = A * B with 16 x 16 int8 matrices (signed, like the Lab 2 core), int32 result.
// Three versions, each checked against the software result:
//   sw    plain C on the core (rv32i: multiply in libgcc, rv32im: MUL instruction)
//   poll  tiled into 4 x 4 blocks on the accelerator (64 block multiplies), wait on STATUS.DONE
//   irq   same tiling, wait with WFI for the accelerator interrupt through IRQC (bit 1)
// Each version is timed with mcycle/minstret. One block is also timed phase by phase to show
// the APB overhead: load A and B, START until DONE, read C and accumulate, clear DONE.
// main returns 0 when every result matches, so crt0 writes tohost = 1.
#include "bench.h"
#include "accel.h"

#define M       16                      // Matrix size, a multiple of ACCEL_N
#define NB      (M / ACCEL_N)           // Blocks per row or column

#define IRQC_PENDING    (*(volatile uint32_t *)0x20006000u)
#define IRQC_ENABLE     (*(volatile uint32_t *)0x20006004u)
#define IRQ_ACCEL       (1u << 1)       // SOC_IRQ_ACCEL in rtl/bus/soc_map.vh
#define MCAUSE_MEI      0x8000000Bu
#define MIE_MEIE        (1u << 11)
#define MSTATUS_MIE     (1u << 3)

#define write_csr(reg, v) __asm__ __volatile__ ("csrw " #reg ", %0" :: "r"(v) : "memory")
#define set_csr(reg, v)   __asm__ __volatile__ ("csrs " #reg ", %0" :: "r"(v) : "memory")
#define clear_csr(reg, v) __asm__ __volatile__ ("csrc " #reg ", %0" :: "r"(v) : "memory")

static int8_t  mat_a[M * M] __attribute__((aligned(4)));
static int8_t  mat_b[M * M] __attribute__((aligned(4)));
static int32_t c_sw[M * M];
static int32_t c_poll[M * M];
static int32_t c_irq[M * M];

static volatile uint32_t irq_done;      // Set by the handler for each accelerator interrupt
static volatile uint32_t irq_count;
static volatile uint32_t irq_bad;       // Unexpected mcause or IRQC PENDING value

// Deterministic data that also covers the extremes -128 and 127
static void fill(void)
{
    uint32_t x = 0x1234567u;
    for (int i = 0; i < M * M; i++) {
        x = x * 1664525u + 1013904223u;
        mat_a[i] = (int8_t)(x >> 24);
        x = x * 1664525u + 1013904223u;
        mat_b[i] = (int8_t)(x >> 24);
    }
    mat_a[0] = -128;
    mat_b[0] = -128;
    mat_a[1] = 127;
    mat_b[M] = 127;
}

static void matmul_sw(int32_t *c)
{
    for (int i = 0; i < M; i++)
        for (int j = 0; j < M; j++) {
            int32_t s = 0;
            for (int k = 0; k < M; k++)
                s += mat_a[i * M + k] * mat_b[k * M + j];
            c[i * M + j] = s;
        }
}

// Rows of a 4 x 4 block are 4 contiguous bytes, so each row is one word (A_BUF and B_BUF
// use the same byte order).
static inline void load_block(int bi, int bj, int bk)
{
    for (int r = 0; r < ACCEL_N; r++) {
        ACCEL_A_BUF[r] = *(const uint32_t *)&mat_a[(bi * ACCEL_N + r) * M + bk * ACCEL_N];
        ACCEL_B_BUF[r] = *(const uint32_t *)&mat_b[(bk * ACCEL_N + r) * M + bj * ACCEL_N];
    }
}

static inline void read_block(int32_t *acc)
{
    for (int t = 0; t < ACCEL_N * ACCEL_N; t++)
        acc[t] += ACCEL_C_BUF[t];
}

static inline void store_block(int32_t *c, int bi, int bj, const int32_t *acc)
{
    for (int r = 0; r < ACCEL_N; r++)
        for (int q = 0; q < ACCEL_N; q++)
            c[(bi * ACCEL_N + r) * M + bj * ACCEL_N + q] = acc[r * ACCEL_N + q];
}

static void matmul_poll(int32_t *c)
{
    for (int bi = 0; bi < NB; bi++)
        for (int bj = 0; bj < NB; bj++) {
            int32_t acc[ACCEL_N * ACCEL_N] = {0};
            for (int bk = 0; bk < NB; bk++) {
                load_block(bi, bj, bk);
                ACCEL_CTRL = ACCEL_CTRL_START;
                while (!(ACCEL_STATUS & ACCEL_STATUS_DONE))
                    ;
                read_block(acc);
                ACCEL_STATUS = ACCEL_STATUS_DONE;
            }
            store_block(c, bi, bj, acc);
        }
}

// The handler clears DONE at the accelerator (the source), then reads PENDING once more:
// the IRQC output has a flop, and the APB read takes long enough for it to drop.
__attribute__((interrupt("machine"), aligned(4))) static void trap_handler(void)
{
    if (read_csr(mcause) != MCAUSE_MEI || !(IRQC_PENDING & IRQ_ACCEL)) {
        irq_bad = 1;
        IRQC_ENABLE = 0;
        return;
    }
    ACCEL_STATUS = ACCEL_STATUS_DONE;
    (void)IRQC_PENDING;
    irq_count = irq_count + 1;
    irq_done = 1;
}

// Wait for the interrupt without a race: MIE is off between the flag check and WFI. WFI still
// wakes on a pending enabled interrupt, then setting MIE takes it on the next instruction
// (D-038, docs/spec/core.md section 4.8).
static inline void wait_irq(void)
{
    for (;;) {
        clear_csr(mstatus, MSTATUS_MIE);
        if (irq_done)
            break;
        __asm__ __volatile__ ("wfi" ::: "memory");
        set_csr(mstatus, MSTATUS_MIE);
    }
    set_csr(mstatus, MSTATUS_MIE);
}

static void matmul_irq(int32_t *c)
{
    for (int bi = 0; bi < NB; bi++)
        for (int bj = 0; bj < NB; bj++) {
            int32_t acc[ACCEL_N * ACCEL_N] = {0};
            for (int bk = 0; bk < NB; bk++) {
                load_block(bi, bj, bk);
                irq_done = 0;
                ACCEL_CTRL = ACCEL_CTRL_START | ACCEL_CTRL_IRQ_EN;
                wait_irq();
                read_block(acc);
            }
            store_block(c, bi, bj, acc);
        }
}

static int compare(const int32_t *c)
{
    for (int i = 0; i < M * M; i++)
        if (c[i] != c_sw[i])
            return 1;
    return 0;
}

static void report_speedup(const char *name, const bench_stats_t *ref, const bench_stats_t *s)
{
    bench_printf("BENCH accel: speedup %s ", name);
    bench_print_ratio(ref->cycles, s->cycles);
    bench_printf("\n");
}

// One block (bi = bj = bk = 0) with polling, phase by phase
static void phases(void)
{
    int32_t  acc[ACCEL_N * ACCEL_N] = {0};
    uint32_t t0, t1, t2, t3, t4;
    t0 = read_csr(mcycle);
    load_block(0, 0, 0);
    t1 = read_csr(mcycle);
    ACCEL_CTRL = ACCEL_CTRL_START;
    while (!(ACCEL_STATUS & ACCEL_STATUS_DONE))
        ;
    t2 = read_csr(mcycle);
    read_block(acc);
    t3 = read_csr(mcycle);
    ACCEL_STATUS = ACCEL_STATUS_DONE;
    t4 = read_csr(mcycle);
    bench_printf("BENCH accel: block phases (cycles, each includes 1 csrr): load A+B %u, "
                 "start to DONE %u, read C %u, clear DONE %u, total %u\n",
                 t1 - t0, t2 - t1, t3 - t2, t4 - t3, t4 - t0);
}

int main(void)
{
    bench_stats_t s_sw, s_poll, s_irq;
    int err = 0;

    fill();

    bench_start(&s_sw);
    matmul_sw(c_sw);
    bench_stop(&s_sw);

    bench_start(&s_poll);
    matmul_poll(c_poll);
    bench_stop(&s_poll);

    write_csr(mtvec, (uint32_t)trap_handler);
    IRQC_ENABLE = IRQ_ACCEL;
    set_csr(mie, MIE_MEIE);
    bench_start(&s_irq);
    matmul_irq(c_irq);
    bench_stop(&s_irq);
    clear_csr(mstatus, MSTATUS_MIE);
    clear_csr(mie, MIE_MEIE);
    IRQC_ENABLE = 0;

    bench_report("accel_sw", &s_sw);
    bench_report("accel_poll", &s_poll);
    bench_report("accel_irq", &s_irq);
    report_speedup("poll", &s_sw, &s_poll);
    report_speedup("irq", &s_sw, &s_irq);
    phases();

    if (compare(c_poll))
        err |= 1;
    if (compare(c_irq))
        err |= 2;
    if (irq_bad || irq_count != NB * NB * NB)
        err |= 4;
    uint32_t sum = 0;
    for (int i = 0; i < M * M; i++)
        sum = sum * 31u + (uint32_t)c_sw[i];
    bench_printf("BENCH accel: %u block multiplies, %u interrupts, checksum %08x, %s\n",
                 NB * NB * NB, irq_count, sum, err ? "results WRONG" : "results OK");
    return err;
}
