#!/usr/bin/env python3
"""tpload.py — send a program to TinyPulse over its UART and run it.

Hardware: a USB-to-UART bridge (3.3 V) with its TX on ui_in[3] and its RX on
uo_out[4], plus ground. Hold ui_in[7] high while you release reset: the chip
starts its boot ROM, prints "TP>", and waits for a program.

    python3 tpload.py -p /dev/ttyUSB0 program.bin        # raw image for 0x1000_0000
    python3 tpload.py -p /dev/ttyUSB0 program.hex        # one 32-bit hex word per line
    python3 tpload.py -p COM5 program.bin --monitor      # then show what it prints
    python3 tpload.py selftest                           # no hardware needed

Build C programs for RAM with sw/link_ram.ld, then
    riscv32-unknown-elf-objcopy -O binary program.elf program.bin

Protocol (implemented by the boot ROM, sw/mkboot.py):
    chip -> host   "TP>"
    host -> chip   length N, 4 bytes little endian, then N bytes
    chip -> host   (sum of the N bytes) mod 256, then "K"
    the chip then runs the program from 0x1000_0000

Only depends on pyserial (pip install pyserial).
"""
import argparse, struct, sys, time

MAX_BYTES = 8 * 1024 * 1024          # RAM A


def load_image(path):
    if path.endswith(".hex"):
        words = [int(l.split()[0], 16) for l in open(path) if l.strip() and not l.startswith("#")]
        return b"".join(struct.pack("<I", w) for w in words)
    return open(path, "rb").read()


def frame(image):
    if not image:
        raise ValueError("the program is empty")
    if len(image) > MAX_BYTES:
        raise ValueError(f"{len(image)} bytes will not fit in RAM A ({MAX_BYTES} bytes)")
    return struct.pack("<I", len(image)) + image, sum(image) & 0xFF


def load(port, image, timeout=5.0, log=print):
    """Send `image` over an open serial port. Returns True on a verified load."""
    payload, want = frame(image)
    port.timeout = timeout
    port.reset_input_buffer()
    log("waiting for TP> (hold ui_in[7] high and release reset now)...")
    seen = b""
    deadline = time.time() + 30
    while not seen.endswith(b"TP>"):
        c = port.read(1)
        if c: seen += c
        if time.time() > deadline:
            log("no TP> seen: is ui_in[7] high during reset, and are TX/RX the right way round?")
            return False
    log(f"bootloader ready; sending {len(image)} bytes")
    t0 = time.time()
    port.write(payload); port.flush()
    reply = port.read(2)
    if len(reply) != 2:
        log(f"no acknowledgement (got {reply!r}); check the baud rate (115,200 at 50 MHz)")
        return False
    if reply[1:] != b"K" or reply[0] != want:
        log(f"checksum mismatch: chip {reply[0]:#04x}, expected {want:#04x}; line noise or wrong baud")
        return False
    log(f"verified in {time.time() - t0:.1f} s; running from 0x1000_0000")
    return True


class FakeChip:
    """Enough of the boot ROM, in Python, to test the host side with no board."""
    def __init__(self, corrupt=False):
        self.out, self.inbuf, self.corrupt, self.timeout = bytearray(b"TP>"), bytearray(), corrupt, 1
        self.ram = None
    def reset_input_buffer(self): pass
    def flush(self): pass
    def read(self, n):
        r, self.out = bytes(self.out[:n]), self.out[n:]
        return r
    def write(self, data):
        self.inbuf += data
        if len(self.inbuf) >= 4:
            n = struct.unpack("<I", self.inbuf[:4])[0]
            if len(self.inbuf) >= 4 + n:
                self.ram = bytes(self.inbuf[4:4 + n])
                s = (sum(self.ram) + (1 if self.corrupt else 0)) & 0xFF
                self.out += bytes([s]) + b"K"


def selftest():
    ok = fails = 0
    def check(cond, what):
        nonlocal ok, fails
        ok += cond; fails += (not cond)
        print(("  ok    " if cond else "  FAIL  ") + what)
    quiet = lambda *a: None
    img = bytes(range(256)) * 3 + b"\x13\x00\x00\x00"
    chip = FakeChip()
    check(load(chip, img, log=quiet), "a clean load is verified")
    check(chip.ram == img, "the chip received every byte, in order")
    check(frame(img)[0][:4] == struct.pack("<I", len(img)), "length is sent first, little endian")
    check(not load(FakeChip(corrupt=True), img, log=quiet), "a corrupted transfer is reported as a failure")
    try: frame(b""); check(False, "an empty program is refused")
    except ValueError: check(True, "an empty program is refused")
    try: frame(b"\0" * (MAX_BYTES + 1)); check(False, "an oversized program is refused")
    except ValueError: check(True, "an oversized program is refused")
    import os, tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".hex", delete=False) as f:
        f.write("00000013\n12345678\n")
    check(load_image(f.name) == b"\x13\x00\x00\x00\x78\x56\x34\x12", ".hex words become little-endian bytes")
    os.unlink(f.name)
    print(f"\n{ok} checks, {fails} failures")
    return fails == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image", help="program.bin / program.hex, or 'selftest'")
    ap.add_argument("-p", "--port", help="serial port, e.g. /dev/ttyUSB0 or COM5")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("--monitor", action="store_true", help="print what the program sends afterwards")
    a = ap.parse_args()
    if a.image == "selftest":
        sys.exit(0 if selftest() else 1)
    if not a.port:
        ap.error("--port is required")
    import serial
    with serial.Serial(a.port, a.baud) as port:
        if not load(port, load_image(a.image)):
            sys.exit(1)
        if a.monitor:
            port.timeout = 0.1
            print("--- program output (Ctrl-C to stop) ---")
            try:
                while True:
                    d = port.read(256)
                    if d: sys.stdout.write(d.decode(errors="replace")); sys.stdout.flush()
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    main()
