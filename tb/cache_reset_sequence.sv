class cache_reset_sequence extends cache_base_sequence;
    `uvm_object_utils(cache_reset_sequence)

    virtual cache_if vif;

    function new(string name = "cache_reset_sequence");
        super.new(name);
    endfunction

    task body();
        logic [31:0] r_data;

        wait (vif.rst_n);

        fork
            begin
                // Issue a read at 0x1000.
                cache_read(32'h1000, r_data);
            end
            begin
                // Wait for two completed RAM reads.
                repeat (2) begin
                    do @(posedge vif.clk);
                    while (!(vif.mem_ready && vif.mem_valid));
                end
                // Assert reset on a falling edge; hold for two rising edges.
                @(negedge vif.clk);
                vif.rst_n = 1'b0;
                @(posedge vif.clk);
                @(posedge vif.clk);
                // Release reset on a falling edge.
                @(negedge vif.clk);
                vif.rst_n = 1'b1;
            end
        join

        // Read 0x1000 again after reset.
        cache_read(32'h1000, r_data);

        cache_write(32'h1000, 32'hA1, 4'b1111);
        cache_write(32'h1004, 32'hB2, 4'b1111);
        cache_write(32'h1008, 32'hC3, 4'b1111);
        cache_write(32'h100C, 32'hD4, 4'b1111);

        fork
            begin
                // Evict the dirty 0x1000 line.
                cache_read(32'h2000, r_data);
            end
            begin
                // Wait for two completed writeback words.
                repeat (2) begin
                    do @(posedge vif.clk);
                    while (!(vif.mem_ready && vif.mem_valid && vif.mem_wstrb == 4'b1111));
                end
                // Assert reset on a falling edge; hold for two rising edges.
                @(negedge vif.clk);
                vif.rst_n = 1'b0;
                @(posedge vif.clk);
                @(posedge vif.clk);
                // Release reset on a falling edge.
                @(negedge vif.clk);
                vif.rst_n = 1'b1;
            end
        join

        cache_read(32'h1000, r_data);
        cache_read(32'h1004, r_data);
        cache_read(32'h1008, r_data);
        cache_read(32'h100C, r_data);

        // Reset while idle, then require a fresh refill of the retained line.
        @(negedge vif.clk);
        vif.rst_n = 1'b0;
        repeat (2)
            @(posedge vif.clk);
        @(negedge vif.clk);
        vif.rst_n = 1'b1;

        cache_read(32'h1000, r_data);
    endtask
endclass
