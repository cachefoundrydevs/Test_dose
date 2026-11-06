`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_ports_amo;
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
    localparam N_OPS = 3000;
`endif
`ifdef NLR
    localparam N_LR = `NLR;
`else
    localparam N_LR = 280;
`endif
`ifdef SEED
    localparam SEED0 = `SEED;
`else
    localparam SEED0 = 1;
`endif
`ifdef ALLPORTS
    localparam [3:0] AMO_PORTS = 4'b1111;
`else
    localparam [3:0] AMO_PORTS = 4'b0100;
`endif
`include "tb_ports_common.vh"
    function [ADDR_W-1:0] amo_line;
        input integer i;
        begin
            case (i)
                0: amo_line = line_addr(1, 0, 0);
                1: amo_line = line_addr(1, 0, 1);
                2: amo_line = line_addr(2, 0, 1);
                3: amo_line = line_addr(1, 1, 2);
                default: amo_line = line_addr(1, 0, 3);
            endcase
        end
    endfunction
    integer op_limit, rot, pp, kk;
    integer e_a, e_b, e_c, e_d;
    integer n_amo_op [0:8];
    integer n_sc_ok, n_sc_fail, n_sc_must_ok, n_sc_must_fail, n_sc_may;
    reg [WDW-1:0] special [0:7];
    function [WDW-1:0] rand_operand;
        input integer dummy;
        integer r;
        begin
            r = {$random(seed)} % 10;
            if (r < 6) rand_operand = {$random(seed), $random(seed)};
            else       rand_operand = special[{$random(seed)} % 8];
        end
    endfunction
    task send_now;
        input integer      pt;
        input [2:0]        kind;
        input [1:0]        size;
        input [ADDR_W-1:0] a;
        input [WDW-1:0]    wd;
        input [3:0]        op;
        output integer     entry;
        integer t;
        reg     wr;
        begin
            wr = (kind == K_ST) || (kind == K_SC) || (kind == K_AMO);
            tick;
            t = 0;
            while ((!can_send(pt) || rule_r3_clash(a, wr)) && t < 20000) begin tick; t = t + 1; end
            send(pt, kind, 1'b0, size, a, wd, op, entry);
        end
    endtask
    task drive_cycle;
        input integer pct;
        reg               wr;
        reg [1:0]         size;
        reg [WDW-1:0]     wd;
        reg [ADDR_W-1:0]  a;
        reg [3:0]         op;
        integer           r, ent, off, li;
        begin
            rot = rot + 1;
            for (kk = 0; kk < PORTS; kk = kk + 1) begin
                pp = (kk + rot) % PORTS;
                if (issued < op_limit && can_send(pp) && ({$random(seed)} % 100) < pct) begin
                    r  = {$random(seed)} % 100;
                    li = {$random(seed)} % 5;
                    wd = rand_operand(0);
                    if (r < 35 && AMO_PORTS[pp]) begin
                        size = (({$random(seed)} % 100) < 60) ? 2'd3 : 2'd2;
                        off  = (({$random(seed)} % 2) * 8) + ((size == 2'd2) ? (({$random(seed)} % 2) * 4) : 0);
                        a    = amo_line(li) + off;
                        op   = {$random(seed)} % 9;
                        if (!rule_r3_clash(a, 1'b1)) begin
                            send(pp, K_AMO, 1'b0, size, a, wd, op, ent);
                            n_amo_op[op] = n_amo_op[op] + 1;
                        end
                    end else begin
                        size = {$random(seed)} % 4;
                        off  = (({$random(seed)} % 32)) & ~((1 << size) - 1);
                        a    = amo_line(li) + off;
                        wr   = (({$random(seed)} % 100) < 40);
                        if (r >= 95) begin
                            a = line_addr({$random(seed)} % NT, {$random(seed)} % NS, {$random(seed)} % NB) + off;
                        end
                        if (!rule_r3_clash(a, wr))
                            send(pp, wr ? K_ST : K_LD, 1'b0, size, a, wd, 4'd0, ent);
                    end
                end
            end
        end
    endtask
    task counter_race;
        input integer n_add;
        reg [ADDR_W-1:0] ctr;
        integer adds, ent, pr, t;
        begin
            ctr  = amo_line(1) + 8;
            adds = 0;
            t = 0;
            while (adds < n_add && t < 100000) begin
                tick;
                t = t + 1;
                if (({$random(seed)} % 100) < 55) begin
                    pr = 2;
                    if (AMO_PORTS == 4'b1111) pr = {$random(seed)} % PORTS;
                    if (can_send(pr)) begin
                        send(pr, K_AMO, 1'b0, 2'd3, ctr, 64'd1, OP_ADD, ent);
                        adds = adds + 1;
                        n_amo_op[OP_ADD] = n_amo_op[OP_ADD] + 1;
                    end
                end else begin
                    for (pr = 0; pr < PORTS; pr = pr + 1)
                        if (can_send(pr) && ({$random(seed)} % 100) < 80)
                            send(pr, K_LD, 1'b0, 2'd3, ctr, 64'd0, 4'd0, ent);
                end
                for (pr = 0; pr < PORTS; pr = pr + 1) read_enable[pr] = (({$random(seed)} % 100) < 85);
            end
            read_enable = {PORTS{1'b1}};
            wait_drained(0);
            $display("counter race: %0d adds sent, reference counter = %0d", adds, ref_read(ctr, 2'd3));
        end
    endtask
    task do_sc;
        input integer      pt;
        input [ADDR_W-1:0] a;
        input [WDW-1:0]    v;
        input integer      must;
        input [8*48-1:0]   what;
        integer e;
        begin
            send_now(pt, K_SC, 2'd3, a, v, 4'd0, e);
            wait_entry(e);
            if (got_d[e] == 64'd0) begin
                n_sc_ok = n_sc_ok + 1;
                ref_write(a, 2'd3, v);
                if (must == 2) begin errors = errors + 1; $display("ERROR: SC succeeded but had to fail: %0s", what); end
            end else begin
                n_sc_fail = n_sc_fail + 1;
                if (must == 1) begin errors = errors + 1; $display("ERROR: SC failed but had to succeed: %0s", what); end
            end
            if (must == 1) n_sc_must_ok = n_sc_must_ok + 1;
            if (must == 2) n_sc_must_fail = n_sc_must_fail + 1;
            if (must == 0) n_sc_may = n_sc_may + 1;
        end
    endtask
    task lrsc_round;
        input integer round;
        integer kind, ctr_i, pl, ps, pi, e_lr, e_x, e_y, n_x, kx;
        reg [ADDR_W-1:0] ctr, other_line, w3;
        reg [WDW-1:0]    v;
        begin
            kind  = round % 7;
            ctr_i = {$random(seed)} % 5;
            ctr   = amo_line(ctr_i);
            w3    = ctr + 24;
            other_line = amo_line((ctr_i + 1 + ({$random(seed)} % 4)) % 5);
            pl    = {$random(seed)} % PORTS;
            ps    = {$random(seed)} % PORTS;
            pi    = {$random(seed)} % PORTS;
            send_now(pl, K_LR, 2'd3, ctr, 64'd0, 4'd0, e_lr);
            case (kind)
                0: begin
                    wait_entry(e_lr);
                    do_sc(ps, ctr, got_d[e_lr] + 64'd1, 1, "a: nothing between LR and SC");
                end
                1: begin
                    send_now(pi, K_ST, 2'd3, w3, {$random(seed), $random(seed)}, 4'd0, e_x);
                    wait_entry(e_lr); wait_entry(e_x);
                    do_sc(ps, ctr, got_d[e_lr] + 64'd1, 2, "b: store to the line between LR and SC");
                end
                2: begin
                    wait_entry(e_lr);
                    send_now(pi, K_LD, 2'd3, w3, 64'd0, 4'd0, e_x);
                    send_now((pi + 1) % PORTS, K_LD, 2'd3, ctr, 64'd0, 4'd0, e_y);
                    wait_entry(e_x); wait_entry(e_y);
                    do_sc(ps, ctr, got_d[e_lr] + 64'd1, 1, "c: loads between LR and SC");
                end
                3: begin
                    for (n_x = 0; n_x < 3; n_x = n_x + 1) begin
                        kx = (pi + n_x) % PORTS;
                        send_now(kx, (({$random(seed)} % 2) == 0) ? K_ST : K_LD, 2'd3, other_line + 8 * ({$random(seed)} % 8),
                                 {$random(seed), $random(seed)}, 4'd0, e_x);
                    end
                    wait_entry(e_lr);
                    do_sc(ps, ctr, got_d[e_lr] + 64'd1, 0, "d: traffic to other lines");
                end
                4: begin
                    wait_entry(e_lr);
                    do_sc(ps, other_line, 64'hE0E0_0000_0000_0001, 2, "e: SC to another line");
                end
                5: begin
                    wait_entry(e_lr);
                    send_now(pi, K_LR, 2'd3, other_line, 64'd0, 4'd0, e_x);
                    wait_entry(e_x);
                    do_sc(ps, ctr, got_d[e_lr] + 64'd1, 2, "f: SC A after LR B");
                    do_sc(pi, other_line, got_d[e_x] + 64'd1, 2, "f: SC B after a failed SC");
                end
                default: begin
                    wait_entry(e_lr);
                    do_sc(ps, ctr, got_d[e_lr] + 64'd1, 1, "g: first SC");
                    do_sc(pi, ctr, got_d[e_lr] + 64'd2, 2, "g: second SC");
                end
            endcase
        end
    endtask
    integer ev_from_line;
    genvar gb;
    generate
        for (gb = 0; gb < NB; gb = gb + 1) begin : g_cov
            always @(posedge clk) if (!rst) begin
                if (!dut.u_dcache.u_front.g_bank[gb].u_queue.all_lines_empty && dut.u_dcache.u_front.g_bank[gb].u_queue.bank_takes_offer)
                    ev_from_line = ev_from_line + 1;
            end
        end
    endgenerate
    integer ii;
    initial begin
        ev_from_line = 0; rot = 0;
        n_sc_ok = 0; n_sc_fail = 0; n_sc_must_ok = 0; n_sc_must_fail = 0; n_sc_may = 0;
        for (ii = 0; ii < 9; ii = ii + 1) n_amo_op[ii] = 0;
        special[0] = 64'd0;                       special[1] = 64'd1;
        special[2] = 64'hFFFF_FFFF_FFFF_FFFF;     special[3] = 64'h8000_0000_0000_0000;
        special[4] = 64'h7FFF_FFFF_FFFF_FFFF;     special[5] = 64'h0000_0000_8000_0000;
        special[6] = 64'h0000_0000_7FFF_FFFF;     special[7] = 64'hFFFF_FFFF_0000_0000;
        init_tb;
        $display("=== part 1: random AMOs and plain accesses ===");
        op_limit = issued + N_OPS;
        while (issued < op_limit) begin
            tick;
            for (pp = 0; pp < PORTS; pp = pp + 1) read_enable[pp] = (({$random(seed)} % 100) < 80);
            drive_cycle(65);
        end
        tick;
        wait_drained(80);
        $display("AMOs sent per operation (SWAP ADD XOR AND OR MIN MAX MINU MAXU): %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                 n_amo_op[0], n_amo_op[1], n_amo_op[2], n_amo_op[3], n_amo_op[4], n_amo_op[5], n_amo_op[6], n_amo_op[7], n_amo_op[8]);
        $display("=== part 2: counter race ===");
        counter_race(300);
        $display("=== part 3: LR / SC rounds ===");
        for (ii = 0; ii < N_LR; ii = ii + 1) lrsc_round(ii);
        wait_drained(0);
        $display("SC results: %0d succeeded, %0d failed; must-succeed %0d, must-fail %0d, either %0d",
                 n_sc_ok, n_sc_fail, n_sc_must_ok, n_sc_must_fail, n_sc_may);
        if (n_sc_ok == 0 || n_sc_fail == 0) begin
            errors = errors + 1;
            $display("ERROR: the LR/SC rounds must produce both successful and failed SCs");
        end
        pulse_and_wait(1'b0);
        check_memory("clean");
        pulse_and_wait(1'b1);
        check_memory("flush");
        for (ii = 0; ii < 9; ii = ii + 1)
            if (n_amo_op[ii] == 0) begin
                errors = errors + 1;
                $display("ERROR: AMO operation %0d never exercised", ii);
            end
        finish_tb("tb_ports_amo");
    end
endmodule
