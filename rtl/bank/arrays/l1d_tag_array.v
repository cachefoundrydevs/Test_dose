`default_nettype none
`include "l1d_defines.vh"
module l1d_tag_array #(
    parameter SETS    = 64,
    parameter WAYS    = 4,
    parameter TAG_W   = 50,
    parameter INDEX_W = $clog2(SETS)
) (
    input  wire                  clk,
    input  wire                  read_enable,
    input  wire [INDEX_W-1:0]    read_set_index,
    input  wire [WAYS-1:0]       way_write_enable,
    input  wire [INDEX_W-1:0]    write_set_index,
    input  wire [TAG_W-1:0]      write_tag,
    output wire [WAYS*TAG_W-1:0] read_tags_flat
);
    genvar w;
    generate
        for (w = 0; w < WAYS; w = w + 1) begin : g_way
            l1d_sram_tdp #(
                .DEPTH  (SETS),
                .COL_W  (TAG_W),
                .NB_COL (1),
                .ADDR_W (INDEX_W)
            ) u_ram (
                .clk     (clk),
                .a_en    (read_enable),
                .a_we    (1'b0),
                .a_addr  (read_set_index),
                .a_wdata ({TAG_W{1'b0}}),
                .a_rdata (read_tags_flat[w*TAG_W +: TAG_W]),
                .b_en    (way_write_enable[w]),
                .b_we    (way_write_enable[w]),
                .b_addr  (write_set_index),
                .b_wdata (write_tag),
                .b_rdata ()
            );
        end
    endgenerate
`ifdef L1D_DEBUG
    always @(posedge clk)
        if (|way_write_enable)
            $display("[%0t] L1D TAG  %m write set=%0d ways=%b tag=%h", $time, write_set_index, way_write_enable, write_tag);
`endif
endmodule
`default_nettype wire
