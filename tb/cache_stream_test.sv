class cache_stream_test extends cache_test;
    `uvm_component_utils(cache_stream_test)

    function new(string name = "cache_stream_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        cache_stream_sequence seq;
        phase.raise_objection(this);
        if (!$test$plusargs("CPU_STREAM"))
            `uvm_fatal("STREAM_MODE", "cache_stream_test requires +CPU_STREAM")
        seq = cache_stream_sequence::type_id::create("seq");
        seq.start(env.agent.sqr);
        phase.drop_objection(this);
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env.ram_checker.cpu_count != 301 || env.agent.drv.stream_replacements != 300)
            `uvm_error("STREAM_COUNT", $sformatf(
                "Expected 301 completions and 300 immediate replacements; got %0d/%0d",
                env.ram_checker.cpu_count, env.agent.drv.stream_replacements))
    endfunction
endclass
