`include "ssync_defines.vh"
//=============================================================
// ssync_top.v
//
// Chip-to-chip serial sync signal transceiver.
// APB-programmable, one TX path + one RX path (independent,
// unidirectional). See doc/spec.md for full specification.
//=============================================================
module ssync_top (
    input  wire        pclk,
    input  wire        presetn,

    // APB slave
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,

    // serial TX pins (this chip -> partner chip)
    output wire        ss_tx_clk,
    output wire [3:0]  ss_tx_data,

    // serial RX pins (partner chip -> this chip)
    input  wire        ss_rx_clk,
    input  wire [3:0]  ss_rx_data
);

    wire        cfg_mode;
    wire [1:0]  cfg_width_sel;
    wire [3:0]  cfg_length_m1;
    wire [9:0]  cfg_clkdiv;
    wire        cfg_rx_count_en;
    wire        cfg_tx_en;
    wire        cfg_rx_en;

    wire        tx_busy;
    wire        tx_start;
    wire [15:0] tx_wdata;

    wire [15:0] rx_data;
    wire        rx_valid;
    wire [31:0] preamble_bit_count;

    ssync_regs u_regs (
        .pclk               (pclk),
        .presetn            (presetn),
        .psel               (psel),
        .penable            (penable),
        .pwrite             (pwrite),
        .paddr              (paddr),
        .pwdata             (pwdata),
        .prdata             (prdata),
        .pready             (pready),
        .cfg_mode           (cfg_mode),
        .cfg_width_sel      (cfg_width_sel),
        .cfg_length_m1      (cfg_length_m1),
        .cfg_clkdiv         (cfg_clkdiv),
        .cfg_rx_count_en    (cfg_rx_count_en),
        .cfg_tx_en          (cfg_tx_en),
        .cfg_rx_en          (cfg_rx_en),
        .tx_busy            (tx_busy),
        .tx_start           (tx_start),
        .tx_wdata           (tx_wdata),
        .rx_data            (rx_data),
        .rx_valid           (rx_valid),
        .preamble_bit_count (preamble_bit_count)
    );

    ssync_tx u_tx (
        .pclk           (pclk),
        .presetn        (presetn),
        .cfg_mode       (cfg_mode),
        .cfg_width_sel  (cfg_width_sel),
        .cfg_length_m1  (cfg_length_m1),
        .cfg_clkdiv     (cfg_clkdiv),
        .cfg_tx_en      (cfg_tx_en),
        .tx_start       (tx_start),
        .tx_wdata       (tx_wdata),
        .tx_busy        (tx_busy),
        .ss_clk         (ss_tx_clk),
        .ss_data        (ss_tx_data)
    );

    ssync_rx u_rx (
        .pclk                (pclk),
        .presetn             (presetn),
        .cfg_mode            (cfg_mode),
        .cfg_width_sel       (cfg_width_sel),
        .cfg_length_m1       (cfg_length_m1),
        .cfg_clkdiv          (cfg_clkdiv),
        .cfg_rx_count_en     (cfg_rx_count_en),
        .cfg_rx_en           (cfg_rx_en),
        .ss_clk_i            (ss_rx_clk),
        .ss_data_i           (ss_rx_data),
        .rx_data             (rx_data),
        .rx_valid            (rx_valid),
        .preamble_bit_count  (preamble_bit_count)
    );

endmodule
