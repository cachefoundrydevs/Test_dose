`timescale 1ns/1ps
`include "l1d_defines.vh"
module tb_ports_vpu;
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
`ifdef VPU
    localparam VPU_PCT = `VPU;
`else
    localparam VPU_PCT = 35;
`endif
`ifdef SNP
    localparam SNP_PCT = `SNP;
`else
    localparam SNP_PCT = 6;
`endif
`ifdef SNOOP
`define TBP_SNOOP
`endif
`define TBP_VPU
`include "tb_ports_common.vh"
    integer ent, ent2, w, k, pp, kk, rot, t_wait, op_limit;
    reg [ADDR_W-1:0]  line_a, line_b, line_c, line_d;
    reg [LINE*8-1:0]  line_v;
    integer n_vst_upg, n_vst_miss, n_vld_vc, n_door_wait;
    initial begin n_vst_upg = 0; n_vst_miss = 0; n_vld_vc = 0; n_door_wait = 0; end
    genvar gb;
    generate
        for (gb = 0; gb < NB; gb = gb + 1) begin : g_cov
            always @(posedge clk) begin
                if (!rst) begin
                    if (dut.u_dcache.g_bank[gb].u_bank.u_s1.s1_lsu_th && dut.u_dcache.g_bank[gb].u_bank.u_s1.m_upg &&
                        dut.u_dcache.g_bank[gb].u_bank.u_s1.s1_line_op && dut.u_dcache.g_bank[gb].u_bank.u_s1.s1_store)
                        n_vst_upg = n_vst_upg + 1;
                    if (dut.u_dcache.g_bank[gb].u_bank.m_alloc && dut.u_dcache.g_bank[gb].u_bank.u_s2.s2_line_op &&
                        dut.u_dcache.g_bank[gb].u_bank.u_s2.s2_store)
                        n_vst_miss = n_vst_miss + 1;
                    if (dut.u_dcache.g_bank[gb].u_bank.s3_load && dut.u_dcache.g_bank[gb].u_bank.u_s2.s3_from_vc &&
                        dut.u_dcache.g_bank[gb].u_bank.u_s2.s2_line_op && !dut.u_dcache.g_bank[gb].u_bank.u_s2.s2_store)
                        n_vld_vc = n_vld_vc + 1;
                    if (dut.u_dcache.g_bank[gb].u_bank.lsu_request_valid && dut.u_dcache.g_bank[gb].u_bank.u_fifo_s0.in_no_place)
                        n_door_wait = n_door_wait + 1;
                end
            end
        end
    endgenerate
    function [LINE*8-1:0] rand_line;
        input integer dummy;
        integer q;
        begin
            for (q = 0; q < LINE / 4; q = q + 1) rand_line[q*32 +: 32] = $random(seed);
        end
    endfunction
    task vpu_now;
        input              is_write;
        input [ADDR_W-1:0] a;
        input [LINE*8-1:0] d;
        output integer     e;
        integer n;
        begin
            n = 0;
            while ((!can_send_vpu(0) || rule_r3_clash(a, is_write)) && n < 100000) begin tick; n = n + 1; end
            send_vpu(is_write, a, d, e);
        end
    endtask
    task scalar_now;
        input integer      pt;
        input [2:0]        kind;
        input [ADDR_W-1:0] a;
        input [WDW-1:0]    d;
        output integer     e;
        integer n;
        begin
            n = 0;
            while ((!can_send(pt) || rule_r3_clash(a, kind == K_ST)) && n < 100000) begin tick; n = n + 1; end
            send(pt, kind, 1'b0, 2'd3, a, d, 4'd0, e);
        end
    endtask
    task wait_vpu;
        input integer e;
        integer t;
        begin
            t = 0;
            while (vgot_t[e] < 0 && t < 30000) begin tick; t = t + 1; end
            if (vgot_t[e] < 0) begin errors = errors + 1; $display("ERROR %0t: VPU idx %0d never answered", $time, e); end
        end
    endtask
    task drive_cycle;
        input integer pct;
        reg               nc, wr;
        reg [1:0]         size;
        reg [WDW-1:0]     wd;
        reg [ADDR_W-1:0]  a;
        integer           r, off;
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
            if (issued < op_limit && can_send_vpu(0) && ({$random(seed)} % 100) < VPU_PCT) begin
                r  = {$random(seed)} % 100;
                wr = (({$random(seed)} % 100) < 50);
                if (r < 30) a = line_addr(1 + ({$random(seed)} % 3), 0, 1);
                else        a = line_addr({$random(seed)} % NT, {$random(seed)} % NS, {$random(seed)} % NB);
                if (!rule_r3_clash(a, wr)) send_vpu(wr, a, rand_line(0), ent);
            end
        end
    endtask
    initial begin
        rot = 0;
        init_tb;
        op_limit = N_OPS + 1000;
        line_a = line_addr(1, 0, 0);
        tick; vpu_now(1'b0, line_a, 0, ent); tick; wait_vpu(ent);
        repeat (20) tick;
        vpu_now(1'b0, line_a, 0, ent); tick; wait_vpu(ent);
        check(vgot_t[ent] - vout_t[ent] == 4, "D1 vector load hit answered in 4 cycles");
        repeat (5) tick;
        vpu_now(1'b1, line_a, rand_line(0), ent); tick; wait_vpu(ent);
        check(vgot_t[ent] - vout_t[ent] == 4, "D2 vector store hit acknowledged in 4 cycles");
        for (w = 0; w < LINE / 8; w = w + 1) begin scalar_now(w % 3, K_LD, line_a + 8 * w, 0, ent2); tick; end
        wait_drained(0);
        check(errors == 0, "D3 scalar loads see the vector store data");
        line_b = line_addr(2, 0, 1);
        for (w = 0; w < LINE / 8; w = w + 1) begin scalar_now(w % 3, K_ST, line_b + 8 * w, {$random(seed), $random(seed)}, ent2); tick; end
        vpu_now(1'b0, line_b, 0, ent); tick;
        wait_drained(0);
        check(errors == 0, "D4 a vector load sees eight scalar stores from three ports");
        line_c = line_addr(3, 1, 2);
        k = n_vst_miss;
        vpu_now(1'b1, line_c, rand_line(0), ent); tick; wait_vpu(ent);
        vpu_now(1'b0, line_c, 0, ent); tick;
        scalar_now(1, K_LD, line_c + 40, 0, ent2); tick;
        wait_drained(0);
        check(n_vst_miss > k, "D5 vector store miss fetched its line (CC-15)");
        line_d = line_addr(4, 1, 3);
        mem_sh_mode = 2'd2;
        scalar_now(0, K_LD, line_d + 16, 0, ent2); tick; wait_entry(ent2);
        mem_sh_mode = 2'd0;
        k = n_vst_upg;
        vpu_now(1'b1, line_d, rand_line(0), ent); tick; wait_vpu(ent);
        vpu_now(1'b0, line_d, 0, ent); tick;
        wait_drained(0);
        check(n_vst_upg > k, "D6 vector store on an S line took the upgrade path (CC-14)");
        for (w = 0; w <= WAYS; w = w + 1) begin vpu_now(1'b0, line_addr(w, 1, 0), 0, ent); tick; wait_vpu(ent); end
        vpu_now(1'b0, line_addr(0, 1, 0), 0, ent); tick;
        wait_drained(0);
        $display("  D7 vector loads answered from the victim cache so far: %0d", n_vld_vc);
        k = n_door_wait;
        for (w = 0; w < 4; w = w + 1) begin vpu_now(1'b1, line_addr(w + 1, 0, 3), rand_line(0), ent); tick; end
        wait_drained(0);
        $display("  D8 cycles a vector store waited at the bank door for a data place: %0d", n_door_wait - k);
        check(errors == 0, "D8 vector stores beyond the data places all completed");
`ifdef SNOOP
        snp_en = 1'b1;
