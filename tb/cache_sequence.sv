class cache_sequence extends cache_base_sequence;

    `uvm_object_utils(cache_sequence)

    function new(string name = "cache_sequence");
        super.new(name);
    endfunction

    task body();
        logic [31:0] r_data;

        repeat (2) begin
            cache_read(32'h1000, r_data);
            cache_read(32'h1004, r_data);
            cache_read(32'h1008, r_data);
            cache_read(32'h100C, r_data);
        end

        // First access to this line is a masked store, forcing allocation.
        cache_write(32'h1014, 32'hAABBCCDD, 4'b0010);
        cache_read(32'h1010, r_data);
        cache_read(32'h1014, r_data);
        cache_read(32'h1018, r_data);
        cache_read(32'h101C, r_data);

        for (int unsigned mask = 1; mask <= 15; mask++) begin
            cache_write(32'h1020, 32'h11223344, 4'b1111);
            cache_write(32'h1020, 32'hAABBCCDD, mask[3:0]);
            cache_read(32'h1020, r_data);
        end

        cache_write(32'h2014, 32'hDEADBEEF, 4'b1111);
        cache_read(32'h2014, r_data);
        cache_read(32'h1014, r_data);
    endtask
endclass
