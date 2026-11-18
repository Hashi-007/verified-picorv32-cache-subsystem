class cache_wait_test extends cache_test;
    `uvm_component_utils(cache_wait_test)

    function new(string name = "cache_wait_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        cache_wait_sequence seq;

        phase.raise_objection(this);
        seq = cache_wait_sequence::type_id::create("seq");
        seq.start(env.agent.sqr);
        phase.drop_objection(this);
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env.ram_checker.cpu_count != 8 || env.ram_checker.hits != 3 ||
            env.ram_checker.misses != 5 || env.ram_checker.ram_reads != 20 ||
            env.ram_checker.ram_writes != 12)
            `uvm_error("WAIT_COUNTS", $sformatf(
                "Expected cpu/hits/misses/reads/writes=8/3/5/20/12; got %0d/%0d/%0d/%0d/%0d",
                env.ram_checker.cpu_count, env.ram_checker.hits,
                env.ram_checker.misses, env.ram_checker.ram_reads,
                env.ram_checker.ram_writes))
    endfunction
endclass
