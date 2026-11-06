`default_nettype none
`include "l1d_defines.vh"
module l1d_top #(
    parameter ADDR_W           = `L1D_ADDR_W,
    parameter LINE_BYTES       = `L1D_LINE_BYTES,
    parameter NUM_BANKS        = `L1D_NUM_BANKS,
    parameter SETS             = `L1D_SETS,
    parameter WAYS             = `L1D_WAYS,
    parameter WRITE_DATA_WIDTH = `L1D_WRITE_DATA_WIDTH,
    parameter MEM_SIZE_BITS    = `L1D_MEM_SIZE_BITS,
    parameter MASTER_ID_BITS   = `L1D_MASTER_ID_BITS,
    parameter IDX_BITS         = `L1D_IDX_BITS,
    parameter PORT_QUEUE_DEPTH = `L1D_PORT_QUEUE_DEPTH,
    parameter LSU_BUF_DEPTH    = `L1D_LSU_BUF_DEPTH,
    parameter TRK_ENTRIES      = `L1D_TRK_ENTRIES,
    parameter TRK_REFILL_RSV   = `L1D_TRK_REFILL_RSV,
    parameter MSHR_ENTRIES     = `L1D_MSHR_ENTRIES,
    parameter MSHR_NC_ENTRIES  = `L1D_MSHR_NC_ENTRIES,
    parameter VC_SLOTS         = `L1D_VC_SLOTS,
    parameter RESP_FIFO_DEPTH  = `L1D_RESP_FIFO_DEPTH,
    parameter REFILL_SKIP      = `L1D_REFILL_SKIP,
    parameter SNP_BUF_DEPTH    = `L1D_SNP_BUF_DEPTH,
    parameter SNP_RESP_DEPTH   = `L1D_SNP_RESP_DEPTH,
    parameter PF_FIFO_DEPTH    = `L1D_PF_FIFO_DEPTH,
    parameter SNP_STARVE       = `L1D_SNP_STARVE,
    parameter LOCK_TIMEOUT     = `L1D_LOCK_TIMEOUT,
    parameter RSV_CLR_ON_EVICT = `L1D_RSV_CLR_ON_EVICT,
    parameter HAS_SNOOP        = `L1D_HAS_SNOOP,
    parameter HAS_AMO          = `L1D_HAS_AMO,
    parameter AXI_DATA_W       = `L1D_AXI_DATA_W,
    parameter AXI_ADDR_W       = `L1D_AXI_ADDR_W,
    parameter L2_ADDR_W        = 56,
    parameter L2_MID_W         = 2,
    parameter L2_TID_W         = 6,
    parameter L2_MASTER_ID     = 0,
    parameter L2_PKT_W         = 1 + L2_ADDR_W + 1 + L2_MID_W + L2_TID_W + 1 + LINE_BYTES + LINE_BYTES*8,
    parameter LSU_PORTS        = `L1D_LSU_PORTS,
    parameter HAS_MISS         = `L1D_HAS_MISS,
    parameter HAS_VC           = `L1D_HAS_VC,
    parameter HAS_NC           = `L1D_HAS_NC,
    parameter HAS_VPU          = `L1D_HAS_VPU
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         flush_request,
    input  wire                         clean_request,
    output reg                          flush_complete,
    output reg                          clean_complete,
    input  wire [LSU_PORTS-1:0]                  cpu_request_valid,
    input  wire [LSU_PORTS-1:0]                  cpu_request_cacheable,
    input  wire [LSU_PORTS-1:0]                  cpu_request_is_write,
    input  wire [LSU_PORTS*MEM_SIZE_BITS-1:0]    cpu_request_size,
    input  wire [LSU_PORTS*MASTER_ID_BITS-1:0]   cpu_request_master_id,
    input  wire [LSU_PORTS*IDX_BITS-1:0]         cpu_request_rob_index,
    input  wire [LSU_PORTS*ADDR_W-1:0]           cpu_request_addr,
    input  wire [LSU_PORTS*WRITE_DATA_WIDTH-1:0] cpu_request_store_data,
    input  wire [LSU_PORTS-1:0]                  cpu_request_is_atomic,
    input  wire [LSU_PORTS-1:0]                  cpu_request_atomic_is_amo,
    input  wire [LSU_PORTS*4-1:0]                cpu_request_amo_op,
    output wire [LSU_PORTS-1:0]                  input_queue_full,
    input  wire [LSU_PORTS-1:0]                  lsu_response_read_enable,
    output wire [LSU_PORTS-1:0]                  lsu_response_valid,
    output wire [LSU_PORTS-1:0]                  lsu_response_is_write_ack,
    output wire [LSU_PORTS*MEM_SIZE_BITS-1:0]    lsu_response_size,
    output wire [LSU_PORTS*MASTER_ID_BITS-1:0]   lsu_response_master_id,
    output wire [LSU_PORTS*IDX_BITS-1:0]         lsu_response_rob_index,
    output wire [LSU_PORTS*WRITE_DATA_WIDTH-1:0] lsu_response_data,
    input  wire                         vpu_req_valid,
    input  wire                         vpu_req_is_write,
    input  wire                         vpu_req_cacheable,
    input  wire [MASTER_ID_BITS-1:0]    vpu_req_master_id,
    input  wire [IDX_BITS-1:0]          vpu_req_rob_index,
    input  wire [ADDR_W-1:0]            vpu_req_addr,
    input  wire [LINE_BYTES*8-1:0]      vpu_req_wdata,
    output wire                         vpu_req_stop,
    input  wire                         vpu_resp_read_enable,
    output wire                         vpu_resp_valid,
    output wire                         vpu_resp_is_write_ack,
    output wire [MASTER_ID_BITS-1:0]    vpu_resp_master_id,
    output wire [IDX_BITS-1:0]          vpu_resp_rob_index,
    output wire [LINE_BYTES*8-1:0]      vpu_resp_data,
    input  wire                         snoop_request_valid,
    output wire                         snoop_request_ready,
    input  wire [ADDR_W-1:0]            snoop_request_addr,
    input  wire                         snoop_request_invalidate,
    output wire                         snoop_response_valid,
    input  wire                         snoop_response_ready,
    output wire [ADDR_W-1:0]            snoop_response_addr,
    output wire                         snoop_response_present,
    output wire                         snoop_response_dirty,
    output wire [LINE_BYTES*8-1:0]      snoop_response_data,
    output reg                          l2_error_sticky,
    output reg                          amo_lock_timeout_sticky,
    output wire                         l2_req_valid,
    input  wire                         l2_req_ready,
    output wire [L2_PKT_W-1:0]          l2_req_pkt,
    input  wire                         l2_resp_valid,
    output wire                         l2_resp_ready,
    input  wire [L2_PKT_W-1:0]          l2_resp_pkt,
    input  wire                         l2_resp_err
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam NB = NUM_BANKS;
    localparam VPU_PORT = LSU_PORTS - 1;
    wire [LSU_PORTS-1:0]       port_req_valid;
    wire [LSU_PORTS*REQ_W-1:0] port_req_packet;
    genvar pkt_port;
    generate
        for (pkt_port = 0; pkt_port < LSU_PORTS; pkt_port = pkt_port + 1) begin : g_req_pkt
            wire [PORT_W-1:0]     port_id = pkt_port;
            if ((HAS_VPU != 0) && (pkt_port == VPU_PORT)) begin : g_vpu
                assign port_req_valid[pkt_port] = vpu_req_valid;
                assign port_req_packet[pkt_port*REQ_W +: REQ_W] =
                    {1'b1, port_id, {AMOOP_W{1'b0}}, 1'b0, 1'b0, vpu_req_is_write, 1'b1,
                     {MEM_SIZE_BITS{1'b1}},
                     vpu_req_master_id,
                     vpu_req_rob_index,
                     vpu_req_addr,
                     {WRITE_DATA_WIDTH{1'b0}}};
            end else begin : g_scalar
                wire                  amo_in  = (HAS_AMO != 0) && cpu_request_is_atomic[pkt_port];
                wire                  seq_in  = amo_in && cpu_request_atomic_is_amo[pkt_port];
                wire [AMOOP_W-1:0]    amo_op  = seq_in ? cpu_request_amo_op[pkt_port*4 +: AMOOP_W] : {AMOOP_W{1'b0}};
                assign port_req_valid[pkt_port] = cpu_request_valid[pkt_port];
                assign port_req_packet[pkt_port*REQ_W +: REQ_W] =
                    {1'b0, port_id, amo_op, seq_in, amo_in, (cpu_request_is_write[pkt_port] || seq_in), cpu_request_cacheable[pkt_port],
                     cpu_request_size[pkt_port*MEM_SIZE_BITS +: MEM_SIZE_BITS],
                     cpu_request_master_id[pkt_port*MASTER_ID_BITS +: MASTER_ID_BITS],
                     cpu_request_rob_index[pkt_port*IDX_BITS +: IDX_BITS],
                     cpu_request_addr[pkt_port*ADDR_W +: ADDR_W],
                     cpu_request_store_data[pkt_port*WRITE_DATA_WIDTH +: WRITE_DATA_WIDTH]};
            end
        end
    endgenerate
    assign vpu_req_stop = (HAS_VPU != 0) ? input_queue_full[VPU_PORT] : 1'b1;
    always @(posedge clk) begin
        if (!rst && (HAS_VPU != 0) && vpu_req_valid) begin
            if (vpu_req_addr[OFFSET_W-1:0] != {OFFSET_W{1'b0}})
                $display("[%0t] L1D TOP  ERROR VPU request idx %0d address %h is not 64-byte aligned", $time, vpu_req_rob_index, vpu_req_addr);
            if (!vpu_req_cacheable)
                $display("[%0t] L1D TOP  ERROR VPU request idx %0d is non-cacheable: not built (open item PO-6), done as cacheable", $time, vpu_req_rob_index);
        end
    end
    wire [NB-1:0]       bk_req_valid;
    wire [NB*REQ_W-1:0] bk_req;
    wire [NB-1:0]       bk_req_ready;
    wire [NB*LINE_W-1:0] bk_req_line;
    l1d_port_front #(`L1D_PARAMS_PASS, .PORT_QUEUE_DEPTH(PORT_QUEUE_DEPTH), .LINE_PORT_ON(HAS_VPU)) u_front (
        .clk                    (clk),
        .rst                    (rst),
        .port_request_valid     (port_req_valid),
        .port_request_packet    (port_req_packet),
        .port_stop              (input_queue_full),
        .bank_request_valid     (bk_req_valid),
        .bank_request_packet    (bk_req),
        .bank_request_ready     (bk_req_ready),
        .port_line_data         (vpu_req_wdata),
        .bank_request_line_data (bk_req_line)
    );
    wire [NB-1:0]               bk_resp_valid;
    wire [NB*RESP_W-1:0]        bk_resp;
    wire [NB*LINE_W-1:0]        bk_resp_line;
    wire [NB*LSU_PORTS*RCNT_W-1:0] bk_resp_free;
    wire [NB-1:0]               bk_rsv_event;
    reg  [NB-1:0]               other_rsv_event_q;
    wire [NB-1:0]               bk_rd_valid, bk_rd_ready, bk_rd_nc, bk_rd_unique;
    wire [NB*AXI_ADDR_W-1:0]    bk_rd_addr;
    wire [NB*8-1:0]             bk_rd_len;
    wire [NB*3-1:0]             bk_rd_size;
    wire [NB*AXI_SUBID_W-1:0]   bk_rd_sub;
    wire [NB-1:0]               bk_r_valid;
    wire [AXI_SUBID_W-1:0]      bk_r_sub;
    wire                        bk_r_nc, bk_r_last, bk_r_err, bk_r_shared;
    wire [AXI_DATA_W-1:0]       bk_r_data;
    wire [NB-1:0]               bk_wr_valid, bk_wr_ready, bk_wr_nc;
    wire [NB*AXI_ADDR_W-1:0]    bk_wr_addr;
    wire [NB*8-1:0]             bk_wr_len;
    wire [NB*3-1:0]             bk_wr_size;
    wire [NB*AXI_SUBID_W-1:0]   bk_wr_sub;
    wire [NB*LINE_W-1:0]        bk_wr_data;
    wire [NB*AXI_STRB_W-1:0]    bk_wr_strb;
    wire [NB-1:0]               bk_b_valid;
    wire [AXI_SUBID_W-1:0]      bk_b_sub;
    wire                        bk_b_nc, bk_b_err;
    reg                         mt_start;
    reg                         mt_op;
    wire [NB-1:0]               mt_done;
    wire [NB-1:0]               bk_lock_err;
    wire                        l2_err;
    wire [NB-1:0]               refill_busy;
    wire [NB-1:0]               bk_snp_valid, bk_snp_ready;
    wire [LINE_ADDR_W-1:0]      bk_snp_line;
    wire                        bk_snp_inv;
    wire [NB-1:0]               bk_snpr_valid;
    wire [NB*SNPR_W-1:0]        bk_snpr_pkt;
    wire [NB*SNPR_CNT_W-1:0]    bk_snpr_free;
    genvar b;
    generate
        for (b = 0; b < NB; b = b + 1) begin : g_bank
            l1d_bank #(`L1D_PARAMS_PASS, .BANK_ID(b)) u_bank (
                .clk                          (clk),
                .rst                          (rst),
                .lsu_request_valid            (bk_req_valid[b]),
                .lsu_request_packet           (bk_req[b*REQ_W +: REQ_W]),
                .lsu_request_ready            (bk_req_ready[b]),
                .lsu_response_valid           (bk_resp_valid[b]),
                .lsu_response_packet          (bk_resp[b*RESP_W +: RESP_W]),
                .lsu_response_fifo_free       (bk_resp_free[b*LSU_PORTS*RCNT_W +: LSU_PORTS*RCNT_W]),
                .snoop_request_valid          (bk_snp_valid[b]),
                .snoop_request_line_addr      (bk_snp_line),
                .snoop_request_invalidate     (bk_snp_inv),
                .snoop_request_ready          (bk_snp_ready[b]),
                .snoop_response_valid         (bk_snpr_valid[b]),
                .snoop_response_packet        (bk_snpr_pkt[b*SNPR_W +: SNPR_W]),
                .snoop_response_fifo_free     (bk_snpr_free[b*SNPR_CNT_W +: SNPR_CNT_W]),
                .prefetch_request_valid       (1'b0),
                .prefetch_request_line_addr   ({LINE_ADDR_W{1'b0}}),
                .prefetch_request_ready       (),
                .axi_read_req_valid           (bk_rd_valid[b]),
                .axi_read_req_ready           (bk_rd_ready[b]),
                .axi_read_req_addr            (bk_rd_addr[b*AXI_ADDR_W +: AXI_ADDR_W]),
                .axi_read_req_burst_len       (bk_rd_len[b*8 +: 8]),
                .axi_read_req_size            (bk_rd_size[b*3 +: 3]),
                .axi_read_req_sub_id          (bk_rd_sub[b*AXI_SUBID_W +: AXI_SUBID_W]),
                .axi_read_req_non_cacheable   (bk_rd_nc[b]),
                .axi_read_req_unique          (bk_rd_unique[b]),
                .axi_read_data_valid          (bk_r_valid[b]),
                .axi_read_data_sub_id         (bk_r_sub),
                .axi_read_data_non_cacheable  (bk_r_nc),
                .axi_read_data                (bk_r_data),
                .axi_read_data_last           (bk_r_last),
                .axi_read_data_error          (bk_r_err),
                .axi_read_data_shared         (bk_r_shared),
                .axi_write_req_valid          (bk_wr_valid[b]),
                .axi_write_req_ready          (bk_wr_ready[b]),
                .axi_write_req_addr           (bk_wr_addr[b*AXI_ADDR_W +: AXI_ADDR_W]),
                .axi_write_req_burst_len      (bk_wr_len[b*8 +: 8]),
                .axi_write_req_size           (bk_wr_size[b*3 +: 3]),
                .axi_write_req_sub_id         (bk_wr_sub[b*AXI_SUBID_W +: AXI_SUBID_W]),
                .axi_write_req_non_cacheable  (bk_wr_nc[b]),
                .axi_write_req_data           (bk_wr_data[b*LINE_W +: LINE_W]),
                .axi_write_req_strobe         (bk_wr_strb[b*AXI_STRB_W +: AXI_STRB_W]),
                .axi_write_resp_valid         (bk_b_valid[b]),
                .axi_write_resp_sub_id        (bk_b_sub),
                .axi_write_resp_non_cacheable (bk_b_nc),
                .axi_write_resp_error         (bk_b_err),
                .refill_handover_busy         (refill_busy[b]),
                .maint_start                  (mt_start),
                .maint_op_is_flush            (mt_op),
                .maint_done                   (mt_done[b]),
                .amo_lock_timeout_pulse       (bk_lock_err[b]),
                .rsv_event_pulse              (bk_rsv_event[b]),
                .other_bank_rsv_event         (other_rsv_event_q[b]),
                .lsu_request_line_data        (bk_req_line[b*LINE_W +: LINE_W]),
                .lsu_response_line_data       (bk_resp_line[b*LINE_W +: LINE_W])
            );
        end
    endgenerate
    l1d_snoop_ctrl #(`L1D_PARAMS_PASS) u_snoop (
        .clk                           (clk),
        .rst                           (rst),
        .snoop_request_valid           (snoop_request_valid),
        .snoop_request_ready           (snoop_request_ready),
        .snoop_request_addr            (snoop_request_addr),
        .snoop_request_invalidate      (snoop_request_invalidate),
        .bank_snoop_valid              (bk_snp_valid),
        .bank_snoop_line_addr          (bk_snp_line),
        .bank_snoop_invalidate         (bk_snp_inv),
        .bank_snoop_ready              (bk_snp_ready),
        .bank_snoop_response_valid     (bk_snpr_valid),
        .bank_snoop_response_packet    (bk_snpr_pkt),
        .bank_snoop_response_fifo_free (bk_snpr_free),
        .snoop_response_valid          (snoop_response_valid),
        .snoop_response_ready          (snoop_response_ready),
        .snoop_response_addr           (snoop_response_addr),
        .snoop_response_present        (snoop_response_present),
        .snoop_response_dirty          (snoop_response_dirty),
        .snoop_response_data           (snoop_response_data)
    );
    localparam VPKT_W = RESP_W + LINE_W;
    localparam [RESP_W-1:0] RESP_DATA_MASK = {{(RESP_W-WRITE_DATA_WIDTH){1'b0}}, {WRITE_DATA_WIDTH{1'b1}}} << RESP_DATA_LSB;
    wire [LSU_PORTS-1:0]        out_valid;
    wire [LSU_PORTS*RESP_W-1:0] out_resp;
    wire [VPKT_W-1:0]           vpu_out_resp;
    genvar out_port;
    genvar route_bank;
    generate
        for (out_port = 0; out_port < LSU_PORTS; out_port = out_port + 1) begin : g_port_out
            wire [NB-1:0]        for_this_port;
            wire [NB*RCNT_W-1:0] port_fifo_free;
            wire [NB*VPKT_W-1:0] vpu_bank_resp;
            for (route_bank = 0; route_bank < NB; route_bank = route_bank + 1) begin : g_route
                assign for_this_port[route_bank] = bk_resp_valid[route_bank] &&
                    (bk_resp[route_bank*RESP_W + RESP_PORT_LSB +: PORT_W] == out_port);
                assign bk_resp_free[(route_bank*LSU_PORTS + out_port)*RCNT_W +: RCNT_W] =
                    port_fifo_free[route_bank*RCNT_W +: RCNT_W];
                assign vpu_bank_resp[route_bank*VPKT_W +: VPKT_W] =
                    {bk_resp_line[route_bank*LINE_W +: LINE_W], (bk_resp[route_bank*RESP_W +: RESP_W] & ~RESP_DATA_MASK)};
            end
            if ((HAS_VPU != 0) && (out_port == VPU_PORT)) begin : g_vpu_out
                l1d_resp_merge #(`L1D_PARAMS_PASS, .EXTRA_W(LINE_W)) u_merge (
                    .clk                     (clk),
                    .rst                     (rst),
                    .bank_response_valid     (for_this_port),
                    .bank_response_packet    (vpu_bank_resp),
                    .bank_response_fifo_free (port_fifo_free),
                    .merged_response_valid   (out_valid[out_port]),
                    .merged_response_packet  (vpu_out_resp),
                    .lsu_read_enable         (vpu_resp_read_enable)
                );
                assign out_resp[out_port*RESP_W +: RESP_W] = {RESP_W{1'b0}};
                assign vpu_resp_valid        = out_valid[out_port];
                assign vpu_resp_is_write_ack = vpu_out_resp[RESP_RDWR_BIT];
                assign vpu_resp_master_id    = vpu_out_resp[RESP_MID_LSB +: MASTER_ID_BITS];
                assign vpu_resp_rob_index    = vpu_out_resp[RESP_IDX_LSB +: IDX_BITS];
                assign vpu_resp_data         = vpu_out_resp[RESP_W +: LINE_W];
            end else begin : g_scalar_out
                l1d_resp_merge #(`L1D_PARAMS_PASS) u_merge (
                    .clk                     (clk),
                    .rst                     (rst),
                    .bank_response_valid     (for_this_port),
                    .bank_response_packet    (bk_resp),
                    .bank_response_fifo_free (port_fifo_free),
                    .merged_response_valid   (out_valid[out_port]),
                    .merged_response_packet  (out_resp[out_port*RESP_W +: RESP_W]),
                    .lsu_read_enable         (lsu_response_read_enable[out_port])
                );
            end
            assign lsu_response_valid[out_port]        = ((HAS_VPU != 0) && (out_port == VPU_PORT)) ? 1'b0 : out_valid[out_port];
            assign lsu_response_is_write_ack[out_port] = out_resp[out_port*RESP_W + RESP_RDWR_BIT];
            assign lsu_response_size[out_port*MEM_SIZE_BITS +: MEM_SIZE_BITS]        = out_resp[out_port*RESP_W + RESP_SIZE_LSB +: MEM_SIZE_BITS];
            assign lsu_response_master_id[out_port*MASTER_ID_BITS +: MASTER_ID_BITS] = out_resp[out_port*RESP_W + RESP_MID_LSB  +: MASTER_ID_BITS];
            assign lsu_response_rob_index[out_port*IDX_BITS +: IDX_BITS]             = out_resp[out_port*RESP_W + RESP_IDX_LSB  +: IDX_BITS];
            assign lsu_response_data[out_port*WRITE_DATA_WIDTH +: WRITE_DATA_WIDTH]  = out_resp[out_port*RESP_W + RESP_DATA_LSB +: WRITE_DATA_WIDTH];
        end
        if (HAS_VPU == 0) begin : g_no_vpu
            assign vpu_out_resp          = {VPKT_W{1'b0}};
            assign vpu_resp_valid        = 1'b0;
            assign vpu_resp_is_write_ack = 1'b0;
            assign vpu_resp_master_id    = {MASTER_ID_BITS{1'b0}};
            assign vpu_resp_rob_index    = {IDX_BITS{1'b0}};
            assign vpu_resp_data         = {LINE_W{1'b0}};
        end
    endgenerate
    integer lr_bank;
    always @(posedge clk) begin
        if (rst) other_rsv_event_q <= {NB{1'b0}};
        else
            for (lr_bank = 0; lr_bank < NB; lr_bank = lr_bank + 1)
                other_rsv_event_q[lr_bank] <= |(bk_rsv_event & ~({{(NB-1){1'b0}}, 1'b1} << lr_bank));
    end
    l1d_l2_port #(`L1D_PARAMS_PASS, .L2_ADDR_W(L2_ADDR_W), .L2_MID_W(L2_MID_W), .L2_TID_W(L2_TID_W),
                  .L2_MASTER_ID(L2_MASTER_ID)) u_l2_port (
        .clk                           (clk),
        .rst                           (rst),
        .bank_read_req_valid           (bk_rd_valid),
        .bank_read_req_ready           (bk_rd_ready),
        .bank_read_req_addr            (bk_rd_addr),
        .bank_read_req_burst_len       (bk_rd_len),
        .bank_read_req_size            (bk_rd_size),
        .bank_read_req_sub_id          (bk_rd_sub),
        .bank_read_req_non_cacheable   (bk_rd_nc),
        .bank_read_req_unique          (bk_rd_unique),
        .bank_read_data_valid          (bk_r_valid),
        .bank_read_data_sub_id         (bk_r_sub),
        .bank_read_data_non_cacheable  (bk_r_nc),
        .bank_read_data                (bk_r_data),
        .bank_read_data_last           (bk_r_last),
        .bank_read_data_error          (bk_r_err),
        .bank_read_data_shared         (bk_r_shared),
        .bank_write_req_valid          (bk_wr_valid),
        .bank_write_req_ready          (bk_wr_ready),
        .bank_write_req_addr           (bk_wr_addr),
        .bank_write_req_burst_len      (bk_wr_len),
        .bank_write_req_size           (bk_wr_size),
        .bank_write_req_sub_id         (bk_wr_sub),
        .bank_write_req_non_cacheable  (bk_wr_nc),
        .bank_write_req_data           (bk_wr_data),
        .bank_write_req_strobe         (bk_wr_strb),
        .bank_write_resp_valid         (bk_b_valid),
        .bank_write_resp_sub_id        (bk_b_sub),
        .bank_write_resp_non_cacheable (bk_b_nc),
        .bank_write_resp_error         (bk_b_err),
        .bank_refill_replay_busy       (refill_busy),
        .l2_error_pulse                (l2_err),
        .l2_req_valid                  (l2_req_valid),
        .l2_req_ready                  (l2_req_ready),
        .l2_req_pkt                    (l2_req_pkt),
        .l2_resp_valid                 (l2_resp_valid),
        .l2_resp_ready                 (l2_resp_ready),
        .l2_resp_pkt                   (l2_resp_pkt),
        .l2_resp_err                   (l2_resp_err)
    );
    always @(posedge clk) begin
        if (rst)         l2_error_sticky <= 1'b0;
        else if (l2_err) l2_error_sticky <= 1'b1;
    end
    always @(posedge clk) begin
        if (rst)               amo_lock_timeout_sticky <= 1'b0;
        else if (|bk_lock_err) amo_lock_timeout_sticky <= 1'b1;
    end
    reg          mt_busy;
    reg [NB-1:0] mt_fin;
    wire [NB-1:0] mt_fin_now = mt_fin | mt_done;
    always @(posedge clk) begin
        if (rst) begin
            mt_busy        <= 1'b0;
            mt_start       <= 1'b0;
            mt_op          <= MAINT_CLEAN;
            mt_fin         <= {NB{1'b0}};
            flush_complete <= 1'b0;
            clean_complete <= 1'b0;
        end else begin
            mt_start       <= 1'b0;
            flush_complete <= 1'b0;
            clean_complete <= 1'b0;
            if (!mt_busy) begin
                if (flush_request || clean_request) begin
                    mt_busy  <= 1'b1;
                    mt_start <= 1'b1;
                    mt_op    <= flush_request ? MAINT_FLUSH : MAINT_CLEAN;
                    mt_fin   <= {NB{1'b0}};
                end
            end else if (&mt_fin_now) begin
                mt_busy        <= 1'b0;
                mt_fin         <= {NB{1'b0}};
                flush_complete <= (mt_op == MAINT_FLUSH);
                clean_complete <= (mt_op == MAINT_CLEAN);
            end else begin
                mt_fin <= mt_fin_now;
            end
        end
    end
`ifdef L1D_DEBUG
    localparam DBG_N = LSU_PORTS * (1 << IDX_BITS);
    reg              dbg_ov [0:DBG_N-1];
    reg              dbg_ow [0:DBG_N-1];
    reg              dbg_oc [0:DBG_N-1];
    reg [ADDR_W-1:0] dbg_oa [0:DBG_N-1];
    integer          dbg_ot [0:DBG_N-1];
    integer          dbg_cyc, dbg_i, dbg_age, dbg_port, dbg_e;
    initial begin
        dbg_cyc = 0;
        for (dbg_i = 0; dbg_i < DBG_N; dbg_i = dbg_i + 1) dbg_ov[dbg_i] = 1'b0;
    end
    always @(posedge clk) begin
        if (rst) begin
            dbg_cyc = 0;
            for (dbg_i = 0; dbg_i < DBG_N; dbg_i = dbg_i + 1) dbg_ov[dbg_i] = 1'b0;
        end else begin
            dbg_cyc = dbg_cyc + 1;
            for (dbg_port = 0; dbg_port < LSU_PORTS; dbg_port = dbg_port + 1) begin
                if (lsu_response_valid[dbg_port] && lsu_response_read_enable[dbg_port]) begin
                    dbg_e = dbg_port * (1 << IDX_BITS) + lsu_response_rob_index[dbg_port*IDX_BITS +: IDX_BITS];
                    if (!dbg_ov[dbg_e])
                        $display("[%0t] L1D TOP  ERROR port %0d response for idx %0d, which is not outstanding",
                                 $time, dbg_port, lsu_response_rob_index[dbg_port*IDX_BITS +: IDX_BITS]);
                    else
                        $display("[%0t] L1D TOP  DONE  port %0d idx=%0d %s %s addr=%h latency=%0d cycles",
                                 $time, dbg_port, lsu_response_rob_index[dbg_port*IDX_BITS +: IDX_BITS],
                                 (dbg_ow[dbg_e] ? "ST" : "LD"), (dbg_oc[dbg_e] ? "C " : "NC"), dbg_oa[dbg_e],
                                 dbg_cyc - dbg_ot[dbg_e]);
                    dbg_ov[dbg_e] = 1'b0;
                end
                if (cpu_request_valid[dbg_port]) begin
                    dbg_e = dbg_port * (1 << IDX_BITS) + cpu_request_rob_index[dbg_port*IDX_BITS +: IDX_BITS];
                    if (dbg_ov[dbg_e])
                        $display("[%0t] L1D TOP  ERROR port %0d idx %0d reused while still outstanding (old addr %h, issued %0d cycles ago; new addr %h). cpu_request_valid must be 1 for exactly one cycle per request, and an index may be reused only after its response.",
                                 $time, dbg_port, cpu_request_rob_index[dbg_port*IDX_BITS +: IDX_BITS], dbg_oa[dbg_e],
                                 dbg_cyc - dbg_ot[dbg_e], cpu_request_addr[dbg_port*ADDR_W +: ADDR_W]);
                    dbg_ov[dbg_e] = 1'b1;
                    dbg_ow[dbg_e] = cpu_request_is_write[dbg_port];
                    dbg_oc[dbg_e] = cpu_request_cacheable[dbg_port];
                    dbg_oa[dbg_e] = cpu_request_addr[dbg_port*ADDR_W +: ADDR_W];
                    dbg_ot[dbg_e] = dbg_cyc;
                end
            end
            for (dbg_i = 0; dbg_i < DBG_N; dbg_i = dbg_i + 1) begin
                dbg_age = dbg_cyc - dbg_ot[dbg_i];
                if (dbg_ov[dbg_i] && dbg_age > 0 && (dbg_age % `L1D_DBG_WD) == 0)
                    $display("[%0t] L1D TOP  STUCK port %0d idx=%0d %s %s addr=%h (bank %0d) has waited %0d cycles for its response; stop=%b, output valid=%b, read_enable=%b",
                             $time, dbg_i / (1 << IDX_BITS), dbg_i % (1 << IDX_BITS), (dbg_ow[dbg_i] ? "ST" : "LD"), (dbg_oc[dbg_i] ? "C " : "NC"),
                             dbg_oa[dbg_i], dbg_oa[dbg_i][BANK_LSB +: BANK_W], dbg_age,
                             input_queue_full, lsu_response_valid, lsu_response_read_enable);
            end
            if (!mt_busy && (flush_request || clean_request))
                $display("[%0t] L1D TOP  MAINT start %s", $time, flush_request ? "flush" : "clean");
            if (mt_busy && (flush_request || clean_request))
                $display("[%0t] L1D TOP  WARNING flush/clean request ignored: one is already running", $time);
            if (mt_busy && (&mt_fin_now))
                $display("[%0t] L1D TOP  MAINT all banks done", $time);
            if (l2_err && !l2_error_sticky)
                $display("[%0t] L1D TOP  ERROR L2 error answer: l2_error_sticky set", $time);
        end
    end
`endif
endmodule
`default_nettype wire
