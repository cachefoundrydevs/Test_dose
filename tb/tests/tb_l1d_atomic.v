`timescale 1ns/1ps
`include "l1d_defines.vh"
`define TEST_NAME "tb_l1d_atomic"
module tb_l1d_atomic;
`include "tb_dir_common.vh"
    reg  [WDW-1:0]    d, d2, d3;
    reg  [1:0]        st;
    reg               pr, dy, fnd, vd, vs;
    reg  [2:0]        vst;
    reg  [LINE*8-1:0] ld;
    integer           i0, i1, i2, i3, t0, n0;
    integer           lat_ld, lat_st, lat_lr, lat_sc, lat_scf, lat_amor, lat_amow;
    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        idle(5);
        req(C_LD, 0, 3, A(1,0,0), 0, d);
        req(C_SC, 0, 3, A(1,0,0), 64'hAAAA_0001, d);
        check(d == 64'd1, "T1 SC without a reservation must answer 1");
        req(C_LD, 0, 3, A(1,0,0), 0, d);
        check(d == pat64(A(1,0,0)), "T1 a failed SC must not write");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        check(d == pat64(A(2,0,0)), "T2 LR data");
        req(C_SC, 0, 3, A(2,0,0), 64'h1111_2222_3333_4444, d);
        check(d == 64'd0, "T2 SC after LR must succeed");
        req(C_LD, 0, 3, A(2,0,0), 0, d);
        check(d == 64'h1111_2222_3333_4444, "T2 SC data written");
        req(C_SC, 0, 3, A(2,0,0), 64'h5, d);
        check(d == 64'd1, "T2 second SC must fail (SC clears the reservation)");
        send(C_LD, 0, 3, A(2,0,0), 0, i0); wait_resp(i0, d); lat_ld = got_t[i0] - snt_t[i0];
        send(C_ST, 0, 3, A(2,0,0) + 32, 64'h3, i0); wait_resp(i0, d); lat_st = got_t[i0] - snt_t[i0];
        send(C_LR, 0, 3, A(2,0,0), 0, i0); wait_resp(i0, d); lat_lr = got_t[i0] - snt_t[i0];
        send(C_SC, 0, 3, A(2,0,0), 64'h77, i0); wait_resp(i0, d); lat_sc = got_t[i0] - snt_t[i0];
        check(d == 64'd0, "T2 SC hit");
        send(C_SC, 0, 3, A(2,0,0), 64'h78, i0); wait_resp(i0, d); lat_scf = got_t[i0] - snt_t[i0];
        check(d == 64'd1, "T2 SC fail hit");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        req(C_ST, 0, 2, A(2,0,0) + 8, 64'h9, d);
        req(C_SC, 0, 3, A(2,0,0), 64'hBAD, d);
        check(d == 64'd1, "T3 store to the reserved line must make the SC fail");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        req(C_LD, 0, 3, A(2,0,0) + 16, 0, d);
        req(C_SC, 0, 3, A(2,0,0), 64'h4444, d);
        check(d == 64'd0, "T4 a load must not break the reservation");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        req(C_LR, 0, 3, A(2,0,1), 0, d);
        req(C_SC, 0, 3, A(2,0,1), 64'h5502, d);
        check(d == 64'd0, "T5 SC on the line of the newest LR (bank 1) succeeds");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        req(C_LR, 0, 3, A(2,0,1), 0, d);
        req(C_SC, 0, 3, A(2,0,0), 64'h5501, d);
        check(d == 64'd1, "T5 the reservation moved to bank 1: an SC in bank 0 fails");
        req(C_SC, 0, 3, A(2,0,1), 64'h5503, d);
        check(d == 64'd1, "T5 the failed SC ended the reservation: the SC in bank 1 fails too");
        req(C_LD, 0, 3, A(2,0,1), 0, d);
        check(d == 64'h5502, "T5 only the successful SC wrote (bank 1 holds 5502)");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        req(C_LR, 0, 3, A(2,1,0), 0, d);
        req(C_SC, 0, 3, A(2,0,0), 64'h6601, d);
        check(d == 64'd1, "T6 the second LR in the bank replaces the first: SC x must fail");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        req(C_LR, 0, 3, A(2,1,0), 0, d);
        req(C_SC, 0, 3, A(2,1,0), 64'h6602, d);
        check(d == 64'd0, "T6 SC y succeeds");
        req(C_LR, 0, 3, A(3,2,0), 0, d);
        req(C_LD, 0, 3, A(4,2,0), 0, d);
        req(C_LD, 0, 3, A(5,2,0), 0, d);
        req(C_LD, 0, 3, A(6,2,0), 0, d);
        peek_state(A(3,2,0), st);
        check(st == ST_I, "T7 the reserved line should have been evicted");
        req(C_SC, 0, 3, A(3,2,0), 64'h7777, d);
        check(d == 64'd1, "T7 eviction clears the reservation: SC must fail");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        amo_op_sel = 4'd1;
        req(C_AR, 0, 3, A(2,0,0), 64'd5, d2);
        check(d2 == d, "T8 AMO answers the old value");
        req(C_SC, 0, 3, A(2,0,0), 64'h8888, d3);
        check(d3 == 64'd1, "T8 an AMO to the reserved line must make the SC fail");
        req(C_LD, 0, 3, A(2,0,0), 0, d3);
        check(d3 == d + 64'd5, "T8 AMO ADD result written");
        send(C_AR, 0, 3, A(2,0,0), 64'h10, i0); wait_resp(i0, d2); lat_amor = got_t[i0] - snt_t[i0];
        check(d2 == d + 64'd5, "T8 AMO hit old value");
        lat_amow = lat_st;
        req(C_LD, 0, 3, A(2,0,0), 0, d);
        send(C_AR, 0, 3, A(2,0,0), 64'h100, i0);
        send(C_LD, 0, 3, A(2,0,0), 0, i1);
        wait_resp(i0, d2);
        wait_resp(i1, d3);
        check(d2 == d, "T9 AMO old value");
        check(d3 == d + 64'h100, "T9 the younger load must see the AMO's result");
        check(got_t[i1] >= got_t[i0], "T9 the load is answered after the AMO");
        req(C_AR, 0, 3, A(7,3,2), 64'hF, d);
        check(d == pat64(A(7,3,2)), "T10 AMO miss answers the old memory value");
        req(C_LD, 0, 3, A(7,3,2), 0, d2);
        check(d2 == pat64(A(7,3,2)) + 64'hF, "T10 AMO miss result written");
        peek_state(A(7,3,2), st);
        check(st == ST_M, "T10 line must be M after the AMO");
        amo_one(4'd0, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h0000_0000_0000_0007, "T11 SWAP");
        amo_one(4'd1, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h8000_0000_0000_000C, "T11 ADD");
        amo_one(4'd2, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h8000_0000_0000_0002, "T11 XOR");
        amo_one(4'd3, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h0000_0000_0000_0005, "T11 AND");
        amo_one(4'd4, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h8000_0000_0000_0007, "T11 OR");
        amo_one(4'd5, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h8000_0000_0000_0005, "T11 MIN (old is negative)");
        amo_one(4'd6, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h0000_0000_0000_0007, "T11 MAX");
        amo_one(4'd7, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h0000_0000_0000_0007, "T11 MINU");
        amo_one(4'd8, 3, A(7,3,2), 64'h8000_0000_0000_0005, 64'd7, 64'h8000_0000_0000_0005, "T11 MAXU");
        amo_w32(4'd5, A(7,3,2), 32'h0000_0005, 32'hFFFF_FFF0, "T12 MIN.W (signed: -16 < 5)");
        amo_w32(4'd8, A(7,3,2), 32'h0000_0005, 32'hFFFF_FFF0, "T12 MAXU.W (unsigned: 0xFFFFFFF0 > 5)");
        amo_w32(4'd1, A(7,3,2), 32'h0000_0020, 32'h0000_0010, "T12 ADD.W (wraps at 32 bits)");
        amo_w32(4'd6, A(7,3,2), 32'h0000_0005, 32'h0000_0005, "T12 MAX.W (signed: 5 > -16)");
        req(C_ST, 0, 3, A(2,0,0), 64'd100, d);
        req(C_ST, 0, 3, A(2,1,0), 64'd200, d);
        amo_op_sel = 4'd1;
        send(C_AR, 0, 3, A(2,0,0), 64'd1, i0);
        send(C_AR, 0, 3, A(2,0,0), 64'd1, i1);
        send(C_AR, 0, 3, A(2,1,0), 64'd2, i2);
        wait_resp(i0, d); wait_resp(i1, d2); wait_resp(i2, d3);
        check(d == 64'd100 && d2 == 64'd101, "T13 the second AMO on the line sees the first one's result");
        check(d3 == 64'd200, "T13 AMO on another line of the bank");
        req(C_LD, 0, 3, A(2,0,0), 0, d);
        check(d == 64'd102, "T13 two AMO ADDs on one line: both applied");
        req(C_LD, 0, 3, A(2,1,0), 0, d);
        check(d == 64'd202, "T13 AMO on the second line applied");
        req(C_SC, 1, 3, NC_BASE + 64, 64'h1234, d);
        check(d == 64'd1, "T14 non-cacheable SC must fail");
        check(mem64(NC_BASE + 64) == pat64(NC_BASE + 64), "T14 non-cacheable SC must not write");
        req(C_LR, 1, 3, NC_BASE + 72, 0, d);
        check(d == pat64(NC_BASE + 72), "T14 non-cacheable LR is a plain load");
        amo_op_sel = 4'd1;
        req(C_AR, 1, 3, NC_BASE + 80, 64'h1, d);
        check(d == 64'd0, "T14 non-cacheable AMO (not supported) answers 0");
        check(mem64(NC_BASE + 80) == pat64(NC_BASE + 80), "T14 non-cacheable AMO must not write");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        snoop(A(2,0,0), 1'b0, pr, dy, ld);
        check(pr == 1'b1, "T15 snoop read finds the line");
        req(C_SC, 0, 3, A(2,0,0), 64'h1515, d);
        check(d == 64'd1, "T15 snoop read on the reserved line: SC must fail");
        req(C_LR, 0, 3, A(2,0,0), 0, d);
        snoop(A(2,0,0), 1'b1, pr, dy, ld);
        req(C_SC, 0, 3, A(2,0,0), 64'h1516, d);
        check(d == 64'd1, "T15 snoop invalidate on the reserved line: SC must fail");
        amo_op_sel = 4'd0;
        req(C_AR, 0, 3, A(2,0,0), 64'hA16A16, d);
        snoop(A(2,0,0), 1'b1, pr, dy, ld);
        check(pr && dy, "T16 snoop answer: present and dirty");
        check(ld[63:0] == 64'hA16A16, "T16 snoop data must hold the AMO's result");
        check(mem64(A(2,0,0)) == 64'hA16A16, "T16 handed-over line written to memory");
        peek_state(A(2,0,0), st);
        check(st == ST_I, "T16 line invalid after the snoop");
        check(!amo_err, "T17 amo_err must stay 0 (there is no AMO lock)");
        check(!mem_err, "mem_err must stay 0");
        $display("cycles (this test's count, hit): load %0d, store %0d, LR %0d, SC success %0d, SC fail %0d, AMO %0d",
                 lat_ld, lat_st, lat_lr, lat_sc, lat_scf, lat_amor);
        check(lat_lr == lat_ld && lat_amor == lat_ld && lat_sc == lat_st && lat_scf == lat_st,
              "atomic hits must take the cycles of a load / store hit (an AMO answers like a load)");
        if (errors == 0) $display("TEST PASSED: tb_l1d_atomic");
        else             $display("TEST FAILED: tb_l1d_atomic (%0d errors)", errors);
        $finish;
    end
    task amo_one;
        input [3:0]        op;
        input [1:0]        size;
        input [ADDR_W-1:0] a;
        input [63:0]       old, opnd, exp_new;
        input [8*40-1:0]   name;
        reg   [63:0]       r1, r2;
        begin
            req(C_ST, 0, 3, a, old, r1);
            amo_op_sel = op;
            req(C_AR, 0, size, a, opnd, r1);
            req(C_LD, 0, 3, a, 0, r2);
            if (r1 !== old || r2 !== exp_new) begin
                errors = errors + 1;
                $display("ERROR %0s: old %h (expected %h), new %h (expected %h)", name, r1, old, r2, exp_new);
            end else
                $display("  %0s: old %h new %h OK", name, r1, r2);
        end
    endtask
    task amo_w32;
        input [3:0]        op;
        input [ADDR_W-1:0] a;
        input [31:0]       opnd, exp_new;
        input [8*40-1:0]   name;
        reg   [63:0]       r1, r2;
        begin
            req(C_ST, 0, 3, a, 64'hFFFF_FFF0_1111_1111, r1);
            amo_op_sel = op;
            req(C_AR, 0, 2, a + 4, {32'd0, opnd}, r1);
            req(C_LD, 0, 3, a, 0, r2);
            if (r1 !== 64'h0000_0000_FFFF_FFF0 || r2 !== {exp_new, 32'h1111_1111}) begin
                errors = errors + 1;
                $display("ERROR %0s: old %h (expected 00000000fffffff0), word %h (expected %h)", name, r1, r2, {exp_new, 32'h1111_1111});
            end else
                $display("  %0s: old %h word %h OK", name, r1, r2);
        end
    endtask
endmodule
