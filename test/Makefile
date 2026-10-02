# Makefile — test runner for TinyPulse-Skywater130.
#
#   make            cocotb + Icarus, the Tiny Tapeout standard flow
#   make sim        every pure-Verilog self-checking testbench
#                   (no cocotb needed; these are the ones to run first)
#   make lint       Verilator -Wall, must be clean
#   make synth      Yosys elaboration + real flip-flop count
#   make area LIB=<sky130 .lib>   REAL sky130 cell area vs every tile size
#   make unit       block-level checks: timing unit, register file, UART, GPIO
#   make soc        system test: boots a program, checks trigger timing
#   make isa        every RV32I instruction against Python-computed results
#   make stress     simultaneous capture, queue overflow, 2^32 rollover
#   make wrap       system-level rollover: TWAIT across the wrap
#   make xpulse     all eleven Xpulse instructions executed
#   make boot       UART bootloader: load a program over serial into RAM, run it
#   make wake       QSPI wake-up from cold, warm and pre-set memory states
#   make c          a Clang-compiled C program, from flash and over the UART bootloader
#                   (needs: pip install ziglang pyelftools)
#   make run PROG=../sw/examples/hello.c
#                   compile any C file and run it on the simulated chip, output live
#   make act        the official RISC-V architecture tests, all 37 RV32E (~10 min)
#   make printf     tp_printf against Python's % formatting
#   make spi        software SPI reads a simulated W25Q128's JEDEC ID
#   make bridge     the demo-board bridge (sw/demoboard/tpboot.py) against a simulated chip
#   make timing     critical-path estimate from real cell delays (needs native yosys, LIB=...)
#   make GATES=yes  the cocotb tests on the post-hardening netlist
#   make prog       regenerate the .hex programs

SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC = ../src

RTL  = $(SRC)/tp_pkg.sv
RTL += $(SRC)/core/tp_nregfile.sv
RTL += $(SRC)/core/tp_ncore.sv
RTL += $(SRC)/sync/sync_timebase.sv
RTL += $(SRC)/sync/sync_capture.sv
RTL += $(SRC)/sync/sync_event_fifo.sv
RTL += $(SRC)/sync/sync_compare.sv
RTL += $(SRC)/sync/sync_unit.sv
RTL += $(SRC)/periph/tp_uart.sv
RTL += $(SRC)/periph/tp_periph.sv
RTL += $(SRC)/boot/tp_bootrom.sv
RTL += $(SRC)/bus/tp_bus.sv
RTL += $(SRC)/bus/qspi_ctrl.sv
RTL += $(SRC)/tp_soc.sv
RTL += $(SRC)/tt_um_normansrule_tinypulse.sv

# cocotb: RTL by default; `make GATES=yes` runs the same tests on the
# gate-level netlist that Tiny Tapeout's CI copies in after hardening.
ifneq ($(GATES),yes)
SIM_BUILD        = sim_build/rtl
VERILOG_SOURCES  = $(RTL) qspi_model.sv tb.v
else
SIM_BUILD        = sim_build/gl
COMPILE_ARGS    += -DGL_TEST -DFUNCTIONAL -DUSE_POWER_PINS -DSIM -DUNIT_DELAY=\#1
VERILOG_SOURCES  = $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v qspi_model.sv tb.v
endif

COMPILE_ARGS += -g2012
TOPLEVEL = tb
COCOTB_TEST_MODULES = test

# --- pure Verilog, no cocotb ------------------------------------------
.PHONY: sim lint synth area unit soc isa stress wrap xpulse boot wake c bridge timing run act gl printf spi pytools prog clean-sim

sim: unit soc isa stress wrap xpulse boot wake c bridge printf spi
	@echo ""
	@echo "all testbenches finished — check for FAILED above"

lint:
	verilator --lint-only -Wall --timing $(RTL) --top-module tt_um_normansrule_tinypulse

area:
	cd .. && bash syn/area_sky130.sh $(LIB)

prog:
	python3 ../sw/mkprog.py prog.hex
	python3 ../sw/mkhello.py hello.hex >/dev/null
	python3 ../sw/mkisa.py  isa.hex
	python3 ../sw/mkwrap.py wrap.hex
	python3 ../sw/mkxpulse.py xpulse.hex

unit:
	@sh iv.sh -g2012 -o tb_unit.vvp -s tb_unit $(RTL) tb_unit.sv
	vvp tb_unit.vvp

soc: prog
	@sh iv.sh -g2012 -o tb_soc.vvp -s tb_soc $(RTL) qspi_model.sv tb_soc.sv
	vvp tb_soc.vvp

isa: prog
	@sh iv.sh -g2012 -o tb_isa.vvp -s tb_isa $(RTL) qspi_model.sv tb_isa.sv
	vvp tb_isa.vvp

