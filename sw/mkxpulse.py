#!/usr/bin/env python3
"""mkxpulse.py — build test/xpulse.hex, a program that executes every one
of the eleven Xpulse instructions.

Written because a coverage audit found that TSTAT, TPULSE and TRATE had
never been executed by any test program. An instruction that no test runs
is an instruction you are guessing about.
"""

from mkprog import (addi, add, lui, sw, ecall,
                    TIME, TPOP, TSTAT, TWAIT, TARM, TPULSE, TMARK,
                    TADJ, TRATE, TCFG, TPW)

BASE = 13          # x13 = PSRAM base pointer

PROG = [
    (addi(8, 0, 255),   "addi x8, x0, 255      ; enable all capture channels"),
    (TCFG(8),           "tcfg x8"),
    (addi(9, 0, 32),    "addi x9, x0, 32       ; trigger pulse width"),
    (TPW(9),            "tpw  x9"),

    (TSTAT(1),          "tstat x1              ; slot 0: queue must be empty"),

    (addi(2, 0, 3),     "addi x2, x0, 3        ; trigger channels 0 and 1"),
    (TPULSE(2),         "tpulse x2             ; fire both immediately"),
    (TSTAT(3),          "tstat x3              ; slot 1: pulses still active"),

    (lui(4, 0x00800),   "lui  x4, 0x00800      ; rate = 2^23 = +0.5 tick/clock"),
    (TRATE(4),          "trate x4              ; run the timebase 1.5x fast"),

    (TIME(5),           "time x5               ; slot 2: t0"),
    (addi(6, 0, 300),   "addi x6, x0, 300"),
    (add(7, 5, 6),      "add  x7, x5, x6       ; deadline = t0 + 300 ticks"),
    (TWAIT(7),          "twait x7"),
    (TIME(10),          "time x10              ; slot 3: t1"),

    (addi(11, 0, 5),    "addi x11, x0, 5       ; software tag 5"),
    (TMARK(12, 11),     "tmark x12, x11        ; push a software event"),
    (TPOP(14),          "tpop x14              ; slot 4: pop it back"),

    (addi(15, 0, -4),   "addi x15, x0, -4"),
    (TADJ(15),          "tadj x15              ; step the timebase back by 4"),

    (lui(BASE, 0x10000), "lui  x13, 0x10000"),
    (sw(1,  BASE, 0),   "sw   x1,  0(x13)"),
    (sw(3,  BASE, 4),   "sw   x3,  4(x13)"),
    (sw(5,  BASE, 8),   "sw   x5,  8(x13)"),
    (sw(10, BASE, 12),  "sw   x10, 12(x13)"),
    (sw(14, BASE, 16),  "sw   x14, 16(x13)"),
    (ecall(),           "ecall"),
]

if __name__ == "__main__":
    import os, sys
    out = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "test", "xpulse.hex")
    with open(out, "w") as f:
        for i, (w, asm) in enumerate(PROG):
            f.write("%08x\n" % (w & 0xFFFFFFFF))
            print("%04x: %08x   %s" % (i * 4, w & 0xFFFFFFFF, asm))
    print("\nwrote %s (%d instructions)" % (out, len(PROG)))
