/* link.ld — TinyPulse-Skywater130 memory map.
 *
 * Code and read-only data live in the external QSPI flash, which the core
 * fetches from directly. Writable data and the stack live in the external
 * QSPI PSRAM. There is no on-chip memory of any kind; see the area budget
 * in the README for why.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 16M
    PSRAM (rwx) : ORIGIN = 0x10000000, LENGTH = 8M
}

SECTIONS
{
    .text : {
        KEEP(*(.text.init))
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > FLASH

    .data : {
        __global_pointer$ = . + 0x800;
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > PSRAM

    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _bss_end = .;
    } > PSRAM

    _stack_top = ORIGIN(PSRAM) + LENGTH(PSRAM);
}
