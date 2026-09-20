# Prototyping TinyPulse-Skywater130 on an FPGA

Prototype before you tape out. The ASIC run then becomes a re-run of
something that already works rather than a first attempt, which matters when
a mistake costs a shuttle slot and three months.

## What to instantiate

Instantiate `tp_soc` directly, not `tt_um_normansrule_tinypulse`. The Tiny
Tapeout wrapper only exists to map onto the fixed 24-pin tile interface; on a
board you have real pins.

```systemverilog
tp_soc #(
    .NREG(16), .AW(4), .RESET_PC(32'h0000_0000),
    .BARREL(1'b1),        // FPGAs have LUTs to spare: use the barrel shifter
    .BIMODAL(1'b1),       // and the real predictor
    .HAS_CPU(1'b1),
    .NCH(8), .NCMP(3), .DEPTH(8), .PTRW(3), .FRACW(24), .FILTW(3)
) u_soc ( ... );
```

Turning on `BARREL`, `BIMODAL`, a deeper queue and the glitch filter gives you
the 2x2 profile. Run the testbenches against **both** parameter sets — the
point of prototyping is to catch things the default build does differently,
not to validate a configuration you are not taping out.

## Clocking

`sck` is generated as core clock / 2 from a register, not a gated clock, so
it goes out through a normal pin. On an FPGA, constrain it as a generated
clock if your flash model needs it; for a real flash, keep the trace short
and check the read latency setting, same as on silicon.

## What to measure on the bench

The three numbers this design lives or dies by:

1. **Capture latency.** Scope a capture pin against `evt_pulse`. Two clock
   periods, every time, with no spread.
2. **Trigger jitter.** Arm a deadline in a loop and scope the trigger output
   against a stable reference. The histogram should be a single bin.
3. **The comparison.** Implement the same timestamp-and-trigger function on an
   RP2040 in C, run both from the same signal source, and overlay the two
   histograms. That one figure is the entire argument for the chip.

## Suggested boards

Any board with a QSPI flash and PSRAM you can reach, plus enough spare
input/output for the eight capture channels. An iCE40UP5K board with attached
PSRAM works and keeps the toolchain open source; an Artix-7 board gives you
more headroom to run the 2x2 profile at speed.

## Constraints

Not included here, because they are board-specific and a wrong constraints
file that looks authoritative is worse than none. Write them for your board:
clock period, the eight capture inputs as asynchronous (they are — that is
what the synchronisers are for), and false paths on the reset.
