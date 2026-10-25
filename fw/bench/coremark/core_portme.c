// core_portme.c - port CoreMark cho tb_core (xem core_portme.h).
#include <stdarg.h>
#include "coremark.h"
#include "bench.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

static bench_stats_t stats;

void start_time(void)
{
    bench_start(&stats);
}

void stop_time(void)
{
    bench_stop(&stats);
}

CORE_TICKS get_time(void)
{
    return stats.cycles;
}

// Assume 1 MHz: seconds = cycles / 10^6
secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks / 1000000u;
}

int ee_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    bench_vprintf(fmt, ap);
    va_end(ap);
    return 0;
}

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR! Please define ee_ptr_int to a type that holds a pointer!\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR! Please define ee_u32 to a 32b unsigned type!\n");
    p->portable_id = 1;
}

// CoreMark/MHz = iterations * 10^6 / cycles
void portable_fini(core_portable *p)
{
    p->portable_id = 0;
    bench_report("coremark", &stats);
    bench_printf("BENCH coremark: iterations %u, cycles/iter ", (unsigned)ITERATIONS);
    bench_print_ratio(stats.cycles, ITERATIONS);
    bench_printf(", CoreMark/MHz ");
    bench_print_ratio((uint32_t)ITERATIONS * 1000000u, stats.cycles);
    bench_printf("\n");
}
