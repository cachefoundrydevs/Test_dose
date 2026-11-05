`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_ports;
`ifdef TINY
    localparam SETS = 4, WAYS = 2, LSU_BUF = 4, MSHR = 2, NCE = 1, VCS = 2, RFIFO = 2;
    localparam TIMING_CHECKS = 0;
`else
    localparam SETS = `L1D_SETS, WAYS = `L1D_WAYS, LSU_BUF = `L1D_LSU_BUF_DEPTH,
               MSHR = `L1D_MSHR_ENTRIES, NCE = `L1D_MSHR_NC_ENTRIES, VCS = `L1D_VC_SLOTS,
               RFIFO = `L1D_RESP_FIFO_DEPTH;
    localparam TIMING_CHECKS = 1;
`endif
`ifdef NOPS
    localparam N_OPS = `NOPS;
`else
    localparam N_OPS = 6000;
`endif
`ifdef SEED
    localparam SEED0 = `SEED;
`else
    localparam SEED0 = 1;
`endif
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
    localparam [2:0] K_LD = 3'd0, K_ST = 3'd1, K_LR = 3'd2, K_SC = 3'd3;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;
    reg                         flush = 0, clean = 0;
    wire                        flush_complete, clean_complete, mem_err, amo_err, snpr_valid;
    reg  [PORTS-1:0]            req_valid = 0, req_cacheable = 0, req_is_write = 0, req_atomic = 0;
    reg  [PORTS*2-1:0]          req_size = 0;
    reg  [PORTS*IDX_BITS-1:0]   req_idx = 0;
    reg  [PORTS*ADDR_W-1:0]     req_addr = 0;
    reg  [PORTS*WDW-1:0]        req_data = 0;
    reg  [PORTS-1:0]            read_enable = {PORTS{1'b1}};
    wire [PORTS-1:0]            port_stop;
    wire [PORTS-1:0]            rsp_valid, rsp_is_write_ack;
    wire [PORTS*2-1:0]          rsp_size, rsp_mid;
    wire [PORTS*IDX_BITS-1:0]   rsp_idx;
    wire [PORTS*WDW-1:0]        rsp_data;
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
    l1d_top_axi_ports #(
        .SETS(SETS), .WAYS(WAYS), .LSU_BUF_DEPTH(LSU_BUF), .MSHR_ENTRIES(MSHR),
        .MSHR_NC_ENTRIES(NCE), .VC_SLOTS(VCS), .RESP_FIFO_DEPTH(RFIFO), .AXI_ID_W(AXI_IDW)
    ) dut (
        .clk(clk), .rst(rst),
        .flush_request(flush), .clean_request(clean), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .cpu_request_valid(req_valid), .cpu_request_cacheable(req_cacheable), .cpu_request_is_write(req_is_write),
        .cpu_request_size(req_size), .cpu_request_master_id({(PORTS*2){1'b0}}), .cpu_request_rob_index(req_idx),
        .cpu_request_addr(req_addr), .cpu_request_store_data(req_data),
        .cpu_request_is_atomic(req_atomic), .cpu_request_atomic_is_amo({PORTS{1'b0}}), .cpu_request_amo_op({(PORTS*4){1'b0}}),
        .input_queue_full(port_stop),
        .lsu_response_read_enable(read_enable), .lsu_response_valid(rsp_valid), .lsu_response_is_write_ack(rsp_is_write_ack),
        .lsu_response_size(rsp_size), .lsu_response_master_id(rsp_mid), .lsu_response_rob_index(rsp_idx),
        .lsu_response_data(rsp_data),
        .snoop_request_valid(1'b0), .snoop_request_ready(), .snoop_request_addr({ADDR_W{1'b0}}), .snoop_request_invalidate(1'b0),
        .snoop_response_valid(snpr_valid), .snoop_response_ready(1'b1), .snoop_response_addr(), .snoop_response_present(),
        .snoop_response_dirty(), .snoop_response_data(),
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
        .rd_pend_valid(), .rd_pend_addr()
    );
    axi_mem_model #(.ID_W(AXI_IDW), .ADDR_W(AXI_AW), .DATA_W(AXI_DW), .MEM_BITS(MEM_BITS),
                    .LAT(8), .READY_PCT(70), .SEED(SEED0 + 7), .SHARED_PCT(0),
                    .LINE_BYTES(LINE), .HOLD_N(1)) u_mem (
        .clk(clk), .rst(rst),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize), .aruser(aruser), .sh_mode(2'd0),
        .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .ruser(ruser), .rvalid(rvalid), .rready(rready),
        .hold_v(1'b0), .hold_a({AXI_AW{1'b0}}), .r_busy(), .r_line(),
        .bd_valid(1'b0), .bd_addr({AXI_AW{1'b0}}), .bd_data({(LINE*8){1'b0}}),
        .rdone_valid(), .rdone_line(), .rdone_unique()
    );
    reg [7:0]        ref_mem  [0:(1<<MEM_BITS)-1];
    reg              out_v    [0:NOUT-1];
    reg [2:0]        out_kind [0:NOUT-1];
    reg [1:0]        out_size [0:NOUT-1];
    reg [WDW-1:0]    out_exp  [0:NOUT-1];
    reg [ADDR_W-1:0] out_addr [0:NOUT-1];
    integer          out_t    [0:NOUT-1];
    integer          got_t    [0:NOUT-1];
    reg [WDW-1:0]    got_d    [0:NOUT-1];
    integer          n_out    [0:PORTS-1];
    integer seed, i, p, errors, issued, answered, total_out, cycles;
    integer op_limit;
    integer n_load, n_store, n_nc;
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
    function [ADDR_W-1:0] rand_addr;
        input        nc;
        input [1:0]  size;
        integer      off;
        begin
            off = ({$random(seed)} % LINE) & ~((1 << size) - 1);
            if (nc) rand_addr = NC_BASE + ({$random(seed)} % NC_LINES) * LINE + off;
            else    rand_addr = line_addr({$random(seed)} % NT, {$random(seed)} % NS, {$random(seed)} % NB) + off;
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
    task send;
        input integer      pt;
        input [2:0]        kind;
        input              nc;
        input [1:0]        size;
        input [ADDR_W-1:0] a;
        input [WDW-1:0]    wd;
        output integer     entry;
        integer f, k;
        begin
            f = -1;
            for (k = NIDX - 1; k >= 0; k = k - 1) if (!out_v[pt*NIDX + k]) f = k;
            if (f < 0) begin
                errors = errors + 1;
                $display("ERROR %0t: tb_ports: no free index on port %0d", $time, pt);
                f = 0;
            end
            if (port_stop[pt]) begin
                errors = errors + 1;
                $display("ERROR %0t: tb_ports: send on port %0d while its stop is 1", $time, pt);
            end
            entry = pt * NIDX + f;
            req_valid[pt]                     = 1'b1;
            req_cacheable[pt]                 = !nc;
            req_is_write[pt]                  = (kind == K_ST) || (kind == K_SC);
            req_atomic[pt]                    = (kind == K_LR) || (kind == K_SC);
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
            if (kind == K_ST) begin
                ref_write(a, size, wd);
                out_exp[entry] = {WDW{1'b0}};
            end else if (kind == K_SC) begin
                out_exp[entry] = {WDW{1'b0}};
            end else begin
                out_exp[entry] = ref_read(a, size);
            end
            n_out[pt] = n_out[pt] + 1;
            total_out = total_out + 1;
            issued    = issued + 1;
        end
    endtask
    task idle;
        begin
            @(negedge clk);
            req_valid = {PORTS{1'b0}};
        end
    endtask
    task wait_entry;
        input integer entry;
        integer t;
        begin
            t = 0;
            while (got_t[entry] < 0 && t < 20000) begin idle; t = t + 1; end
            if (got_t[entry] < 0) begin
                errors = errors + 1;
                $display("ERROR %0t: tb_ports: entry %0d (port %0d idx %0d) never answered", $time, entry, entry / NIDX, entry % NIDX);
            end
        end
    endtask
    task wait_drained;
        input random_read_enable;
        integer t;
        begin
            t = 0;
            while (total_out != 0 && t < 400000) begin
                @(negedge clk);
                req_valid = {PORTS{1'b0}};
                for (p = 0; p < PORTS; p = p + 1)
                    read_enable[p] = random_read_enable ? (({$random(seed)} % 100) < 70) : 1'b1;
                t = t + 1;
            end
            read_enable = {PORTS{1'b1}};
            if (total_out != 0) begin
                errors = errors + 1;
                $display("ERROR %0t: tb_ports: %0d requests never answered", $time, total_out);
            end
        end
    endtask
    integer chk_port, chk_entry;
    always @(posedge clk) begin
        if (!rst) begin
            for (chk_port = 0; chk_port < PORTS; chk_port = chk_port + 1) begin
                if (rsp_valid[chk_port] && read_enable[chk_port]) begin
                    chk_entry = chk_port * NIDX + rsp_idx[chk_port*IDX_BITS +: IDX_BITS];
                    answered = answered + 1;
                    if (!out_v[chk_entry]) begin
                        errors = errors + 1;
                        $display("ERROR %0t: port %0d answer for idx %0d which is not outstanding", $time, chk_port,
                                 rsp_idx[chk_port*IDX_BITS +: IDX_BITS]);
                    end else begin
                        if (rsp_is_write_ack[chk_port] !== ((out_kind[chk_entry] == K_ST) || (out_kind[chk_entry] == K_SC)) ||
                            rsp_size[chk_port*2 +: 2] !== out_size[chk_entry] || rsp_mid[chk_port*2 +: 2] !== 2'd0) begin
                            errors = errors + 1;
                            $display("ERROR %0t: port %0d idx %0d wrong write_ack / size / master id", $time, chk_port,
                                     rsp_idx[chk_port*IDX_BITS +: IDX_BITS]);
                        end
                        if ((out_kind[chk_entry] == K_LD || out_kind[chk_entry] == K_LR) &&
                            rsp_data[chk_port*WDW +: WDW] !== out_exp[chk_entry]) begin
                            errors = errors + 1;
                            $display("ERROR %0t: port %0d idx %0d load @%h size %0d: got %h expected %h", $time, chk_port,
                                     rsp_idx[chk_port*IDX_BITS +: IDX_BITS], out_addr[chk_entry], out_size[chk_entry],
                                     rsp_data[chk_port*WDW +: WDW], out_exp[chk_entry]);
                        end
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
        input        ok;
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
    integer e0, e1, e2, e3, lat0, lat1, lat2, lat3, lat_min, lat_max, lat_sum;
    task timing_part;
        integer b;
        begin
            $display("=== timing: four ports at once ===");
            for (b = 0; b < NB; b = b + 1) begin
                @(negedge clk); send(0, K_LD, 1'b0, 2'd3, line_addr(0, 0, b), 0, e0); idle; wait_entry(e0);
            end
            repeat (10) idle;
            for (p = 0; p < PORTS; p = p + 1) begin
                @(negedge clk); send(p, K_LD, 1'b0, 2'd3, line_addr(0, 0, p % NB) + 8, 0, e0); idle; wait_entry(e0);
                check(got_t[e0] - out_t[e0] == 4, "a load hit on one port alone answers in 4 cycles");
                repeat (6) idle;
            end
            @(negedge clk);
            send(0, K_LD, 1'b0, 2'd3, line_addr(0, 0, 0) + 16, 0, e0);
            send(1, K_LD, 1'b0, 2'd3, line_addr(0, 0, 1) + 16, 0, e1);
            send(2, K_LD, 1'b0, 2'd3, line_addr(0, 0, 2) + 16, 0, e2);
            send(3, K_LD, 1'b0, 2'd3, line_addr(0, 0, 3) + 16, 0, e3);
            idle; wait_entry(e0); wait_entry(e1); wait_entry(e2); wait_entry(e3);
            lat0 = got_t[e0] - out_t[e0]; lat1 = got_t[e1] - out_t[e1]; lat2 = got_t[e2] - out_t[e2]; lat3 = got_t[e3] - out_t[e3];
            $display("  CC-1 latencies: P0 %0d, P1 %0d, P2 %0d, P3 %0d", lat0, lat1, lat2, lat3);
            check(lat0 == 4 && lat1 == 4 && lat2 == 4 && lat3 == 4, "CC-1: four hits to four banks in one cycle: all four in 4 cycles");
            repeat (6) idle;
            @(negedge clk);
            send(0, K_LD, 1'b0, 2'd3, line_addr(0, 0, 1) + 24, 0, e0);
            send(1, K_LD, 1'b0, 2'd3, line_addr(0, 0, 1) + 32, 0, e1);
            send(2, K_LD, 1'b0, 2'd3, line_addr(0, 0, 1) + 40, 0, e2);
            send(3, K_LD, 1'b0, 2'd3, line_addr(0, 0, 1) + 48, 0, e3);
            idle; wait_entry(e0); wait_entry(e1); wait_entry(e2); wait_entry(e3);
            lat0 = got_t[e0] - out_t[e0]; lat1 = got_t[e1] - out_t[e1]; lat2 = got_t[e2] - out_t[e2]; lat3 = got_t[e3] - out_t[e3];
            $display("  CC-2 latencies: P0 %0d, P1 %0d, P2 %0d, P3 %0d", lat0, lat1, lat2, lat3);
            lat_min = lat0; lat_max = lat0; lat_sum = lat0 + lat1 + lat2 + lat3;
            if (lat1 < lat_min) lat_min = lat1; if (lat2 < lat_min) lat_min = lat2; if (lat3 < lat_min) lat_min = lat3;
            if (lat1 > lat_max) lat_max = lat1; if (lat2 > lat_max) lat_max = lat2; if (lat3 > lat_max) lat_max = lat3;
            check(lat_min == 4 && lat_max == 7 && lat_sum == 22, "CC-2: four hits to one bank in one cycle: 4, 5, 6, 7 cycles");
            check(lat0 == 4 && lat1 == 5 && lat2 == 6 && lat3 == 7, "CC-2: in port order P0, P1, P2, P3 (same cycle)");
            repeat (6) idle;
        end
    endtask
    task lrsc_part;
        reg [ADDR_W-1:0] line_a, line_b;
        begin
            $display("=== LR / SC across ports (one global reservation) ===");
            line_a = line_addr(1, 1, 1);
            line_b = line_addr(1, 1, 2);
            @(negedge clk); send(0, K_LR, 1'b0, 2'd3, line_a, 0, e0); idle; wait_entry(e0);
            @(negedge clk); send(2, K_SC, 1'b0, 2'd3, line_a, 64'h0A0A_0001, e1); idle; wait_entry(e1);
            check(got_d[e1] == 64'd0, "LR on P0, SC on P2 to the same line: success");
            if (got_d[e1] == 64'd0) ref_write(line_a, 2'd3, 64'h0A0A_0001);
            @(negedge clk); send(1, K_LD, 1'b0, 2'd3, line_a, 0, e2); idle; wait_entry(e2);
            @(negedge clk); send(0, K_LR, 1'b0, 2'd3, line_a, 0, e0); idle; wait_entry(e0);
            @(negedge clk); send(1, K_LR, 1'b0, 2'd3, line_b, 0, e1); idle; wait_entry(e1);
            @(negedge clk); send(2, K_SC, 1'b0, 2'd3, line_a, 64'h0A0A_0002, e2); idle; wait_entry(e2);
            check(got_d[e2] == 64'd1, "CC-9: LR A (bank 1, P0), LR B (bank 2, P1), SC A (P2) fails");
            @(negedge clk); send(2, K_SC, 1'b0, 2'd3, line_b, 64'h0B0B_0002, e3); idle; wait_entry(e3);
            check(got_d[e3] == 64'd1, "the failed SC ended the reservation: SC B fails too");
            @(negedge clk); send(1, K_LR, 1'b0, 2'd3, line_b, 0, e0); idle; wait_entry(e0);
            @(negedge clk); send(2, K_SC, 1'b0, 2'd3, line_b, 64'h0B0B_0003, e1); idle; wait_entry(e1);
            check(got_d[e1] == 64'd0, "LR on P1 to bank 2, SC on P2: success");
            if (got_d[e1] == 64'd0) ref_write(line_b, 2'd3, 64'h0B0B_0003);
            @(negedge clk); send(0, K_LR, 1'b0, 2'd3, line_a, 0, e0); idle; wait_entry(e0);
            @(negedge clk); send(1, K_ST, 1'b0, 2'd2, line_a + 4, 64'h7777_7777, e1); idle; wait_entry(e1);
            @(negedge clk); send(2, K_SC, 1'b0, 2'd3, line_a, 64'h0A0A_0004, e2); idle; wait_entry(e2);
            check(got_d[e2] == 64'd1, "LR on P0, store on P1 to the line, SC on P2: fail");
            @(negedge clk); send(3, K_LD, 1'b0, 2'd3, line_a, 0, e0); send(0, K_LD, 1'b0, 2'd3, line_b, 0, e1); idle;
            wait_entry(e0); wait_entry(e1);
            repeat (6) idle;
        end
    endtask
    reg [ADDR_W-1:0] cycle_line [0:PORTS-1];
    reg              cycle_wr   [0:PORTS-1];
    integer          cycle_n;
    task drive_random;
        input integer pct;
        reg               nc, wr, clash;
        reg [1:0]         size;
        reg [WDW-1:0]     wd;
        reg [ADDR_W-1:0]  a;
        integer           q, ent;
        begin
            req_valid = {PORTS{1'b0}};
            cycle_n = 0;
            for (p = 0; p < PORTS; p = p + 1) begin
                if (issued < op_limit && n_out[p] < NIDX && !port_stop[p] && ({$random(seed)} % 100) < pct) begin
                    nc   = (({$random(seed)} % 100) < 6);
                    wr   = (({$random(seed)} % 100) < ((p == 2) ? 75 : (p == 3) ? 40 : 20));
                    size = {$random(seed)} % 4;
                    wd   = {$random(seed), $random(seed)};
                    a    = rand_addr(nc, size);
                    clash = 1'b0;
                    for (q = 0; q < cycle_n; q = q + 1)
                        if (cycle_line[q] == {a[ADDR_W-1:6], 6'd0} && (wr || cycle_wr[q])) clash = 1'b1;
                    if (!clash) begin
                        send(p, wr ? K_ST : K_LD, nc, size, a, wd, ent);
                        cycle_line[cycle_n] = {a[ADDR_W-1:6], 6'd0};
                        cycle_wr[cycle_n]   = wr;
                        cycle_n = cycle_n + 1;
                        if (nc) n_nc = n_nc + 1; else if (wr) n_store = n_store + 1; else n_load = n_load + 1;
                    end
                end
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
            end
            @(negedge clk);
        end
    endtask
    integer ev_multi_seat, ev_from_line, ev_multi_answer, ev_stop;
    integer cov_b, cov_n;
    initial begin ev_multi_seat = 0; ev_from_line = 0; ev_multi_answer = 0; ev_stop = 0; end
    always @(posedge clk) if (!rst) begin
        cov_n = 0;
        for (cov_b = 0; cov_b < NB; cov_b = cov_b + 1)
            if (dut.u_dcache.bk_req_valid[cov_b] && dut.u_dcache.bk_req_ready[cov_b]) cov_n = cov_n + 1;
        if (cov_n >= 2) ev_multi_seat = ev_multi_seat + 1;
        cov_n = 0;
        for (cov_b = 0; cov_b < PORTS; cov_b = cov_b + 1)
            if (rsp_valid[cov_b] && read_enable[cov_b]) cov_n = cov_n + 1;
        if (cov_n >= 2) ev_multi_answer = ev_multi_answer + 1;
        if (|port_stop) ev_stop = ev_stop + 1;
    end
    genvar gb;
    generate
        for (gb = 0; gb < NB; gb = gb + 1) begin : g_cov
            always @(posedge clk) if (!rst) begin
                if (!dut.u_dcache.u_front.g_bank[gb].u_queue.all_lines_empty && dut.u_dcache.u_front.g_bank[gb].u_queue.bank_takes_offer)
                    ev_from_line = ev_from_line + 1;
            end
        end
    endgenerate
    initial begin
        seed = SEED0;
        op_limit = 0;
        errors = 0; issued = 0; answered = 0; total_out = 0;
        n_load = 0; n_store = 0; n_nc = 0;
        for (i = 0; i < NOUT; i = i + 1) begin out_v[i] = 1'b0; got_t[i] = -1; end
        for (p = 0; p < PORTS; p = p + 1) n_out[p] = 0;
        for (i = 0; i < (1 << MEM_BITS); i = i + 1) ref_mem[i] = pattern(i);
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (20) idle;
        op_limit = 1000000;
        if (TIMING_CHECKS != 0) timing_part;
        lrsc_part;
        wait_drained(1'b0);
        op_limit = issued + N_OPS;
        while (issued < op_limit) begin
            @(negedge clk);
            for (p = 0; p < PORTS; p = p + 1) read_enable[p] = (({$random(seed)} % 100) < 80);
            drive_random(55);
        end
        @(negedge clk);
        req_valid = {PORTS{1'b0}};
        wait_drained(1'b1);
        $display("random part: %0d requests in all (%0d loads, %0d stores, %0d NC in the random part), %0d answered",
                 issued, n_load, n_store, n_nc, answered);
        pulse_and_wait(1'b0);
        check_memory("clean");
        op_limit = issued + 800;
        while (issued < op_limit) begin
            @(negedge clk);
            drive_random(55);
        end
        @(negedge clk);
        req_valid = {PORTS{1'b0}};
        wait_drained(1'b0);
        pulse_and_wait(1'b1);
        check_memory("flush");
        if (mem_err)   begin errors = errors + 1; $display("ERROR: mem_err is set"); end
        if (amo_err)   begin errors = errors + 1; $display("ERROR: amo_err is set"); end
        if (snpr_valid) begin errors = errors + 1; $display("ERROR: a snoop answer without a snoop"); end
        $display("events: cycles with 2+ banks seating %0d, seated from a waiting line %0d, cycles with 2+ ports answering %0d, stop cycles %0d",
                 ev_multi_seat, ev_from_line, ev_multi_answer, ev_stop);
        if (ev_multi_seat == 0 || ev_from_line == 0 || ev_multi_answer == 0) begin
            errors = errors + 1;
            $display("ERROR: a required 4-port event never happened (see the counts above)");
        end
        if (errors == 0) $display("TEST PASSED: tb_ports (%0d requests, seed %0d)", issued, SEED0);
        else             $display("TEST FAILED: tb_ports (%0d errors)", errors);
        $finish;
    end
    initial begin
        cycles = 0;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            if (cycles > 4000000) begin
                $display("TEST FAILED: tb_ports (timeout, %0d requests outstanding)", total_out);
                $finish;
            end
        end
    end
endmodule
