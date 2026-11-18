interface cache_if(input logic clk);
    logic        rst_n;

    // CPU-facing signals.
    logic        cpu_valid;
    logic [31:0] cpu_addr;
    logic [31:0] cpu_wdata;
    logic [3:0]  cpu_wstrb;
    logic        cpu_ready;
    logic [31:0] cpu_rdata;

    // Backing-memory-facing signals.
    logic        mem_valid;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0]  mem_wstrb;
    logic        mem_ready;
    logic [31:0] mem_rdata;
endinterface
