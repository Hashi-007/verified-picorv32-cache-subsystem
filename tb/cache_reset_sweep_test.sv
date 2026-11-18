class cache_reset_sweep_test extends cache_test;
    `uvm_component_utils(cache_reset_sweep_test)

    function new(string name = "cache_reset_sweep_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        cache_reset_sweep_sequence seq;
        phase.raise_objection(this);
        seq     = cache_reset_sweep_sequence::type_id::create("seq");
        seq.vif = env.agent.drv.vif;
        seq.start(env.agent.sqr);
        phase.drop_objection(this);
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env.ram_checker.cpu_count != 45 || env.ram_checker.ram_reads != 50 ||
            env.ram_checker.ram_writes != 10)
            `uvm_error("RESET_SWEEP_COUNT", $sformatf(
                "Expected CPU/RAM reads/writes=45/50/10, got %0d/%0d/%0d",
                env.ram_checker.cpu_count, env.ram_checker.ram_reads, env.ram_checker.ram_writes))
    endfunction
endclass
