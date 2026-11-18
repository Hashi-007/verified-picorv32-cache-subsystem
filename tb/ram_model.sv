module ram_model (cache_if vif);

    logic [31:0] memory [16383:0];
    int unsigned wait_cycles = 1;
    int unsigned cycles_left;
    bit random_wait;
    int unsigned selected_wait;

    initial begin
        if (!$value$plusargs("RAM_WAIT=%d", wait_cycles))
            wait_cycles = 1;
        if (wait_cycles < 1 || wait_cycles > 8)
            $fatal(1, "RAM_WAIT must be from 1 through 8");
        random_wait = $test$plusargs("RAM_RANDOM");
    end

    initial begin
        for (int unsigned i = 0; i < 16384; i++)
            memory[i] = i;
    end

    logic [31:0] word_index;
    assign word_index = (vif.mem_addr - 32'h1000) >> 2;

    always @(posedge vif.clk) begin
        if (!vif.rst_n) begin
            vif.mem_ready <= 1'b0;
            cycles_left   <= 0;
        end
        else if (vif.mem_ready) begin
            vif.mem_ready <= 1'b0;
            cycles_left   <= 0;

            if (vif.mem_valid) begin
                if (vif.mem_wstrb[0])
                    memory[word_index][7:0] <= vif.mem_wdata[7:0];

                if (vif.mem_wstrb[1])
                    memory[word_index][15:8] <= vif.mem_wdata[15:8];

                if (vif.mem_wstrb[2])
                    memory[word_index][23:16] <= vif.mem_wdata[23:16];

                if (vif.mem_wstrb[3])
                    memory[word_index][31:24] <= vif.mem_wdata[31:24];
            end
        end
        else if (vif.mem_valid) begin
            // Pick once at the first observed request edge, never while stalled.
            if (cycles_left == 0)
                selected_wait = random_wait ? $urandom_range(8, 1) : wait_cycles;
            if ((cycles_left == 0 && selected_wait == 1) || cycles_left == 1) begin
                vif.mem_ready <= 1'b1;
                cycles_left   <= 0;
                if (vif.mem_wstrb == '0)
                    vif.mem_rdata <= memory[word_index];
            end else if (cycles_left == 0) begin
                cycles_left <= selected_wait - 1;
            end else begin
                cycles_left <= cycles_left - 1;
            end
        end
    end
endmodule
