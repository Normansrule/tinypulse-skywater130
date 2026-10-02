# Bringing up TinyPulse on a real board

**This guide needs a fabricated TinyPulse chip.** It exists only after the design has been
submitted to a Tiny Tapeout shuttle and manufactured, which takes months. Until then, a demo board
cannot run TinyPulse: selecting `tt_um_normansrule_tinypulse` fails because it isn't on that chip.
To write and run programs today, use the simulator: `cd test && make run PROG=../sw/examples/hello.c`
(see the README).

Everything here has been checked in simulation, at gate level, and against strict models of the
real memory chips. Where a step depends on something only a board can confirm, it says so.

**Windows / WSL2:** a USB device plugged into Windows is not visible inside WSL2 by default. Either
run `mpremote` from Windows itself (`python -m pip install mpremote`, then `python -m mpremote` in
PowerShell), or forward the demo board into WSL2 with [usbipd-win](https://github.com/dorssel/usbipd-win):
in an administrator PowerShell, `usbipd list`, then `usbipd bind --busid <id>` once, then
`usbipd attach --wsl --busid <id>` each time you plug it in.

## What you need

- a Tiny Tapeout demo board with the chip that contains TinyPulse
- the **Tiny Tapeout QSPI Pmod** (16 MB flash + two 8 MB RAMs), plugged into the bidirectional
  (uio) Pmod header
- a USB-C cable, and a computer with Python 3

That's all. A separate USB-to-UART adapter is optional (see "Full speed" below).

## 1. First power-up: is it alive?

Select `tt_um_normansrule_tinypulse` in the Tiny Tapeout Commander (or from the demo board's
MicroPython: `tt.shuttle.tt_um_normansrule_tinypulse.enable()`), clock it at 50 MHz, and release
reset. With no program at all, the outputs already show their built-in functions:

| Pin | What you should see |
|---|---|
| `uo_out[7]` HEARTBEAT | blinking about 3 times a second (bit 23 of the timebase at 50 MHz) |
| `uo_out[4]` UART TX | steady high (idle) |
| `uo_out[5]` HALT, `uo_out[6]` ILLEGAL | low, unless an empty or erased flash made the core run into garbage |

**If the heartbeat doesn't blink, nothing else will work** — the clock or reset isn't reaching
the design. On the demo board's 7-segment display, the heartbeat is one segment.

## 2. Set the memory read latency

TinyPulse samples `ui_in[2:0]` while reset is held and uses it as the QSPI read latency, to make
up for the delay through the Tiny Tapeout pads and the Pmod wiring. TinyQV, a similar design on
the same Pmod, runs with latency 1 at 64 MHz on real silicon, so **start with `ui_in[2:0] = 1`**
(`ui_in[0]` high during reset). If programs misbehave, try 2; at low clock rates, 0 also works.
`tpboot.py` sets 1 for you.

The memory chips themselves need no setup: 2 µs after every reset TinyPulse puts the flash into
continuous quad read and both RAMs into QPI mode, whatever state they were left in.

## 3. Program it — three ways

### a. Over the demo board's own USB-C port (nothing else needed)

`sw/demoboard/tpboot.py` runs on the demo board and acts as the serial cable. It clocks TinyPulse
at 4.17 MHz, which makes the chip's UART exactly 9600 baud (434 clocks per bit, the reset value),
a rate MicroPython can bit-bang reliably.

```bash
python -m pip install mpremote ziglang pyelftools
cd sw && make TOOLCHAIN=zig RAM=1                    # camera_sync.bin, linked for RAM
mpremote cp demoboard/tpboot.py :tpboot.py
mpremote cp camera_sync.bin :app.bin
mpremote exec "import tpboot; tpboot.load('app.bin')"
```

It holds `ui_in[7]` high through reset (the boot strap), waits for `TP>`, sends the program,
checks the chip's checksum, then prints whatever your program sends. The protocol and bit timing
are tested on a PC against a simulated chip with 15 µs timing jitter, ±2 % clock error and
counter wrap-around (`python3 sw/demoboard/test_tpboot.py`); the board-specific parts — the SDK
calls and pin numbers, which come from the SDK's own pin map — can only be confirmed on a board.

Trade-off: at 4.17 MHz your program runs 12× slower than at 50 MHz, and any timing constants
in it scale the same way.

### b. Full speed, with a USB-UART adapter

Wire any 3.3 V USB-to-UART adapter: its TX to `ui_in[3]`, its RX to `uo_out[4]`, ground to ground.
Clock TinyPulse at 50 MHz, hold `ui_in[7]` high and `ui_in[0]` high while releasing reset, then:

```bash
python3 sw/tpload.py -p /dev/ttyUSB0 camera_sync.bin --monitor      # 115,200 baud
```

### c. Permanently, from flash

Build without `RAM=1` and write `camera_sync.bin` to the Pmod's flash with the
[Tiny Tapeout Flasher](https://tinytapeout.com/guides/configure-flash-qspi-pmod/) while the design
is held in reset (TinyPulse releases the Pmod pins during reset). Release reset with `ui_in[7]`
low and it runs from flash on every power-up. To see its output through the demo board:
`mpremote exec "import tpboot; tpboot.console()"`.

## When something is wrong

| Symptom | Likely cause |
|---|---|
| no heartbeat | clock or reset not reaching the design, or the wrong project selected |
| HALT goes high immediately | the program ran off the end (flash erased or empty): reprogram it |
| ILLEGAL goes high | the core fetched garbage: try another read latency (step 2), or check the Pmod is on the bidirectional header |
| no `TP>` in boot mode | `ui_in[7]` not high during reset, or TX/RX swapped |
| `TP>` appears but the load fails | baud mismatch: the clock must be baud × 434 (4.17 MHz for 9600, 50 MHz for 115,200) |
| program loads, prints garbage | it changed `UART_DIV`; keep the reset value when using `tpboot.py` |

## Timing

A static timing estimate from the real cell library (`cd test && make timing`, needs a native
Yosys): the slowest register-to-register path is about **6.9 ns** once high-fanout nets are
buffered, against 20 ns at 50 MHz. Wires typically add 30–50 % at this size, which still leaves
about 2× margin. The routed timing report from the `gds` GitHub Actions job is the one to trust.
