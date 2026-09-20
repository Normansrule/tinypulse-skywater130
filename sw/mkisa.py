#!/usr/bin/env python3
"""mkisa.py — build test/isa.hex, a program that exercises every RV32I
instruction TinyPulse implements and stores each result to PSRAM for checking.

The testbench (test/tb_isa.sv) knows the expected value of every slot, so a
wrong answer names the instruction that produced it rather than just failing.

Slot N lives at PSRAM word N (0x10000000 + 4*N).
"""

from mkprog import (R, I, S, B, U, J, OPC_OPIMM, OPC_OP, OPC_LOAD, OPC_STORE,
                    OPC_BRANCH, OPC_LUI, OPC_AUIPC, OPC_JAL, OPC_JALR,
                    OPC_SYSTEM, addi, add, lui, sw, lw, ecall)

# RV32E: x0..x15. Reserve x15 as the PSRAM base pointer.
BASE = 15

def auipc(rd, imm20):   return U(OPC_AUIPC, rd, imm20)
def jalr(rd, rs1, imm): return I(OPC_JALR, 0, rd, rs1, imm)
def jal(rd, imm):       return J(OPC_JAL, rd, imm)
def sub(rd, a, b):      return R(OPC_OP, 0, 0x20, rd, a, b)
def sll(rd, a, b):      return R(OPC_OP, 1, 0, rd, a, b)
def slt(rd, a, b):      return R(OPC_OP, 2, 0, rd, a, b)
def sltu(rd, a, b):     return R(OPC_OP, 3, 0, rd, a, b)
def xor_(rd, a, b):     return R(OPC_OP, 4, 0, rd, a, b)
def srl(rd, a, b):      return R(OPC_OP, 5, 0, rd, a, b)
def sra(rd, a, b):      return R(OPC_OP, 5, 0x20, rd, a, b)
def or_(rd, a, b):      return R(OPC_OP, 6, 0, rd, a, b)
def and_(rd, a, b):     return R(OPC_OP, 7, 0, rd, a, b)
def slti(rd, a, i):     return I(OPC_OPIMM, 2, rd, a, i)
def sltiu(rd, a, i):    return I(OPC_OPIMM, 3, rd, a, i)
def xori(rd, a, i):     return I(OPC_OPIMM, 4, rd, a, i)
def ori(rd, a, i):      return I(OPC_OPIMM, 6, rd, a, i)
def andi(rd, a, i):     return I(OPC_OPIMM, 7, rd, a, i)
def slli(rd, a, sh):    return I(OPC_OPIMM, 1, rd, a, sh)
def srli(rd, a, sh):    return I(OPC_OPIMM, 5, rd, a, sh)
def srai(rd, a, sh):    return I(OPC_OPIMM, 5, rd, a, 0x400 | sh)
def lb(rd, rs1, o):     return I(OPC_LOAD, 0, rd, rs1, o)
def lh(rd, rs1, o):     return I(OPC_LOAD, 1, rd, rs1, o)
def lbu(rd, rs1, o):    return I(OPC_LOAD, 4, rd, rs1, o)
def lhu(rd, rs1, o):    return I(OPC_LOAD, 5, rd, rs1, o)
def sb(rs2, rs1, o):    return S(OPC_STORE, 0, rs1, rs2, o)
def sh(rs2, rs1, o):    return S(OPC_STORE, 1, rs1, rs2, o)
def beq(a, b, o):       return B(OPC_BRANCH, 0, a, b, o)
def bne(a, b, o):       return B(OPC_BRANCH, 1, a, b, o)
def blt(a, b, o):       return B(OPC_BRANCH, 4, a, b, o)
def bge(a, b, o):       return B(OPC_BRANCH, 5, a, b, o)
def bltu(a, b, o):      return B(OPC_BRANCH, 6, a, b, o)
def bgeu(a, b, o):      return B(OPC_BRANCH, 7, a, b, o)
def fence():            return I(0x0F, 0, 0, 0, 0)

prog = []          # list of (word, comment)
expect = []        # list of (slot, value, label)
_slot = [0]


def emit(w, c=""):
    prog.append((w, c))


def store(reg, value, label):
    """Store `reg` into the next PSRAM slot and record what it should be."""
    n = _slot[0]
    emit(sw(reg, BASE, 4 * n), f"slot {n}: {label}")
    expect.append((n, value & 0xFFFFFFFF, label))
    _slot[0] = n + 1


# ---------------------------------------------------------------------
# setup: x15 = PSRAM base
# ---------------------------------------------------------------------
emit(lui(BASE, 0x10000), "x15 = PSRAM base")

# ---- LUI / AUIPC ----------------------------------------------------
emit(lui(1, 0xABCDE), "lui x1, 0xABCDE")
store(1, 0xABCDE000, "LUI")

# AUIPC at a known PC. Its slot value is patched below once the address
# of the instruction is known.
auipc_idx = len(prog)
emit(auipc(2, 0x00001), "auipc x2, 1")
auipc_slot = _slot[0]
store(2, 0, "AUIPC")            # placeholder, patched after assembly

