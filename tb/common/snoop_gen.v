`timescale 1ns/1ps
module snoop_gen #(
    parameter ADDR_W     = 64,
    parameter LINE       = 64,
    parameter NB         = 4,
    parameter TAG_STRIDE = 16384,
    parameter SET_STRIDE = 256,
    parameter NT         = 8,
    parameter NS         = 2,
    parameter OPEN_N     = 12,
    parameter COOL       = 2,
    parameter SEED       = 1,
    parameter SNP_PCT    = 10,
    parameter INV_PCT    = 50,
    parameter READY_PCT  = 80,
    parameter FOCUS_PCT  = 40,
    parameter PEND_N     = 1
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     enable,
    input  wire                     focus_v,
    input  wire [ADDR_W-1:0]        focus_a,
    output reg                      snp_valid,
    input  wire                     snp_ready,
    output reg  [ADDR_W-1:0]        snp_addr,
    output reg                      snp_inv,
    input  wire                     snpr_valid,
    output reg                      snpr_ready,
    input  wire [ADDR_W-1:0]        snpr_addr,
    input  wire                     snpr_present,
    input  wire                     snpr_dirty,
    input  wire [LINE*8-1:0]        snpr_data,
    input  wire                     r_busy,
    input  wire [ADDR_W-1:0]        r_line,
    input  wire [PEND_N-1:0]        pend_v,
    input  wire [PEND_N*ADDR_W-1:0] pend_a,
    output reg  [OPEN_N-1:0]        hold_v,
    output reg  [OPEN_N*ADDR_W-1:0] hold_a,
    output wire                     bd_valid,
    output wire [ADDR_W-1:0]        bd_addr,
    output wire [LINE*8-1:0]        bd_data,
    input  wire                     rdone_valid,
    input  wire [ADDR_W-1:0]        rdone_line,
    input  wire                     rdone_unique,
    input  wire                     aw_fire,
    input  wire [ADDR_W-1:0]        aw_addr,
    input  wire [7:0]               aw_len,
    output reg                      ans_valid,
    output reg  [ADDR_W-1:0]        ans_line,
    output reg                      ans_inv,
    output reg                      ans_present,
    output reg                      ans_dirty,
    output wire                     idle,
    output reg  [31:0]              err_cnt
);
    localparam NL = NT * NS * NB;
    localparam [1:0] G_NONE = 2'd0, G_SHARED = 2'd1, G_UNIQUE = 2'd2;
    localparam [1:0] O_FREE = 2'd0, O_PEND = 2'd1, O_OPEN = 2'd2, O_COOL = 2'd3;
    integer seed;
    reg [1:0]        given [0:NL-1];
    reg [1:0]        ost   [0:OPEN_N-1];
    reg [ADDR_W-1:0] oline [0:OPEN_N-1];
    reg              oinv  [0:OPEN_N-1];
    integer          ocool [0:OPEN_N-1];
    integer n_sent, n_inv, n_ans, n_present, n_dirty, n_absent, n_cancel;
    reg [1:0] gs;
    integer   cur;
    integer   k, f, idx;
    reg       busy_line;
    reg       pend_hit;
    function [ADDR_W-1:0] line_of;
        input [ADDR_W-1:0] a;
        begin
            line_of = a & ~(LINE - 1);
        end
    endfunction
    function integer pidx;
        input [ADDR_W-1:0] a;
        integer t, s, b, r;
        begin
            t = a / TAG_STRIDE;
            r = a % TAG_STRIDE;
            s = r / SET_STRIDE;
            r = r % SET_STRIDE;
            b = r / LINE;
            if (t < NT && s < NS && b < NB) pidx = (t * NS + s) * NB + b;
            else                            pidx = -1;
        end
    endfunction
    function [ADDR_W-1:0] rand_line;
        input integer dummy;
        integer t, s, b;
        begin
            t = {$random(seed)} % NT;
            s = {$random(seed)} % NS;
            b = {$random(seed)} % NB;
            rand_line = t * TAG_STRIDE + s * SET_STRIDE + b * LINE;
        end
    endfunction
    wire ans_fire = snpr_valid && snpr_ready;
    assign bd_valid = ans_fire && snpr_dirty;
    assign bd_addr  = line_of(snpr_addr);
    assign bd_data  = snpr_data;
    reg any_open;
    always @* begin
        any_open = (gs != 2'd0);
        for (k = 0; k < OPEN_N; k = k + 1)
            if (ost[k] != O_FREE) any_open = 1'b1;
    end
    assign idle = !any_open;
    always @* begin
        for (k = 0; k < OPEN_N; k = k + 1) begin
            hold_v[k]                 = (ost[k] != O_FREE);
            hold_a[k*ADDR_W +: ADDR_W] = oline[k];
        end
    end
    initial begin
        seed = SEED;
        n_sent = 0; n_inv = 0; n_ans = 0; n_present = 0; n_dirty = 0; n_absent = 0; n_cancel = 0;
    end
    reg [ADDR_W-1:0] cand;
    integer          pi;
    always @(posedge clk) begin
        if (rst) begin
            snp_valid  <= 1'b0;
            snp_addr   <= {ADDR_W{1'b0}};
            snp_inv    <= 1'b0;
            snpr_ready <= 1'b0;
            ans_valid  <= 1'b0;
            gs         <= 2'd0;
            err_cnt    <= 0;
            for (k = 0; k < OPEN_N; k = k + 1) begin
                ost[k]   <= O_FREE;
                oline[k] <= {ADDR_W{1'b0}};
                oinv[k]  <= 1'b0;
                ocool[k] <= 0;
            end
            for (k = 0; k < NL; k = k + 1) given[k] <= G_NONE;
        end else begin
            snpr_ready <= (({$random(seed)} % 100) < READY_PCT);
            ans_valid <= ans_fire;
            if (ans_fire) begin
                n_ans = n_ans + 1;
                f = -1;
                for (k = 0; k < OPEN_N; k = k + 1)
                    if (ost[k] == O_OPEN && oline[k] == line_of(snpr_addr)) f = k;
                ans_line    <= line_of(snpr_addr);
                ans_present <= snpr_present;
                ans_dirty   <= snpr_dirty;
                if (f < 0) begin
                    err_cnt <= err_cnt + 1;
                    ans_inv <= 1'b0;
                    $display("ERROR %0t: snoop answer for line %h, but no snoop on it is open (C1)", $time, snpr_addr);
                end else begin
                    ans_inv  <= oinv[f];
                    ost[f]   <= O_COOL;
                    ocool[f] <= COOL;
                    pi = pidx(line_of(snpr_addr));
                    if (snpr_present) n_present = n_present + 1; else n_absent = n_absent + 1;
                    if (snpr_dirty) n_dirty = n_dirty + 1;
                    if (snpr_dirty && !snpr_present) begin
                        err_cnt <= err_cnt + 1;
                        $display("ERROR %0t: snoop answer dirty but not present, line %h", $time, snpr_addr);
                    end
                    if (pi >= 0) begin
                        if (snpr_dirty && given[pi] != G_UNIQUE) begin
                            err_cnt <= err_cnt + 1;
                            $display("ERROR %0t: dirty snoop answer for line %h, which was never given out unique (C2, view %0d)",
                                     $time, snpr_addr, given[pi]);
                        end
                        if (oinv[f])            given[pi] <= G_NONE;
                        else if (snpr_present)  given[pi] <= G_SHARED;
                        else                    given[pi] <= G_NONE;
                    end
                end
            end
            for (k = 0; k < OPEN_N; k = k + 1)
                if (ost[k] == O_COOL) begin
                    if (ocool[k] <= 1) ost[k] <= O_FREE;
                    else               ocool[k] <= ocool[k] - 1;
                end
            if (rdone_valid) begin
                pi = pidx(rdone_line);
                if (pi >= 0) given[pi] <= rdone_unique ? G_UNIQUE : G_SHARED;
            end
            if (aw_fire && aw_len != 0) begin
                pi = pidx(line_of(aw_addr));
                if (pi >= 0 && given[pi] != G_UNIQUE) begin
                    err_cnt <= err_cnt + 1;
                    $display("ERROR %0t: writeback of line %h, which was never given out unique (C3, view %0d)",
                             $time, aw_addr, given[pi]);
                end
            end
            case (gs)
                2'd0: begin
                    if (enable && (({$random(seed)} % 100) < SNP_PCT)) begin
                        cand = rand_line(0);
                        if (focus_v && (({$random(seed)} % 100) < FOCUS_PCT))
                            cand = line_of(focus_a);
                        f    = -1;
                        busy_line = r_busy && (line_of(r_line) == cand);
                        for (k = 0; k < PEND_N; k = k + 1)
                            if (pend_v[k] === 1'b1 && line_of(pend_a[k*ADDR_W +: ADDR_W]) == cand) busy_line = 1'b1;
                        for (k = 0; k < OPEN_N; k = k + 1) begin
                            if (ost[k] != O_FREE && oline[k] == cand) busy_line = 1'b1;
                            if (ost[k] == O_FREE && f < 0) f = k;
                        end
                        if (!busy_line && f >= 0) begin
                            ost[f]   <= O_PEND;
                            oline[f] <= cand;
                            oinv[f]  <= (({$random(seed)} % 100) < INV_PCT);
                            cur      = f;
                            gs       <= 2'd1;
                        end
                    end
                end
                2'd1: begin
                    pend_hit = 1'b0;
                    for (k = 0; k < PEND_N; k = k + 1)
                        if (pend_v[k] === 1'b1 && line_of(pend_a[k*ADDR_W +: ADDR_W]) == oline[cur]) pend_hit = 1'b1;
                    if ((r_busy && line_of(r_line) == oline[cur]) || pend_hit) begin
                        ost[cur] <= O_FREE;
                        n_cancel = n_cancel + 1;
                        gs <= 2'd0;
                    end else begin
                        snp_valid <= 1'b1;
                        snp_addr  <= oline[cur] + ({$random(seed)} % LINE);
                        snp_inv   <= oinv[cur];
                        gs <= 2'd2;
                    end
                end
                2'd2: begin
                    if (snp_valid && snp_ready) begin
                        snp_valid <= 1'b0;
                        ost[cur]  <= O_OPEN;
                        n_sent = n_sent + 1;
                        if (oinv[cur]) n_inv = n_inv + 1;
                        gs <= 2'd0;
                    end
                end
                default: gs <= 2'd0;
            endcase
        end
    end
endmodule
