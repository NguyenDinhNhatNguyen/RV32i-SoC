/* accel.h - firmware access to the accelerator wrapper (matches rtl/accel/accel_wrapper.v). */
#ifndef ACCEL_H
#define ACCEL_H
#include <stdint.h>

#define ACCEL_BASE      0x30000000u
#define ACCEL_N         4

#define ACCEL_CTRL      (*(volatile uint32_t *)(ACCEL_BASE + 0x000))
#define ACCEL_STATUS    (*(volatile uint32_t *)(ACCEL_BASE + 0x004))
#define ACCEL_INFO      (*(volatile uint32_t *)(ACCEL_BASE + 0x008))
#define ACCEL_A_BUF     ((volatile uint32_t *)(ACCEL_BASE + 0x100))
#define ACCEL_B_BUF     ((volatile uint32_t *)(ACCEL_BASE + 0x200))
#define ACCEL_C_BUF     ((volatile int32_t  *)(ACCEL_BASE + 0x300))

#define ACCEL_CTRL_START   (1u << 0)
#define ACCEL_CTRL_IRQ_EN  (1u << 1)
#define ACCEL_STATUS_BUSY  (1u << 0)
#define ACCEL_STATUS_DONE  (1u << 1)

/* C = A * B, int8 N x N matrices stored by row, polling. */
static inline void accel_matmul(const int8_t *a, const int8_t *b, int32_t *c)
{
    const uint32_t *aw = (const uint32_t *)a;
    const uint32_t *bw = (const uint32_t *)b;
    for (int i = 0; i < ACCEL_N * ACCEL_N / 4; i++) {
        ACCEL_A_BUF[i] = aw[i];
        ACCEL_B_BUF[i] = bw[i];
    }
    ACCEL_CTRL = ACCEL_CTRL_START;
    while (!(ACCEL_STATUS & ACCEL_STATUS_DONE)) { }
    for (int i = 0; i < ACCEL_N * ACCEL_N; i++)
        c[i] = ACCEL_C_BUF[i];
    ACCEL_STATUS = ACCEL_STATUS_DONE;   /* W1C */
}

#endif
