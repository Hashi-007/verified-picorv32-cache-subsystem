module processor_top #(
    parameter bit USE_DCACHE = 1'b1,
    parameter bit USE_ICACHE = 1'b0
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] ram_rdata,
    input  logic        ram_ready,

    output logic [31:0] ram_wdata,
    output logic [3:0]  ram_wstrb,
    output logic [31:0] ram_addr,
    output logic        ram_valid,
    output logic        trap,

    input  logic        tb_owns_port,
    input  logic        tb_valid,
    input  logic [31:0] tb_addr,
    output logic        tb_ready,
    output logic [31:0] tb_rdata
);

    logic        mem_valid;
    logic        mem_instr;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0]  mem_wstrb;
    logic        mem_ready;
    logic [31:0] mem_rdata;

    logic        port_valid, port_instr, port_ready;
    logic [31:0] port_wdata, port_addr, port_rdata;
    logic [3:0]  port_wstrb;

    assign port_valid = tb_owns_port ? tb_valid : mem_valid;
    assign port_addr  = tb_owns_port ? tb_addr : mem_addr;
    assign port_wdata = tb_owns_port ? 32'd0 : mem_wdata;
    assign port_wstrb = tb_owns_port ? 4'b0000 : mem_wstrb;
    assign port_instr = tb_owns_port ? 1'b0 : mem_instr;

    assign mem_ready = tb_owns_port ? 1'b0 : port_ready;
    assign tb_ready  = tb_owns_port ? port_ready : 1'b0;

    assign mem_rdata = port_rdata;
    assign tb_rdata  = port_rdata;

    // Upstream PicoRV32, configured for the native-port RV32I setup.
    // The CPU drives requests; the wrapper supplies completion and read data.
    picorv32 #(
        .ENABLE_REGS_16_31 (1'b1),
        .COMPRESSED_ISA    (1'b0),
        .ENABLE_PCPI       (1'b0),
        .ENABLE_MUL        (1'b0),
        .ENABLE_FAST_MUL   (1'b0),
        .ENABLE_DIV        (1'b0),
        .ENABLE_IRQ        (1'b0),
        .ENABLE_TRACE      (1'b0),
        .LATCHED_MEM_RDATA (1'b0),
        .PROGADDR_RESET    (32'h00000000)
    ) cpu (
        .clk       (clk),
        .resetn    (rst_n),
        .trap      (trap),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_ready (mem_ready),
        .mem_rdata (mem_rdata),

        // Optional coprocessor and interrupt inputs are disabled and tied low.
        .pcpi_wr    (1'b0),
        .pcpi_rd    (32'd0),
        .pcpi_wait  (1'b0),
        .pcpi_ready (1'b0),
        .irq        (32'd0),

        // Unused look-ahead, coprocessor, interrupt and trace outputs.
        .mem_la_read  (),
        .mem_la_write (),
        .mem_la_addr  (),
        .mem_la_wdata (),
        .mem_la_wstrb (),
        .pcpi_valid   (),
        .pcpi_insn    (),
        .pcpi_rs1     (),
        .pcpi_rs2     (),
        .eoi          (),
        .trace_valid  (),
        .trace_data   ()
    );
    // Both bypass choices live inside the wrapper.
    cache_wrapper #(
        .USE_DCACHE (USE_DCACHE),
        .USE_ICACHE (USE_ICACHE)
    ) cache (
        .clk       (clk),
        .rst_n     (rst_n),
        .mem_valid (port_valid),
        .mem_instr (port_instr),
        .mem_addr  (port_addr),
        .mem_wdata (port_wdata),
        .mem_wstrb (port_wstrb),
        .mem_rdata (port_rdata),
        .mem_ready (port_ready),
        .ram_valid (ram_valid),
        .ram_addr  (ram_addr),
        .ram_wdata (ram_wdata),
        .ram_wstrb (ram_wstrb),
        .ram_ready (ram_ready),
        .ram_rdata (ram_rdata)
    );
endmodule
