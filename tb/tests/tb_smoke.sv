`timescale 1ns/1ps
`default_nettype none
`include "l1d_defines.vh"
module tb_smoke;
    localparam ADDR_W           = `L1D_ADDR_W;
    localparam WRITE_DATA_WIDTH = `L1D_WRITE_DATA_WIDTH;
    localparam MEM_SIZE_BITS    = `L1D_MEM_SIZE_BITS;
    localparam MASTER_ID_BITS   = `L1D_MASTER_ID_BITS;
    localparam IDX_BITS         = `L1D_IDX_BITS;
    localparam AXI_DATA_W       = `L1D_AXI_DATA_W;
    localparam AXI_ADDR_W       = `L1D_AXI_ADDR_W;
    localparam AXI_ID_W         = 1 + $clog2(`L1D_NUM_BANKS) +
                                  ((`L1D_MSHR_ENTRIES >= `L1D_VC_SLOTS) ? $clog2(`L1D_MSHR_ENTRIES)
                                                                         : $clog2(`L1D_VC_SLOTS));
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;
    logic                         flush = 1'b0, clean = 1'b0;
    logic                         valid_cpu = 1'b0, cacheable = 1'b1, rd_wr_cpu = 1'b0;
    logic [MEM_SIZE_BITS-1:0]     mem_size_cpu = '0;
    logic [MASTER_ID_BITS-1:0]    master_id_from_cpu = '0;
    logic [IDX_BITS-1:0]          idx_from_cpu = '0;
    logic [ADDR_W-1:0]            PC_from_cpu = '0;
    logic [WRITE_DATA_WIDTH-1:0]  data_from_cpu = '0;
    logic                         read_enable_from_lsu = 1'b1;
    wire                          flush_complete, clean_complete, mem_err;
    wire                          resp_valid, resp_rd_wr;
    wire [MEM_SIZE_BITS-1:0]      resp_size;
    wire [MASTER_ID_BITS-1:0]     resp_mid;
    wire [IDX_BITS-1:0]           resp_idx;
    wire [WRITE_DATA_WIDTH-1:0]   resp_data;
    wire [AXI_ID_W-1:0]   awid, arid;
    wire [AXI_ADDR_W-1:0] awaddr, araddr;
    wire [7:0]            awlen, arlen;
    wire [2:0]            awsize, arsize, awprot, arprot;
    wire [1:0]            awburst, arburst;
    wire [3:0]            awcache, arcache;
    wire                  awvalid, wvalid, wlast, bready, arvalid, rready;
    wire                  snpr_valid, amo_err;
    wire [AXI_DATA_W-1:0] wdata;
    wire [AXI_DATA_W/8-1:0] wstrb;
    l1d_top_axi dut (
        .clk                              (clk),
        .rst                              (rst),
        .flush_request                            (flush),
        .clean_request                            (clean),
        .flush_complete                   (flush_complete),
        .clean_complete                   (clean_complete),
        .cpu_request_valid                        (valid_cpu),
        .cpu_request_cacheable                        (cacheable),
        .cpu_request_is_write                        (rd_wr_cpu),
        .cpu_request_size                     (mem_size_cpu),
        .cpu_request_master_id               (master_id_from_cpu),
        .cpu_request_rob_index                     (idx_from_cpu),
        .cpu_request_addr                      (PC_from_cpu),
        .cpu_request_store_data                    (data_from_cpu),
        .cpu_request_is_atomic                          (1'b0),
        .cpu_request_atomic_is_amo                      (1'b0),
        .cpu_request_amo_op                             (4'd0),
        .snoop_request_valid                        (1'b0),
        .snoop_request_ready                        (),
        .snoop_request_addr                         ('0),
        .snoop_request_invalidate                          (1'b0),
        .snoop_response_valid                       (snpr_valid),
        .snoop_response_ready                       (1'b1),
        .snoop_response_addr                        (),
        .snoop_response_present                     (),
        .snoop_response_dirty                       (),
        .snoop_response_data                        (),
        .amo_lock_timeout_sticky                          (amo_err),
        .lsu_response_read_enable             (read_enable_from_lsu),
        .lsu_response_valid (resp_valid),
        .lsu_response_is_write_ack (resp_rd_wr),
        .lsu_response_size  (resp_size),
        .lsu_response_master_id (resp_mid),
        .lsu_response_rob_index       (resp_idx),
        .lsu_response_data      (resp_data),
        .axi_error_sticky                          (mem_err),
        .m_axi_awid    (awid),    .m_axi_awaddr (awaddr), .m_axi_awlen  (awlen),  .m_axi_awsize (awsize),
        .m_axi_awburst (awburst), .m_axi_awcache(awcache),.m_axi_awprot (awprot), .m_axi_awvalid(awvalid),
        .m_axi_awready (1'b1),
        .m_axi_wdata   (wdata),   .m_axi_wstrb  (wstrb),  .m_axi_wlast  (wlast),  .m_axi_wvalid (wvalid),
        .m_axi_wready  (1'b1),
        .m_axi_bid     ('0),      .m_axi_bresp  (2'b00),  .m_axi_bvalid (1'b0),   .m_axi_bready (bready),
        .m_axi_arid    (arid),    .m_axi_araddr (araddr), .m_axi_arlen  (arlen),  .m_axi_arsize (arsize),
        .m_axi_arburst (arburst), .m_axi_arcache(arcache),.m_axi_arprot (arprot), .m_axi_arvalid(arvalid),
        .m_axi_aruser  (),        .m_axi_ruser  (1'b0),
        .m_axi_arready (1'b1),
        .m_axi_rid     ('0),      .m_axi_rdata  ('0),     .m_axi_rresp  (2'b00),  .m_axi_rlast  (1'b0),
        .m_axi_rvalid  (1'b0),    .m_axi_rready (rready)
    );
    integer errors = 0;
    initial begin
        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (50) begin
            @(posedge clk);
            if (resp_valid || awvalid || wvalid || arvalid || flush_complete || clean_complete || mem_err || snpr_valid || amo_err) begin
                errors = errors + 1;
                $display("ERROR %0t: an output is active while the cache is idle", $time);
            end
        end
        if (errors == 0) $display("TEST PASSED: tb_smoke");
        else             $display("TEST FAILED: tb_smoke (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
