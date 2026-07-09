`include "ssync_defines.vh"
//=============================================================
// ssync_rx.v
//
// Serial receiver core. TX and RX are unidirectional and assumed
// to run with identical cfg (mode/width/length/clkdiv) on both
// chips (per spec).
//
//   - CLOCK mode: samples ss_data_i on every falling edge of
//     ss_data_i's companion ss_clk_i (double-flop synchronized).
//     data register is updated only after all N-bit groups of a
//     full frame have been received (never mid-frame).
//   - PREAMBLE mode: detects the rising edge that starts the
//     2-tick (1,0) preamble on the data line(s), phase-locks a
//     local tick generator to it (same clkdiv as TX, since cfg is
//     shared), then samples one N-bit group per tick.
//
// All inputs are double-flop synchronized; no latches; fully
// synchronous.
//=============================================================
module ssync_rx (
    input  wire        pclk,
    input  wire        presetn,

    input  wire        cfg_mode,
    input  wire [1:0]  cfg_width_sel,
    input  wire [3:0]  cfg_length_m1,
    input  wire [9:0]  cfg_clkdiv,

    input  wire        ss_clk_i,
    input  wire [3:0]  ss_data_i,

    output reg  [15:0] rx_data,
    output reg          rx_valid   // 1-cycle pulse when rx_data updates
);

    // ---------------- width / length decode ----------------
    wire [4:0] length = {1'b0, cfg_length_m1} + 5'd1; // 1..16

    // ---------------- input synchronizers ----------------
    // clk: 3-deep shift -> edge detect on the 2-deep stable value
    reg [2:0] clk_sync;
    // data: 2-deep synchronizer (matches clk_sync[1] timing)
    reg [3:0] data_s0, data_s1;
    // extra 1-cycle delayed copy of data_s1[0] for rising-edge detect
    reg       data_bit0_prev;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            clk_sync       <= 3'b000;
            data_s0        <= 4'b0000;
            data_s1        <= 4'b0000;
            data_bit0_prev <= 1'b0;
        end else begin
            clk_sync       <= {clk_sync[1:0], ss_clk_i};
            data_s0        <= ss_data_i;
            data_s1        <= data_s0;
            data_bit0_prev <= data_s1[0];
        end
    end

    wire clk_fall   = clk_sync[2] & ~clk_sync[1];       // falling edge, stable
    wire data_rise0 = data_s1[0] & ~data_bit0_prev;     // rising edge on bit0 (preamble start candidate)

    // ---------------- local tick generator (preamble mode only) ----
    reg  tick_sync_rst;
    wire tick;
    ssync_tick_gen u_tick (
        .clk        (pclk),
        .rst_n      (presetn),
        .sync_rst   (tick_sync_rst),
        .half_first (1'b1), // first post-lock tick samples bit CENTER, not boundary
        .div        (cfg_clkdiv),
        .tick       (tick)
    );

    // ---------------- FSM ----------------
    localparam R_IDLE     = 3'd0,
               R_PRE_CHK1 = 3'd1, // expect sampled data == 1 (end of preamble tick A)
               R_PRE_CHK0 = 3'd2, // expect sampled data == 0 (end of preamble tick B)
               R_PDATA    = 3'd3, // preamble mode: receiving data groups
               R_CRECV    = 3'd4; // clock mode: receiving data groups

    reg [2:0]  state;
    reg [15:0] acc;
    reg [3:0]  wr_pos;     // 0..15, indexes the 16-bit acc register
    reg [4:0]  bits_left;

    // combinational: value of acc after merging in the current N-bit group
    reg [15:0] new_acc;
    always @(*) begin
        new_acc = acc;
        case (cfg_width_sel)
            `SSYNC_WIDTH_2: new_acc[wr_pos +: 2] = data_s1[1:0];
            `SSYNC_WIDTH_4: new_acc[wr_pos +: 4] = data_s1[3:0];
            default:        new_acc[wr_pos +: 1] = data_s1[0:0];
        endcase
    end

    reg [3:0] next_wr_pos;
    reg [4:0] next_bits_left;
    always @(*) begin
        case (cfg_width_sel)
            `SSYNC_WIDTH_2: begin next_wr_pos = wr_pos + 4'd2; next_bits_left = bits_left - 5'd2; end
            `SSYNC_WIDTH_4: begin next_wr_pos = wr_pos + 4'd4; next_bits_left = bits_left - 5'd4; end
            default:        begin next_wr_pos = wr_pos + 4'd1; next_bits_left = bits_left - 5'd1; end
        endcase
    end

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state         <= R_IDLE;
            acc           <= 16'd0;
            wr_pos        <= 4'd0;
            bits_left     <= 5'd0;
            rx_data       <= 16'd0;
            rx_valid      <= 1'b0;
            tick_sync_rst <= 1'b0;
        end else begin
            rx_valid      <= 1'b0; // default: pulse only on update
            tick_sync_rst <= 1'b0;

            case (state)
                //---------------------------------------------
                R_IDLE: begin
                    wr_pos    <= 4'd0;
                    bits_left <= length;
                    acc       <= 16'd0;
                    if (cfg_mode == `SSYNC_MODE_CLOCK) begin
                        if (clk_fall) begin
                            acc       <= new_acc;
                            wr_pos    <= next_wr_pos;
                            bits_left <= next_bits_left;
                            if (next_bits_left == 5'd0) begin
                                rx_data  <= new_acc;
                                rx_valid <= 1'b1;
                                state    <= R_IDLE;
                            end else begin
                                state <= R_CRECV;
                            end
                        end
                    end else begin
                        if (data_rise0) begin
                            tick_sync_rst <= 1'b1; // rephase: next tick = end of preamble tick A
                            state         <= R_PRE_CHK1;
                        end
                    end
                end

                //--------------- CLOCK MODE --------------------
                R_CRECV: begin
                    if (clk_fall) begin
                        acc       <= new_acc;
                        wr_pos    <= next_wr_pos;
                        bits_left <= next_bits_left;
                        if (next_bits_left == 5'd0) begin
                            rx_data  <= new_acc;
                            rx_valid <= 1'b1;
                            state    <= R_IDLE;
                        end
                    end
                end

                //-------------- PREAMBLE MODE -------------------
                R_PRE_CHK1: begin
                    if (tick) begin
                        if (data_s1[0] == 1'b1) begin
                            state <= R_PRE_CHK0;
                        end else begin
                            state <= R_IDLE; // glitch, abort
                        end
                    end
                end

                R_PRE_CHK0: begin
                    if (tick) begin
                        if (data_s1[0] == 1'b0) begin
                            wr_pos    <= 4'd0;
                            bits_left <= length;
                            acc       <= 16'd0;
                            state     <= R_PDATA;
                        end else begin
                            state <= R_IDLE; // glitch, abort
                        end
                    end
                end

                R_PDATA: begin
                    if (tick) begin
                        acc       <= new_acc;
                        wr_pos    <= next_wr_pos;
                        bits_left <= next_bits_left;
                        if (next_bits_left == 5'd0) begin
                            rx_data  <= new_acc;
                            rx_valid <= 1'b1;
                            state    <= R_IDLE;
                        end
                    end
                end

                default: state <= R_IDLE;
            endcase
        end
    end

endmodule
