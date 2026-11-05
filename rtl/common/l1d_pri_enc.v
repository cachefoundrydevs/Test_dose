`default_nettype none
module l1d_pri_enc #(
    parameter N     = 4,
    parameter IDX_W = (N > 1) ? $clog2(N) : 1
) (
    input  wire [N-1:0]     request_bits,
    output reg  [IDX_W-1:0] lowest_set_index,
    output wire             any_set
);
    integer i;
    always @* begin
        lowest_set_index = {IDX_W{1'b0}};
        for (i = N - 1; i >= 0; i = i - 1)
            if (request_bits[i]) lowest_set_index = i[IDX_W-1:0];
    end
    assign any_set = |request_bits;
endmodule
`default_nettype wire
