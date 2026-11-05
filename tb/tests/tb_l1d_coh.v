`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_l1d_coh;
`ifdef TINY
    localparam SETS = 4, WAYS = 2, LSU_BUF = 4, MSHR = 2, NCE = 1, VCS = 2, RFIFO = 2;
`else
    localparam SETS = `L1D_SETS, WAYS = `L1D_WAYS, LSU_BUF = `L1D_LSU_BUF_DEPTH,
               MSHR = `L1D_MSHR_ENTRIES, NCE = `L1D_MSHR_NC_ENTRIES, VCS = `L1D_VC_SLOTS,
               RFIFO = `L1D_RESP_FIFO_DEPTH;
`endif
`ifdef NOPS
    localparam N_OPS = `NOPS;
`else
    localparam N_OPS = 4000;
`endif
`ifdef SEED
    localparam SEED0 = `SEED;
`else
    localparam SEED0 = 1;
`endif
`ifdef SHARED
    localparam SHARED_PCT = `SHARED;
`else
    localparam SHARED_PCT = 25;
`endif
`ifdef SNP
    localparam SNP_PCT = `SNP;
`else
    localparam SNP_PCT = 8;
`endif
`ifdef MODEB
    localparam MODE_B = 1;
`else
    localparam MODE_B = 0;
`endif
`ifdef NOATOM
    localparam ATOM = 0;
`else
    localparam ATOM = 1;