`endif
        op_limit = issued + N_OPS;
        while (issued < op_limit || total_out != 0) begin
            tick;
            for (pp = 0; pp < PORTS; pp = pp + 1) read_enable[pp] = (({$random(seed)} % 100) < 80);
            vread_enable = (({$random(seed)} % 100) < 80);
            drive_cycle(50);
            if (cyc > 5000000) begin errors = errors + 1; $display("ERROR: random phase does not finish"); op_limit = issued; end
        end
        read_enable = {PORTS{1'b1}};
        vread_enable = 1'b1;
`ifdef SNOOP
        snp_en = 1'b0;
        t_wait = 0;
        while (!sg_idle && t_wait < 100000) begin tick; t_wait = t_wait + 1; end
`endif
        wait_drained(0);
        pulse_and_wait(1'b1);
        check_memory("flush");
        for (k = 0; k < NT * NS * NB; k = k + 1) begin
            vpu_now(1'b0, line_addr(k / (NS * NB), (k / NB) % NS, k % NB), 0, ent);
            tick;
        end
        wait_drained(0);
        pulse_and_wait(1'b1);
        check_memory("final flush");
        $display("coverage: vector store upgrades (CC-14) %0d, vector store misses (CC-15) %0d, vector loads from the victim cache %0d, bank door waits %0d",
                 n_vst_upg, n_vst_miss, n_vld_vc, n_door_wait);
        if (vlat_4 == 0)    begin errors = errors + 1; $display("ERROR: no vector answer in 4 cycles"); end
        if (n_vst_miss == 0) begin errors = errors + 1; $display("ERROR: no vector store miss was seen"); end
        if (n_vst_upg == 0)  begin errors = errors + 1; $display("ERROR: no vector store upgrade (CC-14) was seen"); end
        finish_tb("tb_ports_vpu");
    end
endmodule
