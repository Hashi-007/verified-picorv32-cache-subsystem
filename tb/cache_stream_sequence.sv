// Visit every index, then exercise every store mask on a miss and a hit.
// Helpers submit the next item immediately; +CPU_STREAM removes driver gaps.
class cache_stream_sequence extends cache_base_sequence;
    `uvm_object_utils(cache_stream_sequence)

    function new(string name = "cache_stream_sequence");
        super.new(name);
    endfunction

    task body();
        logic [31:0] data;
        for (int i = 0; i < 256; i++)
            cache_read(32'h1000 + 16 * i + 4 * (i % 4), data);
        for (int mask = 1; mask <= 15; mask++) begin
            cache_write(32'h2000 + 16 * mask, 32'hAABBCCDD, mask[3:0]);
            cache_write(32'h2000 + 16 * mask, 32'h11223344, mask[3:0]);
            cache_read(32'h2000 + 16 * mask, data);
        end
    endtask
endclass
