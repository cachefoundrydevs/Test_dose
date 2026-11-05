`default_nettype none
module l1d_prio_select #(
    parameter REFILL_SKIP = 3,
    parameter SNP_STARVE  = 8
) (
    input  wire clk,
    input  wire rst,
    input  wire snoop_offer_valid,
    input  wire snoop_credit_ok,
    input  wire refill_token_valid,
    input  wire maint_token_valid,
    input  wire lsu_offer_valid,
    input  wire lsu_credit_ok,
    input  wire fast_offer_valid,
    input  wire prefetch_offer_valid,
    input  wire array_write_busy,
    input  wire store_in_flight,
    output wire grant_snoop,
    output wire grant_refill,
    output wire grant_maint,
    output wire grant_lsu,
    output wire grant_fast,
    output wire grant_prefetch
);
    localparam SK_W = (REFILL_SKIP > 0) ? $clog2(REFILL_SKIP + 1) : 1;
    localparam [SK_W-1:0] SKIP_C = REFILL_SKIP;
    localparam ST_W = $clog2(SNP_STARVE + 1);
    localparam [ST_W-1:0] STARVE_C = SNP_STARVE;
    reg  [SK_W-1:0] skip;
    reg  [ST_W-1:0] scnt;
    wire            skip_open = (skip == {SK_W{1'b0}});
    wire            open_  = skip_open && !array_write_busy;
    wire            starve = (scnt == STARVE_C);
    wire            snp_req = snoop_offer_valid && snoop_credit_ok && !(starve && refill_token_valid);
    wire            snp_ok  = snp_req && !store_in_flight;
    wire            snp_wait = snp_req && store_in_flight;
    wire            lsu_ok = lsu_offer_valid && lsu_credit_ok;
    wire            fast_ok = fast_offer_valid && lsu_credit_ok;
    wire            cpu_go = open_ && !snp_ok && !snp_wait && !refill_token_valid && !maint_token_valid;
    assign grant_snoop    = open_ && snp_ok;
    assign grant_refill   = open_ && !snp_ok && refill_token_valid && !store_in_flight;
    assign grant_maint    = open_ && !snp_ok && !refill_token_valid && maint_token_valid && !store_in_flight;
    assign grant_lsu      = cpu_go && lsu_ok;
    assign grant_fast     = cpu_go && !lsu_ok && fast_ok;
    assign grant_prefetch = cpu_go && !lsu_ok && !fast_ok && prefetch_offer_valid;
    always @(posedge clk) begin
        if (rst)
            skip <= {SK_W{1'b0}};
        else if (grant_refill)
            skip <= SKIP_C;
        else if (!skip_open)
            skip <= skip - 1'b1;
    end
    always @(posedge clk) begin
        if (rst || grant_refill || !refill_token_valid)
            scnt <= {ST_W{1'b0}};
        else if (grant_snoop && !starve)
            scnt <= scnt + 1'b1;
    end
endmodule
`default_nettype wire