`endif
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
    localparam OPEN_N   = 12;
    localparam N_ATOM   = 2;
    localparam SET_STRIDE = NB * LINE;
    localparam TAG_STRIDE = NB * SETS * LINE;
    localparam NT         = WAYS + VCS + 3;
    localparam NS         = 2;
    localparam NL         = NT * NS * NB;
    localparam NC_BASE    = 32'h0008_0000;
    localparam NC_LINES   = 4;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    reg                 flush = 0, clean = 0;
    wire                flush_complete, clean_complete, mem_err, amo_err;
    reg                 valid_cpu = 0, cacheable = 1, rd_wr_cpu = 0, amo_cpu = 0, amo_seq_cpu = 0;
    reg  [3:0]          amo_op_cpu = 0;
    reg  [1:0]          mem_size_cpu = 0;
    reg  [1:0]          master_id_from_cpu = 0;
    reg  [IDX_BITS-1:0] idx_from_cpu = 0;
    reg  [ADDR_W-1:0]   PC_from_cpu = 0;
    reg  [WDW-1:0]      data_from_cpu = 0;
    reg                 read_enable_from_lsu = 1;
    wire                r_valid, r_rdwr;
    wire [1:0]          r_size, r_mid;
    wire [IDX_BITS-1:0] r_idx;
    wire [WDW-1:0]      r_data;
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
    wire [15:0]              pend_v;
    wire [16*ADDR_W-1:0]     pend_a;
    l1d_top_axi #(
        .SETS(SETS), .WAYS(WAYS), .LSU_BUF_DEPTH(LSU_BUF), .MSHR_ENTRIES(MSHR),
        .MSHR_NC_ENTRIES(NCE), .VC_SLOTS(VCS), .RESP_FIFO_DEPTH(RFIFO), .AXI_ID_W(AXI_IDW)
    ) dut (
        .clk(clk), .rst(rst),
        .flush_request(flush), .clean_request(clean), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .cpu_request_valid(valid_cpu), .cpu_request_cacheable(cacheable), .cpu_request_is_write(rd_wr_cpu), .cpu_request_size(mem_size_cpu),
        .cpu_request_master_id(master_id_from_cpu), .cpu_request_rob_index(idx_from_cpu),
        .cpu_request_addr(PC_from_cpu), .cpu_request_store_data(data_from_cpu),
        .cpu_request_is_atomic(amo_cpu), .cpu_request_atomic_is_amo(amo_seq_cpu), .cpu_request_amo_op(amo_op_cpu),
        .snoop_request_valid(snp_valid), .snoop_request_ready(snp_ready), .snoop_request_addr(snp_addr), .snoop_request_invalidate(snp_inv),
        .snoop_response_valid(snpr_valid), .snoop_response_ready(snpr_ready), .snoop_response_addr(snpr_addr),
        .snoop_response_present(snpr_present), .snoop_response_dirty(snpr_dirty), .snoop_response_data(snpr_data),
        .amo_lock_timeout_sticky(amo_err),
        .lsu_response_read_enable(read_enable_from_lsu),
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
        .m_axi_ruser(ruser), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .rd_pend_valid(pend_v), .rd_pend_addr(pend_a)
    );
    wire [OPEN_N-1:0]        hold_v;
    wire [OPEN_N*ADDR_W-1:0] hold_a;
    wire                     r_busy, bd_valid, rdone_valid, rdone_unique;
    wire [ADDR_W-1:0]        r_line, bd_addr, rdone_line;
    wire [LINE*8-1:0]        bd_data;
    axi_mem_model #(.ID_W(AXI_IDW), .ADDR_W(AXI_AW), .DATA_W(AXI_DW), .MEM_BITS(MEM_BITS),
                    .LAT(8), .READY_PCT(70), .SEED(SEED0 + 7), .SHARED_PCT(SHARED_PCT),
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
    reg         snp_en = 1'b0;
    reg         focus_v;
    reg  [ADDR_W-1:0] focus_a;
    wire        ans_valid, ans_inv, ans_present, ans_dirty, sg_idle;
    wire [ADDR_W-1:0] ans_line;
    wire [31:0] sg_err;
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
    localparam [2:0] C_LD = 3'd0, C_ST = 3'd1, C_LR = 3'd2, C_SC = 3'd3, C_AR = 3'd4, C_AW = 3'd5;
    localparam [2:0] A_IDLE = 3'd0, A_LRW = 3'd1, A_LRD = 3'd2, A_SCW = 3'd3, A_ARW = 3'd4, A_ARD = 3'd5, A_AWW = 3'd6;
    reg [7:0]        ref_mem  [0:(1<<MEM_BITS)-1];
    reg              out_v    [0:NIDX-1];
    reg [2:0]        out_cls  [0:NIDX-1];
    reg [1:0]        out_size [0:NIDX-1];
    reg [WDW-1:0]    out_exp  [0:NIDX-1];
    reg [WDW-1:0]    out_wd   [0:NIDX-1];
    reg [ADDR_W-1:0] out_addr [0:NIDX-1];
    reg              out_nc   [0:NIDX-1];
    integer          out_slot [0:NIDX-1];
    integer          out_t    [0:NIDX-1];
    reg [2:0]        at_st   [0:N_ATOM-1];
    reg [ADDR_W-1:0] at_addr [0:N_ATOM-1];
    reg              at_brk  [0:N_ATOM-1];
    reg [WDW-1:0]    at_old  [0:N_ATOM-1];
    integer          at_t    [0:N_ATOM-1];
    integer          at_wait [0:N_ATOM-1];
    integer          snp_acc_t [0:NL-1];
    integer seed, i, errors, issued, answered, n_out, cycles;
    integer cyc;
    integer j1, j2;
    integer op_limit;
    integer n_load, n_store, n_nc, n_lr, n_sc_ok, n_sc_fail, n_amo, n_modeb;
    function [7:0] pattern;
        input integer a;
        begin
            pattern = (a * 37) ^ (a >> 7) ^ 8'h5A;
        end
    endfunction
    function [ADDR_W-1:0] line_of;
        input [ADDR_W-1:0] a;
        begin
            line_of = a & ~(LINE - 1);
        end
    endfunction
    function integer pidx;
        input [ADDR_W-1:0] a;
        integer t, s, b, r;
        begin
            t = a / TAG_STRIDE;
            r = a % TAG_STRIDE;
            s = r / SET_STRIDE;
            r = r % SET_STRIDE;
            b = r / LINE;
            if (t < NT && s < NS && b < NB) pidx = (t * NS + s) * NB + b;
            else                            pidx = -1;
        end
    endfunction
    function integer bank_of;
        input [ADDR_W-1:0] a;
        begin
            bank_of = (a / LINE) % NB;
        end
    endfunction
    function [ADDR_W-1:0] rand_addr;
        input        nc;
        input [1:0]  size;
        integer t, s, b, off;
        begin
            off = ({$random(seed)} % LINE) & ~((1 << size) - 1);
            if (nc) begin
                rand_addr = NC_BASE + ({$random(seed)} % NC_LINES) * LINE + off;
            end else begin
                t = {$random(seed)} % NT;
                s = {$random(seed)} % NS;
                b = {$random(seed)} % NB;
                rand_addr = t * TAG_STRIDE + s * SET_STRIDE + b * LINE + off;
            end
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
    function line_locked;
        input [ADDR_W-1:0] a;
        integer q;
        begin
            line_locked = 1'b0;
            for (q = 0; q < N_ATOM; q = q + 1)
                if (line_of(at_addr[q]) == line_of(a) &&
                    (at_st[q] == A_SCW || at_st[q] == A_ARW || at_st[q] == A_ARD || at_st[q] == A_AWW))
                    line_locked = 1'b1;
        end
    endfunction
    function line_in_atom;
        input [ADDR_W-1:0] a;
        integer q;
        begin
            line_in_atom = 1'b0;
            for (q = 0; q < N_ATOM; q = q + 1)
                if (at_st[q] != A_IDLE && line_of(at_addr[q]) == line_of(a)) line_in_atom = 1'b1;
        end
    endfunction
    function line_outstanding;
        input [ADDR_W-1:0] a;
        integer q;
        begin
            line_outstanding = 1'b0;
            for (q = 0; q < NIDX; q = q + 1)
                if (out_v[q] && !out_nc[q] && line_of(out_addr[q]) == line_of(a)) line_outstanding = 1'b1;
        end
    endfunction
    function amo_pending;
        input integer dummy;
        integer q;
        begin
            amo_pending = 1'b0;
            for (q = 0; q < N_ATOM; q = q + 1)
                if (at_st[q] == A_ARW || at_st[q] == A_ARD) amo_pending = 1'b1;
        end
    endfunction
    function atom_busy;
        input integer dummy;
        integer q;
        begin
            atom_busy = 1'b0;
            for (q = 0; q < N_ATOM; q = q + 1)
                if (at_st[q] != A_IDLE) atom_busy = 1'b1;
        end
    endfunction
    task issue;
        input [2:0]        cls;
        input              nc;
        input [1:0]        size;
        input [ADDR_W-1:0] a;
        input [WDW-1:0]    wd;
        input integer      slot;
        integer f, k, q;
        begin
            f = -1;
            for (k = NIDX - 1; k >= 0; k = k - 1) if (!out_v[k]) f = k;
            valid_cpu          = 1'b1;
            cacheable          = !nc;
            rd_wr_cpu          = (cls == C_ST || cls == C_SC || cls == C_AW);
            amo_cpu            = (cls == C_LR || cls == C_SC || cls == C_AR || cls == C_AW);
            amo_seq_cpu        = (cls == C_AR || cls == C_AW);
            amo_op_cpu         = (cls == C_AR) ? 4'd1 : 4'd0;
            mem_size_cpu       = size;
            master_id_from_cpu = 2'd0;
            idx_from_cpu       = f;
            PC_from_cpu        = a;
            data_from_cpu      = wd;
            out_v[f]    = 1'b1;
            out_cls[f]  = cls;
            out_size[f] = size;
            out_addr[f] = a;
            out_wd[f]   = wd;
            out_nc[f]   = nc;
            out_slot[f] = slot;
            out_t[f]    = cyc;
            out_exp[f]  = {WDW{1'b0}};
            case (cls)
                C_ST, C_AW: ref_write(a, size, wd);
                C_LD, C_LR: out_exp[f] = ref_read(a, size);
                C_AR: begin
                    out_exp[f] = ref_read(a, size);
                    ref_write(a, size, out_exp[f] + wd);
                end
                default: ;
            endcase
            if (cls == C_ST || cls == C_AW || cls == C_SC || cls == C_AR)
                for (q = 0; q < N_ATOM; q = q + 1)
                    if (at_st[q] == A_LRD && line_of(at_addr[q]) == line_of(a) && q != slot) at_brk[q] = 1'b1;
            issued = issued + 1;
            n_out  = n_out + 1;
            if (nc) n_nc = n_nc + 1;
            else if (cls == C_ST) n_store = n_store + 1;
            else if (cls == C_LD) n_load = n_load + 1;
        end
    endtask
    task drive_random;
        input integer pct;
        reg nc, wr;
        reg [1:0] size;
        reg [WDW-1:0] wd;
        reg [ADDR_W-1:0] a;
        integer q, room, r, tries;
        begin
            valid_cpu = 1'b0;
            amo_cpu = 1'b0;
            amo_seq_cpu = 1'b0;
            amo_op_cpu  = 4'd0;
            room = NIDX - (amo_pending(0) ? 1 : 0);
            for (q = 0; q < N_ATOM && !valid_cpu; q = q + 1) begin
                if (at_st[q] == A_LRD && n_out < room) begin
                    if (at_wait[q] > 0) at_wait[q] = at_wait[q] - 1;
                    else if (!line_outstanding(at_addr[q])) begin
                        issue(C_SC, 1'b0, 2'd3, at_addr[q], {$random(seed), $random(seed)}, q);
                        at_st[q] = A_SCW;
                    end
                end else if (at_st[q] == A_ARD && n_out < NIDX) begin
                    if (at_wait[q] > 0) at_wait[q] = at_wait[q] - 1;
                    else begin
                        issue(C_AW, 1'b0, 2'd3, at_addr[q], at_old[q] + 64'h0000_0001_0000_0003, q);
                        at_st[q] = A_AWW;
                    end
                end
            end
            if (!valid_cpu && issued < op_limit && n_out < room && ({$random(seed)} % 100) < pct) begin
                r = {$random(seed)} % 100;
                if (ATOM && r < 10) begin
                    q = -1;
                    for (i = N_ATOM - 1; i >= 0; i = i - 1) if (at_st[i] == A_IDLE) q = i;
                    a = rand_addr(1'b0, 2'd3);
                    if (q >= 0 && !line_in_atom(a) && !line_locked(a)) begin
                        at_addr[q] = a;
                        at_brk[q]  = 1'b0;
                        at_wait[q] = (({$random(seed)} % 4) == 0) ? ({$random(seed)} % 60) : ({$random(seed)} % 12);
                        if (r < 5 && !line_outstanding(a)) begin
                            issue(C_AR, 1'b0, 2'd3, a, 64'h0000_0001_0000_0003, q);
                            at_st[q] = A_ARW;
                            n_amo = n_amo + 1;
                        end else if (r >= 5) begin
                            issue(C_LR, 1'b0, 2'd3, a, {WDW{1'b0}}, q);
                            at_st[q] = A_LRW;
                            n_lr = n_lr + 1;
                        end
                    end
                end else begin
                    nc   = (({$random(seed)} % 100) < 6);
                    wr   = (({$random(seed)} % 100) < 45);
                    size = {$random(seed)} % 4;
                    wd   = {$random(seed), $random(seed)};
                    tries = 0;
                    a = rand_addr(nc, size);
                    while (!nc && line_locked(a) && tries < 4) begin
                        a = rand_addr(nc, size);
                        tries = tries + 1;
                    end
                    if (nc || !line_locked(a))
                        issue(wr ? C_ST : C_LD, nc, size, a, wd, -1);
                end
            end
        end
    endtask
    integer q2, pi2;
    always @(posedge clk) begin
        if (!rst && r_valid && read_enable_from_lsu) begin
            answered = answered + 1;
            if (!out_v[r_idx]) begin
                errors = errors + 1;
                $display("ERROR %0t: response for idx %0d which is not outstanding", $time, r_idx);
            end else begin
                if (r_rdwr !== (out_cls[r_idx] == C_ST || out_cls[r_idx] == C_SC || out_cls[r_idx] == C_AW) ||
                    r_size !== out_size[r_idx] || r_mid !== 2'd0) begin
                    errors = errors + 1;
                    $display("ERROR %0t: idx %0d wrong rd_wr/size/master_id (%0d/%0d/%0d)", $time, r_idx, r_rdwr, r_size, r_mid);
                end
                case (out_cls[r_idx])
                    C_LD, C_LR, C_AR: if (r_data !== out_exp[r_idx]) begin
                        errors = errors + 1;
                        $display("ERROR %0t: idx %0d %s @%h size %0d: got %h expected %h", $time, r_idx,
                                 out_cls[r_idx] == C_LD ? "load" : (out_cls[r_idx] == C_LR ? "LR" : "AMO read"),
                                 out_addr[r_idx], out_size[r_idx], r_data, out_exp[r_idx]);
                    end
                    C_SC: if (r_data !== 64'd0 && r_data !== 64'd1) begin
                        errors = errors + 1;
                        $display("ERROR %0t: SC idx %0d answered %h (must be 0 or 1)", $time, r_idx, r_data);
                    end
                    default: if (r_data !== 64'd0) begin
                        errors = errors + 1;
                        $display("ERROR %0t: store ack idx %0d with data %h", $time, r_idx, r_data);
                    end
                endcase
                q2 = out_slot[r_idx];
                if (q2 >= 0) begin
                    case (out_cls[r_idx])
                        C_LR: begin
                            at_st[q2] = A_LRD;
                            at_t[q2]  = cyc;
                            for (j1 = 0; j1 < N_ATOM; j1 = j1 + 1)
                                if (j1 != q2 && at_st[j1] == A_LRD && bank_of(at_addr[j1]) == bank_of(out_addr[r_idx]) &&
                                    out_t[r_idx] >= at_t[j1])
                                    at_brk[j1] = 1'b1;
                        end
                        C_SC: begin
                            if (r_data == 64'd0) begin
                                n_sc_ok = n_sc_ok + 1;
                                ref_write(out_addr[r_idx], out_size[r_idx], out_wd[r_idx]);
                                if (at_brk[q2]) begin
                                    errors = errors + 1;
                                    $display("ERROR %0t: SC @%h succeeded, but its reservation had to be broken (write, snoop or other LR/SC)",
                                             $time, out_addr[r_idx]);
                                end
                            end else begin
                                n_sc_fail = n_sc_fail + 1;
                            end
                            for (j1 = 0; j1 < N_ATOM; j1 = j1 + 1)
                                if (j1 != q2 && at_st[j1] == A_LRD && bank_of(at_addr[j1]) == bank_of(out_addr[r_idx]) &&
                                    out_t[r_idx] >= at_t[j1])
                                    at_brk[j1] = 1'b1;
                            at_st[q2] = A_IDLE;
                        end
                        C_AR: at_st[q2] = A_IDLE;
                        C_AW: at_st[q2] = A_IDLE;
                        default: ;
                    endcase
                end
                out_v[r_idx] = 1'b0;
                n_out = n_out - 1;
            end
        end
    end
    always @(posedge clk) begin
        if (!rst) begin
            if (snp_valid && snp_ready) begin
                pi2 = pidx(line_of(snp_addr));
                if (pi2 >= 0) snp_acc_t[pi2] = cyc;
            end
            if (snpr_valid && snpr_ready) begin
                pi2 = pidx(snpr_addr);
                for (j2 = 0; j2 < N_ATOM; j2 = j2 + 1) begin
                    if (at_st[j2] == A_LRD && line_of(at_addr[j2]) == snpr_addr && pi2 >= 0 &&
                        snp_acc_t[pi2] >= at_t[j2])
                        at_brk[j2] = 1'b1;
                    if (at_st[j2] == A_ARD && line_of(at_addr[j2]) == snpr_addr && pi2 >= 0 &&
                        snp_acc_t[pi2] >= at_t[j2]) begin
                        errors = errors + 1;
                        $display("ERROR %0t: snoop on line %h answered inside an AMO (sent after the AMO read's answer, before the AMO write)",
                                 $time, snpr_addr);
                    end
                end
            end
        end
    end
    reg [ADDR_W-1:0] mb_a;
    reg [WDW-1:0]    mb_v;
    always @(posedge clk) begin
        if (!rst && MODE_B && ans_valid && ans_inv && snp_en &&
            !line_outstanding(ans_line) && !line_in_atom(ans_line) && pidx(ans_line) >= 0 &&
            ({$random(seed)} % 100) < 60) begin
            mb_a = ans_line + (({$random(seed)} % (LINE / 8)) * 8);
            mb_v = {$random(seed), $random(seed)};
            for (j2 = 0; j2 < 8; j2 = j2 + 1) begin
                u_mem.mem[mb_a[MEM_BITS-1:0] + j2] = mb_v[j2*8 +: 8];
                ref_mem[mb_a[MEM_BITS-1:0] + j2]   = mb_v[j2*8 +: 8];
            end
            n_modeb = n_modeb + 1;
        end
    end
    integer fq;
    initial begin focus_v = 1'b0; focus_a = {ADDR_W{1'b0}}; end
    always @(negedge clk) begin
        focus_v = 1'b0;
        for (fq = N_ATOM - 1; fq >= 0; fq = fq - 1)
            if (at_st[fq] != A_IDLE) begin
                focus_v = 1'b1;
                focus_a = at_addr[fq];
            end
    end
    task wait_drained;
        integer t;
        begin
            t = 0;
            while ((n_out != 0 || atom_busy(0)) && t < 200000) begin
                @(negedge clk);
                drive_random(0);
                read_enable_from_lsu = (({$random(seed)} % 100) < 70);
                t = t + 1;
            end
            @(negedge clk);
            valid_cpu = 1'b0;
            read_enable_from_lsu = 1'b1;
            if (n_out != 0) begin
                errors = errors + 1;
                $display("ERROR %0t: %0d requests never answered", $time, n_out);
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
                            if (u_mem.mem[a] !== ref_mem[a]) bad = bad + 1;
                        end
            for (k = 0; k < NC_LINES * LINE; k = k + 1)
                if (u_mem.mem[NC_BASE + k] !== ref_mem[NC_BASE + k]) bad = bad + 1;
            if (bad != 0) begin
                errors = errors + 1;
                $display("ERROR: memory differs from the reference in %0d bytes after %0s", bad, when);
            end else begin
                $display("memory matches the reference after %0s", when);
            end
        end
    endtask
    task load_all;
        integer t, s, b, w;
        begin
            for (t = 0; t < NT; t = t + 1)
                for (s = 0; s < NS; s = s + 1)
                    for (b = 0; b < NB; b = b + 1)
                        for (w = 0; w < LINE / 8; w = w + 1) begin
                            @(negedge clk);
                            while (n_out >= NIDX) begin
                                valid_cpu = 1'b0;
                                @(negedge clk);
                            end
                            issue(C_LD, 1'b0, 2'd3, t * TAG_STRIDE + s * SET_STRIDE + b * LINE + w * 8, {WDW{1'b0}}, -1);
                        end
            @(negedge clk);
            valid_cpu = 1'b0;
            wait_drained;
        end
    endtask
    task snoops_off;
        integer t;
        begin
            snp_en = 1'b0;
            t = 0;
            while (!sg_idle && t < 100000) begin
                @(negedge clk);
                t = t + 1;
            end
            if (!sg_idle) begin
                errors = errors + 1;
                $display("ERROR %0t: snoops never finished", $time);
            end
        end
    endtask
    task pulse_and_wait;
        input is_flush;
        integer t;
        begin
            @(negedge clk);
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
            end else begin
                $display("%0s finished after %0d cycles", is_flush ? "flush" : "clean", t);
            end
            @(negedge clk);
        end
    endtask
    initial begin
        seed = SEED0;
        op_limit = N_OPS;
        errors = 0; issued = 0; answered = 0; n_out = 0;
        n_load = 0; n_store = 0; n_nc = 0; n_lr = 0; n_sc_ok = 0; n_sc_fail = 0; n_amo = 0; n_modeb = 0;
        for (i = 0; i < NIDX; i = i + 1) begin out_v[i] = 1'b0; out_slot[i] = -1; end
        for (i = 0; i < N_ATOM; i = i + 1) begin at_st[i] = A_IDLE; at_addr[i] = 0; at_brk[i] = 0; at_t[i] = 0; at_wait[i] = 0; end
        for (i = 0; i < NL; i = i + 1) snp_acc_t[i] = 0;
        for (i = 0; i < (1 << MEM_BITS); i = i + 1) ref_mem[i] = pattern(i);
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        snp_en = 1'b1;
        while (issued < N_OPS) begin
            @(negedge clk);
            read_enable_from_lsu = (({$random(seed)} % 100) < 75);
            drive_random(55);
        end
        @(negedge clk);
        valid_cpu = 1'b0;
        wait_drained;
        $display("random phase: %0d requests (%0d loads, %0d stores, %0d NC, %0d LR, SC %0d ok / %0d fail, %0d AMO), %0d answered",
                 issued, n_load, n_store, n_nc, n_lr, n_sc_ok, n_sc_fail, n_amo, answered);
        $display("snoops: %0d sent (%0d invalidate), answers: %0d present, %0d dirty, %0d not present; %0d cancelled; mode B writes %0d",
                 u_snp.n_sent, u_snp.n_inv, u_snp.n_present, u_snp.n_dirty, u_snp.n_absent, u_snp.n_cancel, n_modeb);
        snoops_off;
        pulse_and_wait(1'b1);
        check_memory("flush");
        load_all;
        if (mem_err)   begin errors = errors + 1; $display("ERROR: mem_err is set"); end
        if (amo_err)   begin errors = errors + 1; $display("ERROR: amo_err is set (an AMO lock timed out)"); end
        if (sg_err != 0) begin errors = errors + sg_err; $display("ERROR: snoop_gen reported %0d errors", sg_err); end
        report_coverage;
        if (errors == 0) $display("TEST PASSED: tb_l1d_coh (%0d requests, %0d snoops, mode %s, seed %0d)",
                                  issued, u_snp.n_sent, MODE_B ? "B" : "A", SEED0);
        else             $display("TEST FAILED: tb_l1d_coh (%0d errors)", errors);
        $finish;
    end
    integer ev_snp_hand, ev_snp_hit, ev_snp_vc, ev_snp_wmshr, ev_snp_wvc, ev_snp_mshr_np, ev_upg,
            ev_lock_snp, ev_lock_lsu, ev_vict_lock, ev_ins_s;
    initial begin
        ev_snp_hand = 0; ev_snp_hit = 0; ev_snp_vc = 0; ev_snp_wmshr = 0; ev_snp_wvc = 0; ev_snp_mshr_np = 0;
        ev_upg = 0; ev_lock_snp = 0; ev_lock_lsu = 0; ev_vict_lock = 0; ev_ins_s = 0;
    end
    genvar gb;
    generate
        for (gb = 0; gb < NB; gb = gb + 1) begin : g_cov
            always @(posedge clk) if (!rst) begin
                if (dut.u_dcache.g_bank[gb].u_bank.s2_snp && dut.u_dcache.g_bank[gb].u_bank.s2_snp_hit)    ev_snp_hit  = ev_snp_hit + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.s2_snp && dut.u_dcache.g_bank[gb].u_bank.s2_hand)       ev_snp_hand = ev_snp_hand + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.vc_snp)                                        ev_snp_vc   = ev_snp_vc + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.snp_act_valid && dut.u_dcache.g_bank[gb].u_bank.snp_act_code == 2'd1) ev_snp_wmshr = ev_snp_wmshr + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.snp_act_valid && dut.u_dcache.g_bank[gb].u_bank.snp_act_code == 2'd2) ev_snp_wvc   = ev_snp_wvc + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.s2_snp && !dut.u_dcache.g_bank[gb].u_bank.s2_snp_hit && dut.u_dcache.g_bank[gb].u_bank.mshr_hit &&
                    !dut.u_dcache.g_bank[gb].u_bank.mshr_hasd)                                    ev_snp_mshr_np = ev_snp_mshr_np + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.s1_lsu_th && dut.u_dcache.g_bank[gb].u_bank.m_upg)       ev_upg      = ev_upg + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.lock_snp && !dut.u_dcache.g_bank[gb].u_bank.u_fifo.u_snp.buffer_empty)  ev_lock_snp = ev_lock_snp + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.lock_valid && dut.u_dcache.g_bank[gb].u_bank.sel_valid == 1'b0 &&
                    !dut.u_dcache.g_bank[gb].u_bank.buf_empty)                                    ev_lock_lsu = ev_lock_lsu + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.s1_refill && dut.u_dcache.g_bank[gb].u_bank.v_locked)  ev_vict_lock = ev_vict_lock + 1;
                if (dut.u_dcache.g_bank[gb].u_bank.m_ev == 4'd4 && dut.u_dcache.g_bank[gb].u_bank.q1_state == 2'd1) ev_ins_s = ev_ins_s + 1;
            end
        end
    endgenerate
    task report_coverage;
        begin
            $display("events: snoop tag hits %0d (M handed over %0d), snoop on VC slot %0d, snoop waits install %0d / writeback %0d, snoop vs MSHR still fetching %0d",
                     ev_snp_hit, ev_snp_hand, ev_snp_vc, ev_snp_wmshr, ev_snp_wvc, ev_snp_mshr_np);
            $display("        S installs %0d, upgrades %0d, cycles with a snoop buffered while a lock holds snoops %0d, refill victim moved off the locked line %0d",
                     ev_ins_s, ev_upg, ev_lock_snp, ev_vict_lock);
            if (ev_snp_hit == 0 || ev_snp_hand == 0 || ev_snp_vc == 0 || u_snp.n_absent == 0 ||
                (SHARED_PCT > 0 && ev_upg == 0) ||
                (ATOM && (n_sc_ok == 0 || n_sc_fail == 0 || n_amo == 0)) ||
                (MODE_B && n_modeb == 0)) begin
                errors = errors + 1;
                $display("ERROR: a required event never happened (see the counts above)");
            end
        end
    endtask
    initial cyc = 0;
    always @(negedge clk) cyc = cyc + 1;
    initial begin
        cycles = 0;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            if (cycles > 3000000) begin
                $display("TEST FAILED: tb_l1d_coh (timeout, %0d requests outstanding)", n_out);
                $finish;
            end
        end
    end
endmodule
