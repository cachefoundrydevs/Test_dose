`ifndef L1D_BANK_S3_V
`define L1D_BANK_S3_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_s3 #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst,
    s3_old, s3_be, s3_off, s3_new, s3_merged,
    s3_load, s2_pkt, s2_seat,
    m_resp_valid, m_resp_pkt, m_resp_seat, m_resp_ack,
    n_resp_valid, n_resp_pkt, n_resp_seat, n_resp_ack,
    miss_ok, lsu_response_fifo_free,
    lsu_response_valid, lsu_response_packet, done_valid, done_seat,
    m_rd_valid, m_rd_ready, m_rd_line, m_rd_sub, m_rd_unique,
    n_rd_valid, n_rd_ready, n_rd_addr, n_rd_size,
    vc_wr_valid, vc_wr_ready, vc_wr_line, vc_wr_sub, vc_wr_data,
    n_wr_valid, n_wr_ready, n_wr_addr, n_wr_size, n_wr_data, n_wr_strb,
    axi_read_req_valid, axi_read_req_ready, axi_read_req_addr, axi_read_req_burst_len, axi_read_req_size,
    axi_read_req_sub_id, axi_read_req_non_cacheable, axi_read_req_unique,
    axi_write_req_valid, axi_write_req_ready, axi_write_req_addr, axi_write_req_burst_len, axi_write_req_size,
    axi_write_req_sub_id, axi_write_req_non_cacheable, axi_write_req_data, axi_write_req_strobe
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam [7:0]          LEN_C  = AXI_LEN;
    localparam [2:0]          SIZE_C = AXI_SIZE;
    localparam [OFFSET_W-1:0] OFF0   = {OFFSET_W{1'b0}};
    input  wire                        clk;
    input  wire                        rst;
    input  wire [LINE_W-1:0]           s3_old;
    input  wire [LINE_BYTES-1:0]       s3_be;
    input  wire [OFFSET_W-1:0]         s3_off;
    input  wire [WRITE_DATA_WIDTH-1:0] s3_new;
    output reg  [LINE_W-1:0]           s3_merged;
    input  wire                        s3_load;
    input  wire [RESP_W-1:0]           s2_pkt;
    input  wire [SEAT_W-1:0]           s2_seat;
    input  wire                        m_resp_valid;
    input  wire [RESP_W-1:0]           m_resp_pkt;
    input  wire [SEAT_W-1:0]           m_resp_seat;
    output wire                        m_resp_ack;
    input  wire                        n_resp_valid;
    input  wire [RESP_W-1:0]           n_resp_pkt;
    input  wire [SEAT_W-1:0]           n_resp_seat;
    output wire                        n_resp_ack;
    input  wire                        miss_ok;
    input  wire [LSU_PORTS*RCNT_W-1:0] lsu_response_fifo_free;
    output wire                        lsu_response_valid;
    output wire [RESP_W-1:0]           lsu_response_packet;
    output reg                         done_valid;
    output reg  [SEAT_W-1:0]           done_seat;
    input  wire                        m_rd_valid;
    output wire                        m_rd_ready;
    input  wire [LINE_ADDR_W-1:0]      m_rd_line;
    input  wire [MSHR_ID_W-1:0]        m_rd_sub;
    input  wire                        m_rd_unique;
    input  wire                        n_rd_valid;
    output wire                        n_rd_ready;
    input  wire [ADDR_W-1:0]           n_rd_addr;
    input  wire [2:0]                  n_rd_size;
    input  wire                        vc_wr_valid;
    output wire                        vc_wr_ready;
    input  wire [LINE_ADDR_W-1:0]      vc_wr_line;
    input  wire [VC_ID_W-1:0]          vc_wr_sub;
    input  wire [LINE_W-1:0]           vc_wr_data;
    input  wire                        n_wr_valid;
    output wire                        n_wr_ready;
    input  wire [ADDR_W-1:0]           n_wr_addr;
    input  wire [2:0]                  n_wr_size;
    input  wire [AXI_DATA_W-1:0]       n_wr_data;
    input  wire [AXI_STRB_W-1:0]       n_wr_strb;
    output wire                        axi_read_req_valid;
    input  wire                        axi_read_req_ready;
    output wire [AXI_ADDR_W-1:0]       axi_read_req_addr;
    output wire [7:0]                  axi_read_req_burst_len;
    output wire [2:0]                  axi_read_req_size;
    output wire [AXI_SUBID_W-1:0]      axi_read_req_sub_id;
    output wire                        axi_read_req_non_cacheable;
    output wire                        axi_read_req_unique;
    output wire                        axi_write_req_valid;
    input  wire                        axi_write_req_ready;
    output wire [AXI_ADDR_W-1:0]       axi_write_req_addr;
    output wire [7:0]                  axi_write_req_burst_len;
    output wire [2:0]                  axi_write_req_size;
    output wire [AXI_SUBID_W-1:0]      axi_write_req_sub_id;
    output wire                        axi_write_req_non_cacheable;
    output wire [LINE_W-1:0]           axi_write_req_data;
    output wire [AXI_STRB_W-1:0]       axi_write_req_strobe;
    wire [LINE_W-1:0] s3_din = {{(LINE_W-WRITE_DATA_WIDTH){1'b0}}, s3_new} << {s3_off, 3'b000};
    integer ab;
    always @* begin
        for (ab = 0; ab < LINE_BYTES; ab = ab + 1)
            s3_merged[ab*8 +: 8] = s3_be[ab] ? s3_din[ab*8 +: 8] : s3_old[ab*8 +: 8];
    end
    wire s2_push = s3_load;
    wire m_take = !s2_push && m_resp_valid && miss_ok;
    wire n_take = !s2_push && !m_resp_valid && n_resp_valid && miss_ok;
    wire miss_push = m_take || n_take;
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
    integer dbg_mrw, dbg_nrw;
    initial begin dbg_mrw = 0; dbg_nrw = 0; end
    always @(posedge clk) begin
        if (!rst) begin
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
`endif
