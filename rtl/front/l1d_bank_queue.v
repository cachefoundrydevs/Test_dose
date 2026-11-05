`ifndef L1D_BANK_QUEUE_V
`define L1D_BANK_QUEUE_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_queue #(
    `L1D_PARAMS,
    parameter BANK_ID          = 0,
    parameter PORT_QUEUE_DEPTH = `L1D_PORT_QUEUE_DEPTH
) (
    clk, rst,
    port_request_valid, port_request_packet,
    bank_request_valid, bank_request_packet, bank_request_ready,
    port_queue_nearly_full_next
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam ORDER_DEPTH = LSU_PORTS * PORT_QUEUE_DEPTH;
    localparam ORDER_PTR_W = (ORDER_DEPTH > 1) ? $clog2(ORDER_DEPTH) : 1;
    localparam QCNT_W      = $clog2(PORT_QUEUE_DEPTH + 1);
    localparam STOP_MARGIN = 2;
    input  wire                          clk;
    input  wire                          rst;
    input  wire [LSU_PORTS-1:0]          port_request_valid;
    input  wire [LSU_PORTS*REQ_W-1:0]    port_request_packet;
    output wire                          bank_request_valid;
    output wire [REQ_W-1:0]              bank_request_packet;
    input  wire                          bank_request_ready;
    output wire [LSU_PORTS-1:0]          port_queue_nearly_full_next;
    wire [LSU_PORTS-1:0]          line_push;
    wire [LSU_PORTS-1:0]          line_pop;
    wire [LSU_PORTS-1:0]          line_empty;
    wire [LSU_PORTS-1:0]          line_full;
    wire [LSU_PORTS*REQ_W-1:0]    line_head_packet;
    wire [LSU_PORTS*QCNT_W-1:0]   line_free_cnt;
    genvar line_port;
    generate
        for (line_port = 0; line_port < LSU_PORTS; line_port = line_port + 1) begin : g_line
            l1d_fifo #(.WIDTH(REQ_W), .DEPTH(PORT_QUEUE_DEPTH), .CNT_W(QCNT_W)) u_line (
                .clk        (clk),
                .rst        (rst),
                .push       (line_push[line_port]),
                .push_data  (port_request_packet[line_port*REQ_W +: REQ_W]),
                .pop        (line_pop[line_port]),
                .front_data (line_head_packet[line_port*REQ_W +: REQ_W]),
                .empty      (line_empty[line_port]),
                .full       (line_full[line_port]),
                .used_slots (),
                .free_slots (line_free_cnt[line_port*QCNT_W +: QCNT_W])
            );
        end
    endgenerate
    wire all_lines_empty = &line_empty;
    reg  [PORT_W-1:0]      order_port [0:ORDER_DEPTH-1];
    reg  [ORDER_PTR_W-1:0] order_read_ptr;
    reg  [ORDER_PTR_W-1:0] order_write_ptr;
    wire [PORT_W-1:0]      oldest_port = order_port[order_read_ptr];
    localparam [ORDER_PTR_W:0] ORDER_DEPTH_C = ORDER_DEPTH;
    function [ORDER_PTR_W-1:0] order_ptr_add;
        input [ORDER_PTR_W-1:0] base_ptr;
        input [ORDER_PTR_W:0]   step_cnt;
        reg   [ORDER_PTR_W:0]   sum_value;
        begin
            sum_value = {1'b0, base_ptr} + step_cnt;
            if (sum_value >= ORDER_DEPTH_C) sum_value = sum_value - ORDER_DEPTH_C;
            order_ptr_add = sum_value[ORDER_PTR_W-1:0];
        end
    endfunction
    wire [LSU_PORTS-1:0] fresh_grant_onehot;
    wire [PORT_W-1:0]    fresh_grant_index;
    wire                 fresh_any;
    wire                 bank_takes_offer = bank_request_valid && bank_request_ready;
    wire                 fresh_issue      = all_lines_empty && fresh_any && bank_request_ready;
    l1d_arb_rr #(.N(LSU_PORTS), .IDX_W(PORT_W)) u_fresh_pick (
        .clk          (clk),
        .rst          (rst),
        .request_bits (port_request_valid),
        .grant_taken  (fresh_issue),
        .grant_onehot (fresh_grant_onehot),
        .grant_index  (fresh_grant_index),
        .any_request  (fresh_any)
    );
    reg [REQ_W-1:0] fresh_packet;
    integer         fresh_port;
    always @* begin
        fresh_packet = {REQ_W{1'b0}};
        for (fresh_port = 0; fresh_port < LSU_PORTS; fresh_port = fresh_port + 1)
            fresh_packet = fresh_packet | ({REQ_W{fresh_grant_onehot[fresh_port]}} & port_request_packet[fresh_port*REQ_W +: REQ_W]);
    end
    reg [REQ_W-1:0] oldest_head_packet;
    integer         head_port;
    always @* begin
        oldest_head_packet = {REQ_W{1'b0}};
        for (head_port = 0; head_port < LSU_PORTS; head_port = head_port + 1)
            if (oldest_port == head_port[PORT_W-1:0])
                oldest_head_packet = line_head_packet[head_port*REQ_W +: REQ_W];
    end
    assign bank_request_valid  = all_lines_empty ? fresh_any : 1'b1;
    assign bank_request_packet = all_lines_empty ? fresh_packet : oldest_head_packet;
    genvar move_port;
    generate
        for (move_port = 0; move_port < LSU_PORTS; move_port = move_port + 1) begin : g_move
            assign line_push[move_port] = port_request_valid[move_port] && !(fresh_issue && fresh_grant_onehot[move_port]);
            assign line_pop[move_port]  = !all_lines_empty && bank_takes_offer && (oldest_port == move_port);
            wire [QCNT_W:0] free_next = {1'b0, line_free_cnt[move_port*QCNT_W +: QCNT_W]}
                                        + {{QCNT_W{1'b0}}, line_pop[move_port]} - {{QCNT_W{1'b0}}, line_push[move_port]};
            assign port_queue_nearly_full_next[move_port] = (free_next < STOP_MARGIN);
        end
    endgenerate
    reg [LSU_PORTS*ORDER_PTR_W-1:0] join_slot_flat;
    reg [ORDER_PTR_W:0]             join_total;
    integer                         slot_port;
    always @* begin
        join_total = {(ORDER_PTR_W+1){1'b0}};
        for (slot_port = 0; slot_port < LSU_PORTS; slot_port = slot_port + 1) begin
            join_slot_flat[slot_port*ORDER_PTR_W +: ORDER_PTR_W] = order_ptr_add(order_write_ptr, join_total);
            join_total = join_total + {{ORDER_PTR_W{1'b0}}, line_push[slot_port]};
        end
    end
    wire [ORDER_PTR_W-1:0] order_write_ptr_next = order_ptr_add(order_write_ptr, join_total);
    wire [ORDER_PTR_W-1:0] order_read_ptr_next  = order_ptr_add(order_read_ptr, {{ORDER_PTR_W{1'b0}}, 1'b1});
    integer write_port;
    always @(posedge clk) begin
        if (rst) begin
            order_read_ptr  <= {ORDER_PTR_W{1'b0}};
            order_write_ptr <= {ORDER_PTR_W{1'b0}};
        end else begin
            for (write_port = 0; write_port < LSU_PORTS; write_port = write_port + 1)
                if (line_push[write_port])
                    order_port[join_slot_flat[write_port*ORDER_PTR_W +: ORDER_PTR_W]] <= write_port[PORT_W-1:0];
            order_write_ptr <= order_write_ptr_next;
            if (!all_lines_empty && bank_takes_offer)
                order_read_ptr <= order_read_ptr_next;
        end
    end
    integer check_port;
    always @(posedge clk) begin
        if (!rst) begin
            for (check_port = 0; check_port < LSU_PORTS; check_port = check_port + 1)
                if (line_push[check_port] && line_full[check_port])
                    $display("[%0t] L1D QUEUE ERROR bank %0d: port %0d sent a request into its full line (stop rule broken)",
                             $time, BANK_ID, check_port);
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst && bank_takes_offer)
            $display("[%0t] L1D QUEUE bank %0d seats port %0d idx=%0d %s addr=%h (%s)", $time, BANK_ID,
                     bank_request_packet[REQ_PORT_LSB +: PORT_W], bank_request_packet[REQ_IDX_LSB +: IDX_BITS],
                     (bank_request_packet[REQ_RDWR_BIT] ? "ST" : "LD"), bank_request_packet[REQ_ADDR_LSB +: ADDR_W],
                     (all_lines_empty ? "fresh" : "from its line"));
    end
`endif
endmodule
`default_nettype wire
`endif
