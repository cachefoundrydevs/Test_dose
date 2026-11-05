`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_l1d_random;
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
    localparam SHARED_PCT = 0;
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
    localparam SET_STRIDE = NB * LINE;
    localparam TAG_STRIDE = NB * SETS * LINE;
    localparam NT         = WAYS + VCS + 3;
    localparam NS         = 2;
    localparam NC_BASE    = 32'h0008_0000;
    localparam NC_LINES   = 4;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    reg                 flush = 0, clean = 0;
    wire                flush_complete, clean_complete, mem_err;
    wire                stop;
    reg                 valid_cpu = 0, cacheable = 1, rd_wr_cpu = 0;
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
    wire [AXI_IDW-1:0]  awid, arid, bid, rid;
    wire [AXI_AW-1:0]   awaddr, araddr;
    wire [7:0]          awlen, arlen;
    wire [2:0]          awsize, arsize, awprot, arprot;
    wire [1:0]          awburst, arburst, bresp, rresp;
    wire [3:0]          awcache, arcache;
    wire                awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire                arvalid, arready, rvalid, rready, rlast, aruser, ruser;
    wire                snpr_valid, amo_err;
    wire [AXI_DW-1:0]   wdata, rdata;
    wire [AXI_DW/8-1:0] wstrb;
    l1d_top_axi #(
        .SETS(SETS), .WAYS(WAYS), .LSU_BUF_DEPTH(LSU_BUF), .MSHR_ENTRIES(MSHR),
        .MSHR_NC_ENTRIES(NCE), .VC_SLOTS(VCS), .RESP_FIFO_DEPTH(RFIFO), .AXI_ID_W(AXI_IDW)
    ) dut (
        .clk(clk), .rst(rst),
        .flush_request(flush), .clean_request(clean), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .cpu_request_valid(valid_cpu), .cpu_request_cacheable(cacheable), .cpu_request_is_write(rd_wr_cpu), .cpu_request_size(mem_size_cpu),
        .cpu_request_master_id(master_id_from_cpu), .cpu_request_rob_index(idx_from_cpu),
        .cpu_request_addr(PC_from_cpu), .cpu_request_store_data(data_from_cpu),
        .cpu_request_is_atomic(1'b0), .cpu_request_atomic_is_amo(1'b0), .cpu_request_amo_op(4'd0),
        .input_queue_full(stop),
        .snoop_request_valid(1'b0), .snoop_request_ready(), .snoop_request_addr({ADDR_W{1'b0}}), .snoop_request_invalidate(1'b0),
        .snoop_response_valid(snpr_valid), .snoop_response_ready(1'b1), .snoop_response_addr(), .snoop_response_present(), .snoop_response_dirty(), .snoop_response_data(),
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
        .m_axi_ruser(ruser), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );
    axi_mem_model #(.ID_W(AXI_IDW), .ADDR_W(AXI_AW), .DATA_W(AXI_DW), .MEM_BITS(MEM_BITS),
                    .LAT(8), .READY_PCT(70), .SEED(SEED0 + 7), .SHARED_PCT(SHARED_PCT),
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
    reg [7:0]     ref_mem [0:(1<<MEM_BITS)-1];
    reg           out_v    [0:NIDX-1];
    reg           out_wr   [0:NIDX-1];
    reg [1:0]     out_size [0:NIDX-1];
    reg [WDW-1:0] out_exp  [0:NIDX-1];
    reg [ADDR_W-1:0] out_addr [0:NIDX-1];
    integer seed, i, errors, issued, answered, n_out, cycles;
    integer op_limit;
    integer n_load, n_store, n_nc;
    function [7:0] pattern;
        input integer a;
        begin
            pattern = (a * 37) ^ (a >> 7) ^ 8'h5A;
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
    task issue;
        input        nc;
        input        wr;
        input [1:0]  size;
        input [ADDR_W-1:0] a;
        input [WDW-1:0]    wd;
        integer f, k;
        begin
            f = -1;
            for (k = NIDX - 1; k >= 0; k = k - 1) if (!out_v[k]) f = k;
            valid_cpu          = 1'b1;
            cacheable          = !nc;
            rd_wr_cpu          = wr;
            mem_size_cpu       = size;
            master_id_from_cpu = 2'd0;
            idx_from_cpu       = f;
            PC_from_cpu        = a;
            data_from_cpu      = wd;
            out_v[f]    = 1'b1;
            out_wr[f]   = wr;
            out_size[f] = size;
            out_addr[f] = a;
            if (wr) begin
                for (k = 0; k < (1 << size); k = k + 1)
                    ref_mem[a[MEM_BITS-1:0] + k] = wd[k*8 +: 8];
                out_exp[f] = {WDW{1'b0}};
            end else begin
                out_exp[f] = ref_read(a, size);
            end
            issued = issued + 1;
            n_out  = n_out + 1;
            if (nc) n_nc = n_nc + 1; else if (wr) n_store = n_store + 1; else n_load = n_load + 1;
        end
    endtask
    task drive_random;
        input integer pct;
        reg nc, wr;
        reg [1:0] size;
        reg [WDW-1:0] wd;
        begin
            valid_cpu = 1'b0;
            if (issued < op_limit && n_out < NIDX && !stop && ({$random(seed)} % 100) < pct) begin
                nc   = (({$random(seed)} % 100) < 8);
                wr   = (({$random(seed)} % 100) < 45);
                size = {$random(seed)} % 4;
                wd   = {$random(seed), $random(seed)};
                issue(nc, wr, size, rand_addr(nc, size), wd);
            end
        end
    endtask
    reg [WDW-1:0] mask;
    integer m;
    always @(posedge clk) begin
        if (!rst && r_valid && read_enable_from_lsu) begin
            answered = answered + 1;
            if (!out_v[r_idx]) begin
                errors = errors + 1;
                $display("ERROR %0t: response for idx %0d which is not outstanding", $time, r_idx);
            end else begin
                if (r_rdwr !== out_wr[r_idx] || r_size !== out_size[r_idx] || r_mid !== 2'd0) begin
                    errors = errors + 1;
                    $display("ERROR %0t: idx %0d wrong rd_wr/size/master_id (%0d/%0d/%0d)", $time, r_idx, r_rdwr, r_size, r_mid);
                end
                if (!out_wr[r_idx] && r_data !== out_exp[r_idx]) begin
                    errors = errors + 1;
                    $display("ERROR %0t: idx %0d load @%h size %0d: got %h expected %h", $time, r_idx,
                             out_addr[r_idx], out_size[r_idx], r_data, out_exp[r_idx]);
                end
                out_v[r_idx] = 1'b0;
                n_out = n_out - 1;
            end
        end
    end
    task wait_drained;
        integer t;
        begin
            t = 0;
            while (n_out != 0 && t < 200000) begin
                @(negedge clk);
                valid_cpu = 1'b0;
                read_enable_from_lsu = (({$random(seed)} % 100) < 70);
                t = t + 1;
            end
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
                            while (n_out >= NIDX || stop) begin
                                valid_cpu = 1'b0;
                                @(negedge clk);
                            end
                            issue(1'b0, 1'b0, 2'd3, t * TAG_STRIDE + s * SET_STRIDE + b * LINE + w * 8, {WDW{1'b0}});
                        end
            @(negedge clk);
            valid_cpu = 1'b0;
            wait_drained;
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
        n_load = 0; n_store = 0; n_nc = 0;
        for (i = 0; i < NIDX; i = i + 1) out_v[i] = 1'b0;
        for (i = 0; i < (1 << MEM_BITS); i = i + 1) ref_mem[i] = pattern(i);
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk); issue(1'b0, 1'b1, 2'd3, 64'h40, 64'h1122_3344_5566_7788);
        @(negedge clk); issue(1'b0, 1'b0, 2'd3, 64'h40, 0);
        @(negedge clk); issue(1'b0, 1'b0, 2'd0, 64'h43, 0);
        @(negedge clk); issue(1'b0, 1'b0, 2'd1, 64'h46, 0);
        @(negedge clk); valid_cpu = 1'b0;
        wait_drained;
        while (issued < N_OPS) begin
            @(negedge clk);
            read_enable_from_lsu = (({$random(seed)} % 100) < 75);
            drive_random(60);
        end
        @(negedge clk);
        valid_cpu = 1'b0;
        wait_drained;
        $display("random phase: %0d requests (%0d loads, %0d stores, %0d non-cacheable), %0d answered",
                 issued, n_load, n_store, n_nc, answered);
        pulse_and_wait(1'b0);
        check_memory("clean");
        load_all;
        op_limit = issued + 600;
        while (issued < op_limit) begin
            @(negedge clk);
            drive_random(60);
        end
        @(negedge clk);
        valid_cpu = 1'b0;
        wait_drained;
        pulse_and_wait(1'b1);
        check_memory("flush");
        load_all;
        if (mem_err) begin
            errors = errors + 1;
            $display("ERROR: mem_err is set");
        end
        if (amo_err || snpr_valid) begin
            errors = errors + 1;
            $display("ERROR: amo_err or snpr_valid is set without atomics / snoops");
        end
        report_coverage;
        if (errors == 0) $display("TEST PASSED: tb_l1d_random (%0d requests, seed %0d)", issued, SEED0);
        else             $display("TEST FAILED: tb_l1d_random (%0d errors)", errors);
        $finish;
    end
    integer ev_hit, ev_miss, ev_vc_load, ev_swap, ev_wb, ev_wmshr, ev_wany, ev_wvc, ev_held, ev_nc;
    integer ev_upg, ev_ins_s;
    initial begin
        ev_hit = 0; ev_miss = 0; ev_vc_load = 0; ev_swap = 0; ev_wb = 0;
        ev_wmshr = 0; ev_wany = 0; ev_wvc = 0; ev_held = 0; ev_nc = 0;
        ev_upg = 0; ev_ins_s = 0;
    end
    genvar gb;
    generate
        for (gb = 0; gb < NB; gb = gb + 1) begin : g_cov
            always @(posedge clk) if (!rst) begin
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.s2_lsu && dut.u_ports.u_dcache.g_bank[gb].u_bank.s2_hit)        ev_hit     = ev_hit + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.m_alloc && !dut.u_ports.u_dcache.g_bank[gb].u_bank.m_swap)      ev_miss    = ev_miss + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.s3_load && dut.u_ports.u_dcache.g_bank[gb].u_bank.s3_from_vc)   ev_vc_load = ev_vc_load + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.vc_swap)                                       ev_swap    = ev_swap + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.vc_wr_valid && dut.u_ports.u_dcache.g_bank[gb].u_bank.vc_wr_ready) ev_wb   = ev_wb + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.act_valid && dut.u_ports.u_dcache.g_bank[gb].u_bank.act_code == 3'd1) ev_wmshr = ev_wmshr + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.act_valid && dut.u_ports.u_dcache.g_bank[gb].u_bank.act_code == 3'd2) ev_wany  = ev_wany + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.act_valid && dut.u_ports.u_dcache.g_bank[gb].u_bank.act_code == 3'd3) ev_wvc   = ev_wvc + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.r_held)                                        ev_held    = ev_held + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.n_alloc)                                       ev_nc      = ev_nc + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.s1_lsu_th && dut.u_ports.u_dcache.g_bank[gb].u_bank.m_upg)       ev_upg     = ev_upg + 1;
                if (dut.u_ports.u_dcache.g_bank[gb].u_bank.m_ev == 4'd4 && dut.u_ports.u_dcache.g_bank[gb].u_bank.q1_state == 2'd1) ev_ins_s = ev_ins_s + 1;
            end
        end
    endgenerate
    task report_coverage;
        begin
            $display("events: hits %0d, line fetches %0d, victim-cache load hits %0d, swaps %0d, writebacks %0d",
                     ev_hit, ev_miss, ev_vc_load, ev_swap, ev_wb);
            $display("        wait-for-MSHR %0d, MSHR full %0d, wait-for-writeback %0d, refill held %0d, NC accesses %0d",
                     ev_wmshr, ev_wany, ev_wvc, ev_held, ev_nc);
            $display("        v2: lines installed S %0d, S-to-M upgrades %0d", ev_ins_s, ev_upg);
            if (ev_hit == 0 || ev_miss == 0 || ev_vc_load == 0 || ev_swap == 0 || ev_wb == 0 ||
                ev_wmshr == 0 || ev_nc == 0 || (LSU_BUF > MSHR && ev_wany == 0) ||
                (SHARED_PCT > 0 && (ev_ins_s == 0 || ev_upg == 0))) begin
                errors = errors + 1;
                $display("ERROR: a required event never happened (see the counts above)");
            end
        end
    endtask
    initial begin
        cycles = 0;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            if (cycles > 3000000) begin
                $display("TEST FAILED: tb_l1d_random (timeout, %0d requests outstanding)", n_out);
                $finish;
            end
        end
    end
endmodule
