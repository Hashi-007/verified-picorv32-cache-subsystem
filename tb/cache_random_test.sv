class cache_random_test extends cache_test;
    `uvm_component_utils(cache_random_test)

    function new(string name = "cache_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        cache_random_sequence seq;
        phase.raise_objection(this);
        if (!$test$plusargs("RAM_RANDOM") || !$test$plusargs("CPU_STREAM"))
            `uvm_fatal("RANDOM_MODE", "Random test requires +RAM_RANDOM +CPU_STREAM")
        seq = cache_random_sequence::type_id::create("seq");
        seq.start(env.agent.sqr);
        phase.drop_objection(this);
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env.ram_checker.cpu_count != 1000 || env.agent.drv.stream_replacements != 999)
            `uvm_error("RANDOM_COUNT", "Expected 1000 CPU completions without driver gaps")
    endfunction
endclass
