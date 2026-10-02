/* link.ld — programs that run from flash (the normal case).
 *
 * Code and constants stay in the QSPI flash and execute in place. Writable
 * data lives in RAM A: its initial values are stored in flash right after
 * the code (the "load address"), and crt0.S copies them to RAM at start-up.
 * The stack grows down from the top of RAM A.
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
        _code_end = .;                  /* sw/rv32e_check.py checks up to here */
        *(.rodata .rodata.* .srodata .srodata.*)
        . = ALIGN(4);
    } > FLASH

    .data : {
        _data_start = .;
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
        *(.data .data.*)
        . = ALIGN(4);
        _data_end = .;
    } > PSRAM AT > FLASH
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
