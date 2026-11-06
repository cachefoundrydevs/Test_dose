    localparam PORTS    = `L1D_LSU_PORTS;
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
    localparam NOUT     = PORTS * NIDX;
    localparam SET_STRIDE = NB * LINE;
    localparam TAG_STRIDE = NB * SETS * LINE;
    localparam NT         = WAYS + VCS + 3;
    localparam NS         = 2;
    localparam NC_BASE    = 32'h0008_0000;
    localparam NC_LINES   = 4;
    localparam OPEN_N     = 12;
    localparam [2:0] K_LD = 3'd0, K_ST = 3'd1, K_LR = 3'd2, K_SC = 3'd3, K_AMO = 3'd4;
    localparam [3:0] OP_SWAP = 4'd0, OP_ADD = 4'd1, OP_XOR = 4'd2, OP_AND = 4'd3, OP_OR = 4'd4,
                     OP_MIN = 4'd5, OP_MAX = 4'd6, OP_MINU = 4'd7, OP_MAXU = 4'd8;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;
    reg                         flush = 0, clean = 0;
    wire                        flush_complete, clean_complete, mem_err, amo_err;
    reg  [PORTS-1:0]            req_valid = 0, req_cacheable = 0, req_is_write = 0, req_atomic = 0, req_is_amo = 0;
    reg  [PORTS*2-1:0]          req_size = 0;
    reg  [PORTS*IDX_BITS-1:0]   req_idx = 0;
    reg  [PORTS*ADDR_W-1:0]     req_addr = 0;
    reg  [PORTS*WDW-1:0]        req_data = 0;
    reg  [PORTS*4-1:0]          req_amo_op = 0;
    reg  [PORTS-1:0]            read_enable = {PORTS{1'b1}};
    wire [PORTS-1:0]            port_stop;
    wire [PORTS-1:0]            rsp_valid, rsp_is_write_ack;
    wire [PORTS*2-1:0]          rsp_size, rsp_mid;
    wire [PORTS*IDX_BITS-1:0]   rsp_idx;
    wire [PORTS*WDW-1:0]        rsp_data;
    wire                snp_valid, snp_ready, snp_inv;
    wire [ADDR_W-1:0]   snp_addr;
    wire                snpr_valid, snpr_ready, snpr_present, snpr_dirty;
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
    wire [15:0]             pend_v;
    wire [16*ADDR_W-1:0]    pend_a;
    l1d_top_axi_ports #(
        .SETS(SETS), .WAYS(WAYS), .LSU_BUF_DEPTH(LSU_BUF), .MSHR_ENTRIES(MSHR),
        .MSHR_NC_ENTRIES(NCE), .VC_SLOTS(VCS), .RESP_FIFO_DEPTH(RFIFO), .AXI_ID_W(AXI_IDW)
    ) dut (
        .clk(clk), .rst(rst),
        .flush_request(flush), .clean_request(clean), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .cpu_request_valid(req_valid), .cpu_request_cacheable(req_cacheable), .cpu_request_is_write(req_is_write),
        .cpu_request_size(req_size), .cpu_request_master_id({(PORTS*2){1'b0}}), .cpu_request_rob_index(req_idx),
        .cpu_request_addr(req_addr), .cpu_request_store_data(req_data),
        .cpu_request_is_atomic(req_atomic), .cpu_request_atomic_is_amo(req_is_amo), .cpu_request_amo_op(req_amo_op),
        .input_queue_full(port_stop),
        .lsu_response_read_enable(read_enable), .lsu_response_valid(rsp_valid), .lsu_response_is_write_ack(rsp_is_write_ack),
        .lsu_response_size(rsp_size), .lsu_response_master_id(rsp_mid), .lsu_response_rob_index(rsp_idx),
        .lsu_response_data(rsp_data),
        .snoop_request_valid(snp_valid), .snoop_request_ready(snp_ready), .snoop_request_addr(snp_addr),
        .snoop_request_invalidate(snp_inv),
        .snoop_response_valid(snpr_valid), .snoop_response_ready(snpr_ready), .snoop_response_addr(snpr_addr),
        .snoop_response_present(snpr_present), .snoop_response_dirty(snpr_dirty), .snoop_response_data(snpr_data),
        .axi_error_sticky(mem_err), .amo_lock_timeout_sticky(amo_err),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready), .m_axi_aruser(aruser),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_ruser(ruser), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .rd_pend_valid(pend_v), .rd_pend_addr(pend_a)
    );
`ifdef TBP_SNOOP
    wire [OPEN_N-1:0]        hold_v;
    wire [OPEN_N*ADDR_W-1:0] hold_a;
    wire                     r_busy, bd_valid, rdone_valid, rdone_unique;
    wire [ADDR_W-1:0]        r_line, bd_addr, rdone_line;
    wire [LINE*8-1:0]        bd_data;
    reg                      snp_en = 1'b0;
    reg                      focus_v = 1'b0;
    reg  [ADDR_W-1:0]        focus_a = 0;
    wire                     ans_valid, ans_inv, ans_present, ans_dirty, sg_idle;
    wire [ADDR_W-1:0]        ans_line;
    wire [31:0]              sg_err;
    snoop_gen #(.PEND_N(16), .ADDR_W(ADDR_W), .LINE(LINE), .NB(NB), .TAG_STRIDE(TAG_STRIDE), .SET_STRIDE(SET_STRIDE),
                .NT(NT), .NS(NS), .OPEN_N(OPEN_N), .COOL(2), .SEED(SEED0 + 13),
                .SNP_PCT(SNP_PCT), .INV_PCT(50), .READY_PCT(80)) u_snp (
        .clk(clk), .rst(rst), .enable(snp_en), .focus_v(focus_v), .focus_a(focus_a),
        .snp_valid(snp_valid), .snp_ready(snp_ready), .snp_addr(snp_addr), .snp_inv(snp_inv),
        .snpr_valid(snpr_valid), .snpr_ready(snpr_ready), .snpr_addr(snpr_addr),
        .snpr_present(snpr_present), .snpr_dirty(snpr_dirty), .snpr_data(snpr_data),
        .r_busy(r_busy), .r_line(r_line), .pend_v(pend_v), .pend_a(pend_a), .hold_v(hold_v), .hold_a(hold_a),
        .bd_valid(bd_valid), .bd_addr(bd_addr), .bd_data(bd_data),
        .rdone_valid(rdone_valid), .rdone_line(rdone_line), .rdone_unique(rdone_unique),
        .aw_fire(awvalid && awready), .aw_addr(awaddr), .aw_len(awlen),
        .ans_valid(ans_valid), .ans_line(ans_line), .ans_inv(ans_inv),
        .ans_present(ans_present), .ans_dirty(ans_dirty),
        .idle(sg_idle), .err_cnt(sg_err)
    );
