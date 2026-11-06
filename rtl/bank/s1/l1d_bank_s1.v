`ifndef L1D_BANK_S1_V
`define L1D_BANK_S1_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_s1 #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst,
    s1_valid, s1_kind, s1_seat, s1_req, s1_mid, s1_line, s1_mway, s1_mop, s1_sinv, s1_sid, s1_kill,
    tag_q, s1_lines,
    lock_valid, lock_line,
    q1_state, q1_swap, q1_slot, vc_al_ok, vc_al_slot,
    rsv_sc_match,
    r_held, rsv_clear_valid, rsv_clear_line,
    s2_valid, s2_kind, s2_seat, s2_req, s2_mid, s2_line, s2_sinv, s2_sid,
    s2_hit, s2_scfail, s2_snp_hit, s2_hand, s2_way, s2_held, s2_swap, s2_kill,
    s2_words, s2_lines, s2_st_be, s2_st_din,
    s2_wbpend, s2_vvalid, s2_vdirty, s2_vshared, s2_vline, s2_slot
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam [BANK_W-1:0]   BANK_C = BANK_ID;
    localparam [OFFSET_W-1:0] OFF0   = {OFFSET_W{1'b0}};
    input  wire                        clk;
    input  wire                        rst;
    input  wire                        s1_valid;
    input  wire [1:0]                  s1_kind;
    input  wire [SEAT_W-1:0]           s1_seat;
    input  wire [REQ_W-1:0]            s1_req;
    input  wire [MSHR_ID_W-1:0]        s1_mid;
    input  wire [LINE_ADDR_W-1:0]      s1_line;
    input  wire [WAY_W-1:0]            s1_mway;
    input  wire                        s1_mop;
    input  wire                        s1_sinv;
    input  wire [SNP_ID_W-1:0]         s1_sid;
    input  wire                        s1_kill;
    input  wire [WAYS*TAG_W-1:0]       tag_q;
    input  wire [WAYS*LINE_W-1:0]      s1_lines;
    input  wire                        lock_valid;
    input  wire [LINE_ADDR_W-1:0]      lock_line;
    input  wire [1:0]                  q1_state;
    input  wire                        q1_swap;
    input  wire [VC_ID_W-1:0]          q1_slot;
    input  wire                        vc_al_ok;
    input  wire [VC_ID_W-1:0]          vc_al_slot;
    input  wire                        rsv_sc_match;
    output wire                        r_held;
    output wire                        rsv_clear_valid;
    output wire [LINE_ADDR_W-1:0]      rsv_clear_line;
    output reg                         s2_valid;
    output reg  [1:0]                  s2_kind;
    output reg  [SEAT_W-1:0]           s2_seat;
    output reg  [REQ_W-1:0]            s2_req;
    output reg  [MSHR_ID_W-1:0]        s2_mid;
    output reg  [LINE_ADDR_W-1:0]      s2_line;
    output reg                         s2_sinv;
    output reg  [SNP_ID_W-1:0]         s2_sid;
    output reg                         s2_hit;
    output reg                         s2_scfail;
    output reg                         s2_snp_hit;
    output reg                         s2_hand;
    output reg  [WAY_W-1:0]            s2_way;
    output reg                         s2_held;
    output reg                         s2_swap;
    output reg                         s2_kill;
    output reg  [WAYS*WRITE_DATA_WIDTH-1:0] s2_words;
    output reg  [WAYS*LINE_W-1:0]      s2_lines;
    output reg  [LINE_BYTES-1:0]       s2_st_be;
    output reg  [LINE_W-1:0]           s2_st_din;
    output reg                         s2_wbpend;
    output reg                         s2_vvalid;
    output reg                         s2_vdirty;
    output reg                         s2_vshared;
    output reg  [LINE_ADDR_W-1:0]      s2_vline;
    output reg  [VC_ID_W-1:0]          s2_slot;
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
    wire s1_lsu = s1_valid && (s1_kind == K_LSU);
    wire s2_lsu = s2_valid && (s2_kind == K_LSU);
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
    assign                 r_held   = s1_refill && v_valid && !q1_swap && !vc_al_ok;
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
    wire s1_evict = (RSV_CLR_ON_EVICT != 0) && s1_refill && !r_held && v_valid;
    assign rsv_clear_valid = s1_snp || s1_evict;
    assign rsv_clear_line  = s1_snp ? s1_line : v_line;
    always @(posedge clk) begin
        if (rst) begin
            s2_valid <= 1'b0;
        end else begin
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
`ifdef L1D_DEBUG
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
        end
    end
`endif
endmodule
`default_nettype wire
`endif
