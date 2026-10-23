// stdio.h - bản rút gọn cho Dhrystone trên tb_core (không có newlib).
#ifndef BENCH_STDIO_H
#define BENCH_STDIO_H
#include "bench.h"
#define printf bench_printf
#endif
