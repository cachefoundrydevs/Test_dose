`default_nettype none
`include "l1d_defines.vh"
module l1d_meta_flops #(
    parameter SETS    = 64,
    parameter WAYS    = 4,
    parameter INDEX_W = $clog2(SETS),
    parameter WAY_W   = $clog2(WAYS),
    parameter NB      = WAYS - 1
) (
    input  wire               clk,
    input  wire               rst,
    input  wire [INDEX_W-1:0] read_set,
    output wire [2*WAYS-1:0]  read_way_states_flat,
    output wire [NB-1:0]      read_plru_bits,
    input  wire               state_write_enable,
    input  wire [INDEX_W-1:0] state_write_set,
    input  wire [WAY_W-1:0]   state_write_way,
    input  wire [1:0]         state_write_value,
    input  wire               plru_write_enable,
    input  wire [INDEX_W-1:0] plru_write_set,
    input  wire [NB-1:0]      plru_write_value
);
    reg [2*WAYS-1:0] states [0:SETS-1];
    reg [NB-1:0]     plru   [0:SETS-1];
    integer s;
    always @(posedge clk) begin
        if (rst) begin
            for (s = 0; s < SETS; s = s + 1) begin
                states[s] <= {2*WAYS{1'b0}};
                plru[s]   <= {NB{1'b0}};
            end
        end else begin
            if (state_write_enable)
                states[state_write_set][2*state_write_way +: 2] <= state_write_value;
            if (plru_write_enable)
                plru[plru_write_set] <= plru_write_value;
        end
    end
    assign read_way_states_flat = states[read_set];
    assign read_plru_bits   = plru[read_set];
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst && state_write_enable && states[state_write_set][2*state_write_way +: 2] != state_write_value)
            $display("[%0t] L1D META %m set=%0d way=%0d state %0d -> %0d",
                     $time, state_write_set, state_write_way, states[state_write_set][2*state_write_way +: 2], state_write_value);
    end
`endif
endmodule
`default_nettype wire
