// hello.c — the smallest useful TinyPulse program. Try it on the simulated
// chip today:   cd test && make run PROG=../sw/examples/hello.c
#include <stdint.h>
#include "../tinypulse.h"
#include "../tp_io.h"

#ifndef BAUD_DIV
#define BAUD_DIV 434                 // make run passes 8 to keep simulation fast
#endif

int main(void) {
    UART_DIV = BAUD_DIV;
    GPIO_SEL = 0x10;                 // uo_out[4] stays UART TX; the rest are GPIO

    uart_puts("Hello from TinyPulse!\n");

    // Wake up every 100,000 clocks (2 ms at 50 MHz). tp_wait parks the core
    // until the timebase reaches the deadline, so the time read straight after
    // it lands the same few clocks past each deadline, however long the
    // printing in between took — as long as the printing finishes before the
    // next deadline. On this chip one line with three numbers costs about
    // 37,000 clocks (roughly 25 clocks per instruction), hence the spacing.
    uint32_t t0 = tp_time();
    for (uint32_t i = 1; i <= 5; i++) {
        uint32_t deadline = t0 + i * 100000u;
        tp_wait(deadline);
        uint32_t woke = tp_time();
        GPIO_XOR = 0x80;                            // blink uo_out[7]
        uart_puts("tick "); uart_putu(i);
        uart_puts(": deadline t0+"); uart_putu(deadline - t0);
        uart_puts(", woke "); uart_putu(woke - deadline); uart_puts(" clocks after\n");
    }
    uart_puts("bye\n");
    uart_flush();
    return 0;
}
