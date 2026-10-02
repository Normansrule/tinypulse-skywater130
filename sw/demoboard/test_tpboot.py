#!/usr/bin/env python3
"""test_tpboot.py — tpboot.py's UART and boot protocol, tested on a PC.

Runs the real BitBangUart and bootload() from tpboot.py against a simulated
TinyPulse boot ROM, in virtual time, with the things that go wrong on a real
demo board:
  * every tick read costs a random 1-15 us (MicroPython overhead, USB IRQs)
  * the chip's baud rate is off by up to +/-2% (the RP's clock generator
    cannot hit 4,166,400 Hz exactly)
  * the microsecond counter wraps every 2^30 us, as MicroPython's does
"""
import bisect, random, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import tpboot

PERIOD = 1 << 30                                    # MicroPython ticks wrap here


class Clock:
    def __init__(self, start, jitter, seed):
        self.t = float(start); self.jitter = jitter; self.rng = random.Random(seed)
    def ticks_us(self):
        self.t += 1 + self.rng.random() * self.jitter
        return int(self.t) % PERIOD
    @staticmethod
    def ticks_add(a, b): return (a + b) % PERIOD
    @staticmethod
    def ticks_diff(a, b): return ((a - b + PERIOD // 2) % PERIOD) - PERIOD // 2


class FakeTinyPulse:
    """The boot ROM's behaviour, seen from its two pins."""
    def __init__(self, clock, rate_error, reply_sum_error=0, banner=True, after=b"Hi\n"):
        self.clock = clock
        self.bit = 1e6 / (tpboot.BAUD * (1 + rate_error))
        self.frames = []                              # (start time, byte) it transmits
        self.edges_t, self.edges_v = [clock.t], [1]   # what the bridge drove on its TX
        self.cursor = clock.t
        self.got = bytearray()
        self.need = None
        self.sum_error, self.after = reply_sum_error, after
        self.done = False
        if banner: self._send(clock.t + 500, b"TP>")

    def _send(self, t, data):
        for b in data:
            self.frames.append((t, b)); t += 10 * self.bit + 3

    def tx_pin(self, level):                          # bridge -> chip
        if level != self.edges_v[-1]:
            self.edges_t.append(self.clock.t); self.edges_v.append(level)

    def _level_in(self, t):
        return self.edges_v[bisect.bisect_right(self.edges_t, t) - 1]

    def _decode(self):
        now = self.clock.t
        while True:
            i = bisect.bisect_right(self.edges_t, self.cursor)
            fall = next((self.edges_t[j] for j in range(i, len(self.edges_t))
                         if self.edges_v[j] == 0 and self.edges_v[j - 1] == 1), None)
            if fall is None or now < fall + 10 * self.bit:
                return
            v = sum(self._level_in(fall + (k + 1.5) * self.bit) << k for k in range(8))
            assert self._level_in(fall + 9.5 * self.bit) == 1, "bridge sent a bad stop bit"
            self.got.append(v); self.cursor = fall + 9.5 * self.bit
            if self.need is None and len(self.got) == 4:
                self.need = int.from_bytes(self.got[:4], "little") + 4
            if self.need is not None and len(self.got) == self.need and not self.done:
                self.done = True
                s = (sum(self.got[4:]) + self.sum_error) & 255
                self._send(now + 200, bytes([s]) + b"K" + self.after)

    def rx_pin(self):                                 # chip -> bridge
        self._decode()
        t = self.clock.t
        for start, b in self.frames:
            k = int((t - start) // self.bit)
            if 0 <= k <= 9:
                return 0 if k == 0 else (1 if k == 9 else (b >> (k - 1)) & 1)
        return 1


def run(image, rate_error=0.0, jitter=15, start=0, seed=1, **chip):
    clk = Clock(start, jitter, seed)
    chip_ = FakeTinyPulse(clk, rate_error, **chip)
    uart = tpboot.BitBangUart(chip_.tx_pin, chip_.rx_pin, tpboot.BAUD,
                              clk.ticks_us, clk.ticks_add, clk.ticks_diff)
    ok = tpboot.bootload(uart, image, log=lambda *a: None)
    after = bytearray()
    if ok:
        for _ in range(3):
            b = uart.read(100)
            if b is None: break
            after.append(b)
    return ok, bytes(chip_.got[4:]), bytes(after)


checks = fails = 0
def check(cond, what):
    global checks, fails
    checks += 1; fails += (not cond)
    print(("  ok    " if cond else "  FAIL  ") + what)

img = bytes((i * 37 + 11) & 255 for i in range(300))
print("=== tpboot.py against a simulated TinyPulse boot ROM ===")
ok, got, after = run(img)
check(ok, "a clean load is verified (15 us of jitter per tick read)")
check(got == img, "the chip received all 300 bytes, in order")
check(after == b"Hi\n", "the bridge then relays what the program prints")
for err in (+0.02, -0.02):
    ok, got, _ = run(img, rate_error=err, seed=7)
    check(ok and got == img, f"works with the chip's baud off by {err:+.0%}")
ok, got, _ = run(img, start=PERIOD - 50_000, seed=3)
check(ok and got == img, "works across the 2^30 us tick-counter wrap")
ok, _, _ = run(img, reply_sum_error=1)
check(not ok, "a wrong checksum from the chip is reported as a failure")
ok, _, _ = run(img, banner=False)
check(not ok, "no TP> banner times out cleanly instead of hanging")
payload, s = tpboot.frame_program(b"\x01\x02\x03")
check(payload[:4] == b"\x03\x00\x00\x00" and s == 6, "length is little endian; checksum is the byte sum")
check(tpboot.CLOCK_HZ == 9600 * 434, "chip clock is baud x the UART divider's reset value")
print(f"\n{checks} checks, {fails} failures")
sys.exit(1 if fails else 0)
