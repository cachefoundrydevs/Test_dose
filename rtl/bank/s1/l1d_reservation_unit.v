`default_nettype none
`include "l1d_defines.vh"
module l1d_reservation_unit #(`L1D_PARAMS) (
    clk, rst,
    sc_check_line_addr, sc_reservation_matches,
    s2_line_addr, s2_lr_completed, s2_sc_completed, s2_write_completed, s2_amo_read_completed, s2_amo_read_was_hit, s2_amo_write_completed,
    s2_install_valid, s2_install_line_addr,
    s1_clear_valid, s1_clear_line_addr,
    maint_clear,
    other_bank_rsv_clear,
    reservation_valid, reservation_line_addr,
    amo_lock_valid, amo_lock_snoop_hold, amo_lock_line, amo_lock_timeout_pulse
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    localparam TO_W = $clog2(LOCK_TIMEOUT + 1);
    localparam [TO_W-1:0] TO_LAST = LOCK_TIMEOUT - 1;
    localparam [TO_W-1:0] TO_PRELAST = TO_LAST - 1'b1;
    input  wire                   clk;
    input  wire                   rst;
    input  wire [LINE_ADDR_W-1:0] sc_check_line_addr;
    output wire                   sc_reservation_matches;
    input  wire [LINE_ADDR_W-1:0] s2_line_addr;
    input  wire                   s2_lr_completed;
    input  wire                   s2_sc_completed;
    input  wire                   s2_write_completed;
    input  wire                   s2_amo_read_completed;
    input  wire                   s2_amo_read_was_hit;
    input  wire                   s2_amo_write_completed;
    input  wire                   s2_install_valid;
    input  wire [LINE_ADDR_W-1:0] s2_install_line_addr;
    input  wire                   s1_clear_valid;
    input  wire [LINE_ADDR_W-1:0] s1_clear_line_addr;
    input  wire                   maint_clear;
    input  wire                   other_bank_rsv_clear;
    output reg                    reservation_valid;
    output reg  [LINE_ADDR_W-1:0] reservation_line_addr;
    output reg                    amo_lock_valid;
    output reg                    amo_lock_snoop_hold;
    output reg  [LINE_ADDR_W-1:0] amo_lock_line;
    output reg                    amo_lock_timeout_pulse;
    assign sc_reservation_matches = reservation_valid && !other_bank_rsv_clear && (reservation_line_addr == sc_check_line_addr);
    reg                   v_s2;
    reg [LINE_ADDR_W-1:0] l_s2;
    always @* begin
        v_s2 = reservation_valid && !other_bank_rsv_clear;
        l_s2 = reservation_line_addr;
        if (s2_lr_completed) begin
            v_s2 = 1'b1;
            l_s2 = s2_line_addr;
        end else if (s2_sc_completed) begin
            v_s2 = 1'b0;
        end else if (s2_write_completed && reservation_valid && (reservation_line_addr == s2_line_addr)) begin
            v_s2 = 1'b0;
        end
    end
    wire s1_hit_rsv = s1_clear_valid && v_s2 && (l_s2 == s1_clear_line_addr);
    always @(posedge clk) begin
        if (rst) begin
            reservation_valid <= 1'b0;
            reservation_line_addr  <= {LINE_ADDR_W{1'b0}};
        end else begin
            reservation_valid <= v_s2 && !s1_hit_rsv && !maint_clear;
            reservation_line_addr  <= l_s2;
        end
    end
    reg [TO_W-1:0] to_cnt;
    reg            to_last;
    wire           rel_amow = amo_lock_valid && s2_amo_write_completed && (s2_line_addr == amo_lock_line);
    wire           rel_to   = amo_lock_valid && to_last;
    always @(posedge clk) begin
        if (rst) begin
            amo_lock_valid <= 1'b0;
            amo_lock_snoop_hold   <= 1'b0;
            amo_lock_line  <= {LINE_ADDR_W{1'b0}};
            to_cnt     <= {TO_W{1'b0}};
            to_last    <= 1'b0;
            amo_lock_timeout_pulse     <= 1'b0;
        end else begin
            amo_lock_timeout_pulse <= 1'b0;
            if (s2_amo_read_completed) begin
                amo_lock_valid <= 1'b1;
                amo_lock_snoop_hold   <= s2_amo_read_was_hit;
                amo_lock_line  <= s2_line_addr;
            end else if (rel_amow || rel_to) begin
                amo_lock_valid <= 1'b0;
                amo_lock_snoop_hold   <= 1'b0;
                amo_lock_timeout_pulse     <= rel_to && !rel_amow;
            end else if (amo_lock_valid) begin
                if (s2_install_valid && (s2_install_line_addr == amo_lock_line))
                    amo_lock_snoop_hold <= 1'b1;
            end
            if (s2_amo_read_completed) begin
                to_cnt  <= {TO_W{1'b0}};
                to_last <= 1'b0;
            end else if (amo_lock_valid) begin
                to_cnt  <= to_cnt + 1'b1;
                to_last <= (to_cnt == TO_PRELAST);
            end
        end
    end
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            if (s2_lr_completed)
                $display("[%0t] L1D RSV  %m LR sets reservation line=%h", $time, {s2_line_addr, {OFFSET_W{1'b0}}});
            if (s2_sc_completed && reservation_valid)
                $display("[%0t] L1D RSV  %m SC clears reservation", $time);
            if (s2_write_completed && reservation_valid && reservation_line_addr == s2_line_addr)
                $display("[%0t] L1D RSV  %m write to the reserved line clears it", $time);
            if (s1_hit_rsv)
                $display("[%0t] L1D RSV  %m snoop / eviction clears reservation line=%h", $time, {s1_clear_line_addr, {OFFSET_W{1'b0}}});
            if (s2_amo_read_completed)
                $display("[%0t] L1D LOCK %m AMO read locks line=%h (snoop hold %b)", $time, {s2_line_addr, {OFFSET_W{1'b0}}}, s2_amo_read_was_hit);
            if (rel_amow)
                $display("[%0t] L1D LOCK %m AMO write releases line=%h", $time, {amo_lock_line, {OFFSET_W{1'b0}}});
            if (rel_to && !rel_amow)
                $display("[%0t] L1D LOCK %m ERROR lock on line=%h timed out after %0d cycles (AMO write never came)",
                         $time, {amo_lock_line, {OFFSET_W{1'b0}}}, LOCK_TIMEOUT);
            if (amo_lock_valid && !amo_lock_snoop_hold && s2_install_valid && s2_install_line_addr == amo_lock_line)
                $display("[%0t] L1D LOCK %m locked line installed: snoops now held", $time);
        end
    end
`endif
endmodule
`default_nettype wire
