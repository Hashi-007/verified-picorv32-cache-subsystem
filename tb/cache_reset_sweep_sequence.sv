class cache_reset_sweep_sequence extends cache_base_sequence;
    `uvm_object_utils(cache_reset_sweep_sequence)
    virtual cache_if vif;
    function new(string name = "cache_reset_sweep_sequence");
        super.new(name);
    endfunction

    task pulse_reset();
        @(negedge vif.clk);
        vif.rst_n = 0;
        repeat (2)
            @(posedge vif.clk);
        @(negedge vif.clk);
        vif.rst_n = 1;
    endtask

    task interrupt_phase(bit writeback, int unsigned completed_words);
        logic [31:0] data;
        fork
            cache_read(writeback ? 32'h2000 : 32'h1000, data);
            begin
                // The first request edge precedes any allowed RAM completion.
                do @(posedge vif.clk);
                while (!(vif.mem_valid && (vif.mem_wstrb == (writeback ? 4'hF : 4'h0))));
                repeat (completed_words) begin
                    do @(posedge vif.clk);
                    while (!(vif.mem_valid && vif.mem_ready));
                end
                pulse_reset();
            end
        join
    endtask

    task body();
        logic [31:0] data;
        wait (vif.rst_n);
        for (int progress = 0; progress <= 4; progress++) begin
            pulse_reset(); // Begin with invalid lines; also covers idle reset.
            interrupt_phase(0, progress);
            cache_read(32'h1000, data); // Canceled refill cannot supply a stale response.

            for (int word_offset = 0; word_offset < 4; word_offset++)
                cache_write(32'h1000 + 4 * word_offset,
                            32'hCAFE0000 + 16 * progress + word_offset, 4'hF);
            interrupt_phase(1, progress);
            // Data oracle expects exactly the completed writeback prefix in RAM.
            for (int word_offset = 0; word_offset < 4; word_offset++)
                cache_read(32'h1000 + 4 * word_offset, data);
        end
    endtask
endclass
