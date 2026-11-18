module cache_wrapper #(
    parameter bit USE_DCACHE = 1'b1,
    parameter bit USE_ICACHE = 1'b0
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        mem_valid,
    input  logic        mem_instr,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wdata,
    input  logic [3:0]  mem_wstrb,

    output logic        mem_ready,
    output logic [31:0] mem_rdata,

    output logic        ram_valid,
    output logic [31:0] ram_addr,
    output logic [31:0] ram_wdata,
    output logic [3:0]  ram_wstrb,

    input  logic        ram_ready,
    input  logic [31:0] ram_rdata
);

    logic        instr_valid;
    logic        data_valid;
    logic        instr_ready;
    logic [31:0] instr_rdata;
    logic        cache_ready;
    logic [31:0] cache_rdata;
    logic        cache_mem_valid;
    logic [31:0] cache_mem_addr;
    logic [31:0] cache_mem_wdata;
    logic [3:0]  cache_mem_wstrb;
    logic        cache_mem_ready;
    logic [31:0] cache_mem_rdata;
    logic        ic_mem_ready, ic_mem_valid;
    logic [31:0] ic_mem_addr, ic_mem_rdata;

    assign instr_valid = mem_valid && mem_instr;
    assign data_valid  = mem_valid && ~mem_instr;

    assign mem_ready = mem_instr ? instr_ready : cache_ready;
    assign mem_rdata = mem_instr ? instr_rdata : cache_rdata;

    assign ram_valid = mem_instr ? ic_mem_valid : cache_mem_valid;
    assign ram_addr  = mem_instr ? ic_mem_addr : cache_mem_addr;
    assign ram_wdata = mem_instr ? 32'b0 : cache_mem_wdata;
    assign ram_wstrb = mem_instr ? 4'b0000 : cache_mem_wstrb;

    assign cache_mem_ready = !mem_instr && ram_ready;
    assign cache_mem_rdata = ram_rdata;

    assign ic_mem_ready = mem_instr && ram_ready;
    assign ic_mem_rdata = ram_rdata;

    generate
        if (USE_DCACHE) begin : g_dcache
            data_cache cache (
                .clk       (clk),
                .rst_n     (rst_n),
                .cpu_valid (data_valid),
                .cpu_addr  (mem_addr),
                .cpu_wdata (mem_wdata),
                .cpu_wstrb (mem_wstrb),
                .cpu_ready (cache_ready),
                .cpu_rdata (cache_rdata),
                .mem_valid (cache_mem_valid),
                .mem_addr  (cache_mem_addr),
                .mem_wdata (cache_mem_wdata),
                .mem_wstrb (cache_mem_wstrb),
                .mem_ready (cache_mem_ready),
                .mem_rdata (cache_mem_rdata)
            );
        end else begin : g_data_bypass
            assign cache_mem_valid = data_valid;
            assign cache_mem_addr  = mem_addr;
            assign cache_mem_wdata = mem_wdata;
            assign cache_mem_wstrb = mem_wstrb;
            assign cache_ready    = cache_mem_ready;
            assign cache_rdata    = cache_mem_rdata;
        end

        if (USE_ICACHE) begin : g_icache
            instruction_cache i_cache (
                .clk         (clk),
                .rst_n       (rst_n),
                .instr_valid (instr_valid),
                .instr_addr  (mem_addr),
                .instr_ready (instr_ready),
                .instr_rdata (instr_rdata),
                .mem_valid   (ic_mem_valid),
                .mem_addr    (ic_mem_addr),
                .mem_ready   (ic_mem_ready),
                .mem_rdata   (ic_mem_rdata)
            );
        end else begin : g_instr_bypass
            assign ic_mem_valid = instr_valid;
            assign ic_mem_addr  = mem_addr;
            assign instr_ready = ic_mem_ready;
            assign instr_rdata = ic_mem_rdata;
        end
    endgenerate
endmodule
