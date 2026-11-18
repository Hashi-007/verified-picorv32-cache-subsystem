`uvm_analysis_imp_decl(_ram)

class cache_scoreboard extends uvm_scoreboard;

    logic [7:0]  expected_mem [0:65535];
    logic [7:0]  expected_ram [0:65535];

    uvm_analysis_imp #(cache_item, cache_scoreboard) cpu_imp;
    uvm_analysis_imp_ram #(cache_item, cache_scoreboard) ram_imp;

    `uvm_component_utils(cache_scoreboard)

    virtual cache_if vif;

    function new(string name = "cache_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        cpu_imp = new("cpu_imp", this);
        ram_imp = new("ram_imp", this);

        for (int unsigned i = 0; i < 16384; i++) begin
            expected_mem[4 * i]     = i[7:0];
            expected_mem[4 * i + 1] = i[15:8];
            expected_mem[4 * i + 2] = i[23:16];
            expected_mem[4 * i + 3] = i[31:24];
        end
        expected_ram = expected_mem;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "cache_scoreboard: virtual interface not set")
        end
    endfunction

    function void write(cache_item tr);
        int unsigned byte_index;
        logic [31:0] expected_data;

        if (!tr.fields_valid()) begin
            `uvm_error("CPU_FIELDS", "Invalid CPU address, strobe or transferred data")
            return;
        end
        byte_index = (tr.addr - 32'h1000);

        if (tr.wstrb == '0) begin
            for (int i = 0; i < 4; i++) begin
                expected_data[8 * i +: 8] = expected_mem[byte_index + i];
            end
            if (expected_data !== tr.rdata) begin
                `uvm_error("DATA_MISMATCH",
                    $sformatf("addr=%08h expected=%08h actual=%08h",
                              tr.addr, expected_data, tr.rdata))
            end
        end else begin
            for (int i = 0; i < 4; i++) begin
                if (tr.wstrb[i])
                    expected_mem[byte_index + i] = tr.wdata[8 * i +: 8];
            end
        end
    endfunction

    function void write_ram(cache_item tr);
        logic [31:0] expected_data;
        int unsigned byte_index;
        if (!tr.fields_valid(1)) begin
            `uvm_error("RAM_FIELDS", "Invalid RAM address, strobe or transferred data")
            return;
        end
        byte_index = (tr.addr - 32'h1000);

        if (tr.wstrb == '0) begin
            for (int i = 0; i < 4; i++) begin
                expected_data[8 * i +: 8] = expected_ram[byte_index + i];
            end
            if (expected_data !== tr.rdata) begin
                `uvm_error("RAM_READ_DATA",
                    $sformatf("addr=%08h expected=%08h actual=%08h",
                              tr.addr, expected_data, tr.rdata))
            end
        end else begin
            for (int i = 0; i < 4; i++) begin
                if (tr.wstrb[i]) begin
                    if (tr.wdata[8 * i +: 8] !== expected_mem[byte_index + i])
                        `uvm_error("RAM_WRITE_DATA", $sformatf(
                            "addr=%08h byte=%0d expected=%02h actual=%02h",
                            tr.addr, i, expected_mem[byte_index + i], tr.wdata[8 * i +: 8]))

                    expected_ram[byte_index + i] = expected_mem[byte_index + i];
                end
            end
        end
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n)
                expected_mem = expected_ram;
        end
    endtask
endclass
