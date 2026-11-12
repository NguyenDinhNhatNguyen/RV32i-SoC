/* soc_hw.h - register map of the soc_top peripherals for C firmware.
 * Addresses from rtl/bus/soc_map.vh, offsets and bits from the RTL of each block
 * (the files in rtl/periph). The accelerator is in fw/accel.h.
 * Every peripheral takes 32-bit accesses only. Any other access returns PSLVERR,
 * which the core turns into an access fault.
 */
#ifndef SOC_HW_H
#define SOC_HW_H
#include <stdint.h>

#define REG32(a)            (*(volatile uint32_t *)(a))

/* Timer (CLINT style), 0x2000_0000 */
#define TIMER_BASE          0x20000000u
#define TIMER_MTIME_LO      REG32(TIMER_BASE + 0x00)
#define TIMER_MTIME_HI      REG32(TIMER_BASE + 0x04)
#define TIMER_MTIMECMP_LO   REG32(TIMER_BASE + 0x08)    /* Reset value 0xFFFF_FFFF */
#define TIMER_MTIMECMP_HI   REG32(TIMER_BASE + 0x0C)    /* Reset value 0xFFFF_FFFF */
#define TIMER_MSIP          REG32(TIMER_BASE + 0x10)

/* UART 8N1, 0x2000_1000 */
#define UART_BASE           0x20001000u
#define UART_DATA           REG32(UART_BASE + 0x00)     /* Write pushes TX, read pops RX */
#define UART_STATUS         REG32(UART_BASE + 0x04)
#define UART_CTRL           REG32(UART_BASE + 0x08)
#define UART_BAUDDIV        REG32(UART_BASE + 0x0C)
#define UART_ST_TXF         (1u << 0)                   /* TX FIFO full */
#define UART_ST_TXE         (1u << 1)                   /* TX FIFO empty */
#define UART_ST_TXB         (1u << 2)                   /* Shifter busy */
#define UART_ST_RXF         (1u << 3)
#define UART_ST_RXNE        (1u << 4)
#define UART_ST_ERR         (7u << 5)                   /* OVR, FE, TXOVF: write 1 to clear */
#define UART_CTRL_TXEN      (1u << 0)
#define UART_CTRL_RXEN      (1u << 1)
#define UART_CTRL_TXIE      (1u << 2)
#define UART_CTRL_RXIE      (1u << 3)
#define UART_CTRL_ERRIE     (1u << 4)

/* GPIO, 0x2000_2000 */
#define GPIO_BASE           0x20002000u
#define GPIO_DATA_OUT       REG32(GPIO_BASE + 0x00)
#define GPIO_DATA_IN        REG32(GPIO_BASE + 0x04)     /* Read only, 2-flop synchronizer */
#define GPIO_DIR            REG32(GPIO_BASE + 0x08)     /* 1 = output */

/* Interrupt controller, 0x2000_6000. Level sources, output to the core MEIP. */
#define IRQC_BASE           0x20006000u
#define IRQC_PENDING        REG32(IRQC_BASE + 0x00)     /* Read only */
#define IRQC_ENABLE         REG32(IRQC_BASE + 0x04)
#define IRQ_UART            (1u << 0)
#define IRQ_ACCEL           (1u << 1)

/* Machine mode CSR bits */
#define MSTATUS_MIE         (1u << 3)
#define MIE_MSIE            (1u << 3)
#define MIE_MTIE            (1u << 7)
#define MIE_MEIE            (1u << 11)
#define MCAUSE_MSI          0x80000003u
#define MCAUSE_MTI          0x80000007u
#define MCAUSE_MEI          0x8000000Bu
#define MCAUSE_ILLEGAL      2u

#define write_csr(reg, v)   __asm__ __volatile__ ("csrw " #reg ", %0" :: "r"(v) : "memory")
#define set_csr(reg, v)     __asm__ __volatile__ ("csrs " #reg ", %0" :: "r"(v) : "memory")
#define clear_csr(reg, v)   __asm__ __volatile__ ("csrc " #reg ", %0" :: "r"(v) : "memory")

#endif
