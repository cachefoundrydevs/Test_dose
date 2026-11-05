`default_nettype none
module l1d_amo_alu #(
    parameter W             = 64,
    parameter MEM_SIZE_BITS = 2
) (
    input  wire [3:0]               amo_op,
    input  wire [MEM_SIZE_BITS-1:0] access_size,
    input  wire [W-1:0]             old_value,
    input  wire [W-1:0]             operand,
    output reg  [W-1:0]             new_value
);
    `include "l1d_encodings.vh"
    localparam HW = W / 2;
    wire is64 = (access_size == 2'd3);
    wire [W-1:0] a_s = is64 ? old_value : {{HW{old_value[HW-1]}}, old_value[HW-1:0]};
    wire [W-1:0] b_s = is64 ? operand   : {{HW{operand[HW-1]}},   operand[HW-1:0]};
    wire [W-1:0] a_u = is64 ? old_value : {{HW{1'b0}}, old_value[HW-1:0]};
    wire [W-1:0] b_u = is64 ? operand   : {{HW{1'b0}}, operand[HW-1:0]};
    wire         lt_s = $signed(a_s) < $signed(b_s);
    wire         lt_u = a_u < b_u;
    always @* begin
        case (amo_op)
            AMO_ADD:  new_value = old_value + operand;
            AMO_XOR:  new_value = old_value ^ operand;
            AMO_AND:  new_value = old_value & operand;
            AMO_OR:   new_value = old_value | operand;
            AMO_MIN:  new_value = lt_s ? old_value : operand;
            AMO_MAX:  new_value = lt_s ? operand : old_value;
            AMO_MINU: new_value = lt_u ? old_value : operand;
            AMO_MAXU: new_value = lt_u ? operand : old_value;
            default:  new_value = operand;
        endcase
    end
endmodule
`default_nettype wire
