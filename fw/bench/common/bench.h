// bench.h - minimal library for benchmarks on tb_core: print to the tb UART,
// read the mcycle/minstret counters, and a few string functions gcc and the benchmarks need.
// No newlib, to keep the code small enough for the 16 KB IMEM.
#ifndef BENCH_H
#define BENCH_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

#define BENCH_UART_DATA 0x20001000u   // Matches CORE_TB_UART_DATA in tb/core/core_tb_map.vh

#define read_csr(reg) ({ unsigned long __v; \
    __asm__ __volatile__ ("csrr %0, " #reg : "=r"(__v)); __v; })

void bench_putchar(char c);
int  bench_vprintf(const char *fmt, va_list ap);
int  bench_printf(const char *fmt, ...);

// Counters of the measured region. bench_report prints cycles, instructions and CPI (3 decimals).
typedef struct {
    uint32_t cycles;
    uint32_t instret;
} bench_stats_t;

void bench_start(bench_stats_t *s);
void bench_stop(bench_stats_t *s);
void bench_report(const char *name, const bench_stats_t *s);
// Print a/b with 3 decimals, without floating point.
void bench_print_ratio(uint32_t a, uint32_t b);

#endif
