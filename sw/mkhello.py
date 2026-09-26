"""mkhello.py — the microcontroller "hello world", as test/hello.hex.

What it does, in order — each step exercises one thing a microcontroller
must do, and test/test.py checks every one from the pins alone:

  1. set the UART to 8 clocks per bit (fast, so simulation stays short;
     on a real board you would leave the reset value, 115,200 baud)
  2. hand uo_out[0..3] and [5..7] to software, keep UART TX on uo_out[4]
  3. print "Hi TinyPulse\\n" over the UART, polling TX_BUSY between bytes
  4. copy the input pins to the output pins (GPIO_IN -> GPIO_OUT), so a
     test can drive ui_in and see its pattern on uo_out
  5. toggle uo_out[7] three times with GPIO_XOR (an LED blink, minus the delay)
  6. halt with ECALL

Encoders are the same hand-written ones mkprog.py uses: no toolchain needed,
and every instruction's bit pattern is visible here.
"""
import sys
from mkprog import addi, lui, sw, lw, bne, jal, I, R, OPC_OPIMM, OPC_OP, OPC_SYSTEM

PERIPH  = 5          # x5 = 0x3000_0000, the GPIO/UART block
GPIO_OUT, GPIO_IN, GPIO_SEL, UART_DATA, UART_STAT, UART_DIV = 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14
GPIO_SET, GPIO_CLR, GPIO_XOR = 0x18, 0x1C, 0x20

def andi(rd, rs1, imm): return I(OPC_OPIMM, 7, rd, rs1, imm)
def ecall():            return 0x00000073

MESSAGE = b"Hi TinyPulse\n"

prog, notes = [], []
def emit(word, note):
    prog.append(word); notes.append(note)

emit(lui(PERIPH, 0x30000),          "x5 = 0x3000_0000 (peripherals)")
emit(addi(6, 0, 8),                 "x6 = 8")
emit(sw(6, PERIPH, UART_DIV),       "UART_DIV = 8 clocks per bit")
emit(addi(6, 0, 0x10),              "x6 = 0x10")
emit(sw(6, PERIPH, GPIO_SEL),       "GPIO_SEL: only uo_out[4] keeps its function (UART TX)")

for ch in MESSAGE:
    emit(addi(6, 0, ch),            f"x6 = {chr(ch)!r}")
    emit(sw(6, PERIPH, UART_DATA),  "send it")
    emit(lw(7, PERIPH, UART_STAT),  "poll: x7 = UART_STAT")
    emit(andi(7, 7, 1),             "      x7 &= TX_BUSY")
    emit(bne(7, 0, -8),             "      loop while busy")

emit(lw(6, PERIPH, GPIO_IN),        "x6 = input pins")
emit(sw(6, PERIPH, GPIO_OUT),       "echo them on the output pins")
emit(addi(6, 0, 0x80),              "x6 = bit 7")
for _ in range(3):
    emit(sw(6, PERIPH, GPIO_XOR),   "toggle uo_out[7]")
emit(ecall(),                       "halt")

out = sys.argv[1] if len(sys.argv) > 1 else "hello.hex"
with open(out, "w") as f:
    for w in prog:
        f.write(f"{w:08x}\n")
for i, (w, n) in enumerate(zip(prog, notes)):
    print(f"{4*i:04x}: {w:08x}   {n}")
print(f"\nwrote {out} ({len(prog)} words)")
