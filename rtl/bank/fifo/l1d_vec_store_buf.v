`ifndef L1D_VEC_STORE_BUF_V
`define L1D_VEC_STORE_BUF_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_vec_store_buf #(
    `L1D_PARAMS,
    parameter BANK_ID = 0
) (
    clk, rst,
    write_valid, write_line_data, slot_available, write_slot,
    read_slot, read_line_data,
    release_valid, release_slot
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire                   clk;
    input  wire                   rst;
    input  wire                   write_valid;
    input  wire [LINE_W-1:0]      write_line_data;
    output wire                   slot_available;
    output reg  [VEC_SLOT_W-1:0]  write_slot;
    input  wire [VEC_SLOT_W-1:0]  read_slot;
    output reg  [LINE_W-1:0]      read_line_data;
    input  wire                   release_valid;
    input  wire [VEC_SLOT_W-1:0]  release_slot;
    reg [VEC_SLOTS-1:0] slot_used;
    reg [LINE_W-1:0]    slot_line [0:VEC_SLOTS-1];
    integer free_scan;
    always @* begin
        write_slot = {VEC_SLOT_W{1'b0}};
        for (free_scan = VEC_SLOTS - 1; free_scan >= 0; free_scan = free_scan - 1)
            if (!slot_used[free_scan]) write_slot = free_scan[VEC_SLOT_W-1:0];
    end
    assign slot_available = ~&slot_used;
    always @(posedge clk) begin
        if (rst) begin
            slot_used <= {VEC_SLOTS{1'b0}};
        end else begin
            if (release_valid) slot_used[release_slot] <= 1'b0;
            if (write_valid)   slot_used[write_slot]   <= 1'b1;
        end
    end
    always @(posedge clk) begin
        if (write_valid) slot_line[write_slot] <= write_line_data;
    end
    integer read_scan;
    always @* begin
        read_line_data = {LINE_W{1'b0}};
        for (read_scan = 0; read_scan < VEC_SLOTS; read_scan = read_scan + 1)
            read_line_data = read_line_data | ({LINE_W{read_slot == read_scan[VEC_SLOT_W-1:0]}} & slot_line[read_scan]);
    end
    always @(posedge clk) begin
        if (!rst) begin
            if (write_valid && !slot_available)
                $display("[%0t] L1D VECBUF ERROR bank %0d: a vector store entered while all %0d places were used", $time, BANK_ID, VEC_SLOTS);
            if (release_valid && !slot_used[release_slot])
                $display("[%0t] L1D VECBUF ERROR bank %0d: release of free place %0d", $time, BANK_ID, release_slot);
        end
    end
endmodule
`default_nettype wire
`endif
