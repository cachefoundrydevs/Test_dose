`default_nettype none
`include "l1d_defines.vh"
module l1d_fifo_stage #(`L1D_PARAMS) (
    clk, rst,
    lsu_new_request_valid, lsu_new_request_packet, lsu_new_request_ready,
    lsu_offer_valid, lsu_offer_seat, lsu_offer_request_packet, lsu_offer_granted,
    lsu_s2_action_valid, lsu_s2_action_seat, lsu_s2_action_code, lsu_s2_action_wait_id,
    lsu_s3_done_valid, lsu_s3_done_seat,
    amo_lock_valid, amo_lock_line,
    lsu_buffer_empty, lsu_new_request_granted, lsu_new_request_seat, lsu_seat_blocked,
    snoop_new_valid, snoop_new_line_addr, snoop_new_invalidate, snoop_new_ready,
    amo_lock_snoop_hold, amo_read_in_pipeline, amo_lock_set_valid, amo_lock_set_line,
    snoop_offer_valid, snoop_offer_entry_id, snoop_offer_line_addr, snoop_offer_invalidate, snoop_offer_granted,
    snoop_s2_action_valid, snoop_s2_action_entry_id, snoop_s2_action_code, snoop_s2_action_wait_id,
    snoop_buffer_empty,
    prefetch_new_valid, prefetch_new_line_addr, prefetch_new_ready,
    prefetch_offer_valid, prefetch_offer_line_addr, prefetch_offer_granted,
    mshr_entry_freed, victim_slot_freed, nc_entry_freed
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam PF_DEPTH = (PF_FIFO_DEPTH < 2) ? 2 : PF_FIFO_DEPTH;
    input  wire                    clk;
    input  wire                    rst;
    input  wire                    lsu_new_request_valid;
    input  wire [REQ_W-1:0]        lsu_new_request_packet;
    output wire                    lsu_new_request_ready;
    output wire                    lsu_offer_valid;
    output wire [SEAT_W-1:0]       lsu_offer_seat;
    output wire [REQ_W-1:0]        lsu_offer_request_packet;
    input  wire                    lsu_offer_granted;
    input  wire                    lsu_s2_action_valid;
    input  wire [SEAT_W-1:0]       lsu_s2_action_seat;
    input  wire [2:0]              lsu_s2_action_code;
    input  wire [WID_W-1:0]        lsu_s2_action_wait_id;
    input  wire                    lsu_s3_done_valid;
    input  wire [SEAT_W-1:0]       lsu_s3_done_seat;
    input  wire                    amo_lock_valid;
    input  wire [LINE_ADDR_W-1:0]  amo_lock_line;
    output wire                    lsu_buffer_empty;
    input  wire                    lsu_new_request_granted;
    output wire [SEAT_W-1:0]       lsu_new_request_seat;
    output wire [LSU_BUF_DEPTH-1:0] lsu_seat_blocked;
    input  wire                    snoop_new_valid;
    input  wire [LINE_ADDR_W-1:0]  snoop_new_line_addr;
    input  wire                    snoop_new_invalidate;
    output wire                    snoop_new_ready;
    input  wire                    amo_lock_snoop_hold;
    input  wire                    amo_read_in_pipeline;
    input  wire                    amo_lock_set_valid;
    input  wire [LINE_ADDR_W-1:0]  amo_lock_set_line;
    output wire                    snoop_offer_valid;
    output wire [SNP_ID_W-1:0]     snoop_offer_entry_id;
    output wire [LINE_ADDR_W-1:0]  snoop_offer_line_addr;
    output wire                    snoop_offer_invalidate;
    input  wire                    snoop_offer_granted;
    input  wire                    snoop_s2_action_valid;
    input  wire [SNP_ID_W-1:0]     snoop_s2_action_entry_id;
    input  wire [1:0]              snoop_s2_action_code;
    input  wire [WID_W-1:0]        snoop_s2_action_wait_id;
    output wire                    snoop_buffer_empty;
    input  wire                    prefetch_new_valid;
    input  wire [LINE_ADDR_W-1:0]  prefetch_new_line_addr;
    output wire                    prefetch_new_ready;
    output wire                    prefetch_offer_valid;
    output wire [LINE_ADDR_W-1:0]  prefetch_offer_line_addr;
    input  wire                    prefetch_offer_granted;
    input  wire [MSHR_ENTRIES-1:0] mshr_entry_freed;
    input  wire [VC_SLOTS-1:0]     victim_slot_freed;
    input  wire                    nc_entry_freed;
    l1d_lsu_req_buf #(`L1D_PARAMS_PASS) u_lsu (
        .clk                  (clk),
        .rst                  (rst),
        .new_request_valid    (lsu_new_request_valid),
        .new_request_packet   (lsu_new_request_packet),
        .new_request_ready    (lsu_new_request_ready),
        .offer_valid          (lsu_offer_valid),
        .offer_seat           (lsu_offer_seat),
        .offer_request_packet (lsu_offer_request_packet),
        .offer_granted        (lsu_offer_granted),
        .s2_action_valid      (lsu_s2_action_valid),
        .s2_action_seat       (lsu_s2_action_seat),
        .s2_action_code       (lsu_s2_action_code),
        .s2_action_wait_id    (lsu_s2_action_wait_id),
        .s3_done_valid        (lsu_s3_done_valid),
        .s3_done_seat         (lsu_s3_done_seat),
        .mshr_entry_freed     (mshr_entry_freed),
        .victim_slot_freed    (victim_slot_freed),
        .nc_entry_freed       (nc_entry_freed),
        .amo_lock_valid       (amo_lock_valid),
        .amo_lock_line        (amo_lock_line),
        .amo_lock_set_valid   (amo_lock_set_valid),
        .amo_lock_set_line    (amo_lock_set_line),
        .buffer_empty         (lsu_buffer_empty),
        .new_request_granted  (lsu_new_request_granted),
        .new_request_seat     (lsu_new_request_seat),
        .seat_blocked         (lsu_seat_blocked)
    );
    l1d_snoop_buf #(`L1D_PARAMS_PASS) u_snp (
        .clk                  (clk),
        .rst                  (rst),
        .new_snoop_valid      (snoop_new_valid),
        .new_snoop_line_addr  (snoop_new_line_addr),
        .new_snoop_invalidate (snoop_new_invalidate),
        .new_snoop_ready      (snoop_new_ready),
        .amo_lock_snoop_hold  (amo_lock_snoop_hold),
        .amo_lock_line        (amo_lock_line),
        .amo_read_in_pipeline (amo_read_in_pipeline),
        .amo_lock_set_valid   (amo_lock_set_valid),
        .amo_lock_set_line    (amo_lock_set_line),
        .offer_valid          (snoop_offer_valid),
        .offer_entry_id       (snoop_offer_entry_id),
        .offer_line_addr      (snoop_offer_line_addr),
        .offer_invalidate     (snoop_offer_invalidate),
        .offer_granted        (snoop_offer_granted),
        .s2_action_valid      (snoop_s2_action_valid),
        .s2_action_entry_id   (snoop_s2_action_entry_id),
        .s2_action_code       (snoop_s2_action_code),
        .s2_action_wait_id    (snoop_s2_action_wait_id),
        .mshr_entry_freed     (mshr_entry_freed),
        .victim_slot_freed    (victim_slot_freed),
        .buffer_empty         (snoop_buffer_empty)
    );
    wire pf_empty, pf_full;
    l1d_fifo #(.WIDTH(LINE_ADDR_W), .DEPTH(PF_DEPTH)) u_pf (
        .clk        (clk),
        .rst        (rst),
        .push       (prefetch_new_valid),
        .push_data  (prefetch_new_line_addr),
        .pop        (prefetch_offer_granted),
        .front_data (prefetch_offer_line_addr),
        .empty      (pf_empty),
        .full       (pf_full),
        .used_slots (),
        .free_slots ()
    );
    assign prefetch_new_ready  = !pf_full;
    assign prefetch_offer_valid = !pf_empty;
endmodule
`default_nettype wire
