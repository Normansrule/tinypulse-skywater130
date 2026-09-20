#!/usr/bin/env python3
"""mkprog.py — assemble the TinyPulse-Skywater130 self-test program into test/prog.hex.

A deliberately tiny assembler: explicit encoders for each RV32I format plus
the Xpulse custom-0 instructions, so the exact bit pattern of every word is
visible here rather than hidden behind a toolchain. Extend it, or drop it and
use riscv32-unknown-elf-gcc with the .insn macros in sw/tinypulse.h.
"""

OPC_LUI, OPC_AUIPC = 0x37, 0x17
OPC_JAL, OPC_JALR = 0x6F, 0x67
OPC_BRANCH, OPC_LOAD, OPC_STORE = 0x63, 0x03, 0x23
OPC_OPIMM, OPC_OP, OPC_SYSTEM = 0x13, 0x33, 0x73
OPC_CUSTOM0 = 0x0B


def R(op, f3, f7, rd, rs1, rs2):
    return ((f7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) \
         | ((f3 & 7) << 12) | ((rd & 0x1F) << 7) | op


def I(op, f3, rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 7) << 12) \
         | ((rd & 0x1F) << 7) | op


def S(op, f3, rs1, rs2, imm):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) \
         | ((f3 & 7) << 12) | ((imm & 0x1F) << 7) | op


def B(op, f3, rs1, rs2, imm):
    imm &= 0x1FFF
    b12, b11 = (imm >> 12) & 1, (imm >> 11) & 1
    return (b12 << 31) | (((imm >> 5) & 0x3F) << 25) | ((rs2 & 0x1F) << 20) \
         | ((rs1 & 0x1F) << 15) | ((f3 & 7) << 12) \
         | ((((imm >> 1) & 0xF) << 8) | (b11 << 7)) | op


def U(op, rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | op


def J(op, rd, imm):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) \
         | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) \
         | ((rd & 0x1F) << 7) | op


# --- RV32I helpers used below ---
def addi(rd, rs1, imm):  return I(OPC_OPIMM, 0, rd, rs1, imm)
def add(rd, rs1, rs2):   return R(OPC_OP, 0, 0, rd, rs1, rs2)
def lui(rd, imm20):      return U(OPC_LUI, rd, imm20)
def sw(rs2, rs1, imm):   return S(OPC_STORE, 2, rs1, rs2, imm)
def lw(rd, rs1, imm):    return I(OPC_LOAD, 2, rd, rs1, imm)
def bne(rs1, rs2, imm):  return B(OPC_BRANCH, 1, rs1, rs2, imm)
def jal(rd, imm):        return J(OPC_JAL, rd, imm)
def slli(rd, rs1, sh):   return I(OPC_OPIMM, 1, rd, rs1, sh)
def ecall():             return I(OPC_SYSTEM, 0, 0, 0, 0)

# --- Xpulse ---
def TIME(rd):            return R(OPC_CUSTOM0, 0, 0, rd, 0, 0)
def TPOP(rd):            return R(OPC_CUSTOM0, 1, 0, rd, 0, 0)
def TSTAT(rd):           return R(OPC_CUSTOM0, 2, 0, rd, 0, 0)
def TWAIT(rs1):          return R(OPC_CUSTOM0, 3, 0, 0, rs1, 0)
def TARM(rs1, rs2):      return R(OPC_CUSTOM0, 4, 0, 0, rs1, rs2)
def TPULSE(rs1):         return R(OPC_CUSTOM0, 5, 0, 0, rs1, 0)
def TMARK(rd, rs1):      return R(OPC_CUSTOM0, 6, 0, rd, rs1, 0)
def TADJ(rs1):           return R(OPC_CUSTOM0, 7, 0, 0, rs1, 0)
def TRATE(rs1):          return R(OPC_CUSTOM0, 7, 1, 0, rs1, 0)
def TCFG(rs1):           return R(OPC_CUSTOM0, 7, 2, 0, rs1, 0)
def TPW(rs1):            return R(OPC_CUSTOM0, 7, 3, 0, rs1, 0)


PROG = [
    (addi(8, 0, 255),    "addi x8, x0, 255     ; capture enable mask"),
    (TCFG(8),            "tcfg x8              ; all 8 channels, rising edge"),
    (addi(9, 0, 16),     "addi x9, x0, 16      ; trigger pulse width"),
    (TPW(9),             "tpw  x9"),
    (TIME(1),            "time x1              ; t0"),
    (addi(2, 0, 400),    "addi x2, x0, 400"),
    (add(3, 1, 2),       "add  x3, x1, x2      ; deadline = t0 + 400"),
    (addi(4, 0, 0),      "addi x4, x0, 0       ; compare channel 0"),
    (TARM(3, 4),         "tarm x3, x4          ; arm trigger 0 at the deadline"),
    (TWAIT(3),           "twait x3             ; park until the deadline"),
    (TPOP(6),            "tpop x6              ; oldest event"),
    (TMARK(5, 0),        "tmark x5, x0         ; software mark, tag 0"),
    (lui(7, 0x10000),    "lui  x7, 0x10000     ; PSRAM base"),
    (sw(1, 7, 0),        "sw   x1, 0(x7)"),
    (sw(6, 7, 4),        "sw   x6, 4(x7)"),
    (sw(5, 7, 8),        "sw   x5, 8(x7)"),
    (ecall(),            "ecall                ; halt"),
]

if __name__ == "__main__":
    import os, sys
    out = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(__file__), "..", "test", "prog.hex")
    with open(out, "w") as f:
        for i, (word, asm) in enumerate(PROG):
            f.write("%08x\n" % (word & 0xFFFFFFFF))
            print("%04x: %08x   %s" % (i * 4, word & 0xFFFFFFFF, asm))
    print("\nwrote %s (%d words)" % (out, len(PROG)))
