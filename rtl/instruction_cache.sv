// Read-only instruction cache: 4 KiB, direct mapped, 16-byte lines.
// The CPU holds instr_valid and instr_addr until instr_ready completes a fetch.
// mem_* connects to the wrapper's ic_mem_* wires; all RAM accesses are reads.
// Program memory stays unchanged while the CPU runs in this first version.
module instruction_cache (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        instr_valid,
    input  logic [31:0] instr_addr,
    output logic        instr_ready,
    output logic [31:0] instr_rdata,

    output logic        mem_valid,
    output logic [31:0] mem_addr,
    input  logic        mem_ready,
    input  logic [31:0] mem_rdata
);

    logic [31:0] data_mem  [0:255][0:3];
    logic [19:0] tag_mem   [0:255];
    logic        valid_mem [0:255];
    logic [1:0]  word_counter;

    logic [19:0] tag;
    logic [7:0]  index;
    logic [1:0]  word;
    logic        hit;

    assign tag   = instr_addr[31:12];
    assign index = instr_addr[11:4];
    assign word  = instr_addr[3:2];
    assign hit   = valid_mem[index] && (tag_mem[index] == tag);

    typedef enum logic [1:0] {
        IDLE,
        LOOKUP,
        ALLOCATE
    } state_t;
    state_t state, next_state;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state        <= IDLE;
            word_counter <= 2'd0;
            for (int i = 0; i < 256; i++)
                valid_mem[i] <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                LOOKUP: begin
                    if (instr_valid && !hit) begin
                        // Start refill at word 0 and invalidate this line.
                        valid_mem[index] <= 1'b0;
                        word_counter     <= '0;
                    end
                end
                ALLOCATE: begin
                    if (mem_valid && mem_ready) begin
                        // Commit the tag/valid bit only after all four words arrive.
                        data_mem[index][word_counter] <= mem_rdata;
                        if (word_counter == 4'd3) begin
                            word_counter     <= '0;
                            tag_mem[index]   <= tag;
                            valid_mem[index] <= 1'b1;
                        end else
                            word_counter <= word_counter + 1;
                    end
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                // A valid instruction request moves us to LOOKUP.
                if (instr_valid) begin
                    next_state = LOOKUP;
                end
            end
            LOOKUP: begin
                // A hit returns to IDLE; a miss enters ALLOCATE.
                // The requester holds valid/address until completion.
                if (hit) begin
                    next_state = IDLE;
                end else
                    next_state = ALLOCATE;
            end
            ALLOCATE: begin
                // The fourth RAM handshake returns us to LOOKUP.
                if (mem_ready && mem_valid && (word_counter == 3)) begin
                    next_state = LOOKUP;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always_comb begin
        instr_ready = 1'b0;
        instr_rdata = '0;
        mem_valid   = 1'b0;
        mem_addr    = '0;

        if (rst_n) begin
            case (state)
                LOOKUP: begin
                    // On a valid hit, assert ready and return the
                    // word selected by the CPU's original instruction address.
                    if (instr_valid && hit) begin
                        instr_rdata = data_mem[index][word];
                        instr_ready = 1'b1;
                    end
                end
                ALLOCATE: begin
                    // Assert mem_valid and form the refill address
                    // from tag, index, word_counter, and two zero bits.
                    mem_valid = 1'b1;
                    mem_addr  = {{tag}, {index}, {word_counter}, {2'b00}};
                end
                default: ;
            endcase
        end
    end
endmodule
