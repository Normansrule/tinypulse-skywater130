# Makefile — build C for TinyPulse-Skywater130 with a stock RISC-V toolchain.
#
# RV32E means 16 registers, which is what fits on the tile. There is no M
# extension, no compressed extension and no control and status registers
# (CSRs), so keep -march exactly as it is.

CROSS   ?= riscv32-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump

ARCH     = -march=rv32e -mabi=ilp32e
CFLAGS   = $(ARCH) -Os -ffreestanding -nostdlib -fno-builtin \
           -Wall -Wextra -ffunction-sections -fdata-sections
LDFLAGS  = $(ARCH) -nostdlib -T link.ld -Wl,--gc-sections

SRCS     = crt0.S camera_sync.c
TARGET   = camera_sync

all: $(TARGET).bin $(TARGET).lst

$(TARGET).elf: $(SRCS) link.ld tinypulse.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS)

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
