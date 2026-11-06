`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_ports_order;
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
`ifdef STALL
    localparam RD_PCT = 25;
`else
    localparam RD_PCT = 75;
`endif
`ifdef ONEBANK
    localparam ONE_BANK = 1;
`else
    localparam ONE_BANK = 0;
`endif
`include "tb_ports_common.vh"
    function [ADDR_W-1:0] hot_line;
        input integer i;
        begin
            if (ONE_BANK != 0) hot_line = line_addr(1 + i, 0, 1);
            else               hot_line = line_addr(1, 0, i);
        end
    endfunction
    integer ev_raw, ev_war, ev_waw, ev_from_line;
    integer e_a, e_b, e_c, e_d, e_e;
    reg [ADDR_W-1:0] la, lb;
    integer op_limit, rot, pp, kk, li, q;
    task cover_cross;
        input integer      pt;
        input [ADDR_W-1:0] a;
        input              wr;
        integer e;
        begin
            for (e = 0; e < NOUT; e = e + 1)
                if (out_v[e] && (e / NIDX) != pt && line_of(out_addr[e]) == line_of(a)) begin
                    if (!wr && (out_kind[e] == K_ST))                ev_raw = ev_raw + 1;
                    if (wr && (out_kind[e] == K_LD))                 ev_war = ev_war + 1;
                    if (wr && (out_kind[e] == K_ST))                 ev_waw = ev_waw + 1;
                end
        end
    endtask
    task drive_cycle;
        input integer pct;
        reg               nc, wr;
        reg [1:0]         size;
        reg [WDW-1:0]     wd;
        reg [ADDR_W-1:0]  a;
        integer           r, ent, off;
        begin
            rot = rot + 1;
            for (kk = 0; kk < PORTS; kk = kk + 1) begin
                pp = (kk + rot) % PORTS;
                if (issued < op_limit && can_send(pp) && ({$random(seed)} % 100) < pct) begin
                    r    = {$random(seed)} % 100;
                    size = {$random(seed)} % 4;
                    wr   = (({$random(seed)} % 100) < 45);
                    wd   = {$random(seed), $random(seed)};
                    nc   = (r >= 95);
                    if (nc) begin
                        a = NC_BASE + ({$random(seed)} % NC_LINES) * LINE + ((({$random(seed)} % LINE)) & ~((1 << size) - 1));
                    end else if (r < 70) begin
                        li  = {$random(seed)} % 3;
                        off = (({$random(seed)} % 16)) & ~((1 << size) - 1);
                        a   = hot_line(li) + off;
                    end else begin
                        off = (({$random(seed)} % LINE)) & ~((1 << size) - 1);
                        a   = line_addr({$random(seed)} % NT, {$random(seed)} % NS, {$random(seed)} % NB) + off;
                    end
                    if (!rule_r3_clash(a, wr)) begin
                        if (!nc) cover_cross(pp, a, wr);
                        send(pp, wr ? K_ST : K_LD, nc, size, a, wd, 4'd0, ent);
                    end
                end
            end
        end
    endtask
    task directed;
        reg [WDW-1:0] x;
        begin
            la = hot_line(0);
            lb = (ONE_BANK != 0) ? hot_line(1) : line_addr(2, 1, 0);
            tick; send(0, K_LD, 1'b0, 2'd3, la, 0, 4'd0, e_a); tick; wait_entry(e_a);
            tick; send(0, K_LD, 1'b0, 2'd3, lb, 0, 4'd0, e_a); tick; wait_entry(e_a);
            repeat (8) tick;
            $display("=== D1 (CC-4): a store waits in its port line, a younger load of the same bytes on another port ===");
            tick;
            send(0, K_LD, 1'b0, 2'd3, lb + 8, 0, 4'd0, e_a);
            send(2, K_ST, 1'b0, 2'd3, la, 64'hD1D1_D1D1_0000_0001, 4'd0, e_b);
            tick;
            send(1, K_LD, 1'b0, 2'd3, la, 0, 4'd0, e_c);
            tick; wait_entry(e_a); wait_entry(e_b); wait_entry(e_c);
            check(got_d[e_c] == 64'hD1D1_D1D1_0000_0001, "D1 the younger load (P1) returns the store data of P2");
            $display("=== D2 (CC-5): a load waits, a younger store to the same bytes on another port ===");
            tick;
            send(0, K_LD, 1'b0, 2'd3, lb + 16, 0, 4'd0, e_a);
            send(3, K_LD, 1'b0, 2'd3, la, 0, 4'd0, e_b);
            tick;
            send(2, K_ST, 1'b0, 2'd3, la, 64'hD2D2_D2D2_0000_0002, 4'd0, e_c);
            tick; wait_entry(e_a); wait_entry(e_b); wait_entry(e_c);
            check(got_d[e_b] == 64'hD1D1_D1D1_0000_0001, "D2 the older load (P3) returns the OLD data, not the younger store's");
            tick; send(1, K_LD, 1'b0, 2'd3, la, 0, 4'd0, e_d); tick; wait_entry(e_d);
            check(got_d[e_d] == 64'hD2D2_D2D2_0000_0002, "D2 a later load sees the store");
            $display("=== D3: byte stores of different sizes to one word from three ports, in consecutive cycles ===");
            tick; send(0, K_ST, 1'b0, 2'd3, la + 24, 64'h1111_2222_3333_4444, 4'd0, e_a);
            tick; send(1, K_ST, 1'b0, 2'd1, la + 26, 64'h0000_0000_0000_AAAA, 4'd0, e_b);
            tick; send(2, K_ST, 1'b0, 2'd0, la + 25, 64'h0000_0000_0000_00BB, 4'd0, e_c);
            tick; send(3, K_ST, 1'b0, 2'd2, la + 28, 64'h0000_0000_CCCC_DDDD, 4'd0, e_d);
            tick; send(0, K_LD, 1'b0, 2'd3, la + 24, 0, 4'd0, e_e);
            tick; wait_entry(e_a); wait_entry(e_b); wait_entry(e_c); wait_entry(e_d); wait_entry(e_e);
            x = {32'hCCCC_DDDD, 16'hAAAA, 8'hBB, 8'h44};
            check(got_d[e_e] == x, "D3 the bytes are merged in send order (CCCCDDDD AAAA BB 44)");
            repeat (6) tick;
        end
    endtask
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
        ev_raw = 0; ev_war = 0; ev_waw = 0; ev_from_line = 0; rot = 0;
        init_tb;
        op_limit = 1000000;
        directed;
        wait_drained(0);
        op_limit = issued + N_OPS;
        while (issued < op_limit) begin
            tick;
            for (pp = 0; pp < PORTS; pp = pp + 1) read_enable[pp] = (({$random(seed)} % 100) < RD_PCT);
            drive_cycle(70);
        end
        tick;
        wait_drained(RD_PCT);
        $display("random part done: %0d requests", issued);
        pulse_and_wait(1'b0);
        check_memory("clean");
        op_limit = issued + 1000;
        while (issued < op_limit) begin
            tick;
            drive_cycle(70);
        end
        tick;
        wait_drained(0);
        pulse_and_wait(1'b1);
        check_memory("flush");
        $display("coverage: read-after-write across ports %0d, write-after-read %0d, write-after-write %0d, seated from a line %0d",
                 ev_raw, ev_war, ev_waw, ev_from_line);
        if (ev_raw == 0 || ev_war == 0 || ev_waw == 0 || ev_from_line == 0) begin
            errors = errors + 1;
            $display("ERROR: a required cross-port case never happened (see the counts above)");
        end
        finish_tb("tb_ports_order");
    end
endmodule
