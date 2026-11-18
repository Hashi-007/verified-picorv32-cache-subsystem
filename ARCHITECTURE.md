# Cache subsystem architecture

This document describes the implemented subsystem. The processor is
third-party PicoRV32 IP; the cache and integration contribution is described
in [ATTRIBUTION.md](ATTRIBUTION.md).

## Request routing and responses

~~~mermaid
flowchart LR
    CPU["PicoRV32<br/>valid · instr · addr · wdata · wstrb"] --> PORT["CPU / testbench ownership mux"]
    PORT --> SPLIT["Instruction/data routing"]
    SPLIT --> IP["I-cache or bypass<br/>USE_ICACHE"]
    SPLIT --> DP["D-cache or bypass<br/>USE_DCACHE"]
    IP --> SELECT["RAM request selection"]
    DP --> SELECT
    SELECT --> RAM["RAM model<br/>32-bit words"]
    RAM --> RESP["Ready / read-data routing"]
    RESP --> IP
    RESP --> DP
    IP --> CPU
    DP --> CPU
~~~

The testbench ownership mux is simulation support for final result readback.
During normal execution the CPU owns the port. Its `mem_instr` signal selects
the instruction or data path for the complete request, including RAM refill
or writeback activity. One held CPU request makes a separate I/D arbiter
unnecessary in this integration.

The wrapper contains both cache/bypass generate blocks. `processor_top`
always instantiates the wrapper and forwards its two configuration parameters.

## Signal groups

| Boundary | Request toward receiver | Response toward requester |
| --- | --- | --- |
| CPU → processor wrapper | `mem_valid, mem_instr, mem_addr, mem_wdata, mem_wstrb` | `mem_ready, mem_rdata` |
| Instruction routing → I-cache | `instr_valid, instr_addr` | `instr_ready, instr_rdata` |
| Data routing → D-cache | `cpu_valid, cpu_addr, cpu_wdata, cpu_wstrb` | `cpu_ready, cpu_rdata` |
| I-cache → RAM selection | `ic_mem_valid, ic_mem_addr` | `ic_mem_ready, ic_mem_rdata` |
| D-cache → RAM selection | `cache_mem_valid, cache_mem_addr, cache_mem_wdata, cache_mem_wstrb` | `cache_mem_ready, cache_mem_rdata` |
| Wrapper → RAM | `ram_valid, ram_addr, ram_wdata, ram_wstrb` | `ram_ready, ram_rdata` |

The table uses CPU-port signal names inside `processor_top` and cache-port
names on their modules. Wrapper data-path response wires are `cache_ready`
and `cache_rdata`. Instruction RAM requests always select read strobes.
Bypass connects a selected CPU request directly to RAM and routes its response
back. Completion always requires valid and ready at a rising edge.

## Cache storage and addresses

Each cache stores 256 × 128-bit data lines, 256 × 20-bit tags and valid bits.
The D-cache also stores 256 dirty bits. Index `addr[11:4]` selects the line;
tag `addr[31:12]` is compared with its stored tag.
Word `addr[3:2]` selects one of four 32-bit words; store strobes select bytes.

| Operation | RAM word address |
| --- | --- |
| Refill | `{requested_tag, index, word_counter, 2'b00}` |
| Writeback | `{victim_tag, index, word_counter, 2'b00}` |

All four words are transferred through the same 32-bit interface.
The word counter holds during stalls and advances only on RAM handshakes.

## Data-cache controller

~~~mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> LOOKUP: CPU request valid
    LOOKUP --> IDLE: hit / complete read or store
    LOOKUP --> WRITEBACK: miss / valid dirty victim
    LOOKUP --> ALLOCATE: miss / invalid or clean victim
    WRITEBACK --> WRITEBACK: stall or more victim words
    WRITEBACK --> ALLOCATE: fourth write handshake
    ALLOCATE --> ALLOCATE: stall or more refill words
    ALLOCATE --> LOOKUP: fourth read handshake / commit line
~~~

A store hit changes enabled bytes and marks the line dirty. On a miss,
the original CPU fields stay stable until the controller retries lookup.
The selected line is invalidated when entering ALLOCATE, so an interrupted
refill cannot expose a partially updated line. The final refill handshake
commits tag/valid and clears dirty; retrying a store then updates its bytes
and sets dirty again.

## Instruction-cache controller

~~~mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> LOOKUP: instruction request valid
    LOOKUP --> IDLE: hit / return requested word
    LOOKUP --> ALLOCATE: miss
    ALLOCATE --> ALLOCATE: stall or more refill words
    ALLOCATE --> LOOKUP: fourth read handshake / commit line
~~~

There is no WRITEBACK state because instructions are read only.
Both controllers return the requested word after a complete line refill.
Reset from any state invalidates metadata and returns to IDLE.

## Measurement boundary

The completion-marker CPU handshake ends workload timing and freezes
workload counters. The testbench then stalls the CPU and reads the result
through the normal data path. This may hit a dirty cache line; RAM is not
required to hold the latest result at that point.

Cycles exclude that checker transaction and any final full-cache drain.
Instruction counts are accepted fetches, including prefetches, rather than
retired instructions. See [the report](verification/CACHE_MODES_REPORT.md)
for counter definitions and interpretation.
