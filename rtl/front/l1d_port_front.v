`ifndef L1D_PORT_FRONT_V
`define L1D_PORT_FRONT_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_port_front #(
    `L1D_PARAMS,
    parameter PORT_QUEUE_DEPTH = `L1D_PORT_QUEUE_DEPTH,
    parameter LINE_PORT_ON     = 0
) (
    clk, rst,
    port_request_valid, port_request_packet, port_stop,
    bank_request_valid, bank_request_packet, bank_request_ready,
    port_line_data, bank_request_line_data
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire                           clk;
    input  wire                           rst;
    input  wire [LSU_PORTS-1:0]           port_request_valid;
    input  wire [LSU_PORTS*REQ_W-1:0]     port_request_packet;
    output reg  [LSU_PORTS-1:0]           port_stop;
    output wire [NUM_BANKS-1:0]           bank_request_valid;
    output wire [NUM_BANKS*REQ_W-1:0]     bank_request_packet;
    input  wire [NUM_BANKS-1:0]           bank_request_ready;
    input  wire [LINE_W-1:0]              port_line_data;
    output wire [NUM_BANKS*LINE_W-1:0]    bank_request_line_data;
    wire [LSU_PORTS*BANK_W-1:0] port_bank;
    genvar decode_port;
    generate
        for (decode_port = 0; decode_port < LSU_PORTS; decode_port = decode_port + 1) begin : g_decode
            assign port_bank[decode_port*BANK_W +: BANK_W] =
                port_request_packet[decode_port*REQ_W + REQ_ADDR_LSB + BANK_LSB +: BANK_W];
        end
    endgenerate
    wire [NUM_BANKS*LSU_PORTS-1:0] nearly_full_next;
    genvar room_bank;
    generate
        for (room_bank = 0; room_bank < NUM_BANKS; room_bank = room_bank + 1) begin : g_bank
            wire [LSU_PORTS-1:0] for_this_bank;
            genvar match_port;
            for (match_port = 0; match_port < LSU_PORTS; match_port = match_port + 1) begin : g_match
                assign for_this_bank[match_port] = port_request_valid[match_port] &&
                                                   (port_bank[match_port*BANK_W +: BANK_W] == room_bank);
            end
            l1d_bank_queue #(`L1D_PARAMS_PASS, .BANK_ID(room_bank), .PORT_QUEUE_DEPTH(PORT_QUEUE_DEPTH),
                             .LINE_PORT_ON(LINE_PORT_ON)) u_queue (
                .clk                         (clk),
                .rst                         (rst),
                .port_request_valid          (for_this_bank),
                .port_request_packet         (port_request_packet),
                .bank_request_valid          (bank_request_valid[room_bank]),
                .bank_request_packet         (bank_request_packet[room_bank*REQ_W +: REQ_W]),
                .bank_request_ready          (bank_request_ready[room_bank]),
                .port_queue_nearly_full_next (nearly_full_next[room_bank*LSU_PORTS +: LSU_PORTS]),
                .port_line_data              (port_line_data),
                .bank_request_line_data      (bank_request_line_data[room_bank*LINE_W +: LINE_W])
            );
        end
    endgenerate
    reg     [LSU_PORTS-1:0] stop_next;
    integer stop_port;
    integer stop_bank;
    always @* begin
        stop_next = {LSU_PORTS{1'b0}};
        for (stop_port = 0; stop_port < LSU_PORTS; stop_port = stop_port + 1)
            for (stop_bank = 0; stop_bank < NUM_BANKS; stop_bank = stop_bank + 1)
                if (nearly_full_next[stop_bank*LSU_PORTS + stop_port]) stop_next[stop_port] = 1'b1;
    end
    always @(posedge clk) begin
        if (rst) port_stop <= {LSU_PORTS{1'b0}};
        else     port_stop <= stop_next;
    end
endmodule
`default_nettype wire
`endif
