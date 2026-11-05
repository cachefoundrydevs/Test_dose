`default_nettype none
`include "l1d_defines.vh"
module l1d_lsu_req_buf #(`L1D_PARAMS) (
    clk, rst,
    new_request_valid, new_request_packet, new_request_ready, new_request_granted, new_request_seat,
    offer_valid, offer_seat, offer_request_packet, offer_granted,
    s2_action_valid, s2_action_seat, s2_action_code, s2_action_wait_id,
    s3_done_valid, s3_done_seat,
    mshr_entry_freed, victim_slot_freed, nc_entry_freed,
    amo_lock_valid, amo_lock_line, amo_lock_set_valid, amo_lock_set_line,
    buffer_empty, seat_blocked
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam N = LSU_BUF_DEPTH;
    input  wire                 clk;
    input  wire                 rst;
    input  wire                 new_request_valid;
    input  wire [REQ_W-1:0]     new_request_packet;
    output wire                 new_request_ready;
    input  wire                 new_request_granted;
    output wire [SEAT_W-1:0]    new_request_seat;
    output wire                 offer_valid;
    output wire [SEAT_W-1:0]    offer_seat;
    output wire [REQ_W-1:0]     offer_request_packet;
    input  wire                 offer_granted;
    input  wire                 s2_action_valid;
    input  wire [SEAT_W-1:0]    s2_action_seat;
    input  wire [2:0]           s2_action_code;
    input  wire [WID_W-1:0]     s2_action_wait_id;
    input  wire                 s3_done_valid;
    input  wire [SEAT_W-1:0]    s3_done_seat;
    input  wire [MSHR_ENTRIES-1:0] mshr_entry_freed;
    input  wire [VC_SLOTS-1:0]     victim_slot_freed;
    input  wire                    nc_entry_freed;
    input  wire                    amo_lock_valid;
    input  wire [LINE_ADDR_W-1:0]  amo_lock_line;
    input  wire                    amo_lock_set_valid;
    input  wire [LINE_ADDR_W-1:0]  amo_lock_set_line;
    output wire                 buffer_empty;
    output wire [LSU_BUF_DEPTH-1:0] seat_blocked;
    reg [2:0]         st   [0:N-1];
    reg [WID_W-1:0]   wid  [0:N-1];
    reg [REQ_W-1:0]   req  [0:N-1];
    reg [N-1:0]       occ_q;
    reg [N-1:0]       rdy_q;
    reg [N-1:0]       pb   [0:N-1];
    reg [N-1:0]       am   [0:N-1];
    reg [N-1:0]       lm_q;
    reg [N-1:0]       blk0_q;
    reg [N-1:0]       blka_q;
    reg [N-1:0]       nq_q;
    reg [N-1:0]       eqn_q;
    reg [N-1:0]       cnd_q;
    reg               oan_q;
    reg  [N-1:0]             is_store;
    reg  [N-1:0]             is_amor;
    reg  [N-1:0]             is_amow;
    wire [N*LINE_ADDR_W-1:0] lines;
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_seat
            assign lines[g*LINE_ADDR_W +: LINE_ADDR_W] = req[g][REQ_ADDR_LSB + OFFSET_W +: LINE_ADDR_W];
        end
    endgenerate
    wire                   new_store = new_request_packet[REQ_RDWR_BIT] || new_request_packet[REQ_AMO_BIT];
    wire                   new_amor  = new_request_packet[REQ_AMO_BIT] && new_request_packet[REQ_SEQ_BIT] && !new_request_packet[REQ_RDWR_BIT];
    wire                   new_amow  = new_request_packet[REQ_AMO_BIT] && new_request_packet[REQ_SEQ_BIT] &&  new_request_packet[REQ_RDWR_BIT];
    wire [LINE_ADDR_W-1:0] new_line  = new_request_packet[REQ_ADDR_LSB + OFFSET_W +: LINE_ADDR_W];
    wire [N-1:0]           eq_new_seat;
    wire [N-1:0]           eq_seat_set;
    wire                   eq_new_set  = (new_line == amo_lock_set_line);
    wire                   eq_new_lock = (new_line == amo_lock_line);
    generate
        for (g = 0; g < N; g = g + 1) begin : g_cmp
            assign eq_new_seat[g] = (new_line == lines[g*LINE_ADDR_W +: LINE_ADDR_W]);
            assign eq_seat_set[g] = (lines[g*LINE_ADDR_W +: LINE_ADDR_W] == amo_lock_set_line);
        end
    endgenerate
    reg  [N-1:0] free_q;
    reg          any_free_q;
    wire [N-1:0] free_g = free_q;
    wire any_free = any_free_q;
    assign new_request_ready = any_free;
    reg [SEAT_W-1:0] new_seat_r;
    integer ns;
    always @* begin
        new_seat_r = {SEAT_W{1'b0}};
        for (ns = 0; ns < N; ns = ns + 1)
            if (free_g[ns]) new_seat_r = new_seat_r | ns[SEAT_W-1:0];
    end
    assign new_request_seat = new_seat_r;
    wire do_alloc   = new_request_valid && any_free;
    wire [N-1:0] blk_r;
    wire [N-1:0] blk_new;
    wire         v1_new = |(eqn_q & cnd_q);
    wire [N-1:0] blocked;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_blk
            assign blk_r[g]   = amo_lock_valid ? (lm_q[g] ? ~is_amow[g] : blka_q[g]) : blk0_q[g];
            assign blk_new[g] = amo_lock_valid ? (lm_q[g] ? ~is_amow[g] : (v1_new | is_amor[g])) : (v1_new | (is_amor[g] & oan_q));
            assign blocked[g] = nq_q[g] ? blk_new[g] : blk_r[g];
        end
    endgenerate
    wire [N-1:0]   eligible = rdy_q & ~blocked;
    wire [N-1:0]   elig_r   = rdy_q & ~blk_r;
    wire [N*N-1:0] older_flat;
    l1d_age_matrix #(.N(N), .IDX_W(SEAT_W), .ONEHOT_ALLOC(1), .ONEHOT_ENC(1)) u_age (
        .clk             (clk),
        .rst             (rst),
        .allocate_valid  (do_alloc),
        .allocate_index  ({SEAT_W{1'b0}}),
        .allocate_onehot (free_g),
        .candidate_mask  ({N{1'b0}}),
        .older_than_flat (older_flat),
        .oldest_onehot   (),
        .oldest_index    (),
        .any_candidate   ()
    );
    reg [N-1:0]      oldest_oh;
    reg [SEAT_W-1:0] offer_seat_r;
    integer oa2, ob2;
    always @* begin
        offer_seat_r = {SEAT_W{1'b0}};
        for (oa2 = 0; oa2 < N; oa2 = oa2 + 1) begin
            oldest_oh[oa2] = eligible[oa2];
            for (ob2 = 0; ob2 < N; ob2 = ob2 + 1)
                if (ob2 != oa2 && elig_r[ob2] && older_flat[ob2*N + oa2])
                    oldest_oh[oa2] = 1'b0;
            if (oldest_oh[oa2]) offer_seat_r = offer_seat_r | oa2[SEAT_W-1:0];
        end
    end
    assign offer_seat  = offer_seat_r;
    assign offer_valid = |oldest_oh;
    localparam PKC = 4;
    localparam PKW = (REQ_W + PKC - 1) / PKC;
    wire [PKC*N-1:0] pick_p;
    reg  [REQ_W-1:0] offer_pkt_r;
    integer pk, pbit;
    always @* begin
        offer_pkt_r = {REQ_W{1'b0}};
        for (pbit = 0; pbit < REQ_W; pbit = pbit + 1)
            for (pk = 0; pk < N; pk = pk + 1)
                offer_pkt_r[pbit] = offer_pkt_r[pbit] | (pick_p[(pbit / PKW) * N + pk] & req[pk][pbit]);
    end
    assign offer_request_packet = offer_pkt_r;
    assign buffer_empty   = ~|occ_q;
    assign seat_blocked   = blocked;
    reg [2:0] act_st;
    always @* begin
        case (s2_action_code)
            ACT_WMSHR: act_st = mshr_entry_freed[s2_action_wait_id[MSHR_ID_W-1:0]] ? SEAT_READY : SEAT_WMSHR;
            ACT_WANY:  act_st = (|mshr_entry_freed)                                 ? SEAT_READY : SEAT_WANY;
            ACT_WVC:   act_st = victim_slot_freed[s2_action_wait_id[VC_ID_W-1:0]]   ? SEAT_READY : SEAT_WVC;
            ACT_WNC:   act_st = nc_entry_freed                                       ? SEAT_READY : SEAT_WNC;
            ACT_OWNED: act_st = SEAT_OWNED;
            default:   act_st = SEAT_READY;
        endcase
    end
    wire act_ready = (act_st == SEAT_READY);
    wire [N-1:0] ev_alloc = {N{new_request_valid}} & free_g;
    wire [N-1:0] ev_gnt   = {N{offer_granted}} & oldest_oh;
    reg  [N-1:0] ev_act;
    reg  [N-1:0] ev_done;
    reg  [N-1:0] ev_wake;
    reg  [MSHR_ENTRIES-1:0] wm_q [0:N-1];
    reg  [VC_SLOTS-1:0]     wv_q [0:N-1];
    reg  [N-1:0]            wn_q;
    integer e;
    always @* begin
        for (e = 0; e < N; e = e + 1) begin
            ev_act[e]  = s2_action_valid && (s2_action_seat == e);
            ev_done[e] = s3_done_valid   && (s3_done_seat   == e);
            ev_wake[e] = (|(wm_q[e] & mshr_entry_freed)) || (|(wv_q[e] & victim_slot_freed)) || (wn_q[e] && nc_entry_freed);
        end
    end
    wire [MSHR_ENTRIES-1:0] act_wm = (act_st == SEAT_WMSHR) ? ({{(MSHR_ENTRIES-1){1'b0}}, 1'b1} << s2_action_wait_id[MSHR_ID_W-1:0]) :
                                     (act_st == SEAT_WANY)  ? {MSHR_ENTRIES{1'b1}} : {MSHR_ENTRIES{1'b0}};
    wire [VC_SLOTS-1:0]     act_wv = (act_st == SEAT_WVC)   ? ({{(VC_SLOTS-1){1'b0}}, 1'b1} << s2_action_wait_id[VC_ID_W-1:0]) :
                                     {VC_SLOTS{1'b0}};
    wire                    act_wn = (act_st == SEAT_WNC);
    wire [N-1:0] occ_n  = ~ev_done & (occ_q | ev_alloc);
    reg  [N-1:0] free_n;
    reg          free_seen;
    integer      fi;
    always @* begin
        free_seen = 1'b0;
        for (fi = 0; fi < N; fi = fi + 1) begin
            free_n[fi] = ~occ_n[fi] & ~free_seen;
            free_seen  = free_seen | ~occ_n[fi];
        end
    end
    wire [N-1:0] occ_k  = occ_q & ~ev_done;
    wire [N-1:0] ev_alloc_rdy = ev_alloc & ~{N{new_request_granted}};
    wire [N-1:0] rdy_n  = ~ev_done & ((ev_act & {N{act_ready}}) | (~ev_act & ~ev_gnt & (ev_alloc_rdy | ev_wake | rdy_q)));
    reg [N-1:0] pb_col_n [0:N-1];
    reg [N-1:0] am_col_n [0:N-1];
    reg [N-1:0] v1_n, oa_n, lm_n;
    integer c2, o2;
    always @* begin
        for (c2 = 0; c2 < N; c2 = c2 + 1) begin
            for (o2 = 0; o2 < N; o2 = o2 + 1) begin
                if (o2 == c2) begin
                    pb_col_n[c2][o2] = 1'b0;
                    am_col_n[c2][o2] = 1'b0;
                end else if (ev_alloc[c2]) begin
                    pb_col_n[c2][o2] = 1'b0;
                    am_col_n[c2][o2] = occ_k[o2] & is_amor[o2];
                end else begin
                    pb_col_n[c2][o2] = (nq_q[c2] ? (eqn_q[o2] & cnd_q[o2]) : pb[o2][c2]) & ~ev_done[o2];
                    am_col_n[c2][o2] = am[o2][c2] & ~ev_done[o2];
                end
            end
            v1_n[c2] = |pb_col_n[c2];
            oa_n[c2] = |am_col_n[c2];
            if (amo_lock_set_valid) lm_n[c2] = ev_alloc[c2] ? eq_new_set : eq_seat_set[c2];
            else                    lm_n[c2] = ev_alloc[c2] ? eq_new_lock : lm_q[c2];
        end
    end
    wire [N-1:0] blk0_n = v1_n | (is_amor & oa_n);
    wire [N-1:0] blka_n = v1_n | is_amor;
    genvar gc;
    generate
        for (gc = 0; gc < PKC; gc = gc + 1) begin : g_pick
            (* keep *) reg [N-1:0] rdy_c, blk0_c, blka_c, lm_c, nq_c, eqn_c, cnd_c, amow_c, amor_c;
            (* keep *) reg         oan_c;
            (* keep *) always @(posedge clk) begin
                if (rst) begin
                    rdy_c  <= {N{1'b0}};
                    blk0_c <= {N{1'b0}};
                    blka_c <= {N{1'b0}};
                    lm_c   <= {N{1'b0}};
                    nq_c   <= {N{1'b0}};
                    eqn_c  <= {N{1'b0}};
                    cnd_c  <= {N{1'b0}};
                    oan_c  <= 1'b0;
                    amow_c <= {N{1'b0}};
                    amor_c <= {N{1'b0}};
                end else begin
                    rdy_c  <= rdy_n;
                    blk0_c <= blk0_n;
                    blka_c <= blka_n;
                    lm_c   <= lm_n;
                    nq_c   <= ev_alloc;
                    eqn_c  <= eq_new_seat;
                    cnd_c  <= occ_k & (is_store | {N{new_store}});
                    oan_c  <= |(occ_k & is_amor);
                    amow_c <= (ev_alloc & {N{new_amow}}) | (~ev_alloc & is_amow);
                    amor_c <= (ev_alloc & {N{new_amor}}) | (~ev_alloc & is_amor);
                end
            end
            wire         v1_c = |(eqn_c & cnd_c);
            reg  [N-1:0] blkr_c, blkn_c, elig_c, eligr_c, oh_c;
            integer      a, b;
            always @* begin
                for (a = 0; a < N; a = a + 1) begin
                    blkr_c[a]  = amo_lock_valid ? (lm_c[a] ? ~amow_c[a] : blka_c[a]) : blk0_c[a];
                    blkn_c[a]  = amo_lock_valid ? (lm_c[a] ? ~amow_c[a] : (v1_c | amor_c[a])) : (v1_c | (amor_c[a] & oan_c));
                    elig_c[a]  = rdy_c[a] & ~(nq_c[a] ? blkn_c[a] : blkr_c[a]);
                    eligr_c[a] = rdy_c[a] & ~blkr_c[a];
                end
                for (a = 0; a < N; a = a + 1) begin
                    oh_c[a] = elig_c[a];
                    for (b = 0; b < N; b = b + 1)
                        if (b != a && eligr_c[b] && older_flat[b*N + a])
                            oh_c[a] = 1'b0;
                end
            end
            assign pick_p[gc*N +: N] = oh_c;
        end
    endgenerate
    integer s;
    integer j2;
    always @(posedge clk) begin
        if (rst) begin
            for (s = 0; s < N; s = s + 1) begin
                st[s]  <= SEAT_EMPTY;
                wid[s] <= {WID_W{1'b0}};
                pb[s]  <= {N{1'b0}};
                am[s]  <= {N{1'b0}};
                wm_q[s] <= {MSHR_ENTRIES{1'b0}};
                wv_q[s] <= {VC_SLOTS{1'b0}};
            end
            wn_q   <= {N{1'b0}};
            occ_q  <= {N{1'b0}};
            free_q <= {{(N-1){1'b0}}, 1'b1};
            any_free_q <= 1'b1;
            rdy_q  <= {N{1'b0}};
            lm_q   <= {N{1'b0}};
            blk0_q <= {N{1'b0}};
            blka_q <= {N{1'b0}};
            nq_q   <= {N{1'b0}};
            eqn_q  <= {N{1'b0}};
            cnd_q  <= {N{1'b0}};
            oan_q  <= 1'b0;
            is_store <= {N{1'b0}};
            is_amor  <= {N{1'b0}};
            is_amow  <= {N{1'b0}};
        end else begin
            occ_q  <= occ_n;
            free_q <= free_n;
            any_free_q <= ~&occ_n;
            rdy_q  <= rdy_n;
            lm_q   <= lm_n;
            blk0_q <= blk0_n;
            blka_q <= blka_n;
            nq_q   <= ev_alloc;
            eqn_q  <= eq_new_seat;
            cnd_q  <= occ_k & (is_store | {N{new_store}});
            oan_q  <= |(occ_k & is_amor);
            is_store <= (ev_alloc & {N{new_store}}) | (~ev_alloc & is_store);
            is_amor  <= (ev_alloc & {N{new_amor}})  | (~ev_alloc & is_amor);
            is_amow  <= (ev_alloc & {N{new_amow}})  | (~ev_alloc & is_amow);
            for (s = 0; s < N; s = s + 1) begin
                for (j2 = 0; j2 < N; j2 = j2 + 1) begin
                    pb[j2][s] <= pb_col_n[s][j2];
                    am[j2][s] <= am_col_n[s][j2];
                end
                if (ev_done[s] || (!ev_act[s] && ev_wake[s])) begin
                    wm_q[s] <= {MSHR_ENTRIES{1'b0}};
                    wv_q[s] <= {VC_SLOTS{1'b0}};
                    wn_q[s] <= 1'b0;
                end else if (ev_act[s]) begin
                    wm_q[s] <= act_wm;
                    wv_q[s] <= act_wv;
                    wn_q[s] <= act_wn;
                end
                if (ev_wake[s])
                    st[s] <= SEAT_READY;
                if (!occ_q[s])
                    req[s] <= new_request_packet;
                if (ev_alloc[s])
                    st[s]  <= new_request_granted ? SEAT_INFL : SEAT_READY;
                if (ev_gnt[s])
                    st[s] <= SEAT_INFL;
                if (ev_act[s]) begin
                    st[s]  <= act_st;
                    wid[s] <= s2_action_wait_id;
                end
                if (ev_done[s])
                    st[s] <= SEAT_EMPTY;
            end
        end
    end
`ifdef L1D_DEBUG
    function [8*5-1:0] dbg_sname;
        input [2:0] s;
        begin
            case (s)
                SEAT_EMPTY: dbg_sname = "EMPTY";
                SEAT_READY: dbg_sname = "READY";
                SEAT_INFL:  dbg_sname = "INFL";
                SEAT_WMSHR: dbg_sname = "WMSHR";
                SEAT_WANY:  dbg_sname = "WANY";
                SEAT_WVC:   dbg_sname = "WVC";
                SEAT_WNC:   dbg_sname = "WNC";
                default:    dbg_sname = "OWNED";
            endcase
        end
    endfunction
    reg [2:0] dbg_ps  [0:N-1];
    integer   dbg_age [0:N-1];
    integer   dbg_s;
    initial for (dbg_s = 0; dbg_s < N; dbg_s = dbg_s + 1) begin
        dbg_ps[dbg_s] = SEAT_EMPTY; dbg_age[dbg_s] = 0;
    end
    always @(posedge clk) begin
        if (rst) begin
            for (dbg_s = 0; dbg_s < N; dbg_s = dbg_s + 1) begin
                dbg_ps[dbg_s] = SEAT_EMPTY; dbg_age[dbg_s] = 0;
            end
        end else begin
            for (dbg_s = 0; dbg_s < N; dbg_s = dbg_s + 1) begin
                if (st[dbg_s] != dbg_ps[dbg_s]) begin
                    $display("[%0t] L1D SEAT %m seat %0d: %0s -> %0s  idx=%0d %s %s addr=%h wait_id=%0d",
                             $time, dbg_s, dbg_sname(dbg_ps[dbg_s]), dbg_sname(st[dbg_s]),
                             req[dbg_s][REQ_IDX_LSB +: IDX_BITS],
                             (req[dbg_s][REQ_RDWR_BIT] ? "ST" : "LD"),
                             (req[dbg_s][REQ_CACHE_BIT] ? "C " : "NC"),
                             req[dbg_s][REQ_ADDR_LSB +: ADDR_W], wid[dbg_s]);
                    dbg_ps[dbg_s]  = st[dbg_s];
                    dbg_age[dbg_s] = 0;
                end else if (st[dbg_s] != SEAT_EMPTY) begin
                    dbg_age[dbg_s] = dbg_age[dbg_s] + 1;
                    if (dbg_age[dbg_s] % `L1D_DBG_WD == 0)
                        $display("[%0t] L1D SEAT %m STUCK seat %0d in %0s for %0d cycles  idx=%0d %s addr=%h wait_id=%0d blocked_by_older_same_line=%b offered_to_S0=%b",
                                 $time, dbg_s, dbg_sname(st[dbg_s]), dbg_age[dbg_s],
                                 req[dbg_s][REQ_IDX_LSB +: IDX_BITS],
                                 (req[dbg_s][REQ_RDWR_BIT] ? "ST" : "LD"),
                                 req[dbg_s][REQ_ADDR_LSB +: ADDR_W], wid[dbg_s],
                                 blocked[dbg_s], (offer_valid && offer_seat == dbg_s));
                end
            end
        end
    end
`endif
endmodule
`default_nettype wire
