/* link_ram.ld — programs loaded over the UART bootloader (sw/tpload.py).
 * Everything lives in RAM A from 0x1000_0000, where the boot ROM jumps after
 * a verified load. Initialized data is already in place, so the load address
 * equals the run address and crt0.S's copy loop does nothing.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { PSRAM (rwx) : ORIGIN = 0x10000000, LENGTH = 8M }
SECTIONS
{
    .text : {
        KEEP(*(.text.init))
        *(.text .text.*)
        _code_end = .;                  /* sw/rv32e_check.py checks up to here */
        *(.rodata .rodata.* .srodata .srodata.*)
        . = ALIGN(4);
    } > PSRAM
    .data : {
        _data_start = .;
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
        *(.data .data.*)
        . = ALIGN(4);
        _data_end = .;
    } > PSRAM
    _data_lma = LOADADDR(.data);
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > PSRAM
    /* unwind tables and notes the compiler may emit; nothing here needs them */
    /DISCARD/ : { *(.eh_frame .eh_frame_hdr .note .note.* .comment) }

    _stack_top = ORIGIN(PSRAM) + LENGTH(PSRAM);
}
