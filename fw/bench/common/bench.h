// bench.h - thư viện tối giản cho benchmark trên tb_core: in ra UART của tb,
// đọc bộ đếm mcycle/minstret, vài hàm chuỗi mà gcc và benchmark cần.
// Không dùng newlib để mã nhỏ, vừa IMEM 16 KB.
#ifndef BENCH_H
#define BENCH_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

#define BENCH_UART_DATA 0x20001000u   // khớp CORE_TB_UART_DATA trong tb/core/core_tb_map.vh

#define read_csr(reg) ({ unsigned long __v; \
    __asm__ __volatile__ ("csrr %0, " #reg : "=r"(__v)); __v; })

void bench_putchar(char c);
int  bench_vprintf(const char *fmt, va_list ap);
int  bench_printf(const char *fmt, ...);

// Bộ đếm của vùng đo. bench_report in số chu kỳ, số lệnh, CPI (3 chữ số thập phân).
typedef struct {
    uint32_t cycles;
    uint32_t instret;
} bench_stats_t;

void bench_start(bench_stats_t *s);
void bench_stop(bench_stats_t *s);
void bench_report(const char *name, const bench_stats_t *s);
// In a/b với 3 chữ số thập phân, không dùng số thực.
void bench_print_ratio(uint32_t a, uint32_t b);

#endif
