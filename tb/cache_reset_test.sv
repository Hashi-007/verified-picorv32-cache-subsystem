class cache_reset_test extends cache_test;
    `uvm_component_utils(cache_reset_test)

    function new(string name = "cache_reset_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        cache_reset_sequence seq;

        phase.raise_objection(this);
        seq     = cache_reset_sequence::type_id::create("seq");
        seq.vif = env.agent.drv.vif;
        seq.start(env.agent.sqr);
        phase.drop_objection(this);
    endtask
endclass
