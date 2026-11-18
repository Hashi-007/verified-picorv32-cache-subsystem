class cache_base_sequence extends uvm_sequence;
    `uvm_object_utils(cache_base_sequence)

    function new(string name = "cache_base_sequence");
        super.new(name);
    endfunction

    task body();
    endtask

    task cache_read(
        input  logic [31:0] addr,
        output logic [31:0] data
    );

        cache_item tr;
        tr = cache_item::type_id::create("tr");

        start_item(tr);
        tr.addr  = addr;
        tr.wdata = '0;
        tr.wstrb = '0;
        finish_item(tr);
        data = tr.rdata;
    endtask

    task cache_write(
        input  logic [31:0] addr,
        input  logic [31:0] data,
        input  logic [3:0]  wstrb
    );
        cache_item tr;
        tr = cache_item::type_id::create("tr");

        start_item(tr);
        tr.addr  = addr;
        tr.wdata = data;
        tr.wstrb = wstrb;
        finish_item(tr);
    endtask
endclass
