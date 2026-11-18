# Small working-set reuse benchmark.
# Input fixture: 16 words containing 1..16 at byte addresses 0x1000..0x103C.
# Sum all 16 words on each of 16 passes: 16 * (16 * 17 / 2) = 2176.
# Result: 0x00000880 at 0x1100. Completion: store 1 at 0x10FFC.
# cache_reuse.hex contains these 17 RV32I instruction words, starting at 0.
# Hand-encoded; checked by independent decoding against this source.
# Encoding reference: https://github.com/riscv/riscv-opcodes/blob/master/extensions/rv_i
    .option norvc
    .text
    .balign 4
    .globl _start

_start:
    addi x3, x0, 0        # Running sum, initialized once.
    addi x4, x0, 16       # Passes remaining.

pass_loop:
    lui  x6, 0x1          # Restart at address 0x1000 on every pass.
    addi x5, x0, 16       # Words remaining in this pass.

word_loop:
    lw   x7, 0(x6)
    add  x3, x7, x3
    addi x6, x6, 4
    addi x5, x5, -1
    bne  x5, x0, word_loop

    addi x4, x4, -1
    bne  x4, x0, pass_loop

    lui  x6, 0x1
    sw   x3, 256(x6)      # Result at 0x1100.

    lui  x6, 0x11
    addi x7, x0, 1
    sw   x7, -4(x6)       # Completion marker at 0x10FFC.

done:
    jal  x0, done