stress:
	@sh iv.sh -g2012 -o tb_stress.vvp -s tb_stress $(RTL) tb_stress.sv
	vvp tb_stress.vvp

wrap: prog
	@sh iv.sh -g2012 -o tb_wrap.vvp -s tb_wrap $(RTL) qspi_model.sv tb_wrap.sv
	vvp tb_wrap.vvp

xpulse: prog
	@sh iv.sh -g2012 -o tb_xpulse.vvp -s tb_xpulse $(RTL) qspi_model.sv tb_xpulse.sv
	vvp tb_xpulse.vvp

clean-sim:
	rm -f *.vvp *.vcd

# Only pull in the cocotb flow if cocotb is actually installed, so that
# `make sim` works on a machine that only has Icarus.
COCOTB_MAKEFILES := $(shell cocotb-config --makefiles 2>/dev/null)
ifneq ($(COCOTB_MAKEFILES),)
include $(COCOTB_MAKEFILES)/Makefile.sim
endif

boot: prog
	@sh iv.sh -g2012 -o tb_boot.vvp -s tb_boot $(RTL) qspi_model.sv tb_boot.sv
	vvp tb_boot.vvp

wake: prog
	@sh iv.sh -g2012 -o tb_wake.vvp -s tb_wake $(RTL) qspi_model.sv tb_wake.sv
	vvp tb_wake.vvp

# ---- C programs, compiled with the Clang inside `pip install ziglang` ----
# Checked before any C build: which python3 is running, and whether it has the
# two packages. With more than one environment active (a venv on top of conda,
# say), python3 may not be the one you installed them into.
pytools:
	@python3 -c "import ziglang, elftools" 2>/dev/null || { \
	  echo "*** $$(command -v python3) cannot import ziglang and pyelftools."; \
	  echo "*** Install them into that Python:  python3 -m pip install ziglang pyelftools"; \
	  echo "*** or deactivate the extra environment, so python3 is the one that has them."; exit 1; }

# Test builds always compile from scratch, in a private cache that is wiped
# first. Zig's cache decides whether a header changed partly from its
# timestamp, and two edits inside the same second can be missed — which once
# made a restored source reuse a deliberately broken build. A test result has
# to come from the code on disk, so the tests never trust a cache.
ZIG_CACHE = $(CURDIR)/.zig-cache-test
ZCC  = rm -rf $(ZIG_CACHE) && ZIG_GLOBAL_CACHE_DIR=$(ZIG_CACHE) ZIG_LOCAL_CACHE_DIR=$(ZIG_CACHE) python3 -m ziglang cc -target riscv32-freestanding-none -mcpu=generic_rv32+e-i -mabi=ilp32e
ZOBJ = python3 -m ziglang objcopy
CFLAGS_C = -Os -g -fno-unwind-tables -fno-asynchronous-unwind-tables -ffreestanding -nostdlib -fno-builtin -ffunction-sections -fdata-sections \
           -Wall -Wextra -DBAUD_DIV=8
C_SRCS = ../sw/crt0.S ../sw/lib/rt.c ../sw/examples/c_selftest.c

c_flash.elf: pytools $(C_SRCS) ../sw/link.ld ../sw/tinypulse.h ../sw/tp_io.h
	$(ZCC) $(CFLAGS_C) -T ../sw/link.ld -Wl,--gc-sections -o $@ $(C_SRCS)
c_ram.elf: pytools $(C_SRCS) ../sw/link_ram.ld ../sw/tinypulse.h ../sw/tp_io.h
	$(ZCC) $(CFLAGS_C) -T ../sw/link_ram.ld -Wl,--gc-sections -o $@ $(C_SRCS)
%.hex: %.elf
	python3 ../sw/rv32e_check.py $<
	$(ZOBJ) -O binary $< $*.bin
	python3 -c "import sys;d=open('$*.bin','rb').read();d+=b'\0'*((-len(d))%4);print('\n'.join('%08x'%int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)))" > $@

c: c_flash.hex c_ram.hex
	@sh iv.sh -g2012 -o tb_c.vvp -s tb_c $(RTL) qspi_model.sv tb_c.sv
	vvp tb_c.vvp

bridge:
	python3 ../sw/demoboard/test_tpboot.py

# Critical path from the real cell library, with buffering and sizing as a stand-in
# for the real flow's resizer. No wire delay: the routed report in CI is final.
LIB ?= $(HOME)/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
timing:
	cd .. && { grep '^read_verilog' syn/synth_check.ys; \
	  echo 'hierarchy -check -top tt_um_normansrule_tinypulse'; \
	  echo 'synth -top tt_um_normansrule_tinypulse -flatten'; \
	  echo 'dfflibmap -liberty $(LIB)'; \
	  echo 'abc -D 20000 -liberty $(LIB) -script +strash;dch;map,-D,20000;topo;buffer,-p;upsize,-D,20000;dnsize,-D,20000;stime,-p'; \
	} > /tmp/tp_timing.ys && yosys -q -l /tmp/tp_timing.log -s /tmp/tp_timing.ys >/dev/null && \
	  grep -E 'Delay =' /tmp/tp_timing.log | sed -E 's/.*Delay = *([0-9.]+) ps.*/worst register-to-register path: \1 ps (budget 20000 ps at 50 MHz, before wire delay)/' && \
	  grep -E 'Start-point' /tmp/tp_timing.log | sed 's/^ABC: /  /'

