    localparam SETS = 4, WAYS = 2, LSU_BUF = 8, MSHR = 4, NCE = 2, VCS = 2, RFIFO = 4;
    localparam ADDR_W   = `L1D_ADDR_W;
    localparam WDW      = `L1D_WRITE_DATA_WIDTH;
    localparam IDX_BITS = `L1D_IDX_BITS;
    localparam NB       = `L1D_NUM_BANKS;
    localparam LINE     = `L1D_LINE_BYTES;
    localparam AXI_DW   = `L1D_AXI_DATA_W;
    localparam AXI_AW   = `L1D_AXI_ADDR_W;
    localparam AXI_IDW  = 6;
    localparam MEM_BITS = 20;
    localparam NIDX     = (1 << IDX_BITS);
    localparam SET_STRIDE = NB * LINE;
    localparam TAG_STRIDE = NB * SETS * LINE;
    localparam NC_BASE    = 32'h0008_0000;
    localparam LOCK_TO    = 200;
    localparam [2:0] C_LD = 3'd0, C_ST = 3'd1, C_LR = 3'd2, C_SC = 3'd3, C_AR = 3'd4, C_AW = 3'd5;
    localparam [1:0] ST_I = 2'd0, ST_S = 2'd1, ST_E = 2'd2, ST_M = 2'd3;
    localparam [2:0] VC_FREE = 3'd0, VC_VALID = 3'd1, VC_MOVING = 3'd2, VC_WBPEND = 3'd3;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    reg                 flush = 0, clean = 0;
    wire                flush_complete, clean_complete, mem_err, amo_err;
    reg                 valid_cpu = 0, cacheable = 1, rd_wr_cpu = 0, amo_cpu = 0, amo_seq_cpu = 0;
    reg  [3:0]          amo_op_cpu = 0;
    reg  [3:0]          amo_op_sel = 1;
    reg  [1:0]          mem_size_cpu = 0;
    reg  [IDX_BITS-1:0] idx_from_cpu = 0;
    reg  [ADDR_W-1:0]   PC_from_cpu = 0;
    reg  [WDW-1:0]      data_from_cpu = 0;
    wire                r_valid, r_rdwr;
    wire [1:0]          r_size, r_mid;
    wire [IDX_BITS-1:0] r_idx;
    wire [WDW-1:0]      r_data;
    reg                 snp_valid = 0, snp_inv = 0;
    reg  [ADDR_W-1:0]   snp_addr = 0;
    wire                snp_ready;
    wire                snpr_valid, snpr_present, snpr_dirty;
    wire [ADDR_W-1:0]   snpr_addr;
    wire [LINE*8-1:0]   snpr_data;
    wire [AXI_IDW-1:0]  awid, arid, bid, rid;
    wire [AXI_AW-1:0]   awaddr, araddr;
    wire [7:0]          awlen, arlen;
    wire [2:0]          awsize, arsize, awprot, arprot;
    wire [1:0]          awburst, arburst, bresp, rresp;
    wire [3:0]          awcache, arcache;
    wire                awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire                arvalid, arready, rvalid, rready, rlast, aruser, ruser;
    wire [AXI_DW-1:0]   wdata, rdata;
    wire [AXI_DW/8-1:0] wstrb;
    l1d_top_axi #(
        .SETS(SETS), .WAYS(WAYS), .LSU_BUF_DEPTH(LSU_BUF), .MSHR_ENTRIES(MSHR),
        .MSHR_NC_ENTRIES(NCE), .VC_SLOTS(VCS), .RESP_FIFO_DEPTH(RFIFO), .AXI_ID_W(AXI_IDW),
        .LOCK_TIMEOUT(LOCK_TO)
    ) dut (
        .clk(clk), .rst(rst),
        .flush_request(flush), .clean_request(clean), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .cpu_request_valid(valid_cpu), .cpu_request_cacheable(cacheable), .cpu_request_is_write(rd_wr_cpu), .cpu_request_size(mem_size_cpu),
        .cpu_request_master_id(2'd0), .cpu_request_rob_index(idx_from_cpu),
        .cpu_request_addr(PC_from_cpu), .cpu_request_store_data(data_from_cpu),
        .cpu_request_is_atomic(amo_cpu), .cpu_request_atomic_is_amo(amo_seq_cpu), .cpu_request_amo_op(amo_op_cpu),
        .snoop_request_valid(snp_valid), .snoop_request_ready(snp_ready), .snoop_request_addr(snp_addr), .snoop_request_invalidate(snp_inv),
        .snoop_response_valid(snpr_valid), .snoop_response_ready(1'b1), .snoop_response_addr(snpr_addr),
        .snoop_response_present(snpr_present), .snoop_response_dirty(snpr_dirty), .snoop_response_data(snpr_data),
        .amo_lock_timeout_sticky(amo_err),
        .lsu_response_read_enable(1'b1),
        .lsu_response_valid(r_valid), .lsu_response_is_write_ack(r_rdwr),
        .lsu_response_size(r_size), .lsu_response_master_id(r_mid),
        .lsu_response_rob_index(r_idx), .lsu_response_data(r_data),
        .axi_error_sticky(mem_err),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready), .m_axi_aruser(aruser),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_ruser(ruser), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );
    reg              hold_v = 1'b0;
    reg [ADDR_W-1:0] hold_a = 0;
    reg [1:0]        sh_mode = 2'd1;
    wire             snpr_take = snpr_valid;
    axi_mem_model #(.ID_W(AXI_IDW), .ADDR_W(AXI_AW), .DATA_W(AXI_DW), .MEM_BITS(MEM_BITS),
                    .LAT(8), .READY_PCT(100), .SEED(3), .SHARED_PCT(0),
                    .LINE_BYTES(LINE), .HOLD_N(1)) u_mem (
        .clk(clk), .rst(rst),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize), .aruser(aruser), .sh_mode(sh_mode),
        .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .ruser(ruser), .rvalid(rvalid), .rready(rready),
        .hold_v(hold_v), .hold_a(hold_a), .r_busy(), .r_line(),
        .bd_valid(snpr_take && snpr_dirty), .bd_addr(snpr_addr), .bd_data(snpr_data),
        .rdone_valid(), .rdone_line(), .rdone_unique()
    );
    integer          errors = 0;
    integer          cyc = 0;
    always @(negedge clk) cyc = cyc + 1;
    reg              busy  [0:NIDX-1];
    reg              got_v [0:NIDX-1];
    reg [WDW-1:0]    got_d [0:NIDX-1];
    integer          got_t [0:NIDX-1];
    integer          snt_t [0:NIDX-1];
    integer          k_init;
    initial for (k_init = 0; k_init < NIDX; k_init = k_init + 1) begin
        busy[k_init] = 1'b0; got_v[k_init] = 1'b0; got_t[k_init] = 0; snt_t[k_init] = 0;
    end
    always @(posedge clk) begin
        if (!rst && r_valid) begin
            if (!busy[r_idx]) begin
                errors = errors + 1;
                $display("ERROR %0t: answer for idx %0d, which was not sent", $time, r_idx);
            end
            got_v[r_idx] = 1'b1;
            got_d[r_idx] = r_data;
            got_t[r_idx] = cyc;
        end
    end
    integer          snp_acc_t = 0;
    integer          sa_n = 0;
    integer          sa_t;
    reg              sa_present, sa_dirty;
    reg [ADDR_W-1:0] sa_addr;
    reg [LINE*8-1:0] sa_data;
    always @(posedge clk) begin
        if (!rst && snpr_take) begin
            sa_n       = sa_n + 1;
            sa_t       = cyc;
            sa_present = snpr_present;
            sa_dirty   = snpr_dirty;
            sa_addr    = snpr_addr;
            sa_data    = snpr_data;
        end
    end
    integer n_ar = 0, n_ar_uniq = 0;
    always @(posedge clk)
        if (!rst && arvalid && arready && arlen != 0) begin
            n_ar = n_ar + 1;
            if (aruser) n_ar_uniq = n_ar_uniq + 1;
        end
    function [ADDR_W-1:0] A;
        input integer t, s, b;
        begin
            A = t * TAG_STRIDE + s * SET_STRIDE + b * LINE;
        end
    endfunction
    task check;
        input        cond;
        input [8*96-1:0] text;
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("ERROR %0t: %0s", $time, text);
            end
        end
    endtask
    task send;
        input  [2:0]        cls;
        input               nc;
        input  [1:0]        size;
        input  [ADDR_W-1:0] a;
        input  [WDW-1:0]    wd;
        output integer      idx;
        integer f, k;
        begin
            @(negedge clk);
            f = -1;
            for (k = NIDX - 1; k >= 0; k = k - 1) if (!busy[k]) f = k;
            valid_cpu     = 1'b1;
            cacheable     = !nc;
            rd_wr_cpu     = (cls == C_ST || cls == C_SC || cls == C_AW);
            amo_cpu       = (cls == C_LR || cls == C_SC || cls == C_AR || cls == C_AW);
            amo_seq_cpu   = (cls == C_AR || cls == C_AW);
            amo_op_cpu    = (cls == C_AR) ? amo_op_sel : 4'd0;
            mem_size_cpu  = size;
            idx_from_cpu  = f;
            PC_from_cpu   = a;
            data_from_cpu = wd;
            busy[f]  = 1'b1;
            got_v[f] = 1'b0;
            snt_t[f] = cyc;
            idx      = f;
            @(negedge clk);
            valid_cpu   = 1'b0;
            amo_cpu     = 1'b0;
            amo_seq_cpu = 1'b0;
            amo_op_cpu  = 4'd0;
        end
    endtask
    task wait_resp;
        input  integer   idx;
        output [WDW-1:0] rd;
        integer t;
        begin
            t = 0;
            while (!got_v[idx] && t < 5000) begin
                @(negedge clk);
                t = t + 1;
            end
            if (!got_v[idx]) begin
                errors = errors + 1;
                $display("ERROR %0t: idx %0d never answered", $time, idx);
                rd = {WDW{1'bx}};
            end else begin
                rd = got_d[idx];
            end
            busy[idx] = 1'b0;
        end
    endtask
    task req;
        input  [2:0]        cls;
        input               nc;
        input  [1:0]        size;
        input  [ADDR_W-1:0] a;
        input  [WDW-1:0]    wd;
        output [WDW-1:0]    rd;
        integer idx;
        begin
            send(cls, nc, size, a, wd, idx);
            wait_resp(idx, rd);
        end
    endtask
    task snoop_send;
        input [ADDR_W-1:0] a;
        input              inv;
        begin
            @(negedge clk);
            snp_valid = 1'b1;
            snp_addr  = a;
            snp_inv   = inv;
            @(posedge clk);
            while (!snp_ready) @(posedge clk);
            snp_acc_t = cyc;
            @(negedge clk);
            snp_valid = 1'b0;
        end
    endtask
    task snoop;
        input  [ADDR_W-1:0] a;
        input               inv;
        output              present;
        output              dirty;
        output [LINE*8-1:0] data;
        integer n0, t;
        begin
            n0 = sa_n;
            snoop_send(a, inv);
            t = 0;
            while (sa_n == n0 && t < 5000) begin
                @(negedge clk);
                t = t + 1;
            end
            check(sa_n != n0, "snoop never answered");
            check(sa_addr == (a & ~(LINE - 1)), "snoop answer for the wrong line");
            present = sa_present;
            dirty   = sa_dirty;
            data    = sa_data;
        end
    endtask
    task peek_state;
        input  [ADDR_W-1:0] a;
        output [1:0]        st;
        reg [2*WAYS-1:0] sts;
        reg [63:0]       t0, t1, tg;
        integer s, b;
        begin
            repeat (8) @(negedge clk);
            b  = (a / LINE) % NB;
            s  = (a / SET_STRIDE) % SETS;
            tg = a / TAG_STRIDE;
            case (b)
                0: begin sts = dut.u_dcache.g_bank[0].u_bank.u_meta.states[s];
                         t0 = dut.u_dcache.g_bank[0].u_bank.u_tags.g_way[0].u_ram.mem[s];
                         t1 = dut.u_dcache.g_bank[0].u_bank.u_tags.g_way[1].u_ram.mem[s]; end
                1: begin sts = dut.u_dcache.g_bank[1].u_bank.u_meta.states[s];
                         t0 = dut.u_dcache.g_bank[1].u_bank.u_tags.g_way[0].u_ram.mem[s];
                         t1 = dut.u_dcache.g_bank[1].u_bank.u_tags.g_way[1].u_ram.mem[s]; end
                2: begin sts = dut.u_dcache.g_bank[2].u_bank.u_meta.states[s];
                         t0 = dut.u_dcache.g_bank[2].u_bank.u_tags.g_way[0].u_ram.mem[s];
                         t1 = dut.u_dcache.g_bank[2].u_bank.u_tags.g_way[1].u_ram.mem[s]; end
                default: begin sts = dut.u_dcache.g_bank[3].u_bank.u_meta.states[s];
                         t0 = dut.u_dcache.g_bank[3].u_bank.u_tags.g_way[0].u_ram.mem[s];
                         t1 = dut.u_dcache.g_bank[3].u_bank.u_tags.g_way[1].u_ram.mem[s]; end
            endcase
            st = ST_I;
            if (sts[1:0] != ST_I && t0 == tg) st = sts[1:0];
            if (sts[3:2] != ST_I && t1 == tg) st = sts[3:2];
        end
    endtask
    task peek_vc;
        input  [ADDR_W-1:0] a;
        output              found;
        output [2:0]        vst;
        output              dirty;
        output              shared;
        integer b, k;
        reg [ADDR_W-1:0] la;
        begin
            repeat (8) @(negedge clk);
            b = (a / LINE) % NB;
            found = 1'b0; vst = VC_FREE; dirty = 1'b0; shared = 1'b0;
            for (k = 0; k < VCS; k = k + 1) begin
                case (b)
                    0: begin la = dut.u_dcache.g_bank[0].u_bank.u_vc.la[k]; vst = dut.u_dcache.g_bank[0].u_bank.u_vc.st[k];
                             dirty = dut.u_dcache.g_bank[0].u_bank.u_vc.dty[k]; shared = dut.u_dcache.g_bank[0].u_bank.u_vc.shr[k]; end
                    1: begin la = dut.u_dcache.g_bank[1].u_bank.u_vc.la[k]; vst = dut.u_dcache.g_bank[1].u_bank.u_vc.st[k];
                             dirty = dut.u_dcache.g_bank[1].u_bank.u_vc.dty[k]; shared = dut.u_dcache.g_bank[1].u_bank.u_vc.shr[k]; end
                    2: begin la = dut.u_dcache.g_bank[2].u_bank.u_vc.la[k]; vst = dut.u_dcache.g_bank[2].u_bank.u_vc.st[k];
                             dirty = dut.u_dcache.g_bank[2].u_bank.u_vc.dty[k]; shared = dut.u_dcache.g_bank[2].u_bank.u_vc.shr[k]; end
                    default: begin la = dut.u_dcache.g_bank[3].u_bank.u_vc.la[k]; vst = dut.u_dcache.g_bank[3].u_bank.u_vc.st[k];
                             dirty = dut.u_dcache.g_bank[3].u_bank.u_vc.dty[k]; shared = dut.u_dcache.g_bank[3].u_bank.u_vc.shr[k]; end
                endcase
                if (vst != VC_FREE && la == (a / LINE)) begin
                    found = 1'b1;
                    k = VCS;
                end
            end
            if (!found) begin vst = VC_FREE; dirty = 1'b0; shared = 1'b0; end
        end
    endtask
    task idle;
        input integer n;
        begin
            repeat (n) @(negedge clk);
        end
    endtask
    function [63:0] mem64;
        input [ADDR_W-1:0] a;
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1) mem64[k*8 +: 8] = u_mem.mem[a[MEM_BITS-1:0] + k];
        end
    endfunction
    function [63:0] pat64;
        input [ADDR_W-1:0] a;
        integer k, x;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                x = a + k;
                pat64[k*8 +: 8] = (x * 37) ^ (x >> 7) ^ 8'h5A;
            end
        end
    endfunction
    initial begin
        #4000000;
        $display("TEST FAILED: %0s (timeout)", `TEST_NAME);
        $finish;
    end
