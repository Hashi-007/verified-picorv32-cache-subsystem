// Directed instruction-cache checks: hits, refills, stalls and reset.
module instruction_cache_tb #(
    parameter int unsigned RAM_WAIT_CYCLES = 1
);
    timeunit 1ns;
    timeprecision 1ps;

    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        instr_valid = 1'b0;
    logic [31:0] instr_addr = '0;
    logic        instr_ready;
    logic [31:0] instr_rdata;
    logic        mem_valid, mem_ready;
    logic [31:0] mem_addr, mem_rdata;
    bit passed = 0;

    int unsigned completed_fetches = 0;
    int unsigned ram_reads = 0;
    int unsigned stalled_cycles = 0;
    int unsigned aborted_refills = 0;
    bit active_fetch = 0;
    logic [31:0] active_addr;
    int unsigned expected_beats, seen_beats;
    bit held_request = 0;
    logic [31:0] held_addr;

    always #5ns clk = ~clk;

    instruction_cache dut (.*);

    wrapper_ram_model #(.WAIT_CYCLES(RAM_WAIT_CYCLES)) ram (
        .clk       (clk),
        .rst_n     (rst_n),
        .ram_valid (mem_valid),
        .ram_addr  (mem_addr),
        .ram_wdata (32'b0),
        .ram_wstrb (4'b0000),
        .ram_ready (mem_ready),
        .ram_rdata (mem_rdata)
    );

    // Address-dependent values make wrong tags and wrong word selection visible.
    function automatic logic [31:0] expected_word(logic [31:0] addr);
        return 32'hA53C_0000 ^ ((addr >> 2) * 32'h0101_0101);
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            held_request = 0;
            if (mem_valid !== 1'b0 || instr_ready !== 1'b0)
                $fatal(1, "ICACHE_RESET_OUTPUT: request/response active during reset");
        end else begin
            if ($isunknown({mem_valid, instr_ready}))
                $fatal(1, "ICACHE_UNKNOWN_CONTROL");
            if (held_request && (mem_valid !== 1'b1 || mem_addr !== held_addr))
                $fatal(1, "ICACHE_STALL: RAM request changed before handshake");
            held_request = mem_valid && !mem_ready;
            if (held_request) begin
                held_addr = mem_addr;
                stalled_cycles++;
            end
            if (mem_valid && mem_ready) begin
                if (!active_fetch || seen_beats >= expected_beats)
                    $fatal(1, "ICACHE_EXTRA_RAM_READ: addr=%h", mem_addr);
                if (mem_addr !== ((active_addr & 32'hFFFF_FFF0) + 4 * seen_beats))
                    $fatal(1, "ICACHE_REFILL_ADDRESS: request=%h beat=%0d got=%h",
                           active_addr, seen_beats, mem_addr);
                seen_beats++;
                ram_reads++;
            end
            if (instr_ready && !instr_valid)
                $fatal(1, "ICACHE_UNREQUESTED_RESPONSE");
            if (!active_fetch && mem_valid)
                $fatal(1, "ICACHE_UNREQUESTED_RAM_READ");
        end
    end

    task automatic fetch(logic [31:0] addr, int unsigned beats,
                         bit keep_valid = 0);
        bit complete;
        @(negedge clk);
        active_fetch   = 1;
        active_addr    = addr;
        expected_beats = beats;
        seen_beats     = 0;
        instr_addr     = addr;
        instr_valid    = 1;
        complete       = 0;
        repeat (100) begin
            @(posedge clk);
            if (instr_ready) begin
                if (instr_rdata !== expected_word(addr))
                    $fatal(1, "ICACHE_DATA: addr=%h expected=%h got=%h",
                           addr, expected_word(addr), instr_rdata);
                if (seen_beats != beats)
                    $fatal(1, "ICACHE_RAM_COUNT: addr=%h expected=%0d got=%0d",
                           addr, beats, seen_beats);
                completed_fetches++;
                complete = 1;
                break;
            end
        end
        if (!complete)
            $fatal(1, "ICACHE_TIMEOUT: addr=%h", addr);
        if (!keep_valid) begin
            @(negedge clk);
            instr_valid  = 0;
            active_fetch = 0;
        end
    endtask

    task automatic reset_cache();
        @(negedge clk);
        rst_n        = 0;
        instr_valid  = 0;
        active_fetch = 0;
        repeat (2)
            @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    endtask

    task automatic interrupt_refill(int unsigned completed_words);
        logic [31:0] addr;
        bit reached;
        reset_cache();
        addr = 32'h0040 + 16 * completed_words;
        @(negedge clk);
        active_fetch   = 1;
        active_addr    = addr;
        expected_beats = 4;
        seen_beats     = 0;
        instr_addr     = addr;
        instr_valid    = 1;
        reached        = 0;
        repeat (100) begin
            @(negedge clk);
            if (instr_ready)
                $fatal(1, "ICACHE_EARLY_RESPONSE");
            if (mem_valid && seen_beats == completed_words) begin
                reached = 1;
                break;
            end
        end
        if (!reached)
            $fatal(1, "ICACHE_RESET_POINT: words=%0d", completed_words);
        // Abort at a falling edge, after exactly 0/1/2/3 completed RAM reads.
        rst_n        = 0;
        instr_valid  = 0;
        active_fetch = 0;
        repeat (2)
            @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        aborted_refills++;
        fetch(addr, 4);
        fetch(addr + 12, 0);
    endtask

    initial begin
        if (RAM_WAIT_CYCLES < 1 || RAM_WAIT_CYCLES > 8)
            $fatal(1, "RAM_WAIT_CYCLES must be 1..8");
        // Let the reusable RAM model finish its time-zero initialization first.
        #1ns;
        for (int i = 0; i < 32'h11000 / 4; i++)
            ram.memory[i] = expected_word(4 * i);
        reset_cache();

        // Cold tag-zero miss, then every word offset with no new RAM traffic.
        fetch(32'h0004, 4);
        fetch(32'h0000, 0);
        fetch(32'h0008, 0);
        fetch(32'h000C, 0);
        fetch(32'h0004, 0);

        // Next line and continuous valid across three successive CPU requests.
        fetch(32'h0010, 4);
        fetch(32'h0014, 0, 1);
        fetch(32'h0018, 0, 1);
        fetch(32'h001C, 0);

        // Same index, different tag: replace, use, then replace back.
        fetch(32'h1004, 4);
        fetch(32'h1000, 0);
        fetch(32'h100C, 0);
        fetch(32'h0004, 4);
        fetch(32'h0008, 0);

        // Highest line index and nonsequential first-word selection.
        fetch(32'h0FFC, 4);
        fetch(32'h0FF0, 0);
        fetch(32'h1FFC, 4);
        fetch(32'h1FF0, 0);
        fetch(32'h0FFC, 4);
        fetch(32'h0028, 4);
        fetch(32'h0020, 0);
        fetch(32'h002C, 0);

        // Reset must invalidate a previously hitting tag-zero line.
        fetch(32'h0004, 0);
        reset_cache();
        fetch(32'h0004, 4);
        for (int words = 0; words < 4; words++)
            interrupt_refill(words);

        repeat (3)
            @(posedge clk);
        @(negedge clk);
        if (completed_fetches != 32 || ram_reads != 58 || aborted_refills != 4 ||
            stalled_cycles == 0)
            $fatal(1, "ICACHE_TOTALS: fetches=%0d ram_reads=%0d aborts=%0d stalls=%0d",
                   completed_fetches, ram_reads, aborted_refills, stalled_cycles);
        passed = 1;
        $display("ICACHE_STANDALONE_PASS wait=%0d fetches=%0d ram_reads=%0d interrupted_refills=%0d stalled_cycles=%0d",
                 RAM_WAIT_CYCLES, completed_fetches, ram_reads, aborted_refills, stalled_cycles);
        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "ICACHE_WATCHDOG");
    end
endmodule