# ---- register-immediate --------------------------------------------
emit(addi(1, 0, 100), "addi x1, x0, 100")
store(1, 100, "ADDI positive")

emit(addi(1, 0, -100), "addi x1, x0, -100")
store(1, -100, "ADDI negative (sign extension)")

# the regression that the register-file bypass bug would have broken:
# destination and source are the same register
emit(addi(1, 0, 5), "addi x1, x0, 5")
emit(addi(1, 1, 7), "addi x1, x1, 7   <-- rd == rs1")
store(1, 12, "ADDI with rd == rs1")

emit(addi(3, 0, -1), "x3 = -1")
emit(addi(4, 0, 1), "x4 = 1")
emit(slti(5, 3, 0), "slti x5, x3, 0")
store(5, 1, "SLTI -1 < 0 signed")
emit(sltiu(5, 3, 1), "sltiu x5, x3, 1")
store(5, 0, "SLTIU 0xFFFFFFFF < 1 unsigned is false")

emit(lui(6, 0x0F0F0), "x6 = 0x0F0F0000")
emit(xori(5, 6, -1), "xori x5, x6, -1")
store(5, ~0x0F0F0000, "XORI with -1 inverts")
emit(ori(5, 6, 0x0FF), "ori x5, x6, 0xFF")
store(5, 0x0F0F00FF, "ORI")
emit(andi(5, 6, 0x0FF), "andi x5, x6, 0xFF")
store(5, 0x00000000, "ANDI")

emit(addi(7, 0, 1), "x7 = 1")
emit(slli(5, 7, 31), "slli x5, x7, 31")
store(5, 0x80000000, "SLLI by 31")
emit(srli(5, 5, 31), "srli x5, x5, 31")
store(5, 1, "SRLI by 31")
emit(lui(8, 0x80000), "x8 = 0x80000000")
emit(srai(5, 8, 4), "srai x5, x8, 4")
store(5, 0xF8000000, "SRAI keeps the sign")
emit(srli(5, 8, 4), "srli x5, x8, 4")
store(5, 0x08000000, "SRLI does not")
emit(slli(5, 7, 0), "slli x5, x7, 0")
store(5, 1, "SLLI by zero")

# ---- register-register ----------------------------------------------
emit(addi(1, 0, 20), "x1 = 20")
emit(addi(2, 0, 7), "x2 = 7")
emit(add(5, 1, 2), "add")
store(5, 27, "ADD")
emit(sub(5, 1, 2), "sub")
store(5, 13, "SUB")
emit(sub(5, 2, 1), "sub, borrowing")
store(5, -13, "SUB going negative")
emit(and_(5, 1, 2), "and")
store(5, 20 & 7, "AND")
emit(or_(5, 1, 2), "or")
store(5, 20 | 7, "OR")
emit(xor_(5, 1, 2), "xor")
store(5, 20 ^ 7, "XOR")
emit(slt(5, 3, 4), "slt x5, -1, 1")
store(5, 1, "SLT signed")
emit(sltu(5, 3, 4), "sltu x5, 0xFFFFFFFF, 1")
store(5, 0, "SLTU unsigned")
emit(addi(9, 0, 4), "x9 = 4")
emit(sll(5, 1, 9), "sll x5, 20, 4")
store(5, 20 << 4, "SLL by a register")
emit(srl(5, 8, 9), "srl x5, 0x80000000, 4")
store(5, 0x08000000, "SRL by a register")
emit(sra(5, 8, 9), "sra x5, 0x80000000, 4")
store(5, 0xF8000000, "SRA by a register")

# ---- loads and stores ------------------------------------------------
emit(lui(5, 0x89ABC), "x5 = 0x89ABC000")
emit(ori(5, 5, 0x0DE), "x5 = 0x89ABC0DE")
store(5, 0x89ABC0DE, "SW then LW round trip (write)")
lw_src = _slot[0] - 1
emit(lw(6, BASE, 4 * lw_src), "lw it back")
store(6, 0x89ABC0DE, "LW")

emit(lb(6, BASE, 4 * lw_src + 0), "lb byte 0 = 0xDE")
store(6, 0xFFFFFFDE, "LB sign extends")
emit(lbu(6, BASE, 4 * lw_src + 0), "lbu byte 0")
store(6, 0x000000DE, "LBU zero extends")
emit(lb(6, BASE, 4 * lw_src + 3), "lb byte 3 = 0x89")
store(6, 0xFFFFFF89, "LB on the top byte")
emit(lh(6, BASE, 4 * lw_src + 2), "lh half 1 = 0x89AB")
store(6, 0xFFFF89AB, "LH sign extends")
emit(lhu(6, BASE, 4 * lw_src + 2), "lhu half 1")
store(6, 0x000089AB, "LHU zero extends")
emit(lhu(6, BASE, 4 * lw_src + 0), "lhu half 0")
store(6, 0x0000C0DE, "LHU low half")

