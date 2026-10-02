# What TinyPulse was checked against

TinyPulse is new, so it leans on designs and test suites that have already proven themselves —
in silicon, or as the RISC-V community's own conformance standard. This is what each one was
used for, what matched, and what changed because of it.

## The official RISC-V architecture tests — 37 of 37 pass

[riscv-non-isa/riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test), branch
`old-framework-2.x`, suite `rv32e_unratified/E`: one test per RV32E base instruction, written by
RISC-V International's test authors, each with a reference signature produced by the RISC-V
golden model. This is the conformance suite cores such as SERV are checked with.

**Result: all 37 pass — 12,521 signature words, every one identical to the reference.**
Each test is assembled with Clang, checked by `sw/rv32e_check.py`, loaded into RAM and run on
the RTL. Running from RAM matters: it is the path the UART bootloader uses, and `jal-01` alone is
14.7 MB of code, so it also exercises code spanning both RAM chips. The RAM model enforces the
datasheet's timing throughout (below), with zero violations.

```bash
cd test && make act          # fetches the suite (act/fetch.sh), ~10 minutes
```

Setting it up found two things in TinyPulse's test environment, both fixed: the arch-test bench
needed the second RAM model the other benches never had, and the signature's end marker must
not be padded.

## TinyQV — the closest silicon-proven design

[MichaelBell/tinyQV](https://github.com/MichaelBell/tinyQV): an RV32EC microcontroller for Tiny
Tapeout, 4-bit serial, on the same QSPI Pmod, in 2 × 2 tiles. It has worked in silicon on
several shuttles and runs MicroPython. TinyPulse's core is an independent implementation of the
same nibble-serial idea.

| TinyQV | TinyPulse | |
|---|---|---|
| Pmod pins: CS0 flash uio[0], SD0/SD1 uio[1..2], SCK uio[3], SD2/SD3 uio[4..5], CS1/CS2 RAM uio[6..7] | identical | matches |
| flash continuous read, mode bits 0xA0, 6 + 2 + 4 cycle preamble | identical | matches |
| RAM in QPI mode | identical | matches |
| expects the memories already set up when it starts | **wakes both itself** after every reset | TinyPulse needs no setup script |
| runs code only from flash, which "removes the need for handling the PSRAM refresh every 8 µs" | **runs code from RAM** (bootloader) | checked: every RAM transaction releases chip select within 0.88 µs; the RAM model now enforces tCEM ≤ 8 µs and tCPH ≥ 18 ns and every RAM-executing test asserts zero violations |
| silicon runs at 64 MHz with read latency 1 | 50 MHz target | the bring-up guide starts at latency 1 |
| its first silicon (TT06) had a broken UART receiver, worked around in software | UART receive is tested at unit level, through the bootloader and at gate level | a reminder to test anything that can be tested before tape-out |

## nanoV — RV32E with external memory works in silicon

[MichaelBell/nanoV](https://github.com/MichaelBell/nanoV): a minimal-area RV32E core, possibly
the first full RISC-V SoC on Tiny Tapeout (TT04), running programs from external memory. It
confirms the basic premise: RV32E with no on-chip memory is a working microcontroller.

## FazyRV-ExoTiny — waking the RAM from the chip

Another Tiny Tapeout RISC-V design on the QSPI Pmod, which "once released from reset, first
enables Quad Mode in the RAM" — the approach TinyPulse takes for both the RAM and the flash,
instead of relying on the demo board to set the memories up.

## Tiny Tapeout's own infrastructure

- [ttsky-verilog-template](https://github.com/TinyTapeout/ttsky-verilog-template): the CI
  workflows, `src/config.json` and the gate-level test setup are taken from the current template.
- [tt-micropython-firmware](https://github.com/TinyTapeout/tt-micropython-firmware): the demo
  board's SDK. `sw/demoboard/tpboot.py` uses its `DemoBoard` API and takes pin numbers from its
  own pin map (`ttboard.pins.gpio_map`) rather than hard-coding them.
- The memory chips' datasheets (Winbond W25Q128JV, AP Memory APS6404L) define the strict
  simulation models in `test/qspi_model.sv`.
