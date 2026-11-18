# Store-heavy workload: overwrite 16 words on each of 16 passes.
# Pass 1 writes 1 to every word; pass 16 writes 16 to every word.
# Data addresses: 0x1000..0x103C (four cache lines, indices 0..3).
# After the writes, conflicting reads evict all four dirty lines to RAM.
# Read the original words back and sum them: 16 * 16 = 256 (0x100).
# Result at 0x3000; completion marker 1 at 0x10FFC.
# Learner completed the seven loop instructions; mentor supplied the rest.
# cache_store_heavy.hex contains 30 hand-encoded words, independently decoded.
# Runner profile: store_heavy. No separate input fixture is required.
    .option norvc
    .text
    .balign 4
    .globl _start

_start:
    addi x4, x0, 16       # Passes remaining.
    addi x7, x0, 1        # Value to write during this pass.

pass_loop:
    lui  x6, 0x1          # Restart at address 0x1000.
    addi x5, x0, 16       # Words remaining in this pass.

word_loop:
    # Store this pass's value.
    sw   x7, 0(x6)

    # Advance to the next word.
    addi x6, x6, 4

    # Count down the words in this pass.
    addi x5, x5, -1

    # Continue until all 16 words have been written.
    bne  x5, x0, word_loop

    # Use the next value for the next pass.
    addi x7, x7, 1

    # Count down the passes.
    addi x4, x4, -1

    # Restart at 0x1000 while passes remain.
    bne  x4, x0, pass_loop

    # Mentor-supplied verification: evict the four dirty data lines.
    # These addresses share indices 0..3 with 0x1000/1010/1020/1030.
    # The loaded values are discarded; the reads trigger replacement.
    lui  x6, 0x2
    lw   x7, 0(x6)
    lw   x7, 16(x6)
    lw   x7, 32(x6)
    lw   x7, 48(x6)

    # Reload the original data from RAM and compute the checksum in x3.
    addi x3, x0, 0
    lui  x6, 0x1
    addi x5, x0, 16

check_loop:
    lw   x7, 0(x6)
    add  x3, x3, x7
    addi x6, x6, 4
    addi x5, x5, -1
    bne  x5, x0, check_loop

    lui  x6, 0x3
    sw   x3, 0(x6)        # Expected result: 256 at 0x3000.

    lui  x6, 0x11
    addi x7, x0, 1
    sw   x7, -4(x6)       # Completion marker at 0x10FFC.

done:
    jal  x0, done
