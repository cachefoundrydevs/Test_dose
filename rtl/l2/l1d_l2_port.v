`ifndef L1D_L2_PORT_V
`define L1D_L2_PORT_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_l2_port #(
    `L1D_PARAMS,
    parameter L2_ADDR_W    = 56,
    parameter L2_MID_W     = 2,
    parameter L2_TID_W     = 6,
    parameter L2_MASTER_ID = 0
) (
    clk, rst,
    bank_read_req_valid, bank_read_req_ready, bank_read_req_addr, bank_read_req_burst_len, bank_read_req_size,
    bank_read_req_sub_id, bank_read_req_non_cacheable, bank_read_req_unique,
    bank_read_data_valid, bank_read_data_sub_id, bank_read_data_non_cacheable, bank_read_data, bank_read_data_last,
    bank_read_data_error, bank_read_data_shared,
    bank_write_req_valid, bank_write_req_ready, bank_write_req_addr, bank_write_req_burst_len, bank_write_req_size,
    bank_write_req_sub_id, bank_write_req_non_cacheable, bank_write_req_data, bank_write_req_strobe,
    bank_write_resp_valid, bank_write_resp_sub_id, bank_write_resp_non_cacheable, bank_write_resp_error,
    bank_refill_replay_busy,
    l2_error_pulse,
    l2_req_valid, l2_req_ready, l2_req_pkt,
    l2_resp_valid, l2_resp_ready, l2_resp_pkt, l2_resp_err
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam NB        = NUM_BANKS;
    localparam MASK_W    = LINE_BYTES;
    localparam L2_PKT_W  = 1 + L2_ADDR_W + 1 + L2_MID_W + L2_TID_W + 1 + MASK_W + LINE_W;
    localparam MASK_LO   = LINE_W;
    localparam NC_LO     = MASK_LO + MASK_W;
    localparam TID_LO    = NC_LO + 1;
    localparam MID_LO    = TID_LO + L2_TID_W;
    localparam RW_LO     = MID_LO + L2_MID_W;
    localparam ADDR_LO   = RW_LO + 1;
    localparam US_BIT    = ADDR_LO + L2_ADDR_W;
    localparam NTID      = 1 << L2_TID_W;
    localparam APAD_W    = AXI_ADDR_W - L2_ADDR_W;
    localparam [BEAT_W-1:0]   LAST_BEAT = AXI_BEATS - 1;
    localparam [7:0]          LINE_LEN  = AXI_BEATS - 1;
    localparam [L2_MID_W-1:0] MASTER_ID_C = L2_MASTER_ID;
    localparam ROUTE_W   = 2 + BANK_W + AXI_SUBID_W + BEAT_W;
    input  wire                        clk;
    input  wire                        rst;
    input  wire [NB-1:0]               bank_read_req_valid;
    output wire [NB-1:0]               bank_read_req_ready;
    input  wire [NB*AXI_ADDR_W-1:0]    bank_read_req_addr;
    input  wire [NB*8-1:0]             bank_read_req_burst_len;
    input  wire [NB*3-1:0]             bank_read_req_size;
    input  wire [NB*AXI_SUBID_W-1:0]   bank_read_req_sub_id;
    input  wire [NB-1:0]               bank_read_req_non_cacheable;
    input  wire [NB-1:0]               bank_read_req_unique;
    output wire [NB-1:0]               bank_read_data_valid;
    output wire [AXI_SUBID_W-1:0]      bank_read_data_sub_id;
    output wire                        bank_read_data_non_cacheable;
    output wire [AXI_DATA_W-1:0]       bank_read_data;
    output wire                        bank_read_data_last;
    output wire                        bank_read_data_error;
    output wire                        bank_read_data_shared;
    input  wire [NB-1:0]               bank_write_req_valid;
    output wire [NB-1:0]               bank_write_req_ready;
    input  wire [NB*AXI_ADDR_W-1:0]    bank_write_req_addr;
    input  wire [NB*8-1:0]             bank_write_req_burst_len;
    input  wire [NB*3-1:0]             bank_write_req_size;
    input  wire [NB*AXI_SUBID_W-1:0]   bank_write_req_sub_id;
    input  wire [NB-1:0]               bank_write_req_non_cacheable;
    input  wire [NB*LINE_W-1:0]        bank_write_req_data;
    input  wire [NB*AXI_STRB_W-1:0]    bank_write_req_strobe;
    output wire [NB-1:0]               bank_write_resp_valid;
    output wire [AXI_SUBID_W-1:0]      bank_write_resp_sub_id;
    output wire                        bank_write_resp_non_cacheable;
    output wire                        bank_write_resp_error;
    output wire [NB-1:0]               bank_refill_replay_busy;
    output wire                        l2_error_pulse;
    output wire                        l2_req_valid;
    input  wire                        l2_req_ready;
    output wire [L2_PKT_W-1:0]         l2_req_pkt;
    input  wire                        l2_resp_valid;
    output wire                        l2_resp_ready;
    input  wire [L2_PKT_W-1:0]         l2_resp_pkt;
    input  wire                        l2_resp_err;
    wire [NB-1:0]           read_grant_onehot;
    wire [BANK_W-1:0]       read_grant_bank;
    wire                    read_any;
    wire [NB-1:0]           write_grant_onehot;
    wire [BANK_W-1:0]       write_grant_bank;
    wire                    write_any;
    wire                    pick_write;
    wire                    req_take;
    wire                    read_take;
    wire                    write_take;
    reg                     last_was_write;
    reg  [NTID-1:0]         tid_busy;
    wire [NTID-1:0]         tid_free;
    wire [L2_TID_W-1:0]     tid_new;
    wire                    tid_any_free;
    wire [BANK_W-1:0]       sel_bank;
    wire [AXI_ADDR_W-1:0]   sel_addr;
    wire                    sel_nc;
    wire                    sel_unique;
    wire [AXI_SUBID_W-1:0]  sel_sub;
    wire [2:0]              sel_read_size;
    wire [LINE_W-1:0]       sel_write_line;
    wire [AXI_STRB_W-1:0]   sel_write_strobe;
    wire [OFFSET_W-1:0]     sel_offset;
    wire [BEAT_W-1:0]       sel_beat;
    wire [LINE_W-1:0]       nc_write_line;
    wire [MASK_W-1:0]       nc_write_mask;
    reg  [MASK_W-1:0]       nc_read_mask;
    wire [MASK_W-1:0]       sel_mask;
    wire [LINE_W-1:0]       sel_data;
    wire [L2_PKT_W-1:0]     sel_pkt;
    wire [ROUTE_W-1:0]      sel_route;
    integer                 nc_read_bytes;
    integer                 mask_bit;
    reg                     req_reg_valid;
    reg  [L2_PKT_W-1:0]     req_reg_pkt;
    reg  [ROUTE_W-1:0]      route_table [0:NTID-1];
    wire [L2_TID_W-1:0]     resp_tid;
    wire [ROUTE_W-1:0]      resp_route;
    wire                    resp_take;
    reg                     ans_valid;
    reg                     ans_is_write;
    reg                     ans_nc;
    reg                     ans_shared;
    reg  [BANK_W-1:0]       ans_bank;
    reg  [AXI_SUBID_W-1:0]  ans_sub;
    reg                     ans_err;
    reg  [LINE_W-1:0]       ans_line;
    reg  [BEAT_W-1:0]       ans_beat;
    reg  [BEAT_W-1:0]       ans_end_beat;
    wire                    ans_last;
    wire                    resp_ready_int;
    reg                     err_pulse_q;
    genvar                  bank_idx;
    l1d_arb_rr #(.N(NB), .IDX_W(BANK_W)) u_read_rr (
        .clk          (clk),
        .rst          (rst),
        .request_bits (bank_read_req_valid),
        .grant_taken  (read_take),
        .grant_onehot (read_grant_onehot),
        .grant_index  (read_grant_bank),
        .any_request  (read_any)
    );
    l1d_arb_rr #(.N(NB), .IDX_W(BANK_W)) u_write_rr (
        .clk          (clk),
        .rst          (rst),
        .request_bits (bank_write_req_valid),
        .grant_taken  (write_take),
        .grant_onehot (write_grant_onehot),
        .grant_index  (write_grant_bank),
        .any_request  (write_any)
    );
    assign tid_free = ~tid_busy;
    l1d_pri_enc #(.N(NTID), .IDX_W(L2_TID_W)) u_free_tid (
        .request_bits     (tid_free),
        .lowest_set_index (tid_new),
        .any_set          (tid_any_free)
    );
    assign pick_write = write_any & (~read_any | ~last_was_write);
    assign req_take   = ~req_reg_valid & tid_any_free & (read_any | write_any);
    assign read_take  = req_take & ~pick_write;
    assign write_take = req_take &  pick_write;
    assign bank_read_req_ready  = read_take  ? read_grant_onehot  : {NB{1'b0}};
    assign bank_write_req_ready = write_take ? write_grant_onehot : {NB{1'b0}};
    always @(posedge clk) begin : turn_proc
        if (rst)
            last_was_write <= 1'b0;
        else if (req_take)
            last_was_write <= pick_write;
    end
    assign sel_bank         = pick_write ? write_grant_bank : read_grant_bank;
    assign sel_addr         = pick_write ? bank_write_req_addr[write_grant_bank*AXI_ADDR_W +: AXI_ADDR_W]
                                         : bank_read_req_addr[read_grant_bank*AXI_ADDR_W +: AXI_ADDR_W];
    assign sel_nc           = pick_write ? bank_write_req_non_cacheable[write_grant_bank] : bank_read_req_non_cacheable[read_grant_bank];
    assign sel_unique       = ~pick_write & ~sel_nc & bank_read_req_unique[read_grant_bank];
    assign sel_sub          = pick_write ? bank_write_req_sub_id[write_grant_bank*AXI_SUBID_W +: AXI_SUBID_W]
                                         : bank_read_req_sub_id[read_grant_bank*AXI_SUBID_W +: AXI_SUBID_W];
    assign sel_read_size    = bank_read_req_size[read_grant_bank*3 +: 3];
    assign sel_write_line   = bank_write_req_data[write_grant_bank*LINE_W +: LINE_W];
    assign sel_write_strobe = bank_write_req_strobe[write_grant_bank*AXI_STRB_W +: AXI_STRB_W];
    assign sel_offset       = sel_addr[OFFSET_W-1:0];
    assign sel_beat         = (AXI_BEATS > 1) ? sel_addr[AXI_OFF_W +: BEAT_W] : {BEAT_W{1'b0}};
    assign nc_write_line = {{(LINE_W - AXI_DATA_W){1'b0}}, sel_write_line[AXI_DATA_W-1:0]} << (sel_beat * AXI_DATA_W);
    assign nc_write_mask = {{(MASK_W - AXI_STRB_W){1'b0}}, sel_write_strobe} << (sel_beat * AXI_STRB_W);
    always @* begin : nc_read_mask_proc
        nc_read_bytes = 1 << sel_read_size;
        for (mask_bit = 0; mask_bit < MASK_W; mask_bit = mask_bit + 1)
            nc_read_mask[mask_bit] = (mask_bit >= sel_offset) && (mask_bit < sel_offset + nc_read_bytes);
    end
    assign sel_mask  = ~sel_nc ? {MASK_W{1'b1}} : (pick_write ? nc_write_mask : nc_read_mask);
    assign sel_data  = ~pick_write ? {LINE_W{1'b0}} : (sel_nc ? nc_write_line : sel_write_line);
    assign sel_pkt   = {sel_unique, sel_addr[L2_ADDR_W-1:0], pick_write, MASTER_ID_C, tid_new, sel_nc, sel_mask, sel_data};
    assign sel_route = {pick_write, sel_nc, sel_bank, sel_sub, sel_beat};
    always @(posedge clk) begin : req_reg_valid_proc
        if (rst)
            req_reg_valid <= 1'b0;
        else if (req_take)
            req_reg_valid <= 1'b1;
        else if (req_reg_valid && l2_req_ready)
            req_reg_valid <= 1'b0;
    end
    always @(posedge clk) begin : req_reg_data_proc
        if (req_take)
            req_reg_pkt <= sel_pkt;
    end
    always @(posedge clk) begin : route_write_proc
        if (req_take)
            route_table[tid_new] <= sel_route;
    end
    always @(posedge clk) begin : tid_busy_proc
        if (rst)
            tid_busy <= {NTID{1'b0}};
        else begin
            if (req_take)  tid_busy[tid_new]  <= 1'b1;
            if (resp_take) tid_busy[resp_tid] <= 1'b0;
        end
    end
    assign l2_req_valid = req_reg_valid;
    assign l2_req_pkt   = req_reg_pkt;
    assign resp_tid       = l2_resp_pkt[TID_LO +: L2_TID_W];
    assign resp_route     = route_table[resp_tid];
    assign ans_last       = ans_valid & (ans_is_write | (ans_beat == ans_end_beat));
    assign resp_ready_int = ~ans_valid | ans_last;
    assign resp_take      = l2_resp_valid & resp_ready_int;
    always @(posedge clk) begin : ans_ctrl_proc
        if (rst) begin
            ans_valid   <= 1'b0;
            err_pulse_q <= 1'b0;
        end else begin
            err_pulse_q <= resp_take & l2_resp_err;
            if (resp_take)
                ans_valid <= 1'b1;
            else if (ans_last)
                ans_valid <= 1'b0;
        end
    end
    always @(posedge clk) begin : ans_data_proc
        if (resp_take) begin
            ans_is_write <= resp_route[ROUTE_W-1];
            ans_nc       <= resp_route[ROUTE_W-2];
            ans_shared   <= ~resp_route[ROUTE_W-1] & ~resp_route[ROUTE_W-2] & l2_resp_pkt[US_BIT];
            ans_bank     <= resp_route[AXI_SUBID_W + BEAT_W +: BANK_W];
            ans_sub      <= resp_route[BEAT_W +: AXI_SUBID_W];
            ans_err      <= l2_resp_err;
            ans_line     <= l2_resp_pkt[LINE_W-1:0];
            ans_beat     <= resp_route[ROUTE_W-2] ? resp_route[BEAT_W-1:0] : {BEAT_W{1'b0}};
            ans_end_beat <= resp_route[ROUTE_W-2] ? resp_route[BEAT_W-1:0] : LAST_BEAT;
        end else if (ans_valid && !ans_last) begin
            ans_beat <= ans_beat + 1'b1;
        end
    end
    generate
        for (bank_idx = 0; bank_idx < NB; bank_idx = bank_idx + 1) begin : g_steer
            assign bank_read_data_valid[bank_idx]    = ans_valid & ~ans_is_write & (ans_bank == bank_idx);
            assign bank_write_resp_valid[bank_idx]   = ans_valid &  ans_is_write & (ans_bank == bank_idx);
            assign bank_refill_replay_busy[bank_idx] = ans_valid & ~ans_is_write & ~ans_nc & (ans_bank == bank_idx);
        end
    endgenerate
    assign bank_read_data_sub_id         = ans_sub;
    assign bank_read_data_non_cacheable  = ans_nc;
    assign bank_read_data                = ans_line[ans_beat*AXI_DATA_W +: AXI_DATA_W];
    assign bank_read_data_last           = (ans_beat == ans_end_beat);
    assign bank_read_data_error          = ans_err;
    assign bank_read_data_shared         = ans_shared;
    assign bank_write_resp_sub_id        = ans_sub;
    assign bank_write_resp_non_cacheable = ans_nc;
    assign bank_write_resp_error         = ans_err;
    assign l2_resp_ready                 = resp_ready_int;
    assign l2_error_pulse                = err_pulse_q;
`ifdef L1D_DEBUG
    integer dbg_req_wait, dbg_ans_wait, dbg_k, dbg_busy_count;
    initial begin
        dbg_req_wait = 0;
        dbg_ans_wait = 0;
    end
    always @(posedge clk) begin : dbg_proc
        if (rst) begin
            dbg_req_wait = 0;
            dbg_ans_wait = 0;
        end else begin
            if (req_take) begin
                $display("[%0t] L1D L2P  REQ %s %s bank %0d sub %0d tid %0d us %b addr %h", $time, pick_write ? "WR" : "RD",
                         sel_nc ? "NC  " : "line", sel_bank, sel_sub, tid_new, sel_unique, sel_addr);
                if ((APAD_W > 0) && (sel_addr[AXI_ADDR_W-1:L2_ADDR_W] != {APAD_W{1'b0}}))
                    $display("[%0t] L1D L2P  ERROR address %h has bits above the %0d-bit packet address", $time, sel_addr, L2_ADDR_W);
                if (!pick_write && (bank_read_req_burst_len[read_grant_bank*8 +: 8] != (sel_nc ? 8'd0 : LINE_LEN)))
                    $display("[%0t] L1D L2P  ERROR bank %0d read len %0d", $time, read_grant_bank, bank_read_req_burst_len[read_grant_bank*8 +: 8]);
                if (pick_write && (bank_write_req_burst_len[write_grant_bank*8 +: 8] != (sel_nc ? 8'd0 : LINE_LEN)))
                    $display("[%0t] L1D L2P  ERROR bank %0d write len %0d", $time, write_grant_bank, bank_write_req_burst_len[write_grant_bank*8 +: 8]);
            end
            if (resp_take) begin
                $display("[%0t] L1D L2P  RESP tid %0d %s bank %0d sub %0d us %b err %b", $time, resp_tid,
                         resp_route[ROUTE_W-1] ? "WR" : "RD", resp_route[AXI_SUBID_W + BEAT_W +: BANK_W],
                         resp_route[BEAT_W +: AXI_SUBID_W], l2_resp_pkt[US_BIT], l2_resp_err);
                if (!tid_busy[resp_tid])
                    $display("[%0t] L1D L2P  ERROR answer with tid %0d, which is not in use", $time, resp_tid);
                if (l2_resp_pkt[MID_LO +: L2_MID_W] != MASTER_ID_C)
                    $display("[%0t] L1D L2P  ERROR answer with master id %0d, expected %0d", $time, l2_resp_pkt[MID_LO +: L2_MID_W], MASTER_ID_C);
                if (l2_resp_pkt[RW_LO] != resp_route[ROUTE_W-1])
                    $display("[%0t] L1D L2P  ERROR answer rw %b for tid %0d does not match the request", $time, l2_resp_pkt[RW_LO], resp_tid);
            end
            if (req_reg_valid && !l2_req_ready) begin
                dbg_req_wait = dbg_req_wait + 1;
                if (dbg_req_wait % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D L2P  STUCK request not taken by the L2 for %0d cycles", $time, dbg_req_wait);
            end else
                dbg_req_wait = 0;
            dbg_busy_count = 0;
            for (dbg_k = 0; dbg_k < NTID; dbg_k = dbg_k + 1) dbg_busy_count = dbg_busy_count + tid_busy[dbg_k];
            if ((dbg_busy_count > 0) && !l2_resp_valid) begin
                dbg_ans_wait = dbg_ans_wait + 1;
                if (dbg_ans_wait % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D L2P  STUCK %0d tid(s) in use, no answer for %0d cycles", $time, dbg_busy_count, dbg_ans_wait);
            end else
                dbg_ans_wait = 0;
        end
    end
`endif
endmodule
`default_nettype wire
`endif