# SB and SH into a fresh slot
sbsh = _slot[0]
emit(addi(6, 0, 0), "x6 = 0")
emit(sw(6, BASE, 4 * sbsh), "clear the slot")
emit(addi(6, 0, 0x55), "x6 = 0x55")
emit(sb(6, BASE, 4 * sbsh + 1), "sb into byte 1")
emit(lui(7, 0x0000A), "x7 = 0xA000")
emit(ori(7, 7, 0x7BC), "x7 = 0xA7BC")
emit(sh(7, BASE, 4 * sbsh + 2), "sh into the high half")
emit(lw(6, BASE, 4 * sbsh), "read the slot back")
_slot[0] += 1                      # the slot was written by SB/SH directly
expect.append((sbsh, 0xA7BC5500, "SB and SH place bytes correctly"))
store(6, 0xA7BC5500, "LW sees the SB/SH result")

# ---- branches --------------------------------------------------------
# each branch skips one instruction when taken; the slot records which path
def branch_case(mk, a_val, b_val, taken, label):
    emit(addi(1, 0, a_val), f"x1 = {a_val}")
    emit(addi(2, 0, b_val), f"x2 = {b_val}")
    emit(addi(5, 0, 0), "x5 = 0 (not taken marker)")
    emit(mk(1, 2, 8), f"branch: {label}")
    emit(addi(5, 0, 0xAA), "not taken path")
    emit(addi(6, 0, 0), "landing pad")
    store(5, 0 if taken else 0xAA, label)

branch_case(beq, 5, 5, True,  "BEQ taken")
branch_case(beq, 5, 6, False, "BEQ not taken")
branch_case(bne, 5, 6, True,  "BNE taken")
branch_case(blt, -3, 2, True, "BLT signed taken")
branch_case(bltu, -3, 2, False, "BLTU unsigned not taken")
branch_case(bge, 2, -3, True, "BGE signed taken")
branch_case(bgeu, 2, -3, False, "BGEU unsigned not taken")
branch_case(bge, 4, 4, True,  "BGE on equal is taken")

# a backward branch, so the predictor's taken path is exercised
emit(addi(1, 0, 3), "x1 = 3 loop counter")
emit(addi(5, 0, 0), "x5 = 0 accumulator")
loop = len(prog)
emit(addi(5, 5, 10), "x5 += 10")
emit(addi(1, 1, -1), "x1 -= 1")
emit(bne(1, 0, -8), "backward branch while x1 != 0")
store(5, 30, "backward branch loop ran 3 times")

# ---- jumps -----------------------------------------------------------
emit(addi(5, 0, 0), "x5 = 0")
emit(jal(1, 12), "jal x1, +12 (skips two)")
emit(addi(5, 0, 0xBB), "skipped")
emit(addi(5, 0, 0xCC), "skipped")
emit(addi(6, 0, 0), "landing pad")
store(5, 0, "JAL skipped the instructions in between")

# x1 holds the return address: pc_of_jal + 4
jal_ra_idx = len(prog)              # patched below
emit(addi(6, 0, 0), "placeholder for the JAL link check")
jal_slot = _slot[0]
store(1, 0, "JAL link register")    # patched

# JALR: jump to a computed address
emit(auipc(2, 0), "x2 = pc of this auipc")
emit(addi(5, 0, 0), "x5 = 0")
emit(jalr(3, 2, 16), "jalr to auipc_pc + 16")
emit(addi(5, 0, 0xDD), "skipped")
emit(addi(6, 0, 0), "landing pad (auipc_pc + 16)")
store(5, 0, "JALR jumped to the computed target")

# ---- FENCE retires as a no-op ---------------------------------------
emit(addi(5, 0, 0x77), "x5 = 0x77")
emit(fence(), "fence")
store(5, 0x77, "FENCE retires without disturbing state")

# ---- done ------------------------------------------------------------
emit(ecall(), "ecall: halt")

# ---------------------------------------------------------------------
# patch the two PC-relative expectations now that addresses are known
# ---------------------------------------------------------------------
auipc_pc = auipc_idx * 4
expect[[i for i, (n, _, _) in enumerate(expect) if n == auipc_slot][0]] = \
    (auipc_slot, (auipc_pc + 0x1000) & 0xFFFFFFFF, "AUIPC")

jal_pc = None
for i, (w, c) in enumerate(prog):
    if c.startswith("jal x1"):
        jal_pc = i * 4
expect[[i for i, (n, _, _) in enumerate(expect) if n == jal_slot][0]] = \
    (jal_slot, jal_pc + 4, "JAL link register")

if __name__ == "__main__":
    import os, sys
    here = os.path.dirname(os.path.abspath(__file__))
    hexf = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(here, "..", "test", "isa.hex")
    expf = os.path.join(os.path.dirname(os.path.abspath(hexf)), "isa_expect.txt")

    with open(hexf, "w") as f:
        for w, _ in prog:
            f.write("%08x\n" % (w & 0xFFFFFFFF))

    with open(expf, "w") as f:
        for n, v, label in expect:
            # Icarus $fscanf has no %[^\n], so the label is one token
            f.write("%d %08x %s\n" % (n, v, label.replace(" ", "_")))

    print("%d instructions, %d checked results" % (len(prog), len(expect)))
    print("wrote %s and %s" % (hexf, expf))
