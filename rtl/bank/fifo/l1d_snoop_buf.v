`default_nettype none
`include "l1d_defines.vh"
module l1d_snoop_buf #(`L1D_PARAMS) (
    clk, rst,
    new_snoop_valid, new_snoop_line_addr, new_snoop_invalidate, new_snoop_ready,
    amo_lock_snoop_hold, amo_lock_line, amo_read_in_pipeline, amo_lock_set_valid, amo_lock_set_line,
    offer_valid, offer_entry_id, offer_line_addr, offer_invalidate, offer_granted,
    s2_action_valid, s2_action_entry_id, s2_action_code, s2_action_wait_id,
    mshr_entry_freed, victim_slot_freed,
    buffer_empty
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam N = (SNP_BUF_DEPTH < 2) ? 2 : SNP_BUF_DEPTH;
    input  wire                    clk;
    input  wire                    rst;
    input  wire                    new_snoop_valid;
    input  wire [LINE_ADDR_W-1:0]  new_snoop_line_addr;
    input  wire                    new_snoop_invalidate;
    output wire                    new_snoop_ready;
    input  wire                    amo_lock_snoop_hold;
    input  wire [LINE_ADDR_W-1:0]  amo_lock_line;
    input  wire                    amo_read_in_pipeline;
    input  wire                    amo_lock_set_valid;
    input  wire [LINE_ADDR_W-1:0]  amo_lock_set_line;
    output wire                    offer_valid;
    output wire [SNP_ID_W-1:0]     offer_entry_id;
    output wire [LINE_ADDR_W-1:0]  offer_line_addr;
    output wire                    offer_invalidate;
    input  wire                    offer_granted;
    input  wire                    s2_action_valid;
    input  wire [SNP_ID_W-1:0]     s2_action_entry_id;
    input  wire [1:0]              s2_action_code;
    input  wire [WID_W-1:0]        s2_action_wait_id;
    input  wire [MSHR_ENTRIES-1:0] mshr_entry_freed;
    input  wire [VC_SLOTS-1:0]     victim_slot_freed;
    output wire                    buffer_empty;
    reg                   ev  [0:N-1];
    reg [1:0]             hs  [0:N-1];
    reg [LINE_ADDR_W-1:0] el  [0:N-1];
    reg                   ei  [0:N-1];
    reg [WID_W-1:0]       wid [0:N-1];
    reg [N-1:0]           sm  [0:N-1];
    reg [N-1:0]           lm_q;
    wire [N-1:0]        used;
    wire [N-1:0]        free_g;
    reg  [N-1:0]        free_g_r;
    reg                 free_seen;
    integer             fi;
    always @* begin
        free_seen = 1'b0;
        for (fi = 0; fi < N; fi = fi + 1) begin
            free_g_r[fi] = ~used[fi] & ~free_seen;
            free_seen    = free_seen | ~used[fi];
        end
    end
    assign free_g = free_g_r;
    wire                any_free = ~&used;
    reg  [SNP_ID_W-1:0] free_id;
    integer             fj;
    always @* begin
        free_id = {SNP_ID_W{1'b0}};
        for (fj = 0; fj < N; fj = fj + 1)
            if (free_g[fj]) free_id = free_id | fj[SNP_ID_W-1:0];
    end
    assign new_snoop_ready = any_free;
    wire do_alloc   = new_snoop_valid && any_free;
    wire [N*N-1:0] older_flat;
    wire [N-1:0]   infl;
    reg  [N-1:0]   cand;
    integer c;
    integer o;
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_ent
            assign used[g] = ev[g];
            assign infl[g] = ev[g] && (hs[g] == SH_INFL);
        end
    endgenerate
    always @* begin
        for (c = 0; c < N; c = c + 1) begin
            cand[c] = ev[c] && (hs[c] == SH_READY) && !(amo_lock_snoop_hold && lm_q[c]) && !amo_read_in_pipeline;
            for (o = 0; o < N; o = o + 1)
                if (o != c && ev[o] && older_flat[o*N + c] && sm[o][c])
                    cand[c] = 1'b0;
        end
    end
    wire any_cand;
    wire [N-1:0] oldest_oh;
    l1d_age_matrix #(.N(N), .IDX_W(SNP_ID_W), .ONEHOT_ALLOC(1), .ONEHOT_ENC(1)) u_age (
        .clk             (clk),
        .rst             (rst),
        .allocate_valid  (do_alloc),
        .allocate_index  ({SNP_ID_W{1'b0}}),
        .allocate_onehot (free_g),
        .candidate_mask  (cand),
        .older_than_flat (older_flat),
        .oldest_onehot   (oldest_oh),
        .oldest_index    (offer_entry_id),
        .any_candidate   (any_cand)
    );
    assign offer_valid = any_cand && !(|infl);
    wire [N-1:0] pick = {oldest_oh[N-1:1], ~|oldest_oh[N-1:1]};
    reg  [LINE_ADDR_W-1:0] offer_line_r;
    reg                    offer_inv_r;
    integer                pk;
    always @* begin
        offer_line_r = {LINE_ADDR_W{1'b0}};
        offer_inv_r  = 1'b0;
        for (pk = 0; pk < N; pk = pk + 1) begin
            offer_line_r = offer_line_r | ({LINE_ADDR_W{pick[pk]}} & el[pk]);
            offer_inv_r  = offer_inv_r  | (pick[pk] & ei[pk]);
        end
    end
    assign offer_line_addr  = offer_line_r;
    assign offer_invalidate = offer_inv_r;
    assign buffer_empty     = ~|used;
    function [1:0] wait_state;
        input [1:0]       code;
        input [WID_W-1:0] id;
        begin
            case (code)
                SACT_WMSHR: wait_state = mshr_entry_freed[id[MSHR_ID_W-1:0]] ? SH_READY : SH_WMSHR;
                SACT_WVC:   wait_state = victim_slot_freed[id[VC_ID_W-1:0]]     ? SH_READY : SH_WVC;
                default:    wait_state = SH_READY;
            endcase
        end
    endfunction
    wire [N-1:0] eq_new_el;
    wire [N-1:0] eq_el_set;
    wire         eq_new_set  = (new_snoop_line_addr == amo_lock_set_line);
    wire         eq_new_lock = (new_snoop_line_addr == amo_lock_line);
    generate
        for (g = 0; g < N; g = g + 1) begin : g_cmp
            assign eq_new_el[g] = (new_snoop_line_addr == el[g]);
            assign eq_el_set[g] = (el[g] == amo_lock_set_line);
        end
    endgenerate
    integer s;
    integer j2;
    always @(posedge clk) begin
        if (rst) begin
            for (s = 0; s < N; s = s + 1) begin
                ev[s]  <= 1'b0;
                hs[s]  <= SH_READY;
                el[s]  <= {LINE_ADDR_W{1'b0}};
                ei[s]  <= 1'b0;
                wid[s] <= {WID_W{1'b0}};
                sm[s]  <= {N{1'b1}};
            end
            lm_q <= {N{1'b1}};
        end else begin
            for (s = 0; s < N; s = s + 1) begin
                case (hs[s])
                    SH_WMSHR: if (mshr_entry_freed[wid[s][MSHR_ID_W-1:0]]) hs[s] <= SH_READY;
                    SH_WVC:   if (victim_slot_freed[wid[s][VC_ID_W-1:0]])     hs[s] <= SH_READY;
                    default: ;
                endcase
                if (do_alloc && free_g[s]) begin
                    ev[s] <= 1'b1;
                    hs[s] <= SH_READY;
                    el[s] <= new_snoop_line_addr;
                    ei[s] <= new_snoop_invalidate;
                end
                for (j2 = 0; j2 < N; j2 = j2 + 1) begin
                    if (j2 != s) begin
                        if (do_alloc && free_g[s])       sm[s][j2] <= eq_new_el[j2];
                        else if (do_alloc && free_g[j2]) sm[s][j2] <= eq_new_el[s];
                    end
                end
                if (amo_lock_set_valid)
                    lm_q[s] <= (do_alloc && free_g[s]) ? eq_new_set : eq_el_set[s];
                else if (do_alloc && free_g[s])
                    lm_q[s] <= eq_new_lock;
                if (offer_granted && oldest_oh[s])
                    hs[s] <= SH_INFL;
                if (s2_action_valid && (s2_action_entry_id == s)) begin
                    if (s2_action_code == SACT_DONE) begin
                        ev[s] <= 1'b0;
                        hs[s] <= SH_READY;
                    end else begin
                        hs[s]  <= wait_state(s2_action_code, s2_action_wait_id);
                        wid[s] <= s2_action_wait_id;
                    end
                end
            end
        end
    end
`ifdef L1D_DEBUG
    reg [1:0] dbg_ps  [0:N-1];
    reg       dbg_pv  [0:N-1];
    integer   dbg_age [0:N-1];
    integer   dbg_k;
    initial for (dbg_k = 0; dbg_k < N; dbg_k = dbg_k + 1) begin
        dbg_ps[dbg_k] = SH_READY; dbg_pv[dbg_k] = 1'b0; dbg_age[dbg_k] = 0;
    end
    always @(posedge clk) begin
        if (!rst) begin
            if (do_alloc)
                $display("[%0t] L1D SNPB %m snoop in: entry %0d %s line=%h", $time, free_id,
                         new_snoop_invalidate ? "INV " : "READ", {new_snoop_line_addr, {OFFSET_W{1'b0}}});
            if (new_snoop_valid && !any_free)
                $display("[%0t] L1D SNPB %m ERROR snoop pushed while the buffer is full", $time);
            for (dbg_k = 0; dbg_k < N; dbg_k = dbg_k + 1) begin
                if (ev[dbg_k] != dbg_pv[dbg_k] || (ev[dbg_k] && hs[dbg_k] != dbg_ps[dbg_k])) begin
                    if (ev[dbg_k])
                        $display("[%0t] L1D SNPB %m entry %0d state %0d line=%h wait_id=%0d",
                                 $time, dbg_k, hs[dbg_k], {el[dbg_k], {OFFSET_W{1'b0}}}, wid[dbg_k]);
                    dbg_pv[dbg_k]  = ev[dbg_k];
                    dbg_ps[dbg_k]  = hs[dbg_k];
                    dbg_age[dbg_k] = 0;
                end else if (ev[dbg_k]) begin
                    dbg_age[dbg_k] = dbg_age[dbg_k] + 1;
                    if (dbg_age[dbg_k] % `L1D_DBG_WD == 0)
                        $display("[%0t] L1D SNPB %m STUCK entry %0d in state %0d for %0d cycles line=%h locked=%b (0 READY; 2 WMSHR; 3 WVC)",
                                 $time, dbg_k, hs[dbg_k], dbg_age[dbg_k], {el[dbg_k], {OFFSET_W{1'b0}}},
                                 amo_lock_snoop_hold && el[dbg_k] == amo_lock_line);
                end
            end
        end
    end
`endif
endmodule
`default_nettype wire
