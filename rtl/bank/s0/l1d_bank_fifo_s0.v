`ifndef L1D_BANK_FIFO_S0_V
`define L1D_BANK_FIFO_S0_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_fifo_s0 #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst,
    lsu_request_valid, lsu_request_packet, lsu_request_ready, lsu_response_fifo_free,
    snoop_request_valid, snoop_request_line_addr, snoop_request_invalidate, snoop_request_ready, snoop_response_fifo_free,
    prefetch_request_valid, prefetch_request_line_addr, prefetch_request_ready,
    refill_handover_busy,
    s1_valid, s1_kind, s1_req,
    s2_valid, s2_kind, s2_req, s2_hit, s2_seat, s2_sid, s2_line,
    s3_amo_v,
    act_valid, act_code, act_id, done_valid, done_seat, snp_act_valid, snp_act_code, snp_act_id,
    lock_valid, lock_snp, lock_line, ev_amor,
    tok_valid, tok_id, tok_line, mt_valid, mt_set, mt_way, mt_op,
    m_resp_valid, n_resp_valid,
    mshr_freed, vc_freed, nc_freed,
    any_gnt, g_set, gnt_refill, gnt_maint,
    r_valid, r_kind, r_seat, r_req, r_fast, r_mid, r_line, r_mway, r_mop, r_sinv, r_sid,
    seat_blk, buf_empty, miss_ok
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam [BANK_W-1:0]   BANK_C = BANK_ID;
    localparam [OFFSET_W-1:0] OFF0   = {OFFSET_W{1'b0}};
    input  wire                        clk;
    input  wire                        rst;
    input  wire                        lsu_request_valid;
    input  wire [REQ_W-1:0]            lsu_request_packet;
    output wire                        lsu_request_ready;
    input  wire [LSU_PORTS*RCNT_W-1:0] lsu_response_fifo_free;
    input  wire                        snoop_request_valid;
    input  wire [LINE_ADDR_W-1:0]      snoop_request_line_addr;
    input  wire                        snoop_request_invalidate;
    output wire                        snoop_request_ready;
    input  wire [SNPR_CNT_W-1:0]       snoop_response_fifo_free;
    input  wire                        prefetch_request_valid;
    input  wire [LINE_ADDR_W-1:0]      prefetch_request_line_addr;
    output wire                        prefetch_request_ready;
    input  wire                        refill_handover_busy;
    input  wire                        s1_valid;
    input  wire [1:0]                  s1_kind;
    input  wire [REQ_W-1:0]            s1_req;
    input  wire                        s2_valid;
    input  wire [1:0]                  s2_kind;
    input  wire [REQ_W-1:0]            s2_req;
    input  wire                        s2_hit;
    input  wire [SEAT_W-1:0]           s2_seat;
    input  wire [SNP_ID_W-1:0]         s2_sid;
    input  wire [LINE_ADDR_W-1:0]      s2_line;
    input  wire                        s3_amo_v;
    input  wire                        act_valid;
    input  wire [2:0]                  act_code;
    input  wire [WID_W-1:0]            act_id;
    input  wire                        done_valid;
    input  wire [SEAT_W-1:0]           done_seat;
    input  wire                        snp_act_valid;
    input  wire [1:0]                  snp_act_code;
    input  wire [WID_W-1:0]            snp_act_id;
    input  wire                        lock_valid;
    input  wire                        lock_snp;
    input  wire [LINE_ADDR_W-1:0]      lock_line;
    input  wire                        ev_amor;
    input  wire                        tok_valid;
    input  wire [MSHR_ID_W-1:0]        tok_id;
    input  wire [LINE_ADDR_W-1:0]      tok_line;
    input  wire                        mt_valid;
    input  wire [INDEX_W-1:0]          mt_set;
    input  wire [WAY_W-1:0]            mt_way;
    input  wire                        mt_op;
    input  wire                        m_resp_valid;
    input  wire                        n_resp_valid;
    input  wire [MSHR_ENTRIES-1:0]     mshr_freed;
    input  wire [VC_SLOTS-1:0]         vc_freed;
    input  wire                        nc_freed;
    output wire                        any_gnt;
    output wire [INDEX_W-1:0]          g_set;
    output wire                        gnt_refill;
    output wire                        gnt_maint;
    output reg                         r_valid;
    output reg  [1:0]                  r_kind;
    output reg  [SEAT_W-1:0]           r_seat;
    output reg  [REQ_W-1:0]            r_req;
    output reg                         r_fast;
    output reg  [MSHR_ID_W-1:0]        r_mid;
    output reg  [LINE_ADDR_W-1:0]      r_line;
    output reg  [WAY_W-1:0]            r_mway;
    output reg                         r_mop;
    output reg                         r_sinv;
    output reg  [SNP_ID_W-1:0]         r_sid;
    output wire [LSU_BUF_DEPTH-1:0]    seat_blk;
    output wire                        buf_empty;
    output wire                        miss_ok;
    wire r_lsu  = r_valid  && (r_kind  == K_LSU);
    wire s1_lsu = s1_valid && (s1_kind == K_LSU);
    wire s2_lsu = s2_valid && (s2_kind == K_LSU);
    wire [LSU_PORTS-1:0] port_miss_ok;
    wire [LSU_PORTS-1:0] port_grant_ok;
    wire                 push_this_cycle = s2_lsu || m_resp_valid || n_resp_valid;
    genvar credit_port;
    generate
        for (credit_port = 0; credit_port < LSU_PORTS; credit_port = credit_port + 1) begin : g_port_credit
            wire              r_on_port   = r_lsu  && (r_req[REQ_PORT_LSB +: PORT_W]  == credit_port);
            wire              s1_on_port  = s1_lsu && (s1_req[REQ_PORT_LSB +: PORT_W] == credit_port);
            wire [RCNT_W-1:0] port_free   = lsu_response_fifo_free[credit_port*RCNT_W +: RCNT_W];
            wire [RCNT_W+1:0] resv_miss_port  = r_on_port + s1_on_port;
            wire [RCNT_W+1:0] resv_grant_port = r_on_port + s1_on_port + push_this_cycle;
            assign port_miss_ok[credit_port]  = (port_free > resv_miss_port);
            assign port_grant_ok[credit_port] = (port_free > resv_grant_port);
        end
    endgenerate
    assign miss_ok  = &port_miss_ok;
    wire lsu_credit = &port_grant_ok;
    wire r_amor_any  = r_lsu  && r_req[REQ_AMO_BIT]  && r_req[REQ_SEQ_BIT]  && !r_req[REQ_RDWR_BIT];
    wire s1_amor_any = s1_lsu && s1_req[REQ_AMO_BIT] && s1_req[REQ_SEQ_BIT] && !s1_req[REQ_RDWR_BIT];
    wire s2_amor_any = s2_lsu && s2_req[REQ_AMO_BIT] && s2_req[REQ_SEQ_BIT] && !s2_req[REQ_RDWR_BIT];
    wire amor_busy   = r_amor_any || s1_amor_any || s2_amor_any;
    wire snp_credit  = (snoop_response_fifo_free != {SNPR_CNT_W{1'b0}});
    wire                 sel_valid;
    wire [SEAT_W-1:0]    sel_seat;
    wire [REQ_W-1:0]     sel_req;
    wire                 sn_sel_valid, sn_sel_inv;
    wire [SNP_ID_W-1:0]  sn_sel_id;
    wire [LINE_ADDR_W-1:0] sn_sel_line;
    wire                 pf_sel_valid;
    wire [LINE_ADDR_W-1:0] pf_sel_line;
    wire                 gnt_snoop, gnt_lsu, gnt_pf;
    wire                 gnt_fast;
    wire [SEAT_W-1:0]    new_seat;
    assign any_gnt = gnt_snoop || gnt_refill || gnt_maint || gnt_lsu || gnt_fast;
    l1d_fifo_stage #(`L1D_PARAMS_PASS) u_fifo (
        .clk                      (clk),
        .rst                      (rst),
        .lsu_new_request_valid    (lsu_request_valid),
        .lsu_new_request_packet   (lsu_request_packet),
        .lsu_new_request_ready    (lsu_request_ready),
        .lsu_offer_valid          (sel_valid),
        .lsu_offer_seat           (sel_seat),
        .lsu_offer_request_packet (sel_req),
        .lsu_offer_granted        (gnt_lsu),
        .lsu_s2_action_valid      (act_valid),
        .lsu_s2_action_seat       (s2_seat),
        .lsu_s2_action_code       (act_code),
        .lsu_s2_action_wait_id    (act_id),
        .lsu_s3_done_valid        (done_valid),
        .lsu_s3_done_seat         (done_seat),
        .amo_lock_valid           (lock_valid),
        .amo_lock_line            (lock_line),
        .lsu_buffer_empty         (buf_empty),
        .lsu_new_request_granted  (gnt_fast),
        .lsu_new_request_seat     (new_seat),
        .lsu_seat_blocked         (seat_blk),
        .snoop_new_valid          (snoop_request_valid),
        .snoop_new_line_addr      (snoop_request_line_addr),
        .snoop_new_invalidate     (snoop_request_invalidate),
        .snoop_new_ready          (snoop_request_ready),
        .amo_lock_snoop_hold      (lock_snp),
        .amo_read_in_pipeline     (amor_busy || refill_handover_busy),
        .amo_lock_set_valid       (ev_amor),
        .amo_lock_set_line        (s2_line),
        .snoop_offer_valid        (sn_sel_valid),
        .snoop_offer_entry_id     (sn_sel_id),
        .snoop_offer_line_addr    (sn_sel_line),
        .snoop_offer_invalidate   (sn_sel_inv),
        .snoop_offer_granted      (gnt_snoop),
        .snoop_s2_action_valid    (snp_act_valid),
        .snoop_s2_action_entry_id (s2_sid),
        .snoop_s2_action_code     (snp_act_code),
        .snoop_s2_action_wait_id  (snp_act_id),
        .snoop_buffer_empty       (),
        .prefetch_new_valid       (prefetch_request_valid),
        .prefetch_new_line_addr   (prefetch_request_line_addr),
        .prefetch_new_ready       (prefetch_request_ready),
        .prefetch_offer_valid     (pf_sel_valid),
        .prefetch_offer_line_addr (pf_sel_line),
        .prefetch_offer_granted   (gnt_pf),
        .mshr_entry_freed         (mshr_freed),
        .victim_slot_freed        (vc_freed),
        .nc_entry_freed           (nc_freed)
    );
    wire r_amo1 = r_lsu && r_req[REQ_AMO_BIT] && r_req[REQ_SEQ_BIT];
    wire arr_wr_busy = r_amo1;
    wire st_inflight = (r_lsu  && (r_req[REQ_RDWR_BIT]  == OP_WRITE)) ||
                       (s1_lsu && (s1_req[REQ_RDWR_BIT] == OP_WRITE)) ||
                       (s2_lsu && s2_hit && (s2_req[REQ_RDWR_BIT] == OP_WRITE)) ||
                       s3_amo_v;
    wire fast_valid  = lsu_request_valid && lsu_request_ready;
    l1d_prio_select #(.REFILL_SKIP(REFILL_SKIP + 1), .SNP_STARVE(SNP_STARVE)) u_prio (
        .clk                  (clk),
        .rst                  (rst),
        .snoop_offer_valid    (sn_sel_valid),
        .snoop_credit_ok      (snp_credit),
        .refill_token_valid   (tok_valid),
        .maint_token_valid    (mt_valid),
        .lsu_offer_valid      (sel_valid),
        .lsu_credit_ok        (lsu_credit),
        .fast_offer_valid     (fast_valid),
        .prefetch_offer_valid (pf_sel_valid),
        .array_write_busy     (arr_wr_busy),
        .store_in_flight      (st_inflight),
        .grant_snoop          (gnt_snoop),
        .grant_refill         (gnt_refill),
        .grant_maint          (gnt_maint),
        .grant_lsu            (gnt_lsu),
        .grant_fast           (gnt_fast),
        .grant_prefetch       (gnt_pf)
    );
    wire [LINE_ADDR_W-1:0] sel_line = sel_req[REQ_ADDR_LSB + OFFSET_W +: LINE_ADDR_W];
    wire [LINE_ADDR_W-1:0] new_line = lsu_request_packet[REQ_ADDR_LSB + OFFSET_W +: LINE_ADDR_W];
    wire [LINE_ADDR_W-1:0] mt_line  = {{TAG_W{1'b0}}, mt_set, BANK_C};
    wire [LINE_ADDR_W-1:0] g_line   = gnt_snoop  ? sn_sel_line :
                                      gnt_refill ? tok_line :
                                      gnt_maint  ? mt_line :
                                      gnt_fast   ? new_line : sel_line;
    assign                 g_set    = g_line[LA_SET_LSB +: INDEX_W];
    always @(posedge clk) begin
        if (rst) begin
            r_valid  <= 1'b0;
        end else begin
            r_valid  <= any_gnt;
            r_kind   <= gnt_snoop ? K_SNOOP : (gnt_refill ? K_REFILL : (gnt_maint ? K_MAINT : K_LSU));
            r_seat   <= gnt_fast ? new_seat : sel_seat;
            r_req    <= gnt_fast ? lsu_request_packet : sel_req;
            r_fast   <= gnt_fast;
            r_mid    <= tok_id;
            r_line   <= g_line;
            r_mway   <= mt_way;
            r_mop    <= mt_op;
            r_sinv   <= sn_sel_inv;
            r_sid    <= sn_sel_id;
        end
    end
`ifdef L1D_DEBUG
    integer dbg_s0w;
    initial dbg_s0w = 0;
    function [8*4-1:0] dbg_cls;
        input [REQ_W-1:0] r;
        begin
            if (!r[REQ_AMO_BIT])     dbg_cls = r[REQ_RDWR_BIT] ? "ST  " : "LD  ";
            else if (!r[REQ_SEQ_BIT]) dbg_cls = r[REQ_RDWR_BIT] ? "SC  " : "LR  ";
            else                      dbg_cls = r[REQ_RDWR_BIT] ? "AMOW" : "AMOR";
        end
    endfunction
    always @(posedge clk) begin
        if (!rst) begin
            if (gnt_snoop)
                $display("[%0t] L1D B%0d S0 GRANT snoop %s line=%h",
                         $time, BANK_ID, sn_sel_inv ? "INV" : "READ", {sn_sel_line, OFF0});
            else if (gnt_refill)
                $display("[%0t] L1D B%0d S0 GRANT refill token  mshr=%0d line=%h",
                         $time, BANK_ID, tok_id, {tok_line, OFF0});
            else if (gnt_maint)
                $display("[%0t] L1D B%0d S0 GRANT %s token  set=%0d way=%0d",
                         $time, BANK_ID, (mt_op == MAINT_FLUSH) ? "flush" : "clean", mt_set, mt_way);
            else if (gnt_lsu)
                $display("[%0t] L1D B%0d S0 GRANT LSU  seat=%0d idx=%0d %0s %s addr=%h  (resp_free=%0d)",
                         $time, BANK_ID, sel_seat, sel_req[REQ_IDX_LSB +: IDX_BITS],
                         dbg_cls(sel_req), (sel_req[REQ_CACHE_BIT] ? "C " : "NC"),
                         sel_req[REQ_ADDR_LSB +: ADDR_W], lsu_response_fifo_free);
            else if (gnt_fast)
                $display("[%0t] L1D B%0d G  FAST ISSUE seat=%0d idx=%0d %0s %s addr=%h  (resp_free=%0d)",
                         $time, BANK_ID, new_seat, lsu_request_packet[REQ_IDX_LSB +: IDX_BITS],
                         dbg_cls(lsu_request_packet), (lsu_request_packet[REQ_CACHE_BIT] ? "C " : "NC"),
                         lsu_request_packet[REQ_ADDR_LSB +: ADDR_W], lsu_response_fifo_free);
            else if (gnt_pf)
                $display("[%0t] L1D B%0d S0 prefetch line=%h dropped (v2: FIFO only)", $time, BANK_ID, {pf_sel_line, OFF0});
            if (sel_valid && !gnt_lsu) begin
                dbg_s0w = dbg_s0w + 1;
                if (dbg_s0w % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D B%0d S0 STUCK seat %0d ready but not granted for %0d cycles: snoop=%b refill_token=%b maint_token=%b credit=%b (resp_free per port=%h, port credit ok=%b); if all 0 it is the skip after a refill",
                             $time, BANK_ID, sel_seat, dbg_s0w, gnt_snoop, tok_valid, mt_valid, lsu_credit, lsu_response_fifo_free, port_grant_ok);
            end else begin
                dbg_s0w = 0;
            end
        end
    end
`endif
endmodule
`default_nettype wire
`endif
