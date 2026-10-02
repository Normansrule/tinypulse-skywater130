# Verification

Run everything with `cd test && make sim && make && make lint`, plus `make act` for the official RISC-V tests.


**Every command to test everything is in [docs/TESTING.md](docs/TESTING.md).**

| Test | What it proves | Checks |
|---|---|---:|
| `make isa` | every RV32I instruction, vs. Python-computed results | 51 |
| `make unit` | timing unit blocks, rotating register file, UART, GPIO | 48 |
| `make stress` | 8 simultaneous captures, queue overflow, 2³² rollover | 18 |
| `make xpulse` | all eleven Xpulse instructions | 15 |
| `make soc` | boots, arms a deadline, trigger lands on the exact tick | 12 |
| `make wrap` | `TWAIT` held correctly across the timebase rollover | 10 |
| `make boot` | UART bootloader: a program sent over serial lands in RAM and runs | 11 |
| `make wake` | the chip wakes the flash and RAM itself, from cold, warm and pre-set states | 14 |
| `make c` | Clang-compiled C, run from flash and over the UART bootloader, output checked | 12 |
| `make act` | **the official RISC-V architecture tests** (riscv-arch-test, RV32E): signatures vs the golden model, run from RAM | **37 / 37** (12,521 words) |
| `make bridge` | the demo-board bridge vs a simulated chip: jitter, ±2% clock error, counter wrap | 10 |
| `make printf` | `tp_printf` against Python's `%` formatting, 23 cases | 23 |
| `make spi` | software SPI reads a simulated W25Q128's JEDEC ID | 2 |
| Tiny Tapeout pre-flight | CI's own project checker (`tt_tool.py`): docs, ports, build config | passes |
| `make timing` | critical-path estimate from real sky130 cell delays | 6.9 ns / 20 ns |
| `make` (cocotb) | from the pins only: firmware printing over the UART, the boot strap | 6 |
| `make GATES=yes` | the same cocotb tests on the synthesized sky130 netlist | 5 + 1 skipped |
| `tpload.py selftest` | the PC-side loader: framing, checksum, error cases | 7 |
| `make lint` | Verilator `-Wall`, no waivers | clean |

TinyPulse was cross-checked against the RISC-V conformance suite and against TinyQV, the
closest silicon-proven design; [docs/REFERENCES.md](docs/REFERENCES.md) lists what matched and
what changed. One item stands out: TinyQV avoids the RAM's 8 µs refresh rule by never running
code from RAM, while TinyPulse deliberately does (for the bootloader), so the RAM model now
enforces the datasheet's chip-select timing and every test that runs code from RAM checks it.

The memory models are strict: like the real chips, they ignore fast transactions until they
have been woken up properly. An earlier version of the models was forgiving, and hid the fact
that the chip never woke its memories — it simulated perfectly and would not have run a single
instruction on a real board. Making the models strict exposed that, and the wake-up sequence
fixed it.

Compiling real C for the first time found two more bugs that no hand-assembled test could:
the flash linker script put initialized globals in RAM with no copy stored in flash, and the
start-up code never copied them. Any program with `int x = 5;` at file scope would have been
broken on the board. Both are fixed, and putting the bug back makes `make c` fail loudly: the
program prints `data 1` instead of `data 42`, then calls a function pointer that was never
initialized and restarts itself forever.

The tests were checked against themselves: six deliberate bugs were injected (a register-file
nibble mis-write, UART sampling at the bit edge, `GPIO_CLR` acting as toggle, signed compares
treated as unsigned, arithmetic shifts losing the sign, a dropped carry between nibbles), and
the suite caught every one. One test was too weak to catch the `GPIO_CLR` bug at first; it was
strengthened.

