`default_nettype none
`include "l1d_defines.vh"
module l1d_resp_merge #(`L1D_PARAMS) (
    clk, rst,
    bank_response_valid, bank_response_packet, bank_response_fifo_free,
    merged_response_valid, merged_response_packet, lsu_read_enable
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire                       clk;
    input  wire                       rst;
    input  wire [NUM_BANKS-1:0]       bank_response_valid;
    input  wire [NUM_BANKS*RESP_W-1:0] bank_response_packet;
    output wire [NUM_BANKS*RCNT_W-1:0] bank_response_fifo_free;
    output reg                        merged_response_valid;
    output reg  [RESP_W-1:0]          merged_response_packet;
    input  wire                       lsu_read_enable;
    wire [NUM_BANKS-1:0]        f_empty;
    wire [NUM_BANKS*RESP_W-1:0] f_dout;
    wire [NUM_BANKS-1:0]        f_pop;
    wire [NUM_BANKS-1:0]        head_v;
    wire [NUM_BANKS*RESP_W-1:0] head_d;
    wire [NUM_BANKS-1:0]        byp;
    wire load = !merged_response_valid || lsu_read_enable;
    wire [NUM_BANKS-1:0] sel_gnt;
    wire [BANK_W-1:0]    sel_idx;
    wire                 sel_any;
    l1d_arb_rr #(.N(NUM_BANKS), .IDX_W(BANK_W)) u_arb (
        .clk          (clk),
        .rst          (rst),
        .request_bits (head_v),
        .grant_taken  (load),
        .grant_onehot (sel_gnt),
        .grant_index  (sel_idx),
        .any_request  (sel_any)
    );
    genvar b;
    generate
        for (b = 0; b < NUM_BANKS; b = b + 1) begin : g_fifo
            l1d_fifo #(.WIDTH(RESP_W), .DEPTH(RESP_FIFO_DEPTH), .CNT_W(RCNT_W), .POP_LAST(1)) u_fifo (
                .clk        (clk),
                .rst        (rst),
                .push       (bank_response_valid[b] && !byp[b]),
                .push_data  (bank_response_packet[b*RESP_W +: RESP_W]),
                .pop        (f_pop[b]),
                .front_data (f_dout[b*RESP_W +: RESP_W]),
                .empty      (f_empty[b]),
                .full       (),
                .used_slots (),
                .free_slots (bank_response_fifo_free[b*RCNT_W +: RCNT_W])
            );
            assign f_pop[b] = load && sel_gnt[b] && !f_empty[b];
            assign head_v[b] = !f_empty[b] || bank_response_valid[b];
            assign head_d[b*RESP_W +: RESP_W] = f_empty[b] ? bank_response_packet[b*RESP_W +: RESP_W] : f_dout[b*RESP_W +: RESP_W];
            assign byp[b]    = f_empty[b] && load && sel_gnt[b];
        end
    endgenerate
    reg [RESP_W-1:0] sel_resp;
    integer          k;
    always @* begin
        sel_resp = {RESP_W{1'b0}};
        for (k = 0; k < NUM_BANKS; k = k + 1)
            sel_resp = sel_resp | ({RESP_W{sel_gnt[k]}} & head_d[k*RESP_W +: RESP_W]);
    end
    always @(posedge clk) begin
        if (rst) begin
            merged_response_valid <= 1'b0;
            merged_response_packet  <= {RESP_W{1'b0}};
        end else if (load) begin
            merged_response_valid <= sel_any;
            if (sel_any)
                merged_response_packet <= sel_resp;
        end
    end
`ifdef L1D_DEBUG
    integer dbg_hold;
    initial dbg_hold = 0;
    always @(posedge clk) begin
        if (!rst) begin
            if (load && sel_any)
                $display("[%0t] L1D MERGE bank %0d -> output  idx=%0d %s (visible next cycle)",
                         $time, sel_idx, head_d[sel_idx*RESP_W + RESP_IDX_LSB +: IDX_BITS],
                         head_d[sel_idx*RESP_W + RESP_RDWR_BIT] ? "ST-ack" : "LD");
            if (merged_response_valid && !lsu_read_enable) begin
                dbg_hold = dbg_hold + 1;
                if (dbg_hold % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D MERGE STUCK output idx=%0d held %0d cycles: read_enable_from_lsu=%b",
                             $time, merged_response_packet[RESP_IDX_LSB +: IDX_BITS], dbg_hold, lsu_read_enable);
            end else dbg_hold = 0;
        end
    end
`endif
endmodule
`default_nettype wire
