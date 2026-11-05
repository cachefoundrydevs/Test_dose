`timescale 1ns/1ps
module tb_l1d_soc;
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
    localparam ADDR_W   = 64;
    localparam WDW      = 64;
    localparam LINE     = 64;
    localparam AXI_DW   = 128;
    localparam BEAT_B   = AXI_DW / 8;
    localparam ARLEN_W  = LINE / BEAT_B - 1;
    localparam RID_W    = 6;
    localparam WID_W    = 9;
    localparam V1_ID_W  = 6;
    localparam IDX_BITS = 3;
    localparam NIDX     = (1 << IDX_BITS);
    localparam MEM_BITS = 20;
    localparam [ADDR_W-1:0] RANGE_LO = 64'h0002_0000;
    localparam [ADDR_W-1:0] RANGE_HI = 64'h0003_FFFF;
    localparam NB         = 4;
    localparam SETS_PB    = 64;
    localparam SET_STRIDE = NB * LINE;
    localparam TAG_STRIDE = NB * SETS_PB * LINE;
    localparam NT         = 7;
    localparam NS         = 2;
    localparam [ADDR_W-1:0] NC_BASE = 64'h0003_E000;
    localparam NC_LINES   = 4;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    reg                 valid_cpu = 0, cachable = 1, rd_wr_cpu = 0;
    reg  [1:0]          mem_size_cpu = 0;
    reg  [1:0]          master_id_from_cpu = 0;
    reg  [IDX_BITS-1:0] idx_from_cpu = 0;
    reg  [ADDR_W-1:0]   PC_from_cpu = 0;
    reg  [WDW-1:0]      data_from_cpu = 0;
    reg                 read_enable_from_lsu = 1;
    reg                 clean = 0;
    wire                stop, clean_complete, flush_complete, mem_err;
    wire                r_valid, r_rdwr;
    wire [1:0]          r_size, r_mid;
    wire [IDX_BITS-1:0] r_idx;
    wire [WDW-1:0]      r_data;
    wire                D_axi_arvalid, D_axi_arready, D_axi_arlock;
    wire [ADDR_W-1:0]   D_axi_araddr;
    wire [RID_W-1:0]    D_axi_arid;
    wire [ARLEN_W-1:0]  D_axi_arlen;
    wire [2:0]          D_axi_arsize, D_axi_arprot;
    wire [1:0]          D_axi_arburst;
    wire [3:0]          D_axi_arcache, D_axi_arqos;
    wire                D_axi_rvalid, D_axi_rlast, D_axi_rready;
    wire                D_axi_aruser, D_axi_ruser;
    wire [AXI_DW-1:0]   D_axi_rdata;
    wire [RID_W-1:0]    D_axi_rid;
    wire [1:0]          D_axi_rres;
    wire                D_axi_wr_arvalid, D_axi_wr_arready, D_axi_wr_arlock;
    wire [ADDR_W-1:0]   D_axi_wr_araddr;
    wire [WID_W-1:0]    D_axi_wr_arid;
    wire [ARLEN_W-1:0]  D_axi_wr_arlen;
    wire [2:0]          D_axi_wr_arsize, D_axi_wr_arprot;
    wire [1:0]          D_axi_wr_arburst;
    wire [3:0]          D_axi_wr_arcache, D_axi_wr_arqos;
    wire                D_axi_wr_d_valid, D_axi_wr_d_last, D_axi_wr_d_ready;
    wire [AXI_DW-1:0]   D_axi_wr_d_data;
    wire [WID_W-1:0]    D_axi_wr_d_id;
    wire [BEAT_B-1:0]   D_axi_wr_strobe;
    wire                D_axi_wr_res_valid, D_axi_wr_res_ready;
    wire [1:0]          D_axi_wr_res_error_info;
    wire [WID_W-1:0]    D_axi_wr_res_addr_id;
    l1d_top_soc dcache_dut (
        .clk(clk),
        .rst(rst),
        .flush(1'b0),
        .clean(clean),
        .valid_cpu(valid_cpu),
        .cachable(cachable),
        .rd_wr_cpu(rd_wr_cpu),
        .mem_size_cpu(mem_size_cpu),
        .master_id_from_cpu(master_id_from_cpu),
        .idx_from_cpu(idx_from_cpu),
        .PC_from_cpu(PC_from_cpu),
        .data_from_cpu(data_from_cpu),
        .amo_cpu(1'b0),
        .amo_seq_cpu(1'b0),
        .amo_op_cpu(4'd0),
        .snp_valid(1'b0),
        .snp_ready(),
        .snp_addr({ADDR_W{1'b0}}),
        .snp_inv(1'b0),
        .snpr_valid(),
        .snpr_ready(1'b1),
        .snpr_addr(),
        .snpr_present(),
        .snpr_dirty(),
        .snpr_data(),
        .axi_arvalid(D_axi_arvalid),
        .axi_araddr(D_axi_araddr),
        .axi_arid(D_axi_arid[RID_W-1:0]),
        .axi_arlen(D_axi_arlen[ARLEN_W-1:0]),
        .axi_arsize(D_axi_arsize),
        .axi_arburst(D_axi_arburst),
        .axi_arlock(D_axi_arlock),
        .axi_arcache(D_axi_arcache),
        .axi_arprot(D_axi_arprot),
        .axi_arqos(D_axi_arqos),
        .axi_aruser(D_axi_aruser),
        .axi_arready(D_axi_arready),
        .axi_rvalid(D_axi_rvalid),
        .axi_rdata(D_axi_rdata),
        .axi_rid(D_axi_rid[RID_W-1:0]),
        .axi_rres(D_axi_rres),
        .axi_rlast(D_axi_rlast),
        .axi_ruser(D_axi_ruser),
        .axi_rready(D_axi_rready),
        .axi_wr_arvalid(D_axi_wr_arvalid),
        .axi_wr_araddr(D_axi_wr_araddr),
        .axi_wr_arid(D_axi_wr_arid[WID_W-1:0]),
        .axi_wr_arlen(D_axi_wr_arlen[ARLEN_W-1:0]),
        .axi_wr_arsize(D_axi_wr_arsize),
        .axi_wr_arburst(D_axi_wr_arburst),
        .axi_wr_arlock(D_axi_wr_arlock),
        .axi_wr_arcache(D_axi_wr_arcache),
        .axi_wr_arprot(D_axi_wr_arprot),
        .axi_wr_arqos(D_axi_wr_arqos),
        .axi_wr_arready(D_axi_wr_arready),
        .axi_wr_d_valid(D_axi_wr_d_valid),
        .axi_wr_d_last(D_axi_wr_d_last),
        .axi_wr_d_data(D_axi_wr_d_data),
        .axi_wr_d_id(D_axi_wr_d_id[WID_W-1:0]),
        .axi_wr_strobe(D_axi_wr_strobe),
        .axi_wr_d_ready(D_axi_wr_d_ready),
        .axi_wr_res_valid(D_axi_wr_res_valid),
        .axi_wr_res_error_info(D_axi_wr_res_error_info),
        .axi_wr_res_addr_id(D_axi_wr_res_addr_id[WID_W-1:0]),
        .axi_wr_res_ready(D_axi_wr_res_ready),
        .stop(stop),
        .read_enable_from_lsu(read_enable_from_lsu),
        .clean_complete(clean_complete),
        .flush_complete(flush_complete),
        .mem_err(mem_err),
        .amo_err(),
        .final_r_cache_hit_from_sheduler(r_valid),
        .final_r_hit_rd_wr_from_sheduler(r_rdwr),
        .final_r_mem_size_from_sheduler(r_size),
        .final_r_master_id_from_sheduler(r_mid),
        .final_r_idx_from_sheduler(r_idx),
        .final_r_data_from_sheduler(r_data)
    );
    wire [WID_W-1:0] m_rid;
    assign D_axi_rid = m_rid[RID_W-1:0];
    axi_mem_model #(.ID_W(WID_W), .ADDR_W(ADDR_W), .DATA_W(AXI_DW), .MEM_BITS(MEM_BITS),
                    .LAT(8), .READY_PCT(70), .SEED(SEED0 + 11), .SHARED_PCT(20),
                    .LINE_BYTES(LINE), .HOLD_N(1)) u_mem (
        .clk(clk), .rst(rst),
        .awid(D_axi_wr_arid), .awaddr(D_axi_wr_araddr),
        .awlen({{(8-ARLEN_W){1'b0}}, D_axi_wr_arlen}), .awsize(D_axi_wr_arsize),
        .awvalid(D_axi_wr_arvalid), .awready(D_axi_wr_arready),
        .wdata(D_axi_wr_d_data), .wstrb(D_axi_wr_strobe), .wlast(D_axi_wr_d_last),
        .wvalid(D_axi_wr_d_valid), .wready(D_axi_wr_d_ready),
        .bid(D_axi_wr_res_addr_id), .bresp(D_axi_wr_res_error_info),
        .bvalid(D_axi_wr_res_valid), .bready(D_axi_wr_res_ready),
        .arid({{(WID_W-RID_W){1'b0}}, D_axi_arid}), .araddr(D_axi_araddr),
        .arlen({{(8-ARLEN_W){1'b0}}, D_axi_arlen}), .arsize(D_axi_arsize), .aruser(D_axi_aruser), .sh_mode(2'd0),
        .arvalid(D_axi_arvalid), .arready(D_axi_arready),
        .rid(m_rid), .rdata(D_axi_rdata), .rresp(D_axi_rres), .rlast(D_axi_rlast), .ruser(D_axi_ruser),
        .rvalid(D_axi_rvalid), .rready(D_axi_rready),
        .hold_v(1'b0), .hold_a({ADDR_W{1'b0}}), .r_busy(), .r_line(),
        .bd_valid(1'b0), .bd_addr({ADDR_W{1'b0}}), .bd_data({(LINE*8){1'b0}}),
        .rdone_valid(), .rdone_line(), .rdone_unique()
    );
    reg [7:0]        ref_mem  [0:(1<<MEM_BITS)-1];
    reg              out_v    [0:NIDX-1];
    reg              out_wr   [0:NIDX-1];
    reg [1:0]        out_size [0:NIDX-1];
    reg [WDW-1:0]    out_exp  [0:NIDX-1];
    reg [ADDR_W-1:0] out_addr [0:NIDX-1];
    integer seed, i, errors, issued, answered, n_out;
    integer n_ar, n_aw, n_w, n_ar1, n_aw1, n_stop;
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
                rand_addr = RANGE_LO + t * TAG_STRIDE + s * SET_STRIDE + b * LINE + off;
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
            cachable           = !nc;
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
        end
    endtask
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
    task check_addr;
        input [8*3-1:0]    ch;
        input [ADDR_W-1:0] a;
        input integer      len;
        input [2:0]        size;
        input [1:0]        burst;
        input              lock;
        input [3:0]        qos;
        input integer      id_hi;
        integer bytes;
        begin
            if (len == 0) bytes = 1 << size;
            else          bytes = (len + 1) * BEAT_B;
            if (a < RANGE_LO || a + bytes - 1 > RANGE_HI) begin
                errors = errors + 1;
                $display("ERROR %0t: %0s addr %h outside 0x20000-0x3FFFF", $time, ch, a);
            end
            if (a % bytes != 0) begin
                errors = errors + 1;
                $display("ERROR %0t: %0s addr %h not aligned to its access (%0d beats, %0d bytes)", $time, ch, a, len + 1, bytes);
            end
            if ((len == 0 ? (size > 3'd3) : (size !== 3'd4)) || burst !== 2'd1 || lock !== 1'b0 || qos !== 4'd0) begin
                errors = errors + 1;
                $display("ERROR %0t: %0s len/size/burst/lock/qos = %0d/%0d/%0d/%0d/%0d (expected size 0-3 for len 0, 4 for a line; 1/0/0)", $time, ch, len, size, burst, lock, qos);
            end
            if (id_hi != 0) begin
                errors = errors + 1;
                $display("ERROR %0t: %0s id has bits set above the v1 id", $time, ch);
            end
        end
    endtask
    always @(posedge clk) begin
        if (!rst) begin
            if (stop) n_stop = n_stop + 1;
            if (D_axi_arvalid && D_axi_arready) begin
                n_ar = n_ar + 1;
                if (D_axi_arlen == 0) n_ar1 = n_ar1 + 1;
                check_addr("AR ", D_axi_araddr, D_axi_arlen, D_axi_arsize, D_axi_arburst,
                           D_axi_arlock, D_axi_arqos, D_axi_arid >> V1_ID_W);
            end
            if (D_axi_wr_arvalid && D_axi_wr_arready) begin
                n_aw = n_aw + 1;
                if (D_axi_wr_arlen == 0) n_aw1 = n_aw1 + 1;
                check_addr("AW ", D_axi_wr_araddr, D_axi_wr_arlen, D_axi_wr_arsize, D_axi_wr_arburst,
                           D_axi_wr_arlock, D_axi_wr_arqos, D_axi_wr_arid >> V1_ID_W);
            end
            if (D_axi_wr_d_valid && D_axi_wr_d_ready) begin
                n_w = n_w + 1;
                if (D_axi_wr_d_id !== D_axi_wr_arid) begin
                    errors = errors + 1;
                    $display("ERROR %0t: W id %h differs from the write in progress %h", $time, D_axi_wr_d_id, D_axi_wr_arid);
                end
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
        integer a, bad;
        begin
            bad = 0;
            for (a = RANGE_LO; a <= RANGE_HI; a = a + 1)
                if (u_mem.mem[a] !== ref_mem[a]) begin
                    if (bad < 10)
                        $display("ERROR: memory @%h = %h, expected %h", a, u_mem.mem[a], ref_mem[a]);
                    bad = bad + 1;
                end
            if (bad != 0) begin
                errors = errors + 1;
                $display("ERROR: %0d bytes differ after clean", bad);
            end
        end
    endtask
    reg nc, wr;
    reg [1:0] size;
    reg [WDW-1:0] wd;
    integer t;
    initial begin
        seed = SEED0;
        errors = 0; issued = 0; answered = 0; n_out = 0;
        n_ar = 0; n_aw = 0; n_w = 0; n_ar1 = 0; n_aw1 = 0; n_stop = 0;
        for (i = 0; i < (1 << MEM_BITS); i = i + 1) ref_mem[i] = pattern(i);
        for (i = 0; i < NIDX; i = i + 1) out_v[i] = 1'b0;
        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (5) @(negedge clk);
        while (issued < N_OPS) begin
            @(negedge clk);
            valid_cpu = 1'b0;
            read_enable_from_lsu = (({$random(seed)} % 100) < 80);
            if (n_out < NIDX && !stop && ({$random(seed)} % 100) < 60) begin
                nc   = (({$random(seed)} % 100) < 10);
                wr   = (({$random(seed)} % 100) < 45);
                size = {$random(seed)} % 4;
                wd   = {$random(seed), $random(seed)};
                issue(nc, wr, size, rand_addr(nc, size), wd);
            end
        end
        @(negedge clk);
        valid_cpu = 1'b0;
        wait_drained;
        clean = 1'b1;
        @(negedge clk);
        clean = 1'b0;
        t = 0;
        while (!clean_complete && t < 200000) begin
            @(posedge clk);
            t = t + 1;
        end
        if (!clean_complete) begin
            errors = errors + 1;
            $display("ERROR: clean never completed");
        end
        repeat (20) @(negedge clk);
        check_memory;
        if (mem_err) begin
            errors = errors + 1;
            $display("ERROR: mem_err is set");
        end
        if (n_ar1 == 0 || n_aw1 == 0 || n_ar == n_ar1 || n_aw == n_aw1) begin
            errors = errors + 1;
            $display("ERROR: coverage: one-beat AR %0d / AW %0d, line AR %0d / AW %0d (each must be > 0)",
                     n_ar1, n_aw1, n_ar - n_ar1, n_aw - n_aw1);
        end
        $display("issued %0d, answered %0d; AR %0d (one-beat %0d), AW %0d (one-beat %0d), W beats %0d; stop cycles %0d",
                 issued, answered, n_ar, n_ar1, n_aw, n_aw1, n_w, n_stop);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
