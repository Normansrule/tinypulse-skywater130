/* link_ram.ld — for programs loaded over the UART bootloader (sw/tpload.py).
   Everything, code and data, lives in RAM A from 0x1000_0000, where the boot
   ROM jumps after a verified load. The stack grows down from the top of RAM A.
   Symbol names match sw/crt0.S and sw/link.ld. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { PSRAM (rwx) : ORIGIN = 0x10000000, LENGTH = 8M }
SECTIONS {
    .text : {
        *(.text.init)              /* crt0 first: execution starts at 0x1000_0000 */
        *(.text*)
        *(.rodata*)
    } > PSRAM
    .data : {
        __global_pointer$ = . + 0x800;
        *(.sdata*) *(.data*)
    } > PSRAM
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.sbss*) *(.bss*) *(COMMON)
        _bss_end = .;
    } > PSRAM
    _stack_top = ORIGIN(PSRAM) + LENGTH(PSRAM);
}
