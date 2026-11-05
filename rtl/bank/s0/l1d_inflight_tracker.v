`default_nettype none
module l1d_inflight_tracker #(
    parameter N           = 8,
    parameter LINE_ADDR_W = 58
) (
    input  wire [N-1:0]             seat_occupied,
    input  wire [N-1:0]             seat_is_store_class,
    input  wire [N-1:0]             seat_is_amo_read,
    input  wire [N-1:0]             seat_is_amo_write,
    input  wire [N*LINE_ADDR_W-1:0] seat_line_addrs,
    input  wire [N*N-1:0]           older_than_flat,
    input  wire                     amo_lock_valid,
    input  wire [LINE_ADDR_W-1:0]   amo_lock_line,
    output reg  [N-1:0]             seat_blocked
);
    integer c;
    integer o;
    reg     v1_blk;
    reg     older_amor;
    reg     lock_hit;
    always @* begin
        for (c = 0; c < N; c = c + 1) begin
            v1_blk     = 1'b0;
            older_amor = 1'b0;
            for (o = 0; o < N; o = o + 1) begin
                if (o != c && seat_occupied[o] && older_than_flat[o*N + c]) begin
                    if ((seat_line_addrs[o*LINE_ADDR_W +: LINE_ADDR_W] == seat_line_addrs[c*LINE_ADDR_W +: LINE_ADDR_W]) &&
                        (seat_is_store_class[o] || seat_is_store_class[c]))
                        v1_blk = 1'b1;
                    if (seat_is_amo_read[o])
                        older_amor = 1'b1;
                end
            end
            lock_hit   = amo_lock_valid && (seat_line_addrs[c*LINE_ADDR_W +: LINE_ADDR_W] == amo_lock_line);
            seat_blocked[c] = (v1_blk && !(seat_is_amo_write[c] && lock_hit)) ||
                         (lock_hit && !seat_is_amo_write[c]) ||
                         (seat_is_amo_read[c] && (amo_lock_valid || older_amor));
        end
    end
endmodule
`default_nettype wire
