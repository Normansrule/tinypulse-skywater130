# Verification and validation — TinyPulse-Skywater130

What has been proven, how, and what has not. The last section is the
important one.

Reproduce everything here with:

```bash
cd test
make lint      # Verilator -Wall, must be clean
make sim       # 246 assertions across seven testbenches
make synth     # Yosys elaboration and the real flip-flop count
make           # the cocotb suite, 4 tests
```

---

## 1. Summary

| Check | Result |
|---|---|
| Self-checking simulation assertions | **246 / 246 passing** |
| cocotb tests | **4 / 4 passing** |
| Verilator `--lint-only -Wall` | **clean**, one documented waiver |
| Yosys elaboration | **passes**, 1,373 flip-flops, **0 latches** |
| RV32I instructions executed and result-checked | **40 / 40** |
| Xpulse instructions executed and result-checked | **11 / 11** |
| Build profiles simulated | **2 of 3** (1x2 and 2x2; the 1x1 profile is empty) |

The single lint waiver is `IMPORTSTAR`, and it is deliberate: file-scope
`import tp_pkg::*;` is the only import form Yosys's native frontend parses,
and that frontend is what hardens the chip.

---

## 2. Testbenches

| Testbench | Assertions | Level | What it proves |
|---|---:|---|---|
| `tb_unit.sv` | 88 | block | Each datapath and sync block standalone |
| `tb_soc.sv` | 12 | system | Boots a program; the trigger edge lands on the exact programmed tick |
| `tb_isa.sv` | 51 | system | All 40 RV32I instructions against independently computed results |
| `tb_stress.sv` | 18 | block | Eight simultaneous captures, queue overflow, 2³² rollover |
| `tb_wrap.sv` | 10 | system | `TWAIT` and the comparator across the rollover, in a real program |
| `tb_xpulse.sv` | 16 | system | All 11 Xpulse instructions executed |
| `tb_profile.sv` | 51 | system | The whole ISA test re-run on the 2x2 parameter set |
| `test.py` (cocotb) | 4 | system | Pin-level driving through the Tiny Tapeout interface |

### Why `tb_isa.sv` carries the most weight

`sw/mkisa.py` assembles a 168-instruction program exercising all 40 RV32I
instructions, stores 49 results into the PSRAM, and computes the expected
value of every one of them **in Python, from the specification, not from
the RTL**. The testbench compares the two. Two independent implementations
agreeing is worth far more than a testbench that checks the hardware
against itself.

`tb_profile.sv` runs that same program against `BARREL=1` and `BIMODAL=1`,
because a parameter you never simulate is a parameter that does not work.

---

## 3. Module coverage

"Direct" means a dedicated testbench instantiates the module on its own and
drives its ports. "System" means it is exercised only as part of the whole
chip.

| Module | Direct | System | Notes |
|---|:--:|:--:|---|
| `tp_alu` | yes | yes | 14 cases including signed/unsigned boundaries at `0x80000000` |
| `tp_shifter` | yes | yes | Iterative build; shift-by-zero and shift-by-31 |
| `tp_branch_comp` | yes | yes | Via the branch unit's 10 cases |
| `tp_branch_unit` | yes | yes | All 6 conditions plus the 2 reserved `funct3` values |
| `tp_regfile` | **yes** | yes | Includes the no-bypass regression (see below) |
| `tp_imm_gen` | yes | yes | All 5 immediate formats plus "no immediate" |
| `tp_decode` | no | yes | Covered by all 51 ISA results and the 11 Xpulse ones |
| `tp_bpred` | **yes** | yes | Bimodal counter saturation in both directions |
| `tp_hazard` | **yes** | yes | All 9 stall and flush conditions |
| `tp_lsu` | yes | yes | Every byte lane, both extensions, all three store widths |
| `tp_fetch` | no | yes | Every program is a fetch test; redirect covered by branches |
| `tp_core` | no | yes | Four testbenches drive it end to end |
| `tp_bus` | no | yes | Arbitration exercised by every load and store |
| `qspi_ctrl` | no | yes | Streaming, deselect, sub-word writes, both devices |
| `sync_timebase` | yes | yes | Free run, rate trim, signed step |
| `sync_capture` | yes | yes | Latency measured, not assumed |
| `sync_event_fifo` | yes | yes | Fill, drain, overflow, recovery |
| `sync_compare` | yes | yes | Including across the rollover |
| `sync_unit` | yes | yes | Both access paths, coincident-edge arbitration |
| `tp_soc` | yes | yes | Instantiated directly for the 2x2 profile |
| `tt_um_normansrule_tinypulse` | — | yes | The submission top, driven by four testbenches |

### The regression worth naming

`tb_unit.sv` asserts that a register file read in the same cycle as a write
to the same address returns the **old** value. That is not a style
preference. This pipeline reads and writes in one stage, so a write-through
bypass feeds an instruction its own result as its own operand: `addi x1, x1, 1`
becomes a combinational loop in silicon and an unstable one in simulation.
Verilator found it as `UNOPTFLAT` after it had passed 207 assertions,
because no test had yet used an instruction whose destination was also its
source. `tb_isa.sv` now covers `rd == rs1` explicitly and `tb_unit.sv`
guards the register file directly.

