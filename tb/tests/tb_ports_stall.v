`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_ports_stall;
`ifdef TINY
    localparam SETS = 4, WAYS = 2, LSU_BUF = 4, MSHR = 2, NCE = 1, VCS = 2, RFIFO = 2;
    localparam LAT_BOUND = 96;
`else
    localparam SETS = `L1D_SETS, WAYS = `L1D_WAYS, LSU_BUF = `L1D_LSU_BUF_DEPTH,
               MSHR = `L1D_MSHR_ENTRIES, NCE = `L1D_MSHR_NC_ENTRIES, VCS = `L1D_VC_SLOTS,
               RFIFO = `L1D_RESP_FIFO_DEPTH;
    localparam LAT_BOUND = 64;
`endif
`ifdef SEED
    localparam SEED0 = `SEED;
`else
    localparam SEED0 = 1;
`endif
`include "tb_ports_common.vh"
    integer pp, kk, ent, t, n;
    integer base_cnt [0:PORTS-1];
    integer sent_win [0:PORTS-1];
    integer cnt_min, cnt_max;
    reg [ADDR_W-1:0] a;
    reg [PORTS-1:0]         prev_valid, prev_ren;
    reg [PORTS*IDX_BITS-1:0] prev_idx;
    reg [PORTS*WDW-1:0]     prev_data;
    reg [PORTS-1:0]         prev_ack;
    integer mon_p;
    initial begin prev_valid = 0; prev_ren = {PORTS{1'b1}}; prev_idx = 0; prev_data = 0; prev_ack = 0; end
    always @(posedge clk) begin
        if (!rst) begin
            for (mon_p = 0; mon_p < PORTS; mon_p = mon_p + 1) begin
                if (prev_valid[mon_p] && !prev_ren[mon_p]) begin
                    if (rsp_valid[mon_p] !== 1'b1 ||
                        rsp_idx[mon_p*IDX_BITS +: IDX_BITS] !== prev_idx[mon_p*IDX_BITS +: IDX_BITS] ||
                        rsp_data[mon_p*WDW +: WDW] !== prev_data[mon_p*WDW +: WDW] ||
                        rsp_is_write_ack[mon_p] !== prev_ack[mon_p]) begin
                        errors = errors + 1;
                        $display("ERROR %0t: port %0d answer changed or vanished while read_enable was 0", $time, mon_p);
                    end
                end
            end
            prev_valid = rsp_valid;
            prev_ren   = read_enable;
            prev_idx   = rsp_idx;
            prev_data  = rsp_data;
            prev_ack   = rsp_is_write_ack;
        end
    end
    function [ADDR_W-1:0] hit_addr;
        input integer b, w;
        begin
            hit_addr = line_addr(0, 0, b) + 8 * (w % 8);
        end
    endfunction
    task preload;
        integer b;
        begin
            for (b = 0; b < NB; b = b + 1) begin
                tick; send(b % PORTS, K_LD, 1'b0, 2'd3, hit_addr(b, 0), 64'd0, 4'd0, ent);
            end
            tick; wait_drained(0);
            repeat (10) tick;
        end
    endtask
    task check_idle_stop;
        input [8*40-1:0] when;
        begin
            repeat (12) tick;
            if (total_out != 0 || port_stop != {PORTS{1'b0}}) begin
                errors = errors + 1;
                $display("ERROR %0t: after %0s: %0d requests outstanding, stop = %b (must be idle and 0)", $time, when, total_out, port_stop);
            end else $display("  ok: all stops are 0 when idle, after %0s", when);
        end
    endtask
    task send_hits;
        input [PORTS-1:0] mask;
        input integer     bank0;
        input integer     bank_step;
        integer p;
        begin
            for (p = 0; p < PORTS; p = p + 1)
                if (mask[p] && can_send(p)) begin
                    send(p, K_LD, 1'b0, 2'd3, hit_addr((bank0 + p * bank_step) % NB, {$random(seed)} % 8) , 64'd0, 4'd0, ent);
                    sent_win[p] = sent_win[p] + 1;
                end
        end
    endtask
    task window_start;
        integer p;
        begin
            for (p = 0; p < PORTS; p = p + 1) begin base_cnt[p] = lat_cnt_port[p]; sent_win[p] = 0; end
        end
    endtask
    integer s2a_ok, s2b_p0, s2b_p2, s2b_p3;
    initial begin
        $display("=== S0: requests at the pins during reset ===");
        init_tb_pre_reset;
        for (n = 0; n < 8; n = n + 1) begin
            @(negedge clk);
            req_valid    = {PORTS{1'b1}};
            req_cacheable = {PORTS{1'b1}};
            req_addr[0*ADDR_W +: ADDR_W] = line_addr(1, 0, 0);
            req_addr[1*ADDR_W +: ADDR_W] = line_addr(1, 0, 1) + 8;
            req_addr[2*ADDR_W +: ADDR_W] = line_addr(1, 1, 2);
            req_addr[3*ADDR_W +: ADDR_W] = line_addr(1, 0, 3) + 16;
            req_idx      = {3'd3, 3'd2, 3'd1, 3'd0};
        end
        @(negedge clk);
        req_valid = {PORTS{1'b0}};
        init_tb_release_reset(0);
        repeat (30) tick;
        check(answered == 0, "S0 no answer for a request that was sent during reset");
        tick; send(0, K_LD, 1'b0, 2'd3, hit_addr(0, 1), 64'd0, 4'd0, ent); tick; wait_entry(ent);
        check(got_t[ent] >= 0, "S0 the first request after reset is answered");
        check_idle_stop("S0");
        preload;
        $display("=== S1: all four ports stall for 600 cycles ===");
        window_start;
        read_enable = {PORTS{1'b0}};
        for (n = 0; n < 600; n = n + 1) begin tick; send_hits(4'b1111, 0, 1); end
        $display("  sent during the stall: P0 %0d, P1 %0d, P2 %0d, P3 %0d (at most 8 each)", sent_win[0], sent_win[1], sent_win[2], sent_win[3]);
        check(sent_win[0] > 0 && sent_win[1] > 0 && sent_win[2] > 0 && sent_win[3] > 0, "S1 every port could send before its stop");
        check(total_out == sent_win[0] + sent_win[1] + sent_win[2] + sent_win[3], "S1 no answer was taken or lost during the stall");
        read_enable = {PORTS{1'b1}};
        tick; wait_drained(0);
        check_idle_stop("S1");
        $display("=== S1L: stop seen one cycle late, four ports to one bank, answers stalled ===");
        stop_lag = 1;
        window_start;
        read_enable = {PORTS{1'b0}};
        for (n = 0; n < 300; n = n + 1) begin tick; send_hits(4'b1111, 0, 0); end
        $display("  sent during the stall: P0 %0d, P1 %0d, P2 %0d, P3 %0d", sent_win[0], sent_win[1], sent_win[2], sent_win[3]);
        check(total_out == sent_win[0] + sent_win[1] + sent_win[2] + sent_win[3], "S1L no answer was taken or lost during the stall");
        read_enable = {PORTS{1'b1}};
        tick; wait_drained(0);
        stop_lag = 0;
        check_idle_stop("S1L");
        $display("=== S2a: P1 stalls for 800 cycles, the others work on other banks ===");
        window_start;
        for (n = 0; n < 800; n = n + 1) begin
            tick;
            read_enable = 4'b1101;
            if (can_send(1)) begin send(1, K_LD, 1'b0, 2'd3, hit_addr(1, {$random(seed)} % 8), 64'd0, 4'd0, ent); sent_win[1] = sent_win[1] + 1; end
            if (can_send(0)) begin send(0, K_LD, 1'b0, 2'd3, hit_addr(0, {$random(seed)} % 8), 64'd0, 4'd0, ent); sent_win[0] = sent_win[0] + 1; end
            if (can_send(2)) begin send(2, K_LD, 1'b0, 2'd3, hit_addr(2, {$random(seed)} % 8), 64'd0, 4'd0, ent); sent_win[2] = sent_win[2] + 1; end
            if (can_send(3)) begin send(3, K_LD, 1'b0, 2'd3, hit_addr(3, {$random(seed)} % 8), 64'd0, 4'd0, ent); sent_win[3] = sent_win[3] + 1; end
        end
        $display("  completed in the window: P0 %0d, P1 %0d, P2 %0d, P3 %0d", lat_cnt_port[0]-base_cnt[0], lat_cnt_port[1]-base_cnt[1],
                 lat_cnt_port[2]-base_cnt[2], lat_cnt_port[3]-base_cnt[3]);
        check((lat_cnt_port[0]-base_cnt[0]) >= 100 && (lat_cnt_port[2]-base_cnt[2]) >= 100 && (lat_cnt_port[3]-base_cnt[3]) >= 100,
              "S2a the other ports go on working while P1 stalls (>= 100 each)");
        read_enable = {PORTS{1'b1}};
        tick; wait_drained(0);
        check_idle_stop("S2a");
        $display("=== S2b: P1 stalls for 800 cycles, the others use P1's bank (information) ===");
        window_start;
        for (n = 0; n < 800; n = n + 1) begin
            tick;
            read_enable = 4'b1101;
            send_hits(4'b1111, 1, 0);
        end
        s2b_p0 = lat_cnt_port[0]-base_cnt[0]; s2b_p2 = lat_cnt_port[2]-base_cnt[2]; s2b_p3 = lat_cnt_port[3]-base_cnt[3];
        $display("INFO S2b: completed in the window while P1 stalls: P0 %0d, P1 %0d, P2 %0d, P3 %0d%0s", s2b_p0, lat_cnt_port[1]-base_cnt[1],
                 s2b_p2, s2b_p3, (s2b_p0 + s2b_p2 + s2b_p3 < 30) ? "  -> the stalled port blocks the bank for the other ports" : "");
        read_enable = {PORTS{1'b1}};
        tick; wait_drained(0);
        check_idle_stop("S2b");
        $display("=== S3: four ports, one bank, highest rate, %0d cycles ===", 3000);
        for (n = 0; n < PORTS; n = n + 1) lat_max_port[n] = 0;
        window_start;
        for (n = 0; n < 3000; n = n + 1) begin
            tick;
            send_hits(4'b1111, 2, 0);
        end
        tick; wait_drained(0);
        cnt_min = lat_cnt_port[0] - base_cnt[0]; cnt_max = cnt_min;
        for (n = 1; n < PORTS; n = n + 1) begin
            if (lat_cnt_port[n] - base_cnt[n] < cnt_min) cnt_min = lat_cnt_port[n] - base_cnt[n];
            if (lat_cnt_port[n] - base_cnt[n] > cnt_max) cnt_max = lat_cnt_port[n] - base_cnt[n];
        end
        $display("  completed: P0 %0d, P1 %0d, P2 %0d, P3 %0d; largest latency per port: %0d %0d %0d %0d (bound %0d)",
                 lat_cnt_port[0]-base_cnt[0], lat_cnt_port[1]-base_cnt[1], lat_cnt_port[2]-base_cnt[2], lat_cnt_port[3]-base_cnt[3],
                 lat_max_port[0], lat_max_port[1], lat_max_port[2], lat_max_port[3], LAT_BOUND);
        check(lat_max_port[0] <= LAT_BOUND && lat_max_port[1] <= LAT_BOUND && lat_max_port[2] <= LAT_BOUND && lat_max_port[3] <= LAT_BOUND,
              "S3 no answer takes longer than LAT_BOUND cycles");
        check(cnt_min * 100 >= cnt_max * 60, "S3 every port completes at least 60 % of the busiest port's count");
        check_idle_stop("S3");
        finish_tb("tb_ports_stall");
    end
endmodule
