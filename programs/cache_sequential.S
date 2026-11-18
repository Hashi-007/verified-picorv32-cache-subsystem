# Sequential workload: one pass through 5 KiB, exceeding the 4 KiB cache.
# Reuses the summation loop from cache_reuse.S; image hand-encoded.
# Input fixture: 1280 words containing 1..1280 at 0x1000..0x23FC.
# Sum: 1280 * 1281 / 2 = 819840 (0x000C8280).
# Result address: 0x3000, outside the input array.
# Completion marker: store 1 at 0x10FFC.
# cache_sequential.hex contains these 17 RV32I words, independently decoded.
# The TB supplies the input fixture; the runner profile is sequential.
    .option norvc
    .text
    .balign 4
    .globl _start

_start:
    addi x3, x0, 0        # Running sum.
    # Initialize x4 to 1 pass.
    addi x4, x0, 1

pass_loop:
    lui  x6, 0x1          # Start address 0x1000.
    # Initialize x5 to 1280 words.
    addi x5, x0, 1280

word_loop:
    lw   x7, 0(x6)
    add  x3, x7, x3
    addi x6, x6, 4
    addi x5, x5, -1
    bne  x5, x0, word_loop

    addi x4, x4, -1
    bne  x4, x0, pass_loop

    # Load result address 0x3000 into x6 using lui.
    lui  x6, 0x3
    # Store x3 at offset 0 from x6.
    sw   x3, 0(x6)

    lui  x6, 0x11
    addi x7, x0, 1
    sw   x7, -4(x6)

done:
    jal  x0, done
