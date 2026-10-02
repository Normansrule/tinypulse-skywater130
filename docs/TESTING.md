# Testing everything

Every command runs from `test/` inside the repository. On Ubuntu under WSL2 with a conda
environment active, `python -m pip` installs into the environment you're in; if a later step
says a module is missing, install with `python3 -m pip` instead, since the Makefile calls `python3`.

## One-time setup

```bash
sudo apt install iverilog verilator yosys          # simulator, linter, synthesis
python -m pip install cocotb pytest ziglang pyelftools
```

`ziglang` provides the C compiler (Clang, targeting RV32E) and `pyelftools` reads the compiled
programs. A sky130 PDK (for `make area`, `make timing` and `make gl`) is expected at `~/pdk/sky130A`;
point elsewhere with `PDK_ROOT=` or `LIB=`.

## The everyday run — about 5 minutes

```bash
cd ~/tinypulse-skywater130/test
make sim        # all twelve self-checking suites, 226 checks
make            # the cocotb tests, from the pins only (6 tests)
make lint       # Verilator -Wall, no waivers
```

Each testbench ends with a line like `51 checks, 0 failures`. `make sim` covers:

| Bench | Checks | What it proves |
|---|---:|---|
| unit | 48 | timing-unit blocks, rotating register file, UART, GPIO |
| soc | 12 | boots, arms a deadline, the trigger lands on the exact tick |
| isa | 51 | every RV32I instruction vs Python-computed results |
| stress | 18 | 8 simultaneous captures, queue overflow, 2³² rollover |
| wrap | 10 | `TWAIT` across the timebase rollover |
| xpulse | 15 | all eleven timing instructions |
| boot | 11 | the UART bootloader, end to end, with RAM timing checked |
| wake | 14 | the chip wakes the flash and RAM from cold, warm and pre-set states |
| c | 12 | a Clang-compiled C program from flash and via the bootloader |
| bridge | 10 | the demo-board bridge vs a simulated chip with jitter and clock error |
| printf | 23 | `tp_printf`, character for character against Python's `%` formatting |
| spi | 2 | the software SPI reads a simulated W25Q128 flash's JEDEC ID (`EF 40 18`) |

## Run your own program on the simulated chip

```bash
make run PROG=../sw/examples/hello.c              # or any C file of yours
```

## The deeper checks

```bash
make act        # the official RISC-V architecture tests: 37/37 RV32E, about 10 minutes
make gl         # synthesize to sky130 gates and rerun the cocotb tests on the netlist
make area       # real cell area against the sky130 library (expect ~49,186 µm²)
make timing     # critical-path estimate from real cell delays (expect ~6.9 ns vs 20 ns)
```

`make act` downloads the suite the first time (`act/fetch.sh`) and prints one line per
instruction, ending in `37 of 37 official RV32E tests pass`.

## The software side

```bash
python3 ../sw/tpload.py selftest                  # the PC-side UART loader, 7 checks
python3 ../sw/demoboard/test_tpboot.py            # the demo-board bridge, 10 checks (also in make sim)
cd ../sw && make TOOLCHAIN=zig && make TOOLCHAIN=zig RAM=1    # build the example for flash and RAM
```

## Regenerating the images

```bash
cd ~/tinypulse-skywater130
python3 docs/tools/figures.py                      # pinout, block diagram, scale
python3 docs/tools/animations.py                   # the animated diagrams
python3 -m pip install klayout pillow
python3 docs/tools/layout_preview.py ~/pdk/sky130A/libs.ref/sky130_fd_sc_hd    # cell-level layout
python3 docs/tools/zoom_animation.py               # the tile-to-transistor zoom
python3 docs/tools/exploded_cell.py ~/pdk/sky130A/libs.ref/sky130_fd_sc_hd     # the exploded flip-flop
python3 docs/tools/build_explorer.py               # the interactive explorer page
```

## Tiny Tapeout's own pre-flight check

The `gds` workflow starts by running Tiny Tapeout's project checker. You can run the same
checker first, in its own Python environment (its pinned packages would otherwise change your
conda environment):

```bash
python3 -m venv ~/tt-venv && . ~/tt-venv/bin/activate
cd ~/tinypulse-skywater130
git clone --depth 1 https://github.com/TinyTapeout/tt-support-tools tt
pip install -r tt/requirements.txt
python tt/tt_tool.py --check-docs            # expect: Documentation check passed successfully.
python tt/tt_tool.py --create-user-config    # expect: creating include file (reads every source with CI's Yosys)
deactivate
```

Both pass. `tt/` and the generated `src/user_config.json` are git-ignored; CI makes its own.

## A note on test builds

Every test compiles C from scratch in a private, freshly wiped cache. Zig's build cache judges
whether a header changed partly by its timestamp, and during mutation testing a source that was
broken and restored within the same second was once built from the stale broken version. A test
result has to come from the code on disk, so the tests never trust a cache.

## After pushing to GitHub

The `gds` workflow hardens the design with the full Tiny Tapeout flow (LibreLane). When it
succeeds, the `viewer` job publishes the real routed layout to GitHub Pages — enable
**Settings → Pages → Source: GitHub Actions** once — at:

- `https://normansrule.github.io/tinypulse-skywater130/gds_render.png` (image)
- `https://normansrule.github.io/tinypulse-skywater130/` (opens the 3D viewer)

The `test` workflow runs the cocotb tests on the post-layout netlist. Its routing and timing
reports are the final word on whether the design fits and meets 50 MHz.
