# crt0.S — reset entry for TinyPulse-Skywater130.
# The core starts fetching at 0x00000000, which is the first word of the
# external QSPI flash, so this must be the first thing the linker places.
    .section .text.init, "ax"
    .global _start
_start:
    # RV32E has 16 registers; x2 is the stack pointer by the ilp32e ABI.
    la      sp, _stack_top
    la      gp, __global_pointer$

    # zero .bss
    la      t0, _bss_start
    la      t1, _bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    call    main

    # main returned: halt. ECALL parks the core with HALT high on uo[4].
    ecall
3:  j       3b
