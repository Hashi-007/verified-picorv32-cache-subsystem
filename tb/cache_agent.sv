class cache_agent extends uvm_agent;

    uvm_sequencer #(cache_item) sqr;
    cache_driver                 drv;
    cache_monitor                c_mon;

    `uvm_component_utils(cache_agent)

    function new(string name = "cache_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        sqr   = uvm_sequencer #(cache_item)::type_id::create("sqr", this);
        drv   = cache_driver::type_id::create("drv", this);
        c_mon = cache_monitor::type_id::create("c_mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
