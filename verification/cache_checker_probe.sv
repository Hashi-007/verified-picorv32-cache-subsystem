// Isolated negative probe, not a DUT test. Exactly 20 UVM errors are intentional.
// Compile after cache_pkg, simulate cache_checker_probe, and check the PASS marker.
module cache_checker_probe;
    import uvm_pkg::*;
    import cache_pkg::*;
    // Questa resolves all package virtual-interface types at elaboration,
    // including unused class tasks; provide a matching static interface.
    cache_if vif(.clk(1'b0));
    initial begin
        cache_scoreboard sb;
        cache_item tr;
        uvm_report_server server;
        sb = new("probe", null);
        tr = new("tr");
        for (int trial = 0; trial < 8; trial++) begin
            tr.addr  = 32'h1000;
            tr.wstrb = 4'hF;
            tr.wdata = 32'hAABBCCDD;
            tr.rdata = 0;
            case (trial)
                0: tr.addr = 32'hFFC;
                1: tr.addr = 32'h11000;
                2: tr.addr = 32'h1001;
                3: tr.addr = 'x;
                4: tr.wstrb = 'x;
                5: tr.wdata = 'x;
                6: begin
                    tr.wstrb = 0;
                    tr.rdata = 'x;
                end
                7: tr.addr = 32'hFFFFFFFC;
            endcase
            sb.write(tr);
            sb.write_ram(tr);
        end
        // Partial RAM strobes are illegal; the standalone CPU supports them.
        tr.addr  = 32'h1000;
        tr.wstrb = 1;
        tr.wdata = 1;
        sb.write_ram(tr);
        // Prove both read oracles and the writeback-data oracle can detect a fault.
        tr.wstrb = 0;
        tr.rdata = 1;
        sb.write(tr);
        sb.write_ram(tr);
        tr.wstrb = 4'hF;
        tr.wdata = 1;
        sb.write_ram(tr);
        // A corrupt observed write must not contaminate either golden image.
        if (sb.expected_mem[0] !== 0 || sb.expected_ram[0] !== 0)
            $fatal(1, "Probe contaminated the golden image");
        server = uvm_report_server::get_server();
        if (server.get_severity_count(UVM_ERROR) != 20 ||
            server.get_severity_count(UVM_FATAL) != 0 ||
            server.get_id_count("CPU_FIELDS") != 8 ||
            server.get_id_count("RAM_FIELDS") != 9 ||
            server.get_id_count("DATA_MISMATCH") != 1 ||
            server.get_id_count("RAM_READ_DATA") != 1 ||
            server.get_id_count("RAM_WRITE_DATA") != 1)
            $fatal(1, "Unexpected negative-probe error count or category");
        $display("CHECKER_NEGATIVE_PASS: 20 expected errors; golden images unchanged");
        $finish;
    end
endmodule
