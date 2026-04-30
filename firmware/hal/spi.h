/*
 * hal/spi.h — SPI Master Controller Hardware Abstraction Layer
 * =============================================================
 * Base: 0x0000_2000 | Block: SPI Master (LIDAR Sensor Interface)
 * Source: REGISTER_MAP.md §3
 */

#ifndef HAL_SPI_H
#define HAL_SPI_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Base Address ---- */
#define SPI_HAL_BASE            0x00002000UL

/* ---- Register Offsets (32-bit aligned) ---- */
#define SPI_CTRL_OFFSET         0x00U
#define SPI_STATUS_OFFSET       0x04U
#define SPI_CLKDIV_OFFSET       0x08U
#define SPI_TXDATA_OFFSET       0x0CU
#define SPI_RXDATA_OFFSET       0x10U
#define SPI_CS_OFFSET           0x14U
#define SPI_INTR_MASK_OFFSET    0x18U
#define SPI_INTR_STATUS_OFFSET  0x1CU

/* ---- Absolute Register Addresses ---- */
#define SPI_CTRL                (SPI_HAL_BASE + SPI_CTRL_OFFSET)
#define SPI_STATUS              (SPI_HAL_BASE + SPI_STATUS_OFFSET)
#define SPI_CLKDIV              (SPI_HAL_BASE + SPI_CLKDIV_OFFSET)
#define SPI_TXDATA              (SPI_HAL_BASE + SPI_TXDATA_OFFSET)
#define SPI_RXDATA              (SPI_HAL_BASE + SPI_RXDATA_OFFSET)
#define SPI_CS                  (SPI_HAL_BASE + SPI_CS_OFFSET)
#define SPI_INTR_MASK           (SPI_HAL_BASE + SPI_INTR_MASK_OFFSET)
#define SPI_INTR_STATUS         (SPI_HAL_BASE + SPI_INTR_STATUS_OFFSET)

/* ---- SPI_CTRL Bits ---- */
#define SPI_CTRL_ENABLE         (1U << 0)
#define SPI_CTRL_CPOL           (1U << 1)
#define SPI_CTRL_CPHA           (1U << 2)
#define SPI_CTRL_MSTEN          (1U << 3)
#define SPI_CTRL_LSBFE          (1U << 4)
#define SPI_CTRL_AUTOCS         (1U << 5)
#define SPI_CTRL_TX_FIFO_CLR    (1U << 8)
#define SPI_CTRL_RX_FIFO_CLR    (1U << 9)
#define SPI_CTRL_CLK_EN         (1U << 10)
#define SPI_CTRL_SOFT_RST       (1U << 11)

#define SPI_MODE_0              0x00000000UL
#define SPI_MODE_3              (SPI_CTRL_CPOL | SPI_CTRL_CPHA)

/* ---- SPI_STATUS Bits ---- */
#define SPI_STAT_TX_EMPTY       (1U << 0)
#define SPI_STAT_TX_FULL        (1U << 1)
#define SPI_STAT_RX_EMPTY       (1U << 2)
#define SPI_STAT_RX_FULL        (1U << 3)
#define SPI_STAT_TX_BUSY        (1U << 4)

/* ---- SPI Clock Dividers @ 100 MHz ---- */
#define SPI_DIV_25MHZ           2U
#define SPI_DIV_10MHZ           5U
#define SPI_DIV_5MHZ            10U
#define SPI_DIV_500KHZ          100U

/* ---- Inline MMIO Helpers ---- */
static inline void spi_hal_write(uint32_t offset, uint32_t value) {
    *((volatile uint32_t *)(SPI_HAL_BASE + offset)) = value;
}

static inline uint32_t spi_hal_read(uint32_t offset) {
    return *((volatile uint32_t *)(SPI_HAL_BASE + offset));
}

#ifdef __cplusplus
}
#endif

#endif /* HAL_SPI_H */
