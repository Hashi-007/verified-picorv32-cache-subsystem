`uvm_analysis_imp_decl(_policy_cpu)
`uvm_analysis_imp_decl(_policy_ram)

// Policy model for serial CPU requests, cleared on every sampled reset.
// Architectural data remains checked independently by cache_scoreboard.
class cache_ram_checker extends uvm_scoreboard;
    `uvm_component_utils(cache_ram_checker)

    virtual cache_if vif;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "cache_ram_checker: virtual interface not set")
        end
    endfunction

    uvm_analysis_imp_policy_cpu #(cache_item, cache_ram_checker) cpu_imp;
    uvm_analysis_imp_policy_ram #(cache_item, cache_ram_checker) ram_imp;

    typedef struct packed {
        logic [31:0] addr;
        logic [3:0]  wstrb;
    } ram_transfer_t;
    ram_transfer_t pending_ram[$];

    logic [31:0] resident_line [0:255];
    bit resident_valid [0:255];
    bit resident_dirty [0:255];

    int unsigned cpu_count, hits, misses, ram_reads, ram_writes;
    bit previous_valid;
    int unsigned previous_class;

    covergroup cpu_coverage with function sample(
        bit store, bit hit, int unsigned slot, int unsigned word_offset,
        int unsigned mask, int unsigned victim);
        option.per_instance = 1;
        cp_kind: coverpoint store {
            bins read_op = {0};
            bins store_op = {1};
        }
        cp_hit: coverpoint hit {
            bins miss = {0};
            bins hit = {1};
        }
        cp_index: coverpoint slot {
            bins indices[] = {[0:255]};
        }
        cp_word: coverpoint word_offset {
            bins offsets[] = {[0:3]};
        }
        cp_mask: coverpoint mask iff (store) {
            bins masks[] = {[1:15]};
        }
        cp_victim: coverpoint victim iff (!hit) {
            bins invalid_line = {0};
            bins clean_line = {1};
            bins dirty_line = {2};
        }
        kind_hit: cross cp_kind, cp_hit;
        mask_hit: cross cp_mask, cp_hit;
        kind_victim: cross cp_kind, cp_victim;
    endgroup

    covergroup transition_coverage with function sample(int unsigned previous,
                                                       int unsigned current);
        option.per_instance = 1;
        cp_previous: coverpoint previous {
            bins classes[] = {[0:3]};
        }
        cp_current: coverpoint current {
            bins classes[] = {[0:3]};
        }
        request_pairs: cross cp_previous, cp_current;
    endgroup

    function new(string name = "cache_ram_checker", uvm_component parent = null);
        super.new(name, parent);
        cpu_imp             = new("cpu_imp", this);
        ram_imp             = new("ram_imp", this);
        cpu_coverage        = new();
        transition_coverage = new();
    endfunction

    function void reset_model();
        // An aborted miss still has to obey the ordered writeback/refill prefix.
        // CPU fields remain stable until reset cancels that request.
        check_aborted_prefix();
        pending_ram.delete();
        previous_valid = 0;
        for (int i = 0; i < 256; i++) begin
            resident_valid[i] = 1'b0;
            resident_dirty[i] = 1'b0;
            resident_line[i]  = '0;
        end
    endfunction

    function void check_aborted_prefix();
        int unsigned slot, maximum_words;
        bit dirty_victim;
        logic [31:0] line_base;
        if (pending_ram.size() == 0)
            return;
        if ($isunknown(vif.cpu_addr) || vif.cpu_addr[1:0] != 0 ||
            vif.cpu_addr < 32'h1000 || vif.cpu_addr > 32'h10FFC) begin
            `uvm_error("RESET_PREFIX_FIELDS", "Aborted request has an invalid address")
            return;
        end
        slot          = vif.cpu_addr[11:4];
        line_base     = {vif.cpu_addr[31:4], 4'b0};
        dirty_victim  = resident_valid[slot] && resident_dirty[slot];
        maximum_words = dirty_victim ? 8 : 4;
        if (pending_ram.size() > maximum_words)
            `uvm_error("RESET_PREFIX_COUNT", "Too many RAM words before reset cancellation")
        for (int unsigned i = 0; i < pending_ram.size(); i++) begin
            if (dirty_victim && i < 4)
                check_word(i, resident_line[slot] + 4 * i, 4'hF);
            else
                check_word(i, line_base + 4 * (i - (dirty_victim ? 4 : 0)), 4'h0);
        end
    endfunction

    virtual function void write_policy_ram(cache_item tr);
        ram_transfer_t transfer;
        if (!tr.fields_valid(1)) begin
            `uvm_error("POLICY_RAM_FIELDS", "Invalid observed RAM transfer")
            return;
        end
        transfer.addr  = tr.addr;
        transfer.wstrb = tr.wstrb;
        pending_ram.push_back(transfer);
        if (tr.wstrb === 4'b0000)
            ram_reads++;
        else ram_writes++;
    endfunction

    function void check_word(int unsigned position,
                            logic [31:0] expected_addr,
                            logic [3:0]  expected_wstrb);
        if (position >= pending_ram.size())
            return;
        if (pending_ram[position].addr !== expected_addr ||
            pending_ram[position].wstrb !== expected_wstrb)
            `uvm_error("RAM_WORD", $sformatf(
                "word=%0d expected addr=%08h strb=%h; actual addr=%08h strb=%h",
                position, expected_addr, expected_wstrb,
                pending_ram[position].addr, pending_ram[position].wstrb))
    endfunction

    virtual function void write_policy_cpu(cache_item tr);
        int unsigned slot, expected_count, refill_start;
        logic [31:0] line_base;
        bit is_hit, dirty_victim;

        cpu_count++;
        if (!tr.fields_valid()) begin
            `uvm_error("CPU_FIELDS", "Policy checker received an invalid CPU request")
            return;
        end

        slot           = tr.addr[11:4];
        line_base      = {tr.addr[31:4], 4'b0000};
        is_hit         = resident_valid[slot] && resident_line[slot] == line_base;
        dirty_victim   = resident_valid[slot] && resident_dirty[slot];
        expected_count = is_hit ? 0 : (dirty_victim ? 8 : 4);
        cpu_coverage.sample(tr.wstrb != 0, is_hit, slot, tr.addr[3:2],
                            tr.wstrb, !resident_valid[slot] ? 0 : (dirty_victim ? 2 : 1));
        if (previous_valid)
            transition_coverage.sample(previous_class, 2 * (tr.wstrb != 0) + is_hit);
        previous_class = 2 * (tr.wstrb != 0) + is_hit;
        previous_valid = 1;
        `uvm_info("CPU_COV_OBS", $sformatf(
            "addr=%08h strb=%h hit=%0d victim=%0d", tr.addr, tr.wstrb, is_hit,
            !resident_valid[slot] ? 0 : (dirty_victim ? 2 : 1)), UVM_LOW)

        if (pending_ram.size() != expected_count)
            `uvm_error("RAM_COUNT", $sformatf(
                "CPU addr=%08h predicted %s: expected %0d RAM words, observed %0d",
                tr.addr, is_hit ? "hit" : "miss", expected_count, pending_ram.size()))

        if (is_hit) begin
            hits++;
        end else begin
            misses++;
            refill_start = dirty_victim ? 4 : 0;
            if (dirty_victim)
                for (int unsigned i = 0; i < 4; i++)
                    check_word(i, resident_line[slot] + 4 * i, 4'b1111);
            for (int unsigned i = 0; i < 4; i++)
                check_word(refill_start + i, line_base + 4 * i, 4'b0000);

            resident_line[slot]  = line_base;
            resident_valid[slot] = 1'b1;
            resident_dirty[slot] = 1'b0;
        end
        if (tr.wstrb != 4'b0000)
            resident_dirty[slot] = 1'b1;
        pending_ram.delete();
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n) begin
                reset_model();
            end
        end
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (pending_ram.size() != 0)
            `uvm_error("RAM_PENDING", $sformatf(
                "%0d RAM transfers have no completed CPU request", pending_ram.size()))
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("CACHE_POLICY", $sformatf(
            "cpu=%0d hits=%0d misses=%0d ram_reads=%0d ram_writes=%0d",
            cpu_count, hits, misses, ram_reads, ram_writes), UVM_LOW)
        `uvm_info("CPU_COVERAGE", $sformatf("cpu=%0.2f transitions=%0.2f",
            cpu_coverage.get_inst_coverage(), transition_coverage.get_inst_coverage()), UVM_LOW)
    endfunction
endclass
