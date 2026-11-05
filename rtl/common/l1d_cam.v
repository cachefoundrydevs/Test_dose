`default_nettype none
module l1d_cam #(
    parameter N     = 8,
    parameter KEY_W = 16
) (
    input  wire [N*KEY_W-1:0] stored_keys,
    input  wire [N-1:0]       stored_valid,
    input  wire [KEY_W-1:0]   search_key,
    output wire [N-1:0]       match_onehot
);
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_cmp
            assign match_onehot[g] = stored_valid[g] && (stored_keys[g*KEY_W +: KEY_W] == search_key);
        end
    endgenerate
endmodule
`default_nettype wire
