// util.h - thay util.h của riscv-tests/benchmarks/common khi dịch Dhrystone
// cho tb_core. dhrystone_main.c chỉ cần read_csr và setStats.
// Đặt thư mục này trước trong -I để file gốc không bị dùng.
#ifndef BENCH_DHRY_UTIL_H
#define BENCH_DHRY_UTIL_H

#include "bench.h"

void setStats(int enable);

#endif
