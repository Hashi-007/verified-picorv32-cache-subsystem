class cache_monitor extends uvm_monitor;
    `uvm_component_utils(cache_monitor)

    virtual cache_if vif;
    uvm_analysis_port #(cache_item) ap;

    function new(string name = "cache_monitor",
                 uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "cache_monitor: virtual interface not set")
        end
    endfunction

    task run_phase(uvm_phase phase);
        cache_item tr;

        forever begin
            @(posedge vif.clk);
            if (vif.rst_n && vif.cpu_valid && vif.cpu_ready) begin
                tr       = cache_item::type_id::create("tr");
                tr.addr  = vif.cpu_addr;
                tr.wdata = vif.cpu_wdata;
                tr.rdata = vif.cpu_rdata;
                tr.wstrb = vif.cpu_wstrb;

                ap.write(tr);
            end
        end
    endtask
endclass
