`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_sel #(`L1D_PARAMS) (
    clk, rst,
    input_queue_empty, input_queue_head, input_queue_pop,
    bank_request_valid, bank_request_packet, bank_request_ready
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire                     clk;
    input  wire                     rst;
    input  wire                     input_queue_empty;
    input  wire [REQ_W-1:0]         input_queue_head;
    output wire                     input_queue_pop;
    output wire [NUM_BANKS-1:0]     bank_request_valid;
    output wire [REQ_W-1:0]         bank_request_packet;
    input  wire [NUM_BANKS-1:0]     bank_request_ready;
    wire [BANK_W-1:0] head_bank = input_queue_head[REQ_ADDR_LSB + BANK_LSB +: BANK_W];
    genvar b;
    generate
        for (b = 0; b < NUM_BANKS; b = b + 1) begin : g_lane
            assign bank_request_valid[b] = !input_queue_empty && (head_bank == b);
        end
    endgenerate
    assign bank_request_packet = input_queue_head;
    assign input_queue_pop    = !input_queue_empty && bank_request_ready[head_bank];
`ifdef L1D_DEBUG
    integer dbg_blk;
    initial dbg_blk = 0;
    always @(posedge clk) begin
        if (!rst) begin
            if (input_queue_pop) begin
                $display("[%0t] L1D SEL  idx=%0d %s addr=%h -> bank %0d",
                         $time, input_queue_head[REQ_IDX_LSB +: IDX_BITS], (input_queue_head[REQ_RDWR_BIT] ? "ST" : "LD"),
                         input_queue_head[REQ_ADDR_LSB +: ADDR_W], head_bank);
                dbg_blk = 0;
            end else if (!input_queue_empty) begin
                dbg_blk = dbg_blk + 1;
                if (dbg_blk % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D SEL  STUCK head idx=%0d waits %0d cycles: bank %0d has no free seat",
                             $time, input_queue_head[REQ_IDX_LSB +: IDX_BITS], dbg_blk, head_bank);
            end
        end
    end
`endif
endmodule
`default_nettype wire
