// tp_spi.h — SPI master in software, on the GPIO pins. Mode 0 (clock idles
// low, data sampled on the rising edge), MSB first.
//
// TinyPulse has no SPI hardware — area goes to the core and the timing unit —
// but GPIO_SET / GPIO_CLR change one pin per store, so a software SPI is short
// and has no read-modify-write races. It runs at roughly 100 kHz at 50 MHz:
// fine for sensors, flash IDs and small displays.
//
// Default pins (override by defining them before including this file):
//   SCK  uo_out[1]    MOSI uo_out[2]    CS  uo_out[3] (active low)
//   MISO ui_in[4]
#ifndef TP_SPI_H
#define TP_SPI_H
#include <stdint.h>
#include "tp_io.h"

#ifndef SPI_SCK
#define SPI_SCK   (1u << 1)
#endif
#ifndef SPI_MOSI
#define SPI_MOSI  (1u << 2)
#endif
#ifndef SPI_CS
#define SPI_CS    (1u << 3)
#endif
#ifndef SPI_MISO_BIT
#define SPI_MISO_BIT 4
#endif

static inline void spi_begin(void) {
    GPIO_SEL &= ~(SPI_SCK | SPI_MOSI | SPI_CS);     // these pins become plain GPIO
    GPIO_SET = SPI_CS;                              // deselected
    GPIO_CLR = SPI_SCK | SPI_MOSI;                  // clock idles low
}
static inline void spi_select(void)   { GPIO_CLR = SPI_CS; }
static inline void spi_deselect(void) { GPIO_SET = SPI_CS; }

static inline uint8_t spi_transfer(uint8_t out) {
    uint8_t in = 0;
    for (int i = 7; i >= 0; i--) {
        if ((out >> i) & 1u) GPIO_SET = SPI_MOSI; else GPIO_CLR = SPI_MOSI;
        GPIO_SET = SPI_SCK;                                         // rising edge: both sample
        in = (uint8_t)((in << 1) | ((GPIO_IN >> SPI_MISO_BIT) & 1u));
        GPIO_CLR = SPI_SCK;
    }
    return in;
}
#endif
