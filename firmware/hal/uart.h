/*
 * hal/uart.h — UART Hardware Abstraction Layer
 * =============================================
 * Base: 0x0000_6000 | Block: 16550-Compatible UART (Debug Console)
 * Source: REGISTER_MAP.md §7
 */

#ifndef HAL_UART_H
#define HAL_UART_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define UART_HAL_BASE           0x00006000UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define UART_RBR_OFFSET         0x00U   /* RX Buffer (DLAB=0)              */
#define UART_THR_OFFSET         0x00U   /* TX Holding (DLAB=0)             */
#define UART_DLL_OFFSET         0x00U   /* Divisor Latch LSB (DLAB=1)      */
#define UART_DLM_OFFSET         0x04U   /* Divisor Latch MSB (DLAB=1)      */
#define UART_IER_OFFSET         0x04U   /* Interrupt Enable (DLAB=0)       */
#define UART_IIR_OFFSET         0x08U   /* Interrupt Identification        */
#define UART_FCR_OFFSET         0x08U   /* FIFO Control                    */
#define UART_LCR_OFFSET         0x0CU   /* Line Control                    */
#define UART_MCR_OFFSET         0x10U   /* Modem Control                   */
#define UART_LSR_OFFSET         0x14U   /* Line Status                     */
#define UART_MSR_OFFSET         0x18U   /* Modem Status                    */
#define UART_SCR_OFFSET         0x1CU   /* Scratch                         */

/* ---- Absolute Register Addresses ---- */
#define UART_RBR                (UART_HAL_BASE + UART_RBR_OFFSET)
#define UART_THR                (UART_HAL_BASE + UART_THR_OFFSET)
#define UART_DLL                (UART_HAL_BASE + UART_DLL_OFFSET)
#define UART_DLM                (UART_HAL_BASE + UART_DLM_OFFSET)
#define UART_IER                (UART_HAL_BASE + UART_IER_OFFSET)
#define UART_IIR                (UART_HAL_BASE + UART_IIR_OFFSET)
#define UART_FCR                (UART_HAL_BASE + UART_FCR_OFFSET)
#define UART_LCR                (UART_HAL_BASE + UART_LCR_OFFSET)
#define UART_MCR                (UART_HAL_BASE + UART_MCR_OFFSET)
#define UART_LSR                (UART_HAL_BASE + UART_LSR_OFFSET)
#define UART_MSR                (UART_HAL_BASE + UART_MSR_OFFSET)
#define UART_SCR                (UART_HAL_BASE + UART_SCR_OFFSET)

/* ---- LCR Bit Definitions ---- */
#define UART_LCR_WLS_5          0x00U
#define UART_LCR_WLS_6          0x01U
#define UART_LCR_WLS_7          0x02U
#define UART_LCR_WLS_8          0x03U
#define UART_LCR_STB            0x04U
#define UART_LCR_PAR_NONE       0x00U
#define UART_LCR_PAR_ODD        0x08U
#define UART_LCR_PAR_EVEN       0x18U
#define UART_LCR_PAR_MARK       0x28U
#define UART_LCR_PAR_SPACE      0x38U
#define UART_LCR_BRK            0x40U
#define UART_LCR_DLAB           0x80U

/* ---- LSR Bit Definitions ---- */
#define UART_LSR_DR             0x01U
#define UART_LSR_OE             0x02U
#define UART_LSR_PE             0x04U
#define UART_LSR_FE             0x08U
#define UART_LSR_BI             0x10U
#define UART_LSR_THRE           0x20U
#define UART_LSR_TEMT           0x40U
#define UART_LSR_RXFIFOERR      0x80U

/* ---- IER Bit Definitions ---- */
#define UART_IER_RX_AVAIL       0x01U
#define UART_IER_TX_EMPTY       0x02U
#define UART_IER_RX_STAT        0x04U
#define UART_IER_MODEM          0x08U

/* ---- FCR Bit Definitions ---- */
#define UART_FCR_FIFO_EN        0x01U
#define UART_FCR_RX_FIFO_CLR    0x02U
#define UART_FCR_TX_FIFO_CLR    0x04U

/* ---- Baud Rate Divisors (sys_clk = 100 MHz → Divisor = sys_clk / (16 × baud)) ---- */
#define UART_BAUD_115200_DLL    54U
#define UART_BAUD_115200_DLM    0U
#define UART_BAUD_57600_DLL     108U
#define UART_BAUD_57600_DLM     0U
#define UART_BAUD_38400_DLL     163U
#define UART_BAUD_38400_DLM     0U
#define UART_BAUD_19200_DLL     326U
#define UART_BAUD_19200_DLM     1U
#define UART_BAUD_9600_DLL      651U
#define UART_BAUD_9600_DLM      2U

/* ---- Inline MMIO Helpers ---- */
static inline void uart_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(UART_HAL_BASE + offset)) = value;
}

static inline uint32_t uart_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(UART_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_UART_H */
