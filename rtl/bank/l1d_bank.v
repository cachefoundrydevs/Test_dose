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
    rsv_event_pulse, other_bank_rsv_event,
    lsu_request_line_data, lsu_response_line_data
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
    input  wire [LINE_W-1:0]        lsu_request_line_data;
    output wire [LINE_W-1:0]        lsu_response_line_data;
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
    wire                    any_gnt;
    wire [INDEX_W-1:0]      g_set;
    wire                    gnt_refill, gnt_maint;
    wire                    r_valid;
    wire [1:0]              r_kind;
    wire [SEAT_W-1:0]       r_seat;
    wire [REQ_W-1:0]        r_req;
    wire                    r_fast;
    wire [MSHR_ID_W-1:0]    r_mid;
    wire [LINE_ADDR_W-1:0]  r_line;
    wire [WAY_W-1:0]        r_mway;
    wire                    r_mop;
    wire                    r_sinv;
    wire [SNP_ID_W-1:0]     r_sid;
    wire [LSU_BUF_DEPTH-1:0] seat_blk;
    wire                    buf_empty;
    wire                    miss_ok;
    wire                    s1_valid;
    wire [1:0]              s1_kind;
    wire [SEAT_W-1:0]       s1_seat;
    wire [REQ_W-1:0]        s1_req;
    wire [MSHR_ID_W-1:0]    s1_mid;
    wire [LINE_ADDR_W-1:0]  s1_line;
    wire [WAY_W-1:0]        s1_mway;
    wire                    s1_mop;
    wire                    s1_sinv;
    wire [SNP_ID_W-1:0]     s1_sid;
    wire                    s1_kill;
    wire [WAYS*TAG_W-1:0]   tag_q;
    wire [WAYS*LINE_W-1:0]  s1_lines;
    wire                    r_held;
    wire                    rsv_clear_valid;
    wire [LINE_ADDR_W-1:0]  rsv_clear_line;
    wire                    s2_valid;
    wire [1:0]              s2_kind;
    wire [SEAT_W-1:0]       s2_seat;
    wire [REQ_W-1:0]        s2_req;
    wire [MSHR_ID_W-1:0]    s2_mid;
    wire [LINE_ADDR_W-1:0]  s2_line;
    wire                    s2_sinv;
    wire [SNP_ID_W-1:0]     s2_sid;
    wire                    s2_hit;
    wire                    s2_scfail;
    wire                    s2_snp_hit;
    wire                    s2_hand;
    wire [WAY_W-1:0]        s2_way;
    wire                    s2_held;
    wire                    s2_swap;
    wire                    s2_kill;
    wire [WAYS*WRITE_DATA_WIDTH-1:0] s2_words;
    wire [WAYS*LINE_W-1:0]  s2_lines;
    wire [LINE_BYTES-1:0]   s2_st_be;
    wire [LINE_W-1:0]       s2_st_din;
    wire                    s2_wbpend;
    wire                    s2_vvalid;
    wire                    s2_vdirty;
    wire                    s2_vshared;
    wire [LINE_ADDR_W-1:0]  s2_vline;
    wire [VC_ID_W-1:0]      s2_slot;
    wire                    s2_refill;
    wire                    s2_maint;
    wire                    s2_st_wr;
    wire                    s2_uniq;
    wire                    s2_amo1;
    wire                    s2_alloc_is_write;
    wire [LINE_W-1:0]       line_q;
    wire [LINE_W-1:0]       st_merged;
    wire                    act_valid;
    wire [2:0]              act_code;
    wire [WID_W-1:0]        act_id;
    wire                    s3_load;
    wire [RESP_W-1:0]       s2_pkt;
    wire                    m_alloc, m_swap;
    wire                    vc_swap;
    wire                    n_alloc;
    wire                    ev_lr, ev_sc, ev_wr;
    wire                    ev_amor, ev_amow;
    wire                    snp_act_valid;
    wire [1:0]              snp_act_code;
    wire [WID_W-1:0]        snp_act_id;
    wire                    vc_snp;
    wire                    vc_ins;
    wire                    vc_rel;
    wire                    s3_amo_v;
    wire [LINE_ADDR_W-1:0]  s3_line;
    wire [WAY_W-1:0]        s3_way;
    wire [LINE_W-1:0]       s3_old;
    wire [LINE_BYTES-1:0]   s3_be;
    wire [OFFSET_W-1:0]     s3_off;
    wire [WRITE_DATA_WIDTH-1:0] s3_new;
    wire [LINE_W-1:0]       s3_merged;
    wire                    done_valid;
    wire [SEAT_W-1:0]       done_seat;
    wire                    m_resp_ack, n_resp_ack;
    wire                    m_rd_ready, n_rd_ready;
    wire                    vc_wr_ready, n_wr_ready;
    wire                    rsv_sc_match;
    wire                    lock_valid, lock_snp;
    wire [LINE_ADDR_W-1:0]  lock_line;
    wire                    mshr_hit, mshr_can, mshr_hasd;
    wire [MSHR_ID_W-1:0]    mshr_hid, mshr_aid;
    wire                    m_rd_valid, m_rd_unique;
    wire [LINE_ADDR_W-1:0]  m_rd_line;
    wire [MSHR_ID_W-1:0]    m_rd_sub;
    wire                    m_resp_valid;
    wire [RESP_W-1:0]       m_resp_pkt;
    wire [SEAT_W-1:0]       m_resp_seat;
    wire                    tok_valid;
    wire [MSHR_ID_W-1:0]    tok_id;
    wire [LINE_ADDR_W-1:0]  tok_line;
    wire [1:0]              q1_state;
    wire                    q1_swap;
    wire [VC_ID_W-1:0]      q1_slot;
    wire [LINE_W-1:0]       q2_data;
    wire                    mshr_busy;
    wire [MSHR_ENTRIES-1:0] mshr_freed;
    wire                    nc_can;
    wire                    n_rd_valid, n_wr_valid;
    wire [ADDR_W-1:0]       n_rd_addr, n_wr_addr;
    wire [2:0]              n_rd_size, n_wr_size;
    wire [AXI_DATA_W-1:0]   n_wr_data;
    wire [AXI_STRB_W-1:0]   n_wr_strb;
    wire                    n_resp_valid;
    wire [RESP_W-1:0]       n_resp_pkt;
    wire [SEAT_W-1:0]       n_resp_seat;
    wire                    nc_empty;
    wire                    nc_freed;
    wire                    vc_hit, vc_dirty, vc_shared;
    wire [VC_ID_W-1:0]      vc_slot;
    wire [2:0]              vc_state;
    wire [LINE_W-1:0]       vc_data;
    wire                    vc_al_ok;
    wire [VC_ID_W-1:0]      vc_al_slot;
    wire                    vc_wr_valid;
    wire [LINE_ADDR_W-1:0]  vc_wr_line;
    wire [VC_ID_W-1:0]      vc_wr_sub;
    wire [LINE_W-1:0]       vc_wr_data;
    wire                    vc_empty;
    wire [VC_SLOTS-1:0]     vc_freed;
    wire                    mt_valid;
    wire [INDEX_W-1:0]      mt_set;
    wire [WAY_W-1:0]        mt_way;
    wire                    mt_op;
    wire                    vc_drain;
    wire                    vec_slot_available;
    wire [VEC_SLOT_W-1:0]   vec_write_slot;
    wire                    vec_write_valid;
    wire [VEC_SLOT_W-1:0]   vec_read_slot;
    wire [LINE_W-1:0]       vec_read_line_data;
    wire                    vec_release_valid;
    wire [VEC_SLOT_W-1:0]   vec_release_slot;
    wire                    s2_alloc_no_response;
    wire [LINE_W-1:0]       s2_line_answer;
    wire [ADDR_W-1:0]           s2_addr  = s2_req[REQ_ADDR_LSB +: ADDR_W];
    wire [OFFSET_W-1:0]         s2_off   = s2_addr[OFFSET_W-1:0];
    wire [MEM_SIZE_BITS-1:0]    s2_size  = s2_req[REQ_SIZE_LSB +: MEM_SIZE_BITS];
    wire [MASTER_ID_BITS-1:0]   s2_mstid = s2_req[REQ_MID_LSB +: MASTER_ID_BITS];
    wire [IDX_BITS-1:0]         s2_idx   = s2_req[REQ_IDX_LSB +: IDX_BITS];
    wire [PORT_W-1:0]           s2_port  = s2_req[REQ_PORT_LSB +: PORT_W];
    wire [WRITE_DATA_WIDTH-1:0] s2_wdata = s2_req[REQ_DATA_LSB +: WRITE_DATA_WIDTH];
    l1d_vec_store_buf #(`L1D_PARAMS_PASS, .BANK_ID(BANK_ID)) u_vec_buf (
        .clk             (clk),
        .rst             (rst),
        .write_valid     (vec_write_valid),
        .write_line_data (lsu_request_line_data),
        .slot_available  (vec_slot_available),
        .write_slot      (vec_write_slot),
        .read_slot       (vec_read_slot),
        .read_line_data  (vec_read_line_data),
        .release_valid   (vec_release_valid),
        .release_slot    (vec_release_slot)
    );
    assign lsu_response_line_data = s2_line_answer;
    l1d_bank_fifo_s0 #(`L1D_PARAMS_PASS, .BANK_ID(BANK_ID)) u_fifo_s0 (
        .clk                        (clk),
        .rst                        (rst),
        .lsu_request_valid          (lsu_request_valid),
        .lsu_request_packet         (lsu_request_packet),
        .lsu_request_ready          (lsu_request_ready),
        .lsu_response_fifo_free     (lsu_response_fifo_free),
        .snoop_request_valid        (snoop_request_valid),
        .snoop_request_line_addr    (snoop_request_line_addr),
        .snoop_request_invalidate   (snoop_request_invalidate),
        .snoop_request_ready        (snoop_request_ready),
        .snoop_response_fifo_free   (snoop_response_fifo_free),
        .prefetch_request_valid     (prefetch_request_valid),
        .prefetch_request_line_addr (prefetch_request_line_addr),
        .prefetch_request_ready     (prefetch_request_ready),
        .refill_handover_busy       (refill_handover_busy),
        .s1_valid (s1_valid), .s1_kind (s1_kind), .s1_req (s1_req),
        .s2_valid (s2_valid), .s2_kind (s2_kind), .s2_req (s2_req), .s2_hit (s2_hit),
        .s2_seat  (s2_seat),  .s2_sid  (s2_sid),  .s2_line (s2_line),
        .s3_amo_v (s3_amo_v),
        .act_valid (act_valid), .act_code (act_code), .act_id (act_id),
        .done_valid (done_valid), .done_seat (done_seat),
        .snp_act_valid (snp_act_valid), .snp_act_code (snp_act_code), .snp_act_id (snp_act_id),
        .lock_valid (lock_valid), .lock_snp (lock_snp), .lock_line (lock_line), .ev_amor (ev_amor),
        .tok_valid (tok_valid), .tok_id (tok_id), .tok_line (tok_line),
        .mt_valid (mt_valid), .mt_set (mt_set), .mt_way (mt_way), .mt_op (mt_op),
        .m_resp_valid (m_resp_valid), .n_resp_valid (n_resp_valid),
        .mshr_freed (mshr_freed), .vc_freed (vc_freed), .nc_freed (nc_freed),
        .any_gnt (any_gnt), .g_set (g_set), .gnt_refill (gnt_refill), .gnt_maint (gnt_maint),
        .r_valid (r_valid), .r_kind (r_kind), .r_seat (r_seat), .r_req (r_req), .r_fast (r_fast), .r_mid (r_mid),
        .r_line (r_line), .r_mway (r_mway), .r_mop (r_mop), .r_sinv (r_sinv), .r_sid (r_sid),
        .seat_blk (seat_blk), .buf_empty (buf_empty), .miss_ok (miss_ok),
        .vec_slot_available (vec_slot_available), .vec_write_slot (vec_write_slot), .vec_write_valid (vec_write_valid)
    );
    l1d_bank_r #(`L1D_PARAMS_PASS, .BANK_ID(BANK_ID)) u_r (
        .clk (clk), .rst (rst),
        .any_gnt (any_gnt), .g_set (g_set),
        .r_valid (r_valid), .r_kind (r_kind), .r_seat (r_seat), .r_req (r_req), .r_fast (r_fast), .r_mid (r_mid),
        .r_line (r_line), .r_mway (r_mway), .r_mop (r_mop), .r_sinv (r_sinv), .r_sid (r_sid),
        .seat_blk (seat_blk),
        .s2_refill (s2_refill), .s2_st_wr (s2_st_wr), .s2_way (s2_way), .s2_line (s2_line),
        .q2_data (q2_data), .st_merged (st_merged),
        .s3_amo_v (s3_amo_v), .s3_way (s3_way), .s3_line (s3_line), .s3_merged (s3_merged),
        .s1_valid (s1_valid), .s1_kind (s1_kind), .s1_seat (s1_seat), .s1_req (s1_req), .s1_mid (s1_mid),
        .s1_line (s1_line), .s1_mway (s1_mway), .s1_mop (s1_mop), .s1_sinv (s1_sinv), .s1_sid (s1_sid),
        .s1_kill (s1_kill), .tag_q (tag_q), .s1_lines (s1_lines)
    );
    l1d_bank_s1 #(`L1D_PARAMS_PASS, .BANK_ID(BANK_ID)) u_s1 (
        .clk (clk), .rst (rst),
        .s1_valid (s1_valid), .s1_kind (s1_kind), .s1_seat (s1_seat), .s1_req (s1_req), .s1_mid (s1_mid),
        .s1_line (s1_line), .s1_mway (s1_mway), .s1_mop (s1_mop), .s1_sinv (s1_sinv), .s1_sid (s1_sid),
        .s1_kill (s1_kill), .tag_q (tag_q), .s1_lines (s1_lines),
        .lock_valid (lock_valid), .lock_line (lock_line),
        .q1_state (q1_state), .q1_swap (q1_swap), .q1_slot (q1_slot), .vc_al_ok (vc_al_ok), .vc_al_slot (vc_al_slot),
        .rsv_sc_match (rsv_sc_match),
        .r_held (r_held), .rsv_clear_valid (rsv_clear_valid), .rsv_clear_line (rsv_clear_line),
        .vec_read_slot (vec_read_slot), .vec_read_line_data (vec_read_line_data),
        .s2_valid (s2_valid), .s2_kind (s2_kind), .s2_seat (s2_seat), .s2_req (s2_req), .s2_mid (s2_mid),
        .s2_line (s2_line), .s2_sinv (s2_sinv), .s2_sid (s2_sid),
        .s2_hit (s2_hit), .s2_scfail (s2_scfail), .s2_snp_hit (s2_snp_hit), .s2_hand (s2_hand), .s2_way (s2_way),
        .s2_held (s2_held), .s2_swap (s2_swap), .s2_kill (s2_kill),
        .s2_words (s2_words), .s2_lines (s2_lines), .s2_st_be (s2_st_be), .s2_st_din (s2_st_din),
        .s2_wbpend (s2_wbpend), .s2_vvalid (s2_vvalid), .s2_vdirty (s2_vdirty), .s2_vshared (s2_vshared),
        .s2_vline (s2_vline), .s2_slot (s2_slot)
    );
    l1d_bank_s2 #(`L1D_PARAMS_PASS, .BANK_ID(BANK_ID)) u_s2 (
        .clk (clk), .rst (rst),
        .s2_valid (s2_valid), .s2_kind (s2_kind), .s2_seat (s2_seat), .s2_req (s2_req), .s2_mid (s2_mid),
        .s2_line (s2_line), .s2_sinv (s2_sinv),
        .s2_hit (s2_hit), .s2_scfail (s2_scfail), .s2_snp_hit (s2_snp_hit), .s2_hand (s2_hand), .s2_way (s2_way),
        .s2_held (s2_held), .s2_swap (s2_swap), .s2_kill (s2_kill),
        .s2_words (s2_words), .s2_lines (s2_lines), .s2_st_be (s2_st_be), .s2_st_din (s2_st_din),
        .s2_wbpend (s2_wbpend), .s2_vvalid (s2_vvalid), .s2_vdirty (s2_vdirty), .s2_vshared (s2_vshared),
        .s2_vline (s2_vline), .s2_slot (s2_slot),
        .mshr_hit (mshr_hit), .mshr_hid (mshr_hid), .mshr_hasd (mshr_hasd), .mshr_can (mshr_can), .mshr_aid (mshr_aid),
        .vc_hit (vc_hit), .vc_slot (vc_slot), .vc_state (vc_state), .vc_data (vc_data), .vc_dirty (vc_dirty),
        .nc_can (nc_can),
        .s2_refill (s2_refill), .s2_maint (s2_maint), .s2_st_wr (s2_st_wr),
        .s2_uniq (s2_uniq), .s2_amo1 (s2_amo1), .s2_alloc_is_write (s2_alloc_is_write), .s2_alloc_no_response (s2_alloc_no_response),
        .s2_line_answer (s2_line_answer), .vec_release_valid (vec_release_valid), .vec_release_slot (vec_release_slot),
        .line_q (line_q), .st_merged (st_merged),
        .act_valid (act_valid), .act_code (act_code), .act_id (act_id),
        .s3_load (s3_load), .s2_pkt (s2_pkt),
        .m_alloc (m_alloc), .m_swap (m_swap), .vc_swap (vc_swap), .n_alloc (n_alloc),
        .ev_lr (ev_lr), .ev_sc (ev_sc), .ev_wr (ev_wr), .ev_amor (ev_amor), .ev_amow (ev_amow),
        .rsv_event_pulse (rsv_event_pulse),
        .snoop_response_valid (snoop_response_valid), .snoop_response_packet (snoop_response_packet),
        .snp_act_valid (snp_act_valid), .snp_act_code (snp_act_code), .snp_act_id (snp_act_id),
        .vc_snp (vc_snp), .vc_ins (vc_ins), .vc_rel (vc_rel),
        .s3_amo_v (s3_amo_v), .s3_line (s3_line), .s3_way (s3_way), .s3_old (s3_old),
        .s3_be (s3_be), .s3_off (s3_off), .s3_new (s3_new)
    );
    l1d_bank_s3 #(`L1D_PARAMS_PASS, .BANK_ID(BANK_ID)) u_s3 (
        .clk (clk), .rst (rst),
        .s3_old (s3_old), .s3_be (s3_be), .s3_off (s3_off), .s3_new (s3_new), .s3_merged (s3_merged),
        .s3_load (s3_load), .s2_pkt (s2_pkt), .s2_seat (s2_seat),
        .m_resp_valid (m_resp_valid), .m_resp_pkt (m_resp_pkt), .m_resp_seat (m_resp_seat), .m_resp_ack (m_resp_ack),
        .n_resp_valid (n_resp_valid), .n_resp_pkt (n_resp_pkt), .n_resp_seat (n_resp_seat), .n_resp_ack (n_resp_ack),
        .miss_ok (miss_ok), .lsu_response_fifo_free (lsu_response_fifo_free),
        .lsu_response_valid (lsu_response_valid), .lsu_response_packet (lsu_response_packet),
        .done_valid (done_valid), .done_seat (done_seat),
        .m_rd_valid (m_rd_valid), .m_rd_ready (m_rd_ready), .m_rd_line (m_rd_line), .m_rd_sub (m_rd_sub), .m_rd_unique (m_rd_unique),
        .n_rd_valid (n_rd_valid), .n_rd_ready (n_rd_ready), .n_rd_addr (n_rd_addr), .n_rd_size (n_rd_size),
        .vc_wr_valid (vc_wr_valid), .vc_wr_ready (vc_wr_ready), .vc_wr_line (vc_wr_line), .vc_wr_sub (vc_wr_sub), .vc_wr_data (vc_wr_data),
        .n_wr_valid (n_wr_valid), .n_wr_ready (n_wr_ready), .n_wr_addr (n_wr_addr), .n_wr_size (n_wr_size),
        .n_wr_data (n_wr_data), .n_wr_strb (n_wr_strb),
        .axi_read_req_valid (axi_read_req_valid), .axi_read_req_ready (axi_read_req_ready),
        .axi_read_req_addr (axi_read_req_addr), .axi_read_req_burst_len (axi_read_req_burst_len),
        .axi_read_req_size (axi_read_req_size), .axi_read_req_sub_id (axi_read_req_sub_id),
        .axi_read_req_non_cacheable (axi_read_req_non_cacheable), .axi_read_req_unique (axi_read_req_unique),
        .axi_write_req_valid (axi_write_req_valid), .axi_write_req_ready (axi_write_req_ready),
        .axi_write_req_addr (axi_write_req_addr), .axi_write_req_burst_len (axi_write_req_burst_len),
        .axi_write_req_size (axi_write_req_size), .axi_write_req_sub_id (axi_write_req_sub_id),
        .axi_write_req_non_cacheable (axi_write_req_non_cacheable), .axi_write_req_data (axi_write_req_data),
        .axi_write_req_strobe (axi_write_req_strobe)
    );
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
        .s1_clear_valid         (rsv_clear_valid),
        .s1_clear_line_addr     (rsv_clear_line),
        .maint_clear            (maint_start),
        .other_bank_rsv_clear   (other_bank_rsv_event),
        .reservation_valid      (),
        .reservation_line_addr  (),
        .amo_lock_valid         (lock_valid),
        .amo_lock_snoop_hold    (lock_snp),
        .amo_lock_line          (lock_line),
        .amo_lock_timeout_pulse (amo_lock_timeout_pulse)
    );
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
        .allocate_is_write        (s2_alloc_is_write),
        .allocate_no_response     (s2_alloc_no_response),
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
endmodule
`default_nettype wire
