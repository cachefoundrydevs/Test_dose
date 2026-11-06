`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_ports_coh;
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
`ifdef SEED
    localparam SEED0 = `SEED;
`else
    localparam SEED0 = 1;
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
`ifdef MAINT
    localparam MAINT_ON = 1;
`else
    localparam MAINT_ON = 0;
`endif
`define TBP_SNOOP
`include "tb_ports_common.vh"
    integer op_limit, rot, pp, kk, t_wait;
    integer n_modeb, n_maint;
    function line_outstanding;
        input [ADDR_W-1:0] a;
        integer e;
        begin
            line_outstanding = 1'b0;
            for (e = 0; e < NOUT; e = e + 1)
                if (out_v[e] && line_of(out_addr[e]) == line_of(a)) line_outstanding = 1'b1;
        end
    endfunction
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
                    nc   = (r >= 94);
                    off  = (({$random(seed)} % LINE)) & ~((1 << size) - 1);
                    if (nc)           a = NC_BASE + ({$random(seed)} % NC_LINES) * LINE + off;
                    else if (r < 25)  a = line_addr(1 + ({$random(seed)} % 3), 0, 1) + off;
                    else              a = line_addr({$random(seed)} % NT, {$random(seed)} % NS, {$random(seed)} % NB) + off;
                    if (!nc && pp == 2 && r >= 85 && r < 94) begin
                        size = (({$random(seed)} % 2) == 0) ? 2'd3 : 2'd2;
                        a    = {a[ADDR_W-1:6], 3'd0, 3'd0} + ((size == 2'd2) ? (({$random(seed)} % 2) * 4) : 0);
                        if (!rule_r3_clash(a, 1'b1))
                            send(pp, K_AMO, 1'b0, size, a, wd, {$random(seed)} % 9, ent);
                    end else if (!rule_r3_clash(a, wr)) begin
                        send(pp, wr ? K_ST : K_LD, nc, size, a, wd, 4'd0, ent);
                    end
                end
            end
        end
    endtask
    reg [ADDR_W-1:0] mb_a;
    reg [WDW-1:0]    mb_v;
    integer          mb_j;
    always @(posedge clk) begin
        if (!rst && MODE_B != 0 && ans_valid && ans_inv && snp_en && !line_outstanding(ans_line) &&
            ({$random(seed)} % 100) < 60) begin
            mb_a = ans_line + (({$random(seed)} % (LINE / 8)) * 8);
            mb_v = {$random(seed), $random(seed)};
            for (mb_j = 0; mb_j < 8; mb_j = mb_j + 1) begin
                u_mem.mem[mb_a[MEM_BITS-1:0] + mb_j] = mb_v[mb_j*8 +: 8];
                ref_mem[mb_a[MEM_BITS-1:0] + mb_j]   = mb_v[mb_j*8 +: 8];
            end
            n_modeb = n_modeb + 1;
        end
    end
    task snoops_off;
        integer t;
        begin
            snp_en = 1'b0;
            t = 0;
            while (!sg_idle && t < 100000) begin tick; t = t + 1; end
            if (!sg_idle) begin errors = errors + 1; $display("ERROR %0t: snoops never finished", $time); end
        end
    endtask
    task load_all;
        integer t, s, b, w, pr, n;
        reg [ADDR_W-1:0] a;
        integer ent;
        begin
            pr = 0;
            for (t = 0; t < NT; t = t + 1)
                for (s = 0; s < NS; s = s + 1)
                    for (b = 0; b < NB; b = b + 1)
                        for (w = 0; w < LINE / 8; w = w + 1) begin
                            a = line_addr(t, s, b) + 8 * w;
                            n = 0;
                            tick;
                            while (!can_send(pr) && n < 100000) begin tick; n = n + 1; end
                            send(pr, K_LD, 1'b0, 2'd3, a, 64'd0, 4'd0, ent);
                            pr = (pr + 1) % PORTS;
                        end
            tick;
            wait_drained(0);
        end
    endtask
    integer mstate, mcnt, next_maint, mop, n_maint_busy;
    task maint_step;
        input allow_new;
        begin
            case (mstate)
                0: if (cyc >= next_maint && allow_new) begin snp_en = 1'b0; mstate = 1; end
                1: if (sg_idle) begin
                       mop = {$random(seed)} % 2;
                       if (mop == 1) flush = 1'b1; else clean = 1'b1;
                       if (total_out != 0) n_maint_busy = n_maint_busy + 1;
                       mstate = 2; mcnt = 0;
                   end
                2: begin flush = 1'b0; clean = 1'b0; mstate = 3; end
                3: begin
                       mcnt = mcnt + 1;
                       if (flush_complete || clean_complete) begin
                           snp_en = 1'b1; mstate = 0; n_maint = n_maint + 1;
                           next_maint = cyc + 800 + ({$random(seed)} % 1200);
                       end else if (mcnt > 200000) begin
                           errors = errors + 1; $display("ERROR: flush / clean never completed under load"); mstate = 0; snp_en = 1'b1;
                       end
                   end
                default: mstate = 0;
            endcase
        end
    endtask
    initial begin
        n_modeb = 0; n_maint = 0; n_maint_busy = 0; rot = 0; mstate = 0; mcnt = 0; mop = 0;
        init_tb;
        op_limit = N_OPS;
        next_maint = cyc + 600;
        snp_en = 1'b1;
        while (issued < op_limit || total_out != 0) begin
            tick;
            for (pp = 0; pp < PORTS; pp = pp + 1) read_enable[pp] = (({$random(seed)} % 100) < 80);
            drive_cycle(55);
            if (MAINT_ON != 0) maint_step(issued < op_limit);
            if (cyc > 5000000) begin errors = errors + 1; $display("ERROR: random phase does not finish"); issued = op_limit; end
        end
        read_enable = {PORTS{1'b1}};
        t_wait = 0;
        while (mstate != 0 && t_wait < 300000) begin tick; maint_step(1'b0); t_wait = t_wait + 1; end
        $display("random phase: %0d requests, %0d outside writes (mode B), %0d clean / flush under load (%0d started with requests outstanding)",
                 issued, n_modeb, n_maint, n_maint_busy);
        snoops_off;
        wait_drained(0);
        pulse_and_wait(1'b1);
        check_memory("flush");
        load_all;
        snp_en = 1'b1;
        repeat (400) tick;
        snoops_off;
        pulse_and_wait(1'b1);
        check_memory("final flush");
        $display("snoops: %0d sent (%0d invalidate), %0d answered (%0d present, %0d dirty, %0d absent), %0d cancelled",
                 u_snp.n_sent, u_snp.n_inv, u_snp.n_ans, u_snp.n_present, u_snp.n_dirty, u_snp.n_absent, u_snp.n_cancel);
        if (u_snp.n_ans == 0 || u_snp.n_present == 0 || u_snp.n_dirty == 0) begin
            errors = errors + 1;
            $display("ERROR: the snoop traffic never produced a present and a dirty answer (see the counts above)");
        end
        if (MODE_B != 0 && n_modeb == 0) begin errors = errors + 1; $display("ERROR: mode B never wrote outside the cache"); end
        if (MAINT_ON != 0 && (n_maint < 1 || n_maint_busy < 1)) begin errors = errors + 1; $display("ERROR: no clean / flush ran under load (%0d done, %0d with requests outstanding)", n_maint, n_maint_busy); end
        finish_tb("tb_ports_coh");
    end
endmodule
