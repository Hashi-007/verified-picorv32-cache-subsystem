class cache_random_sequence extends cache_base_sequence;
    `uvm_object_utils(cache_random_sequence)

    function new(string name = "cache_random_sequence");
        super.new(name);
    endfunction

    task body();
        cache_item tr;
        int unsigned choice;
        logic [31:0] last_addr = 32'h1000;
        for (int i = 0; i < 1000; i++) begin
            choice = $urandom_range(99, 0);
            tr     = cache_item::type_id::create("tr");
            start_item(tr);
            // Mix same-line reuse, same-index conflicts and the complete region.
            // Solve data/strobes in every branch; reads and stores are balanced.
            if (choice < 40) begin
                if (!tr.randomize() with {
                    addr[31:4] == local::last_addr[31:4];
                    wstrb dist {0 := 15, [1:15] := 1};
                }) `uvm_fatal("RANDOMIZE", "Locality request randomization failed")
            end else if (choice < 70) begin
                if (!tr.randomize() with {
                    addr[11:4] == local::last_addr[11:4];
                    addr[31:12] != local::last_addr[31:12];
                    wstrb dist {0 := 15, [1:15] := 1};
                }) `uvm_fatal("RANDOMIZE", "Conflict request randomization failed")
            end else begin
                if (!tr.randomize() with {
                    wstrb dist {0 := 15, [1:15] := 1};
                }) `uvm_fatal("RANDOMIZE", "Region request randomization failed")
            end
            last_addr = tr.addr;
            finish_item(tr);
        end
    endtask
endclass
