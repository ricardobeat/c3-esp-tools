/* Entry point. The ROM jumps here with SRAM loaded and nothing else set up.
 *
 * Sets sp and gp, clears .bss, builds the thread-local block and points tp at
 * it, installs a trap handler and calls c3_main. */

    .section .text.init, "ax"
    .globl _start
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    la      sp, _stack_top

    csrw    mie, zero
    csrci   mstatus, 8

    /* .bss */
    la      t0, _bss_start
    la      t1, _bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    /* TLS block: zero it, then copy the .tdata image over the front */
    la      t0, __tls_start
    la      t1, __tls_end
3:  bgeu    t0, t1, 4f
    sb      zero, 0(t0)
    addi    t0, t0, 1
    j       3b
4:  la      t0, __tdata_start
    la      t1, __tdata_end
    la      t2, __tls_start
5:  bgeu    t0, t1, 6f
    lbu     t3, 0(t0)
    sb      t3, 0(t2)
    addi    t0, t0, 1
    addi    t2, t2, 1
    j       5b
6:  la      tp, __tls_start

    la      t0, trap_entry
    csrw    mtvec, t0

    call    c3_main
7:  wfi
    j       7b

    .balign 256
    .globl trap_entry
trap_entry:
    csrr    a0, mcause
    csrr    a1, mepc
    csrr    a2, mtval
    call    c3_trap
8:  wfi
    j       8b

    /* Keep .tdata and .tbss in every link, so the TLS symbols in the linker
     * script always exist even for programs without a `tlocal`. */
    .section .tdata, "awT", @progbits
    .balign 4
tls_anchor:
    .word   0
    .section .tbss, "awT", @nobits
    .balign 4
tls_bss_anchor:
    .space  4
