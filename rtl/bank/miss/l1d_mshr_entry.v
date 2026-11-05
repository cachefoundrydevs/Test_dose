`define L1D_CHECK_M11
`default_nettype none
`include "l1d_defines.vh"
module l1d_mshr_entry #(`L1D_PARAMS) (
    clk, rst,
    allocate_valid, allocate_line_addr, allocate_is_swap, allocate_swap_line_data, allocate_swap_dirty, allocate_swap_shared, allocate_swap_vc_slot,
    allocate_unique_read, allocate_seat, allocate_is_write, allocate_no_response, allocate_access_size, allocate_master_id, allocate_rob_index, allocate_port, allocate_byte_offset, allocate_store_data,
    axi_read_addr_accepted, axi_read_beat_valid, axi_read_beat_data, axi_read_beat_last, axi_read_beat_error, axi_read_beat_shared,
    response_taken, refill_token_granted, refill_token_held_by_s1, install_done_by_s2,
    entry_busy, entry_line_addr, axi_read_addr_request, axi_read_is_unique, response_request, response_packet, response_seat, refill_token_request,
    axi_read_addr_request_ctrl, response_request_ctrl, refill_token_request_ctrl,
    line_buffer_data, install_state, line_buffer_has_data, entry_is_swap, entry_swap_vc_slot, entry_freed_pulse
);
    `include "l1d_encodings.vh"
    `include "l1d_fields.vh"
    input  wire                        clk;
    input  wire                        rst;
    input  wire                        allocate_valid;
    input  wire [LINE_ADDR_W-1:0]      allocate_line_addr;
    input  wire                        allocate_is_swap;
    input  wire [LINE_W-1:0]           allocate_swap_line_data;
    input  wire                        allocate_swap_dirty;
    input  wire                        allocate_swap_shared;
    input  wire [VC_ID_W-1:0]          allocate_swap_vc_slot;
    input  wire                        allocate_unique_read;
    input  wire [SEAT_W-1:0]           allocate_seat;
    input  wire                        allocate_is_write;
    input  wire                        allocate_no_response;
    input  wire [MEM_SIZE_BITS-1:0]    allocate_access_size;
    input  wire [MASTER_ID_BITS-1:0]   allocate_master_id;
    input  wire [IDX_BITS-1:0]         allocate_rob_index;
    input  wire [PORT_W-1:0]           allocate_port;
    input  wire [OFFSET_W-1:0]         allocate_byte_offset;
    input  wire [WRITE_DATA_WIDTH-1:0] allocate_store_data;
    input  wire                        axi_read_addr_accepted;
    input  wire                        axi_read_beat_valid;
    input  wire [AXI_DATA_W-1:0]       axi_read_beat_data;
    input  wire                        axi_read_beat_last;
    input  wire                        axi_read_beat_error;
    input  wire                        axi_read_beat_shared;
    input  wire                        response_taken;
    input  wire                        refill_token_granted;
    input  wire                        refill_token_held_by_s1;
    input  wire                        install_done_by_s2;
    output wire                        entry_busy;
    output wire [LINE_ADDR_W-1:0]      entry_line_addr;
    output wire                        axi_read_addr_request;
    output wire                        axi_read_is_unique;
    output wire                        response_request;
    output wire [RESP_W-1:0]           response_packet;
    output wire [SEAT_W-1:0]           response_seat;
    output wire                        refill_token_request;
    output wire                        axi_read_addr_request_ctrl;
    output wire                        response_request_ctrl;
    output wire                        refill_token_request_ctrl;
    output wire [LINE_W-1:0]           line_buffer_data;
    output wire [1:0]                  install_state;
    output wire                        line_buffer_has_data;
    output wire                        entry_is_swap;
    output wire [VC_ID_W-1:0]          entry_swap_vc_slot;
    output wire                        entry_freed_pulse;
    localparam [2:0] E_IDLE    = 3'd0;
    localparam [2:0] E_AR      = 3'd1;
    localparam [2:0] E_DATA    = 3'd2;
    localparam [2:0] E_MERGE   = 3'd3;
    localparam [2:0] E_RESP    = 3'd4;
    localparam [2:0] E_TOKEN   = 3'd5;
    localparam [2:0] E_INSTALL = 3'd6;
    reg [2:0]                  state;
    reg [LINE_ADDR_W-1:0]      line_r;
    reg [LINE_W-1:0]           buf_r;
    reg                        dirty_r;
    reg                        shared_r;
    reg                        unique_r;
    reg                        swap_r;
    reg                        nr_r;
    wire                       nr_go;
    reg [VC_ID_W-1:0]          slot_r;
    reg                        err_r;
    reg [BEAT_W-1:0]           beat;
    reg                        busy_r;
    reg                        ar_q;
    reg                        dat_q;
    reg                        mrg_q;
    reg                        rs_q;
    reg                        tk_q;
    reg                        inst_q;
    reg                        ar_arb_q;
    reg                        rs_arb_q;
    reg                        tk_arb_q;
    reg                        ar_c_q, rs_c_q, tk_c_q;
    reg [AXI_BEATS-1:0]        beat_oh;
    reg [SEAT_W-1:0]           p_seat;
    reg                        p_rd_wr;
    reg [MEM_SIZE_BITS-1:0]    p_size;
    reg [MASTER_ID_BITS-1:0]   p_mid;
    reg [IDX_BITS-1:0]         p_idx;
    reg [PORT_W-1:0]           p_port;
    reg [OFFSET_W-1:0]         p_off;
    reg [WRITE_DATA_WIDTH-1:0] p_wdata;
    initial if (AXI_BEATS < 2) $display("ERROR l1d_mshr_entry: the store-merge pipeline needs AXI_BEATS >= 2 (it is %0d)", AXI_BEATS);
    localparam WBYTES = WRITE_DATA_WIDTH / 8;
    localparam BEAT_BYTES = AXI_DATA_W / 8;
    localparam BEAT_OFF_W = $clog2(BEAT_BYTES);
    localparam HI_N = LINE_BYTES / BEAT_BYTES;
    reg  [HI_N-1:0]       off_hi_r;
    reg  [BEAT_BYTES-1:0] off_lo_r;
    reg  [LINE_BYTES-1:0] off_oh_r;
    reg  [WBYTES-1:0]     szk_r;
    reg  [LINE_BYTES-1:0] st_mask;
    reg  [LINE_W-1:0]     st_data;
    reg  [LINE_BYTES-1:0] mask_n;
    reg  [LINE_W-1:0]     data_n;
    integer a, k, b;
    always @(posedge clk) begin
        for (a = 0; a < HI_N; a = a + 1)
            off_hi_r[a] <= (p_off[OFFSET_W-1:BEAT_OFF_W] == a);
        for (a = 0; a < BEAT_BYTES; a = a + 1)
            off_lo_r[a] <= (p_off[BEAT_OFF_W-1:0] == a);
        for (a = 0; a < LINE_BYTES; a = a + 1)
            off_oh_r[a] <= off_hi_r[a / BEAT_BYTES] & off_lo_r[a % BEAT_BYTES];
        for (k = 0; k < WBYTES; k = k + 1)
            szk_r[k] <= (k < (1 << p_size));
    end
    always @* begin
        for (b = 0; b < LINE_BYTES; b = b + 1) begin
            mask_n[b]        = 1'b0;
            data_n[b*8 +: 8] = 8'h00;
            for (k = 0; k < WBYTES; k = k + 1)
                if (b - k >= 0) begin
                    mask_n[b]        = mask_n[b] | (off_oh_r[b-k] & szk_r[k]);
                    data_n[b*8 +: 8] = data_n[b*8 +: 8] | ({8{off_oh_r[b-k]}} & p_wdata[k*8 +: 8]);
                end
        end
    end
    always @(posedge clk) begin
        st_mask <= mask_n;
        st_data <= data_n;
    end
    reg [WRITE_DATA_WIDTH-1:0] ld_r;
    reg [AXI_DATA_W-1:0] ld_beat_r;
    reg [LINE_W-1:0] merged;
    integer m;
    always @* begin
        for (m = 0; m < LINE_BYTES; m = m + 1)
            merged[m*8 +: 8] = st_mask[m] ? st_data[m*8 +: 8] : buf_r[m*8 +: 8];
    end
    reg [WRITE_DATA_WIDTH-1:0] load_data;
    integer lk, lj;
    always @* begin
        for (lk = 0; lk < WBYTES; lk = lk + 1) begin
            load_data[lk*8 +: 8] = 8'h00;
            for (lj = 0; lj < BEAT_BYTES; lj = lj + 1)
                if (lj + lk < BEAT_BYTES)
                    load_data[lk*8 +: 8] = load_data[lk*8 +: 8] | ({8{szk_r[lk] & off_lo_r[lj]}} & ld_beat_r[(lj+lk)*8 +: 8]);
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            state   <= E_IDLE;
            dirty_r  <= 1'b0;
            shared_r <= 1'b0;
            unique_r <= 1'b0;
            swap_r   <= 1'b0;
            nr_r     <= 1'b0;
            err_r    <= 1'b0;
            beat     <= {BEAT_W{1'b0}};
        end else begin
            case (state)
                E_IDLE: begin
                  p_off   <= allocate_byte_offset;
                  p_wdata <= allocate_store_data;
                  slot_r  <= allocate_swap_vc_slot;
                  if (allocate_valid) begin
                    line_r  <= allocate_line_addr;
                    swap_r  <= allocate_is_swap;
                    unique_r <= allocate_unique_read && !allocate_is_swap;
                    err_r   <= 1'b0;
                    beat    <= {BEAT_W{1'b0}};
                    p_seat  <= allocate_seat;
                    p_rd_wr <= allocate_is_write;
                    nr_r    <= allocate_no_response;
                    p_size  <= allocate_access_size;
                    p_mid   <= allocate_master_id;
                    p_idx   <= allocate_rob_index;
                    p_port  <= allocate_port;
                    if (allocate_is_swap) begin
                        dirty_r  <= allocate_swap_dirty;
                        shared_r <= allocate_swap_shared;
                        state    <= E_TOKEN;
                    end else begin
                        dirty_r  <= 1'b0;
                        shared_r <= 1'b0;
                        state    <= E_AR;
                    end
                  end
                end
                E_AR: if (axi_read_addr_accepted) state <= E_DATA;
                E_DATA: if (axi_read_beat_valid) begin
                    beat  <= beat + 1'b1;
                    err_r <= err_r | axi_read_beat_error;
                    shared_r <= shared_r | (axi_read_beat_shared && !unique_r);
                    if (axi_read_beat_last) state <= E_MERGE;
                end
                E_MERGE: begin
                    if (p_rd_wr == OP_WRITE) begin
                        dirty_r <= 1'b1;
                    end
                    ld_r  <= (p_rd_wr == OP_WRITE) ? {WRITE_DATA_WIDTH{1'b0}} : load_data;
                    state <= nr_go ? E_TOKEN : E_RESP;
                end
                E_RESP: if (response_taken) state <= err_r ? E_IDLE : E_TOKEN;
                E_TOKEN: if (refill_token_granted) state <= E_INSTALL;
                E_INSTALL: begin
                    if (refill_token_held_by_s1)       state <= E_TOKEN;
                    else if (install_done_by_s2) state <= E_IDLE;
                end
                default: state <= E_IDLE;
            endcase
        end
    end
    always @(posedge clk) begin
        if (rst) busy_r <= 1'b0;
        else     busy_r <= busy_r ? !entry_freed_pulse : allocate_valid;
    end
    assign entry_busy      = busy_r;
    assign entry_line_addr      = line_r;
    wire last_beat = dat_q && axi_read_beat_valid && axi_read_beat_last;
    wire ar_n = (!busy_r && allocate_valid && !allocate_is_swap) || (ar_q && !axi_read_addr_accepted);
    assign nr_go = nr_r && !err_r;
    wire rs_n = (mrg_q && !nr_go) || (rs_q && !response_taken);
    wire m11_other = (!busy_r && allocate_valid && allocate_is_swap) || (mrg_q && nr_go) ||
                     (inst_q && refill_token_held_by_s1);
    wire tk_n = tk_q ? !refill_token_granted :
                (rs_q ? (response_taken && !err_r) : m11_other);
    (* keep *) always @(posedge clk) begin
        if (rst) begin
            ar_q <= 1'b0;  rs_q <= 1'b0;  tk_q <= 1'b0;  dat_q <= 1'b0;  mrg_q <= 1'b0;  inst_q <= 1'b0;
        end else begin
            ar_q   <= ar_n;
            rs_q   <= rs_n;
            tk_q   <= tk_n;
            dat_q  <= (ar_q && axi_read_addr_accepted) || (dat_q && !last_beat);
            mrg_q  <= last_beat;
            inst_q <= (tk_q && refill_token_granted) || (inst_q && !refill_token_held_by_s1 && !install_done_by_s2);
        end
    end
    (* keep *) always @(posedge clk) begin
        if (rst) begin
            ar_arb_q <= 1'b0;  rs_arb_q <= 1'b0;  tk_arb_q <= 1'b0;
        end else begin
            ar_arb_q <= ar_n;
            rs_arb_q <= rs_n;
            tk_arb_q <= tk_n;
        end
    end
    (* keep *) always @(posedge clk) begin
        if (rst) begin
            ar_c_q <= 1'b0;  rs_c_q <= 1'b0;  tk_c_q <= 1'b0;
        end else begin
            ar_c_q <= ar_n;
            rs_c_q <= rs_n;
            tk_c_q <= tk_n;
        end
    end
    always @(posedge clk) begin
        if (rst)                              beat_oh <= {{(AXI_BEATS-1){1'b0}}, 1'b1};
        else if (!busy_r && allocate_valid)   beat_oh <= {{(AXI_BEATS-1){1'b0}}, 1'b1};
        else if (dat_q && axi_read_beat_valid) beat_oh <= (beat_oh << 1) | (beat_oh >> (AXI_BEATS - 1));
    end
    integer bj;
    always @(posedge clk) begin
        if (!busy_r) begin
            buf_r <= allocate_swap_line_data;
        end else if (dat_q && axi_read_beat_valid) begin
            for (bj = 0; bj < AXI_BEATS; bj = bj + 1)
                if (beat_oh[bj]) buf_r[bj*AXI_DATA_W +: AXI_DATA_W] <= axi_read_beat_data;
        end else if (mrg_q && (p_rd_wr == OP_WRITE)) begin
            buf_r <= merged;
        end
    end
    always @(posedge clk) begin
        if (dat_q && axi_read_beat_valid && (|(beat_oh & off_hi_r)))
            ld_beat_r <= axi_read_beat_data;
    end
    assign axi_read_addr_request    = ar_arb_q;
    assign axi_read_is_unique   = unique_r;
    assign response_request  = rs_arb_q;
    assign refill_token_request   = tk_arb_q;
    assign axi_read_addr_request_ctrl = ar_c_q;
    assign response_request_ctrl      = rs_c_q;
    assign refill_token_request_ctrl  = tk_c_q;
    assign line_buffer_data      = buf_r;
    assign install_state = dirty_r  ? ST_M :
                        unique_r ? ST_E :
                        shared_r ? ST_S : ST_E;
    assign line_buffer_has_data  = mrg_q || rs_q || tk_q || inst_q;
    assign entry_is_swap      = swap_r;
    assign entry_swap_vc_slot = slot_r;
    assign response_seat = p_seat;
    assign entry_freed_pulse     = (rs_q && response_taken && err_r) ||
                       (inst_q && install_done_by_s2 && !refill_token_held_by_s1);
    assign response_packet = {p_port, p_rd_wr, p_size, p_mid, p_idx, ld_r};
`ifdef L1D_DEBUG
    function [8*7-1:0] dbg_ename;
        input [2:0] s;
        begin
            case (s)
                E_IDLE:    dbg_ename = "IDLE";
                E_AR:      dbg_ename = "AR";
                E_DATA:    dbg_ename = "DATA";
                E_MERGE:   dbg_ename = "MERGE";
                E_RESP:    dbg_ename = "RESP";
                E_TOKEN:   dbg_ename = "TOKEN";
                E_INSTALL: dbg_ename = "INSTALL";
                default:   dbg_ename = "?";
            endcase
        end
    endfunction
    reg [2:0] dbg_ps;
    integer   dbg_age;
    initial begin dbg_ps = E_IDLE; dbg_age = 0; end
    always @(posedge clk) begin
        if (rst) begin
            dbg_ps  = E_IDLE;
            dbg_age = 0;
        end else begin
            if (state != dbg_ps) begin
                $display("[%0t] L1D MSHR %m: %0s -> %0s  line=%h %s primary idx=%0d %s err=%b",
                         $time, dbg_ename(dbg_ps), dbg_ename(state), {line_r, {OFFSET_W{1'b0}}},
                         swap_r ? "swap" : "fetch", p_idx, (p_rd_wr ? "ST" : "LD"), err_r);
                dbg_ps  = state;
                dbg_age = 0;
            end else if (state != E_IDLE) begin
                dbg_age = dbg_age + 1;
                if (dbg_age % `L1D_DBG_WD == 0)
                    $display("[%0t] L1D MSHR %m STUCK in %0s for %0d cycles  line=%h beats_received=%0d of %0d  (AR: AXI master/ARREADY; DATA: R beats with this entry's id; RESP: response FIFO place; TOKEN: Stage 0 grant; INSTALL: Stage 2)",
                             $time, dbg_ename(state), dbg_age, {line_r, {OFFSET_W{1'b0}}}, beat, AXI_BEATS);
            end
            if (axi_read_beat_valid) begin
                if (state != E_DATA)
                    $display("[%0t] L1D MSHR %m ERROR R beat for this entry while it is in %0s (wrong RID from memory?)",
                             $time, dbg_ename(state));
                else begin
                    $display("[%0t] L1D MSHR %m R beat %0d of %0d last=%b err=%b data=%h",
                             $time, beat, AXI_BEATS, axi_read_beat_last, axi_read_beat_error, axi_read_beat_data);
                    if (axi_read_beat_last && beat != AXI_BEATS - 1)
                        $display("[%0t] L1D MSHR %m ERROR RLAST on beat %0d, expected on beat %0d (memory sent the wrong burst length)",
                                 $time, beat, AXI_BEATS - 1);
                    if (!axi_read_beat_last && beat == AXI_BEATS - 1)
                        $display("[%0t] L1D MSHR %m ERROR beat %0d has no RLAST: the entry will never leave DATA (memory sent the wrong burst length or RLAST)",
                                 $time, beat);
                end
            end
        end
    end
`endif
endmodule
`default_nettype wire
