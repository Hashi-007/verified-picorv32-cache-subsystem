# Conflict workload: alternate two blocks mapped to cache index 0.
# Input fixture: word 0x1000 contains 1; word 0x2000 contains 2.
# Their tags are 1 and 2, so each alternating input load replaces the other.
# Repeat 128 read pairs; expected sum 128 * (1 + 2) = 384 (0x00000180).
# Store the result at 0x3000 and completion marker 1 at 0x10FFC.
# cache_conflict.hex contains 16 hand-encoded words, independently decoded.
# The TB supplies the two input words; the runner profile is conflict.
    .option norvc
    .text
    .balign 4
    .globl _start

_start:
    addi x3, x0, 0        # Running sum.
    addi x4, x0, 128      # Pairs remaining.
    lui  x5, 0x1          # Fixed address A: 0x1000.
    lui  x6, 0x2          # Fixed address B: 0x2000.

pair_loop:
    # Load the word at 0(x5) into x7.
    lw   x7, 0(x5)
    # Add x7 to the running sum x3.
    add  x3, x7, x3
    # Load the word at 0(x6) into x7.
    lw   x7, 0(x6)
    # Add x7 to the running sum x3.
    add  x3, x7, x3
    # Decrement x4 by 1.
    addi x4, x4, -1
    # Branch to pair_loop while x4 is nonzero.
    bne  x4, x0, pair_loop

    lui  x6, 0x3
    sw   x3, 0(x6)        # Result at 0x3000.

    lui  x6, 0x11
    addi x7, x0, 1
    sw   x7, -4(x6)       # Completion marker.

done:
    jal  x0, done
