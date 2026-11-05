`default_nettype none
`include "l1d_defines.vh"
module l1d_victim_cache #(`L1D_PARAMS) (
    clk, rst,
    lookup_line_addr_next, lookup_line_addr, lookup_hit, lookup_slot, lookup_slot_state, lookup_line_data, lookup_dirty, lookup_shared,
    victim_slot_available, victim_slot_index,
    insert_valid, insert_slot, insert_line_addr, insert_line_data, insert_dirty, insert_shared, insert_as_writeback_pending,
    swap_start_valid, swap_start_slot,
    release_valid, release_slot,
    snoop_hit_valid, snoop_hit_slot, snoop_invalidate,
    drain_enable,
    writeback_req_valid, writeback_req_ready, writeback_req_line_addr, writeback_req_slot_id, writeback_req_data,
    writeback_done_valid, writeback_done_slot_id,
    all_slots_free, slot_freed_pulses
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam N = VC_SLOTS;
    input  wire                   clk;
    input  wire                   rst;
    input  wire [LINE_ADDR_W-1:0] lookup_line_addr_next;
    input  wire [LINE_ADDR_W-1:0] lookup_line_addr;
    output wire                   lookup_hit;
    output wire [VC_ID_W-1:0]     lookup_slot;
    output wire [2:0]             lookup_slot_state;
    output wire [LINE_W-1:0]      lookup_line_data;
    output wire                   lookup_dirty;
    output wire                   lookup_shared;
    output wire                   victim_slot_available;
    output wire [VC_ID_W-1:0]     victim_slot_index;
    input  wire                   insert_valid;
    input  wire [VC_ID_W-1:0]     insert_slot;
    input  wire [LINE_ADDR_W-1:0] insert_line_addr;
    input  wire [LINE_W-1:0]      insert_line_data;
    input  wire                   insert_dirty;
    input  wire                   insert_shared;
    input  wire                   insert_as_writeback_pending;
    input  wire                   swap_start_valid;
    input  wire [VC_ID_W-1:0]     swap_start_slot;
    input  wire                   release_valid;
    input  wire [VC_ID_W-1:0]     release_slot;
    input  wire                   snoop_hit_valid;
    input  wire [VC_ID_W-1:0]     snoop_hit_slot;
    input  wire                   snoop_invalidate;
    input  wire                   drain_enable;
    output wire                   writeback_req_valid;
    input  wire                   writeback_req_ready;
    output wire [LINE_ADDR_W-1:0] writeback_req_line_addr;
    output wire [VC_ID_W-1:0]     writeback_req_slot_id;
    output wire [LINE_W-1:0]      writeback_req_data;
    input  wire                   writeback_done_valid;
    input  wire [VC_ID_W-1:0]     writeback_done_slot_id;
    output wire                   all_slots_free;
    output reg  [N-1:0]           slot_freed_pulses;
    reg [1:0]             st   [0:N-1];
    reg [LINE_ADDR_W-1:0] la   [0:N-1];
    reg                   dty  [0:N-1];
    reg                   shr  [0:N-1];
    reg                   iss  [0:N-1];
    reg [LINE_W-1:0]      dmem [0:N-1];
    wire [N-1:0]             in_use, is_free, is_clean, is_dirty, is_pend;
    reg  [N-1:0]             use_q;
    wire [N-1:0]             excl;
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_slot
            assign excl[g]     = (swap_start_valid && (swap_start_slot == g)) || (snoop_hit_valid && (snoop_hit_slot == g));
            assign in_use[g]   = use_q[g];
            assign is_free[g]  = !use_q[g] && !excl[g];
            assign is_clean[g] = (st[g] == VC_VALID) && !dty[g] && !excl[g];
            assign is_dirty[g] = (st[g] == VC_VALID) &&  dty[g] && !excl[g];
            assign is_pend[g]  = (st[g] == VC_WBPEND) && !iss[g];
        end
    endgenerate
    reg  [N-1:0] lk_addr_q;
    wire [N-1:0] lk_match_q = lk_addr_q & use_q;
    wire [N-1:0] lk_match = lk_match_q;
    reg  [N-1:0] lk_first;
    reg          lk_seen;
    reg  [VC_ID_W-1:0] lk_idx;
    integer      q;
    always @* begin
        lk_seen = 1'b0;
        lk_idx  = {VC_ID_W{1'b0}};
        for (q = 0; q < N; q = q + 1) begin
            lk_first[q] = lk_match[q] & ~|(lk_match & ((1 << q) - 1));
            if (lk_first[q]) lk_idx = lk_idx | q[VC_ID_W-1:0];
        end
    end
    assign lookup_hit  = |lk_match;
    assign lookup_slot = lk_idx;
    wire [N-1:0] lk_pick = {lk_first[N-1:1], lk_match[0] | ~|lk_match[N-1:1]};
    reg  [2:0]        lk_st;
    reg               lk_dty, lk_shr;
    always @* begin
        lk_st = 3'd0;  lk_dty = 1'b0;  lk_shr = 1'b0;
        for (q = 0; q < N; q = q + 1) begin
            lk_st   = lk_st   | ({3{lk_pick[q]}}      & st[q]);
            lk_dty  = lk_dty  | (lk_pick[q] & dty[q]);
            lk_shr  = lk_shr  | (lk_pick[q] & shr[q]);
        end
    end
    assign lookup_slot_state = lk_st;
    assign lookup_dirty      = lk_dty;
    assign lookup_shared     = lk_shr;
    function [N-1:0] lowest_oh;
        input [N-1:0] v;
        integer b;
        reg seen;
        begin
            seen = 1'b0;
            for (b = 0; b < N; b = b + 1) begin
                lowest_oh[b] = v[b] & ~seen;
                seen         = seen | v[b];
            end
        end
    endfunction
    function [VC_ID_W-1:0] enc_oh;
        input [N-1:0] v;
        integer b;
        begin
            enc_oh = {VC_ID_W{1'b0}};
            for (b = 0; b < N; b = b + 1)
                if (v[b]) enc_oh = enc_oh | b[VC_ID_W-1:0];
        end
    endfunction
    wire [N-1:0]       free_oh  = lowest_oh(is_free);
    wire [VC_ID_W-1:0] free_slot = enc_oh(free_oh);
    wire               any_free  = |is_free;
    wire [VC_ID_W-1:0] clean_slot;
    wire               any_clean;
    l1d_age_matrix #(.N(N), .IDX_W(VC_ID_W)) u_age (
        .clk             (clk),
        .rst             (rst),
        .allocate_valid  (insert_valid),
        .allocate_index  (insert_slot),
        .candidate_mask  (is_clean),
        .older_than_flat (),
        .oldest_onehot   (),
        .oldest_index    (clean_slot),
        .any_candidate   (any_clean)
    );
    assign victim_slot_available   = any_free || (|is_clean);
    assign victim_slot_index = any_free ? free_slot : clean_slot;
    wire [N-1:0] pend_oh  = lowest_oh(is_pend);
    wire [N-1:0] dirty_oh = lowest_oh(is_dirty);
    wire         any_pend  = |is_pend;
    wire         any_dirty = |is_dirty;
    reg                wb_act;
    reg [VC_ID_W-1:0]  wb_slot;
    reg [N-1:0]        wb_oh;
    wire pressure  = !any_free || drain_enable;
    wire wb_start  = !wb_act && (any_pend || (pressure && any_dirty));
    wire [N-1:0]       wb_pick_oh = any_pend ? pend_oh : dirty_oh;
    wire [VC_ID_W-1:0] wb_pick    = enc_oh(wb_pick_oh);
    reg  [N-1:0]       wb_set;
    wire               wb_dg = !wb_act && !any_pend && pressure;
    integer            v;
    always @* begin
        for (v = 0; v < N; v = v + 1)
            wb_set[v] = (!wb_act && is_pend[v] && ~|(is_pend & ((1 << v) - 1))) ||
                        (wb_dg && is_dirty[v] && ~|(is_dirty & ((1 << v) - 1)));
    end
    reg  [LINE_ADDR_W-1:0] wb_la;
    reg  [LINE_W-1:0]      wb_data;
    integer w;
    always @* begin
        wb_la = {LINE_ADDR_W{1'b0}};  wb_data = {LINE_W{1'b0}};
        for (w = 0; w < N; w = w + 1) begin
            wb_la   = wb_la   | ({LINE_ADDR_W{wb_oh[w]}} & la[w]);
            wb_data = wb_data | ({LINE_W{wb_oh[w]}}      & dmem[w]);
        end
    end
    assign writeback_req_valid = wb_act;
    assign writeback_req_line_addr  = wb_la;
    assign writeback_req_slot_id   = wb_slot;
    assign writeback_req_data  = wb_data;
    reg  [2:0]             st_n [0:N-1];
    reg  [N-1:0]           match_n;
    reg  [N-1:0]           iss_n;
    reg  [2:0]             st_base, st_ovr, st_o;
    reg                    ovr, wbe, h_swp, h_snp, h_rel, h_ins, m_ln, h_hand;
    wire                   eq_ins = (insert_line_addr == lookup_line_addr_next);
    integer sn;
    always @* begin
        for (sn = 0; sn < N; sn = sn + 1) begin
            st_base = st[sn];
            if (writeback_done_valid && (writeback_done_slot_id == sn))     st_base = VC_FREE;
            if (drain_enable && (st[sn] == VC_VALID) && !dty[sn])           st_base = VC_FREE;
            h_swp = swap_start_valid && (swap_start_slot == sn);
            h_snp = snoop_hit_valid && snoop_invalidate && (snoop_hit_slot == sn);
            h_rel = release_valid && (release_slot == sn);
            h_ins = insert_valid && (insert_slot == sn);
            ovr    = h_swp || h_snp || h_rel || h_ins;
            st_ovr = h_ins ? (insert_as_writeback_pending ? VC_WBPEND : VC_VALID) : ((h_rel || h_snp) ? VC_FREE : VC_MOVING);
            st_o   = ovr ? st_ovr : st_base;
            wbe      = wb_set[sn] && !ovr;
            st_n[sn] = ({3{wbe}} & VC_WBPEND) | ({3{!wbe}} & st_o);
            m_ln        = h_ins ? eq_ins : (la[sn] == lookup_line_addr_next);
            match_n[sn] = m_ln;
            h_hand    = wb_act && writeback_req_ready && (wb_slot == sn);
            iss_n[sn] = (h_ins ? 1'b0 : (h_hand || iss[sn])) && !wb_set[sn];
        end
    end
    reg [N-1:0] use_n;
    integer un;
    always @* for (un = 0; un < N; un = un + 1) use_n[un] = (st_n[un] != VC_FREE);
    localparam LK_DUP = 4;
    localparam LK_PW  = LINE_W / LK_DUP;
    (* keep *) reg [N-1:0] lka_c [0:LK_DUP-1];
    (* keep *) reg [N-1:0] use_c [0:LK_DUP-1];
    genvar gp;
    generate
        for (gp = 0; gp < LK_DUP; gp = gp + 1) begin : g_lkd
            wire [N-1:0] m_c = lka_c[gp] & use_c[gp];
            wire [LK_PW-1:0] tv [0:2*N-2];
            wire             ta [0:2*N-2];
            genvar tq, tl, ti;
            for (tq = 0; tq < N; tq = tq + 1) begin : g_leaf
                assign tv[tq] = dmem[tq][gp*LK_PW +: LK_PW];
                assign ta[tq] = m_c[tq];
            end
            for (tl = 1; tl <= VC_ID_W; tl = tl + 1) begin : g_lvl
                for (ti = 0; ti < (N >> tl); ti = ti + 1) begin : g_node
                    localparam LO = 2*N - ((2*N) >> (tl - 1)) + 2*ti;
                    localparam ND = 2*N - ((2*N) >> tl) + ti;
                    wire sel_lo = ta[LO] | ~ta[LO+1];
                    assign tv[ND] = sel_lo ? tv[LO] : tv[LO+1];
                    assign ta[ND] = ta[LO] | ta[LO+1];
                end
            end
            assign lookup_line_data[gp*LK_PW +: LK_PW] = tv[2*N-2];
            always @(posedge clk) begin
                if (rst) begin
                    lka_c[gp] <= {N{1'b0}};
                    use_c[gp] <= {N{1'b0}};
                end else begin
                    lka_c[gp] <= match_n;
                    use_c[gp] <= use_n;
                end
            end
        end
    endgenerate
    integer s;
    always @(posedge clk) begin
        if (rst) begin
            lk_addr_q <= {N{1'b0}};
            use_q     <= {N{1'b0}};
            for (s = 0; s < N; s = s + 1) begin
                st[s]  <= VC_FREE;
                dty[s] <= 1'b0;
                shr[s] <= 1'b0;
                iss[s] <= 1'b0;
            end
            wb_act  <= 1'b0;
            wb_slot <= {VC_ID_W{1'b0}};
            wb_oh   <= {{(N-1){1'b0}}, 1'b1};
            slot_freed_pulses   <= {N{1'b0}};
        end else begin
            slot_freed_pulses <= {N{1'b0}};
            lk_addr_q <= match_n;
            for (s = 0; s < N; s = s + 1) begin
                st[s]  <= st_n[s];
                use_q[s] <= use_n[s];
                iss[s] <= iss_n[s];
            end
            if (writeback_done_valid)
                slot_freed_pulses[writeback_done_slot_id] <= 1'b1;
            if (wb_act && writeback_req_ready)
                wb_act <= 1'b0;
            else if (wb_start)
                wb_act <= 1'b1;
            if (!wb_act) begin
                wb_slot <= wb_pick;
                wb_oh   <= wb_pick_oh;
            end
            if (snoop_hit_valid && !snoop_invalidate) begin
                shr[snoop_hit_slot] <= 1'b1;
                dty[snoop_hit_slot] <= 1'b0;
            end
            if (insert_valid) begin
                la[insert_slot]   <= insert_line_addr;
                dty[insert_slot]  <= insert_dirty;
                shr[insert_slot]  <= insert_shared;
                dmem[insert_slot] <= insert_line_data;
            end
        end
    end
    assign all_slots_free = ~|in_use;
`ifdef L1D_DEBUG
    reg [LINE_ADDR_W-1:0] dbg_next_q;
    reg                   dbg_next_v;
    always @(posedge clk) begin
        dbg_next_q <= lookup_line_addr_next;
        dbg_next_v <= !rst;
        if (!rst && dbg_next_v && (lookup_line_addr !== dbg_next_q))
            $display("[%0t] L1D VC %m ERROR lookup_line_addr %h is not last cycle's lookup_line_addr_next %h (V-5 look-ahead broken)",
                     $time, lookup_line_addr, dbg_next_q);
    end
    function [8*7-1:0] dbg_vname;
        input [2:0] s;
        begin
            case (s)
                VC_FREE:   dbg_vname = "FREE";
                VC_VALID:  dbg_vname = "VALID";
                VC_MOVING: dbg_vname = "MOVING";
                VC_WBPEND: dbg_vname = "WBPEND";
                default:   dbg_vname = "?";
            endcase
        end
    endfunction
    integer dbg_age [0:N-1];
    integer dbg_wbw, dbg_k;
    initial begin
        dbg_wbw = 0;
        for (dbg_k = 0; dbg_k < N; dbg_k = dbg_k + 1) dbg_age[dbg_k] = 0;
    end
    always @(posedge clk) begin
        if (!rst) begin
            if (insert_valid)
                $display("[%0t] L1D VC   %m insert slot %0d line=%h dirty=%b as %s (old state %0s)",
                         $time, insert_slot, {insert_line_addr, {OFFSET_W{1'b0}}}, insert_dirty,
                         insert_as_writeback_pending ? "WBPEND" : "VALID", dbg_vname(st[insert_slot]));
            if (swap_start_valid)
                $display("[%0t] L1D VC   %m swap start slot %0d line=%h -> MOVING",
                         $time, swap_start_slot, {la[swap_start_slot], {OFFSET_W{1'b0}}});
            if (release_valid)
                $display("[%0t] L1D VC   %m slot %0d released (swap installed into an empty way)", $time, release_slot);
            if (snoop_hit_valid)
                $display("[%0t] L1D VC   %m snoop %s slot %0d line=%h (was %0s dirty=%b)", $time,
                         snoop_invalidate ? "invalidates" : "reads", snoop_hit_slot, {la[snoop_hit_slot], {OFFSET_W{1'b0}}},
                         dbg_vname(st[snoop_hit_slot]), dty[snoop_hit_slot]);
            if (snoop_hit_valid && st[snoop_hit_slot] != VC_VALID)
                $display("[%0t] L1D VC   %m ERROR snoop operation on slot %0d which is not VALID", $time, snoop_hit_slot);
            if (wb_start && !(wb_act && writeback_req_ready))
                $display("[%0t] L1D VC   %m writeback start slot %0d line=%h (%s)",
                         $time, wb_pick, {la[wb_pick], {OFFSET_W{1'b0}}},
                         any_pend ? "WBPEND line" : (drain_enable ? "drain" : "no free slot"));
            if (wb_act && writeback_req_ready)
                $display("[%0t] L1D VC   %m writeback slot %0d handed to the AXI master", $time, wb_slot);
            if (writeback_done_valid) begin
                if (st[writeback_done_slot_id] != VC_WBPEND)
                    $display("[%0t] L1D VC   %m ERROR B for slot %0d, which is %0s, not WBPEND (wrong BID from memory?)",
                             $time, writeback_done_slot_id, dbg_vname(st[writeback_done_slot_id]));
                else
                    $display("[%0t] L1D VC   %m B slot %0d -> FREE", $time, writeback_done_slot_id);
            end
            if (wb_act && !writeback_req_ready) begin
                dbg_wbw = dbg_wbw + 1;
                if (dbg_wbw % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D VC   %m STUCK writeback slot %0d offered for %0d cycles, AXI write channel busy",
                             $time, wb_slot, dbg_wbw);
            end else dbg_wbw = 0;
            for (dbg_k = 0; dbg_k < N; dbg_k = dbg_k + 1) begin
                if (st[dbg_k] == VC_WBPEND || st[dbg_k] == VC_MOVING) begin
                    dbg_age[dbg_k] = dbg_age[dbg_k] + 1;
                    if (dbg_age[dbg_k] % `L1D_DBG_WD == 0)
                        $display("[%0t] L1D VC   %m STUCK slot %0d in %0s for %0d cycles line=%h sent=%b (WBPEND: waiting for B; MOVING: waiting for its swap install)",
                                 $time, dbg_k, dbg_vname(st[dbg_k]), dbg_age[dbg_k],
                                 {la[dbg_k], {OFFSET_W{1'b0}}}, iss[dbg_k]);
                end else begin
                    dbg_age[dbg_k] = 0;
                end
            end
        end
    end
`endif
endmodule
`default_nettype wire
