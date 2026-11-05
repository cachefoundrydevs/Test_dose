`default_nettype none
`include "l1d_defines.vh"
module l1d_bank #(`L1D_PARAMS, parameter BANK_ID = 0) (
    clk, rst,
    lsu_request_valid, lsu_request_packet, lsu_request_ready,
    lsu_response_valid, lsu_response_packet, lsu_response_fifo_free,
    snoop_request_valid, snoop_request_line_addr, snoop_request_invalidate, snoop_request_ready,
    snoop_response_valid, snoop_response_packet, snoop_response_fifo_free,
    prefetch_request_valid, prefetch_request_line_addr, prefetch_request_ready,
    axi_read_req_valid, axi_read_req_ready, axi_read_req_addr, axi_read_req_burst_len, axi_read_req_size, axi_read_req_sub_id, axi_read_req_non_cacheable, axi_read_req_unique,
    axi_read_data_valid, axi_read_data_sub_id, axi_read_data_non_cacheable, axi_read_data, axi_read_data_last, axi_read_data_error, axi_read_data_shared,
    axi_write_req_valid, axi_write_req_ready, axi_write_req_addr, axi_write_req_burst_len, axi_write_req_size, axi_write_req_sub_id, axi_write_req_non_cacheable, axi_write_req_data, axi_write_req_strobe,
    axi_write_resp_valid, axi_write_resp_sub_id, axi_write_resp_non_cacheable, axi_write_resp_error,
    refill_handover_busy,
    maint_start, maint_op_is_flush, maint_done,
    amo_lock_timeout_pulse,
    rsv_event_pulse, other_bank_rsv_event
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire                     clk;
    input  wire                     rst;
    input  wire                     lsu_request_valid;
    input  wire [REQ_W-1:0]         lsu_request_packet;
    output wire                     lsu_request_ready;
    output wire                     lsu_response_valid;
    output wire [RESP_W-1:0]        lsu_response_packet;
    input  wire [LSU_PORTS*RCNT_W-1:0] lsu_response_fifo_free;
    output wire                     rsv_event_pulse;
    input  wire                     other_bank_rsv_event;
    input  wire                     snoop_request_valid;
    input  wire [LINE_ADDR_W-1:0]   snoop_request_line_addr;
    input  wire                     snoop_request_invalidate;
    output wire                     snoop_request_ready;
    output wire                     snoop_response_valid;
    output wire [SNPR_W-1:0]        snoop_response_packet;
    input  wire [SNPR_CNT_W-1:0]    snoop_response_fifo_free;
    input  wire                     prefetch_request_valid;
    input  wire [LINE_ADDR_W-1:0]   prefetch_request_line_addr;
    output wire                     prefetch_request_ready;
    output wire                     axi_read_req_valid;
    input  wire                     axi_read_req_ready;
    output wire [AXI_ADDR_W-1:0]    axi_read_req_addr;
    output wire [7:0]               axi_read_req_burst_len;
    output wire [2:0]               axi_read_req_size;
    output wire [AXI_SUBID_W-1:0]   axi_read_req_sub_id;
    output wire                     axi_read_req_non_cacheable;
    output wire                     axi_read_req_unique;
    input  wire                     axi_read_data_valid;
    input  wire [AXI_SUBID_W-1:0]   axi_read_data_sub_id;
    input  wire                     axi_read_data_non_cacheable;
    input  wire [AXI_DATA_W-1:0]    axi_read_data;
    input  wire                     axi_read_data_last;
    input  wire                     axi_read_data_error;
    input  wire                     axi_read_data_shared;
    input  wire                     refill_handover_busy;
    output wire                     axi_write_req_valid;
    input  wire                     axi_write_req_ready;
    output wire [AXI_ADDR_W-1:0]    axi_write_req_addr;
    output wire [7:0]               axi_write_req_burst_len;
    output wire [2:0]               axi_write_req_size;
    output wire [AXI_SUBID_W-1:0]   axi_write_req_sub_id;
    output wire                     axi_write_req_non_cacheable;
    output wire [LINE_W-1:0]        axi_write_req_data;
    output wire [AXI_STRB_W-1:0]    axi_write_req_strobe;
    input  wire                     axi_write_resp_valid;
    input  wire [AXI_SUBID_W-1:0]   axi_write_resp_sub_id;
    input  wire                     axi_write_resp_non_cacheable;
    input  wire                     axi_write_resp_error;
    input  wire                     maint_start;
    input  wire                     maint_op_is_flush;
    output wire                     maint_done;
    output wire                     amo_lock_timeout_pulse;
    localparam [BANK_W-1:0] BANK_C  = BANK_ID;
    localparam [7:0]        LEN_C   = AXI_LEN;
    localparam [2:0]        SIZE_C  = AXI_SIZE;
    localparam [OFFSET_W-1:0] OFF0  = {OFFSET_W{1'b0}};
    localparam [WRITE_DATA_WIDTH-1:0] SC_FAIL_W = {{(WRITE_DATA_WIDTH-1){1'b0}}, SC_FAIL};
    reg                     r_valid;
    reg  [1:0]              r_kind;
    reg  [SEAT_W-1:0]       r_seat;
    reg  [REQ_W-1:0]        r_req;
    reg  [MSHR_ID_W-1:0]    r_mid;
    reg  [LINE_ADDR_W-1:0]  r_line;
    reg  [WAY_W-1:0]        r_mway;
    reg                     r_mop;
    reg                     r_sinv;
    reg  [SNP_ID_W-1:0]     r_sid;
    reg                     r_fast;
    reg                     s1_kill, s2_kill;
    reg  [WAYS*TAG_W-1:0]   tag_q;
    reg  [WAYS*LINE_W-1:0]  s1_lines;
    reg  [WAYS*WRITE_DATA_WIDTH-1:0] s2_words;
    reg  [WAYS*LINE_W-1:0]  s2_lines;
    reg  [LINE_BYTES-1:0]   s2_st_be;
    reg  [LINE_W-1:0]       s2_st_din;
    reg                     s1_valid, s2_valid;
    reg  [1:0]              s1_kind,  s2_kind;
    reg  [SEAT_W-1:0]       s1_seat,  s2_seat;
    reg  [REQ_W-1:0]        s1_req,   s2_req;
    reg  [MSHR_ID_W-1:0]    s1_mid,   s2_mid;
    reg  [LINE_ADDR_W-1:0]  s1_line,  s2_line;
    reg  [WAY_W-1:0]        s1_mway;
    reg                     s1_mop;
    reg                     s1_sinv,  s2_sinv;
    reg  [SNP_ID_W-1:0]     s1_sid,   s2_sid;
    reg                     s2_hit;
    reg                     s2_scfail;
    reg                     s2_snp_hit, s2_hand;
    reg  [WAY_W-1:0]        s2_way;
    reg                     s2_vvalid, s2_vdirty, s2_vshared, s2_held, s2_swap, s2_wbpend;
    reg  [LINE_ADDR_W-1:0]  s2_vline;
    reg  [VC_ID_W-1:0]      s2_slot;
    wire                    rsv_sc_match;
    wire                    lock_valid, lock_snp;
    wire                    ev_amor;
    wire [LINE_ADDR_W-1:0]  lock_line;
    wire                 sel_valid;
    wire [SEAT_W-1:0]    sel_seat;
    wire [REQ_W-1:0]     sel_req;
    wire                 sn_sel_valid, sn_sel_inv;
    wire [SNP_ID_W-1:0]  sn_sel_id;
    wire [LINE_ADDR_W-1:0] sn_sel_line;
    wire                 pf_sel_valid;
    wire [LINE_ADDR_W-1:0] pf_sel_line;
    wire                 gnt_snoop, gnt_refill, gnt_maint, gnt_lsu, gnt_pf;
    wire                 gnt_fast;
    wire                 any_gnt = gnt_snoop || gnt_refill || gnt_maint || gnt_lsu || gnt_fast;
    wire [SEAT_W-1:0]    new_seat;
    wire [LSU_BUF_DEPTH-1:0] seat_blk;
    reg                  act_valid;
    reg  [2:0]           act_code;
    reg  [WID_W-1:0]     act_id;
    reg                  done_valid;
    reg  [SEAT_W-1:0]    done_seat;
    reg                  snp_act_valid;
    reg  [1:0]           snp_act_code;
    reg  [WID_W-1:0]     snp_act_id;
    wire [MSHR_ENTRIES-1:0] mshr_freed;
    wire [VC_SLOTS-1:0]     vc_freed;
    wire                    nc_freed;
    wire                    buf_empty;
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
    wire                   tok_valid;
    wire [MSHR_ID_W-1:0]   tok_id;
    wire [LINE_ADDR_W-1:0] tok_line;
    wire                   mt_valid;
    wire [INDEX_W-1:0]     mt_set;
    wire [WAY_W-1:0]       mt_way;
    wire                   mt_op;
    wire r_lsu  = r_valid  && (r_kind  == K_LSU);
    wire s1_lsu = s1_valid && (s1_kind == K_LSU);
    wire s2_lsu = s2_valid && (s2_kind == K_LSU);
    wire miss_push;
    wire m_resp_valid, n_resp_valid;
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
    wire miss_ok    = &port_miss_ok;
    wire lsu_credit = &port_grant_ok;
    wire r_amor_any  = r_lsu  && r_req[REQ_AMO_BIT]  && r_req[REQ_SEQ_BIT]  && !r_req[REQ_RDWR_BIT];
    wire s1_amor_any = s1_lsu && s1_req[REQ_AMO_BIT] && s1_req[REQ_SEQ_BIT] && !s1_req[REQ_RDWR_BIT];
    wire s2_amor_any = s2_lsu && s2_req[REQ_AMO_BIT] && s2_req[REQ_SEQ_BIT] && !s2_req[REQ_RDWR_BIT];
    wire amor_busy   = r_amor_any || s1_amor_any || s2_amor_any;
    wire snp_credit  = (snoop_response_fifo_free != {SNPR_CNT_W{1'b0}});
    reg                     s3_amo_v;
    reg  [LINE_ADDR_W-1:0]  s3_line;
    reg  [WAY_W-1:0]        s3_way;
    reg  [LINE_W-1:0]       s3_old;
    reg  [LINE_BYTES-1:0]   s3_be;
    reg  [OFFSET_W-1:0]     s3_off;
    reg  [WRITE_DATA_WIDTH-1:0] s3_new;
    reg  [LINE_W-1:0]       s3_merged;
    wire [INDEX_W-1:0]      s3_set = s3_line[LA_SET_LSB +: INDEX_W];
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
    wire [INDEX_W-1:0]     g_set    = g_line[LA_SET_LSB +: INDEX_W];
    wire [INDEX_W-1:0] s1_set = s1_line[LA_SET_LSB +: INDEX_W];
    wire [TAG_W-1:0]   s1_tag = s1_line[LA_TAG_LSB +: TAG_W];
    wire               s1_cache = s1_req[REQ_CACHE_BIT];
    wire               s1_store = (s1_req[REQ_RDWR_BIT] == OP_WRITE);
    wire               s1_amo   = s1_req[REQ_AMO_BIT];
    wire               s1_is_sc = s1_amo && !s1_req[REQ_SEQ_BIT] && s1_store;
    wire [OFFSET_W-1:0]        s1_off  = s1_req[REQ_ADDR_LSB +: OFFSET_W];
    wire [MEM_SIZE_BITS-1:0]   s1_size = s1_req[REQ_SIZE_LSB +: MEM_SIZE_BITS];
    wire [WRITE_DATA_WIDTH-1:0] s1_wdata = s1_req[REQ_DATA_LSB +: WRITE_DATA_WIDTH];
    wire               s1_refill = s1_valid && (s1_kind == K_REFILL);
    wire               s1_maint  = s1_valid && (s1_kind == K_MAINT);
    wire               s1_snp    = s1_valid && (s1_kind == K_SNOOP);
    wire [WAYS*TAG_W-1:0] tag_rd;
    wire                  tag_wr;
    wire [WAYS-1:0]       tag_we;
    wire [INDEX_W-1:0]    s2_set;
    l1d_tag_array #(.SETS(SETS), .WAYS(WAYS), .TAG_W(TAG_W), .INDEX_W(INDEX_W)) u_tags (
        .clk              (clk),
        .read_enable      (any_gnt),
        .read_set_index   (g_set),
        .way_write_enable (tag_wr ? tag_we : {WAYS{1'b0}}),
        .write_set_index  (s2_set),
        .write_tag        (s2_line[LA_TAG_LSB +: TAG_W]),
        .read_tags_flat   (tag_rd)
    );
    wire [WAYS*LINE_W-1:0] line_rd;
    wire [LINE_W-1:0]      q2_data;
    wire                   s2_refill;
    wire                   s2_st_wr;
    reg  [LINE_W-1:0]      st_merged;
    l1d_data_array #(.SETS(SETS), .WAYS(WAYS), .LINE_BYTES(LINE_BYTES), .INDEX_W(INDEX_W), .WAY_W(WAY_W)) u_data (
        .clk               (clk),
        .read_enable       (any_gnt),
        .write_enable      (s2_refill || s2_st_wr || s3_amo_v),
        .write_way         (s3_amo_v ? s3_way : s2_way),
        .read_set_index    (g_set),
        .write_set_index   (s3_amo_v ? s3_set : s2_set),
        .write_line        (s3_amo_v ? s3_merged : (s2_refill ? q2_data : st_merged)),
        .read_lines_flat   (line_rd)
    );
    wire [2*WAYS-1:0] m_states;
    wire [WAYS-2:0]   m_plru;
    wire              st_we;
    wire [WAY_W-1:0]  st_way;
    wire [1:0]        st_val;
    wire              pl_we;
    wire [WAYS-2:0]   plru_new;
    l1d_meta_flops #(.SETS(SETS), .WAYS(WAYS), .INDEX_W(INDEX_W), .WAY_W(WAY_W)) u_meta (
        .clk                  (clk),
        .rst                  (rst),
        .read_set             (s1_set),
        .read_way_states_flat (m_states),
        .read_plru_bits       (m_plru),
        .state_write_enable   (st_we),
        .state_write_set      (s1_set),
        .state_write_way      (st_way),
        .state_write_value    (st_val),
        .plru_write_enable    (pl_we),
        .plru_write_set       (s1_set),
        .plru_write_value     (plru_new)
    );
    wire             hit;
    wire [WAY_W-1:0] hit_way, victim_way, vict_way;
    wire [WAY_W-1:0] acc_way = (s1_kind == K_LSU) ? hit_way : vict_way;
    l1d_s1_lookup #(.WAYS(WAYS), .TAG_W(TAG_W), .WAY_W(WAY_W)) u_lookup (
        .way_tags_flat   (tag_q),
        .way_states_flat (m_states),
        .plru_bits       (m_plru),
        .lookup_tag      (s1_tag),
        .accessed_way    (acc_way),
        .hit             (hit),
        .hit_way         (hit_way),
        .victim_way      (victim_way),
        .plru_bits_next  (plru_new)
    );
    wire [1:0] hit_st = m_states[2*hit_way +: 2];
    wire [1:0]         q1_state;
    wire               q1_swap;
    wire [VC_ID_W-1:0] q1_slot;
    wire               vc_al_ok;
    wire [VC_ID_W-1:0] vc_al_slot;
    wire s2_lrsc   = s2_lsu && s2_req[REQ_AMO_BIT] && !s2_req[REQ_SEQ_BIT];
    wire sc_ok     = rsv_sc_match && !s2_lrsc;
    wire s1_live   = s1_lsu && !s1_kill;
    wire s1_scfail = s1_live && s1_cache && s1_is_sc && !sc_ok;
    wire s1_lsu_th = s1_live && s1_cache && hit && !s1_scfail;
    wire [LINE_ADDR_W-1:0] v0_line  = {tag_q[victim_way*TAG_W +: TAG_W], s1_set, BANK_C};
    wire                   v_locked = lock_valid && (v0_line == lock_line);
    assign                 vict_way = v_locked ? (victim_way ^ {{(WAY_W-1){1'b0}}, 1'b1}) : victim_way;
    wire [1:0]             v_st     = m_states[2*vict_way +: 2];
    wire                   v_valid  = (v_st != ST_I);
    wire                   v_dirty  = (v_st == ST_M);
    wire [LINE_ADDR_W-1:0] v_line   = {tag_q[vict_way*TAG_W +: TAG_W], s1_set, BANK_C};
    wire [VC_ID_W-1:0]     r_slot   = q1_swap ? q1_slot : vc_al_slot;
    wire                   r_held   = s1_refill && v_valid && !q1_swap && !vc_al_ok;
    wire [1:0]             mt_st    = m_states[2*s1_mway +: 2];
    wire                   mt_dirty = (mt_st == ST_M);
    wire [LINE_ADDR_W-1:0] mt_vline = {tag_q[s1_mway*TAG_W +: TAG_W], s1_set, BANK_C};
    wire                   m_held   = s1_maint && mt_dirty && !vc_al_ok;
    reg  [3:0] m_ev;
    reg  [1:0] m_cur;
    wire [1:0] m_nxt;
    wire       m_we, m_upg, m_hand;
    always @* begin
        m_ev  = EV_NONE;
        m_cur = hit_st;
        if (s1_lsu_th)
            m_ev = s1_store ? EV_WRITE_HIT : (s1_amo ? EV_UNIQ_HIT : EV_LOAD_HIT);
        else if (s1_refill && !r_held)
            m_ev = EV_INSTALL;
        else if (s1_maint && !m_held) begin
            m_ev  = (s1_mop == MAINT_FLUSH) ? EV_FLUSH : EV_CLEAN;
            m_cur = mt_st;
        end else if (s1_snp && hit)
            m_ev = s1_sinv ? EV_SNP_INV : EV_SNP_READ;
    end
    l1d_mesi_next u_mesi (
        .event_code            (m_ev),
        .current_state         (m_cur),
        .install_state         (q1_state),
        .next_state            (m_nxt),
        .state_write_enable    (m_we),
        .upgrade_needed        (m_upg),
        .snoop_hands_over_data (m_hand)
    );
    wire s1_hit = s1_lsu_th && !m_upg;
    wire [WAY_W-1:0] s1_way = (s1_kind == K_REFILL) ? vict_way :
                              (s1_kind == K_MAINT)  ? s1_mway : hit_way;
    assign st_we  = m_we;
    assign st_way = s1_way;
    assign st_val = m_nxt;
    assign pl_we  = s1_hit || (s1_refill && !r_held);
    reg  [LINE_BYTES-1:0] st_be;
    wire [LINE_W-1:0]     st_wext = s1_wdata;
    wire [LINE_W-1:0]     st_din  = st_wext << {s1_off, 3'b000};
    integer bi;
    integer nby;
    always @* begin
        nby = 1 << s1_size;
        for (bi = 0; bi < LINE_BYTES; bi = bi + 1)
            st_be[bi] = (bi >= s1_off) && (bi < s1_off + nby);
    end
    wire [WAYS*WRITE_DATA_WIDTH-1:0] s1_words;
    genvar gwd;
    generate
        for (gwd = 0; gwd < WAYS; gwd = gwd + 1) begin : g_word
            l1d_resp_gen #(.IN_BYTES(LINE_BYTES), .WRITE_DATA_WIDTH(WRITE_DATA_WIDTH),
                           .MEM_SIZE_BITS(MEM_SIZE_BITS), .OFF_W(OFFSET_W)) u_word (
                .source_block (s1_lines[gwd*LINE_W +: LINE_W]), .byte_offset (s1_off), .access_size (s1_size),
                .load_data    (s1_words[gwd*WRITE_DATA_WIDTH +: WRITE_DATA_WIDTH])
            );
        end
    endgenerate
    reg                   wl_valid_q;
    reg [LINE_ADDR_W-1:0] wl_line_q;
    always @(posedge clk) begin
        if (rst) wl_valid_q <= 1'b0;
        else     wl_valid_q <= s2_st_wr || s3_amo_v;
        wl_line_q <= s3_amo_v ? s3_line : s2_line;
    end
    wire wl_hit = wl_valid_q && (r_line == wl_line_q);
    wire amo_hit = s3_amo_v && (r_line == s3_line);
    wire r_kill = r_lsu && ((r_fast && seat_blk[r_seat]) || wl_hit || amo_hit);
    always @(posedge clk) begin
        if (rst) begin
            r_valid  <= 1'b0;
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
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
            s1_valid <= r_valid;
            s1_kind  <= r_kind;
            s1_seat  <= r_seat;
            s1_req   <= r_req;
            s1_mid   <= r_mid;
            s1_line  <= r_line;
            s1_mway  <= r_mway;
            s1_mop   <= r_mop;
            s1_sinv  <= r_sinv;
            s1_sid   <= r_sid;
            s1_kill  <= r_kill;
            tag_q    <= tag_rd;
            s1_lines <= line_rd;
            s2_valid   <= s1_valid;
            s2_kind    <= s1_kind;
            s2_seat    <= s1_seat;
            s2_req     <= s1_req;
            s2_mid     <= s1_mid;
            s2_line    <= s1_line;
            s2_sinv    <= s1_sinv;
            s2_sid     <= s1_sid;
            s2_hit     <= s1_hit;
            s2_scfail  <= s1_scfail;
            s2_snp_hit <= s1_snp && hit;
            s2_hand    <= m_hand;
            s2_way     <= s1_way;
            s2_held    <= r_held || m_held;
            s2_swap    <= q1_swap;
            s2_kill    <= s1_kill;
            s2_words   <= s1_words;
            s2_lines   <= s1_lines;
            s2_st_be   <= st_be;
            s2_st_din  <= st_din;
            s2_wbpend  <= s1_maint;
            if (s1_maint) begin
                s2_vvalid  <= mt_dirty;
                s2_vdirty  <= 1'b1;
                s2_vshared <= 1'b0;
                s2_vline   <= mt_vline;
                s2_slot    <= vc_al_slot;
            end else begin
                s2_vvalid  <= v_valid;
                s2_vdirty  <= v_dirty;
                s2_vshared <= (v_st == ST_S);
                s2_vline   <= v_line;
                s2_slot    <= r_slot;
            end
        end
    end
    assign s2_set = s2_line[LA_SET_LSB +: INDEX_W];
    wire               s2_cache  = s2_req[REQ_CACHE_BIT];
    wire               s2_store  = (s2_req[REQ_RDWR_BIT] == OP_WRITE);
    wire               s2_amo    = s2_req[REQ_AMO_BIT];
    wire               s2_seq    = s2_req[REQ_SEQ_BIT];
    wire               s2_is_lr  = s2_amo && !s2_seq && !s2_store;
    wire               s2_is_sc  = s2_amo && !s2_seq &&  s2_store;
    wire               s2_is_amr = s2_amo &&  s2_seq && !s2_store;
    wire               s2_is_amw = s2_amo &&  s2_seq &&  s2_store;
    wire               s2_uniq   = s2_store || s2_amo;
    wire               s2_amo1   = s2_amo && s2_seq;
    wire [ADDR_W-1:0]  s2_addr   = s2_req[REQ_ADDR_LSB +: ADDR_W];
    wire [OFFSET_W-1:0]         s2_off   = s2_addr[OFFSET_W-1:0];
    wire [MEM_SIZE_BITS-1:0]    s2_size  = s2_req[REQ_SIZE_LSB +: MEM_SIZE_BITS];
    wire [MASTER_ID_BITS-1:0]   s2_mstid = s2_req[REQ_MID_LSB +: MASTER_ID_BITS];
    wire [IDX_BITS-1:0]         s2_idx   = s2_req[REQ_IDX_LSB +: IDX_BITS];
    wire [PORT_W-1:0]           s2_port  = s2_req[REQ_PORT_LSB +: PORT_W];
    wire [WRITE_DATA_WIDTH-1:0] s2_wdata = s2_req[REQ_DATA_LSB +: WRITE_DATA_WIDTH];
    assign s2_refill = s2_valid && (s2_kind == K_REFILL) && !s2_held;
    wire s2_maint  = s2_valid && (s2_kind == K_MAINT);
    wire s2_snp    = s2_valid && (s2_kind == K_SNOOP);
    assign s2_st_wr  = s2_lsu && s2_hit && s2_store && !s2_amo1;
    reg [LINE_W-1:0] line_q;
    integer lw;
    always @* begin
        line_q = {LINE_W{1'b0}};
        for (lw = 0; lw < WAYS; lw = lw + 1)
            line_q = line_q | ({LINE_W{s2_way == lw}} & s2_lines[lw*LINE_W +: LINE_W]);
    end
    integer mb;
    always @* begin
        for (mb = 0; mb < LINE_BYTES; mb = mb + 1)
            st_merged[mb*8 +: 8] = s2_st_be[mb] ? s2_st_din[mb*8 +: 8] : line_q[mb*8 +: 8];
    end
    assign tag_wr = s2_refill;
    genvar gw;
    generate
        for (gw = 0; gw < WAYS; gw = gw + 1) begin : g_tagwe
            assign tag_we[gw] = (s2_way == gw);
        end
    endgenerate
    wire [LINE_W-1:0]           vc_data;
    wire [WRITE_DATA_WIDTH-1:0] vcl_data;
    reg  [WRITE_DATA_WIDTH-1:0] hit_data;
    integer hw;
    always @* begin
        hit_data = {WRITE_DATA_WIDTH{1'b0}};
        for (hw = 0; hw < WAYS; hw = hw + 1)
            hit_data = hit_data | ({WRITE_DATA_WIDTH{s2_way == hw}} & s2_words[hw*WRITE_DATA_WIDTH +: WRITE_DATA_WIDTH]);
    end
    l1d_resp_gen #(.IN_BYTES(LINE_BYTES), .WRITE_DATA_WIDTH(WRITE_DATA_WIDTH),
                   .MEM_SIZE_BITS(MEM_SIZE_BITS), .OFF_W(OFFSET_W)) u_vc_data (
        .source_block (vc_data), .byte_offset (s2_off), .access_size (s2_size), .load_data (vcl_data)
    );
    wire                 mshr_hit, mshr_can, mshr_hasd;
    wire [MSHR_ID_W-1:0] mshr_hid, mshr_aid;
    wire                 vc_hit, vc_dirty, vc_shared;
    wire [VC_ID_W-1:0]   vc_slot;
    wire [2:0]           vc_state;
    wire                 nc_can;
    reg  s3_load;
    reg  s3_from_vc;
    reg  s3_scfail;
    reg  s3_zero;
    reg  m_alloc, m_swap;
    reg  vc_swap;
    reg  n_alloc;
    always @* begin
        s3_load    = 1'b0;
        s3_from_vc = 1'b0;
        s3_scfail  = 1'b0;
        s3_zero    = 1'b0;
        m_alloc    = 1'b0;
        m_swap     = 1'b0;
        vc_swap    = 1'b0;
        n_alloc    = 1'b0;
        act_valid  = 1'b0;
        act_code   = ACT_NONE;
        act_id     = {WID_W{1'b0}};
        if (s2_lsu && s2_kill) begin
            act_valid = 1'b1;
            act_code  = ACT_NONE;
        end else if (s2_lsu) begin
            if (!s2_cache) begin
                if (s2_is_sc) begin
                    s3_load   = 1'b1;
                    s3_scfail = 1'b1;
                end else if (s2_amo1) begin
                    s3_load = 1'b1;
                    s3_zero = 1'b1;
                end else begin
                    act_valid = 1'b1;
                    if (nc_can) begin
                        n_alloc  = 1'b1;
                        act_code = ACT_OWNED;
                    end else begin
                        act_code = ACT_WNC;
                    end
                end
            end else if (s2_scfail) begin
                s3_load   = 1'b1;
                s3_scfail = 1'b1;
            end else if (s2_hit) begin
                s3_load = 1'b1;
            end else if (mshr_hit) begin
                act_valid = 1'b1;
                act_code  = ACT_WMSHR;
                act_id    = mshr_hid;
            end else if (vc_hit && vc_state == VC_VALID) begin
                if (!s2_uniq) begin
                    s3_load    = 1'b1;
                    s3_from_vc = 1'b1;
                    if (mshr_can) begin
                        m_alloc = 1'b1;
                        m_swap  = 1'b1;
                        vc_swap = 1'b1;
                    end
                end else begin
                    act_valid = 1'b1;
                    if (mshr_can) begin
                        m_alloc  = 1'b1;
                        m_swap   = 1'b1;
                        vc_swap  = 1'b1;
                        act_code = ACT_WMSHR;
                        act_id   = mshr_aid;
                    end else begin
                        act_code = ACT_WANY;
                    end
                end
            end else if (vc_hit && vc_state == VC_WBPEND) begin
                if (!s2_uniq) begin
                    s3_load    = 1'b1;
                    s3_from_vc = 1'b1;
                end else begin
                    act_valid = 1'b1;
                    act_code  = ACT_WVC;
                    act_id    = vc_slot;
                end
            end else if (vc_hit) begin
                act_valid = 1'b1;
                act_code  = ACT_WANY;
            end else begin
                act_valid = 1'b1;
                if (mshr_can) begin
                    m_alloc  = 1'b1;
                    if (s2_amo1) begin
                        act_code = ACT_WMSHR;
                        act_id   = mshr_aid;
                    end else begin
                        act_code = ACT_OWNED;
                    end
                end else begin
                    act_code = ACT_WANY;
                end
            end
        end
    end
    wire [WRITE_DATA_WIDTH-1:0] s2_rdata = s3_scfail ? SC_FAIL_W :
                                           s3_zero   ? {WRITE_DATA_WIDTH{1'b0}} :
                                           (s2_store && !s2_amo1) ? {WRITE_DATA_WIDTH{1'b0}} :
                                           (s3_from_vc ? vcl_data : hit_data);
    wire [RESP_W-1:0] s2_pkt = {s2_port, (s2_req[REQ_RDWR_BIT] && !s2_amo1), s2_size, s2_mstid, s2_idx, s2_rdata};
    wire s2_done_lsu = s2_lsu && (s3_load || (act_valid && act_code == ACT_OWNED));
    wire ev_lr   = s2_done_lsu && s2_cache && s2_is_lr;
    assign rsv_event_pulse = ev_lr || ev_sc;
    wire ev_sc   = s2_done_lsu && s2_is_sc;
    wire ev_wr   = s2_done_lsu && s2_cache && s2_store && !s2_is_sc;
    assign ev_amor = 1'b0;
    wire ev_amow = 1'b0;
    wire [WRITE_DATA_WIDTH-1:0] amo_new;
    l1d_amo_alu #(.W(WRITE_DATA_WIDTH), .MEM_SIZE_BITS(MEM_SIZE_BITS)) u_amo (
        .amo_op      (s2_req[REQ_AMOOP_LSB +: AMOOP_W]),
        .access_size (s2_size),
        .old_value   (hit_data),
        .operand     (s2_wdata),
        .new_value   (amo_new)
    );
    always @(posedge clk) begin
        if (rst) s3_amo_v <= 1'b0;
        else     s3_amo_v <= s2_lsu && s2_hit && s2_amo1;
        s3_line <= s2_line;
        s3_way  <= s2_way;
        s3_old  <= line_q;
        s3_be   <= s2_st_be;
        s3_off  <= s2_off;
        s3_new  <= amo_new;
    end
    wire [LINE_W-1:0] s3_din = {{(LINE_W-WRITE_DATA_WIDTH){1'b0}}, s3_new} << {s3_off, 3'b000};
    integer ab;
    always @* begin
        for (ab = 0; ab < LINE_BYTES; ab = ab + 1)
            s3_merged[ab*8 +: 8] = s3_be[ab] ? s3_din[ab*8 +: 8] : s3_old[ab*8 +: 8];
    end
    reg  snp_push;
    reg  snp_present, snp_dirty, snp_from_vc;
    reg  vc_snp;
    always @* begin
        snp_push      = 1'b0;
        snp_present   = 1'b0;
        snp_dirty     = 1'b0;
        snp_from_vc   = 1'b0;
        vc_snp        = 1'b0;
        snp_act_valid = 1'b0;
        snp_act_code  = SACT_DONE;
        snp_act_id    = {WID_W{1'b0}};
        if (s2_snp) begin
            snp_act_valid = 1'b1;
            if (s2_snp_hit) begin
                snp_push    = 1'b1;
                snp_present = 1'b1;
                snp_dirty   = s2_hand;
            end else if (mshr_hit) begin
                if (mshr_hasd) begin
                    snp_act_code = SACT_WMSHR;
                    snp_act_id   = mshr_hid;
                end else begin
                    snp_push = 1'b1;
                end
            end else if (vc_hit && vc_state == VC_VALID) begin
                snp_push    = 1'b1;
                snp_present = 1'b1;
                snp_dirty   = vc_dirty;
                snp_from_vc = 1'b1;
                vc_snp      = 1'b1;
            end else if (vc_hit && vc_state == VC_WBPEND) begin
                snp_act_code = SACT_WVC;
                snp_act_id   = vc_slot;
            end else if (vc_hit) begin
                snp_act_code = SACT_WMSHR;
                snp_act_id   = mshr_hid;
            end else begin
                snp_push = 1'b1;
            end
        end
    end
    assign snoop_response_valid = snp_push;
    assign snoop_response_packet   = {snp_present, snp_dirty, s2_line, (snp_from_vc ? vc_data : line_q)};
    wire s1_evict = (RSV_CLR_ON_EVICT != 0) && s1_refill && !r_held && v_valid;
    l1d_reservation_unit #(`L1D_PARAMS_PASS) u_rsv (
        .clk                    (clk),
        .rst                    (rst),
        .sc_check_line_addr     (s1_line),
        .sc_reservation_matches (rsv_sc_match),
        .s2_line_addr           (s2_line),
        .s2_lr_completed        (ev_lr),
        .s2_sc_completed        (ev_sc),
        .s2_write_completed     (ev_wr),
        .s2_amo_read_completed  (ev_amor),
        .s2_amo_read_was_hit    (s2_hit),
        .s2_amo_write_completed (ev_amow),
        .s2_install_valid       (s2_refill),
        .s2_install_line_addr   (s2_line),
        .s1_clear_valid         (s1_snp || s1_evict),
        .s1_clear_line_addr     (s1_snp ? s1_line : v_line),
        .maint_clear            (maint_start),
        .other_bank_rsv_clear   (other_bank_rsv_event),
        .reservation_valid      (),
        .reservation_line_addr  (),
        .amo_lock_valid         (lock_valid),
        .amo_lock_snoop_hold    (lock_snp),
        .amo_lock_line          (lock_line),
        .amo_lock_timeout_pulse (amo_lock_timeout_pulse)
    );
    wire                   m_rd_valid, m_rd_ready, m_rd_unique;
    wire [LINE_ADDR_W-1:0] m_rd_line;
    wire [MSHR_ID_W-1:0]   m_rd_sub;
    wire                   m_resp_ack;
    wire [RESP_W-1:0]      m_resp_pkt;
    wire [SEAT_W-1:0]      m_resp_seat;
    wire                   mshr_busy;
    l1d_mshr #(`L1D_PARAMS_PASS) u_mshr (
        .clk                      (clk),
        .rst                      (rst),
        .lookup_line_addr         (s2_line),
        .lookup_hit               (mshr_hit),
        .lookup_entry_id          (mshr_hid),
        .lookup_entry_has_data    (mshr_hasd),
        .allocate_valid           (m_alloc),
        .allocate_line_addr       (s2_line),
        .allocate_is_swap         (m_swap),
        .allocate_swap_line_data  (vc_data),
        .allocate_swap_dirty      (vc_dirty),
        .allocate_swap_shared     (vc_shared),
        .allocate_swap_vc_slot    (vc_slot),
        .allocate_unique_read     (s2_uniq),
        .allocate_seat            (s2_seat),
        .allocate_is_write        (s2_req[REQ_RDWR_BIT] && !s2_amo1),
        .allocate_no_response     (s2_amo1),
        .allocate_access_size     (s2_size),
        .allocate_master_id       (s2_mstid),
        .allocate_rob_index       (s2_idx),
        .allocate_port            (s2_port),
        .allocate_byte_offset     (s2_off),
        .allocate_store_data      (s2_wdata),
        .can_allocate             (mshr_can),
        .allocate_entry_id        (mshr_aid),
        .axi_read_req_valid       (m_rd_valid),
        .axi_read_req_ready       (m_rd_ready),
        .axi_read_req_line_addr   (m_rd_line),
        .axi_read_req_sub_id      (m_rd_sub),
        .axi_read_req_unique      (m_rd_unique),
        .axi_read_beat_valid      (axi_read_data_valid && !axi_read_data_non_cacheable),
        .axi_read_beat_sub_id     (axi_read_data_sub_id[MSHR_ID_W-1:0]),
        .axi_read_beat_data       (axi_read_data),
        .axi_read_beat_last       (axi_read_data_last),
        .axi_read_beat_error      (axi_read_data_error),
        .axi_read_beat_shared     (axi_read_data_shared),
        .response_valid           (m_resp_valid),
        .response_packet          (m_resp_pkt),
        .response_seat            (m_resp_seat),
        .response_taken           (m_resp_ack),
        .refill_token_valid       (tok_valid),
        .refill_token_entry_id    (tok_id),
        .refill_token_line_addr   (tok_line),
        .refill_token_granted     (gnt_refill),
        .s1_install_entry_id      (s1_mid),
        .s1_install_state         (q1_state),
        .s1_install_is_swap       (q1_swap),
        .s1_install_vc_slot       (q1_slot),
        .s2_install_entry_id      (s2_mid),
        .s2_install_line_data     (q2_data),
        .s1_token_held_valid      (r_held),
        .s1_token_held_entry_id   (s1_mid),
        .s2_install_done_valid    (s2_refill),
        .s2_install_done_entry_id (s2_mid),
        .any_entry_busy           (mshr_busy),
        .entry_freed_pulses       (mshr_freed)
    );
    wire                        n_rd_valid, n_rd_ready, n_wr_valid, n_wr_ready;
    wire [ADDR_W-1:0]           n_rd_addr, n_wr_addr;
    wire [2:0]                  n_rd_size, n_wr_size;
    wire [AXI_DATA_W-1:0]       n_wr_data;
    wire [AXI_STRB_W-1:0]       n_wr_strb;
    wire                        n_resp_ack;
    wire [RESP_W-1:0]           n_resp_pkt;
    wire [SEAT_W-1:0]           n_resp_seat;
    wire                        nc_empty;
    l1d_mshr_nc #(`L1D_PARAMS_PASS) u_nc (
        .clk                  (clk),
        .rst                  (rst),
        .allocate_valid       (n_alloc),
        .allocate_seat        (s2_seat),
        .allocate_is_write    (s2_req[REQ_RDWR_BIT]),
        .allocate_access_size (s2_size),
        .allocate_master_id   (s2_mstid),
        .allocate_rob_index   (s2_idx),
        .allocate_port        (s2_port),
        .allocate_addr        (s2_addr),
        .allocate_store_data  (s2_wdata),
        .can_allocate         (nc_can),
        .axi_read_req_valid   (n_rd_valid),
        .axi_read_req_ready   (n_rd_ready),
        .axi_read_req_addr    (n_rd_addr),
        .axi_read_req_size    (n_rd_size),
        .axi_read_beat_valid  (axi_read_data_valid && axi_read_data_non_cacheable),
        .axi_read_beat_data   (axi_read_data),
        .axi_read_beat_error  (axi_read_data_error),
        .axi_write_req_valid  (n_wr_valid),
        .axi_write_req_ready  (n_wr_ready),
        .axi_write_req_addr   (n_wr_addr),
        .axi_write_req_size   (n_wr_size),
        .axi_write_req_data   (n_wr_data),
        .axi_write_req_strobe (n_wr_strb),
        .axi_write_resp_valid (axi_write_resp_valid && axi_write_resp_non_cacheable),
        .axi_write_resp_error (axi_write_resp_error),
        .response_valid       (n_resp_valid),
        .response_packet      (n_resp_pkt),
        .response_seat        (n_resp_seat),
        .response_taken       (n_resp_ack),
        .queue_empty          (nc_empty),
        .entry_freed_pulse    (nc_freed)
    );
    wire                   vc_wr_valid, vc_wr_ready;
    wire [LINE_ADDR_W-1:0] vc_wr_line;
    wire [VC_ID_W-1:0]     vc_wr_sub;
    wire [LINE_W-1:0]      vc_wr_data;
    wire                   vc_empty, vc_drain;
    wire vc_ins = (s2_refill && s2_vvalid) || (s2_maint && !s2_held && s2_vvalid);
    wire vc_rel = s2_refill && s2_swap && !s2_vvalid;
    l1d_victim_cache #(`L1D_PARAMS_PASS) u_vc (
        .clk                         (clk),
        .rst                         (rst),
        .lookup_line_addr_next       (s1_line),
        .lookup_line_addr            (s2_line),
        .lookup_hit                  (vc_hit),
        .lookup_slot                 (vc_slot),
        .lookup_slot_state           (vc_state),
        .lookup_line_data            (vc_data),
        .lookup_dirty                (vc_dirty),
        .lookup_shared               (vc_shared),
        .victim_slot_available       (vc_al_ok),
        .victim_slot_index           (vc_al_slot),
        .insert_valid                (vc_ins),
        .insert_slot                 (s2_slot),
        .insert_line_addr            (s2_vline),
        .insert_line_data            (line_q),
        .insert_dirty                (s2_vdirty),
        .insert_shared               (s2_vshared),
        .insert_as_writeback_pending (s2_wbpend),
        .swap_start_valid            (vc_swap),
        .swap_start_slot             (vc_slot),
        .release_valid               (vc_rel),
        .release_slot                (s2_slot),
        .snoop_hit_valid             (vc_snp),
        .snoop_hit_slot              (vc_slot),
        .snoop_invalidate            (s2_sinv),
        .drain_enable                (vc_drain),
        .writeback_req_valid         (vc_wr_valid),
        .writeback_req_ready         (vc_wr_ready),
        .writeback_req_line_addr     (vc_wr_line),
        .writeback_req_slot_id       (vc_wr_sub),
        .writeback_req_data          (vc_wr_data),
        .writeback_done_valid        (axi_write_resp_valid && !axi_write_resp_non_cacheable),
        .writeback_done_slot_id      (axi_write_resp_sub_id[VC_ID_W-1:0]),
        .all_slots_free              (vc_empty),
        .slot_freed_pulses           (vc_freed)
    );
    wire bank_idle = buf_empty && !r_valid && !s1_valid && !s2_valid && !s3_amo_v && !mshr_busy && nc_empty && !lock_valid;
    l1d_maint #(`L1D_PARAMS_PASS) u_maint (
        .clk                (clk),
        .rst                (rst),
        .maint_start        (maint_start),
        .maint_op_is_flush  (maint_op_is_flush),
        .bank_idle          (bank_idle),
        .victim_cache_empty (vc_empty),
        .victim_cache_drain (vc_drain),
        .token_valid        (mt_valid),
        .token_set          (mt_set),
        .token_way          (mt_way),
        .token_op_is_flush  (mt_op),
        .token_granted      (gnt_maint),
        .s2_result_valid    (s2_maint),
        .s2_result_held     (s2_held),
        .maint_done         (maint_done),
        .maint_busy         ()
    );
    wire s2_push = s3_load;
    wire m_take = !s2_push && m_resp_valid && miss_ok;
    wire n_take = !s2_push && !m_resp_valid && n_resp_valid && miss_ok;
    assign miss_push  = m_take || n_take;
    assign m_resp_ack = m_take;
    assign n_resp_ack = n_take;
    assign lsu_response_valid  = s2_push || miss_push;
    assign lsu_response_packet = s2_push ? s2_pkt : (m_take ? m_resp_pkt : n_resp_pkt);
    always @* begin
        done_valid = lsu_response_valid;
        done_seat  = s2_push ? s2_seat : (m_take ? m_resp_seat : n_resp_seat);
    end
    wire [ADDR_W-1:0] m_rd_addr = {m_rd_line, OFF0};
    wire [ADDR_W-1:0] rd_addr_w = m_rd_valid ? m_rd_addr : n_rd_addr;
    assign axi_read_req_valid   = m_rd_valid || n_rd_valid;
    assign m_rd_ready = axi_read_req_ready && m_rd_valid;
    assign n_rd_ready = axi_read_req_ready && !m_rd_valid;
    assign axi_read_req_addr    = rd_addr_w;
    assign axi_read_req_burst_len     = m_rd_valid ? LEN_C : 8'd0;
    assign axi_read_req_size    = m_rd_valid ? SIZE_C : n_rd_size;
    assign axi_read_req_sub_id     = m_rd_valid ? m_rd_sub : {AXI_SUBID_W{1'b0}};
    assign axi_read_req_non_cacheable      = !m_rd_valid;
    assign axi_read_req_unique  = m_rd_valid && m_rd_unique;
    wire [ADDR_W-1:0] vc_wr_addr = {vc_wr_line, OFF0};
    wire [ADDR_W-1:0] wr_addr_w  = vc_wr_valid ? vc_wr_addr : n_wr_addr;
    wire [LINE_W-1:0] n_wr_line  = n_wr_data;
    assign axi_write_req_valid    = vc_wr_valid || n_wr_valid;
    assign vc_wr_ready = axi_write_req_ready && vc_wr_valid;
    assign n_wr_ready  = axi_write_req_ready && !vc_wr_valid;
    assign axi_write_req_addr     = wr_addr_w;
    assign axi_write_req_burst_len      = vc_wr_valid ? LEN_C : 8'd0;
    assign axi_write_req_size     = vc_wr_valid ? SIZE_C : n_wr_size;
    assign axi_write_req_sub_id      = vc_wr_valid ? vc_wr_sub : {AXI_SUBID_W{1'b0}};
    assign axi_write_req_non_cacheable       = !vc_wr_valid;
    assign axi_write_req_data     = vc_wr_valid ? vc_wr_data : n_wr_line;
    assign axi_write_req_strobe     = vc_wr_valid ? {AXI_STRB_W{1'b1}} : n_wr_strb;
`ifdef L1D_DEBUG
    integer dbg_s0w, dbg_mrw, dbg_nrw;
    initial begin dbg_s0w = 0; dbg_mrw = 0; dbg_nrw = 0; end
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
            if (r_kill)
                $display("[%0t] L1D B%0d R  fast issue seat=%0d CANCELLED (seat blocked by an older same-line request / AMO rule): back to READY",
                         $time, BANK_ID, r_seat);
            if (sel_valid && !gnt_lsu) begin
                dbg_s0w = dbg_s0w + 1;
                if (dbg_s0w % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D B%0d S0 STUCK seat %0d ready but not granted for %0d cycles: snoop=%b refill_token=%b maint_token=%b credit=%b (resp_free per port=%h, port credit ok=%b); if all 0 it is the skip after a refill",
                             $time, BANK_ID, sel_seat, dbg_s0w, gnt_snoop, tok_valid, mt_valid, lsu_credit, lsu_response_fifo_free, port_grant_ok);
            end else begin
                dbg_s0w = 0;
            end
            if (s1_lsu)
                $display("[%0t] L1D B%0d S1 LSU  seat=%0d idx=%0d %0s %s addr=%h set=%0d tag=%h -> %s way=%0d state=%0d%s%s%s",
                         $time, BANK_ID, s1_seat, s1_req[REQ_IDX_LSB +: IDX_BITS],
                         dbg_cls(s1_req), (s1_cache ? "C " : "NC"),
                         s1_req[REQ_ADDR_LSB +: ADDR_W], s1_set, s1_tag,
                         (!s1_cache ? "non-cacheable" : (hit ? "HIT" : "MISS")), hit_way, hit_st,
                         (s1_hit && s1_store) ? " (byte write)" : "",
                         m_upg ? " (S copy dropped: upgrade, unique fetch)" : "",
                         s1_scfail ? " (SC: no reservation -> fail)" : "");
            if (s1_refill)
                $display("[%0t] L1D B%0d S1 REFILL mshr=%0d line=%h set=%0d victim way=%0d state=%0d victim_line=%h swap=%b vc_slot=%0d (vc_room=%b) install state=%0d%s%s",
                         $time, BANK_ID, s1_mid, {s1_line, OFF0}, s1_set, vict_way, v_st,
                         {v_line, OFF0}, q1_swap, r_slot, vc_al_ok, q1_state,
                         v_locked ? " (PLRU victim is AMO-locked: other way taken)" : "",
                         r_held ? " -> HELD (no victim-cache slot)" : "");
            if (s1_maint)
                $display("[%0t] L1D B%0d S1 MAINT set=%0d way=%0d state=%0d dirty=%b%s",
                         $time, BANK_ID, s1_set, s1_mway, mt_st, mt_dirty, m_held ? " -> HELD (no victim-cache slot)" : "");
            if (s1_snp)
                $display("[%0t] L1D B%0d S1 SNOOP %s line=%h -> %s way=%0d state %0d -> %0d%s",
                         $time, BANK_ID, s1_sinv ? "INV" : "READ", {s1_line, OFF0}, hit ? "HIT" : "tag miss",
                         hit_way, hit_st, hit ? m_nxt : hit_st, m_hand ? " (M: data handed over)" : "");
            if (s2_lsu) begin
                if (!s2_cache)
                    $display("[%0t] L1D B%0d S2 LSU  idx=%0d NC %0s addr=%h -> %s",
                             $time, BANK_ID, s2_idx, dbg_cls(s2_req), s2_addr,
                             s3_scfail ? "SC fail (non-cacheable)" :
                             (n_alloc ? "NC queue" : "NC queue full, seat waits (WNC)"));
                else if (s2_scfail)
                    $display("[%0t] L1D B%0d S2 LSU  idx=%0d SC addr=%h -> FAIL (answer 1)", $time, BANK_ID, s2_idx, s2_addr);
                else if (s2_hit)
                    $display("[%0t] L1D B%0d S2 LSU  idx=%0d %0s addr=%h -> HIT way=%0d data=%h",
                             $time, BANK_ID, s2_idx, dbg_cls(s2_req), s2_addr, s2_way, s2_rdata);
                else if (mshr_hit)
                    $display("[%0t] L1D B%0d S2 LSU  idx=%0d %0s addr=%h -> MISS, line already in MSHR %0d: seat waits (WMSHR)",
                             $time, BANK_ID, s2_idx, dbg_cls(s2_req), s2_addr, mshr_hid);
                else if (vc_hit)
                    $display("[%0t] L1D B%0d S2 LSU  idx=%0d %0s addr=%h -> victim-cache hit slot=%0d state=%0d: answer=%b swap=%b act=%0d",
                             $time, BANK_ID, s2_idx, dbg_cls(s2_req), s2_addr, vc_slot, vc_state,
                             s3_load, m_swap, act_code);
                else if (m_alloc)
                    $display("[%0t] L1D B%0d S2 LSU  idx=%0d %0s addr=%h -> MISS: MSHR entry %0d allocated, %s fetch of line %h",
                             $time, BANK_ID, s2_idx, dbg_cls(s2_req), s2_addr, mshr_aid,
                             s2_uniq ? "unique" : "shared", {s2_line, OFF0});
                else
                    $display("[%0t] L1D B%0d S2 LSU  idx=%0d %0s addr=%h -> MISS, all MSHR entries busy: seat waits (WANY)",
                             $time, BANK_ID, s2_idx, dbg_cls(s2_req), s2_addr);
            end
            if (s2_valid && s2_kind == K_REFILL)
                $display("[%0t] L1D B%0d S2 REFILL mshr=%0d line=%h %s",
                         $time, BANK_ID, s2_mid, {s2_line, OFF0},
                         s2_held ? "held, token goes back to the MSHR" : "INSTALLED (line + tag written), entry freed");
            if (s2_refill && s2_vvalid)
                $display("[%0t] L1D B%0d S2 victim line %h (dirty=%b shared=%b) -> victim-cache slot %0d",
                         $time, BANK_ID, {s2_vline, OFF0}, s2_vdirty, s2_vshared, s2_slot);
            if (s2_maint)
                $display("[%0t] L1D B%0d S2 MAINT %s", $time, BANK_ID,
                         s2_held ? "held (retry)" : (s2_vvalid ? "dirty line -> victim cache (WBPEND)" : "done"));
            if (s2_snp) begin
                if (snp_push)
                    $display("[%0t] L1D B%0d S2 SNOOP %s line=%h -> answer present=%b dirty=%b%s",
                             $time, BANK_ID, s2_sinv ? "INV" : "READ", {s2_line, OFF0}, snp_present, snp_dirty,
                             snp_from_vc ? " (from victim-cache slot)" : (mshr_hit ? " (MSHR still waiting for data)" : ""));
                else
                    $display("[%0t] L1D B%0d S2 SNOOP %s line=%h -> waits for %s %0d",
                             $time, BANK_ID, s2_sinv ? "INV" : "READ", {s2_line, OFF0},
                             snp_act_code == SACT_WVC ? "victim-cache writeback, slot" : "install, MSHR entry",
                             snp_act_id);
                if (vc_hit && vc_state == VC_MOVING && !mshr_hit)
                    $display("[%0t] L1D B%0d S2 SNOOP ERROR MOVING slot without an MSHR entry", $time, BANK_ID);
            end
            if (lsu_response_valid)
                $display("[%0t] L1D B%0d S3 RESP from %s  seat=%0d idx=%0d %s data=%h (resp_free=%0d)",
                         $time, BANK_ID, s2_push ? "pipeline" : (m_take ? "MSHR" : "NC"),
                         done_seat, lsu_response_packet[RESP_IDX_LSB +: IDX_BITS], (lsu_response_packet[RESP_RDWR_BIT] ? "ST-ack" : "LD"),
                         lsu_response_packet[RESP_DATA_LSB +: WRITE_DATA_WIDTH], lsu_response_fifo_free);
            if (m_resp_valid && !m_take) begin
                dbg_mrw = dbg_mrw + 1;
                if (dbg_mrw % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D B%0d S3 STUCK MSHR response waits %0d cycles: s3_busy=%b miss_ok=%b resp_free=%0d",
                             $time, BANK_ID, dbg_mrw, s2_push, miss_ok, lsu_response_fifo_free);
            end else dbg_mrw = 0;
            if (n_resp_valid && !n_take) begin
                dbg_nrw = dbg_nrw + 1;
                if (dbg_nrw % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D B%0d S3 STUCK NC response waits %0d cycles: s3_busy=%b mshr_resp=%b miss_ok=%b resp_free=%0d",
                             $time, BANK_ID, dbg_nrw, s2_push, m_resp_valid, miss_ok, lsu_response_fifo_free);
            end else dbg_nrw = 0;
        end
    end
`endif
endmodule
`default_nettype wire
