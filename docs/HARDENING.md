# Hardening TinyPulse-Skywater130

Everything in this file is work that has to happen on your machine, because
it needs the SkyWater sky130 process design kit (PDK) and a full
place-and-route flow. Simulation and lint are done; this is the part that
turns register-transfer level (RTL) code into a layout.

Order matters. Do not skip to step 4.

---

## What is already known, so you can check the tools against it

| Quantity | Value | Where it came from |
|---|---|---|
| Flip-flops | **1,373** flattened, 1,369 by module | `yosys -s syn/synth_check.ys`, exact |
| Generic cells before technology mapping | 10,317 | same run |
| Latches inferred | **0** | the `select -assert-none t:$dlatch` in that script |
| Self-checking simulation assertions | 207, all passing | `cd test && make sim` |
| Verilator `-Wall` | clean | `cd test && make lint` |

If your synthesis run disagrees with the flip-flop count by more than a few,
something is different about your setup and it is worth understanding before
you continue.

---

## Step 0 — versions, because this is where the time goes

```bash
yosys -V          # need >= 0.44
verilator --version
iverilog -V | head -1
```

Ubuntu and Debian ship an old Yosys. Yosys 0.33, which is what Debian
packaged for a long time, **cannot parse this design**: it does not support
file-scope `import`, so it dies on the first module. If `yosys -V` reports
anything below 0.44:

```bash
pip install --break-system-packages yowasp-yosys
yowasp-yosys -V
# then substitute yowasp-yosys wherever this file says yosys
```

This is not a quirk of this project. Yosys's native Verilog frontend passes
roughly half of a standard SystemVerilog construct suite. The RTL here was
deliberately written to stay inside what it accepts — no typedef'd enums or
packed structs on ports or in declarations — precisely so you are not forced
to depend on the `yosys-slang` plugin being present in someone else's
continuous integration. If you ever add a `typedef enum` port to this
design, it will simulate perfectly and then fail to harden.

---

## Step 1 — prove it still passes before you spend an hour on layout

```bash
cd test
make lint         # Verilator -Wall, must be clean
make sim          # 207 assertions across six testbenches
make synth        # Yosys elaboration, prints the real flip-flop count
cd ..
```

If any of those fail, stop. Hardening a broken design just gives you a
broken layout more slowly.

---

## Step 2 — install the hardening flow

Tiny Tapeout builds with LibreLane (the successor to OpenLane 2). Two ways
to get it; the container is less trouble on Windows Subsystem for Linux
(WSL2).

### Option A — Docker (recommended on WSL2)

Docker Desktop must be running on the Windows side with WSL2 integration
enabled for your distribution. Check from inside Ubuntu:

```bash
docker run --rm hello-world
```

Then:

```bash
pip install --break-system-packages librelane
```

LibreLane pulls its own container image on first run. The sky130 PDK is
fetched automatically into `~/.volare` the first time, which is a few
gigabytes and takes a while. Let it finish.

