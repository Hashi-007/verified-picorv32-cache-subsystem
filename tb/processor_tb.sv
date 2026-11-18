// Processor program testbench with CPU-side completion detection.
module processor_tb #(
    parameter bit USE_DCACHE = 1'b1,
    parameter bit USE_ICACHE = 1'b0,
    parameter int unsigned RAM_WAIT_CYCLES = 1,
    parameter string PROGRAM_HEX = "programs/cache_smoke.hex",
    parameter logic [31:0] RESULT_ADDR = 32'h00001004,
    parameter logic [31:0] EXPECTED_RESULT = 32'h11223345
);
    timeunit 1ns;
    timeprecision 1ps;

    logic        clk = 0;
    logic        rst_n = 0;
    always #5ns clk = ~clk;

    logic        ram_valid;
    logic [31:0] ram_addr, ram_wdata;
    logic [3:0]  ram_wstrb;
    logic        ram_ready;
    logic [31:0] ram_rdata;
    logic        trap;
    bit program_completed = 0;
    bit readback_passed = 0;
    int cycles_completed = 0;
    int unsigned ram_instr_reads = 0;
    int unsigned ram_data_reads = 0;
    int unsigned ram_data_writes = 0;
    int unsigned cache_hits = 0;
    int unsigned cache_misses = 0;
    bit request_had_refill = 0;
    int unsigned cpu_instr_fetches = 0;
    int unsigned icache_hits = 0;
    int unsigned icache_misses = 0;
    bit instr_request_had_refill = 0;
    int unsigned cpu_data_reads = 0;
    int unsigned cpu_data_stores = 0;
    int unsigned cache_read_hits = 0;
    int unsigned cache_read_misses = 0;
    int unsigned tb_ram_reads = 0;
    int unsigned tb_ram_writes = 0;

    logic        tb_owns_port = 0;
    logic        tb_valid = 0;
    logic [31:0] tb_addr = 0;
    logic        tb_ready;
    logic [31:0] tb_rdata;

    processor_top #(
        .USE_DCACHE (USE_DCACHE),
        .USE_ICACHE (USE_ICACHE)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .ram_valid    (ram_valid),
        .ram_addr     (ram_addr),
        .ram_wdata    (ram_wdata),
        .ram_wstrb    (ram_wstrb),
        .ram_ready    (ram_ready),
        .ram_rdata    (ram_rdata),
        .trap         (trap),
        .tb_owns_port (tb_owns_port),
        .tb_valid     (tb_valid),
        .tb_addr      (tb_addr),
        .tb_ready     (tb_ready),
        .tb_rdata     (tb_rdata)
    );

    wrapper_ram_model #(
        .WAIT_CYCLES (RAM_WAIT_CYCLES)
    ) ram (
        .clk       (clk),
        .rst_n     (rst_n),
        .ram_valid (ram_valid),
        .ram_addr  (ram_addr),
        .ram_wdata (ram_wdata),
        .ram_wstrb (ram_wstrb),
        .ram_ready (ram_ready),
        .ram_rdata (ram_rdata)
    );

    initial begin
        repeat (2)
            @(posedge clk);

        $readmemh(PROGRAM_HEX, ram.memory);

        if (PROGRAM_HEX == "programs/cache_reuse.hex") begin
            for (int i = 0; i < 16; i++) begin
                ram.memory[1024 + i] = i + 1;
            end
        end else if (PROGRAM_HEX == "programs/cache_sequential.hex") begin
            for (int i = 0; i < 1280; i++) begin
                ram.memory[1024 + i] = i + 1;
            end
        end else if (PROGRAM_HEX == "programs/cache_conflict.hex") begin
            ram.memory[1024] = 32'd1;
            ram.memory[2048] = 32'd2;
        end

        @(negedge clk);
        rst_n = 1;
    end

    always @(posedge clk) begin
        if (!rst_n)
            cycles_completed <= 0;
        else
            cycles_completed <= cycles_completed + 1;
    end

    initial begin
        wait (program_completed);
        @(negedge clk);
        // The marker-edge counter updates have completed before this report.
        $display("CACHE_CONFIG dcache_enabled=%0b icache_enabled=%0b",
                 USE_DCACHE, USE_ICACHE);
        $display("RAM_TRAFFIC instr_reads=%0d data_reads=%0d data_writes=%0d",
                 ram_instr_reads, ram_data_reads, ram_data_writes);
        $display("CACHE_ACCESS cache_enabled=%0b hits=%0d misses=%0d",
                 USE_DCACHE, cache_hits, cache_misses);
        $display("CPU_DATA reads=%0d stores=%0d read_hits=%0d read_misses=%0d",
                 cpu_data_reads, cpu_data_stores, cache_read_hits, cache_read_misses);
        $display("ICACHE_ACCESS cache_enabled=%0b fetches=%0d hits=%0d misses=%0d",
                 USE_ICACHE, cpu_instr_fetches, icache_hits, icache_misses);
        if (USE_ICACHE && cpu_instr_fetches != 0)
            $display("ICACHE_HIT_RATE percent=%.2f", 100.0 * icache_hits / cpu_instr_fetches);
        else
            $display("ICACHE_HIT_RATE percent=N/A");
        if (USE_DCACHE && (cpu_data_reads + cpu_data_stores) != 0)
            $display("DCACHE_HIT_RATE all_percent=%.2f read_percent=%.2f",
                     100.0 * cache_hits / (cpu_data_reads + cpu_data_stores),
                     cpu_data_reads != 0 ? 100.0 * cache_read_hits / cpu_data_reads : 0.0);
        else
            $display("DCACHE_HIT_RATE all_percent=N/A read_percent=N/A");
        tb_owns_port = 1;
        tb_addr      = RESULT_ADDR;
        tb_valid     = 1;

        do @(posedge clk); while (!tb_ready);

        if (tb_rdata !== EXPECTED_RESULT) begin
            $fatal(1, "READBACK_DATA: expected %08h, got %08h",
                   EXPECTED_RESULT, tb_rdata);
        end

        @(negedge clk);
        tb_valid        = 1'b0;
        readback_passed = 1'b1;
        $display("CHECKER_READBACK requests=1 ram_reads=%0d ram_writes=%0d",
                 tb_ram_reads, tb_ram_writes);
        $finish;
    end

    // Count completed RAM words during CPU execution, including the marker.
    // Exclude the subsequent result read driven by this testbench.
    always @(posedge clk) begin
        if (!rst_n) begin
            ram_instr_reads <= 0;
            ram_data_reads  <= 0;
            ram_data_writes <= 0;
            tb_ram_reads    <= 0;
            tb_ram_writes   <= 0;
        end else if (ram_valid && ram_ready) begin
            if (tb_owns_port) begin
                if (ram_wstrb == 4'b0000)
                    tb_ram_reads <= tb_ram_reads + 1;
                else
                    tb_ram_writes <= tb_ram_writes + 1;
            end else if (dut.mem_instr)
                ram_instr_reads <= ram_instr_reads + 1;
            else if (ram_wstrb == 4'b0000)
                ram_data_reads <= ram_data_reads + 1;
            else
                ram_data_writes <= ram_data_writes + 1;
        end
    end

    // Count accepted instruction fetches, including prefetches, not retirement.
    // A full-line refill completes before the original CPU fetch completes.
    always @(posedge clk) begin
        if (!rst_n) begin
            cpu_instr_fetches        <= 0;
            icache_hits              <= 0;
            icache_misses            <= 0;
            instr_request_had_refill <= 1'b0;
        end else if (!tb_owns_port) begin
            if (USE_ICACHE && ram_valid && ram_ready && dut.mem_instr)
                instr_request_had_refill <= 1'b1;
            if (dut.mem_valid && dut.mem_ready && dut.mem_instr) begin
                cpu_instr_fetches <= cpu_instr_fetches + 1;
                if (USE_ICACHE) begin
                    if (instr_request_had_refill)
                        icache_misses <= icache_misses + 1;
                    else
                        icache_hits <= icache_hits + 1;
                end
                instr_request_had_refill <= 1'b0;
            end
        end
    end

    // Count each original CPU data request once at completion.
    // In this blocking cache, refill reads finish before the CPU handshake.
    // Leave hit/miss counters at zero in bypass mode (not applicable).
    always @(posedge clk) begin
        if (!rst_n) begin
            cache_hits         <= 0;
            cache_misses       <= 0;
            request_had_refill <= 1'b0;
            cache_read_hits    <= 0;
            cache_read_misses  <= 0;
        end else if (USE_DCACHE && !tb_owns_port) begin
            if (ram_valid && ram_ready && !dut.mem_instr &&
                ram_wstrb == 4'b0000) begin
                request_had_refill <= 1'b1;
            end

            if (dut.mem_valid && dut.mem_ready && !dut.mem_instr) begin
                if (request_had_refill) begin
                    cache_misses <= cache_misses + 1;
                    if (dut.mem_wstrb == 4'b0000)
                        cache_read_misses <= cache_read_misses + 1;
                end else begin
                    cache_hits <= cache_hits + 1;
                    if (dut.mem_wstrb == 4'b0000)
                        cache_read_hits <= cache_read_hits + 1;
                end
                request_had_refill <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cpu_data_reads  <= 0;
            cpu_data_stores <= 0;
        end else if (!tb_owns_port && dut.mem_valid && dut.mem_ready && !dut.mem_instr) begin
            if (dut.mem_wstrb == 4'b0000)
                cpu_data_reads <= cpu_data_reads + 1;
            else
                cpu_data_stores <= cpu_data_stores + 1;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (trap)
                $fatal(1, "PROCESSOR_TRAP: CPU trapped before completing the program");

            if (dut.mem_valid && dut.mem_ready && !dut.mem_instr &&
                dut.mem_addr == 32'h00010FFC && dut.mem_wstrb == 4'b1111) begin
                if (dut.mem_wdata !== 32'd1)
                    $fatal(1, "PROCESSOR_MARKER: expected 1, got %08h", dut.mem_wdata);

                program_completed = 1;
                $display("Program completed: CPU stored 1 at 0x00010FFC");
                // Keep the historical data-cache label for the baseline audit.
                $display("USE_CACHE=%0b cycles=%0d", USE_DCACHE, cycles_completed + 1);
            end
        end
    end
endmodule
