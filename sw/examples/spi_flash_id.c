// spi_flash_id.c — read a SPI flash chip's JEDEC ID with the software SPI.
// On a board, wire a W25Q-series flash to SCK/MOSI/CS/MISO (see tp_spi.h);
// `make spi` runs it against a simulated W25Q128 that answers EF 40 18.
#include <stdint.h>
#include "../tp_io.h"
#include "../tp_spi.h"
#include "../tp_printf.h"
#ifndef BAUD_DIV
#define BAUD_DIV 434
#endif
int main(void) {
    UART_DIV = BAUD_DIV;
    GPIO_SEL = 0x10;                 // only UART TX keeps its function
    spi_begin();
    spi_select();
    spi_transfer(0x9F);              // JEDEC ID
    uint8_t mfr = spi_transfer(0), type = spi_transfer(0), cap = spi_transfer(0);
    spi_deselect();
    tp_printf("JEDEC ID: %02X %02X %02X\n", mfr, type, cap);
    tp_printf("%s\n", (mfr == 0xEF && type == 0x40 && cap == 0x18) ? "Winbond W25Q128 found" : "unknown chip");
    uart_flush();
    return 0;
}