# Run any C program on the simulated chip: make run PROG=path/to/file.c
PROG ?= ../sw/examples/hello.c
run: pytools $(PROG)
	$(ZCC) $(CFLAGS_C) -T ../sw/link.ld -Wl,--gc-sections -o run.elf ../sw/crt0.S ../sw/lib/rt.c ../sw/lib/tp_printf.c $(PROG)
	python3 ../sw/rv32e_check.py run.elf
	$(ZOBJ) -O binary run.elf run.bin
	python3 -c "d=open('run.bin','rb').read();d+=b'\0'*((-len(d))%4);print('\n'.join('%08x'%int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)))" > run.hex
	@iverilog -g2012 -o tb_run.vvp -s tb_run $(RTL) qspi_model.sv tb_run.sv > tb_run_build.log 2>&1 || \
	  { echo '--- iverilog failed to build the run bench:'; grep -v 'sorry' tb_run_build.log; exit 1; }
	@vvp -n tb_run.vvp $(RUNARGS) | grep -v '^VCD\|readmemh'

# The official RISC-V architecture tests (riscv-arch-test, RV32E): 37 tests,
# signatures compared with the golden model's references. About 10 minutes.
act:
	test -d act/riscv-arch-test || sh act/fetch.sh
	python3 act/run_act.py

# Gate-level, locally: synthesize to real sky130 cells with your Yosys and PDK,
# then run the cocotb tests on the netlist (what Tiny Tapeout's gl_test job does
# with the post-layout netlist).
PDK_ROOT ?= $(HOME)/pdk
GL_LIB = $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
gl:
	cd .. && { grep '^read_verilog' syn/synth_check.ys; \
	  echo 'hierarchy -check -top tt_um_normansrule_tinypulse'; \
	  echo 'synth -top tt_um_normansrule_tinypulse -flatten'; \
	  echo 'dfflibmap -liberty $(GL_LIB)'; echo 'abc -liberty $(GL_LIB)'; echo 'opt_clean'; \
	  echo 'hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO'; \
	  echo 'opt_clean'; echo 'write_verilog -noattr /tmp/tp_gl.v'; } > /tmp/tp_gl.ys && yosys -q -s /tmp/tp_gl.ys
	python3 -c "s=open('/tmp/tp_gl.v').read();m='module tt_um_normansrule_tinypulse(';s=s.replace(m,m+'VPWR, VGND, ',1);i=s.index(');',s.index(m));open('gate_level_netlist.v','w').write(s[:i+2]+'\n  input VPWR;\n  input VGND;'+s[i+2:])"
	rm -rf sim_build/gl results.xml
	$(MAKE) GATES=yes PDK_ROOT=$(PDK_ROOT) COMPILE_ARGS="-g2012 -DGL_TEST -DFUNCTIONAL -DSIM -DUNIT_DELAY=#1" results.xml

# tp_printf, checked character for character against Python's % operator
printf:
	python3 printf_check.py
	@$(MAKE) -s run PROG=printf_cases.c > printf_out.txt 2>&1 || \
	  { echo '--- building or running the printf test failed; its output:'; grep -v 'sorry' printf_out.txt; exit 1; }
	@python3 -c "import sys; g=[l for l in open('printf_out.txt') if l.startswith('[')]; w=open('printf_expect.txt').readlines(); bad=[(a,b) for a,b in zip(g,w) if a!=b]; [print('  FAIL  got %r want %r' % (a.rstrip(), b.rstrip())) for a,b in bad]; ok=len(g)==len(w) and not bad; print('%d checks, %d failures' % (len(w), len(bad) + (len(g)!=len(w)))); sys.exit(0 if ok else 1)"

# the software SPI (sw/tp_spi.h) against a simulated W25Q128 flash
spi:
	@$(MAKE) -s run PROG=../sw/examples/spi_flash_id.c RUNARGS=+spi_flash > spi_out.txt 2>&1 || \
	  { echo '--- building or running the SPI test failed; its output:'; grep -v 'sorry' spi_out.txt; exit 1; }
	@grep -q "JEDEC ID: EF 40 18" spi_out.txt && grep -q "Winbond W25Q128 found" spi_out.txt && \
	  grep "JEDEC" spi_out.txt && echo "2 checks, 0 failures" || { cat spi_out.txt; echo "SPI TEST FAILED"; exit 1; }
