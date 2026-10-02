#!/usr/bin/env python3
"""rv32e_check.py — will this program run on TinyPulse?

Decodes every instruction in an ELF's code (from the start of .text to the
linker symbol _code_end) and rejects anything TinyPulse does not implement:

    compressed (16-bit) instructions      TinyPulse has no C extension
    multiply / divide                     no M extension: link sw/lib/rt.c
    CSR and other SYSTEM instructions     only ECALL and EBREAK exist
    registers x16..x31                    RV32E has x0..x15
    reserved funct3/funct7 combinations

    python3 sw/rv32e_check.py program.elf

A clean result prints a one-line summary and exits 0. Needs pyelftools.
"""
import sys
from elftools.elf.elffile import ELFFile

OPS = {0x37: "LUI", 0x17: "AUIPC", 0x6F: "JAL", 0x67: "JALR", 0x63: "BRANCH",
       0x03: "LOAD", 0x23: "STORE", 0x13: "OP-IMM", 0x33: "OP", 0x0F: "FENCE",
       0x73: "SYSTEM", 0x0B: "XPULSE"}

def problem(w):
    if w & 3 != 3:
        return "compressed (16-bit) instruction: build without the C extension"
    op = w & 0x7F; f3 = (w >> 12) & 7; f7 = w >> 25
    rd, rs1, rs2 = (w >> 7) & 31, (w >> 15) & 31, (w >> 20) & 31
    if op not in OPS:
        return f"opcode {op:#04x} is not implemented"
    uses = {"LUI": "d", "AUIPC": "d", "JAL": "d", "JALR": "ds", "BRANCH": "st",
            "LOAD": "ds", "STORE": "st", "OP-IMM": "ds", "OP": "dst", "FENCE": "", "SYSTEM": "", "XPULSE": "dst"}[OPS[op]]
    for kind, reg in (("d", rd), ("s", rs1), ("t", rs2)):
        if kind in uses and reg > 15:
            return f"uses x{reg}: RV32E has only x0..x15 (compile with -mabi=ilp32e)"
    if op == 0x33 and f7 == 0x01:
        return "multiply/divide (M extension): link sw/lib/rt.c and compile without M"
    if op == 0x33 and not (f7 == 0 or (f7 == 0x20 and f3 in (0, 5))):
        return f"OP with funct7={f7:#x} funct3={f3} is reserved"
    if op == 0x13 and f3 == 1 and f7 != 0 or op == 0x13 and f3 == 5 and f7 not in (0, 0x20):
        return "reserved shift encoding"
    if op == 0x73 and w not in (0x00000073, 0x00100073):
        return "CSR or privileged instruction: only ECALL and EBREAK exist"
    if op == 0x03 and f3 in (3, 6, 7): return "load width not in RV32"
    if op == 0x23 and f3 > 2: return "store width not in RV32"
    if op == 0x63 and f3 in (2, 3): return "reserved branch"
    if op == 0x67 and f3 != 0: return "reserved JALR"
    return None

def main(path):
    elf = ELFFile(open(path, "rb"))
    text = elf.get_section_by_name(".text")
    syms = {s.name: s["st_value"] for s in elf.get_section_by_name(".symtab").iter_symbols()}
    if "_code_end" not in syms:
        sys.exit("no _code_end symbol: link with sw/link.ld or sw/link_ram.ld")
    base, data = text["sh_addr"], text.data()
    end = syms["_code_end"] - base
    bad = 0
    for off in range(0, end, 4):
        w = int.from_bytes(data[off:off + 4], "little")
        why = problem(w)
        if why:
            bad += 1
            print(f"  {base + off:08x}: {w:08x}   {why}")
    n = end // 4
    print(f"{path}: {n} instructions, {'all runnable on TinyPulse' if not bad else f'{bad} NOT runnable'}")
    return bad == 0

if __name__ == "__main__":
    ok = all(main(p) for p in sys.argv[1:])
    sys.exit(0 if ok else 1)
