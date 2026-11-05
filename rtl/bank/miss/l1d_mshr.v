`define L1D_CHECK_M7
`default_nettype none
`include "l1d_defines.vh"
module l1d_mshr #(`L1D_PARAMS) (
    clk, rst,
    lookup_line_addr, lookup_hit, lookup_entry_id, lookup_entry_has_data,
    allocate_valid, allocate_line_addr, allocate_is_swap, allocate_swap_line_data, allocate_swap_dirty, allocate_swap_shared, allocate_swap_vc_slot,
    allocate_unique_read, allocate_seat, allocate_is_write, allocate_no_response, allocate_access_size, allocate_master_id, allocate_rob_index, allocate_byte_offset, allocate_store_data, can_allocate, allocate_entry_id,
    axi_read_req_valid, axi_read_req_ready, axi_read_req_line_addr, axi_read_req_sub_id, axi_read_req_unique,
    axi_read_beat_valid, axi_read_beat_sub_id, axi_read_beat_data, axi_read_beat_last, axi_read_beat_error, axi_read_beat_shared,
    response_valid, response_packet, response_seat, response_taken,
    refill_token_valid, refill_token_entry_id, refill_token_line_addr, refill_token_granted,
    s1_install_entry_id, s1_install_state, s1_install_is_swap, s1_install_vc_slot,
    s2_install_entry_id, s2_install_line_data,
    s1_token_held_valid, s1_token_held_entry_id, s2_install_done_valid, s2_install_done_entry_id,
    any_entry_busy, entry_freed_pulses
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam N = MSHR_ENTRIES;
    input  wire                        clk;
    input  wire                        rst;
    input  wire [LINE_ADDR_W-1:0]      lookup_line_addr;
    output wire                        lookup_hit;
    output wire [MSHR_ID_W-1:0]        lookup_entry_id;
    output wire                        lookup_entry_has_data;
    input  wire                        allocate_valid;
    input  wire [LINE_ADDR_W-1:0]      allocate_line_addr;
    input  wire                        allocate_is_swap;
    input  wire [LINE_W-1:0]           allocate_swap_line_data;
    input  wire                        allocate_swap_dirty;
    input  wire                        allocate_swap_shared;
    input  wire [VC_ID_W-1:0]          allocate_swap_vc_slot;
    input  wire                        allocate_unique_read;
    input  wire [SEAT_W-1:0]           allocate_seat;
    input  wire                        allocate_is_write;
    input  wire                        allocate_no_response;
    input  wire [MEM_SIZE_BITS-1:0]    allocate_access_size;
    input  wire [MASTER_ID_BITS-1:0]   allocate_master_id;
    input  wire [IDX_BITS-1:0]         allocate_rob_index;
    input  wire [OFFSET_W-1:0]         allocate_byte_offset;
    input  wire [WRITE_DATA_WIDTH-1:0] allocate_store_data;
    output wire                        can_allocate;
    output wire [MSHR_ID_W-1:0]        allocate_entry_id;
    output wire                        axi_read_req_valid;
    input  wire                        axi_read_req_ready;
    output wire [LINE_ADDR_W-1:0]      axi_read_req_line_addr;
    output wire [MSHR_ID_W-1:0]        axi_read_req_sub_id;
    output wire                        axi_read_req_unique;
    input  wire                        axi_read_beat_valid;
    input  wire [MSHR_ID_W-1:0]        axi_read_beat_sub_id;
    input  wire [AXI_DATA_W-1:0]       axi_read_beat_data;
    input  wire                        axi_read_beat_last;
    input  wire                        axi_read_beat_error;
    input  wire                        axi_read_beat_shared;
    output wire                        response_valid;
    output wire [RESP_W-1:0]           response_packet;
    output wire [SEAT_W-1:0]           response_seat;
    input  wire                        response_taken;
    output wire                        refill_token_valid;
    output wire [MSHR_ID_W-1:0]        refill_token_entry_id;
    output wire [LINE_ADDR_W-1:0]      refill_token_line_addr;
    input  wire                        refill_token_granted;
    input  wire [MSHR_ID_W-1:0]        s1_install_entry_id;
    output wire [1:0]                  s1_install_state;
    output wire                        s1_install_is_swap;
    output wire [VC_ID_W-1:0]          s1_install_vc_slot;
    input  wire [MSHR_ID_W-1:0]        s2_install_entry_id;
    output wire [LINE_W-1:0]           s2_install_line_data;
    input  wire                        s1_token_held_valid;
    input  wire [MSHR_ID_W-1:0]        s1_token_held_entry_id;
    input  wire                        s2_install_done_valid;
    input  wire [MSHR_ID_W-1:0]        s2_install_done_entry_id;
    output wire                        any_entry_busy;
    output wire [N-1:0]                entry_freed_pulses;
    wire [N-1:0]               e_busy, e_ar, e_resp, e_tok, e_swap, e_uniq, e_hasd;
    wire [2*N-1:0]             e_ist;
    wire [N*LINE_ADDR_W-1:0]   e_line;
    wire [N*RESP_W-1:0]        e_pkt;
    wire [N*SEAT_W-1:0]        e_seat;
    wire [N*LINE_W-1:0]        e_data;
    wire [N*VC_ID_W-1:0]       e_slot;
    wire [N-1:0] lk_match;
    l1d_cam #(.N(N), .KEY_W(LINE_ADDR_W)) u_cam (
        .stored_keys  (e_line),
        .stored_valid (e_busy),
        .search_key   (lookup_line_addr),
        .match_onehot (lk_match)
    );
    l1d_pri_enc #(.N(N), .IDX_W(MSHR_ID_W)) u_lk (
        .request_bits (lk_match), .lowest_set_index (lookup_entry_id), .any_set (lookup_hit)
    );
    l1d_pri_enc #(.N(N), .IDX_W(MSHR_ID_W)) u_free (
        .request_bits (~e_busy), .lowest_set_index (allocate_entry_id), .any_set (can_allocate)
    );
    reg [N-1:0] free_g;
    reg         busy_below;
    integer     f;
    always @* begin
        busy_below = 1'b1;
        for (f = 0; f < N; f = f + 1) begin
            free_g[f]  = ~e_busy[f] & busy_below;
            busy_below = busy_below & e_busy[f];
        end
    end
    wire [N-1:0]         ar_g, rs_g, tk_g;
    wire [MSHR_ID_W-1:0] ar_i, rs_i, tk_i;
    l1d_arb_rr #(.N(N), .IDX_W(MSHR_ID_W)) u_ar_arb (
        .clk(clk), .rst(rst), .request_bits(e_ar), .grant_taken(axi_read_req_ready), .grant_onehot(ar_g), .grant_index(ar_i), .any_request(axi_read_req_valid)
    );
    l1d_arb_rr #(.N(N), .IDX_W(MSHR_ID_W)) u_rs_arb (
        .clk(clk), .rst(rst), .request_bits(e_resp), .grant_taken(response_taken), .grant_onehot(rs_g), .grant_index(rs_i), .any_request(response_valid)
    );
    l1d_arb_rr #(.N(N), .IDX_W(MSHR_ID_W)) u_tk_arb (
        .clk(clk), .rst(rst), .request_bits(e_tok), .grant_taken(refill_token_granted), .grant_onehot(tk_g), .grant_index(tk_i), .any_request(refill_token_valid)
    );
    wire [N-1:0] e_ar_c, e_resp_c, e_tok_c;
    wire [N-1:0] ar_gc, rs_gc, tk_gc;
    l1d_arb_rr #(.N(N), .IDX_W(MSHR_ID_W)) u_ar_arb_c (
        .clk(clk), .rst(rst), .request_bits(e_ar_c), .grant_taken(axi_read_req_ready), .grant_onehot(ar_gc), .grant_index(), .any_request()
    );
    l1d_arb_rr #(.N(N), .IDX_W(MSHR_ID_W)) u_rs_arb_c (
        .clk(clk), .rst(rst), .request_bits(e_resp_c), .grant_taken(response_taken), .grant_onehot(rs_gc), .grant_index(), .any_request()
    );
    l1d_arb_rr #(.N(N), .IDX_W(MSHR_ID_W)) u_tk_arb_c (
        .clk(clk), .rst(rst), .request_bits(e_tok_c), .grant_taken(refill_token_granted), .grant_onehot(tk_gc), .grant_index(), .any_request()
    );
    (* keep *) reg [N-1:0] m7_ar_mask;
    wire [N-1:0] m7_ar_next, m7_ar_masked, m7_ar_gm, m7_ar_gu;
    wire [N-1:0] m7_ar_sm, m7_ar_su;
    wire m7_ar_use = |m7_ar_masked;
    genvar m7_ar_j;
    generate
        for (m7_ar_j = 0; m7_ar_j < N; m7_ar_j = m7_ar_j + 1) begin : g_m7_ar
            if (m7_ar_j == 0) begin : g_first
                assign m7_ar_next[m7_ar_j] = 1'b0;
                assign m7_ar_gm[m7_ar_j] = m7_ar_masked[m7_ar_j];
                assign m7_ar_gu[m7_ar_j] = e_ar[m7_ar_j];
            end else begin : g_rest
                assign m7_ar_next[m7_ar_j] = |ar_g[m7_ar_j-1:0];
                assign m7_ar_gm[m7_ar_j] = m7_ar_masked[m7_ar_j] & ~|m7_ar_masked[m7_ar_j-1:0];
                assign m7_ar_gu[m7_ar_j] = e_ar[m7_ar_j] & ~|e_ar[m7_ar_j-1:0];
            end
        end
    endgenerate
    (* keep *) always @(posedge clk) begin
        if (rst) m7_ar_mask <= {N{1'b0}};
        else if (axi_read_req_ready && axi_read_req_valid) m7_ar_mask <= m7_ar_next;
    end
    assign m7_ar_masked = e_ar & m7_ar_mask;
    assign m7_ar_sm = {m7_ar_gm[N-1:1], ~|m7_ar_gm[N-1:1]};
    assign m7_ar_su = {m7_ar_gu[N-1:1], ~|m7_ar_gu[N-1:1]};
    (* keep *) reg [N-1:0] m7_rs_mask;
    wire [N-1:0] m7_rs_next, m7_rs_masked, m7_rs_gm, m7_rs_gu;
    wire [N-1:0] m7_rs_sm, m7_rs_su;
    wire m7_rs_use = |m7_rs_masked;
    genvar m7_rs_j;
    generate
        for (m7_rs_j = 0; m7_rs_j < N; m7_rs_j = m7_rs_j + 1) begin : g_m7_rs
            if (m7_rs_j == 0) begin : g_first
                assign m7_rs_next[m7_rs_j] = 1'b0;
                assign m7_rs_gm[m7_rs_j] = m7_rs_masked[m7_rs_j];
                assign m7_rs_gu[m7_rs_j] = e_resp[m7_rs_j];
            end else begin : g_rest
                assign m7_rs_next[m7_rs_j] = |rs_g[m7_rs_j-1:0];
                assign m7_rs_gm[m7_rs_j] = m7_rs_masked[m7_rs_j] & ~|m7_rs_masked[m7_rs_j-1:0];
                assign m7_rs_gu[m7_rs_j] = e_resp[m7_rs_j] & ~|e_resp[m7_rs_j-1:0];
            end
        end
    endgenerate
    (* keep *) always @(posedge clk) begin
        if (rst) m7_rs_mask <= {N{1'b0}};
        else if (response_taken && response_valid) m7_rs_mask <= m7_rs_next;
    end
    assign m7_rs_masked = e_resp & m7_rs_mask;
    assign m7_rs_sm = {m7_rs_gm[N-1:1], ~|m7_rs_gm[N-1:1]};
    assign m7_rs_su = {m7_rs_gu[N-1:1], ~|m7_rs_gu[N-1:1]};
    (* keep *) reg [N-1:0] m7_tk_mask;
    wire [N-1:0] m7_tk_next, m7_tk_masked, m7_tk_gm, m7_tk_gu;
    wire [N-1:0] m7_tk_sm, m7_tk_su;
    wire m7_tk_use = |m7_tk_masked;
    genvar m7_tk_j;
    generate
        for (m7_tk_j = 0; m7_tk_j < N; m7_tk_j = m7_tk_j + 1) begin : g_m7_tk
            if (m7_tk_j == 0) begin : g_first
                assign m7_tk_next[m7_tk_j] = 1'b0;
                assign m7_tk_gm[m7_tk_j] = m7_tk_masked[m7_tk_j];
                assign m7_tk_gu[m7_tk_j] = e_tok[m7_tk_j];
            end else begin : g_rest
                assign m7_tk_next[m7_tk_j] = |tk_g[m7_tk_j-1:0];
                assign m7_tk_gm[m7_tk_j] = m7_tk_masked[m7_tk_j] & ~|m7_tk_masked[m7_tk_j-1:0];
                assign m7_tk_gu[m7_tk_j] = e_tok[m7_tk_j] & ~|e_tok[m7_tk_j-1:0];
            end
        end
    endgenerate
    (* keep *) always @(posedge clk) begin
        if (rst) m7_tk_mask <= {N{1'b0}};
        else if (refill_token_granted && refill_token_valid) m7_tk_mask <= m7_tk_next;
    end
    assign m7_tk_masked = e_tok & m7_tk_mask;
    assign m7_tk_sm = {m7_tk_gm[N-1:1], ~|m7_tk_gm[N-1:1]};
    assign m7_tk_su = {m7_tk_gu[N-1:1], ~|m7_tk_gu[N-1:1]};
    wire [N-1:0] ar_sel = {ar_g[N-1:1], ~|ar_g[N-1:1]};
    wire [N-1:0] rs_sel = {rs_g[N-1:1], ~|rs_g[N-1:1]};
    wire [N-1:0] tk_sel = {tk_g[N-1:1], ~|tk_g[N-1:1]};
    wire [LINE_ADDR_W-1:0] ar_line, tk_line;
    wire ar_unique;
    wire [RESP_W-1:0] rs_pkt;
    wire [SEAT_W-1:0] rs_seat;
    reg [LINE_ADDR_W-1:0] m7_am, m7_au, m7_km, m7_ku;
    reg m7_um, m7_uu;
    reg [RESP_W-1:0] m7_pm, m7_pu;
    reg [SEAT_W-1:0] m7_tm, m7_tu;
    integer m7k;
    always @* begin
        m7_am = {LINE_ADDR_W{1'b0}}; m7_au = {LINE_ADDR_W{1'b0}};
        m7_km = {LINE_ADDR_W{1'b0}}; m7_ku = {LINE_ADDR_W{1'b0}};
        m7_pm = {RESP_W{1'b0}}; m7_pu = {RESP_W{1'b0}};
        m7_tm = {SEAT_W{1'b0}}; m7_tu = {SEAT_W{1'b0}};
        m7_um = 1'b0; m7_uu = 1'b0;
        for (m7k = 0; m7k < N; m7k = m7k + 1) begin
            m7_am = m7_am | ({LINE_ADDR_W{m7_ar_sm[m7k]}} & e_line[m7k*LINE_ADDR_W +: LINE_ADDR_W]);
            m7_au = m7_au | ({LINE_ADDR_W{m7_ar_su[m7k]}} & e_line[m7k*LINE_ADDR_W +: LINE_ADDR_W]);
            m7_km = m7_km | ({LINE_ADDR_W{m7_tk_sm[m7k]}} & e_line[m7k*LINE_ADDR_W +: LINE_ADDR_W]);
            m7_ku = m7_ku | ({LINE_ADDR_W{m7_tk_su[m7k]}} & e_line[m7k*LINE_ADDR_W +: LINE_ADDR_W]);
            m7_pm = m7_pm | ({RESP_W{m7_rs_sm[m7k]}} & e_pkt[m7k*RESP_W +: RESP_W]);
            m7_pu = m7_pu | ({RESP_W{m7_rs_su[m7k]}} & e_pkt[m7k*RESP_W +: RESP_W]);
            m7_tm = m7_tm | ({SEAT_W{m7_rs_sm[m7k]}} & e_seat[m7k*SEAT_W +: SEAT_W]);
            m7_tu = m7_tu | ({SEAT_W{m7_rs_su[m7k]}} & e_seat[m7k*SEAT_W +: SEAT_W]);
            m7_um = m7_um | (m7_ar_sm[m7k] & e_uniq[m7k]);
            m7_uu = m7_uu | (m7_ar_su[m7k] & e_uniq[m7k]);
        end
    end
    assign ar_line = m7_ar_use ? m7_am : m7_au;
    assign ar_unique = m7_ar_use ? m7_um : m7_uu;
    assign tk_line = m7_tk_use ? m7_km : m7_ku;
    assign rs_pkt = m7_rs_use ? m7_pm : m7_pu;
    assign rs_seat = m7_rs_use ? m7_tm : m7_tu;
    assign axi_read_req_line_addr   = ar_line;
    assign axi_read_req_sub_id    = ar_i;
    assign axi_read_req_unique = ar_unique;
    assign response_packet  = rs_pkt;
    assign response_seat = rs_seat;
    assign refill_token_entry_id    = tk_i;
    assign refill_token_line_addr  = tk_line;
    reg [N-1:0] lk_first;
    reg         lk_seen;
    integer     q;
    always @* begin
        lk_seen = 1'b0;
        for (q = 0; q < N; q = q + 1) begin
            lk_first[q] = lk_match[q] & ~lk_seen;
            lk_seen     = lk_seen | lk_match[q];
        end
    end
    assign lookup_entry_has_data = |(lk_first & e_hasd);
    assign s1_install_state  = e_ist[2*s1_install_entry_id +: 2];
    assign s1_install_is_swap   = e_swap[s1_install_entry_id];
    assign s1_install_vc_slot   = e_slot[s1_install_entry_id*VC_ID_W +: VC_ID_W];
    assign s2_install_line_data   = e_data[s2_install_entry_id*LINE_W +: LINE_W];
    assign any_entry_busy  = |e_busy;
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_entry
            l1d_mshr_entry #(`L1D_PARAMS_PASS) u_entry (
                .clk                     (clk),
                .rst                     (rst),
                .allocate_valid          (allocate_valid && free_g[g]),
                .allocate_line_addr      (allocate_line_addr),
                .allocate_is_swap        (allocate_is_swap),
                .allocate_swap_line_data (allocate_swap_line_data),
                .allocate_swap_dirty     (allocate_swap_dirty),
                .allocate_swap_shared    (allocate_swap_shared),
                .allocate_swap_vc_slot   (allocate_swap_vc_slot),
                .allocate_unique_read    (allocate_unique_read),
                .allocate_seat           (allocate_seat),
                .allocate_is_write       (allocate_is_write),
                .allocate_no_response    (allocate_no_response),
                .allocate_access_size    (allocate_access_size),
                .allocate_master_id      (allocate_master_id),
                .allocate_rob_index      (allocate_rob_index),
                .allocate_byte_offset    (allocate_byte_offset),
                .allocate_store_data     (allocate_store_data),
                .axi_read_addr_accepted  (axi_read_req_ready && ar_gc[g]),
                .axi_read_beat_valid     (axi_read_beat_valid && (axi_read_beat_sub_id == g)),
                .axi_read_beat_data      (axi_read_beat_data),
                .axi_read_beat_last      (axi_read_beat_last),
                .axi_read_beat_error     (axi_read_beat_error),
                .axi_read_beat_shared    (axi_read_beat_shared),
                .response_taken          (response_taken && rs_gc[g]),
                .refill_token_granted    (refill_token_granted && tk_gc[g]),
                .refill_token_held_by_s1 (s1_token_held_valid && (s1_token_held_entry_id == g)),
                .install_done_by_s2      (s2_install_done_valid && (s2_install_done_entry_id == g)),
                .entry_busy              (e_busy[g]),
                .entry_line_addr         (e_line[g*LINE_ADDR_W +: LINE_ADDR_W]),
                .axi_read_addr_request   (e_ar[g]),
                .axi_read_is_unique      (e_uniq[g]),
                .response_request        (e_resp[g]),
                .response_packet         (e_pkt[g*RESP_W +: RESP_W]),
                .response_seat           (e_seat[g*SEAT_W +: SEAT_W]),
                .refill_token_request    (e_tok[g]),
                .axi_read_addr_request_ctrl (e_ar_c[g]),
                .response_request_ctrl      (e_resp_c[g]),
                .refill_token_request_ctrl  (e_tok_c[g]),
                .line_buffer_data        (e_data[g*LINE_W +: LINE_W]),
                .install_state           (e_ist[2*g +: 2]),
                .line_buffer_has_data    (e_hasd[g]),
                .entry_is_swap           (e_swap[g]),
                .entry_swap_vc_slot      (e_slot[g*VC_ID_W +: VC_ID_W]),
                .entry_freed_pulse       (entry_freed_pulses[g])
            );
        end
    endgenerate
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            if (allocate_valid && !can_allocate)
                $display("[%0t] L1D MSHR %m ERROR allocation while every entry is busy", $time);
            if (allocate_valid && lookup_hit && !allocate_is_swap)
                $display("[%0t] L1D MSHR %m ERROR fetch allocated for line %h, which entry %0d already has",
                         $time, {allocate_line_addr, {OFFSET_W{1'b0}}}, lookup_entry_id);
            if (axi_read_beat_valid && !e_busy[axi_read_beat_sub_id])
                $display("[%0t] L1D MSHR %m ERROR R beat for entry %0d, which is free (wrong RID from memory?)",
                         $time, axi_read_beat_sub_id);
        end
    end
`endif
endmodule
`default_nettype wire
