`ifndef L2_PKT_AXI_BRIDGE_V
`define L2_PKT_AXI_BRIDGE_V
`default_nettype none
module l2_pkt_axi_bridge #(
   parameter US_W       = 1,
   parameter ADDR_W     = 56,
   parameter RW_W       = 1,
   parameter MID_W      = 2,
   parameter TID_W      = 6,
   parameter NC_W       = 1,
   parameter DATA_W     = 512,
   parameter AXI_ADDR_W = 64,
   parameter AXI_DATA_W = 128,
   parameter ID_HAS_MID = 1,
   parameter AXI_ID_W   = 8,
   parameter N_OUT      = 8
) (
   input  wire                      clk,
   input  wire                      rst,
   input  wire                      req_valid,
   input  wire [US_W+ADDR_W+RW_W+MID_W+TID_W+NC_W+DATA_W/8+DATA_W-1:0] req_pkt,
   input  wire                      resp_ready,
   input  wire                      m_axi_awready,
   input  wire                      m_axi_wready,
   input  wire [AXI_ID_W-1:0]       m_axi_bid,
   input  wire [1:0]                m_axi_bresp,
   input  wire                      m_axi_bvalid,
   input  wire                      m_axi_arready,
   input  wire [AXI_ID_W-1:0]       m_axi_rid,
   input  wire [AXI_DATA_W-1:0]     m_axi_rdata,
   input  wire [1:0]                m_axi_rresp,
   input  wire                      m_axi_rlast,
   input  wire                      m_axi_rvalid,
   input  wire                      m_axi_ruser,
   output wire                      req_ready,
   output wire                      resp_valid,
   output wire [US_W+ADDR_W+RW_W+MID_W+TID_W+NC_W+DATA_W/8+DATA_W-1:0] resp_pkt,
   output wire                      resp_err,
   output wire [AXI_ID_W-1:0]       m_axi_awid,
   output wire [AXI_ADDR_W-1:0]     m_axi_awaddr,
   output wire [7:0]                m_axi_awlen,
   output wire [2:0]                m_axi_awsize,
   output wire [1:0]                m_axi_awburst,
   output wire [3:0]                m_axi_awcache,
   output wire [2:0]                m_axi_awprot,
   output wire                      m_axi_awvalid,
   output wire [AXI_DATA_W-1:0]     m_axi_wdata,
   output wire [AXI_DATA_W/8-1:0]   m_axi_wstrb,
   output wire                      m_axi_wlast,
   output wire                      m_axi_wvalid,
   output wire                      m_axi_bready,
   output wire [AXI_ID_W-1:0]       m_axi_arid,
   output wire [AXI_ADDR_W-1:0]     m_axi_araddr,
   output wire [7:0]                m_axi_arlen,
   output wire [2:0]                m_axi_arsize,
   output wire [1:0]                m_axi_arburst,
   output wire [3:0]                m_axi_arcache,
   output wire [2:0]                m_axi_arprot,
   output wire                      m_axi_aruser,
   output wire                      m_axi_arvalid,
   output wire                      m_axi_rready,
   output wire [N_OUT-1:0]          rd_pend_valid,
   output wire [N_OUT*AXI_ADDR_W-1:0] rd_pend_addr
);
   localparam MASK_W   = DATA_W / 8;
   localparam PKT_W    = US_W + ADDR_W + RW_W + MID_W + TID_W + NC_W + MASK_W +
                         DATA_W;
   localparam MASK_LO  = DATA_W;
   localparam NC_LO    = MASK_LO + MASK_W;
   localparam TID_LO   = NC_LO + NC_W;
   localparam MID_LO   = TID_LO + TID_W;
   localparam RW_LO    = MID_LO + MID_W;
   localparam ADDR_LO  = RW_LO + RW_W;
   localparam US_LO    = ADDR_LO + ADDR_W;
   localparam PID_W    = MID_W + TID_W;
   localparam AID_W    = (ID_HAS_MID != 0) ? PID_W : TID_W;
   localparam LINE_OFF = $clog2(DATA_W / 8);
   localparam APAD_W   = AXI_ADDR_W - ADDR_W;
   localparam IPAD_W   = AXI_ID_W - AID_W;
   localparam AXI_STRB_W = AXI_DATA_W / 8;
   localparam AXI_OFF_W  = $clog2(AXI_STRB_W);
   localparam BEATS      = DATA_W / AXI_DATA_W;
   localparam BEAT_W     = $clog2(BEATS);
   localparam LEN_W      = 8;
   localparam [LEN_W-1:0] AXI_LEN = BEATS - 1;
   localparam [2:0] AXI_SIZE = $clog2(AXI_STRB_W);
   localparam SLOT_W     = $clog2(N_OUT);
   localparam [1:0] AXI_BURST_INCR = 2'b01;
   localparam [3:0] AXI_CACHE_WB   = 4'b1111;
   localparam [3:0] AXI_CACHE_DEV  = 4'b0000;
   localparam [2:0] AXI_PROT_DATA  = 3'b000;
   localparam       RW_WRITE       = 1'b1;
   wire [ADDR_W-1:0]      rq_addr;
   wire                   rq_rw;
   wire [PID_W-1:0]       rq_pid;
   wire                   rq_nc;
   wire                   rq_us;
   wire [MASK_W-1:0]      rq_mask;
   wire [DATA_W-1:0]      rq_data;
   wire [BEAT_W-1:0]      rq_beat;
   reg  [2:0]             rq_nc_size;
   wire [AXI_ADDR_W-1:0]  rq_axi_addr;
   wire [LEN_W-1:0]       rq_len;
   wire [2:0]             rq_size;
   wire [3:0]             rq_cache;
   wire                   req_fire;
   wire                   req_ready_int;
   integer                n;
   integer                km;
   reg  [SLOT_W-1:0]      free_idx;
   reg                    has_free;
   reg  [SLOT_W-1:0]      r_slot;
   reg  [SLOT_W-1:0]      b_slot;
   reg  [SLOT_W-1:0]      resp_sel;
   reg                    resp_any;
   integer                k;
   integer                j;
   reg  [N_OUT-1:0]       slot_vld;
   reg  [N_OUT-1:0]       slot_done;
   reg  [N_OUT-1:0]       slot_rw;
   reg  [N_OUT-1:0]       slot_nc;
   reg  [N_OUT-1:0]       slot_err;
   reg  [N_OUT-1:0]       slot_shared;
   reg  [N_OUT-1:0]       slot_rstart;
   reg  [PID_W-1:0]       slot_pid  [0:N_OUT-1];
   reg  [ADDR_W-1:0]      slot_addr [0:N_OUT-1];
   reg  [MASK_W-1:0]      slot_mask [0:N_OUT-1];
   reg  [BEAT_W-1:0]      slot_beat [0:N_OUT-1];
   reg  [DATA_W-1:0]      slot_data [0:N_OUT-1];
   reg  [SLOT_W-1:0]      rr_ptr;
   reg                    ar_busy;
   reg  [AID_W-1:0]       ar_aid;
   reg  [AXI_ADDR_W-1:0]  ar_addr;
   reg  [LEN_W-1:0]       ar_len;
   reg  [2:0]             ar_size;
   reg  [3:0]             ar_cache;
   reg                    ar_user;
   reg                    w_busy;
   reg                    aw_done;
   reg                    w_done;
   reg  [BEAT_W-1:0]      w_beat;
   reg  [BEAT_W-1:0]      w_end;
   reg  [SLOT_W-1:0]      w_slot;
   reg  [AID_W-1:0]       aw_aid;
   reg  [AXI_ADDR_W-1:0]  aw_addr;
   reg  [LEN_W-1:0]       aw_len;
   reg  [2:0]             aw_size;
   reg  [3:0]             aw_cache;
   wire                   aw_fire;
   wire                   w_fire;
   wire                   w_last;
   wire                   r_fire;
   wire                   b_fire;
   wire                   resp_fire;
   wire                   r_err;
   wire                   b_err;
   wire [DATA_W-1:0]      resp_data;
   assign rq_addr     = req_pkt[ADDR_LO +: ADDR_W];
   assign rq_rw       = req_pkt[RW_LO];
   assign rq_pid      = req_pkt[TID_LO +: PID_W];
   assign rq_nc       = req_pkt[NC_LO];
   assign rq_us       = req_pkt[US_LO];
   assign rq_mask     = req_pkt[MASK_LO +: MASK_W];
   assign rq_data     = req_pkt[0 +: DATA_W];
   assign rq_beat     = rq_addr[AXI_OFF_W +: BEAT_W];
   always @* begin : nc_size_proc
      n = 0;
      for (km = 0; km < MASK_W; km = km + 1) begin
         n = n + rq_mask[km];
      end
      case (n)
         2:       rq_nc_size = 3'd1;
         4:       rq_nc_size = 3'd2;
         8:       rq_nc_size = 3'd3;
         16:      rq_nc_size = 3'd4;
         default: rq_nc_size = 3'd0;
      endcase
   end
   assign rq_axi_addr = rq_nc ? {{APAD_W{1'b0}}, rq_addr} :
                        {{APAD_W{1'b0}}, rq_addr[ADDR_W-1:LINE_OFF],
                         {LINE_OFF{1'b0}}};
   assign rq_len      = rq_nc ? {LEN_W{1'b0}} : AXI_LEN;
   assign rq_size     = rq_nc ? rq_nc_size : AXI_SIZE;
   assign rq_cache    = rq_nc ? AXI_CACHE_DEV : AXI_CACHE_WB;
   always @* begin : free_proc
      free_idx = {SLOT_W{1'b0}};
      has_free = 1'b0;
      for (k = N_OUT - 1; k >= 0; k = k - 1) begin
         if (!slot_vld[k]) begin
            free_idx = k[SLOT_W-1:0];
            has_free = 1'b1;
         end
      end
   end
   always @* begin : match_proc
      r_slot = {SLOT_W{1'b0}};
      b_slot = {SLOT_W{1'b0}};
      for (k = 0; k < N_OUT; k = k + 1) begin
         if (slot_vld[k] && !slot_done[k] && !slot_rw[k] &&
             (slot_pid[k][AID_W-1:0] == m_axi_rid[AID_W-1:0])) begin
            r_slot = k[SLOT_W-1:0];
         end
         if (slot_vld[k] && !slot_done[k] && slot_rw[k] &&
             (slot_pid[k][AID_W-1:0] == m_axi_bid[AID_W-1:0])) begin
            b_slot = k[SLOT_W-1:0];
         end
      end
   end
   always @* begin : resp_pick_proc
      resp_sel = {SLOT_W{1'b0}};
      resp_any = 1'b0;
      for (k = 2 * N_OUT - 1; k >= 0; k = k - 1) begin
         j = (k >= N_OUT) ? (k - N_OUT) : k;
         if ((k >= rr_ptr) && slot_done[j]) begin
            resp_sel = j[SLOT_W-1:0];
            resp_any = 1'b1;
         end
      end
   end
   assign req_ready_int = has_free & ~ar_busy & ~w_busy;
   assign req_fire      = req_valid & req_ready_int;
   assign aw_fire       = w_busy & ~aw_done & m_axi_awready;
   assign w_fire        = w_busy & ~w_done & m_axi_wready;
   assign w_last        = (w_beat == w_end);
   assign r_fire        = m_axi_rvalid;
   assign b_fire        = m_axi_bvalid;
   assign resp_fire     = resp_any & resp_ready;
   assign r_err         = m_axi_rresp[1];
   assign b_err         = m_axi_bresp[1];
   always @(posedge clk) begin : slot_ctrl_proc
      if (rst) begin
         slot_vld  <= {N_OUT{1'b0}};
         slot_done <= {N_OUT{1'b0}};
         slot_err  <= {N_OUT{1'b0}};
         slot_shared <= {N_OUT{1'b0}};
         slot_rstart <= {N_OUT{1'b0}};
         rr_ptr    <= {SLOT_W{1'b0}};
      end else begin
         if (req_fire) begin
            slot_vld[free_idx]  <= 1'b1;
            slot_done[free_idx] <= 1'b0;
            slot_err[free_idx]  <= 1'b0;
            slot_shared[free_idx] <= 1'b0;
            slot_rstart[free_idx] <= 1'b0;
         end
         if (r_fire) begin
            slot_err[r_slot] <= slot_err[r_slot] | r_err;
            slot_shared[r_slot] <= slot_shared[r_slot] | m_axi_ruser;
            slot_rstart[r_slot] <= 1'b1;
            if (m_axi_rlast) begin
               slot_done[r_slot] <= 1'b1;
            end
         end
         if (b_fire) begin
            slot_err[b_slot]  <= b_err;
            slot_done[b_slot] <= 1'b1;
         end
         if (resp_fire) begin
            slot_vld[resp_sel]  <= 1'b0;
            slot_done[resp_sel] <= 1'b0;
            rr_ptr <= (resp_sel == N_OUT - 1) ? {SLOT_W{1'b0}} :
                      resp_sel + 1'b1;
         end
      end
   end
   always @(posedge clk) begin : slot_data_proc
      if (req_fire) begin
         slot_rw[free_idx]   <= rq_rw;
         slot_nc[free_idx]   <= rq_nc;
         slot_pid[free_idx]  <= rq_pid;
         slot_addr[free_idx] <= rq_addr;
         slot_mask[free_idx] <= rq_mask;
         slot_beat[free_idx] <= rq_nc ? rq_beat : {BEAT_W{1'b0}};
         slot_data[free_idx] <= rq_data;
      end
      if (r_fire) begin
         slot_data[r_slot][slot_beat[r_slot] * AXI_DATA_W +: AXI_DATA_W]
            <= m_axi_rdata;
         slot_beat[r_slot] <= slot_beat[r_slot] + 1'b1;
      end
   end
   always @(posedge clk) begin : ar_proc
      if (rst) begin
         ar_busy <= 1'b0;
      end else if (req_fire && (rq_rw != RW_WRITE)) begin
         ar_busy <= 1'b1;
      end else if (ar_busy && m_axi_arready) begin
         ar_busy <= 1'b0;
      end
   end
   always @(posedge clk) begin : ar_data_proc
      if (req_fire && (rq_rw != RW_WRITE)) begin
         ar_aid   <= rq_pid[AID_W-1:0];
         ar_addr  <= rq_axi_addr;
         ar_len   <= rq_len;
         ar_size  <= rq_size;
         ar_cache <= rq_cache;
         ar_user  <= rq_us & ~rq_nc;
      end
   end
   always @(posedge clk) begin : w_proc
      if (rst) begin
         w_busy  <= 1'b0;
         aw_done <= 1'b0;
         w_done  <= 1'b0;
         w_beat  <= {BEAT_W{1'b0}};
      end else if (req_fire && (rq_rw == RW_WRITE)) begin
         w_busy  <= 1'b1;
         aw_done <= 1'b0;
         w_done  <= 1'b0;
         w_beat  <= rq_nc ? rq_beat : {BEAT_W{1'b0}};
      end else if (w_busy) begin
         if (aw_fire) begin
            aw_done <= 1'b1;
         end
         if (w_fire) begin
            if (w_last) begin
               w_done <= 1'b1;
            end else begin
               w_beat <= w_beat + 1'b1;
            end
         end
         if ((aw_done || aw_fire) && (w_done || (w_fire && w_last))) begin
            w_busy <= 1'b0;
         end
      end
   end
   always @(posedge clk) begin : w_data_proc
      if (req_fire && (rq_rw == RW_WRITE)) begin
         w_slot   <= free_idx;
         w_end    <= rq_nc ? rq_beat : AXI_LEN[BEAT_W-1:0];
         aw_aid   <= rq_pid[AID_W-1:0];
         aw_addr  <= rq_axi_addr;
         aw_len   <= rq_len;
         aw_size  <= rq_size;
         aw_cache <= rq_cache;
      end
   end
   assign resp_data  = slot_rw[resp_sel] ? {DATA_W{1'b0}} :
                       slot_data[resp_sel];
   assign req_ready  = req_ready_int;
   assign resp_valid = resp_any;
   assign resp_pkt   = {slot_shared[resp_sel] & ~slot_rw[resp_sel] & ~slot_nc[resp_sel], slot_addr[resp_sel], slot_rw[resp_sel],
                        slot_pid[resp_sel], slot_nc[resp_sel],
                        slot_mask[resp_sel], resp_data};
   assign resp_err   = slot_err[resp_sel];
   assign m_axi_arvalid = ar_busy;
   assign m_axi_arid    = {{IPAD_W{1'b0}}, ar_aid};
   assign m_axi_araddr  = ar_addr;
   assign m_axi_arlen   = ar_len;
   assign m_axi_arsize  = ar_size;
   assign m_axi_arburst = AXI_BURST_INCR;
   assign m_axi_arcache = ar_cache;
   assign m_axi_arprot  = AXI_PROT_DATA;
   assign m_axi_aruser  = ar_user;
   assign m_axi_rready  = 1'b1;
   assign m_axi_awvalid = w_busy & ~aw_done;
   assign m_axi_awid    = {{IPAD_W{1'b0}}, aw_aid};
   assign m_axi_awaddr  = aw_addr;
   assign m_axi_awlen   = aw_len;
   assign m_axi_awsize  = aw_size;
   assign m_axi_awburst = AXI_BURST_INCR;
   assign m_axi_awcache = aw_cache;
   assign m_axi_awprot  = AXI_PROT_DATA;
   assign m_axi_wvalid  = w_busy & ~w_done;
   assign m_axi_wdata   = slot_data[w_slot][w_beat * AXI_DATA_W +:
                                            AXI_DATA_W];
   assign m_axi_wstrb   = slot_mask[w_slot][w_beat * AXI_STRB_W +:
                                            AXI_STRB_W];
   assign m_axi_wlast   = w_last;
   assign m_axi_bready  = 1'b1;
   genvar gp;
   generate
      for (gp = 0; gp < N_OUT; gp = gp + 1) begin : g_rd_pend
         assign rd_pend_valid[gp] = slot_vld[gp] & ~slot_rw[gp] & ~slot_nc[gp] & (slot_rstart[gp] | slot_done[gp]);
         assign rd_pend_addr[gp*AXI_ADDR_W +: AXI_ADDR_W] = {{APAD_W{1'b0}}, slot_addr[gp][ADDR_W-1:LINE_OFF], {LINE_OFF{1'b0}}};
      end
   endgenerate
`ifdef L1D_DEBUG
   always @(posedge clk) begin : dbg_proc
      if (!rst && req_fire) begin
         for (k = 0; k < N_OUT; k = k + 1) begin
            if (slot_vld[k] &&
                (slot_pid[k][AID_W-1:0] == rq_pid[AID_W-1:0])) begin
               $display("[%0t] L2 BRIDGE ERROR id %h reused in flight",
                        $time, rq_pid);
            end
         end
         if (rq_nc && (rq_nc_size == 3'd0) && (n != 1)) begin
            $display("[%0t] L2 BRIDGE ERROR NC mask %h is not 1/2/4/8/16 bytes",
                     $time, rq_mask);
         end
      end
      if (!rst && r_fire && !(|(slot_vld & ~slot_done & ~slot_rw))) begin
         $display("[%0t] L2 BRIDGE ERROR R id %h, no read waiting",
                  $time, m_axi_rid);
      end
      if (!rst && b_fire && !(|(slot_vld & ~slot_done & slot_rw))) begin
         $display("[%0t] L2 BRIDGE ERROR B id %h, no write waiting",
                  $time, m_axi_bid);
      end
   end
`endif
endmodule
`default_nettype wire
`endif
