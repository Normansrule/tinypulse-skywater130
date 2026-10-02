// tp_printf.h — printf over the UART, sized for a chip with no divider.
//
//   tp_printf("t=%u us, id=%08x, name=%s\n", t, id, "x5");
//
// Supports %d %i %u %x %X %c %s %%, an optional '0' flag and a field width
// (e.g. %08x, %5d). Decimal output uses subtraction by powers of ten, not
// division, so a number costs hundreds of clocks rather than tens of
// thousands. Implemented in lib/tp_printf.c.
#ifndef TP_PRINTF_H
#define TP_PRINTF_H
int tp_printf(const char *fmt, ...);
#endif
