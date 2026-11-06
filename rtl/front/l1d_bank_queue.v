`ifndef L1D_BANK_QUEUE_V
`define L1D_BANK_QUEUE_V
`default_nettype none
`include "l1d_defines.vh"
module l1d_bank_queue #(
    `L1D_PARAMS,
    parameter BANK_ID          = 0,
    parameter PORT_QUEUE_DEPTH = `L1D_PORT_QUEUE_DEPTH,
    parameter LINE_PORT_ON     = 0
) (
    clk, rst,
    port_request_valid, port_request_packet,
    bank_request_valid, bank_request_packet, bank_request_ready,
    port_queue_nearly_full_next,
    port_line_data, bank_request_line_data
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam ORDER_NEED  = LSU_PORTS * PORT_QUEUE_DEPTH;
    localparam ORDER_DEPTH = 1 << $clog2(ORDER_NEED);
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
    input  wire [LINE_W-1:0]             port_line_data;
    output wire [LINE_W-1:0]             bank_request_line_data;
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
    reg  [ORDER_DEPTH-1:0] order_read_onehot;
    reg  [ORDER_DEPTH-1:0] order_write_onehot;
    function [ORDER_DEPTH-1:0] rotate_left;
        input [ORDER_DEPTH-1:0] pointer_onehot;
        input integer           step_cnt;
        integer                 bit_idx;
        begin
            for (bit_idx = 0; bit_idx < ORDER_DEPTH; bit_idx = bit_idx + 1)
                rotate_left[(bit_idx + step_cnt) % ORDER_DEPTH] = pointer_onehot[bit_idx];
        end
    endfunction
    reg     [PORT_W-1:0]    oldest_port;
    integer                 read_place;
    always @* begin
        oldest_port = {PORT_W{1'b0}};
        for (read_place = 0; read_place < ORDER_DEPTH; read_place = read_place + 1)
            oldest_port = oldest_port | ({PORT_W{order_read_onehot[read_place]}} & order_port[read_place]);
    end
    reg  [LSU_PORTS-1:0] fresh_onehot;
    integer              prio_port;
    always @* begin
        fresh_onehot = {LSU_PORTS{1'b0}};
        for (prio_port = LSU_PORTS - 1; prio_port >= 0; prio_port = prio_port - 1)
            if (port_request_valid[prio_port]) fresh_onehot = {{(LSU_PORTS-1){1'b0}}, 1'b1} << prio_port;
    end
    wire fresh_any        = |port_request_valid;
    wire bank_takes_offer = bank_request_valid && bank_request_ready;
    wire fresh_issue      = all_lines_empty && fresh_any && bank_request_ready;
    reg [REQ_W-1:0] fresh_packet;
    integer         fresh_port;
    always @* begin
        fresh_packet = {REQ_W{1'b0}};
        for (fresh_port = 0; fresh_port < LSU_PORTS; fresh_port = fresh_port + 1)
            fresh_packet = fresh_packet | ({REQ_W{fresh_onehot[fresh_port]}} & port_request_packet[fresh_port*REQ_W +: REQ_W]);
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
            assign line_push[move_port] = port_request_valid[move_port] && !(fresh_issue && fresh_onehot[move_port]);
            assign line_pop[move_port]  = !all_lines_empty && bank_takes_offer && (oldest_port == move_port);
            wire [QCNT_W:0] free_next = {1'b0, line_free_cnt[move_port*QCNT_W +: QCNT_W]}
                                        + {{QCNT_W{1'b0}}, line_pop[move_port]} - {{QCNT_W{1'b0}}, line_push[move_port]};
            assign port_queue_nearly_full_next[move_port] = (free_next < STOP_MARGIN);
        end
    endgenerate
    generate
        if (LINE_PORT_ON != 0) begin : g_line_data
            wire [LINE_W-1:0] line_data_head;
            l1d_fifo #(.WIDTH(LINE_W), .DEPTH(PORT_QUEUE_DEPTH), .CNT_W(QCNT_W)) u_line_data (
                .clk        (clk),
                .rst        (rst),
                .push       (line_push[LSU_PORTS-1]),
                .push_data  (port_line_data),
                .pop        (line_pop[LSU_PORTS-1]),
                .front_data (line_data_head),
                .empty      (),
                .full       (),
                .used_slots (),
                .free_slots ()
            );
            assign bank_request_line_data = all_lines_empty ? port_line_data : line_data_head;
        end else begin : g_no_line_data
            assign bank_request_line_data = {LINE_W{1'b0}};
        end
    endgenerate
    reg     [ORDER_DEPTH-1:0] place_write_en;
    reg     [ORDER_DEPTH*PORT_W-1:0] place_write_port;
    reg     [ORDER_DEPTH-1:0] port_place_onehot;
    integer                   rank_cnt;
    integer                   join_port;
    integer                   place_idx;
    always @* begin
        place_write_en   = {ORDER_DEPTH{1'b0}};
        place_write_port = {(ORDER_DEPTH*PORT_W){1'b0}};
        rank_cnt = 0;
        for (join_port = 0; join_port < LSU_PORTS; join_port = join_port + 1) begin
            port_place_onehot = rotate_left(order_write_onehot, rank_cnt);
            if (port_request_valid[join_port]) begin
                place_write_en = place_write_en | port_place_onehot;
                for (place_idx = 0; place_idx < ORDER_DEPTH; place_idx = place_idx + 1)
                    if (port_place_onehot[place_idx])
                        place_write_port[place_idx*PORT_W +: PORT_W] = join_port[PORT_W-1:0];
                rank_cnt = rank_cnt + 1;
            end
        end
    end
    wire [ORDER_DEPTH-1:0] order_write_onehot_next = rotate_left(order_write_onehot, rank_cnt);
    wire [ORDER_DEPTH-1:0] order_read_onehot_next  = rotate_left(order_read_onehot, 1);
    integer write_place;
    always @(posedge clk) begin
        if (rst) begin
            order_read_onehot  <= {{(ORDER_DEPTH-1){1'b0}}, 1'b1};
            order_write_onehot <= {{(ORDER_DEPTH-1){1'b0}}, 1'b1};
        end else begin
            for (write_place = 0; write_place < ORDER_DEPTH; write_place = write_place + 1)
                if (place_write_en[write_place])
                    order_port[write_place] <= place_write_port[write_place*PORT_W +: PORT_W];
            order_write_onehot <= order_write_onehot_next;
            if (bank_takes_offer)
                order_read_onehot <= order_read_onehot_next;
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
