// tp_io.h — GPIO and UART from C. Pairs with tinypulse.h (the timing unit).
#ifndef TP_IO_H
#define TP_IO_H
#include <stdint.h>

#define TP_PERIPH    ((volatile uint32_t *)0x30000000u)
#define GPIO_OUT     TP_PERIPH[0]   // value on output pins in GPIO mode
#define GPIO_IN      TP_PERIPH[1]   // the eight input pins
#define GPIO_SEL     TP_PERIPH[2]   // 1 = pin shows its built-in function
#define UART_DATA    TP_PERIPH[3]
#define UART_STAT    TP_PERIPH[4]   // bit 0 TX_BUSY, 1 RX_VALID, 2 RX_OVERRUN
#define UART_DIV     TP_PERIPH[5]   // clocks per bit; 434 = 115,200 baud at 50 MHz
#define GPIO_SET     TP_PERIPH[6]
#define GPIO_CLR     TP_PERIPH[7]
#define GPIO_XOR     TP_PERIPH[8]

static inline void uart_putc(char c) { while (UART_STAT & 1u) { } UART_DATA = (uint8_t)c; }
static inline int  uart_ready(void)  { return (UART_STAT >> 1) & 1u; }
static inline char uart_getc(void)   { while (!uart_ready()) { } return (char)UART_DATA; }
static inline void uart_flush(void)  { while (UART_STAT & 1u) { } }

static inline void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

// Unsigned decimal WITHOUT dividing. TinyPulse has no hardware divider, so
// the obvious "v % 10, v / 10" loop costs two 32-step software divisions per
// digit — tens of thousands of clocks per number. Subtracting powers of ten
// takes at most 9 steps per digit.
static inline void uart_putu(uint32_t v) {
    static const uint32_t p10[10] = {1000000000u, 100000000u, 10000000u, 1000000u,
                                     100000u, 10000u, 1000u, 100u, 10u, 1u};
    int started = 0;
    for (int i = 0; i < 10; i++) {
        char d = '0';
        while (v >= p10[i]) { v -= p10[i]; d++; }
        if (d != '0' || started || i == 9) { uart_putc(d); started = 1; }
    }
}
static inline void uart_puti(int32_t v) {
    if (v < 0) { uart_putc('-'); uart_putu(-(uint32_t)v); } else uart_putu((uint32_t)v);
}
static inline void uart_puthex(uint32_t v) {
    for (int i = 28; i >= 0; i -= 4) uart_putc("0123456789abcdef"[(v >> i) & 15u]);
}
// Jump back into the boot ROM: the chip prints TP> and waits for a new
// program, like reset_usb_boot() on an RP2040.
static inline void __attribute__((noreturn)) tp_reboot_to_bootloader(void) {
    uart_flush();
    ((void (*)(void))0x40000000u)();
    __builtin_unreachable();
}
#endif
