// util.h - replaces util.h of riscv-tests/benchmarks/common when compiling Dhrystone
// for tb_core. dhrystone_main.c only needs read_csr and setStats.
// Put this directory first in -I so the original file is not used.
#ifndef BENCH_DHRY_UTIL_H
#define BENCH_DHRY_UTIL_H

#include "bench.h"

void setStats(int enable);

#endif
