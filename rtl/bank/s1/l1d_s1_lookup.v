`default_nettype none
module l1d_s1_lookup #(
    parameter WAYS  = 4,
    parameter TAG_W = 50,
    parameter WAY_W = $clog2(WAYS),
    parameter NB    = WAYS - 1
) (
    input  wire [WAYS*TAG_W-1:0] way_tags_flat,
    input  wire [2*WAYS-1:0]     way_states_flat,
    input  wire [NB-1:0]         plru_bits,
    input  wire [TAG_W-1:0]      lookup_tag,
    input  wire [WAY_W-1:0]      accessed_way,
    output wire                  hit,
    output wire [WAY_W-1:0]      hit_way,
    output wire [WAY_W-1:0]      victim_way,
    output wire [NB-1:0]         plru_bits_next
);
    wire [WAYS-1:0] valid;
    wire [WAYS-1:0] match;
    genvar w;
    generate
        for (w = 0; w < WAYS; w = w + 1) begin : g_way
            assign valid[w] = (way_states_flat[2*w +: 2] != 2'b00);
            assign match[w] = valid[w] && (way_tags_flat[w*TAG_W +: TAG_W] == lookup_tag);
        end
    endgenerate
    assign hit = |match;
    l1d_pri_enc #(.N(WAYS), .IDX_W(WAY_W)) u_hit (
        .request_bits     (match),
        .lowest_set_index (hit_way),
        .any_set          ()
    );
    wire [WAY_W-1:0] inv_way;
    wire             any_inv;
    l1d_pri_enc #(.N(WAYS), .IDX_W(WAY_W)) u_inv (
        .request_bits     (~valid),
        .lowest_set_index (inv_way),
        .any_set          (any_inv)
    );
    wire [WAY_W-1:0] plru_victim;
    l1d_plru #(.WAYS(WAYS), .WAY_W(WAY_W), .NB(NB)) u_plru (
        .plru_bits      (plru_bits),
        .accessed_way   (accessed_way),
        .victim_way     (plru_victim),
        .plru_bits_next (plru_bits_next)
    );
    assign victim_way = any_inv ? inv_way : plru_victim;
endmodule
`default_nettype wire
