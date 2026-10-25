// bench.c - xem bench.h.
#include "bench.h"

void bench_putchar(char c)
{
    *(volatile uint32_t *)BENCH_UART_DATA = (uint8_t)c;
}

static void put_str(const char *s, int width, int left)
{
    int n = 0;
    while (s[n])
        n++;
    if (!left)
        for (; width > n; width--)
            bench_putchar(' ');
    while (*s)
        bench_putchar(*s++);
    for (; width > n; width--)
        bench_putchar(' ');
}

static void put_num(uint32_t v, unsigned base, int neg, int width, char pad, int upper)
{
    char buf[12];
    int  n = 0;
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    do {
        buf[n++] = digits[v % base];
        v /= base;
    } while (v);
    if (neg) {
        if (pad == '0') {
            bench_putchar('-');
            width--;
        } else
            buf[n++] = '-';
    }
    for (; width > n; width--)
        bench_putchar(pad);
    while (n)
        bench_putchar(buf[--n]);
}

// Supports %d %i %u %x %X %c %s %%, flags '-' '0', width, and the l prefix (long = 32 bits).
int bench_vprintf(const char *fmt, va_list ap)
{
    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            bench_putchar(*fmt);
            continue;
        }
        fmt++;
        int  left = 0, width = 0;
        char pad = ' ';
        for (; *fmt == '-' || *fmt == '0'; fmt++) {
            if (*fmt == '-')
                left = 1;
            else
                pad = '0';
        }
        for (; *fmt >= '0' && *fmt <= '9'; fmt++)
            width = width * 10 + (*fmt - '0');
        while (*fmt == 'l')
            fmt++;
        switch (*fmt) {
        case 'd':
        case 'i': {
            int32_t v = va_arg(ap, int32_t);
            put_num(v < 0 ? -(uint32_t)v : (uint32_t)v, 10, v < 0, width, pad, 0);
            break;
        }
        case 'u': put_num(va_arg(ap, uint32_t), 10, 0, width, pad, 0); break;
        case 'x': put_num(va_arg(ap, uint32_t), 16, 0, width, pad, 0); break;
        case 'X': put_num(va_arg(ap, uint32_t), 16, 0, width, pad, 1); break;
        case 'c': bench_putchar((char)va_arg(ap, int)); break;
        case 's': put_str(va_arg(ap, const char *), width, left); break;
        case '%': bench_putchar('%'); break;
        case '\0': return 0;
        default:  bench_putchar('%'); bench_putchar(*fmt); break;
        }
    }
    return 0;
}

int bench_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    bench_vprintf(fmt, ap);
    va_end(ap);
    return 0;
}

void bench_start(bench_stats_t *s)
{
    s->instret = read_csr(minstret);
    s->cycles  = read_csr(mcycle);
}

void bench_stop(bench_stats_t *s)
{
    uint32_t c = read_csr(mcycle);
    uint32_t i = read_csr(minstret);
    s->cycles  = c - s->cycles;
    s->instret = i - s->instret;
}

void bench_print_ratio(uint32_t a, uint32_t b)
{
    // a * 1000 can overflow 32 bits, so compute the integer and fractional parts separately
    uint32_t q = a / b, r = a % b;
    uint32_t frac = (uint32_t)(((uint64_t)r * 1000 + b / 2) / b);
    if (frac == 1000) {
        q++;
        frac = 0;
    }
    bench_printf("%u.%03u", q, frac);
}

void bench_report(const char *name, const bench_stats_t *s)
{
    bench_printf("BENCH %s: cycles %u, instret %u, CPI ", name, s->cycles, s->instret);
    bench_print_ratio(s->cycles, s->instret);
    bench_printf("\n");
}

// Functions gcc may call (memcpy/memset for struct and array assignment) and the string
// functions Dhrystone uses.
void *memcpy(void *dst, const void *src, size_t n)
{
    uint8_t *d = dst;
    const uint8_t *s = src;
    if ((((uintptr_t)d | (uintptr_t)s | n) & 3) == 0) {
        for (; n; n -= 4, d += 4, s += 4)
            *(uint32_t *)d = *(const uint32_t *)s;
        return dst;
    }
    while (n--)
        *d++ = *s++;
    return dst;
}

void *memset(void *dst, int c, size_t n)
{
    uint8_t *d = dst;
    while (n--)
        *d++ = (uint8_t)c;
    return dst;
}

char *strcpy(char *dst, const char *src)
{
    char *d = dst;
    while ((*d++ = *src++))
        ;
    return dst;
}

int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return (uint8_t)*a - (uint8_t)*b;
}
