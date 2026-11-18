class cache_item extends uvm_sequence_item;
    rand logic [31:0] addr;
    rand logic [31:0] wdata;
    rand logic [3:0]  wstrb;

    logic [31:0] rdata;

    constraint addr_range {
        addr inside {[32'h1000 : 32'h10FFC]};
        addr[1:0] == 2'b00;
    }

    `uvm_object_utils(cache_item)

    function new(string name = "cache_item");
        super.new(name);
    endfunction

    // Validate before converting an address to an array subscript. Only enabled
    // store bytes are meaningful; reads must carry a completely known result.
    function bit fields_valid(bit ram_side = 0);
        if ($isunknown({addr, wstrb}) || addr[1:0] != 0 ||
            addr < 32'h1000 || addr > 32'h10FFC) return 0;
        if (ram_side && !(wstrb inside {4'h0, 4'hF}))
            return 0;
        if (wstrb == 0)
            return !$isunknown(rdata);
        for (int i = 0; i < 4; i++)
            if (wstrb[i] && $isunknown(wdata[8 * i +: 8]))
                return 0;
        return 1;
    endfunction
endclass
