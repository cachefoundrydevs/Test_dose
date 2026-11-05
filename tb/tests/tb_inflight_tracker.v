`timescale 1ns/1ps
`ifdef SMALL
  `define TRK_N 4
  `define TRK_LAW 6
`else
  `define TRK_N 8
  `define TRK_LAW 58
`endif
`ifndef NRAND
  `define NRAND 200000
`endif
`ifndef SEED
  `define SEED 1
`endif
module tb_inflight_tracker;
    localparam N   = `TRK_N;
    localparam LAW = `TRK_LAW;
    reg  [N-1:0]     occ, st, ar, aw;
    reg  [LAW-1:0]   ln [0:N-1];
    reg  [N*N-1:0]   older;
    reg              lock_v;
    reg  [LAW-1:0]   lock_l;
    reg  [N*LAW-1:0] lines_flat;
    wire [N-1:0]     blocked;
    l1d_inflight_tracker #(.N(N), .LINE_ADDR_W(LAW)) dut (
        .seat_occupied       (occ),
        .seat_is_store_class (st),
        .seat_is_amo_read    (ar),
        .seat_is_amo_write   (aw),
        .seat_line_addrs     (lines_flat),
        .older_than_flat     (older),
        .amo_lock_valid      (lock_v),
        .amo_lock_line       (lock_l),
        .seat_blocked        (blocked)
    );
    integer errors, checks, i, n, seed;
    integer cnt_blocked, cnt_ruleA, cnt_ruleB, cnt_ruleC, cnt_supp;
    reg [N-1:0] exp;
    task pack;
        integer k;
        begin
            for (k = 0; k < N; k = k + 1) lines_flat[k*LAW +: LAW] = ln[k];
        end
    endtask
    task model;
        integer c, o;
        reg a, b, cc, lock_hit, older_ar;
        begin
            exp = {N{1'b0}};
            for (c = 0; c < N; c = c + 1) begin
                a = 1'b0; older_ar = 1'b0;
                lock_hit = lock_v && (ln[c] == lock_l);
                for (o = 0; o < N; o = o + 1) begin
                    if (o != c && occ[o] && older[o*N + c]) begin
                        if (ln[o] == ln[c] && (st[o] || st[c])) a = 1'b1;
                        if (ar[o]) older_ar = 1'b1;
                    end
                end
                b  = lock_hit && !aw[c];
                cc = ar[c] && (lock_v || older_ar);
                if (a && !(aw[c] && lock_hit)) exp[c] = 1'b1;
                if (b)  exp[c] = 1'b1;
                if (cc) exp[c] = 1'b1;
                if (a && !(aw[c] && lock_hit)) cnt_ruleA = cnt_ruleA + 1;
                if (b)  cnt_ruleB = cnt_ruleB + 1;
                if (cc) cnt_ruleC = cnt_ruleC + 1;
                if (a && aw[c] && lock_hit) cnt_supp = cnt_supp + 1;
            end
            if (exp != {N{1'b0}}) cnt_blocked = cnt_blocked + 1;
        end
    endtask
    task check_model;
        begin
            pack; model; #1;
            checks = checks + 1;
            if (blocked !== exp) begin
                errors = errors + 1;
                if (errors <= 20) $display("MISMATCH random: got %b expected %b (occ=%b st=%b ar=%b aw=%b lock_v=%b)", blocked, exp, occ, st, ar, aw, lock_v);
            end
        end
    endtask
    task check_hand;
        input [8*28-1:0] name;
        input [2:0]      want;
        begin
            pack; #1;
            checks = checks + 1;
            if (blocked[2:0] !== want || (blocked >> 3) !== 0) begin
                errors = errors + 1;
                $display("FAIL %0s: blocked=%b, expected seats[2:0]=%b and the other seats 0", name, blocked, want);
            end
            model;
            if (exp[2:0] !== want) begin
                errors = errors + 1;
                $display("FAIL %0s: reference model gives %b but the hand value is %b", name, exp[2:0], want);
            end
        end
    endtask
    task clear_all;
        integer k;
        begin
            occ = 0; st = 0; ar = 0; aw = 0; older = 0; lock_v = 0; lock_l = 0;
            for (k = 0; k < N; k = k + 1) ln[k] = k + 1;
        end
    endtask
    task seat;
        input integer   k;
        input           o_, s_, r_, w_;
        input [LAW-1:0] l_;
        begin
            occ[k] = o_; st[k] = s_ | w_ | r_; ar[k] = r_; aw[k] = w_; ln[k] = l_;
        end
    endtask
    reg [LAW-1:0] pool [0:2];
    integer k2;
    initial begin
        errors = 0; checks = 0; cnt_blocked = 0; cnt_ruleA = 0; cnt_ruleB = 0; cnt_ruleC = 0; cnt_supp = 0;
        seed = `SEED;
        lines_flat = 0;
        clear_all; older = {N*N{1'b1}};
        check_hand("D1 empty", 3'b000);
        clear_all; seat(0,1,0,0,0,10); seat(1,1,0,0,0,10); older[0*N+1] = 1;
        check_hand("D2 load,load same line", 3'b000);
        clear_all; seat(0,1,1,0,0,10); seat(1,1,0,0,0,10); older[0*N+1] = 1;
        check_hand("D3 older store", 3'b010);
        clear_all; seat(0,1,0,0,0,10); seat(1,1,1,0,0,10); older[0*N+1] = 1;
        check_hand("D4 younger store", 3'b010);
        clear_all; seat(0,1,1,0,0,10); seat(1,1,1,0,0,11); older[0*N+1] = 1;
        check_hand("D5 different lines", 3'b000);
        clear_all; seat(0,0,1,0,0,10); seat(1,1,0,0,0,10); older[0*N+1] = 1;
        check_hand("D6 older seat empty", 3'b000);
        clear_all; lock_v = 1; lock_l = 10; seat(0,1,0,0,0,10); seat(1,1,0,0,0,11);
        check_hand("D7 lock blocks same line", 3'b001);
        clear_all; lock_v = 1; lock_l = 10; seat(0,1,0,0,1,10);
        check_hand("D8 AMO write passes lock", 3'b000);
        clear_all; lock_v = 1; lock_l = 20; seat(0,1,0,1,0,10);
        check_hand("D9 AMO read, lock elsewhere", 3'b001);
        clear_all; seat(0,1,0,1,0,10); seat(1,1,0,1,0,11); seat(2,1,0,0,0,12);
        older[0*N+1] = 1; older[0*N+2] = 1; older[1*N+2] = 1;
        check_hand("D10 older AMO read", 3'b010);
        clear_all; lock_v = 1; lock_l = 10; seat(0,1,0,0,1,10); seat(1,1,0,0,0,10); older[0*N+1] = 1;
        check_hand("D11 AMO write then load", 3'b010);
        clear_all; lock_v = 1; lock_l = 10; seat(0,1,0,0,1,10); seat(1,1,0,0,1,10); older[0*N+1] = 1;
        check_hand("D12 AMO write, AMO write", 3'b000);
        pool[0] = 1; pool[1] = $random(seed); pool[2] = $random(seed);
        for (n = 0; n < `NRAND; n = n + 1) begin
            for (i = 0; i < N; i = i + 1) begin
                occ[i] = (($random(seed) & 3) != 0);
                k2 = $random(seed) & 7;
                st[i] = (k2 >= 4); ar[i] = (k2 == 6); aw[i] = (k2 == 7);
                k2 = $random(seed) & 7;
                if (k2 == 7) ln[i] = $random(seed);
                else         ln[i] = pool[k2 % 3];
            end
            for (i = 0; i < N*N; i = i + 1) older[i] = $random(seed);
            lock_v = $random(seed);
            k2 = $random(seed) & 7;
            if (k2 == 7) lock_l = $random(seed); else lock_l = pool[k2 % 3];
            check_model;
        end
        $display("checks=%0d  vectors with a blocked seat=%0d  rule A=%0d  rule B=%0d  rule C=%0d  A cancelled by AMO write=%0d",
                 checks, cnt_blocked, cnt_ruleA, cnt_ruleB, cnt_ruleC, cnt_supp);
        if (cnt_ruleA == 0 || cnt_ruleB == 0 || cnt_ruleC == 0 || cnt_supp == 0) begin
            errors = errors + 1;
            $display("FAIL: a rule was never exercised by the random vectors");
        end
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
