# crt0.S — start-up code for TinyPulse, for both link.ld (from flash) and
# link_ram.ld (loaded over the UART bootloader).
#
#   1. set the stack pointer and global pointer
#   2. copy initialized data from its load address to RAM (a no-op when the
#      program was loaded into RAM, where the two addresses are equal)
#   3. zero .bss
#   4. call main(); when it returns, ECALL halts the core and raises HALT
#      (uo_out[5], if that pin is still in its built-in function)
    .section .text.init, "ax"
    .global _start
_start:
    .option push
    .option norelax
    la      sp, _stack_top
    la      gp, __global_pointer$
    .option pop

    la      t0, _data_lma
    la      t1, _data_start
    la      t2, _data_end
    beq     t0, t1, 2f
1:  bgeu    t1, t2, 2f
    lw      a0, 0(t0)
    sw      a0, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       1b
2:
    la      t0, _bss_start
    la      t1, _bss_end
3:  bgeu    t0, t1, 4f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       3b
4:
    call    main
    ecall
5:  j       5b
