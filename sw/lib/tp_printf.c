// tp_printf.c — see tp_printf.h.
#include <stdarg.h>
#include <stdint.h>
#include "../tp_io.h"
#include "../tp_printf.h"

// Print digits held least-significant-first in buf, with an optional sign,
// padded to `width` the way C does: spaces go before the sign, zeros after it.
static int emit_digits(char *buf, int n, int width, char pad, int negative) {
    int count = 0, len = n + negative;
    if (pad == ' ') for (int i = len; i < width; i++) { uart_putc(' '); count++; }
    if (negative) { uart_putc('-'); count++; }
    if (pad == '0') for (int i = len; i < width; i++) { uart_putc('0'); count++; }
    while (n) { uart_putc(buf[--n]); count++; }
    return count;
}

static int put_unsigned(uint32_t v, int width, char pad, int negative) {
    static const uint32_t p10[10] = {1000000000u, 100000000u, 10000000u, 1000000u,
                                     100000u, 10000u, 1000u, 100u, 10u, 1u};
    char buf[10]; int n = 0, started = 0;
    char tmp[10]; int t = 0;
    for (int i = 0; i < 10; i++) {
        char d = '0';
        while (v >= p10[i]) { v -= p10[i]; d++; }
        if (d != '0' || started || i == 9) { tmp[t++] = d; started = 1; }
    }
    while (t) buf[n++] = tmp[--t];                     // least significant first
    return emit_digits(buf, n, width, pad, negative);
}

static int put_hex(uint32_t v, int width, char pad, int upper) {
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    char buf[8]; int n = 0;
    do { buf[n++] = digits[v & 15u]; v >>= 4; } while (v);
    return emit_digits(buf, n, width, pad, 0);
}

int tp_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int count = 0;
    for (; *fmt; fmt++) {
        if (*fmt != '%') { uart_putc(*fmt); count++; continue; }
        fmt++;
        char pad = ' ';
        int width = 0;
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
        switch (*fmt) {
        case 'd': case 'i': {
            int32_t v = va_arg(ap, int32_t);
            count += put_unsigned(v < 0 ? -(uint32_t)v : (uint32_t)v, width, pad, v < 0);
            break;
        }
        case 'u': count += put_unsigned(va_arg(ap, uint32_t), width, pad, 0); break;
        case 'x': count += put_hex(va_arg(ap, uint32_t), width, pad, 0); break;
        case 'X': count += put_hex(va_arg(ap, uint32_t), width, pad, 1); break;
        case 'c': uart_putc((char)va_arg(ap, int)); count++; break;
        case 's': {
            const char *s = va_arg(ap, const char *);
            int len = 0; while (s[len]) len++;
            for (int i = len; i < width; i++) { uart_putc(' '); count++; }
            while (*s) { uart_putc(*s++); count++; }
            break;
        }
        case '%': uart_putc('%'); count++; break;
        case '\0': fmt--; break;                        // stray % at the end
        default: uart_putc('%'); uart_putc(*fmt); count += 2; break;
        }
    }
    va_end(ap);
    return count;
}
