# Cache subsystem specification

**Implemented and simulation-validated, 18 November 2026.**
This specification describes the final I-cache/D-cache integration.

## Geometry

Both caches contain 4 KiB of data, excluding metadata: 256 direct-mapped
lines of 16 bytes, each holding four 32-bit words. Addresses are 32-bit byte
addresses; data is little endian.

| Address field | Bits | Width |
| --- | --- | ---: |
| Tag | [31:12] | 20 |
| Line index | [11:4] | 8 |
| Word offset | [3:2] | 2 |
| Byte offset | [1:0] | 2 |

Each cache has 256 tags and valid bits. The D-cache additionally has a dirty
bit per line. A hit requires a valid line with a matching tag.

## Transaction contract

CPU-facing and RAM-facing ports use native valid/ready handshakes.
A transfer completes on a rising edge with both valid and ready asserted.
The requester holds valid, address, write data and strobes stable until
completion. Read data is sampled on that completion edge.

The CPU has one request outstanding. The wrapper routes instruction requests
to the I-cache path and data requests to the D-cache path. Both caches share
one 32-bit RAM interface. Independent elaboration parameters `USE_ICACHE`
and `USE_DCACHE` select cache or bypass hardware; defaults are 0 and 1.
These are not runtime switches.

## Data-cache behavior

`cpu_wstrb == 0` selects a read; any nonzero mask selects a store.
Strobe bit i enables byte `[8*i +: 8]` of the selected 32-bit word.
Requests use word-aligned addresses; byte masks select lanes.

| Condition | Action |
| --- | --- |
| Read hit | Return the selected cached word |
| Store hit | Update enabled bytes and set dirty |
| Miss with invalid or clean victim | Refill the requested line |
| Miss with valid dirty victim | Write back all four victim words, then refill |
| Completed refill | Commit tag/valid, clear dirty and retry the original request |

Writeback uses the victim tag and selected index, and sends four full-word
stores with strobes `1111`. Refill uses the requested tag/index and four
reads with strobes `0000`. The two-bit word counter advances only on RAM
handshakes. A line being refilled is invalid until all four words arrive.
The original CPU request stays stable throughout the miss.

Controllers: D-cache `IDLE / LOOKUP / WRITEBACK / ALLOCATE`;
I-cache `IDLE / LOOKUP / ALLOCATE`.

## Instruction-cache behavior

The I-cache only reads. A hit returns the selected instruction word.
A miss reads all four words of its line, commits tag/valid on the final
handshake, then retries lookup. There are no dirty bits or writeback.
The original word offset selects the response after refill.

Program memory remains fixed during execution. This version has no FENCE.I
or self-modifying-code support.

## Clock and reset

All hardware uses one clock and synchronous active-low reset.
Reset clears controller/counter state and valid bits. The D-cache also
clears dirty bits. Stored data need not be cleared because invalid lines
cannot hit. RAM contents survive reset.

Reset cancels unfinished CPU requests and refills. RAM stores that already
completed remain written; uncommitted dirty cache data may be lost.
Reset is not a flush or a transactional rollback.

## Processor simulation

PicoRV32 uses its native memory interface in RV32I configuration, with reset
PC zero, 32 integer registers and compressed instructions, multiply/divide,
PCPI, interrupts and trace disabled. See the pinned
[upstream configuration record](third_party/picorv32/UPSTREAM.md).

| Region | Byte-address range |
| --- | --- |
| Code | 0x00000000–0x00000FFF |
| Data RAM | 0x00001000–0x00010FFF |
| Reserved completion word | 0x00010FFC |

RAM wait L means a request first observed at edge N completes at edge N+L.
Every word pays that delay; there is no burst discount or overlap.
The experiments use L=1, 4 and 8.

A completed CPU full-word store of 1 to the completion address ends program
timing. The testbench then takes the normal data port to read the result,
holding the CPU off without resetting the caches. That checker traffic is
reported separately.

## Acceptance and evidence

- Standalone D-cache: 16 positive cases, three random seeds and 442 defined
  functional bins, plus a separate fault-injection checker probe.
- Standalone I-cache: directed hit/miss, offset, replacement, stall and
  partial-refill reset checks at waits 1/4/8.
- Processor: four workloads × four configurations × three waits, plus four
  smoke cases; all 52 check completion, x3 and result readback.

See [verification](verification/README.md) and
[measured results](verification/CACHE_MODES_REPORT.md).
No whole-cache flush, associativity, multiple outstanding transactions, AXI,
coherence, MMIO, memory-error handling or FPGA implementation is claimed.
