class ram_monitor extends uvm_monitor;
    `uvm_component_utils(ram_monitor)

    virtual cache_if vif;
    uvm_analysis_port #(cache_item) ap;

    function new(string name = "ram_monitor",
                 uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ram_monitor: virtual interface not set")
        end
    endfunction

    task run_phase(uvm_phase phase);
        cache_item tr;

        forever begin
            @(posedge vif.clk);
            if (vif.rst_n && vif.mem_valid && vif.mem_ready) begin
                tr       = cache_item::type_id::create("tr");
                tr.addr  = vif.mem_addr;
                tr.wdata = vif.mem_wdata;
                tr.rdata = vif.mem_rdata;
                tr.wstrb = vif.mem_wstrb;

                ap.write(tr);
            end
        end
    endtask
endclass
