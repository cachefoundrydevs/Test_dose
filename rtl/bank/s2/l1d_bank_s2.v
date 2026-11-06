`ifndef L1D_BANK_S2_V
`define L1D_BANK_S2_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_s2 #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst,
    s2_valid, s2_kind, s2_seat, s2_req, s2_mid, s2_line, s2_sinv,
    s2_hit, s2_scfail, s2_snp_hit, s2_hand, s2_way, s2_held, s2_swap, s2_kill,
    s2_words, s2_lines, s2_st_be, s2_st_din,
    s2_wbpend, s2_vvalid, s2_vdirty, s2_vshared, s2_vline, s2_slot,
    mshr_hit, mshr_hid, mshr_hasd, mshr_can, mshr_aid,
    vc_hit, vc_slot, vc_state, vc_data, vc_dirty,
    nc_can,
    s2_refill, s2_maint, s2_st_wr, s2_uniq, s2_amo1, s2_alloc_is_write,
    line_q, st_merged,
    act_valid, act_code, act_id,
    s3_load, s2_pkt,
    m_alloc, m_swap, vc_swap, n_alloc,
    ev_lr, ev_sc, ev_wr, ev_amor, ev_amow, rsv_event_pulse,
    snoop_response_valid, snoop_response_packet,
    snp_act_valid, snp_act_code, snp_act_id,
    vc_snp, vc_ins, vc_rel,
    s3_amo_v, s3_line, s3_way, s3_old, s3_be, s3_off, s3_new
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam [OFFSET_W-1:0] OFF0 = {OFFSET_W{1'b0}};
    localparam [WRITE_DATA_WIDTH-1:0] SC_FAIL_W = {{(WRITE_DATA_WIDTH-1){1'b0}}, SC_FAIL};
    input  wire                        clk;
    input  wire                        rst;
    input  wire                        s2_valid;
    input  wire [1:0]                  s2_kind;
    input  wire [SEAT_W-1:0]           s2_seat;
    input  wire [REQ_W-1:0]            s2_req;
    input  wire [MSHR_ID_W-1:0]        s2_mid;
    input  wire [LINE_ADDR_W-1:0]      s2_line;
    input  wire                        s2_sinv;
    input  wire                        s2_hit;
    input  wire                        s2_scfail;
    input  wire                        s2_snp_hit;
    input  wire                        s2_hand;
    input  wire [WAY_W-1:0]            s2_way;
    input  wire                        s2_held;
    input  wire                        s2_swap;
    input  wire                        s2_kill;
    input  wire [WAYS*WRITE_DATA_WIDTH-1:0] s2_words;
    input  wire [WAYS*LINE_W-1:0]      s2_lines;
    input  wire [LINE_BYTES-1:0]       s2_st_be;
    input  wire [LINE_W-1:0]           s2_st_din;
    input  wire                        s2_wbpend;
    input  wire                        s2_vvalid;
    input  wire                        s2_vdirty;
    input  wire                        s2_vshared;
    input  wire [LINE_ADDR_W-1:0]      s2_vline;
    input  wire [VC_ID_W-1:0]          s2_slot;
    input  wire                        mshr_hit;
    input  wire [MSHR_ID_W-1:0]        mshr_hid;
    input  wire                        mshr_hasd;
    input  wire                        mshr_can;
    input  wire [MSHR_ID_W-1:0]        mshr_aid;
    input  wire                        vc_hit;
    input  wire [VC_ID_W-1:0]          vc_slot;
    input  wire [2:0]                  vc_state;
    input  wire [LINE_W-1:0]           vc_data;
    input  wire                        vc_dirty;
    input  wire                        nc_can;
    output wire                        s2_refill;
    output wire                        s2_maint;
    output wire                        s2_st_wr;
    output wire                        s2_uniq;
    output wire                        s2_amo1;
    output wire                        s2_alloc_is_write;
    output reg  [LINE_W-1:0]           line_q;
    output reg  [LINE_W-1:0]           st_merged;
    output reg                         act_valid;
    output reg  [2:0]                  act_code;
    output reg  [WID_W-1:0]            act_id;
    output reg                         s3_load;
    output wire [RESP_W-1:0]           s2_pkt;
    output reg                         m_alloc;
    output reg                         m_swap;
    output reg                         vc_swap;
    output reg                         n_alloc;
    output wire                        ev_lr;
    output wire                        ev_sc;
    output wire                        ev_wr;
    output wire                        ev_amor;
    output wire                        ev_amow;
    output wire                        rsv_event_pulse;
    output wire                        snoop_response_valid;
    output wire [SNPR_W-1:0]           snoop_response_packet;
    output reg                         snp_act_valid;
    output reg  [1:0]                  snp_act_code;
    output reg  [WID_W-1:0]            snp_act_id;
    output reg                         vc_snp;
    output wire                        vc_ins;
    output wire                        vc_rel;
    output reg                         s3_amo_v;
    output reg  [LINE_ADDR_W-1:0]      s3_line;
    output reg  [WAY_W-1:0]            s3_way;
    output reg  [LINE_W-1:0]           s3_old;
    output reg  [LINE_BYTES-1:0]       s3_be;
    output reg  [OFFSET_W-1:0]         s3_off;
    output reg  [WRITE_DATA_WIDTH-1:0] s3_new;
    wire               s2_lsu = s2_valid && (s2_kind == K_LSU);
    wire               s2_cache  = s2_req[REQ_CACHE_BIT];
    wire               s2_store  = (s2_req[REQ_RDWR_BIT] == OP_WRITE);
    wire               s2_amo    = s2_req[REQ_AMO_BIT];
    wire               s2_seq    = s2_req[REQ_SEQ_BIT];
    wire               s2_is_lr  = s2_amo && !s2_seq && !s2_store;
    wire               s2_is_sc  = s2_amo && !s2_seq &&  s2_store;
    wire               s2_is_amr = s2_amo &&  s2_seq && !s2_store;
    wire               s2_is_amw = s2_amo &&  s2_seq &&  s2_store;
    assign             s2_uniq   = s2_store || s2_amo;
    assign             s2_amo1   = s2_amo && s2_seq;
    wire [ADDR_W-1:0]  s2_addr   = s2_req[REQ_ADDR_LSB +: ADDR_W];
    wire [OFFSET_W-1:0]         s2_off   = s2_addr[OFFSET_W-1:0];
    wire [MEM_SIZE_BITS-1:0]    s2_size  = s2_req[REQ_SIZE_LSB +: MEM_SIZE_BITS];
    wire [MASTER_ID_BITS-1:0]   s2_mstid = s2_req[REQ_MID_LSB +: MASTER_ID_BITS];
    wire [IDX_BITS-1:0]         s2_idx   = s2_req[REQ_IDX_LSB +: IDX_BITS];
    wire [PORT_W-1:0]           s2_port  = s2_req[REQ_PORT_LSB +: PORT_W];
    wire [WRITE_DATA_WIDTH-1:0] s2_wdata = s2_req[REQ_DATA_LSB +: WRITE_DATA_WIDTH];
    assign             s2_alloc_is_write = s2_req[REQ_RDWR_BIT] && !s2_amo1;
    assign s2_refill = s2_valid && (s2_kind == K_REFILL) && !s2_held;
    assign s2_maint  = s2_valid && (s2_kind == K_MAINT);
    wire s2_snp    = s2_valid && (s2_kind == K_SNOOP);
    assign s2_st_wr  = s2_lsu && s2_hit && s2_store && !s2_amo1;
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
    reg  s3_from_vc;
    reg  s3_scfail;
    reg  s3_zero;
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
    assign s2_pkt = {s2_port, (s2_req[REQ_RDWR_BIT] && !s2_amo1), s2_size, s2_mstid, s2_idx, s2_rdata};
    wire s2_done_lsu = s2_lsu && (s3_load || (act_valid && act_code == ACT_OWNED));
    assign ev_lr   = s2_done_lsu && s2_cache && s2_is_lr;
    assign ev_sc   = s2_done_lsu && s2_is_sc;
    assign rsv_event_pulse = ev_lr || ev_sc;
    assign ev_wr   = s2_done_lsu && s2_cache && s2_store && !s2_is_sc;
    assign ev_amor = 1'b0;
    assign ev_amow = 1'b0;
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
    reg  snp_push;
    reg  snp_present, snp_dirty, snp_from_vc;
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
    assign vc_ins = (s2_refill && s2_vvalid) || (s2_maint && !s2_held && s2_vvalid);
    assign vc_rel = s2_refill && s2_swap && !s2_vvalid;
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
        end
    end
`endif
endmodule
`default_nettype wire
`endif