---

## 4. Instruction coverage

Every instruction below is **executed by a program and its result checked**,
not merely present in a decode table.

**RV32I, all 40:** `LUI` `AUIPC` `JAL` `JALR` `BEQ` `BNE` `BLT` `BGE` `BLTU`
`BGEU` `LB` `LH` `LW` `LBU` `LHU` `SB` `SH` `SW` `ADDI` `SLTI` `SLTIU`
`XORI` `ORI` `ANDI` `SLLI` `SRLI` `SRAI` `ADD` `SUB` `SLL` `SLT` `SLTU`
`XOR` `SRL` `SRA` `OR` `AND` `FENCE` `ECALL` `EBREAK`

**Xpulse, all 11:** `TIME` `TPOP` `TSTAT` `TWAIT` `TARM` `TPULSE` `TMARK`
`TADJ` `TRATE` `TCFG` `TPW`

`TSTAT`, `TPULSE` and `TRATE` were added to the suite only after a coverage
audit found that no program had ever executed them. They decoded correctly
and nothing had proven they did the right thing to the hardware. `TRATE` in
particular is now checked the only way it can be: the testbench counts
clocks independently and confirms the timebase ran ahead of them.

---

## 5. Claims, and the assertion that backs each one

| Datasheet claim | Proven by |
|---|---|
| Trigger edge lands on the exact programmed tick, zero jitter | `tb_soc.sv`: programmed 531, fired 531 |
| Capture latency is 2 clocks and constant | `tb_unit.sv` measures it rather than assuming |
| Timestamps survive the 2³² rollover | `tb_stress.sv` (block) and `tb_wrap.sv` (system, `TWAIT` held 1,395 clocks) |
| Coincident edges are all queued, in channel order, sharing one timestamp | `tb_stress.sv`, eight channels on one clock |
| A full queue reports overflow and keeps working | `tb_stress.sv` |
| The timebase can be slewed | `tb_unit.sv` (exact tick count) and `tb_xpulse.sv` (through the instruction) |
| Timebase advances exactly one tick per clock when untrimmed | `tb_unit.sv`, 100 clocks |
| 21 clocks per sequential instruction, 48 for a taken branch | Measured on a straight-line benchmark |

---

## 6. What has NOT been done

Stated plainly, because a verification document that only lists successes
is marketing.

- **No hardening run against the sky130 PDK.** Synthesis proves the RTL
  elaborates and fixes the flip-flop count at 1,373. Area, timing and
  routability all need the real flow. `tiles: "2x2"` is a
  synthesis-backed prediction, not a confirmed fit.
- **No static timing analysis.** The 50 MHz target is a target. The
  critical path is *believed* to be register file read → 33-bit adder →
  writeback multiplexer → register file write, by construction. Nothing has
  measured it.
- **No gate-level simulation.** `tb_isa.sv` is written to observe
  everything through the pins precisely so it can run on a post-layout
  netlist; that has not happened yet.
- **No formal verification.** "An armed compare fires exactly once" and "no
  event is dropped while the queue has room" are currently proven by
  directed simulation, which is weaker than a proof. Both are small safety
  properties over small state and suit formal well.
- **No power analysis.** The low-duty-cycle claim for `TWAIT` is
  architectural reasoning, not a measured number.
- **The QSPI models are mine.** `test/qspi_model.sv` implements the
  protocol `qspi_ctrl` expects, so the two agree by construction. That is
  enough to catch sequencing and byte-order bugs — it caught the
  chip-select bug — but it cannot catch a disagreement between my reading
  of a real flash datasheet and the real flash. Verify continuous-read mode
  entry and tSHSL against the part you actually solder down.
- **The 1x1 profile is empty.** `HAS_CPU=0` elaborates and lints but has no
  host interface, so nothing can reach the sync registers. See the build
  profiles section of the README.
- **No multi-corner analysis.** Everything assumes typical.

---

## 7. Bugs the suite has caught

Listed because they are the argument for running the tools rather than
reading the code. Numbers 5 and 6 would each have produced dead silicon.

1. The bus held its request high during the cycle the QSPI controller
   answered, so the controller started the same transaction twice.
2. The iterative shifter returned a stale accumulator on a zero shift.
3. Sub-word PSRAM writes dropped the byte offset, so `SB` wrote to the
   wrong address.
4. The trigger output was one tick late, which would have made the
   zero-jitter claim false by one tick.
5. **A combinational loop through the register file** — found by Verilator
   after 207 assertions had passed.
6. **Every taken branch fetched garbage** — the controller issued a new
   address while chip select was still low from the open continuous-read
   stream, so the instruction stream came back two bytes misaligned and
   stayed that way. Found by writing a program with branches in it.
7. **The design would not have synthesized at all** — typedef'd enums and
   packed structs on module ports are outside what Yosys's native frontend
   accepts. Found by running Yosys for the first time.
8. Three Xpulse instructions had never been executed. Found by auditing
   coverage rather than assuming it.
