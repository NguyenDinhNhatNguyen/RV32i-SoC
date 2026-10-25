// string.h - minimal version for Dhrystone, functions are in fw/bench/common/bench.c.
#ifndef BENCH_STRING_H
#define BENCH_STRING_H
#include <stddef.h>
void *memcpy(void *dst, const void *src, size_t n);
char *strcpy(char *dst, const char *src);
int   strcmp(const char *a, const char *b);
#endif
