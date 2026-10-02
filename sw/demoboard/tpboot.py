# tpboot.py — program and talk to TinyPulse through the demo board's own USB-C
# port. No USB-UART adapter, no flasher. Runs ON the Tiny Tapeout demo board
# (MicroPython + the ttboard SDK that ships on it).
#
# From your PC:
#     pip install mpremote
#     mpremote cp sw/demoboard/tpboot.py :tpboot.py
#     mpremote cp app.bin :app.bin                        # built with: make RAM=1
#     mpremote exec "import tpboot; tpboot.load('app.bin')"
# or, for a program already in flash, just watch its serial output:
#     mpremote exec "import tpboot; tpboot.console()"
#
# How: the demo board's RP2350 drives TinyPulse's ui_in pins and reads its
# uo_out pins, so it can act as the serial cable itself. It bit-bangs the
# UART on ui_in[3] (TinyPulse RX) and uo_out[4] (TinyPulse TX) at 9600 baud,
# a rate MicroPython can time reliably. Rather than change anything on the
# chip, it CLOCKS TinyPulse at 9600 x 434 = 4.17 MHz: the chip's UART divider
# resets to 434 clocks per bit, so the chip ends up at exactly 9600 baud.
#
# Trade-off: your program runs at 4.17 MHz, not 50. Everything is 12x slower
# and time constants in your code scale with the clock. For full speed, use a
# 3.3 V USB-UART adapter and sw/tpload.py at 115,200 baud with a 50 MHz clock.
#
# Programs must keep UART_DIV at its reset value (434) for this bridge.
#
# Status: the protocol and bit timing are tested on a PC against a simulated
# chip with timing jitter (sw/demoboard/test_tpboot.py). It has not yet been
# run on a real board, because there is no TinyPulse silicon yet.

import time

PROJECT = "tt_um_normansrule_tinypulse"
BAUD = 9600
UART_DIV = 434                       # TinyPulse's reset value
CLOCK_HZ = BAUD * UART_DIV           # 4,166,400 Hz
LATENCY = 1                          # QSPI read latency strap, ui_in[2:0]


class BitBangUart:
    """8N1 UART on two plain GPIOs, timed with the microsecond tick counter."""

    def __init__(self, tx, rx, baud, ticks_us, ticks_add, ticks_diff,
                 irq_off=None, irq_on=None):
        self.tx, self.rx = tx, rx
        self.bit = 1_000_000 / baud
        self.ticks_us, self.ticks_add, self.ticks_diff = ticks_us, ticks_add, ticks_diff
        self.irq_off = irq_off or (lambda: 0)
        self.irq_on = irq_on or (lambda s: None)
        self.tx(1)

    def _until(self, t):
        while self.ticks_diff(t, self.ticks_us()) > 0:
            pass

    def write(self, data):
        for b in data:
            state = self.irq_off()
            t0 = self.ticks_us()
            frame = [0] + [(b >> i) & 1 for i in range(8)] + [1]
            for i, level in enumerate(frame):
                self.tx(level)
                self._until(self.ticks_add(t0, int((i + 1) * self.bit)))
            self.irq_on(state)

    def read(self, timeout_ms):
        """One byte, or None if nothing starts within timeout_ms."""
        start = self.ticks_us()
        limit = timeout_ms * 1000
        while self.rx():                                   # wait for the start bit
            if self.ticks_diff(self.ticks_us(), start) > limit:
                return None
        state = self.irq_off()
        t0 = self.ticks_us()
        self._until(self.ticks_add(t0, int(self.bit / 2)))
        if self.rx():                                      # a glitch, not a start bit
            self.irq_on(state)
            return self.read(timeout_ms)
        value = 0
        for i in range(8):
            self._until(self.ticks_add(t0, int((i + 1.5) * self.bit)))
            value |= (self.rx() & 1) << i
        self._until(self.ticks_add(t0, int(9.5 * self.bit)))   # into the stop bit
        self.irq_on(state)
        return value


def frame_program(image):
    n = len(image)
    return bytes([n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255]) + image, sum(image) & 255


def bootload(uart, image, log=print):
    """Talk to TinyPulse's boot ROM. Returns True if the chip verified the load."""
    seen = b""
    while not seen.endswith(b"TP>"):
        c = uart.read(3000)
        if c is None:
            log("no TP> from the chip: is it selected, clocked, and strapped for boot?")
            return False
        seen += bytes([c])
    payload, want = frame_program(image)
    log("bootloader ready, sending %d bytes (about %d s at %d baud)"
        % (len(image), len(payload) * 10 // BAUD + 1, BAUD))
    uart.write(payload)
    got_sum, got_k = uart.read(2000), uart.read(2000)
    if got_k != ord("K") or got_sum != want:
        log("load failed: chip answered %r %r, expected checksum %d and K" % (got_sum, got_k, want))
        return False
    log("verified; running from 0x1000_0000")
    return True


def _board(boot):
    from ttboard.demoboard import DemoBoard
    from ttboard.pins.gpio_map import GPIOMap
    import machine
    tt = DemoBoard.get()
    getattr(tt.shuttle, PROJECT).enable()
    tt.reset_project(True)
    tt.ui_in.value = (0x80 if boot else 0) | 0x08 | LATENCY   # boot strap, RX idle, latency
    tt.clock_project_PWM(CLOCK_HZ)
    tx = machine.Pin(GPIOMap.UI_IN3, machine.Pin.OUT)
    rx = machine.Pin(GPIOMap.UO_OUT4, machine.Pin.IN)
    uart = BitBangUart(tx.value, rx.value, BAUD, time.ticks_us, time.ticks_add,
                       time.ticks_diff, machine.disable_irq, machine.enable_irq)
    time.sleep_ms(2)            # RAM needs 150 us after power-up; be generous
    tt.reset_project(False)
    return uart


def _monitor(uart, seconds):
    import sys
    idle_since = time.ticks_ms()
    while seconds is None or time.ticks_diff(time.ticks_ms(), idle_since) < seconds * 1000:
        b = uart.read(200)
        if b is not None:
            sys.stdout.write(chr(b))
            idle_since = time.ticks_ms()


def load(path, monitor_seconds=None):
    """Send a RAM-linked program (make RAM=1) and show what it prints."""
    image = open(path, "rb").read()
    uart = _board(boot=True)
    if bootload(uart, image):
        _monitor(uart, monitor_seconds)


def console(monitor_seconds=None):
    """Run the program in flash and show what it prints."""
    _monitor(_board(boot=False), monitor_seconds)
