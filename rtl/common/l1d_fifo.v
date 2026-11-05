`default_nettype none
`include "l1d_defines.vh"
module l1d_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 4,
    parameter CNT_W = $clog2(DEPTH + 1),
    parameter POP_LAST = 0
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             push,
    input  wire [WIDTH-1:0] push_data,
    input  wire             pop,
    output wire [WIDTH-1:0] front_data,
    output wire             empty,
    output wire             full,
    output wire [CNT_W-1:0] used_slots,
    output wire [CNT_W-1:0] free_slots
);
    localparam [CNT_W-1:0] DEPTH_C  = DEPTH;
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [DEPTH-1:0] wr_oh;
    reg [DEPTH-1:0] rd_oh;
    reg [DEPTH:0]   lvl;
    wire            empty_r = lvl[0];
    wire            full_r  = lvl[DEPTH];
    reg [CNT_W-1:0] cnt;
    reg [CNT_W-1:0] free_r;
    integer i;
    integer j;
    integer k;
    always @* begin
        cnt    = {CNT_W{1'b0}};
        free_r = {CNT_W{1'b0}};
        for (k = 0; k <= DEPTH; k = k + 1)
            if (lvl[k]) begin
                cnt    = cnt    | k[CNT_W-1:0];
                free_r = free_r | (DEPTH_C - k[CNT_W-1:0]);
            end
    end
    wire do_push = push && !full_r;
    wire do_pop  = pop  && !empty_r;
    wire [DEPTH:0] lvl_pl;
    generate
        if (POP_LAST != 0) begin : g_pop_last
            (* keep *) wire [DEPTH:0] lvl_np = do_push ? (lvl << 1) : lvl;
            (* keep *) wire [DEPTH:0] lvl_p  = do_push ? lvl : (lvl >> 1);
            assign lvl_pl = ({(DEPTH+1){do_pop}} & lvl_p) | ({(DEPTH+1){!do_pop}} & lvl_np);
        end else begin : g_pop_std
            assign lvl_pl = lvl;
        end
    endgenerate
    always @(posedge clk) begin
        if (rst) begin
            wr_oh   <= {{(DEPTH-1){1'b0}}, 1'b1};
            rd_oh   <= {{(DEPTH-1){1'b0}}, 1'b1};
            lvl     <= {{DEPTH{1'b0}}, 1'b1};
        end else begin
            if (do_push) begin
                for (i = 0; i < DEPTH; i = i + 1)
                    if (wr_oh[i]) mem[i] <= push_data;
                wr_oh <= (wr_oh << 1) | (wr_oh >> (DEPTH - 1));
            end
            if (do_pop)
                rd_oh <= (rd_oh << 1) | (rd_oh >> (DEPTH - 1));
            if (POP_LAST != 0)
                lvl <= lvl_pl;
            else
                case ({do_push, do_pop})
                    2'b10:   lvl <= lvl << 1;
                    2'b01:   lvl <= lvl >> 1;
                    default: ;
                endcase
        end
    end
    wire [DEPTH*WIDTH-1:0] mem_flat;
    genvar g;
    generate
        for (g = 0; g < DEPTH; g = g + 1) begin : g_flat
            assign mem_flat[g*WIDTH +: WIDTH] = mem[g];
        end
    endgenerate
    reg [WIDTH-1:0] front;
    always @* begin
        front = {WIDTH{1'b0}};
        for (j = 0; j < DEPTH; j = j + 1)
            front = front | (mem_flat[j*WIDTH +: WIDTH] & {WIDTH{rd_oh[j]}});
    end
    assign front_data  = front;
    assign empty       = empty_r;
    assign full        = full_r;
    assign used_slots  = cnt;
    assign free_slots  = free_r;
`ifdef L1D_DEBUG
    always @(posedge clk) begin
        if (!rst) begin
            if (push && cnt == DEPTH_C)
                $display("[%0t] L1D FIFO %m ERROR push while full (depth %0d): entry lost", $time, DEPTH);
            if (pop && cnt == {CNT_W{1'b0}})
                $display("[%0t] L1D FIFO %m ERROR pop while empty", $time);
            if (push === 1'bx || pop === 1'bx)
                $display("[%0t] L1D FIFO %m WARNING push/pop is X", $time);
        end
    end
`endif
endmodule
`default_nettype wire
