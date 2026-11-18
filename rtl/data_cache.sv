module data_cache (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        cpu_valid,
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    input  logic [3:0]  cpu_wstrb,
    output logic        cpu_ready,
    output logic [31:0] cpu_rdata,

    output logic        mem_valid,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    output logic [3:0]  mem_wstrb,
    input  logic        mem_ready,
    input  logic [31:0] mem_rdata
);

    logic [19:0] tag;
    logic [7:0]  index;
    logic [1:0]  word;
    logic [1:0]  byte_offset;

    assign tag         = cpu_addr[31:12];
    assign index       = cpu_addr[11:4];
    assign word        = cpu_addr[3:2];
    assign byte_offset = cpu_addr[1:0];

    logic [1:0]  word_counter;

    logic [31:0] data_mem  [255:0][3:0];
    logic [19:0] tag_mem   [255:0];
    logic        valid_mem [255:0];
    logic        dirty_mem [255:0];

    typedef enum logic [1:0] {
        IDLE,
        LOOKUP,
        WRITEBACK,
        ALLOCATE
    } state_t;

    state_t state, next_state;

    logic        hit;

    assign hit = ((tag == tag_mem[index]) && (valid_mem[index]));

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 256; i++) begin
                valid_mem[i] <= 1'b0;
                dirty_mem[i] <= 1'b0;
            end

            word_counter <= '0;
            state        <= IDLE;
        end else begin
            state <= next_state;
            if (state != ALLOCATE && next_state == ALLOCATE)
                valid_mem[index] <= 1'b0;

            case (state)
                LOOKUP: begin
                    if (!hit) begin
                        word_counter <= 2'b00;
                    end

                    if (cpu_valid && hit && (cpu_wstrb != 4'b0000)) begin
                        for (int i = 0; i < 4; i++) begin
                            if (cpu_wstrb[i])
                                data_mem[index][word][8 * i +: 8] <= cpu_wdata[8 * i +: 8];
                        end
                        dirty_mem[index] <= 1'b1;
                    end
                end
                WRITEBACK: begin
                    if (mem_valid && mem_ready) begin
                        if (word_counter == 2'b11) begin
                            word_counter <= 2'b00;
                        end else begin
                            word_counter <= word_counter + 1;
                        end
                    end
                end
                ALLOCATE: begin
                    if (mem_valid && mem_ready) begin
                        data_mem[index][word_counter] <= mem_rdata;
                        if (word_counter == 2'b11) begin
                            word_counter     <= 2'b00;
                            tag_mem[index]   <= tag;
                            valid_mem[index] <= 1'b1;
                            dirty_mem[index] <= 1'b0;
                        end else begin
                            word_counter <= word_counter + 1;
                        end
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
                if (cpu_valid) begin
                    next_state = LOOKUP;
                end
            end
            LOOKUP: begin
                if (hit) begin
                    next_state = IDLE;
                end else if (valid_mem[index] && dirty_mem[index]) begin
                    next_state = WRITEBACK;
                end else
                    next_state = ALLOCATE;
            end
            WRITEBACK: begin
                if (mem_valid && mem_ready && word_counter == 2'd3) begin
                    next_state = ALLOCATE;
                end
            end
            ALLOCATE: begin
                if (mem_valid && mem_ready && word_counter == 2'd3) begin
                    next_state = LOOKUP;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always_comb begin
        cpu_ready = 1'b0;
        cpu_rdata = '0;
        mem_valid = 1'b0;
        mem_addr  = '0;
        mem_wdata = '0;
        mem_wstrb = '0;

        if (rst_n) begin
            case (state)
                LOOKUP: begin
                    if (hit && cpu_valid) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = data_mem[index][word];
                    end
                end
                WRITEBACK: begin
                    mem_valid = 1'b1;
                    mem_addr  = {{tag_mem[index]}, {index}, {word_counter}, {2'b00}};
                    mem_wdata = data_mem[index][word_counter];
                    mem_wstrb = 4'b1111;
                end
                ALLOCATE: begin
                    mem_valid = 1'b1;
                    mem_addr  = {{tag}, {index}, {word_counter}, {2'b00}};
                    mem_wstrb = 4'b0000;
                end
                default: ;
            endcase
        end
    end

endmodule
