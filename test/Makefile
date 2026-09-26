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
.PHONY: sim lint synth area unit soc isa stress wrap xpulse boot wake prog clean-sim

sim: unit soc isa stress wrap xpulse boot wake
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
	iverilog -g2012 -o tb_unit.vvp -s tb_unit $(RTL) tb_unit.sv
	vvp tb_unit.vvp

soc: prog
	iverilog -g2012 -o tb_soc.vvp -s tb_soc $(RTL) qspi_model.sv tb_soc.sv
	vvp tb_soc.vvp

isa: prog
	iverilog -g2012 -o tb_isa.vvp -s tb_isa $(RTL) qspi_model.sv tb_isa.sv
	vvp tb_isa.vvp

stress:
	iverilog -g2012 -o tb_stress.vvp -s tb_stress $(RTL) tb_stress.sv
	vvp tb_stress.vvp

wrap: prog
	iverilog -g2012 -o tb_wrap.vvp -s tb_wrap $(RTL) qspi_model.sv tb_wrap.sv
	vvp tb_wrap.vvp

xpulse: prog
	iverilog -g2012 -o tb_xpulse.vvp -s tb_xpulse $(RTL) qspi_model.sv tb_xpulse.sv
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
	iverilog -g2012 -o tb_boot.vvp -s tb_boot $(RTL) qspi_model.sv tb_boot.sv
	vvp tb_boot.vvp

wake: prog
	iverilog -g2012 -o tb_wake.vvp -s tb_wake $(RTL) qspi_model.sv tb_wake.sv
	vvp tb_wake.vvp
