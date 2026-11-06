`default_nettype none

module l1d_sram_tdp #(
    parameter DEPTH  = 64,
    parameter COL_W  = 8,
    parameter NB_COL = 64,
    parameter DATA_W = COL_W * NB_COL,
    parameter ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
    input  wire              clk,
    input  wire              a_en,
    input  wire [NB_COL-1:0] a_we,
    input  wire [ADDR_W-1:0] a_addr,
    input  wire [DATA_W-1:0] a_wdata,
    output wire [DATA_W-1:0] a_rdata,
    input  wire              b_en,
    input  wire [NB_COL-1:0] b_we,
    input  wire [ADDR_W-1:0] b_addr,
    input  wire [DATA_W-1:0] b_wdata,
    output wire [DATA_W-1:0] b_rdata
);
    generate
        if (DEPTH == 64 && DATA_W == 512) begin : g_data
            l1d_macro_data_tdp u_macro (
                .clk(clk),
                .a_en(a_en), .a_we(|a_we), .a_addr(a_addr), .a_wdata(a_wdata), .a_rdata(a_rdata),
                .b_en(b_en), .b_we(|b_we), .b_addr(b_addr), .b_wdata(b_wdata), .b_rdata(b_rdata));
        end else if (DEPTH == 64 && DATA_W == 50) begin : g_tag
            l1d_macro_tag_tdp u_macro (
                .clk(clk),
                .a_en(a_en), .a_we(|a_we), .a_addr(a_addr), .a_wdata(a_wdata), .a_rdata(a_rdata),
                .b_en(b_en), .b_we(|b_we), .b_addr(b_addr), .b_wdata(b_wdata), .b_rdata(b_rdata));
        end else begin : g_unsupported
            l1d_sram_tdp_size_not_supported_by_asap7_flow u_err ();
        end
    endgenerate
endmodule

`default_nettype wire
