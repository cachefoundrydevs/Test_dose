`default_nettype none
`include "l1d_defines.vh"
module l1d_maint #(`L1D_PARAMS) (
    clk, rst,
    maint_start, maint_op_is_flush, bank_idle, victim_cache_empty, victim_cache_drain,
    token_valid, token_set, token_way, token_op_is_flush, token_granted,
    s2_result_valid, s2_result_held,
    maint_done, maint_busy
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire               clk;
    input  wire               rst;
    input  wire               maint_start;
    input  wire               maint_op_is_flush;
    input  wire               bank_idle;
    input  wire               victim_cache_empty;
    output wire               victim_cache_drain;
    output wire               token_valid;
    output wire [INDEX_W-1:0] token_set;
    output wire [WAY_W-1:0]   token_way;
    output wire               token_op_is_flush;
    input  wire               token_granted;
    input  wire               s2_result_valid;
    input  wire               s2_result_held;
    output reg                maint_done;
    output wire               maint_busy;
    localparam [2:0] M_IDLE  = 3'd0;
    localparam [2:0] M_WAIT  = 3'd1;
    localparam [2:0] M_DRAIN = 3'd2;
    localparam [2:0] M_REQ   = 3'd3;
    localparam [2:0] M_RUN   = 3'd4;
    localparam [2:0] M_FINAL = 3'd5;
    localparam [INDEX_W-1:0] LAST_SET = SETS - 1;
    localparam [WAY_W-1:0]   LAST_WAY = WAYS - 1;
    reg [2:0]         ms;
    reg               op_r;
    reg [INDEX_W-1:0] set_r;
    reg [WAY_W-1:0]   way_r;
    reg               wlast_q;
    reg               slast_q;
    reg [INDEX_W-1:0] set_inc_q;
    localparam        WLAST0 = (LAST_WAY == {WAY_W{1'b0}});
    localparam        SLAST0 = (LAST_SET == {INDEX_W{1'b0}});
    always @(posedge clk) begin
        if (rst) begin
            ms    <= M_IDLE;
            op_r  <= MAINT_CLEAN;
            set_r <= {INDEX_W{1'b0}};
            way_r <= {WAY_W{1'b0}};
            wlast_q   <= WLAST0;
            slast_q   <= SLAST0;
            set_inc_q <= {INDEX_W{1'b0}} + 1'b1;
            maint_done  <= 1'b0;
        end else begin
            maint_done <= 1'b0;
            case (ms)
                M_IDLE: if (maint_start) begin
                    op_r  <= maint_op_is_flush;
                    set_r <= {INDEX_W{1'b0}};
                    way_r <= {WAY_W{1'b0}};
                    wlast_q   <= WLAST0;
                    slast_q   <= SLAST0;
                    set_inc_q <= {INDEX_W{1'b0}} + 1'b1;
                    ms    <= M_WAIT;
                end
                M_WAIT:  if (bank_idle) ms <= M_DRAIN;
                M_DRAIN: if (victim_cache_empty)  ms <= M_REQ;
                M_REQ:   if (token_granted)   ms <= M_RUN;
                M_RUN: if (s2_result_valid) begin
                    if (s2_result_held) begin
                        ms <= M_REQ;
                    end else if (wlast_q && slast_q) begin
                        ms <= M_FINAL;
                    end else begin
                        if (wlast_q) begin
                            way_r     <= {WAY_W{1'b0}};
                            set_r     <= set_inc_q;
                            wlast_q   <= WLAST0;
                            slast_q   <= (set_inc_q == LAST_SET);
                            set_inc_q <= set_inc_q + 1'b1;
                        end else begin
                            way_r     <= way_r + 1'b1;
                            wlast_q   <= ((way_r + 1'b1) == LAST_WAY);
                        end
                        ms <= M_REQ;
                    end
                end
                M_FINAL: if (victim_cache_empty) begin
                    maint_done <= 1'b1;
                    ms   <= M_IDLE;
                end
                default: ms <= M_IDLE;
            endcase
        end
    end
    assign victim_cache_drain  = (ms == M_DRAIN) || (ms == M_FINAL);
    assign token_valid = (ms == M_REQ);
    assign token_set   = set_r;
    assign token_way   = way_r;
    assign token_op_is_flush    = op_r;
    assign maint_busy      = (ms != M_IDLE);
`ifdef L1D_DEBUG
    function [8*5-1:0] dbg_mname;
        input [2:0] s;
        begin
            case (s)
                M_IDLE:  dbg_mname = "IDLE";
                M_WAIT:  dbg_mname = "WAIT";
                M_DRAIN: dbg_mname = "DRAIN";
                M_REQ:   dbg_mname = "REQ";
                M_RUN:   dbg_mname = "RUN";
                default: dbg_mname = "FINAL";
            endcase
        end
    endfunction
    reg [2:0] dbg_ps;
    integer   dbg_age;
    initial begin dbg_ps = M_IDLE; dbg_age = 0; end
    always @(posedge clk) begin
        if (rst) begin
            dbg_ps  = M_IDLE;
            dbg_age = 0;
        end else begin
            if (ms != dbg_ps) begin
                if (!(dbg_ps == M_REQ && ms == M_RUN) && !(dbg_ps == M_RUN && ms == M_REQ))
                    $display("[%0t] L1D MAINT %m: %0s -> %0s (%s)", $time, dbg_mname(dbg_ps), dbg_mname(ms),
                             op_r == MAINT_FLUSH ? "flush" : "clean");
                dbg_ps  = ms;
                dbg_age = 0;
            end else if (ms != M_IDLE) begin
                dbg_age = dbg_age + 1;
                if (dbg_age % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D MAINT %m STUCK in %0s for %0d cycles  set=%0d way=%0d bank_idle=%b vc_empty=%b",
                             $time, dbg_mname(ms), dbg_age, set_r, way_r, bank_idle, victim_cache_empty);
            end
            if (ms == M_RUN && s2_result_valid && s2_result_held)
                $display("[%0t] L1D MAINT %m set %0d way %0d held (no victim-cache slot), retry", $time, set_r, way_r);
            if (ms == M_RUN && s2_result_valid && !s2_result_held && way_r == LAST_WAY && (set_r % 16) == 15)
                $display("[%0t] L1D MAINT %m walked sets 0..%0d", $time, set_r);
            if (maint_done)
                $display("[%0t] L1D MAINT %m done", $time);
        end
    end
`endif
endmodule
`default_nettype wire
