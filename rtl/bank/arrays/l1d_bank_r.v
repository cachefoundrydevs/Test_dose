`ifndef L1D_BANK_R_V
`define L1D_BANK_R_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_r #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst,
    any_gnt, g_set,
    r_valid, r_kind, r_seat, r_req, r_fast, r_mid, r_line, r_mway, r_mop, r_sinv, r_sid,
    seat_blk,
    s2_refill, s2_st_wr, s2_way, s2_line, q2_data, st_merged,
    s3_amo_v, s3_way, s3_line, s3_merged,
    s1_valid, s1_kind, s1_seat, s1_req, s1_mid, s1_line, s1_mway, s1_mop, s1_sinv, s1_sid, s1_kill,
    tag_q, s1_lines
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire                        clk;
    input  wire                        rst;
    input  wire                        any_gnt;
    input  wire [INDEX_W-1:0]          g_set;
    input  wire                        r_valid;
    input  wire [1:0]                  r_kind;
    input  wire [SEAT_W-1:0]           r_seat;
    input  wire [REQ_W-1:0]            r_req;
    input  wire                        r_fast;
    input  wire [MSHR_ID_W-1:0]        r_mid;
    input  wire [LINE_ADDR_W-1:0]      r_line;
    input  wire [WAY_W-1:0]            r_mway;
    input  wire                        r_mop;
    input  wire                        r_sinv;
    input  wire [SNP_ID_W-1:0]         r_sid;
    input  wire [LSU_BUF_DEPTH-1:0]    seat_blk;
    input  wire                        s2_refill;
    input  wire                        s2_st_wr;
    input  wire [WAY_W-1:0]            s2_way;
    input  wire [LINE_ADDR_W-1:0]      s2_line;
    input  wire [LINE_W-1:0]           q2_data;
    input  wire [LINE_W-1:0]           st_merged;
    input  wire                        s3_amo_v;
    input  wire [WAY_W-1:0]            s3_way;
    input  wire [LINE_ADDR_W-1:0]      s3_line;
    input  wire [LINE_W-1:0]           s3_merged;
    output reg                         s1_valid;
    output reg  [1:0]                  s1_kind;
    output reg  [SEAT_W-1:0]           s1_seat;
    output reg  [REQ_W-1:0]            s1_req;
    output reg  [MSHR_ID_W-1:0]        s1_mid;
    output reg  [LINE_ADDR_W-1:0]      s1_line;
    output reg  [WAY_W-1:0]            s1_mway;
    output reg                         s1_mop;
    output reg                         s1_sinv;
    output reg  [SNP_ID_W-1:0]         s1_sid;
    output reg                         s1_kill;
    output reg  [WAYS*TAG_W-1:0]       tag_q;
    output reg  [WAYS*LINE_W-1:0]      s1_lines;
    wire [INDEX_W-1:0] s2_set = s2_line[LA_SET_LSB +: INDEX_W];
    wire [INDEX_W-1:0] s3_set = s3_line[LA_SET_LSB +: INDEX_W];
    wire [WAYS*TAG_W-1:0] tag_rd;
    wire                  tag_wr = s2_refill;
    wire [WAYS-1:0]       tag_we;
    genvar gw;
    generate
        for (gw = 0; gw < WAYS; gw = gw + 1) begin : g_tagwe
            assign tag_we[gw] = (s2_way == gw);
        end
    endgenerate
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
    wire r_lsu = r_valid && (r_kind == K_LSU);
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
            s1_valid <= 1'b0;
        end else begin
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
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            if (r_kill)
                $display("[%0t] L1D B%0d R  fast issue seat=%0d CANCELLED (seat blocked by an older same-line request / AMO rule): back to READY",
                         $time, BANK_ID, r_seat);
        end
    end
`endif
endmodule
`default_nettype wire
`endif
