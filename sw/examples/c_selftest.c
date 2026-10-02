// c_selftest.c — proves the C toolchain end to end on the real design.
//
// Exercises exactly the things that break silently with a bad crt0 or
// linker script: initialized globals (copied from flash), zeroed .bss,
// read-only strings in flash, the stack, multiply/divide helpers (no M
// extension), function pointers, and the Xpulse timing instructions.
// The testbench decodes the UART and compares the text line by line.
#include <stdint.h>
#include "../tinypulse.h"
#include "../tp_io.h"

#ifndef BAUD_DIV
#define BAUD_DIV 434                 // simulation builds pass 8
#endif

int32_t  counter = 41;               // .data: must arrive as 41
uint32_t zeroed[4];                  // .bss:  must arrive as zero
static const char greeting[] = "Hi from C";

static int32_t fib(int32_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }   // stack
static int32_t twice(int32_t x) { return x * 2; }
static int32_t (*volatile op)(int32_t) = twice;                                  // indirect call

int main(void) {
    UART_DIV = BAUD_DIV;
    GPIO_SEL = 0x10;                 // keep only UART TX on its function

    uart_puts(greeting); uart_putc('\n');
    counter++;
    uart_puts("data "); uart_puti(counter); uart_putc('\n');
    uart_puts("bss ");  uart_putu(zeroed[0] | zeroed[1] | zeroed[2] | zeroed[3]); uart_putc('\n');

    volatile int32_t a = -1234, b = 56;          // volatile: force real mul/div calls
    uart_puts("mul "); uart_puti(a * b);   uart_putc('\n');
    uart_puts("div "); uart_puti(a / b);   uart_putc('\n');
    uart_puts("mod "); uart_puti(a % b);   uart_putc('\n');
    uart_puts("fib "); uart_puti(fib(12)); uart_putc('\n');
    uart_puts("fn ");  uart_puti(op(21));  uart_putc('\n');

    uint32_t t0 = tp_time();
    tp_wait(t0 + 1000);              // park the core for exactly 1000 ticks
    uint32_t dt = tp_time() - t0;
    uart_puts("wait "); uart_putc(dt >= 1000 && dt < 1200 ? 'Y' : 'N'); uart_putc('\n');

    GPIO_OUT = 0xA5 & ~0x10;
    uart_puts("done\n");
    uart_flush();
    return 0;
}
