#!/usr/bin/env python3
"""printf_check.py — tp_printf against Python's own % formatting.

Writes printf_cases.c (one tp_printf call per case) and printf_expect.txt
(Python's rendering of the same format strings), for `make printf`.
"""
CASES = [
    ("%d", -1234), ("%d", 0), ("%d", 2147483647), ("%d", -2147483648),
    ("%5d", 42), ("%5d", -42), ("%05d", 42), ("%05d", -42), ("%i", 7),
    ("%u", 4294967295), ("%u", 0), ("%8u", 123), ("%08u", 123),
    ("%x", 0xDEADBEEF), ("%X", 0xDEADBEEF), ("%08x", 0x1F), ("%2x", 0xABC), ("%x", 0),
    ("%c", ord("Z")), ("%s", "TinyPulse"), ("%10s", "right"), ("%%", None),
    ("t=%u id=%08x", (1000, 0x2A)),
]
c, expect = [], []
for fmt, arg in CASES:
    args = arg if isinstance(arg, tuple) else ((arg,) if arg is not None else ())
    py_args = tuple(chr(a) if "%c" in fmt else a for a in args)
    expect.append("[" + (fmt % py_args if args else fmt % ()) + "]\n")
    c_args = []
    for a in args:
        if isinstance(a, str): c_args.append('"' + a + '"')
        elif a > 2147483647:   c_args.append(f"{a}u")
        elif a == -2147483648: c_args.append("(int32_t)0x80000000")
        else:                  c_args.append(f"(int32_t){a}")
    c.append(f'    tp_printf("[{fmt}]\\n"' + "".join(", " + x for x in c_args) + ");")
open("printf_cases.c", "w").write(
    '#include <stdint.h>\n#include "../sw/tp_io.h"\n#include "../sw/tp_printf.h"\n'
    "#ifndef BAUD_DIV\n#define BAUD_DIV 434\n#endif\n"
    "int main(void) {\n    UART_DIV = BAUD_DIV;\n    GPIO_SEL = 0x10;\n" + "\n".join(c) +
    "\n    uart_flush();\n    return 0;\n}\n")
open("printf_expect.txt", "w").write("".join(expect))
print(f"{len(CASES)} printf cases generated")
