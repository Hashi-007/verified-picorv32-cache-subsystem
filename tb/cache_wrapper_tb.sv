// Three-access wrapper smoke test with an independent shared RAM model.
module cache_wrapper_tb;
    timeunit 1ns;
    timeprecision 1ps;

    logic        clk = 0;
    logic        rst_n = 0;
    always #5ns clk = ~clk;

    logic        mem_valid = 0;
    logic        mem_instr = 0;
    logic [31:0] mem_addr = 0;
    logic [31:0] mem_wdata = 0;
    logic [3:0]  mem_wstrb = 0;
    logic        mem_ready;
    logic [31:0] mem_rdata;
    logic        ram_valid;
    logic [31:0] ram_addr, ram_wdata;
    logic [3:0]  ram_wstrb;
    logic        ram_ready;
    logic [31:0] ram_rdata;

    int unsigned cpu_count = 0;
    int unsigned ram_count = 0;
    bit test_passed = 0;

    localparam logic [31:0] EXPECTED_RAM_ADDR [0:4] = '{
        32'h0000, 32'h1000, 32'h1004, 32'h1008, 32'h100C
    };
    localparam logic [31:0] EXPECTED_RAM_DATA [0:4] = '{
        32'hA5A55A5A, 32'h11223344, 32'h55667788, 32'h99AABBCC, 32'hDDEEFF00
    };

    cache_wrapper dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_ready (mem_ready),
        .mem_rdata (mem_rdata),
        .ram_valid (ram_valid),
        .ram_addr  (ram_addr),
        .ram_wdata (ram_wdata),
        .ram_wstrb (ram_wstrb),
        .ram_ready (ram_ready),
        .ram_rdata (ram_rdata)
    );

    wrapper_ram_model ram (
        .clk       (clk),
        .rst_n     (rst_n),
        .ram_valid (ram_valid),
        .ram_addr  (ram_addr),
        .ram_wdata (ram_wdata),
        .ram_wstrb (ram_wstrb),
        .ram_ready (ram_ready),
        .ram_rdata (ram_rdata)
    );

    // Count only rising-edge handshakes. Also check every RAM word's address,
    // direction and data, not just the number of completed transfers.
    always @(posedge clk) begin
        if (rst_n) begin
            if ($isunknown({mem_valid, mem_ready, ram_valid, ram_ready}))
                $fatal(1, "WRAPPER_CONTROL_X: unknown valid/ready signal");
            if (mem_valid && mem_ready) begin
                cpu_count++;
                $display("CPU_OBS instr=%0b addr=%08h data=%08h", mem_instr, mem_addr, mem_rdata);
            end
            if (ram_valid && ram_ready) begin
                if (ram_count >= 5)
                    $fatal(1, "WRAPPER_EXTRA_RAM: unexpected sixth RAM transfer");
                if (ram_addr !== EXPECTED_RAM_ADDR[ram_count] || ram_wstrb !== 4'b0000 ||
                    ram_rdata !== EXPECTED_RAM_DATA[ram_count])
                    $fatal(1, "WRAPPER_RAM_WORD: word=%0d addr=%h strb=%h data=%h", ram_count,
                           ram_addr, ram_wstrb, ram_rdata);
                $display("RAM_OBS word=%0d addr=%08h strb=%h data=%08h",
                         ram_count, ram_addr, ram_wstrb, ram_rdata);
                ram_count++;
            end
        end
    end

    a_cpu_stable: assert property (
        @(posedge clk) disable iff (!rst_n)
        (mem_valid && !mem_ready) |=>
        (mem_valid && $stable({mem_instr, mem_addr, mem_wdata, mem_wstrb}))
    ) else $fatal(1, "WRAPPER_CPU_STABILITY: pending CPU request changed");

    a_ram_stable: assert property (
        @(posedge clk) disable iff (!rst_n)
        (ram_valid && !ram_ready) |=>
        (ram_valid && $stable({ram_addr, ram_wdata, ram_wstrb}))
    ) else $fatal(1, "WRAPPER_RAM_STABILITY: pending RAM request changed");

    task automatic read_check(
        input string label,
        input bit instruction,
        input  logic [31:0] address,
        input  logic [31:0] expected_data,
        input int unsigned expected_ram_words
    );
        int unsigned ram_before;
        bit completed;
        logic [31:0] actual_data;

        @(negedge clk);
        ram_before = ram_count;
        mem_instr  = instruction;
        mem_addr   = address;
        mem_wdata  = 0;
        mem_wstrb  = 0;
        mem_valid  = 1;
        completed  = 0;

        for (int cycle = 0; cycle < 100; cycle++) begin
            @(posedge clk);
            if (instruction && dut.g_dcache.cache.cpu_valid !== 1'b0)
                $fatal(1, "WRAPPER_BYPASS: instruction request entered data cache");
            if (expected_ram_words == 0 && ram_valid !== 1'b0)
                $fatal(1, "WRAPPER_HIT: data hit incorrectly requested RAM");
            if (mem_valid && mem_ready) begin
                actual_data = mem_rdata;
                completed   = 1;
                break;
            end
        end
        if (!completed)
            $fatal(1, "WRAPPER_TIMEOUT: %s did not complete", label);
        if (actual_data !== expected_data)
            $fatal(1, "WRAPPER_DATA: %s expected=%08h actual=%08h", label, expected_data, actual_data);

        // Check counters at the falling edge, after all rising-edge observers
        // have run. Instruction CPU and RAM completions occur on the same edge.
        @(negedge clk);
        mem_valid = 0;
        if (ram_count - ram_before != expected_ram_words)
            $fatal(1, "WRAPPER_RAM_COUNT: %s expected=%0d actual=%0d", label,
                   expected_ram_words, ram_count - ram_before);
        $display("WRAPPER_CHECK PASS %s data=%08h ram_words=%0d", label,
                 actual_data, ram_count - ram_before);
    endtask

    initial begin
        $timeformat(-9, 0, " ns", 10);
        repeat (2)
            @(posedge clk);
        @(negedge clk);
        rst_n = 1;

        read_check("instruction_fetch", 1, 32'h0000, 32'hA5A55A5A, 1);
        read_check("data_miss",         0, 32'h1000, 32'h11223344, 4);
        read_check("data_hit",          0, 32'h1000, 32'h11223344, 0);

        repeat (2)
            @(negedge clk);
        if (cpu_count != 3 || ram_count != 5 || ram_valid !== 0 || mem_ready !== 0)
            $fatal(1, "WRAPPER_FINAL: expected three CPU/five RAM completions and idle outputs");
        test_passed = 1;
        $display("WRAPPER_SMOKE_PASS cpu=%0d ram_reads=%0d ram_writes=0", cpu_count, ram_count);
        $finish;
    end

    initial begin
        #20us;
        $fatal(1, "WRAPPER_WATCHDOG: test exceeded 20 us");
    end
endmodule
