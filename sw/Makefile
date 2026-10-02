# Makefile — build C for TinyPulse-Skywater130 with a stock RISC-V toolchain.
#
# RV32E means 16 registers, which is what fits on the tile. There is no M
# extension, no compressed extension and no control and status registers
# (CSRs), so keep -march exactly as it is.

# Toolchain: GNU by default. `make TOOLCHAIN=zig` uses the Clang inside the
# ziglang pip package instead (pip install ziglang) — no cross-compiler to
# install, and it is what the repository's own tests use.
TOOLCHAIN ?= gnu
ifeq ($(TOOLCHAIN),zig)
CC       = python3 -m ziglang cc -target riscv32-freestanding-none -mcpu=generic_rv32+e-i
OBJCOPY  = python3 -m ziglang objcopy
OBJDUMP  = true
ARCH     = -mabi=ilp32e
else
CROSS   ?= riscv32-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
ARCH     = -march=rv32e -mabi=ilp32e
endif
CFLAGS   = $(ARCH) -Os -g -fno-unwind-tables -fno-asynchronous-unwind-tables -ffreestanding -nostdlib -fno-builtin \
           -Wall -Wextra -ffunction-sections -fdata-sections
LDFLAGS  = $(ARCH) -nostdlib -T $(LDSCRIPT) -Wl,--gc-sections

# `make`          program for flash (put camera_sync.bin in flash with the TT flasher)
# `make RAM=1`    program for RAM   (send it with: python3 tpload.py -p PORT camera_sync.bin)
SRCS     = crt0.S lib/rt.c camera_sync.c
TARGET   = camera_sync
ifeq ($(RAM),1)
LDSCRIPT = link_ram.ld
else
LDSCRIPT = link.ld
endif

all: $(TARGET).bin $(TARGET).lst

$(TARGET).elf: $(SRCS) $(LDSCRIPT) tinypulse.h tp_io.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS)
	python3 rv32e_check.py $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).lst: $(TARGET).elf
	$(OBJDUMP) -d -S $< > $@

# the simulator wants one 32-bit hex word per line
$(TARGET).hex: $(TARGET).bin
	python3 -c "import sys;d=open('$<','rb').read();d+=b'\0'*((-len(d))%4);\
print('\n'.join('%08x'%int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)))" > $@

clean:
	rm -f *.elf *.bin *.lst *.hex

.PHONY: all clean