### Option B — Nix

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
# restart the shell, then
nix profile install github:efabless/librelane
```

Nix gives a reproducible toolchain and is what the LibreLane developers use.
It is also a larger initial download.

---

## Step 3 — harden the design

The Tiny Tapeout template supplies the configuration that pins your design
into a tile: the die area for the tile count, the pin placement the harness
expects, and the power straps. **Do not write your own floorplan.** Get the
template:

```bash
cd ~
git clone https://github.com/TinyTapeout/tt10-verilog-template.git tt-template
# use whichever shuttle template is current — check tinytapeout.com
```

Copy `src/`, `info.yaml`, `docs/` and `test/` from this repository over the
template's, keeping the template's `.github/`, `Makefile` and any
`*.json`/`*.tcl` configuration. Then:

```bash
cd ~/tt-template
make            # or follow the template's README; it wraps librelane
```

What actually runs, in order: Yosys synthesis, floorplanning, power
distribution network insertion, global and detailed placement, clock tree
synthesis, global and detailed routing, parasitic extraction, static timing
analysis, and finally GDSII streaming plus design-rule and
layout-versus-schematic checks.

Expect 10 to 40 minutes for a design this size.

### The easier route

Push to GitHub with Actions enabled and the Tiny Tapeout workflow does all
of this in continuous integration and publishes the GDSII, the reports and a
rendered datasheet page. Use that as the reference result and run locally
only when you need to iterate quickly or debug a failure.

---

## Step 4 — read the reports before you look at the picture

This is the step people skip. The layout renders beautifully whether or not
it meets timing.

```bash
cd runs/<latest>/
```

**Area and utilisation** — `reports/synthesis/*stat*.rpt` and the
floorplan log. What you want:

- The standard cell count and total cell area in µm².
- The core utilisation percentage. Above roughly 60–70% on a tile, detailed
  routing starts failing.

Compare the flip-flop count against the 1,373 this repository measured. It
should match closely; a large difference means a configuration difference.

**Timing** — `reports/signoff/*sta*.rpt` or the `openroad` STA logs. Look
for:

- **Worst negative slack (WNS)** on the setup path. Must be positive at your
  target clock period. Negative means the design does not run at that speed;
  either lower `clock_hz` in `info.yaml` or shorten the critical path.
- **Total negative slack (TNS)**. Should be zero.
- **Hold slack.** Must be positive. Hold violations are not fixable by
  slowing the clock and are the more dangerous kind.

The critical path should be the one this design was built around:
register file read → the 33-bit adder in `tp_alu` → writeback multiplexer
→ register file write. If static timing reports something else as critical —
the shifter, the branch comparator, the target adder — then an assumption in
the microarchitecture section of the README is wrong and worth investigating
rather than papering over.

**Design rule check (DRC) and layout versus schematic (LVS)** — must both be
clean. Zero violations, not "a few".

**Antenna violations** — the flow inserts diodes automatically. A handful of
reported-then-fixed ones are normal.

---

## Step 5 — open the layout in KLayout

```bash
sudo apt install klayout        # or download from klayout.de for a current build
klayout runs/<latest>/final/gds/tt_um_normansrule_tinypulse.gds
```

KLayout needs the sky130 layer properties file to colour the layers
meaningfully. It ships with the PDK:

```
~/.volare/sky130A/libs.tech/klayout/tech/sky130A.lyp
```

Load it with **File → Load Layer Properties**, or start KLayout with the
technology already selected:

```bash
klayout -e -nn ~/.volare/sky130A/libs.tech/klayout/tech/sky130A.lyt \
        runs/<latest>/final/gds/tt_um_normansrule_tinypulse.gds
```

### What to actually look at

Opening the GDS is satisfying and mostly not informative. Four things are
worth checking with your eyes:

1. **The outline.** Your design must sit inside the tile boundary with the
   power rails reaching the edges where the harness expects them. Anything
   poking outside means a floorplan configuration mismatch.
2. **Density.** Pan around at moderate zoom. You are looking for large empty
   regions next to congested ones, which means placement struggled. Even
   density is what you want.
3. **The register file.** It is 512 flip-flops, 37% of the design, and it
   will be visible as a large regular block. If it is smeared across the
   whole tile rather than clustered, routing is probably fighting it.
4. **Routing congestion on metal 1 and metal 2.** Turn off the upper metals
   and look for areas where the lower layers are completely full.

Useful KLayout operations:

- **Tools → DRC** runs a rule deck if you load one; the flow has already
  done this, so this is for spot checks.
- **Display → Layers** to isolate a single metal layer.
- The **hierarchy browser** (left panel) lets you jump to an instance by
  name, which is how you find `u_soc.g_cpu.u_core.u_rf`.
- **Edit → Layer → Flatten** only on a copy; never flatten the file you plan
  to submit.

### Measuring the area yourself

In KLayout, **Tools → Measure** gives you the bounding box. Compare against
the tile pitch: sky130 tiles are about 161 µm by 112 µm for 1x1, and a 2x2
is roughly 334 µm by 226 µm. If your design's bounding box is comfortably
inside, consider whether a smaller tile count would have fit — each step
down is real money.

---

## Step 6 — gate-level simulation

The flow writes a post-layout netlist. Simulating it catches things RTL
simulation cannot: an inverted reset, a synthesis mis-optimisation, a
timing-dependent bug.

```bash
# the netlist is usually at:
runs/<latest>/final/nl/tt_um_normansrule_tinypulse.nl.v
```

Run the existing testbenches against it instead of the RTL, with the sky130
cell models:

```bash
iverilog -g2012 -o gl.vvp -s tb_soc \
  -DFUNCTIONAL -DUSE_POWER_PINS \
  ~/.volare/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v \
  ~/.volare/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v \
  runs/<latest>/final/nl/tt_um_normansrule_tinypulse.nl.v \
  test/qspi_model.sv test/tb_soc.sv
vvp gl.vvp
```

The testbenches in this repository were written to drive the chip through
its pins, with only a few hierarchy probes, specifically so this works. The
probes that reach inside (`dut.u_soc.u_sync.now`, the core state) will not
exist in a gate-level netlist — comment those assertions out or use
`tb_isa.sv`, which checks results through the PSRAM model and touches no
internal signals.

**`tb_isa.sv` is the one to run at gate level.** 51 checks, all observed
through the pins, comparing against expectations computed independently in
Python.

---

## Step 7 — before you submit

- [ ] `make lint` clean
- [ ] `make sim` — 207 assertions passing
- [ ] `make synth` — flip-flop count as expected
- [ ] Hardening completes with no DRC and no LVS violations
- [ ] Setup worst negative slack positive at the clock in `info.yaml`
- [ ] Hold slack positive
- [ ] `tiles` in `info.yaml` matches what actually fit
- [ ] Gate-level `tb_isa.sv` passing
- [ ] `docs/info.md` describes what the chip really does
- [ ] Pinout in `info.yaml` matches `src/tt_um_normansrule_tinypulse.sv`

That last one is worth double-checking by hand. The pinout in `info.yaml` is
what gets printed on the datasheet other people read; nothing checks it
against the RTL.

---

## If it does not fit

The measured flip-flop budget, by module, from `syn/stat.txt`:

| Module | Flip-flops | Share |
|---|---:|---:|
| `tp_regfile` | 512 | 37% |
| `qspi_ctrl` | 165 | 12% |
| `sync_compare` (3 channels) | 163 | 12% |
| `tp_fetch` | 133 | 10% |
| `tp_core` | 115 | 8% |
| `sync_timebase` | 81 | 6% |
| `sync_event_fifo` | 70 | 5% |
| `sync_unit` | 60 | 4% |
| `tp_shifter` | 40 | 3% |
| `sync_capture` | 24 | 2% |
| `tp_soc`, `tp_bus` | 6 | – |
| **Total** | **1,369** | |

Knobs, cheapest first:

1. **`sync_compare` to 2 channels** (`NCMP=2`): about 54 flip-flops. You lose
   TRIG2 on `uio[6]`.
2. **`qspi_ctrl`'s `prefix_q`**: 32 flip-flops. It exists only to hold the
   command prefix across the deselect state and could be rebuilt
   combinationally from `cur_addr`, `cur_dev` and `cur_we`.
3. **`FRACW` from 24 to 16**: 8 flip-flops, and the rate trim resolution goes
   from 0.06 to 15 parts per million. Only worth it if you are not
   disciplining the clock.
4. **`next_seq_addr` narrower**: it is 24 bits to cover a 16 MB flash; 16
   bits covers 64 KB of streaming reach and saves 8.
5. **The register file.** 512 flip-flops is 37% of the design and dropping to
   8 registers saves 256. It is also the one change that costs you the stock
   toolchain: `-march=rv32e` assumes 16 registers, so you would be
   hand-writing assembly or patching a compiler. Do this last.

Do not reach for the register file first just because it is the biggest
number. The first four are free in every sense.
