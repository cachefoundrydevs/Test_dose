`default_nettype none
`include "l1d_defines.vh"
module l1d_top_soc #(
    parameter D_CACHE_SIZE                    = 64 * 1024,
    parameter D_NUM_OF_WAYS                   = 4,
    parameter D_CACHE_LINE                    = 64,
    parameter D_SET_INDEX                     = D_CACHE_SIZE / (D_NUM_OF_WAYS * D_CACHE_LINE),
    parameter D_ADDR_WIDTH                    = 64,
    parameter D_CACHE_LINE_BITS               = D_CACHE_LINE * 8,
    parameter D_WRITE_DATA_WIDTH              = 64,
    parameter D_VICTIM_DEPTH                  = 8,
    parameter D_VICTIM_BITS                   = $clog2(D_VICTIM_DEPTH),
    parameter D_VC_DEPTH_FIFO                 = 8,
    parameter D_VC_DEPTH_FIFO_BITS            = $clog2(D_VC_DEPTH_FIFO),
    parameter D_MSHR_DEPTH                    = 16,
    parameter D_MSHR_BITS                     = $clog2(D_MSHR_DEPTH),
    parameter D_NON_CACHABLE_DEPTH            = 8,
    parameter D_NON_CACHABLE_BITS             = $clog2(D_NON_CACHABLE_DEPTH),
    parameter D_MSHR_DEPTH_FIFO               = 16,
    parameter D_AXI_BYTE                      = 16,
    parameter D_MM_BUS_SIZE_BITS              = D_AXI_BYTE * 8,
    parameter D_SHEDULAR_DEPTH                = 16,
    parameter D_SHEDULAR_BITS                 = $clog2(D_SHEDULAR_DEPTH),
    parameter D_NUM_OF_MASTER_ID              = 4,
    parameter D_NUM_OF_IDX                    = 8,
    parameter D_MASTER_ID_BITS                = $clog2(D_NUM_OF_MASTER_ID),
    parameter D_IDX_BITS                      = $clog2(D_NUM_OF_IDX),
    parameter D_MEM_SIZE_TYPE                 = 4,
    parameter D_MEM_SIZE_BITS                 = $clog2(D_MEM_SIZE_TYPE),
    parameter D_MSHR_TO_MM_DW_FIFO_DEPTH      = 16,
    parameter D_DATA_MSHR_TO_MM_DW_FIFO_DEPTH = 16,
    parameter D_OFFSET_BITS                   = $clog2(D_CACHE_LINE),
    parameter D_SET_BITS                      = $clog2(D_SET_INDEX),
    parameter D_WAY_BITS                      = $clog2(D_NUM_OF_WAYS),
    parameter D_TAG_BITS                      = D_ADDR_WIDTH - (D_SET_BITS + D_OFFSET_BITS),
    parameter D_CLEAN_WB_DEPTH                = 16,
    parameter D_CLEAN_WB_BITS                 = $clog2(D_CLEAN_WB_DEPTH),
    parameter D_NO_OF_TRANSTION               = D_CACHE_LINE_BITS / D_MM_BUS_SIZE_BITS,
    parameter D_TRANSTION_BITS                = $clog2(D_NO_OF_TRANSTION),
    parameter D_STROBE_BITS                   = D_AXI_BYTE,
    parameter D_FULL_STROBE_BITS              = D_NO_OF_TRANSTION * D_STROBE_BITS,
    parameter D_FINAL_WR_POINTER_AXI          = (D_MSHR_BITS + 1) + D_WAY_BITS + 1 + 1,
    parameter D_ARLEN                         = D_NO_OF_TRANSTION - 1,
    parameter D_ARSIZE                        = D_ARLEN,
    parameter D_ARBURST                       = 2,
    parameter D_AXI_READ_ADDR_BITS            = D_MSHR_BITS + 2,
    parameter D_AXI_WRITE_ADDR_BITS           = D_FINAL_WR_POINTER_AXI
) (
    input  wire                              clk,
    input  wire                              rst,
    input  wire                              flush,
    input  wire                              clean,
    input  wire                              valid_cpu,
    input  wire                              cachable,
    input  wire                              rd_wr_cpu,
    input  wire [D_MEM_SIZE_BITS-1:0]        mem_size_cpu,
    input  wire [D_MASTER_ID_BITS-1:0]       master_id_from_cpu,
    input  wire [D_IDX_BITS-1:0]             idx_from_cpu,
    input  wire [D_ADDR_WIDTH-1:0]           PC_from_cpu,
    input  wire [D_WRITE_DATA_WIDTH-1:0]     data_from_cpu,
    input  wire                              amo_cpu,
    input  wire                              amo_seq_cpu,
    input  wire [3:0]                        amo_op_cpu,
    input  wire                              snp_valid,
    output wire                              snp_ready,
    input  wire [D_ADDR_WIDTH-1:0]           snp_addr,
    input  wire                              snp_inv,
    output wire                              snpr_valid,
    input  wire                              snpr_ready,
    output wire [D_ADDR_WIDTH-1:0]           snpr_addr,
    output wire                              snpr_present,
    output wire                              snpr_dirty,
    output wire [D_CACHE_LINE_BITS-1:0]      snpr_data,
    output wire                              axi_arvalid,
    output wire [D_ADDR_WIDTH-1:0]           axi_araddr,
    output wire [D_AXI_READ_ADDR_BITS-1:0]   axi_arid,
    output wire [D_ARLEN-1:0]                axi_arlen,
    output wire [2:0]                        axi_arsize,
    output wire [1:0]                        axi_arburst,
    output wire                              axi_arlock,
    output wire [3:0]                        axi_arcache,
    output wire [2:0]                        axi_arprot,
    output wire [3:0]                        axi_arqos,
    output wire                              axi_aruser,
    input  wire                              axi_arready,
    input  wire                              axi_rvalid,
    input  wire [D_MM_BUS_SIZE_BITS-1:0]     axi_rdata,
    input  wire [D_AXI_READ_ADDR_BITS-1:0]   axi_rid,
    input  wire [1:0]                        axi_rres,
    input  wire                              axi_rlast,
    input  wire                              axi_ruser,
    output wire                              axi_rready,
    output wire                              axi_wr_arvalid,
    output wire [D_ADDR_WIDTH-1:0]           axi_wr_araddr,
    output wire [D_AXI_WRITE_ADDR_BITS-1:0]  axi_wr_arid,
    output wire [D_ARLEN-1:0]                axi_wr_arlen,
    output wire [2:0]                        axi_wr_arsize,
    output wire [1:0]                        axi_wr_arburst,
    output wire                              axi_wr_arlock,
    output wire [3:0]                        axi_wr_arcache,
    output wire [2:0]                        axi_wr_arprot,
    output wire [3:0]                        axi_wr_arqos,
    input  wire                              axi_wr_arready,
    output wire                              axi_wr_d_valid,
    output wire                              axi_wr_d_last,
    output wire [D_MM_BUS_SIZE_BITS-1:0]     axi_wr_d_data,
    output wire [D_AXI_WRITE_ADDR_BITS-1:0]  axi_wr_d_id,
    output wire [D_STROBE_BITS-1:0]          axi_wr_strobe,
    input  wire                              axi_wr_d_ready,
    input  wire                              axi_wr_res_valid,
    input  wire [1:0]                        axi_wr_res_error_info,
    input  wire [D_AXI_WRITE_ADDR_BITS-1:0]  axi_wr_res_addr_id,
    output wire                              axi_wr_res_ready,
    output wire                              stop,
    input  wire                              read_enable_from_lsu,
    output wire                              clean_complete,
    output wire                              flush_complete,
    output wire                              mem_err,
    output wire                              amo_err,
    output wire                              final_r_cache_hit_from_sheduler,
    output wire                              final_r_hit_rd_wr_from_sheduler,
    output wire [D_MEM_SIZE_BITS-1:0]        final_r_mem_size_from_sheduler,
    output wire [D_MASTER_ID_BITS-1:0]       final_r_master_id_from_sheduler,
    output wire [D_IDX_BITS-1:0]             final_r_idx_from_sheduler,
    output wire [D_WRITE_DATA_WIDTH-1:0]     final_r_data_from_sheduler
);
    localparam NUM_BANKS = `L1D_NUM_BANKS;
    localparam SETS      = D_SET_INDEX / NUM_BANKS;
    localparam MSHR_E    = `L1D_MSHR_ENTRIES;
    localparam VC_S      = `L1D_VC_SLOTS;
    localparam ID_W      = 6;
    generate
        if (ID_W > D_AXI_READ_ADDR_BITS || ID_W > D_AXI_WRITE_ADDR_BITS) begin : g_id_check
            initial begin
                $display("l1d_top_soc ERROR: v1 AXI id (%0d bits) is wider than D_AXI_READ_ADDR_BITS (%0d) or D_AXI_WRITE_ADDR_BITS (%0d)",
                         ID_W, D_AXI_READ_ADDR_BITS, D_AXI_WRITE_ADDR_BITS);
                $finish;
            end
        end
    endgenerate
    wire [ID_W-1:0]               awid,  arid;
    wire [D_ADDR_WIDTH-1:0]       awaddr, araddr;
    wire [7:0]                    awlen, arlen;
    wire [2:0]                    awsize, arsize, awprot, arprot;
    wire [1:0]                    awburst, arburst;
    wire [3:0]                    awcache, arcache;
    l1d_top_axi #(
        .ADDR_W           (D_ADDR_WIDTH),
        .LINE_BYTES       (D_CACHE_LINE),
        .NUM_BANKS        (NUM_BANKS),
        .SETS             (SETS),
        .WAYS             (D_NUM_OF_WAYS),
        .WRITE_DATA_WIDTH (D_WRITE_DATA_WIDTH),
        .MEM_SIZE_BITS    (D_MEM_SIZE_BITS),
        .MASTER_ID_BITS   (D_MASTER_ID_BITS),
        .IDX_BITS         (D_IDX_BITS),
        .MSHR_ENTRIES     (MSHR_E),
        .VC_SLOTS         (VC_S),
        .AXI_DATA_W       (D_MM_BUS_SIZE_BITS),
        .AXI_ADDR_W       (D_ADDR_WIDTH),
        .AXI_ID_W         (ID_W)
    ) u_l1d (
        .clk                       (clk),
        .rst                       (rst),
        .flush_request             (flush),
        .clean_request             (clean),
        .flush_complete            (flush_complete),
        .clean_complete            (clean_complete),
        .cpu_request_valid         (valid_cpu),
        .cpu_request_cacheable     (cachable),
        .cpu_request_is_write      (rd_wr_cpu),
        .cpu_request_size          (mem_size_cpu),
        .cpu_request_master_id     (master_id_from_cpu),
        .cpu_request_rob_index     (idx_from_cpu),
        .cpu_request_addr          (PC_from_cpu),
        .cpu_request_store_data    (data_from_cpu),
        .cpu_request_is_atomic     (amo_cpu),
        .cpu_request_atomic_is_amo (amo_seq_cpu),
        .cpu_request_amo_op        (amo_op_cpu),
        .input_queue_full          (stop),
        .snoop_request_valid       (snp_valid),
        .snoop_request_ready       (snp_ready),
        .snoop_request_addr        (snp_addr),
        .snoop_request_invalidate  (snp_inv),
        .snoop_response_valid      (snpr_valid),
        .snoop_response_ready      (snpr_ready),
        .snoop_response_addr       (snpr_addr),
        .snoop_response_present    (snpr_present),
        .snoop_response_dirty      (snpr_dirty),
        .snoop_response_data       (snpr_data),
        .lsu_response_read_enable  (read_enable_from_lsu),
        .lsu_response_valid        (final_r_cache_hit_from_sheduler),
        .lsu_response_is_write_ack (final_r_hit_rd_wr_from_sheduler),
        .lsu_response_size         (final_r_mem_size_from_sheduler),
        .lsu_response_master_id    (final_r_master_id_from_sheduler),
        .lsu_response_rob_index    (final_r_idx_from_sheduler),
        .lsu_response_data         (final_r_data_from_sheduler),
        .axi_error_sticky          (mem_err),
        .amo_lock_timeout_sticky   (amo_err),
        .m_axi_awid    (awid),
        .m_axi_awaddr  (awaddr),
        .m_axi_awlen   (awlen),
        .m_axi_awsize  (awsize),
        .m_axi_awburst (awburst),
        .m_axi_awcache (awcache),
        .m_axi_awprot  (awprot),
        .m_axi_awvalid (axi_wr_arvalid),
        .m_axi_awready (axi_wr_arready),
        .m_axi_wdata  (axi_wr_d_data),
        .m_axi_wstrb  (axi_wr_strobe),
        .m_axi_wlast  (axi_wr_d_last),
        .m_axi_wvalid (axi_wr_d_valid),
        .m_axi_wready (axi_wr_d_ready),
        .m_axi_bid    (axi_wr_res_addr_id[ID_W-1:0]),
        .m_axi_bresp  (axi_wr_res_error_info),
        .m_axi_bvalid (axi_wr_res_valid),
        .m_axi_bready (axi_wr_res_ready),
        .m_axi_arid    (arid),
        .m_axi_araddr  (araddr),
        .m_axi_arlen   (arlen),
        .m_axi_arsize  (arsize),
        .m_axi_arburst (arburst),
        .m_axi_arcache (arcache),
        .m_axi_arprot  (arprot),
        .m_axi_aruser  (axi_aruser),
        .m_axi_arvalid (axi_arvalid),
        .m_axi_arready (axi_arready),
        .m_axi_rid    (axi_rid[ID_W-1:0]),
        .m_axi_rdata  (axi_rdata),
        .m_axi_rresp  (axi_rres),
        .m_axi_rlast  (axi_rlast),
        .m_axi_ruser  (axi_ruser),
        .m_axi_rvalid (axi_rvalid),
        .m_axi_rready (axi_rready),
        .rd_pend_valid (),
        .rd_pend_addr  ()
    );
    localparam RD_PAD = D_AXI_READ_ADDR_BITS  - ID_W;
    localparam WR_PAD = D_AXI_WRITE_ADDR_BITS - ID_W;
    generate
        if (RD_PAD > 0) begin : g_rd_pad
            assign axi_arid = {{RD_PAD{1'b0}}, arid};
        end else begin : g_rd_nopad
            assign axi_arid = arid;
        end
        if (WR_PAD > 0) begin : g_wr_pad
            assign axi_wr_arid = {{WR_PAD{1'b0}}, awid};
            assign axi_wr_d_id = {{WR_PAD{1'b0}}, awid};
        end else begin : g_wr_nopad
            assign axi_wr_arid = awid;
            assign axi_wr_d_id = awid;
        end
    endgenerate
    assign axi_araddr     = araddr;
    assign axi_arlen      = arlen[D_ARLEN-1:0];
    assign axi_arsize     = arsize;
    assign axi_arburst    = arburst;
    assign axi_arlock     = 1'b0;
    assign axi_arcache    = arcache;
    assign axi_arprot     = arprot;
    assign axi_arqos      = 4'd0;
    assign axi_wr_araddr  = awaddr;
    assign axi_wr_arlen   = awlen[D_ARLEN-1:0];
    assign axi_wr_arsize  = awsize;
    assign axi_wr_arburst = awburst;
    assign axi_wr_arlock  = 1'b0;
    assign axi_wr_arcache = awcache;
    assign axi_wr_arprot  = awprot;
    assign axi_wr_arqos   = 4'd0;
`ifdef L1D_DEBUG
    integer dbg_x;
    integer dbg_arw, dbg_aww, dbg_ww, dbg_rsw;
    initial begin
        dbg_x = 0; dbg_arw = 0; dbg_aww = 0; dbg_ww = 0; dbg_rsw = 0;
        $display("L1D SOC  debug trace on: v1 AXI id = %0d bits, read id port %0d, write id port %0d, arlen port %0d bits, beats/line %0d",
                 ID_W, D_AXI_READ_ADDR_BITS, D_AXI_WRITE_ADDR_BITS, D_ARLEN, D_NO_OF_TRANSTION);
    end
    always @(posedge clk) begin
        if (rst !== 1'b0 && rst !== 1'b1 && dbg_x < 20) begin
            dbg_x = dbg_x + 1;
            $display("[%0t] L1D SOC  WARNING rst is %b", $time, rst);
        end
        if (rst === 1'b0) begin
            if (^{valid_cpu, read_enable_from_lsu, flush, clean, axi_arready, axi_rvalid,
                  axi_wr_arready, axi_wr_d_ready, axi_wr_res_valid} === 1'bx && dbg_x < 20) begin
                dbg_x = dbg_x + 1;
                $display("[%0t] L1D SOC  WARNING X/Z on a control input: valid_cpu=%b read_enable_from_lsu=%b flush=%b clean=%b axi_arready=%b axi_rvalid=%b axi_wr_arready=%b axi_wr_d_ready=%b axi_wr_res_valid=%b",
                         $time, valid_cpu, read_enable_from_lsu, flush, clean, axi_arready, axi_rvalid,
                         axi_wr_arready, axi_wr_d_ready, axi_wr_res_valid);
            end
            if (valid_cpu === 1'b1) begin
                $display("[%0t] L1D SOC  REQ   idx=%0d %s cachable=%b size=%0d mid=%0d addr=%h data=%h stop=%b",
                         $time, idx_from_cpu, (rd_wr_cpu ? "ST" : "LD"), cachable, mem_size_cpu,
                         master_id_from_cpu, PC_from_cpu, data_from_cpu, stop);
                if (^{cachable, rd_wr_cpu, mem_size_cpu, master_id_from_cpu, idx_from_cpu, PC_from_cpu} === 1'bx)
                    $display("[%0t] L1D SOC  WARNING X/Z in the request fields (cachable/rd_wr/size/mid/idx/addr)", $time);
            end
            if (final_r_cache_hit_from_sheduler && read_enable_from_lsu === 1'b1) begin
                $display("[%0t] L1D SOC  RESP  idx=%0d %s size=%0d mid=%0d data=%h",
                         $time, final_r_idx_from_sheduler, (final_r_hit_rd_wr_from_sheduler ? "ST-ack" : "LD"),
                         final_r_mem_size_from_sheduler, final_r_master_id_from_sheduler, final_r_data_from_sheduler);
                dbg_rsw = 0;
            end else if (final_r_cache_hit_from_sheduler) begin
                dbg_rsw = dbg_rsw + 1;
                if (dbg_rsw % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D SOC  STUCK response idx=%0d waits %0d cycles for read_enable_from_lsu (=%b)",
                             $time, final_r_idx_from_sheduler, dbg_rsw, read_enable_from_lsu);
            end
            if (axi_arvalid && axi_arready === 1'b1) begin
                $display("[%0t] L1D SOC  AR    id=%0d addr=%h len=%0d size=%0d burst=%0d cache=%h prot=%0d",
                         $time, axi_arid, axi_araddr, axi_arlen, axi_arsize, axi_arburst, axi_arcache, axi_arprot);
                dbg_arw = 0;
            end else if (axi_arvalid) begin
                dbg_arw = dbg_arw + 1;
                if (dbg_arw % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D SOC  STUCK axi_arvalid=1 for %0d cycles, axi_arready=%b (id=%0d addr=%h)",
                             $time, dbg_arw, axi_arready, axi_arid, axi_araddr);
            end
            if (axi_rvalid === 1'b1) begin
                $display("[%0t] L1D SOC  R     id=%0d rres=%0d rlast=%b data=%h",
                         $time, axi_rid, axi_rres, axi_rlast, axi_rdata);
                if (^{axi_rid, axi_rlast, axi_rres} === 1'bx)
                    $display("[%0t] L1D SOC  WARNING X/Z on axi_rid / axi_rlast / axi_rres while axi_rvalid=1", $time);
            end
            if (axi_wr_arvalid && axi_wr_arready === 1'b1) begin
                $display("[%0t] L1D SOC  AW    id=%0d addr=%h len=%0d size=%0d burst=%0d cache=%h",
                         $time, axi_wr_arid, axi_wr_araddr, axi_wr_arlen, axi_wr_arsize, axi_wr_arburst, axi_wr_arcache);
                dbg_aww = 0;
            end else if (axi_wr_arvalid) begin
                dbg_aww = dbg_aww + 1;
                if (dbg_aww % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D SOC  STUCK axi_wr_arvalid=1 for %0d cycles, axi_wr_arready=%b (id=%0d addr=%h)",
                             $time, dbg_aww, axi_wr_arready, axi_wr_arid, axi_wr_araddr);
            end
            if (axi_wr_d_valid && axi_wr_d_ready === 1'b1) begin
                $display("[%0t] L1D SOC  W     id=%0d last=%b strobe=%h data=%h",
                         $time, axi_wr_d_id, axi_wr_d_last, axi_wr_strobe, axi_wr_d_data);
                dbg_ww = 0;
            end else if (axi_wr_d_valid) begin
                dbg_ww = dbg_ww + 1;
                if (dbg_ww % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D SOC  STUCK axi_wr_d_valid=1 for %0d cycles, axi_wr_d_ready=%b (id=%0d)",
                             $time, dbg_ww, axi_wr_d_ready, axi_wr_d_id);
            end
            if (axi_wr_res_valid === 1'b1) begin
                $display("[%0t] L1D SOC  B     id=%0d resp=%0d", $time, axi_wr_res_addr_id, axi_wr_res_error_info);
                if (^{axi_wr_res_addr_id, axi_wr_res_error_info} === 1'bx)
                    $display("[%0t] L1D SOC  WARNING X/Z on axi_wr_res_addr_id / axi_wr_res_error_info while axi_wr_res_valid=1", $time);
            end
            if (flush === 1'b1 || clean === 1'b1)
                $display("[%0t] L1D SOC  MAINT flush=%b clean=%b", $time, flush, clean);
            if (clean_complete) $display("[%0t] L1D SOC  clean_complete", $time);
            if (flush_complete) $display("[%0t] L1D SOC  flush_complete", $time);
        end
    end
`endif
endmodule
`default_nettype wire
