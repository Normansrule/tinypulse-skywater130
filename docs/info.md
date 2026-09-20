## How it works

TinyPulse-Skywater130 is a RISC-V core whose instruction set treats **time as an
operand**. It pairs a 2-stage RV32I core with a hardware timebase, an event
capture queue and deadline-driven trigger outputs, and joins them with ten
custom instructions in the RISC-V custom-0 opcode space.

The problem it solves is sensor time alignment. On a microcontroller, the gap
between a pin moving and software reading a timer is one interrupt latency —
tens of microseconds, and it varies from event to event. That variance, not
the sensors, is what limits fusion quality on cheap robots. TinyPulse timestamps
in hardware at one-clock resolution with a constant two-clock latency, and
drives its trigger outputs from a hardware comparator so the output edge lands
on the exact tick that was programmed.

- **Timebase** — 32-bit, one tick per core clock (20 ns at 50 MHz). A 24-bit
  fractional accumulator slews the rate at about 0.06 parts per million per
  count, so it can be disciplined against an external pulse-per-second
  reference without ever stepping backwards.
- **Capture** — 8 inputs, each with a two-flop synchroniser and edge detect.
  All channels share one ordered event queue, so the *order* of events across
  channels is preserved. That ordering is the thing you are trying to measure.
- **Compare** — 3 trigger outputs. Arm one with an absolute timebase value and
  the pin fires on that tick with zero jitter, whatever the core is doing.
- **Core** — RV32E register set (16 registers), full RV32I instruction set, no
  multiply, no compressed extension, no control and status registers. Code
  runs from an external QSPI flash, data from an external QSPI pseudo-static
  RAM (PSRAM).

The headline instruction is `TWAIT rs1`: the core stops until the timebase
reaches an exact value, then resumes. No interrupt, no polling loop, no
software jitter.

## How to test

The repository has six self-checking testbenches, 207 assertions in total,
which need only Icarus Verilog:

```
cd test && make sim
```

They cover each block standalone; a full system boot that arms a deadline 400
ticks out, injects a capture edge while the core is parked in `TWAIT` and
checks the trigger pin fired on tick 400 exactly; every RV32I instruction
against expectations computed independently in Python; eight capture channels
edging on the same clock; the 2^32 timebase rollover at both block and system
level; and the same instruction-set test re-run against the larger 2x2 build
profile. `make lint` runs Verilator with `-Wall` and is clean.

On hardware: wire a QSPI flash to `uio[0:4]` and `uo[7]`, hold `ui[2:0]` at
the flash read latency while reset is low (see the README's bring-up section —
this is the setting most likely to be wrong on the first attempt), release
reset, and watch `uo[6]` for a heartbeat. Drive any of `ui[0:7]` and the event
pin `uo[2]` goes high.

## External hardware

- **QSPI NOR flash** (W25Q128 or similar) on `uio[0:3]` data, `uio[4]` chip
  select, `uo[7]` clock. Holds the program. Must be left in continuous read
  mode — the controller streams sequential fetches without re-issuing an
  address, which is where most of the speed comes from.
- **QSPI PSRAM** (APS6404 or similar) sharing the data bus, chip select on
  `uio[5]`. Holds writable data and the stack.
- Whatever you are synchronising: camera strobe returns, inertial measurement
  unit data-ready lines, encoder index pulses, lidar sync — on `ui[0:7]`.
- Trigger destinations (camera shutter, strobe, scope) on `uo[0]`, `uo[1]`,
  `uio[6]`.
