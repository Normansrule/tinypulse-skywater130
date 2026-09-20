#!/usr/bin/env python3
"""mkwrap.py — build test/wrap.hex: a program that drives the timebase to
just below the 2^32 rollover and then sets a deadline on the far side of it.

TWAIT and the compare unit both use a signed difference so this works. If
either used an unsigned >=, this program would sail straight through the
TWAIT and fire the trigger 85 seconds early, and no ordinary test would
ever notice.
"""

from mkprog import addi, add, lui, sw, ecall, TIME, TARM, TWAIT, TADJ

STEP     = -1000     # jump the timebase back to just below the wrap
LEAD     = 1500      # deadline this far ahead, which lands past zero

PROG = [
    (addi(1, 0, STEP),  f"addi x1, x0, {STEP}"),
    (TADJ(1),           "tadj x1              ; timebase -> just under 2^32"),
    (TIME(2),           "time x2              ; t0, near the wrap"),
    (addi(3, 0, LEAD),  f"addi x3, x0, {LEAD}"),
    (add(4, 2, 3),      "add  x4, x2, x3      ; deadline, wrapped past zero"),
    (addi(5, 0, 0),     "addi x5, x0, 0       ; compare channel 0"),
    (TARM(4, 5),        "tarm x4, x5          ; arm across the rollover"),
    (TWAIT(4),          "twait x4             ; must NOT return immediately"),
    (TIME(6),           "time x6              ; t1, after the wrap"),
    (lui(7, 0x10000),   "lui  x7, 0x10000"),
    (sw(2, 7, 0),       "sw   x2, 0(x7)       ; slot 0 = t0"),
    (sw(4, 7, 4),       "sw   x4, 4(x7)       ; slot 1 = deadline"),
    (sw(6, 7, 8),       "sw   x6, 8(x7)       ; slot 2 = t1"),
    (ecall(),           "ecall"),
]

if __name__ == "__main__":
    import os, sys
    out = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "test", "wrap.hex")
    with open(out, "w") as f:
        for i, (w, asm) in enumerate(PROG):
            f.write("%08x\n" % (w & 0xFFFFFFFF))
            print("%04x: %08x   %s" % (i * 4, w & 0xFFFFFFFF, asm))
    print("\nwrote %s" % out)
