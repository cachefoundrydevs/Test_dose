`default_nettype none
`include "l1d_defines.vh"
module l1d_mesi_next (
    input  wire [3:0] event_code,
    input  wire [1:0] current_state,
    input  wire [1:0] install_state,
    output reg  [1:0] next_state,
    output reg        state_write_enable,
    output reg        upgrade_needed,
    output reg        snoop_hands_over_data
);
    `include "l1d_encodings.vh"
    always @* begin
        next_state  = current_state;
        state_write_enable   = 1'b0;
        upgrade_needed  = 1'b0;
        snoop_hands_over_data = 1'b0;
        case (event_code)
            EV_WRITE_HIT: begin
                if (current_state == ST_E) begin
                    next_state = ST_M; state_write_enable = 1'b1;
                end else if (current_state == ST_S) begin
                    next_state = ST_I; state_write_enable = 1'b1; upgrade_needed = 1'b1;
                end
            end
            EV_UNIQ_HIT: begin
                if (current_state == ST_S) begin
                    next_state = ST_I; state_write_enable = 1'b1; upgrade_needed = 1'b1;
                end
            end
            EV_INSTALL: begin
                next_state = install_state; state_write_enable = 1'b1;
            end
            EV_SNP_READ: begin
                if (current_state != ST_I && current_state != ST_S) begin
                    next_state  = ST_S; state_write_enable = 1'b1;
                    snoop_hands_over_data = (current_state == ST_M);
                end
            end
            EV_SNP_INV: begin
                if (current_state != ST_I) begin
                    next_state  = ST_I; state_write_enable = 1'b1;
                    snoop_hands_over_data = (current_state == ST_M);
                end
            end
            EV_CLEAN: begin
                if (current_state == ST_M) begin
                    next_state = ST_E; state_write_enable = 1'b1;
                end
            end
            EV_FLUSH: begin
                if (current_state != ST_I) begin
                    next_state = ST_I; state_write_enable = 1'b1;
                end
            end
            default: ;
        endcase
    end
endmodule
`default_nettype wire
