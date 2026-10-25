// dhry_wrap.c - runs the riscv-tests Dhrystone on tb_core.
// dhrystone_main.c is compiled with -Dmain=dhry_main. This file measures the region between
// setStats(1) and setStats(0), prints CPI and Dhrystone/MHz, then checks the final
// results (the "should be" values in the original code). On a mismatch main returns an
// error code so the tb FAILs.
#include "bench.h"

#define NUMBER_OF_RUNS 500   // Matches NUMBER_OF_RUNS in dhrystone.h

extern int  Int_Glob, Bool_Glob;
extern char Ch_1_Glob, Ch_2_Glob;
extern int  Arr_1_Glob[50], Arr_2_Glob[50][50];

int dhry_main(int argc, char **argv);

static bench_stats_t stats;

void setStats(int enable)
{
    if (enable)
        bench_start(&stats);
    else
        bench_stop(&stats);
}

int main(void)
{
    dhry_main(0, 0);

    bench_report("dhrystone", &stats);
    // Dhrystone/s at 1 MHz = runs * 10^6 / cycles.
    // DMIPS/MHz divides further by 1757 (the VAX 11/780 Dhrystone/s).
    uint32_t dps_mhz = (uint32_t)((uint64_t)NUMBER_OF_RUNS * 1000000u / stats.cycles);
    bench_printf("BENCH dhrystone: runs %u, cycles/run ", NUMBER_OF_RUNS);
    bench_print_ratio(stats.cycles, NUMBER_OF_RUNS);
    bench_printf(", Dhrystone/s/MHz %u, DMIPS/MHz ", dps_mhz);
    bench_print_ratio((uint32_t)((uint64_t)NUMBER_OF_RUNS * 1000000u / 1757u), stats.cycles);
    bench_printf("\n");

    int err = 0;
    if (Int_Glob != 5)                          err |= 1;
    if (Bool_Glob != 1)                         err |= 2;
    if (Ch_1_Glob != 'A' || Ch_2_Glob != 'B')   err |= 4;
    if (Arr_1_Glob[8] != 7)                     err |= 8;
    if (Arr_2_Glob[8][7] != NUMBER_OF_RUNS + 10) err |= 16;
    bench_printf("BENCH dhrystone: %s\n", err ? "final values WRONG" : "final values OK");
    return err;
}
