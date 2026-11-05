`default_nettype none
`include "l1d_defines.vh"
module l1d_mshr_nc #(`L1D_PARAMS) (
    clk, rst,
    allocate_valid, allocate_seat, allocate_is_write, allocate_access_size, allocate_master_id, allocate_rob_index, allocate_port, allocate_addr, allocate_store_data, can_allocate,
    axi_read_req_valid, axi_read_req_ready, axi_read_req_addr, axi_read_req_size,
    axi_read_beat_valid, axi_read_beat_data, axi_read_beat_error,
    axi_write_req_valid, axi_write_req_ready, axi_write_req_addr, axi_write_req_size, axi_write_req_data, axi_write_req_strobe,
    axi_write_resp_valid, axi_write_resp_error,
    response_valid, response_packet, response_seat, response_taken,
    queue_empty, entry_freed_pulse
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam QDEPTH = (MSHR_NC_ENTRIES < 2) ? 2 : MSHR_NC_ENTRIES;
    localparam Q_WDATA = 0;
    localparam Q_ADDR  = Q_WDATA + WRITE_DATA_WIDTH;
    localparam Q_IDX   = Q_ADDR  + ADDR_W;
    localparam Q_MID   = Q_IDX   + IDX_BITS;
    localparam Q_SIZE  = Q_MID   + MASTER_ID_BITS;
    localparam Q_RDWR  = Q_SIZE  + MEM_SIZE_BITS;
    localparam Q_SEAT  = Q_RDWR  + 1;
    localparam Q_PORT  = Q_SEAT  + SEAT_W;
    localparam Q_W     = Q_PORT  + PORT_W;
    input  wire                        clk;
    input  wire                        rst;
    input  wire                        allocate_valid;
    input  wire [SEAT_W-1:0]           allocate_seat;
    input  wire                        allocate_is_write;
    input  wire [MEM_SIZE_BITS-1:0]    allocate_access_size;
    input  wire [MASTER_ID_BITS-1:0]   allocate_master_id;
    input  wire [IDX_BITS-1:0]         allocate_rob_index;
    input  wire [PORT_W-1:0]           allocate_port;
    input  wire [ADDR_W-1:0]           allocate_addr;
    input  wire [WRITE_DATA_WIDTH-1:0] allocate_store_data;
    output wire                        can_allocate;
    output wire                        axi_read_req_valid;
    input  wire                        axi_read_req_ready;
    output wire [ADDR_W-1:0]           axi_read_req_addr;
    output wire [2:0]                  axi_read_req_size;
    input  wire                        axi_read_beat_valid;
    input  wire [AXI_DATA_W-1:0]       axi_read_beat_data;
    input  wire                        axi_read_beat_error;
    output wire                        axi_write_req_valid;
    input  wire                        axi_write_req_ready;
    output wire [ADDR_W-1:0]           axi_write_req_addr;
    output wire [2:0]                  axi_write_req_size;
    output wire [AXI_DATA_W-1:0]       axi_write_req_data;
    output wire [AXI_STRB_W-1:0]       axi_write_req_strobe;
    input  wire                        axi_write_resp_valid;
    input  wire                        axi_write_resp_error;
    output wire                        response_valid;
    output wire [RESP_W-1:0]           response_packet;
    output wire [SEAT_W-1:0]           response_seat;
    input  wire                        response_taken;
    output wire                        queue_empty;
    output wire                        entry_freed_pulse;
    wire [Q_W-1:0] head;
    wire           q_empty, q_full;
    wire           q_pop;
    l1d_fifo #(.WIDTH(Q_W), .DEPTH(QDEPTH)) u_q (
        .clk        (clk),
        .rst        (rst),
        .push       (allocate_valid),
        .push_data  ({allocate_port, allocate_seat, allocate_is_write, allocate_access_size, allocate_master_id, allocate_rob_index, allocate_addr, allocate_store_data}),
        .pop        (q_pop),
        .front_data (head),
        .empty      (q_empty),
        .full       (q_full),
        .used_slots (),
        .free_slots ()
    );
    reg [1:0] n_used;
    assign can_allocate = (MSHR_NC_ENTRIES < 2) ? (n_used == 2'd0) : !q_full;
    localparam WBYTES = WRITE_DATA_WIDTH / 8;
    reg  [Q_W-1:0]              head_q;
    reg  [AXI_STRB_W-1:0]       lane_oh_q;
    reg  [WBYTES-1:0]           szk_q;
    wire [AXI_OFF_W-1:0]        f_lane = head[Q_ADDR +: AXI_OFF_W];
    wire [MEM_SIZE_BITS-1:0]    f_size = head[Q_SIZE +: MEM_SIZE_BITS];
    integer ql;
    always @(posedge clk) begin
        head_q <= head;
        for (ql = 0; ql < AXI_STRB_W; ql = ql + 1)
            lane_oh_q[ql] <= (f_lane == ql);
        for (ql = 0; ql < WBYTES; ql = ql + 1)
            szk_q[ql] <= (ql < (1 << f_size));
    end
    wire [ADDR_W-1:0]           h_addr  = head_q[Q_ADDR +: ADDR_W];
    wire [WRITE_DATA_WIDTH-1:0] h_wdata = head_q[Q_WDATA +: WRITE_DATA_WIDTH];
    wire [MEM_SIZE_BITS-1:0]    h_size  = head_q[Q_SIZE +: MEM_SIZE_BITS];
    wire                        h_rd_wr = head_q[Q_RDWR];
    localparam [1:0] H_IDLE  = 2'd0;
    localparam [1:0] H_ISSUE = 2'd1;
    localparam [1:0] H_WAIT  = 2'd2;
    localparam [1:0] H_RESP  = 2'd3;
    reg [1:0]            hs;
    reg [AXI_DATA_W-1:0] rbeat;
    reg                  herr;
    always @(posedge clk) begin
        if (rst) begin
            hs     <= H_IDLE;
            herr   <= 1'b0;
            n_used <= 2'd0;
        end else begin
            case ({allocate_valid, q_pop})
                2'b10:   n_used <= n_used + 1'b1;
                2'b01:   n_used <= n_used - 1'b1;
                default: n_used <= n_used;
            endcase
            case (hs)
                H_IDLE:  if (!q_empty) hs <= H_ISSUE;
                H_ISSUE: if ((h_rd_wr == OP_READ) ? axi_read_req_ready : axi_write_req_ready) hs <= H_WAIT;
                H_WAIT: begin
                    if (h_rd_wr == OP_READ && axi_read_beat_valid) begin
                        rbeat <= axi_read_beat_data;
                        herr  <= axi_read_beat_error;
                        hs    <= H_RESP;
                    end else if (h_rd_wr == OP_WRITE && axi_write_resp_valid) begin
                        herr  <= axi_write_resp_error;
                        hs    <= H_RESP;
                    end
                end
                H_RESP:  if (response_taken) hs <= H_IDLE;
                default: hs <= H_IDLE;
            endcase
        end
    end
    assign q_pop = (hs == H_RESP) && response_taken;
    assign entry_freed_pulse = q_pop;
    assign queue_empty = q_empty;
    integer i, k;
    reg [AXI_STRB_W-1:0] strb;
    reg [AXI_DATA_W-1:0] wdata_sh;
    always @* begin
        for (i = 0; i < AXI_STRB_W; i = i + 1) begin
            strb[i]          = 1'b0;
            wdata_sh[i*8 +: 8] = 8'h00;
            for (k = 0; k < WBYTES; k = k + 1)
                if (i - k >= 0) begin
                    strb[i]            = strb[i] | (lane_oh_q[i-k] & szk_q[k]);
                    wdata_sh[i*8 +: 8] = wdata_sh[i*8 +: 8] | ({8{lane_oh_q[i-k]}} & h_wdata[k*8 +: 8]);
                end
        end
    end
    assign axi_read_req_valid = (hs == H_ISSUE) && (h_rd_wr == OP_READ);
    wire [2:0] h_axsize = h_size;
    assign axi_read_req_addr  = h_addr;
    assign axi_read_req_size  = h_axsize;
    assign axi_write_req_valid = (hs == H_ISSUE) && (h_rd_wr == OP_WRITE);
    assign axi_write_req_addr  = h_addr;
    assign axi_write_req_size  = h_axsize;
    assign axi_write_req_data  = wdata_sh;
    assign axi_write_req_strobe  = strb;
    reg [WRITE_DATA_WIDTH-1:0] load_data;
    integer lk, lj;
    always @* begin
        for (lk = 0; lk < WBYTES; lk = lk + 1) begin
            load_data[lk*8 +: 8] = 8'h00;
            for (lj = 0; lj < AXI_STRB_W; lj = lj + 1)
                if (lj + lk < AXI_STRB_W)
                    load_data[lk*8 +: 8] = load_data[lk*8 +: 8] | ({8{szk_q[lk] & lane_oh_q[lj]}} & rbeat[(lj+lk)*8 +: 8]);
        end
    end
`ifdef L1D_DEBUG
    function [8*5-1:0] dbg_hname;
        input [1:0] s;
        begin
            case (s)
                H_IDLE:  dbg_hname = "IDLE";
                H_ISSUE: dbg_hname = "ISSUE";
                H_WAIT:  dbg_hname = "WAIT";
                default: dbg_hname = "RESP";
            endcase
        end
    endfunction
    reg [1:0] dbg_ps;
    integer   dbg_age;
    initial begin dbg_ps = H_IDLE; dbg_age = 0; end
    always @(posedge clk) begin
        if (rst) begin
            dbg_ps  = H_IDLE;
            dbg_age = 0;
        end else begin
            if (allocate_valid)
                $display("[%0t] L1D NC   %m queued idx=%0d %s addr=%h size=%0d data=%h (can_alloc=%b)",
                         $time, allocate_rob_index, (allocate_is_write ? "ST" : "LD"), allocate_addr, allocate_access_size, allocate_store_data, can_allocate);
            if (hs != dbg_ps) begin
                $display("[%0t] L1D NC   %m head: %0s -> %0s  %s addr=%h (AXI addr %h, size %0d, strobe %h)",
                         $time, dbg_hname(dbg_ps), dbg_hname(hs), (h_rd_wr ? "ST" : "LD"),
                         h_addr, h_addr, h_axsize, strb);
                dbg_ps  = hs;
                dbg_age = 0;
            end else if (hs != H_IDLE) begin
                dbg_age = dbg_age + 1;
                if (dbg_age % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D NC   %m STUCK head in %0s for %0d cycles  %s addr=%h  (ISSUE: AXI master busy; WAIT: no %s from memory; RESP: no response-FIFO place)",
                             $time, dbg_hname(hs), dbg_age, (h_rd_wr ? "ST" : "LD"), h_addr,
                             (h_rd_wr ? "B" : "R beat"));
            end
            if (axi_read_beat_valid) begin
                if (hs != H_WAIT || h_rd_wr != OP_READ)
                    $display("[%0t] L1D NC   %m ERROR NC R beat while the head is in %0s (wrong RID from memory?)",
                             $time, dbg_hname(hs));
                else
                    $display("[%0t] L1D NC   %m R err=%b data=%h", $time, axi_read_beat_error, axi_read_beat_data);
            end
            if (axi_write_resp_valid) begin
                if (hs != H_WAIT || h_rd_wr != OP_WRITE)
                    $display("[%0t] L1D NC   %m ERROR NC B while the head is in %0s (wrong BID from memory?)",
                             $time, dbg_hname(hs));
                else
                    $display("[%0t] L1D NC   %m B err=%b", $time, axi_write_resp_error);
            end
        end
    end
`endif
    assign response_valid = (hs == H_RESP);
    assign response_seat  = head_q[Q_SEAT +: SEAT_W];
    assign response_packet   = {head_q[Q_PORT +: PORT_W], h_rd_wr, h_size, head_q[Q_MID +: MASTER_ID_BITS], head_q[Q_IDX +: IDX_BITS],
                         (h_rd_wr == OP_WRITE) ? {WRITE_DATA_WIDTH{1'b0}} : load_data};
endmodule
`default_nettype wire
