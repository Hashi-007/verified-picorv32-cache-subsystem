class cache_env extends uvm_env;

    cache_agent       agent;
    ram_monitor       r_mon;
    cache_scoreboard  sb;
    cache_ram_checker ram_checker;

    `uvm_component_utils(cache_env)

    function new(string name = "cache_env", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent       = cache_agent::type_id::create("agent", this);
        r_mon       = ram_monitor::type_id::create("r_mon", this);
        sb          = cache_scoreboard::type_id::create("sb", this);
        ram_checker = cache_ram_checker::type_id::create("ram_checker", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        agent.c_mon.ap.connect(sb.cpu_imp);
        agent.c_mon.ap.connect(ram_checker.cpu_imp);
        r_mon.ap.connect(ram_checker.ram_imp);
        r_mon.ap.connect(sb.ram_imp);
    endfunction
endclass
