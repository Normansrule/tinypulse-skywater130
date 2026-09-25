# Makefile — test runner for TinyPulse-Skywater130.
#
#   make            cocotb + Icarus, the Tiny Tapeout standard flow
#   make sim        every pure-Verilog self-checking testbench
#                   (no cocotb needed; these are the ones to run first)
#   make lint       Verilator -Wall, must be clean
#   make synth      Yosys elaboration + real flip-flop count
#   make area LIB=<sky130 .lib>   REAL sky130 cell area vs every tile size
#   make unit       block-level checks
#   make soc        system test: boots a program, checks trigger timing
#   make isa        all 40 RV32I instructions against expected results
#   make stress     simultaneous capture, queue overflow, 2^32 rollover
#   make wrap       system-level rollover: TWAIT across the wrap
#   make xpulse     all eleven Xpulse instructions executed
#   make profile    the same ISA test against the 2x2 build profile
#   make prog       regenerate the .hex programs

SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC = ../src

RTL  = $(SRC)/tp_pkg.sv
RTL += $(SRC)/core/tp_alu.sv
RTL += $(SRC)/core/tp_shifter.sv
RTL += $(SRC)/core/tp_branch_comp.sv
RTL += $(SRC)/core/tp_branch_unit.sv
RTL += $(SRC)/core/tp_regfile.sv
RTL += $(SRC)/core/tp_imm_gen.sv
RTL += $(SRC)/core/tp_decode.sv
RTL += $(SRC)/core/tp_bpred.sv
RTL += $(SRC)/core/tp_hazard.sv
RTL += $(SRC)/core/tp_lsu.sv
RTL += $(SRC)/core/tp_fetch.sv
RTL += $(SRC)/core/tp_core.sv
RTL += $(SRC)/sync/sync_timebase.sv
RTL += $(SRC)/sync/sync_capture.sv
RTL += $(SRC)/sync/sync_event_fifo.sv
RTL += $(SRC)/sync/sync_compare.sv
RTL += $(SRC)/sync/sync_unit.sv
RTL += $(SRC)/bus/tp_bus.sv
RTL += $(SRC)/bus/qspi_ctrl.sv
RTL += $(SRC)/tp_soc.sv
RTL += $(SRC)/tt_um_normansrule_tinypulse.sv

VERILOG_SOURCES = $(RTL) qspi_model.sv tb.v

COMPILE_ARGS += -g2012
TOPLEVEL = tb
MODULE   = test

# --- pure Verilog, no cocotb ------------------------------------------
.PHONY: sim lint synth area unit soc isa stress wrap xpulse profile prog clean-sim

sim: unit soc isa stress wrap xpulse profile
	@echo ""
	@echo "all testbenches finished — check for FAILED above"

# IMPORTSTAR is waived deliberately and it is the only waiver in this
# project. Verilator is right that `import tp_pkg::*;` at compilation
# unit scope pollutes the global namespace. The alternative, putting the
# import in the module header, is not parseable by Yosys's native
# frontend -- and that frontend is what hardens the chip. Namespace
# tidiness loses to being able to synthesize.
lint:
	verilator --lint-only -Wall --timing $(RTL) --top-module tt_um_normansrule_tinypulse

area:
	cd .. && bash syn/area_sky130.sh $(LIB)

prog:
	python3 ../sw/mkprog.py prog.hex
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

profile: prog
	iverilog -g2012 -o tb_profile.vvp -s tb_profile $(RTL) qspi_model.sv tb_profile.sv
	vvp tb_profile.vvp

clean-sim:
	rm -f *.vvp *.vcd

# Only pull in the cocotb flow if cocotb is actually installed, so that
# `make sim` works on a machine that only has Icarus.
COCOTB_MAKEFILES := $(shell cocotb-config --makefiles 2>/dev/null)
ifneq ($(COCOTB_MAKEFILES),)
include $(COCOTB_MAKEFILES)/Makefile.sim
endif
