`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_latency;
`ifdef RLAT
    localparam RLAT = `RLAT;
`else
    localparam RLAT = 10;
`endif
`ifdef BLAT
    localparam BLAT = `BLAT;
`else
    localparam BLAT = 6;
`endif
    localparam ADDR_W   = `L1D_ADDR_W;
    localparam WDW      = `L1D_WRITE_DATA_WIDTH;
    localparam IDX_BITS = `L1D_IDX_BITS;
    localparam NB       = `L1D_NUM_BANKS;
    localparam LINE     = `L1D_LINE_BYTES;
    localparam SETS     = `L1D_SETS;
    localparam VCS      = `L1D_VC_SLOTS;
    localparam AXI_DW   = `L1D_AXI_DATA_W;
    localparam AXI_AW   = `L1D_AXI_ADDR_W;
    localparam AXI_IDW  = 6;
    localparam BEATS    = LINE * 8 / AXI_DW;
    localparam PKT_LINE_EXTRA = 2 + BEATS;
    localparam PKT_NC_EXTRA   = 3;
    localparam OFF_W    = $clog2(LINE);
    localparam BANK_W   = $clog2(NB);
    localparam SET_W    = $clog2(SETS);
    localparam TAG_LSB  = OFF_W + BANK_W + SET_W;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;
    reg                 flush = 0, clean = 0;
    wire                flush_complete, clean_complete, mem_err;
    reg                 valid_cpu = 0, cacheable = 1, rd_wr_cpu = 0;
    reg  [1:0]          mem_size_cpu = 3;
    reg  [1:0]          master_id_from_cpu = 0;
    reg  [IDX_BITS-1:0] idx_from_cpu = 0;
    reg  [ADDR_W-1:0]   PC_from_cpu = 0;
    reg  [WDW-1:0]      data_from_cpu = 0;
    reg                 read_enable_from_lsu = 1;
    wire                r_valid, r_rdwr;
    wire [1:0]          r_size, r_mid;
    wire [IDX_BITS-1:0] r_idx;
    wire [WDW-1:0]      r_data;
    wire [AXI_IDW-1:0]  awid, arid;
    reg  [AXI_IDW-1:0]  bid, rid;
    wire [AXI_AW-1:0]   awaddr, araddr;
    wire [7:0]          awlen, arlen;
    wire [2:0]          awsize, arsize, awprot, arprot;
    wire [1:0]          awburst, arburst;
    wire [3:0]          awcache, arcache;
    wire                awvalid, wvalid, wlast, bready, arvalid, rready;
    reg                 bvalid = 0, rvalid = 0, rlast = 0;
    wire [AXI_DW-1:0]   wdata;
    reg  [AXI_DW-1:0]   rdata;
    wire [AXI_DW/8-1:0] wstrb;
    l1d_top_axi #(.AXI_ID_W(AXI_IDW)) dut (
        .clk(clk), .rst(rst),
        .flush_request(flush), .clean_request(clean), .flush_complete(flush_complete), .clean_complete(clean_complete),
        .cpu_request_valid(valid_cpu), .cpu_request_cacheable(cacheable), .cpu_request_is_write(rd_wr_cpu), .cpu_request_size(mem_size_cpu),
        .cpu_request_master_id(master_id_from_cpu), .cpu_request_rob_index(idx_from_cpu),
        .cpu_request_addr(PC_from_cpu), .cpu_request_store_data(data_from_cpu),
        .cpu_request_is_atomic(1'b0), .cpu_request_atomic_is_amo(1'b0), .cpu_request_amo_op(4'd0),
        .snoop_request_valid(1'b0), .snoop_request_ready(), .snoop_request_addr({ADDR_W{1'b0}}), .snoop_request_invalidate(1'b0),
        .snoop_response_valid(), .snoop_response_ready(1'b1), .snoop_response_addr(), .snoop_response_present(), .snoop_response_dirty(), .snoop_response_data(),
        .amo_lock_timeout_sticky(),
        .lsu_response_read_enable(read_enable_from_lsu),
        .lsu_response_valid(r_valid), .lsu_response_is_write_ack(r_rdwr),
        .lsu_response_size(r_size), .lsu_response_master_id(r_mid),
        .lsu_response_rob_index(r_idx), .lsu_response_data(r_data),
        .axi_error_sticky(mem_err),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
        .m_axi_awvalid(awvalid), .m_axi_awready(1'b1),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(1'b1),
        .m_axi_bid(bid), .m_axi_bresp(2'b00), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
        .m_axi_arvalid(arvalid), .m_axi_arready(1'b1), .m_axi_aruser(), .m_axi_ruser(1'b0),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(2'b00), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );
    localparam QD = 16;
    reg [AXI_IDW-1:0] rq_id  [0:QD-1];
    reg [AXI_AW-1:0]  rq_ad  [0:QD-1];
    reg [7:0]         rq_len [0:QD-1];
    integer           rq_t   [0:QD-1];
    integer           rq_n = 0;
    integer           r_beat = 0;
    reg [AXI_IDW-1:0] bq_id  [0:QD-1];
    integer           bq_t   [0:QD-1];
    integer           bq_n = 0;
    reg [AXI_IDW-1:0] aw_id_r;
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            rq_n <= 0; r_beat <= 0; bq_n <= 0;
            rvalid <= 1'b0; bvalid <= 1'b0;
        end else begin : mem_step
            integer n_r, n_b, beat;
            reg [63:0] rd_word;
            n_r  = rq_n;
            n_b  = bq_n;
            beat = r_beat;
            if (rvalid) begin
                if (rlast) begin
                    for (k = 0; k < QD - 1; k = k + 1) begin
                        rq_id[k] = rq_id[k+1]; rq_ad[k] = rq_ad[k+1];
                        rq_len[k] = rq_len[k+1]; rq_t[k] = rq_t[k+1];
                    end
                    n_r  = n_r - 1;
                    beat = 0;
                end else begin
                    beat = beat + 1;
                end
            end
            if (arvalid) begin
                rq_id[n_r] = arid; rq_ad[n_r] = araddr; rq_len[n_r] = arlen; rq_t[n_r] = cyc;
                n_r = n_r + 1;
            end
            rd_word = rq_ad[0] + beat * (AXI_DW / 8);
            if (n_r > 0 && (cyc + 1 >= rq_t[0] + RLAT)) begin
                rvalid <= 1'b1;
                rid    <= rq_id[0];
                rlast  <= (beat == rq_len[0]);
                rdata  <= {(AXI_DW/64){rd_word}};
            end else begin
                rvalid <= 1'b0;
            end
            if (bvalid) begin
                for (k = 0; k < QD - 1; k = k + 1) begin
                    bq_id[k] = bq_id[k+1]; bq_t[k] = bq_t[k+1];
                end
                n_b = n_b - 1;
            end
            if (awvalid) aw_id_r <= awid;
            if (wvalid && wlast) begin
                bq_id[n_b] = awvalid ? awid : aw_id_r;
                bq_t[n_b]  = cyc;
                n_b = n_b + 1;
            end
            if (n_b > 0 && (cyc + 1 >= bq_t[0] + BLAT)) begin
                bvalid <= 1'b1;
                bid    <= bq_id[0];
            end else begin
                bvalid <= 1'b0;
            end
            rq_n   <= n_r;
            bq_n   <= n_b;
            r_beat <= beat;
        end
    end
    reg     trace = 0;
    integer c0 = 0;
    integer i;
    always @(posedge clk) if (!rst && trace) begin
        if (dut.u_dcache.g_bank[0].u_bank.gnt_lsu)
            $display("    c0+%0d  G   grant LSU seat %0d", cyc - c0, dut.u_dcache.g_bank[0].u_bank.sel_seat);
        if (dut.u_dcache.g_bank[0].u_bank.gnt_fast)
            $display("    c0+%0d  G   FAST ISSUE seat %0d (request at the pins, tag + data read of all ways)", cyc - c0, dut.u_dcache.g_bank[0].u_bank.new_seat);
        if (dut.u_dcache.g_bank[0].u_bank.r_kill)
            $display("    c0+%0d  R   fast issue cancelled (seat blocked), back to READY", cyc - c0);
        if (dut.u_dcache.g_bank[0].u_bank.gnt_refill)
            $display("    c0+%0d  S0  grant REFILL/SWAP token (MSHR entry %0d)", cyc - c0, dut.u_dcache.g_bank[0].u_bank.tok_id);
        if (dut.u_dcache.g_bank[0].u_bank.s1_hit)
            $display("    c0+%0d  S1  tag hit way %0d (%s)", cyc - c0, dut.u_dcache.g_bank[0].u_bank.hit_way,
                     dut.u_dcache.g_bank[0].u_bank.s1_store ? "store: bytes written in S2" : "load");
        if (dut.u_dcache.g_bank[0].u_bank.s1_lsu && !dut.u_dcache.g_bank[0].u_bank.s1_hit)
            $display("    c0+%0d  S1  tag miss", cyc - c0);
        if (dut.u_dcache.g_bank[0].u_bank.s1_refill)
            $display("    c0+%0d  S1  refill: victim way %0d valid=%0d held=%0d", cyc - c0,
                     dut.u_dcache.g_bank[0].u_bank.victim_way, dut.u_dcache.g_bank[0].u_bank.v_valid, dut.u_dcache.g_bank[0].u_bank.r_held);
        if (dut.u_dcache.g_bank[0].u_bank.s3_load)
            $display("    c0+%0d  S2  response built (%s)", cyc - c0, dut.u_dcache.g_bank[0].u_bank.s3_from_vc ? "victim cache" : "data array");
        if (dut.u_dcache.g_bank[0].u_bank.act_valid)
            $display("    c0+%0d  S2  seat %0d -> action %0d (1=WMSHR 2=WANY 3=WVC 4=WNC 5=OWNED) id %0d%s", cyc - c0,
                     dut.u_dcache.g_bank[0].u_bank.s2_seat, dut.u_dcache.g_bank[0].u_bank.act_code, dut.u_dcache.g_bank[0].u_bank.act_id,
                     dut.u_dcache.g_bank[0].u_bank.m_swap ? ", swap started" : "");
        if (dut.u_dcache.g_bank[0].u_bank.s2_refill)
            $display("    c0+%0d  S2  install: line + tag written, MSHR entry %0d freed", cyc - c0, dut.u_dcache.g_bank[0].u_bank.s2_mid);
        if (dut.u_dcache.g_bank[0].u_bank.lsu_response_valid)
            $display("    c0+%0d  S2  answer pushed to the merger (%s), seat %0d freed", cyc - c0,
                     dut.u_dcache.g_bank[0].u_bank.s3_load ? "pipeline" :
                     (dut.u_dcache.g_bank[0].u_bank.m_take ? "MSHR" : "NC"), dut.u_dcache.g_bank[0].u_bank.done_seat);
        if (arvalid)
            $display("    c0+%0d  AXI AR handshake id %0h", cyc - c0, arid);
        if (rvalid)
            $display("    c0+%0d  AXI R beat%s", cyc - c0, rlast ? " (last)" : "");
        if (awvalid)
            $display("    c0+%0d  AXI AW handshake id %0h", cyc - c0, awid);
        if (wvalid)
            $display("    c0+%0d  AXI W beat%s", cyc - c0, wlast ? " (last)" : "");
        if (bvalid)
            $display("    c0+%0d  AXI B id %0h", cyc - c0, bid);
        if (r_valid && read_enable_from_lsu)
            $display("    c0+%0d  OUT response idx %0d (%s)", cyc - c0, r_idx, r_rdwr ? "store ack" : "load data");
    end
    integer t_issue [0:(1<<IDX_BITS)-1];
    integer t_resp  [0:(1<<IDX_BITS)-1];
    reg [WDW-1:0] d_resp [0:(1<<IDX_BITS)-1];
    reg     pend    [0:(1<<IDX_BITS)-1];
    integer errors = 0;
    integer next_idx = 0;
    always @(posedge clk) begin
        if (!rst && r_valid && read_enable_from_lsu) begin
            if (!pend[r_idx]) begin
                $display("ERROR: response for idle idx %0d", r_idx);
                errors = errors + 1;
            end
            pend[r_idx]   <= 1'b0;
            t_resp[r_idx] <= cyc;
            d_resp[r_idx] <= r_data;
        end
    end
    function [ADDR_W-1:0] mk;
        input integer tag, set, bank, off;
        begin
            mk = ({{(ADDR_W-32){1'b0}}, tag[31:0]} << TAG_LSB) | (set << (OFF_W + BANK_W)) |
                 (bank << OFF_W) | off;
        end
    endfunction
    task issue;
        input        wr;
        input        cach;
        input [ADDR_W-1:0] a;
        output integer id;
        begin
            id = next_idx;
            next_idx = (next_idx + 1) % (1 << IDX_BITS);
            valid_cpu    = 1'b1;
            rd_wr_cpu    = wr;
            cacheable    = cach;
            mem_size_cpu = 2'd3;
            idx_from_cpu = id;
            PC_from_cpu  = a;
            data_from_cpu = {a[31:0], 32'h5a5a_0000 | id};
            pend[id]     = 1'b1;
            t_issue[id]  = cyc;
            @(negedge clk);
        end
    endtask
    task idle;
        begin
            valid_cpu = 1'b0;
        end
    endtask
    task wait_done;
        input integer id;
        begin
            while (pend[id]) @(posedge clk);
            @(negedge clk);
        end
    endtask
    task settle;
        begin
            repeat (40) @(negedge clk);
        end
    endtask
    task check;
        input [8*40-1:0] name;
        input integer id;
        input integer want;
        integer got;
        begin
            got = t_resp[id] - t_issue[id];
            if (got == want)
                $display("  RESULT %0s: latency %0d cycles (expected %0d) OK", name, got, want);
            else begin
                $display("  RESULT %0s: latency %0d cycles, EXPECTED %0d  <-- MISMATCH", name, got, want);
                errors = errors + 1;
            end
        end
    endtask
    task begin_scn;
        input [8*100-1:0] title;
        begin
            $display("");
            $display("=== %0s ===", title);
            c0 = cyc;
            next_idx = 0;
            trace = 1;
        end
    endtask
    task vc_valid_line;
        output [ADDR_W-1:0] a;
        output integer      found;
        integer s;
        begin
            found = 0;
            a = 0;
            for (s = 0; s < VCS; s = s + 1)
                if (!found && dut.u_dcache.g_bank[0].u_bank.u_vc.st[s] == 3'd1) begin
                    a = {dut.u_dcache.g_bank[0].u_bank.u_vc.la[s], {OFF_W{1'b0}}};
                    found = 1;
                end
        end
    endtask
    integer id0, id1, id2, id3, id4, id5, id6, id7, n, f;
    reg [ADDR_W-1:0] va;
    initial begin
        for (k = 0; k < (1 << IDX_BITS); k = k + 1) pend[k] = 1'b0;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (4) @(negedge clk);
        $display("tb_latency: RLAT = %0d, BLAT = %0d, AXI beats per line = %0d", RLAT, BLAT, BEATS);
        begin_scn("1. load miss, line not in cache / VC / MSHR (fetch)");
        issue(0, 1, mk(1, 5, 0, 8), id0);
        idle;
        wait_done(id0); trace = 0;
        check("load miss", id0, 7 + RLAT + BEATS + PKT_LINE_EXTRA);
        settle;
        begin_scn("2. load hit");
        issue(0, 1, mk(1, 5, 0, 8), id0);
        idle;
        wait_done(id0); trace = 0;
        check("load hit", id0, 4);
        settle;
        begin_scn("3. store hit (8 bytes)");
        issue(1, 1, mk(1, 5, 0, 16), id0);
        idle;
        wait_done(id0); trace = 0;
        check("store hit", id0, 4);
        settle;
        begin_scn("4. store miss (fetch, bytes merged in the MSHR)");
        issue(1, 1, mk(2, 6, 0, 0), id0);
        idle;
        wait_done(id0); trace = 0;
        check("store miss", id0, 7 + RLAT + BEATS + PKT_LINE_EXTRA);
        settle;
        begin_scn("5. load + load to the same line, consecutive cycles (both hit)");
        issue(0, 1, mk(1, 5, 0, 8), id0);
        issue(0, 1, mk(1, 5, 0, 24), id1);
        idle;
        wait_done(id1); trace = 0;
        check("load A", id0, 4);
        check("load B (same line)", id1, 4);
        settle;
        begin_scn("6. load then store to the same line, consecutive cycles");
        issue(0, 1, mk(1, 5, 0, 8), id0);
        issue(1, 1, mk(1, 5, 0, 32), id1);
        idle;
        wait_done(id1); trace = 0;
        check("load", id0, 4);
        check("store behind load", id1, 8);
        settle;
        begin_scn("7. primary miss + secondary miss to the same line");
        issue(0, 1, mk(3, 7, 0, 0), id0);
        issue(0, 1, mk(3, 7, 0, 8), id1);
        idle;
        wait_done(id1); trace = 0;
        check("primary miss", id0, 7 + RLAT + BEATS + PKT_LINE_EXTRA);
        check("secondary miss (waits for install)", id1, 14 + RLAT + BEATS + PKT_LINE_EXTRA);
        settle;
        $display("");
        $display("=== (setup) five misses to set 9 of bank 0, one victim goes to the victim cache ===");
        for (n = 1; n <= 5; n = n + 1) begin
            issue(0, 1, mk(10 + n, 9, 0, 0), id0);
            idle;
            wait_done(id0);
            settle;
        end
        vc_valid_line(va, f);
        if (!f) begin $display("ERROR: no VALID victim-cache slot"); errors = errors + 1; end
        begin_scn("8. load that hits a VALID victim-cache slot (answered, then swapped back)");
        issue(0, 1, va, id0);
        idle;
        wait_done(id0);
        settle; trace = 0;
        check("victim-cache load hit", id0, 4);
        issue(0, 1, mk(16, 9, 0, 0), id0);
        idle;
        wait_done(id0);
        settle;
        vc_valid_line(va, f);
        if (!f) begin $display("ERROR: no VALID victim-cache slot"); errors = errors + 1; end
        begin_scn("9. store that hits a VALID victim-cache slot (swap back, retry, hit)");
        issue(1, 1, va, id0);
        idle;
        wait_done(id0); trace = 0;
        check("victim-cache store hit", id0, 12);
        settle;
        begin_scn("10. non-cacheable load");
        issue(0, 0, 64'h0000_0000_0008_0000, id0);
        idle;
        wait_done(id0); trace = 0;
        check("NC load", id0, 8 + RLAT + PKT_NC_EXTRA);
        settle;
        begin_scn("11. non-cacheable store");
        issue(1, 0, 64'h0000_0000_0008_0040, id0);
        idle;
        wait_done(id0); trace = 0;
        check("NC store", id0, 8 + BLAT + PKT_NC_EXTRA);
        settle;
        begin_scn("12. eight load hits to bank 0, one request per cycle");
        for (n = 0; n < 8; n = n + 1) issue(0, 1, mk(1, 5, 0, 8 * n), id0);
        idle;
        for (n = 0; n < 8; n = n + 1) wait_done(n);
        trace = 0;
        for (n = 0; n < 8; n = n + 1)
            $display("  load %0d: issued c0+%0d, answered c0+%0d, latency %0d",
                     n, t_issue[n] - c0, t_resp[n] - c0, t_resp[n] - t_issue[n]);
        check("12: load 0", 0, 4); check("12: load 3", 3, 4);
        check("12: load 4", 4, 4); check("12: load 7", 7, 4);
        settle;
        begin_scn("13. eight load hits, banks 0,1,2,3,0,1,2,3, one request per cycle");
        for (n = 0; n < 4; n = n + 1) begin
            if (n > 0) begin
                trace = 0;
                issue(0, 1, mk(1, 5, n, 0), id0); idle; wait_done(id0); settle;
            end
        end
        c0 = cyc; next_idx = 0; trace = 1;
        for (n = 0; n < 8; n = n + 1) issue(0, 1, mk(1, 5, n % 4, 8 * (n / 4)), id0);
        idle;
        for (n = 0; n < 8; n = n + 1) wait_done(n);
        trace = 0;
        for (n = 0; n < 8; n = n + 1)
            $display("  load %0d (bank %0d): issued c0+%0d, answered c0+%0d, latency %0d",
                     n, n % 4, t_issue[n] - c0, t_resp[n] - c0, t_resp[n] - t_issue[n]);
        for (n = 0; n < 8; n = n + 1) check("13: load", n, 4);
        settle;
        begin_scn("14. six load hits to bank 0 while read_enable_from_lsu = 0 for 20 cycles");
        read_enable_from_lsu = 1'b0;
        for (n = 0; n < 6; n = n + 1) issue(0, 1, mk(1, 5, 0, 8 * n), id0);
        idle;
        repeat (14) @(negedge clk);
        read_enable_from_lsu = 1'b1;
        for (n = 0; n < 6; n = n + 1) wait_done(n);
        trace = 0;
        for (n = 0; n < 6; n = n + 1)
            $display("  load %0d: issued c0+%0d, answered c0+%0d, latency %0d",
                     n, t_issue[n] - c0, t_resp[n] - c0, t_resp[n] - t_issue[n]);
        settle;
        begin_scn("15. load hit arriving just as a refill token (same bank) is granted");
        issue(0, 1, mk(4, 8, 0, 0), id0);
        idle;
        repeat (6 + RLAT + BEATS + PKT_LINE_EXTRA) @(negedge clk);
        issue(0, 1, mk(1, 5, 0, 8), id1);
        idle;
        wait_done(id0); wait_done(id1); trace = 0;
        check("15: miss", id0, 7 + RLAT + BEATS + PKT_LINE_EXTRA);
        check("15: hit behind refill token", id1, 8);
        settle;
        begin_scn("16. store hit, then a load hit to another line granted in the store's write cycle");
        issue(1, 1, mk(1, 5, 0, 16), id0);
        idle; @(negedge clk); @(negedge clk);
        issue(0, 1, mk(4, 8, 0, 0), id1);
        idle;
        wait_done(id0); wait_done(id1); trace = 0;
        check("16: store hit", id0, 4);
        check("16: load hit, other line, during the write", id1, 4);
        settle;
        begin_scn("17. store hit, then a load of the same bytes granted in the store's write cycle (cancel + retry)");
        issue(1, 1, mk(1, 5, 0, 24), id0);
        idle; @(negedge clk); @(negedge clk);
        issue(0, 1, mk(1, 5, 0, 24), id1);
        idle;
        wait_done(id0); wait_done(id1); trace = 0;
        check("17: store hit", id0, 4);
        check("17: load of the stored bytes (cancelled once, retried)", id1, 8);
        va = mk(1, 5, 0, 24);
        if (d_resp[id1] !== {va[31:0], 32'h5a5a_0000 | id0}) begin
            $display("  RESULT 17: load data %h, EXPECTED the store data %h  <-- MISMATCH", d_resp[id1],
                     {va[31:0], 32'h5a5a_0000 | id0});
            errors = errors + 1;
        end else
            $display("  RESULT 17: load returns the store's data %h OK", d_resp[id1]);
        settle;
        $display("");
        if (errors == 0 && !mem_err) $display("TEST PASSED");
        else                         $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
    initial begin
        #2000000;
        $display("TEST FAILED (timeout)");
        $finish;
    end
endmodule
