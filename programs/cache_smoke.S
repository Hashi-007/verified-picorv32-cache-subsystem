# RV32I smoke program for cached load/store integration.
# cache_smoke.hex contains these nine instructions starting at byte address 0.
# Encodings follow https://github.com/riscv/riscv-opcodes/blob/master/extensions/rv_i
    .option norvc
    .text
    .balign 4
    .globl _start

_start:
    lui  x1, 0x1          # Base address: 0x1000.
    lw   x2, 0(x1)        # Read the RAM fixture: 0x11223344.
    addi x2, x2, 1        # Result: 0x11223345.
    sw   x2, 4(x1)        # Store at 0x1004 through the data cache.
    lw   x3, 4(x1)        # Read the result back into x3.

    lui  x4, 0x11         # Completion base address: 0x11000.
    addi x5, x0, 1
    sw   x5, -4(x4)       # Completion marker: store 1 at 0x10FFC.

done:
    jal  x0, done         # Stay here after completion.
