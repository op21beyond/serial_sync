`include "ssync_defines.vh"
//=============================================================
// ssync_tx.v
//
// Serial transmitter core.
//   - CLOCK mode  (cfg_mode=1): 2-pin, ss_clk + ss_data[N-1:0].
//       ss_clk toggles only while a frame is in flight (idle=0).
//       New data is set up on ss_clk rising tick, held stable
//       through the ss_clk falling tick (=> RX sample point).
//   - PREAMBLE mode (cfg_mode=0, default): 1-pin group, no clock.
//       A 2-tick preamble (1 then 0) is sent on all active data
//       lines, followed by length/N ticks of data, LSB group first.
//
// Fully synchronous, no latches. All outputs registered.
//=============================================================
module ssync_tx (
    input  wire        pclk,
    input  wire        presetn,

    input  wire        cfg_mode,        // 0=preamble 1=clock
    input  wire [1:0]  cfg_width_sel,   // N encode
    input  wire [3:0]  cfg_length_m1,   // length-1
    input  wire [9:0]  cfg_clkdiv,
    input  wire        cfg_tx_en,       // 0=TX disabled, ss_clk/ss_data held low

    input  wire        tx_start,        // 1-cycle pulse, valid only if !tx_busy
    input  wire [15:0] tx_wdata,

    output reg          tx_busy,
    output reg          ss_clk,
    output reg  [3:0]   ss_data
);

    // ---------------- length decode ----------------
    wire [4:0] length = {1'b0, cfg_length_m1} + 5'd1; // 1..16

    // ---------------- tick generator ----------------
    reg  tick_sync_rst;
    wire tick;
    ssync_tick_gen u_tick (
        .clk        (pclk),
        .rst_n      (presetn),
        .sync_rst   (tick_sync_rst),
        .half_first (1'b0),
        .div        (cfg_clkdiv),
        .tick       (tick)
    );

    // ---------------- FSM ----------------
    localparam S_IDLE          = 3'd0,
               S_PRE_HI        = 3'd1,  // preamble mode: driving '1'
               S_PRE_LO        = 3'd2,  // preamble mode: driving '0'
               S_PDATA         = 3'd3,  // preamble mode: data ticks
               S_CLK_RISE      = 3'd4,  // clock mode: setup edge
               S_CLK_FALL      = 3'd5,  // clock mode: sample edge (hold)
               S_DONE_WAIT     = 3'd6,  // preamble mode: hold last group one extra tick
               S_CLK_DONE_WAIT = 3'd7;  // clock mode: hold last group one extra tick
               // after the falling edge, before clearing ss_data, so the RX's
               // input synchronizer has time to sample the final group.

    reg [2:0]  state;
    reg [15:0] sreg;
    reg [4:0]  bits_left;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state         <= S_IDLE;
            tx_busy       <= 1'b0;
            ss_clk        <= 1'b0;
            ss_data       <= 4'b0000;
            sreg          <= 16'd0;
            bits_left     <= 5'd0;
            tick_sync_rst <= 1'b0;
        end else if (!cfg_tx_en) begin
            // TX disabled: force idle and hold outputs low. Any in-flight
            // frame is abandoned (spec assumes cfg is stable during a
            // transfer, same as other control registers).
            state         <= S_IDLE;
            tx_busy       <= 1'b0;
            ss_clk        <= 1'b0;
            ss_data       <= 4'b0000;
            tick_sync_rst <= 1'b0;
        end else begin
            tick_sync_rst <= 1'b0; // default (1-cycle pulse only on start)

            case (state)
                //---------------------------------------------
                S_IDLE: begin
                    ss_clk  <= 1'b0;
                    ss_data <= 4'b0000;
                    if (tx_start) begin
                        tx_busy       <= 1'b1;
                        sreg          <= tx_wdata;
                        bits_left     <= length;
                        tick_sync_rst <= 1'b1; // rephase tick counter to frame start
                        if (cfg_mode == `SSYNC_MODE_CLOCK) begin
                            state <= S_CLK_RISE;
                        end else begin
                            ss_data <= 4'b1111; // preamble '1' (active lines only meaningful)
                            state   <= S_PRE_HI;
                        end
                    end
                end

                //--------------- PREAMBLE MODE ----------------
                S_PRE_HI: begin
                    if (tick) begin
                        ss_data <= 4'b0000; // preamble '0'
                        state   <= S_PRE_LO;
                    end
                end

                S_PRE_LO: begin
                    if (tick) begin
                        state <= S_PDATA;
                        // first data group is driven combinationally below via
                        // the "drive_data" block once we enter S_PDATA; use a
                        // one-cycle head start by loading it here.
                        case (cfg_width_sel)
                            `SSYNC_WIDTH_2: begin
                                ss_data   <= {2'b00, sreg[1:0]};
                                sreg      <= {2'b00, sreg[15:2]};
                                bits_left <= bits_left - 5'd2;
                            end
                            `SSYNC_WIDTH_4: begin
                                ss_data   <= sreg[3:0];
                                sreg      <= {4'b0000, sreg[15:4]};
                                bits_left <= bits_left - 5'd4;
                            end
                            default: begin
                                ss_data   <= {3'b000, sreg[0]};
                                sreg      <= {1'b0, sreg[15:1]};
                                bits_left <= bits_left - 5'd1;
                            end
                        endcase
                    end
                end

                S_PDATA: begin
                    if (tick) begin
                        if (bits_left == 5'd0) begin
                            // last group already on the bus for one full tick;
                            // hold one more tick then go idle.
                            state <= S_DONE_WAIT;
                        end else begin
                            case (cfg_width_sel)
                                `SSYNC_WIDTH_2: begin
                                    ss_data   <= {2'b00, sreg[1:0]};
                                    sreg      <= {2'b00, sreg[15:2]};
                                    bits_left <= bits_left - 5'd2;
                                end
                                `SSYNC_WIDTH_4: begin
                                    ss_data   <= sreg[3:0];
                                    sreg      <= {4'b0000, sreg[15:4]};
                                    bits_left <= bits_left - 5'd4;
                                end
                                default: begin
                                    ss_data   <= {3'b000, sreg[0]};
                                    sreg      <= {1'b0, sreg[15:1]};
                                    bits_left <= bits_left - 5'd1;
                                end
                            endcase
                        end
                    end
                end

                S_DONE_WAIT: begin
                    if (tick) begin
                        ss_data <= 4'b0000;
                        tx_busy <= 1'b0;
                        state   <= S_IDLE;
                    end
                end

                //---------------- CLOCK MODE -------------------
                S_CLK_RISE: begin
                    if (tick) begin
                        ss_clk <= 1'b1;
                        case (cfg_width_sel)
                            `SSYNC_WIDTH_2: begin
                                ss_data   <= {2'b00, sreg[1:0]};
                                sreg      <= {2'b00, sreg[15:2]};
                                bits_left <= bits_left - 5'd2;
                            end
                            `SSYNC_WIDTH_4: begin
                                ss_data   <= sreg[3:0];
                                sreg      <= {4'b0000, sreg[15:4]};
                                bits_left <= bits_left - 5'd4;
                            end
                            default: begin
                                ss_data   <= {3'b000, sreg[0]};
                                sreg      <= {1'b0, sreg[15:1]};
                                bits_left <= bits_left - 5'd1;
                            end
                        endcase
                        state <= S_CLK_FALL;
                    end
                end

                S_CLK_FALL: begin
                    if (tick) begin
                        ss_clk <= 1'b0; // falling edge -> RX samples here
                        if (bits_left == 5'd0) begin
                            // keep ss_data at its final value for one more
                            // tick so the RX's double-flop synchronizer has
                            // margin to sample it before it is cleared.
                            state <= S_CLK_DONE_WAIT;
                        end else begin
                            state <= S_CLK_RISE;
                        end
                    end
                end

                S_CLK_DONE_WAIT: begin
                    if (tick) begin
                        tx_busy <= 1'b0;
                        ss_data <= 4'b0000;
                        state   <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
