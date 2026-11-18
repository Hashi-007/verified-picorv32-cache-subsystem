class cache_wait_sequence extends cache_base_sequence;
    `uvm_object_utils(cache_wait_sequence)

    function new(string name = "cache_wait_sequence");
        super.new(name);
    endfunction

    task body();
        logic [31:0] r_data;

        cache_read(32'h1000, r_data);
        cache_write(32'h1004, 32'hDEADBEEF, 4'b1111);
        cache_read(32'h1004, r_data);

        // Dirty read miss, then clean and dirty store misses at the same index.
        cache_read(32'h2000, r_data);
        cache_write(32'h3004, 32'hCAFEBABE, 4'b1111);
        cache_write(32'h4008, 32'hA5A55A5A, 4'b1111);
        cache_read(32'h4008, r_data);
        cache_read(32'h1004, r_data);
    endtask
endclass
