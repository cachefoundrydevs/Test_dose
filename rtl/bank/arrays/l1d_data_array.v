`default_nettype none
`include "l1d_defines.vh"
module l1d_data_array #(
    parameter SETS       = 64,
    parameter WAYS       = 4,
    parameter LINE_BYTES = 64,
    parameter INDEX_W    = $clog2(SETS),
    parameter WAY_W      = (WAYS > 1) ? $clog2(WAYS) : 1
) (
    input  wire                         clk,
    input  wire                         read_enable,
    input  wire [INDEX_W-1:0]           read_set_index,
    input  wire                         write_enable,
    input  wire [WAY_W-1:0]             write_way,
    input  wire [INDEX_W-1:0]           write_set_index,
    input  wire [LINE_BYTES*8-1:0]      write_line,
    output wire [WAYS*LINE_BYTES*8-1:0] read_lines_flat
);
    localparam LINE_W = LINE_BYTES * 8;
    genvar w;
    generate
        for (w = 0; w < WAYS; w = w + 1) begin : g_way
            wire this_wr = write_enable && (write_way == w);
            l1d_sram_tdp #(
                .DEPTH  (SETS),
                .COL_W  (LINE_W),
                .NB_COL (1),
                .ADDR_W (INDEX_W)
            ) u_ram (
                .clk     (clk),
                .a_en    (read_enable),
                .a_we    (1'b0),
                .a_addr  (read_set_index),
                .a_wdata ({LINE_W{1'b0}}),
                .a_rdata (read_lines_flat[w*LINE_W +: LINE_W]),
                .b_en    (this_wr),
                .b_we    (this_wr),
                .b_addr  (write_set_index),
                .b_wdata (write_line),
                .b_rdata ()
            );
        end
    endgenerate
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (write_enable)
            $display("[%0t] L1D DATA %m line write set/way=%0d/%0d data=%h", $time, write_set_index, write_way, write_line);
    end
`endif
endmodule
`default_nettype wire