`else
    assign snp_valid    = 1'b0;
    assign snp_addr     = {ADDR_W{1'b0}};
    assign snp_inv      = 1'b0;
    assign snpr_ready   = 1'b1;
    wire [OPEN_N-1:0]        hold_v = {OPEN_N{1'b0}};
    wire [OPEN_N*ADDR_W-1:0] hold_a = {(OPEN_N*ADDR_W){1'b0}};
    wire                     bd_valid = 1'b0;
    wire [ADDR_W-1:0]        bd_addr  = {ADDR_W{1'b0}};
    wire [LINE*8-1:0]        bd_data  = {(LINE*8){1'b0}};
    wire                     r_busy, rdone_valid, rdone_unique;
    wire [ADDR_W-1:0]        r_line, rdone_line;
`endif
    axi_mem_model #(.ID_W(AXI_IDW), .ADDR_W(AXI_AW), .DATA_W(AXI_DW), .MEM_BITS(MEM_BITS),
                    .LAT(8), .READY_PCT(70), .SEED(SEED0 + 7), .SHARED_PCT(0),
                    .LINE_BYTES(LINE), .HOLD_N(OPEN_N)) u_mem (
        .clk(clk), .rst(rst),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize), .aruser(aruser), .sh_mode(2'd0),
        .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .ruser(ruser), .rvalid(rvalid), .rready(rready),
        .hold_v(hold_v), .hold_a(hold_a), .r_busy(r_busy), .r_line(r_line),
        .bd_valid(bd_valid), .bd_addr(bd_addr), .bd_data(bd_data),
        .rdone_valid(rdone_valid), .rdone_line(rdone_line), .rdone_unique(rdone_unique)
    );
    reg [7:0]        ref_mem  [0:(1<<MEM_BITS)-1];
    reg              out_v    [0:NOUT-1];
    reg [2:0]        out_kind [0:NOUT-1];
    reg [1:0]        out_size [0:NOUT-1];
    reg [WDW-1:0]    out_exp  [0:NOUT-1];
    reg              out_chk  [0:NOUT-1];
    reg [ADDR_W-1:0] out_addr [0:NOUT-1];
    integer          out_t    [0:NOUT-1];
    integer          got_t    [0:NOUT-1];
    reg [WDW-1:0]    got_d    [0:NOUT-1];
    integer          n_out    [0:PORTS-1];
    integer seed, errors, issued, answered, total_out, cycles, wd_limit;
    integer lat_max_port [0:PORTS-1];
    integer lat_sum_port [0:PORTS-1];
    integer lat_cnt_port [0:PORTS-1];
    integer lat_hist [0:7];
    integer n_kind [0:4];
    integer n_slow = 0;
    integer          cl_cyc;
    integer          cl_n;
    reg [ADDR_W-1:0] cl_line [0:PORTS-1];
    reg              cl_wr   [0:PORTS-1];
    function [7:0] pattern;
        input integer a;
        begin
            pattern = (a * 37) ^ (a >> 7) ^ 8'h5A;
        end
    endfunction
    function [ADDR_W-1:0] line_addr;
        input integer t, s, b;
        begin
            line_addr = t * TAG_STRIDE + s * SET_STRIDE + b * LINE;
        end
    endfunction
    function [ADDR_W-1:0] line_of;
        input [ADDR_W-1:0] a;
        begin
            line_of = {a[ADDR_W-1:6], 6'd0};
        end
    endfunction
    function [WDW-1:0] ref_read;
        input [ADDR_W-1:0] a;
        input [1:0]        size;
        integer k;
        begin
            ref_read = {WDW{1'b0}};
            for (k = 0; k < (1 << size); k = k + 1)
                ref_read[k*8 +: 8] = ref_mem[a[MEM_BITS-1:0] + k];
        end
    endfunction
    task ref_write;
        input [ADDR_W-1:0] a;
        input [1:0]        size;
        input [WDW-1:0]    wd;
        integer k;
        begin
            for (k = 0; k < (1 << size); k = k + 1)
                ref_mem[a[MEM_BITS-1:0] + k] = wd[k*8 +: 8];
        end
    endtask
    function [WDW-1:0] amo_ref;
        input [3:0]     op;
        input [1:0]     size;
        input [WDW-1:0] old_v;
        input [WDW-1:0] opd;
        reg   signed [WDW-1:0] sa, sb;
        reg   [WDW-1:0] ua, ub;
        reg             lt_s, lt_u;
        begin
            if (size == 2'd3) begin
                sa = old_v; sb = opd; ua = old_v; ub = opd;
            end else begin
                sa = {{32{old_v[31]}}, old_v[31:0]}; sb = {{32{opd[31]}}, opd[31:0]};
                ua = {32'd0, old_v[31:0]};           ub = {32'd0, opd[31:0]};
            end
            lt_s = (sa < sb);
            lt_u = (ua < ub);
            case (op)
                OP_ADD:  amo_ref = old_v + opd;
                OP_XOR:  amo_ref = old_v ^ opd;
                OP_AND:  amo_ref = old_v & opd;
                OP_OR:   amo_ref = old_v | opd;
                OP_MIN:  amo_ref = lt_s ? old_v : opd;
                OP_MAX:  amo_ref = lt_s ? opd : old_v;
                OP_MINU: amo_ref = lt_u ? old_v : opd;
                OP_MAXU: amo_ref = lt_u ? opd : old_v;
                default: amo_ref = opd;
            endcase
        end
    endfunction
    function rule_r3_clash;
        input [ADDR_W-1:0] a;
        input              wr;
        integer q;
        begin
            rule_r3_clash = 1'b0;
            if (cl_cyc == cyc)
                for (q = 0; q < cl_n; q = q + 1)
                    if (cl_line[q] == line_of(a) && (wr || cl_wr[q])) rule_r3_clash = 1'b1;
        end
    endfunction
    reg  [PORTS-1:0] stop_prev;
    integer          stop_lag;
    initial begin stop_prev = {PORTS{1'b0}}; stop_lag = 0; end
    always @(posedge clk) stop_prev <= port_stop;
    function stop_seen;
        input integer pt;
        begin
            stop_seen = (stop_lag != 0) ? stop_prev[pt] : port_stop[pt];
        end
    endfunction
    function can_send;
        input integer pt;
        begin
            can_send = !stop_seen(pt) && (n_out[pt] < NIDX) && !req_valid[pt];
        end
    endfunction
    task tick;
        begin
            @(negedge clk);
            req_valid = {PORTS{1'b0}};
        end
    endtask
    task send;
        input integer      pt;
        input [2:0]        kind;
        input              nc;
        input [1:0]        size;
        input [ADDR_W-1:0] a;
        input [WDW-1:0]    wd;
        input [3:0]        op;
        output integer     entry;
        integer f, k;
        reg     wr;
        reg [WDW-1:0] old_v;
        begin
            wr = (kind == K_ST) || (kind == K_SC) || (kind == K_AMO);
            f = -1;
            for (k = NIDX - 1; k >= 0; k = k - 1) if (!out_v[pt*NIDX + k]) f = k;
            if (f < 0) begin
                errors = errors + 1;
                $display("ERROR %0t: testbench rule R2: no free ROB index on port %0d", $time, pt);
                f = 0;
            end
            if (stop_seen(pt)) begin
                errors = errors + 1;
                $display("ERROR %0t: testbench rule R1: send on port %0d while its stop is 1", $time, pt);
            end
            if (req_valid[pt]) begin
                errors = errors + 1;
                $display("ERROR %0t: testbench: port %0d sent twice in one cycle", $time, pt);
            end
            if (rule_r3_clash(a, wr)) begin
                errors = errors + 1;
                $display("ERROR %0t: testbench rule R3: two requests to line %h in one cycle, one of them writes", $time, line_of(a));
            end
            if (cl_cyc != cyc) begin cl_cyc = cyc; cl_n = 0; end
            cl_line[cl_n] = line_of(a); cl_wr[cl_n] = wr; cl_n = cl_n + 1;
            entry = pt * NIDX + f;
            req_valid[pt]                     = 1'b1;
            req_cacheable[pt]                 = !nc;
            req_is_write[pt]                  = (kind == K_ST) || (kind == K_SC);
            req_atomic[pt]                    = (kind == K_LR) || (kind == K_SC) || (kind == K_AMO);
            req_is_amo[pt]                    = (kind == K_AMO);
            req_amo_op[pt*4 +: 4]             = (kind == K_AMO) ? op : 4'd0;
            req_size[pt*2 +: 2]               = size;
            req_idx[pt*IDX_BITS +: IDX_BITS]  = f;
            req_addr[pt*ADDR_W +: ADDR_W]     = a;
            req_data[pt*WDW +: WDW]           = wd;
            out_v[entry]    = 1'b1;
            out_kind[entry] = kind;
            out_size[entry] = size;
            out_addr[entry] = a;
            out_t[entry]    = cyc;
            got_t[entry]    = -1;
            out_chk[entry]  = 1'b1;
            case (kind)
                K_ST: begin
                    ref_write(a, size, wd);
                    out_exp[entry] = {WDW{1'b0}};
                end
                K_AMO: begin
                    old_v = ref_read(a, size);
                    out_exp[entry] = old_v;
                    ref_write(a, size, amo_ref(op, size, old_v, wd));
                end
                K_SC: out_exp[entry] = {WDW{1'b0}};
                default: out_exp[entry] = ref_read(a, size);
            endcase
            n_out[pt] = n_out[pt] + 1;
            total_out = total_out + 1;
            issued    = issued + 1;
            n_kind[kind] = n_kind[kind] + 1;
        end
    endtask
    task wait_entry;
        input integer entry;
        integer t;
        begin
            t = 0;
            while (got_t[entry] < 0 && t < 30000) begin tick; t = t + 1; end
            if (got_t[entry] < 0) begin
                errors = errors + 1;
                $display("ERROR %0t: entry %0d (port %0d idx %0d) never answered", $time, entry, entry / NIDX, entry % NIDX);
            end
        end
    endtask
    task wait_drained;
        input integer rnd_pct;
        integer t, pp;
        begin
            t = 0;
            while (total_out != 0 && t < 400000) begin
                tick;
                for (pp = 0; pp < PORTS; pp = pp + 1)
                    read_enable[pp] = (rnd_pct == 0) ? 1'b1 : (({$random(seed)} % 100) < rnd_pct);
                t = t + 1;
            end
            read_enable = {PORTS{1'b1}};
            if (total_out != 0) begin
                errors = errors + 1;
                $display("ERROR %0t: %0d requests never answered", $time, total_out);
            end
        end
    endtask
    integer chk_port, chk_entry, chk_lat, chk_b;
    always @(posedge clk) begin
        if (!rst) begin
            for (chk_port = 0; chk_port < PORTS; chk_port = chk_port + 1) begin
                if (rsp_valid[chk_port] === 1'bx) begin
                    errors = errors + 1;
                    $display("ERROR %0t: port %0d response valid is X", $time, chk_port);
                end
                if (rsp_valid[chk_port] === 1'b1 && read_enable[chk_port]) begin
                    chk_entry = chk_port * NIDX + rsp_idx[chk_port*IDX_BITS +: IDX_BITS];
                    answered = answered + 1;
                    if (!out_v[chk_entry]) begin
                        errors = errors + 1;
                        $display("ERROR %0t: port %0d answer for idx %0d which is not outstanding (duplicate, lost or wrong port)",
                                 $time, chk_port, rsp_idx[chk_port*IDX_BITS +: IDX_BITS]);
                    end else begin
                        if (rsp_is_write_ack[chk_port] !== ((out_kind[chk_entry] == K_ST) || (out_kind[chk_entry] == K_SC)) ||
                            rsp_size[chk_port*2 +: 2] !== out_size[chk_entry] || rsp_mid[chk_port*2 +: 2] !== 2'd0) begin
                            errors = errors + 1;
                            $display("ERROR %0t: port %0d idx %0d wrong write_ack / size / master id", $time, chk_port,
                                     rsp_idx[chk_port*IDX_BITS +: IDX_BITS]);
                        end
                        if ((out_kind[chk_entry] == K_LD || out_kind[chk_entry] == K_LR || out_kind[chk_entry] == K_AMO) &&
                            out_chk[chk_entry] && rsp_data[chk_port*WDW +: WDW] !== out_exp[chk_entry]) begin
                            errors = errors + 1;
                            $display("ERROR %0t: port %0d idx %0d kind %0d @%h size %0d: got %h expected %h", $time, chk_port,
                                     rsp_idx[chk_port*IDX_BITS +: IDX_BITS], out_kind[chk_entry], out_addr[chk_entry],
                                     out_size[chk_entry], rsp_data[chk_port*WDW +: WDW], out_exp[chk_entry]);
                        end
                        if (out_kind[chk_entry] == K_SC && rsp_data[chk_port*WDW +: WDW] > 64'd1) begin
                            errors = errors + 1;
                            $display("ERROR %0t: port %0d idx %0d SC answered %h (must be 0 or 1)", $time, chk_port,
                                     rsp_idx[chk_port*IDX_BITS +: IDX_BITS], rsp_data[chk_port*WDW +: WDW]);
                        end
                        chk_lat = cyc - out_t[chk_entry];
                        if (chk_lat < 4) begin
                            errors = errors + 1;
                            $display("ERROR %0t: port %0d idx %0d answered after %0d cycles (an answer cannot come before 4)",
                                     $time, chk_port, rsp_idx[chk_port*IDX_BITS +: IDX_BITS], chk_lat);
                        end
                        if (chk_lat > 400 && n_slow < 20) begin
                            n_slow = n_slow + 1;
                            $display("SLOW %0t: port %0d idx %0d kind %0d @%h took %0d cycles (sent at cycle %0d)", $time, chk_port,
                                     rsp_idx[chk_port*IDX_BITS +: IDX_BITS], out_kind[chk_entry], out_addr[chk_entry], chk_lat, out_t[chk_entry]);
                        end
                        if (chk_lat > lat_max_port[chk_port]) lat_max_port[chk_port] = chk_lat;
                        lat_sum_port[chk_port] = lat_sum_port[chk_port] + chk_lat;
                        lat_cnt_port[chk_port] = lat_cnt_port[chk_port] + 1;
                        chk_b = (chk_lat <= 4) ? 0 : (chk_lat == 5) ? 1 : (chk_lat <= 7) ? 2 : (chk_lat <= 11) ? 3 :
                                (chk_lat <= 23) ? 4 : (chk_lat <= 63) ? 5 : (chk_lat <= 255) ? 6 : 7;
                        lat_hist[chk_b] = lat_hist[chk_b] + 1;
                        got_t[chk_entry] = cyc;
                        got_d[chk_entry] = rsp_data[chk_port*WDW +: WDW];
                        out_v[chk_entry] = 1'b0;
                        n_out[chk_port]  = n_out[chk_port] - 1;
                        total_out        = total_out - 1;
                    end
                end
            end
        end
    end
    task check;
        input            ok;
        input [8*80-1:0] what;
        begin
            if (!ok) begin
                errors = errors + 1;
                $display("ERROR: %0s", what);
            end else begin
                $display("  ok: %0s", what);
            end
        end
    endtask
    task check_memory;
        input [8*16-1:0] when;
        integer t, s, b, k, a, bad;
        begin
            bad = 0;
            for (t = 0; t < NT; t = t + 1)
                for (s = 0; s < NS; s = s + 1)
                    for (b = 0; b < NB; b = b + 1)
                        for (k = 0; k < LINE; k = k + 1) begin
                            a = t * TAG_STRIDE + s * SET_STRIDE + b * LINE + k;
                            if (u_mem.mem[a] !== ref_mem[a]) begin
                                bad = bad + 1;
                                if (bad <= 6) $display("  differs: address %h memory %h reference %h (tag %0d set %0d bank %0d)", a, u_mem.mem[a], ref_mem[a], t, s, b);
                            end
                        end
            for (k = 0; k < NC_LINES * LINE; k = k + 1)
                if (u_mem.mem[NC_BASE + k] !== ref_mem[NC_BASE + k]) begin
                    bad = bad + 1;
                    if (bad <= 6) $display("  differs: NC address %h memory %h reference %h", NC_BASE + k, u_mem.mem[NC_BASE + k], ref_mem[NC_BASE + k]);
                end
            if (bad != 0) begin
                errors = errors + 1;
                $display("ERROR: memory differs from the reference in %0d bytes after %0s", bad, when);
            end else begin
                $display("memory matches the reference after %0s", when);
            end
        end
    endtask
    task pulse_and_wait;
        input is_flush;
        integer t;
        begin
            @(negedge clk);
            req_valid = {PORTS{1'b0}};
            if (is_flush) flush = 1'b1; else clean = 1'b1;
            @(negedge clk);
            flush = 1'b0;
            clean = 1'b0;
            t = 0;
            while (!(is_flush ? flush_complete : clean_complete) && t < 500000) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t >= 500000) begin
                errors = errors + 1;
                $display("ERROR: %0s_complete never came", is_flush ? "flush" : "clean");
            end
            @(negedge clk);
        end
    endtask
    integer init_i, init_p;
    task init_tb_pre_reset;
        begin
            seed = SEED0;
            errors = 0; issued = 0; answered = 0; total_out = 0;
            cl_cyc = -1; cl_n = 0;
            for (init_i = 0; init_i < NOUT; init_i = init_i + 1) begin out_v[init_i] = 1'b0; got_t[init_i] = -1; got_d[init_i] = 0; out_chk[init_i] = 1'b1; end
            for (init_p = 0; init_p < PORTS; init_p = init_p + 1) begin
                n_out[init_p] = 0; lat_max_port[init_p] = 0; lat_sum_port[init_p] = 0; lat_cnt_port[init_p] = 0;
            end
            for (init_i = 0; init_i < 8; init_i = init_i + 1) lat_hist[init_i] = 0;
            for (init_i = 0; init_i < 5; init_i = init_i + 1) n_kind[init_i] = 0;
            for (init_i = 0; init_i < (1 << MEM_BITS); init_i = init_i + 1) ref_mem[init_i] = pattern(init_i);
            repeat (5) @(posedge clk);
        end
    endtask
    task init_tb_release_reset;
        input integer settle;
        begin
            @(negedge clk);
            rst = 1'b0;
            repeat (settle) @(negedge clk);
        end
    endtask
    task init_tb;
        begin
            init_tb_pre_reset;
            init_tb_release_reset(20);
        end
    endtask
    task finish_tb;
        input [8*24-1:0] name;
        begin
            $display("stats: %0d requests (LD %0d, ST %0d, LR %0d, SC %0d, AMO %0d), %0d answered; max latency per port: P0 %0d P1 %0d P2 %0d P3 %0d",
                     issued, n_kind[0], n_kind[1], n_kind[2], n_kind[3], n_kind[4], answered,
                     lat_max_port[0], lat_max_port[1], lat_max_port[2], lat_max_port[3]);
            $display("latency histogram (cycles 4 | 5 | 6-7 | 8-11 | 12-23 | 24-63 | 64-255 | more): %0d %0d %0d %0d %0d %0d %0d %0d",
                     lat_hist[0], lat_hist[1], lat_hist[2], lat_hist[3], lat_hist[4], lat_hist[5], lat_hist[6], lat_hist[7]);
            if (mem_err) begin errors = errors + 1; $display("ERROR: mem_err is set"); end
            if (amo_err) begin errors = errors + 1; $display("ERROR: amo_err is set"); end
`ifdef TBP_SNOOP
            if (sg_err != 0) begin errors = errors + 1; $display("ERROR: snoop_gen reported %0d contract errors", sg_err); end
`else
            if (snpr_valid) begin errors = errors + 1; $display("ERROR: a snoop answer without a snoop"); end
`endif
            if (total_out != 0) begin errors = errors + 1; $display("ERROR: %0d requests still outstanding at the end", total_out); end
            if (errors == 0) $display("TEST PASSED: %0s (%0d requests, seed %0d)", name, issued, SEED0);
            else             $display("TEST FAILED: %0s (%0d errors)", name, errors);
            $finish;
        end
    endtask
    initial begin
        cycles = 0;
        wd_limit = 6000000;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            if (cycles > wd_limit) begin
                $display("ERROR: watchdog, %0d requests outstanding after %0d cycles", total_out, cycles);
                $display("TEST FAILED: watchdog timeout");
                $finish;
            end
        end
    end
