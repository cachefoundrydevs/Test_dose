`default_nettype none
module l1d_age_matrix #(
    parameter N     = 8,
    parameter IDX_W = (N > 1) ? $clog2(N) : 1,
    parameter ONEHOT_ALLOC = 0,
    parameter ONEHOT_ENC   = 0
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             allocate_valid,
    input  wire [IDX_W-1:0] allocate_index,
    input  wire [N-1:0]     allocate_onehot,
    input  wire [N-1:0]     candidate_mask,
    output wire [N*N-1:0]   older_than_flat,
    output reg  [N-1:0]     oldest_onehot,
    output wire [IDX_W-1:0] oldest_index,
    output wire             any_candidate
);
    reg [N-1:0] older [0:N-1];
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N; i = i + 1)
                older[i] <= {N{1'b0}};
        end else if (allocate_valid) begin
            for (i = 0; i < N; i = i + 1) begin
                if (ONEHOT_ALLOC != 0) begin
                    if (allocate_onehot[i]) older[i] <= {N{1'b0}};
                    else                    older[i] <= older[i] | allocate_onehot;
                end else begin
                    if (i == allocate_index) older[i] <= {N{1'b0}};
                    else                older[i][allocate_index] <= 1'b1;
                end
            end
        end
    end
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_flat
            assign older_than_flat[g*N +: N] = older[g];
        end
    endgenerate
    integer a;
    integer b;
    always @* begin
        for (a = 0; a < N; a = a + 1) begin
            oldest_onehot[a] = candidate_mask[a];
            for (b = 0; b < N; b = b + 1)
                if (b != a && candidate_mask[b] && older[b][a])
                    oldest_onehot[a] = 1'b0;
        end
    end
    generate
        if (ONEHOT_ENC != 0) begin : g_oh_enc
            reg [IDX_W-1:0] idx_or;
            integer e;
            always @* begin
                idx_or = {IDX_W{1'b0}};
                for (e = 0; e < N; e = e + 1)
                    if (oldest_onehot[e]) idx_or = idx_or | e[IDX_W-1:0];
            end
            assign oldest_index  = idx_or;
            assign any_candidate = |oldest_onehot;
        end else begin : g_pri_enc
            l1d_pri_enc #(.N(N), .IDX_W(IDX_W)) u_enc (
                .request_bits     (oldest_onehot),
                .lowest_set_index (oldest_index),
                .any_set          (any_candidate)
            );
        end
    endgenerate
    always @(posedge clk) begin
        if (ONEHOT_ENC != 0 && !rst && ((oldest_onehot & (oldest_onehot - 1'b1)) != {N{1'b0}}) && (oldest_onehot !== {N{1'bx}}))
            $display("[%0t] L1D AGE %m ERROR oldest_onehot is not one-hot (%b): keep ONEHOT_ENC = 0 for this user", $time, oldest_onehot);
    end
endmodule
`default_nettype wire
