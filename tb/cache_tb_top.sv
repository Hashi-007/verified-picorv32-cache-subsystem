module cache_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    import uvm_pkg::*;
    import cache_pkg::*;

    logic        clk = 1'b0;

    // A delay is required so the clock advances simulation time.
    always #5ns clk = ~clk;

    cache_if vif(.clk(clk));

    ram_model ram(.vif(vif));

    data_cache dut (
        .clk   (clk),
        .rst_n (vif.rst_n),

        .cpu_valid (vif.cpu_valid),
        .cpu_addr  (vif.cpu_addr),
        .cpu_wdata (vif.cpu_wdata),
        .cpu_wstrb (vif.cpu_wstrb),
        .cpu_ready (vif.cpu_ready),
        .cpu_rdata (vif.cpu_rdata),

        .mem_valid (vif.mem_valid),
        .mem_addr  (vif.mem_addr),
        .mem_wdata (vif.mem_wdata),
        .mem_wstrb (vif.mem_wstrb),
        .mem_ready (vif.mem_ready),
        .mem_rdata (vif.mem_rdata)
    );

    cache_stall_checks stall_checks(.vif(vif), .word_counter(dut.word_counter));

    initial begin
        vif.rst_n = 1'b0;

        repeat (2)
            @(posedge clk);
        @(negedge clk);
        vif.rst_n = 1'b1;
    end

    initial begin
        // A stuck sequence must fail even if it is waiting outside the driver.
        #2ms;
        $fatal(1, "TEST_TIMEOUT: standalone test exceeded 2 ms");
    end

    initial begin
        uvm_config_db#(virtual cache_if)::set(
            null, "uvm_test_top.env.*", "vif", vif
        );
        run_test("cache_test");
    end
endmodule
