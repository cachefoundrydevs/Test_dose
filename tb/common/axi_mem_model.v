`timescale 1ns/1ps
module axi_mem_model #(
    parameter ID_W      = 6,
    parameter ADDR_W    = 64,
    parameter DATA_W    = 128,
    parameter MEM_BITS  = 20,
    parameter LAT       = 8,
    parameter READY_PCT = 70,
    parameter SEED      = 1,
    parameter SHARED_PCT = 0,
    parameter LINE_BYTES = 64,
    parameter HOLD_N    = 1
) (
    input  wire              clk,
    input  wire              rst,
    input  wire [ID_W-1:0]   awid,
    input  wire [ADDR_W-1:0] awaddr,
    input  wire [7:0]        awlen,
    input  wire [2:0]        awsize,
    input  wire              awvalid,
    output reg               awready,
    input  wire [DATA_W-1:0] wdata,
    input  wire [DATA_W/8-1:0] wstrb,
    input  wire              wlast,
    input  wire              wvalid,
    output reg               wready,
    output reg  [ID_W-1:0]   bid,
    output reg  [1:0]        bresp,
    output reg               bvalid,
    input  wire              bready,
    input  wire [ID_W-1:0]   arid,
    input  wire [ADDR_W-1:0] araddr,
    input  wire [7:0]        arlen,
    input  wire [2:0]        arsize,
    input  wire              aruser,
    input  wire [1:0]        sh_mode,
    input  wire              arvalid,
    output reg               arready,
    output reg  [ID_W-1:0]   rid,
    output reg  [DATA_W-1:0] rdata,
    output reg  [1:0]        rresp,
    output reg               rlast,
    output reg               ruser,
    output reg               rvalid,
    input  wire              rready,
    input  wire [HOLD_N-1:0]        hold_v,
    input  wire [HOLD_N*ADDR_W-1:0] hold_a,
    output wire                     r_busy,
    output wire [ADDR_W-1:0]        r_line,
    input  wire                     bd_valid,
    input  wire [ADDR_W-1:0]        bd_addr,
    input  wire [LINE_BYTES*8-1:0]  bd_data,
    output reg                      rdone_valid,
    output reg  [ADDR_W-1:0]        rdone_line,
    output reg                      rdone_unique
);
    localparam MEM_BYTES = (1 << MEM_BITS);
    localparam STRB      = DATA_W / 8;
    localparam QD        = 16;
    reg [7:0] mem [0:MEM_BYTES-1];
    integer   seed;
    integer   i;
    function [7:0] pattern;
        input integer a;
        begin
            pattern = (a * 37) ^ (a >> 7) ^ 8'h5A;
        end
    endfunction
    initial begin
        seed = SEED;
        for (i = 0; i < MEM_BYTES; i = i + 1)
            mem[i] = pattern(i);
    end
    function integer rnd_pct;
        input integer dummy;
        begin
            rnd_pct = (({$random(seed)} % 100) < READY_PCT) ? 1 : 0;
        end
    endfunction
    reg              rq_v   [0:QD-1];
    reg [ID_W-1:0]   rq_id  [0:QD-1];
    reg [ADDR_W-1:0] rq_ad  [0:QD-1];
    reg [7:0]        rq_len [0:QD-1];
    reg [2:0]        rq_sz  [0:QD-1];
    reg [31:0]       rq_seq [0:QD-1];
    reg              rq_uq  [0:QD-1];
    reg              rq_sh  [0:QD-1];
    reg [31:0]       seq_n;
    reg              r_act;
    reg [4:0]        r_slot;
    reg [7:0]        r_beat;
    integer          r_wait;
    integer          nfree;
    integer          fslot;
    integer          k, j, cand, nc;
    reg              older_same;
    reg              held;
    integer          h;
    function [ADDR_W-1:0] line_of;
        input [ADDR_W-1:0] a;
        begin
            line_of = a & ~(LINE_BYTES - 1);
        end
    endfunction
    assign r_busy = r_act;
    assign r_line = line_of(rq_ad[r_slot]);
    task pick_burst;
        begin
            cand = -1;
            nc   = 0;
            for (k = 0; k < QD; k = k + 1) begin
                if (rq_v[k]) begin
                    older_same = 0;
                    for (j = 0; j < QD; j = j + 1)
                        if (rq_v[j] && j != k && rq_id[j] == rq_id[k] && rq_seq[j] < rq_seq[k])
                            older_same = 1;
                    held = 0;
                    for (h = 0; h < HOLD_N; h = h + 1)
                        if (hold_v[h] === 1'b1 && line_of(hold_a[h*ADDR_W +: ADDR_W]) == line_of(rq_ad[k]))
                            held = 1;
                    if (!older_same && !held) begin
                        nc = nc + 1;
                        if (({$random(seed)} % nc) == 0) cand = k;
                    end
                end
            end
        end
    endtask
    function [DATA_W-1:0] read_beat;
        input [ADDR_W-1:0] a;
        integer b;
        reg [MEM_BITS-1:0] base;
        begin
            base = a[MEM_BITS-1:0] & ~(STRB - 1);
            for (b = 0; b < STRB; b = b + 1)
                read_beat[b*8 +: 8] = mem[base + b];
        end
    endfunction
    always @(posedge clk) begin
        if (rst) begin
            for (k = 0; k < QD; k = k + 1) rq_v[k] <= 1'b0;
            arready <= 1'b0;
            rvalid  <= 1'b0;
            r_act   <= 1'b0;
            seq_n   <= 0;
            r_slot  <= 0;
            rdone_valid <= 1'b0;
        end else begin
            if (arvalid && arready) begin
                fslot = -1;
                for (k = QD - 1; k >= 0; k = k - 1) if (!rq_v[k]) fslot = k;
                rq_v[fslot]   <= 1'b1;
                rq_id[fslot]  <= arid;
                rq_ad[fslot]  <= araddr;
                rq_len[fslot] <= arlen;
                rq_sz[fslot]  <= arsize;
                rq_seq[fslot] <= seq_n;
                rq_uq[fslot]  <= (aruser === 1'b1);
                rq_sh[fslot]  <= (aruser !== 1'b1) && (arlen != 0) &&
                                 ((sh_mode === 2'd2) ? 1'b1 :
                                  (sh_mode === 2'd1) ? 1'b0 : (({$random(seed)} % 100) < SHARED_PCT));
                seq_n         <= seq_n + 1;
            end
            nfree = 0;
            for (k = 0; k < QD; k = k + 1) if (!rq_v[k]) nfree = nfree + 1;
            arready <= (nfree > 1) && rnd_pct(0);
            rdone_valid <= 1'b0;
            if (rvalid && rready) begin
                rvalid <= 1'b0;
                if (rlast) begin
                    r_act        <= 1'b0;
                    rq_v[r_slot] <= 1'b0;
                    if (rq_len[r_slot] != 0) begin
                        rdone_valid  <= 1'b1;
                        rdone_line   <= line_of(rq_ad[r_slot]);
                        rdone_unique <= rq_uq[r_slot] || !rq_sh[r_slot];
                    end
                end else begin
                    r_beat <= r_beat + 1'b1;
                end
            end else if (!r_act) begin
                pick_burst;
                if (cand >= 0) begin
                    r_act  <= 1'b1;
                    r_slot <= cand;
                    r_beat <= 8'd0;
                    r_wait <= LAT;
                end
            end else if (r_wait > 0) begin
                r_wait <= r_wait - 1;
            end else if (!rvalid && rnd_pct(0)) begin
                rvalid <= 1'b1;
                rid    <= rq_id[r_slot];
                rresp  <= 2'b00;
                rlast  <= (r_beat == rq_len[r_slot]);
                ruser  <= rq_sh[r_slot];
                rdata  <= read_beat(rq_ad[r_slot] + r_beat * (1 << rq_sz[r_slot]));
            end
        end
    end
    reg [ID_W-1:0]   wq_id  [0:QD-1];
    reg [ADDR_W-1:0] wq_ad  [0:QD-1];
    reg [2:0]        wq_sz  [0:QD-1];
    reg [4:0]        wq_head, wq_tail;
    reg [5:0]        wq_cnt;
    reg [7:0]        w_beat;
    reg [ID_W-1:0]   bq_id  [0:QD-1];
    reg [4:0]        bq_head, bq_tail;
    reg [5:0]        bq_cnt;
    reg [MEM_BITS-1:0] wbase;
    integer            s;
    reg                b_push;
    integer            wq_next;
    always @(posedge clk) begin
        if (rst) begin
            awready <= 1'b0;
            wready  <= 1'b0;
            bvalid  <= 1'b0;
            wq_head <= 0; wq_tail <= 0; wq_cnt <= 0;
            bq_head <= 0; bq_tail <= 0; bq_cnt <= 0;
            w_beat  <= 0;
        end else begin
            b_push = 1'b0;
            if (awvalid && awready) begin
                wq_id[wq_tail] <= awid;
                wq_ad[wq_tail] <= awaddr;
                wq_sz[wq_tail] <= awsize;
                wq_tail        <= (wq_tail + 1) % QD;
            end
            if (bd_valid === 1'b1) begin
                wbase = bd_addr[MEM_BITS-1:0] & ~(LINE_BYTES - 1);
                for (s = 0; s < LINE_BYTES; s = s + 1)
                    mem[wbase + s] <= bd_data[s*8 +: 8];
            end
            if (wvalid && wready) begin
                wbase = (wq_ad[wq_head][MEM_BITS-1:0] + w_beat * (1 << wq_sz[wq_head])) & ~(STRB - 1);
                for (s = 0; s < STRB; s = s + 1)
                    if (wstrb[s]) mem[wbase + s] <= wdata[s*8 +: 8];
                if (wlast) begin
                    w_beat         <= 0;
                    wq_head        <= (wq_head + 1) % QD;
                    bq_id[bq_tail] <= wq_id[wq_head];
                    bq_tail        <= (bq_tail + 1) % QD;
                    b_push = 1'b1;
                end else begin
                    w_beat <= w_beat + 1;
                end
            end
            wq_next = wq_cnt + ((awvalid && awready) ? 1 : 0) - ((wvalid && wready && wlast) ? 1 : 0);
            wq_cnt  <= wq_next;
            awready <= (wq_next < QD - 2) && rnd_pct(0);
            wready  <= (wq_next > 0) && rnd_pct(0);
            if (bvalid && bready) begin
                bvalid  <= 1'b0;
                bq_head <= (bq_head + 1) % QD;
            end
            bq_cnt <= bq_cnt + (b_push ? 1 : 0) - ((bvalid && bready) ? 1 : 0);
            if (!(bvalid && bready) && !bvalid && (bq_cnt != 0) && rnd_pct(0)) begin
                bvalid <= 1'b1;
                bid    <= bq_id[bq_head];
                bresp  <= 2'b00;
            end
        end
    end
endmodule
