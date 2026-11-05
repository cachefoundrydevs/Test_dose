`default_nettype none
module l1d_resp_gen #(
    parameter IN_BYTES         = 64,
    parameter WRITE_DATA_WIDTH = 64,
    parameter MEM_SIZE_BITS    = 2,
    parameter OFF_W            = $clog2(IN_BYTES)
) (
    input  wire [IN_BYTES*8-1:0]       source_block,
    input  wire [OFF_W-1:0]            byte_offset,
    input  wire [MEM_SIZE_BITS-1:0]    access_size,
    output reg  [WRITE_DATA_WIDTH-1:0] load_data
);
    localparam OUT_BYTES = WRITE_DATA_WIDTH / 8;
    wire [IN_BYTES*8-1:0] shifted = source_block >> {byte_offset, 3'b000};
    integer i;
    integer nbytes;
    always @* begin
        nbytes = 1 << access_size;
        for (i = 0; i < OUT_BYTES; i = i + 1)
            load_data[i*8 +: 8] = (i < nbytes) ? shifted[i*8 +: 8] : 8'h00;
    end
endmodule
`default_nettype wire
