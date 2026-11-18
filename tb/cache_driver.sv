class cache_driver extends uvm_driver #(cache_item);
    `uvm_component_utils(cache_driver)

    virtual cache_if vif;
    bit stream_mode;
    int unsigned stream_replacements;

    function new(string name = "cache_driver",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "cache_driver: virtual interface not set")
        end
    endfunction

    task run_phase(uvm_phase phase);
        cache_item tr;

        stream_mode   = $test$plusargs("CPU_STREAM");
        vif.cpu_valid = 1'b0;

        wait (vif.rst_n);

        forever begin
            if (tr == null) begin
                seq_item_port.get_next_item(tr);
                do @(negedge vif.clk);
                while (!vif.rst_n);
            end

            vif.cpu_addr  = tr.addr;
            vif.cpu_wstrb = tr.wstrb;
            vif.cpu_wdata = tr.wdata;
            vif.cpu_valid = 1'b1;

            for (int unsigned cycles = 0; cycles < 100; cycles++) begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    break;
                end else begin
                    if ((vif.cpu_valid === 1'b1) && (vif.cpu_ready === 1'b1)) begin
                        if (tr.wstrb == '0)
                            tr.rdata = vif.cpu_rdata;
                        break;
                    end

                    if (cycles == 99)
                        `uvm_fatal("TIMEOUT", $sformatf(
                            "CPU request at 0x%08h did not complete within 100 cycles",
                            tr.addr))
                end
            end

            // Release the sequence at completion so its next item can be ready
            // for the immediately following falling edge. Default mode retains
            // the standard driver's idle spacing.
            if (stream_mode)
                seq_item_port.item_done();
            @(negedge vif.clk);
            vif.cpu_valid = 1'b0;
            if (!stream_mode)
                seq_item_port.item_done();
            tr = null;
            if (stream_mode && vif.rst_n) begin
                seq_item_port.try_next_item(tr);
                if (tr != null)
                    stream_replacements++;
            end
        end
    endtask
endclass
