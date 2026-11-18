# PicoRV32 upstream dependency

Imported 2026-11-16 for cache subsystem integration. PicoRV32 is existing
third-party CPU IP from the YosysHQ project.

- Repository: https://github.com/YosysHQ/picorv32
- Pinned revision: `ef203c2b0a3fb793280f5114941416c425c5b461`
- Source: https://raw.githubusercontent.com/YosysHQ/picorv32/ef203c2b0a3fb793280f5114941416c425c5b461/picorv32.v
- License: https://raw.githubusercontent.com/YosysHQ/picorv32/ef203c2b0a3fb793280f5114941416c425c5b461/COPYING
- License type: ISC; original source header and separate COPYING are retained.
- Local modifications to imported files: none.

SHA256 of the downloaded bytes:

| File | SHA256 |
| --- | --- |
| picorv32.v | 0836050971B3C6CDD28AC3B1E5719A67FB645161912BEF1E472E63995CEB0622 |
| COPYING | 041EBC727233E5BF096DD41260CBB81014D3D29CA007A15F3B1807D4E9FF288E |

processor_top instantiates the native-port picorv32 module, with all 32
integer registers enabled and compressed instructions, multiply/divide,
external PCPI, interrupts and trace disabled. The reset address is zero.
Other parameters retain upstream defaults, including counter support.
LATCHED_MEM_RDATA is zero: read data is supplied at the completion handshake.
The unused PCPI/IRQ inputs are tied low and unused outputs are left open.

The CPU's STACKADDR remains at its upstream default FFFFFFFF (no automatic
stack-pointer initialization). A future program needing a stack must initialize
it through program startup or a deliberate configuration update. The subsequent integration and program tests are documented in the
[project overview](../../README.md) and
[performance report](../../verification/CACHE_MODES_REPORT.md).
