module cache_stall_checks(cache_if vif, input logic [1:0] word_counter);
    int unsigned expected_wait = 1;
    int unsigned elapsed_cycles;
    bit tracking;
    logic [31:0] request_addr;
    logic [3:0]  request_wstrb;
    bit random_wait;
    bit seen_up, reset_seen, phase_active, phase_write;
    int unsigned phase_words, continuous_requests;
    bit completed_last_edge;

    covergroup ram_coverage with function sample(bit write_op, int unsigned offset,
                                                int unsigned latency);
        option.per_instance = 1;
        cp_direction: coverpoint write_op {
            bins read_op = {0};
            bins write_op = {1};
        }
        cp_word: coverpoint offset {
            bins words[] = {[0:3]};
        }
        cp_wait: coverpoint latency {
            bins delays[] = {[1:8]};
        }
        transfer_cross: cross cp_direction, cp_word, cp_wait;
    endgroup
    covergroup reset_coverage with function sample(int unsigned reset_phase,
                                                  int unsigned progress);
        option.per_instance = 1;
        cp_phase: coverpoint reset_phase {
            bins idle = {0};
            bins refill = {1};
            bins writeback = {2};
        }
        cp_progress: coverpoint progress iff (reset_phase != 0) {
            bins completed_words[] = {[0:4]};
        }
        phase_progress: cross cp_phase, cp_progress {
            ignore_bins idle_progress = binsof(cp_phase.idle);
        }
    endgroup
    ram_coverage ram_cov = new();
    reset_coverage reset_cov = new();

    initial begin
        if (!$value$plusargs("RAM_WAIT=%d", expected_wait))
            expected_wait = 1;
        random_wait = $test$plusargs("RAM_RANDOM");
    end

    // Check sampled fields through the edge on which the transfer completes.
    a_ram_stable: assert property (
        @(posedge vif.clk) disable iff (!vif.rst_n)
        (vif.mem_valid && !vif.mem_ready) |=>
        (vif.mem_valid && $stable({vif.mem_addr, vif.mem_wdata, vif.mem_wstrb}))
    ) else $error("RAM_STABILITY: request changed while waiting for ready");

    a_counter_stable: assert property (
        @(posedge vif.clk) disable iff (!vif.rst_n)
        (vif.mem_valid && !vif.mem_ready) |=> $stable(word_counter)
    ) else $error("WORD_COUNTER_STABILITY: counter advanced without a handshake");

    a_cpu_stable: assert property (
        @(posedge vif.clk) disable iff (!vif.rst_n)
        (vif.cpu_valid && !vif.cpu_ready) |=>
        (vif.cpu_valid && $stable({vif.cpu_addr, vif.cpu_wdata, vif.cpu_wstrb}))
    ) else $error("CPU_STABILITY: request changed before completion");

    a_known_control: assert property (
        @(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.cpu_valid, vif.cpu_ready, vif.mem_valid, vif.mem_ready})
    ) else $error("CONTROL_X: unknown valid/ready signal");

    a_cpu_completion: assert property (
        @(posedge vif.clk) disable iff (!vif.rst_n)
        vif.cpu_ready |-> vif.cpu_valid
    ) else $error("CPU_COMPLETION: ready without a CPU request");

    a_reset_outputs: assert property (
        @(posedge vif.clk) !vif.rst_n |-> (!vif.cpu_ready && !vif.mem_valid)
    ) else $error("RESET_OUTPUTS: cache request/completion active in reset");

    // Classify reset using externally observed RAM requests and completions.
    // Progress four covers reset after the last RAM beat, before CPU completion.
    always @(posedge vif.clk) begin
        if (!vif.rst_n) begin
            if (seen_up && !reset_seen) begin
                reset_cov.sample(phase_active ? (phase_write ? 2 : 1) : 0, phase_words);
                $display("RESET_COV_OBS phase=%0d progress=%0d",
                    phase_active ? (phase_write ? 2 : 1) : 0, phase_words);
            end
            reset_seen          = 1;
            phase_active        = 0;
            phase_words         = 0;
            completed_last_edge = 0;
        end else begin
            seen_up    = 1;
            reset_seen = 0;
            if (completed_last_edge && vif.cpu_valid) begin
                continuous_requests++;
                $display("CPU_CONTINUOUS_OBS count=%0d", continuous_requests);
            end
            completed_last_edge = vif.cpu_valid && vif.cpu_ready;
            if (vif.mem_valid) begin
                if (!phase_active || phase_write != (vif.mem_wstrb != 0)) begin
                    phase_active = 1;
                    phase_write  = vif.mem_wstrb != 0;
                    phase_words  = 0;
                end
                if (vif.mem_ready)
                    phase_words++;
            end
            if (vif.cpu_valid && vif.cpu_ready) begin
                phase_active = 0;
                phase_words  = 0;
            end
        end
    end

    // Measure actual request-to-completion latency independently of the RAM timer.
    always @(posedge vif.clk) begin
        if (!vif.rst_n) begin
            tracking       = 1'b0;
            elapsed_cycles = 0;
        end else if (!tracking) begin
            if (vif.mem_valid) begin
                if (vif.mem_ready) begin
                    $error("RAM_LATENCY: transfer completed without an earlier request edge");
                end else begin
                    tracking       = 1'b1;
                    elapsed_cycles = 0;
                    request_addr   = vif.mem_addr;
                    request_wstrb  = vif.mem_wstrb;
                end
            end
        end else begin
            elapsed_cycles++;
            if (vif.mem_valid && vif.mem_ready) begin
                if ((!random_wait && elapsed_cycles != expected_wait) ||
                    (random_wait && !(elapsed_cycles inside {[1:8]})))
                    $error("RAM_LATENCY: addr=%08h expected=%0d observed=%0d",
                           request_addr, expected_wait, elapsed_cycles);
                $display("RAM_WAIT_OBS addr=%08h strb=%h cycles=%0d",
                         request_addr, request_wstrb, elapsed_cycles);
                ram_cov.sample(request_wstrb != 0, request_addr[3:2], elapsed_cycles);
                tracking = 1'b0;
            end
        end
    end

    final begin
        $display("PORT_COVERAGE ram=%0.2f reset=%0.2f continuous=%0d",
                 ram_cov.get_inst_coverage(), reset_cov.get_inst_coverage(), continuous_requests);
    end
endmodule
