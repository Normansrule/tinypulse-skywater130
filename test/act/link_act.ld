OUTPUT_ARCH(riscv)
ENTRY(rvtest_entry_point)
MEMORY { RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 16M }
SECTIONS {
    .text   : { *(.text.init) *(.text*) _code_end = .; } > RAM
    .data   : { *(.data*) *(.sdata*) *(.rodata*) } > RAM
    .tohost : { *(.tohost) } > RAM
    .bss    : { *(.bss*) *(.sbss*) } > RAM
    /DISCARD/ : { *(.eh_frame .eh_frame_hdr .comment .note*) }
}
