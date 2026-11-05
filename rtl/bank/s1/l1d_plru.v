`default_nettype none
module l1d_plru #(
    parameter WAYS  = 4,
    parameter WAY_W = $clog2(WAYS),
    parameter NB    = WAYS - 1
) (
    input  wire [NB-1:0]    plru_bits,
    input  wire [WAY_W-1:0] accessed_way,
    output reg  [WAY_W-1:0] victim_way,
    output reg  [NB-1:0]    plru_bits_next
);
    integer l;
    integer node;
    integer dir;
    always @* begin
        node   = 0;
        victim_way = {WAY_W{1'b0}};
        for (l = 0; l < WAY_W; l = l + 1) begin
            dir    = plru_bits[node] ? 1 : 0;
            victim_way = (victim_way << 1) | dir[WAY_W-1:0];
            node   = 2 * node + 1 + dir;
        end
    end
    integer ul;
    integer unode;
    integer udir;
    always @* begin
        unode    = 0;
        plru_bits_next = plru_bits;
        for (ul = 0; ul < WAY_W; ul = ul + 1) begin
            udir            = accessed_way[WAY_W-1-ul] ? 1 : 0;
            plru_bits_next[unode] = (udir == 0);
            unode           = 2 * unode + 1 + udir;
        end
    end
endmodule
`default_nettype wire
