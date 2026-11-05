`default_nettype none
`include "l1d_defines.vh"
module l1d_snoop_ctrl #(`L1D_PARAMS) (
    clk, rst,
    snoop_request_valid, snoop_request_ready, snoop_request_addr, snoop_request_invalidate,
    bank_snoop_valid, bank_snoop_line_addr, bank_snoop_invalidate, bank_snoop_ready,
    bank_snoop_response_valid, bank_snoop_response_packet, bank_snoop_response_fifo_free,
    snoop_response_valid, snoop_response_ready, snoop_response_addr, snoop_response_present, snoop_response_dirty, snoop_response_data
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam NB = NUM_BANKS;
    localparam [OFFSET_W-1:0] OFF0 = {OFFSET_W{1'b0}};
    input  wire                     clk;
    input  wire                     rst;
    input  wire                     snoop_request_valid;
    output wire                     snoop_request_ready;
    input  wire [ADDR_W-1:0]        snoop_request_addr;
    input  wire                     snoop_request_invalidate;
    output wire [NB-1:0]            bank_snoop_valid;
    output wire [LINE_ADDR_W-1:0]   bank_snoop_line_addr;
    output wire                     bank_snoop_invalidate;
    input  wire [NB-1:0]            bank_snoop_ready;
    input  wire [NB-1:0]            bank_snoop_response_valid;
    input  wire [NB*SNPR_W-1:0]     bank_snoop_response_packet;
    output wire [NB*SNPR_CNT_W-1:0] bank_snoop_response_fifo_free;
    output reg                      snoop_response_valid;
    input  wire                     snoop_response_ready;
    output wire [ADDR_W-1:0]        snoop_response_addr;
    output wire                     snoop_response_present;
    output wire                     snoop_response_dirty;
    output wire [LINE_W-1:0]        snoop_response_data;
    wire [BANK_W-1:0] r_bank = snoop_request_addr[BANK_LSB +: BANK_W];
    wire              en     = (HAS_SNOOP != 0);
    genvar b;
    generate
        for (b = 0; b < NB; b = b + 1) begin : g_route
            assign bank_snoop_valid[b] = en && snoop_request_valid && (r_bank == b);
        end
    endgenerate
    assign bank_snoop_line_addr = snoop_request_addr[OFFSET_W +: LINE_ADDR_W];
    assign bank_snoop_invalidate  = snoop_request_invalidate;
    assign snoop_request_ready   = en && bank_snoop_ready[r_bank];
    localparam RD = (SNP_RESP_DEPTH < 2) ? 2 : SNP_RESP_DEPTH;
    wire [NB-1:0]        f_empty;
    wire [NB*SNPR_W-1:0] f_dout;
    wire [NB-1:0]        f_pop;
    wire                 load = !snoop_response_valid || snoop_response_ready;
    wire [NB-1:0]     sel_gnt;
    wire [BANK_W-1:0] sel_idx;
    wire              sel_any;
    l1d_arb_rr #(.N(NB), .IDX_W(BANK_W)) u_arb (
        .clk          (clk),
        .rst          (rst),
        .request_bits (~f_empty),
        .grant_taken  (load),
        .grant_onehot (sel_gnt),
        .grant_index  (sel_idx),
        .any_request  (sel_any)
    );
    generate
        for (b = 0; b < NB; b = b + 1) begin : g_fifo
            l1d_fifo #(.WIDTH(SNPR_W), .DEPTH(RD), .CNT_W(SNPR_CNT_W), .POP_LAST(1)) u_fifo (
                .clk        (clk),
                .rst        (rst),
                .push       (bank_snoop_response_valid[b]),
                .push_data  (bank_snoop_response_packet[b*SNPR_W +: SNPR_W]),
                .pop        (f_pop[b]),
                .front_data (f_dout[b*SNPR_W +: SNPR_W]),
                .empty      (f_empty[b]),
                .full       (),
                .used_slots (),
                .free_slots (bank_snoop_response_fifo_free[b*SNPR_CNT_W +: SNPR_CNT_W])
            );
            assign f_pop[b] = load && sel_gnt[b];
        end
    endgenerate
    reg [SNPR_W-1:0] sel_pkt;
    integer k;
    always @* begin
        sel_pkt = {SNPR_W{1'b0}};
        for (k = 0; k < NB; k = k + 1)
            sel_pkt = sel_pkt | ({SNPR_W{sel_gnt[k]}} & f_dout[k*SNPR_W +: SNPR_W]);
    end
    reg [SNPR_W-1:0] out_pkt;
    always @(posedge clk) begin
        if (rst) begin
            snoop_response_valid <= 1'b0;
            out_pkt    <= {SNPR_W{1'b0}};
        end else if (load) begin
            snoop_response_valid <= sel_any;
            if (sel_any)
                out_pkt <= sel_pkt;
        end
    end
    assign snoop_response_addr    = {out_pkt[SNPR_LINE_LSB +: LINE_ADDR_W], OFF0};
    assign snoop_response_present = out_pkt[SNPR_PRES_BIT];
    assign snoop_response_dirty   = out_pkt[SNPR_DIRTY_BIT];
    assign snoop_response_data    = out_pkt[SNPR_DATA_LSB +: LINE_W];
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            if (snoop_request_valid && snoop_request_ready)
                $display("[%0t] L1D SNPC snoop %s addr=%h -> bank %0d", $time,
                         snoop_request_invalidate ? "INV " : "READ", snoop_request_addr, r_bank);
            if (snoop_response_valid && snoop_response_ready)
                $display("[%0t] L1D SNPC answer addr=%h present=%b dirty=%b", $time,
                         snoop_response_addr, snoop_response_present, snoop_response_dirty);
        end
    end
`endif
endmodule
`default_nettype wire
