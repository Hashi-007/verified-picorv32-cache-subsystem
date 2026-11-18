class cache_test extends uvm_test;
    `uvm_component_utils(cache_test)

    cache_env env;

    function new(string name = "cache_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = cache_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        cache_sequence seq;

        phase.raise_objection(this);
        seq = cache_sequence::type_id::create("seq");
        seq.start(env.agent.sqr);
        phase.drop_objection(this);
    endtask
endclass
