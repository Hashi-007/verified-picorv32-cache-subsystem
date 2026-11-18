// Separate shared RAM for wrapper tests: code and data start at byte address 0.
// A request first seen at edge N completes at edge N + WAIT_CYCLES.
module wrapper_ram_model #(
    parameter int unsigned WAIT_CYCLES = 1
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ram_valid,
    input  logic [31:0] ram_addr,
    input  logic [31:0] ram_wdata,
    input  logic [3:0]  ram_wstrb,
    output logic        ram_ready,
    output logic [31:0] ram_rdata
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam int WORDS = 32'h11000 / 4;
    int unsigned wait_count;
    logic [31:0] memory [0:WORDS - 1];
    logic [31:0] word_index;
    assign word_index = ram_addr >> 2;

    initial begin
        for (int i = 0; i < WORDS; i++)
            memory[i] = '0;
        // Default wrapper-test patterns; processor tests load their own image.
        memory[32'h0000 >> 2] = 32'hA5A55A5A;
        memory[32'h1000 >> 2] = 32'h11223344;
        memory[32'h1004 >> 2] = 32'h55667788;
        memory[32'h1008 >> 2] = 32'h99AABBCC;
        memory[32'h100C >> 2] = 32'hDDEEFF00;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ram_ready  <= 1'b0;
            ram_rdata  <= '0;
            wait_count <= 0;
        end else begin
            if (ram_valid) begin
                if ($isunknown({ram_addr, ram_wstrb}) ||
                    ram_addr[1:0] != 0 || ram_addr > 32'h10FFC)
                    $fatal(1, "WRAPPER_RAM_FIELDS: invalid addr=%h strb=%h", ram_addr, ram_wstrb);
            end

            if (ram_ready) begin
                ram_ready  <= 1'b0;
                wait_count <= 0;
                // Write only at the actual valid && ready completion edge.
                if (ram_valid)
                    for (int byte_lane = 0; byte_lane < 4; byte_lane++)
                        if (ram_wstrb[byte_lane])
                            memory[word_index][8 * byte_lane +: 8] <= ram_wdata[8 * byte_lane +: 8];
            end else if (ram_valid) begin
                if (wait_count == WAIT_CYCLES - 1) begin
                    ram_ready <= 1'b1;
                    if (ram_wstrb == 0)
                        ram_rdata <= memory[word_index];
                end else begin
                    wait_count <= wait_count + 1;
                end
            end
        end
    end
endmodule
