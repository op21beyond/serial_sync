`ifndef SSYNC_DEFINES_VH
`define SSYNC_DEFINES_VH
//=============================================================
// ssync_defines.vh
// Common constants for the ssync (serial sync) IP.
//=============================================================

// ---- cfg.mode ----
`define SSYNC_MODE_PREAMBLE 1'b0   // default
`define SSYNC_MODE_CLOCK    1'b1

// ---- cfg.width encoding (parallel bits per serial tick) ----
`define SSYNC_WIDTH_1 2'b00        // default, N=1
`define SSYNC_WIDTH_2 2'b01        // N=2
`define SSYNC_WIDTH_4 2'b10        // N=4
// 2'b11 reserved (treated as N=4 by decode logic)

// ---- APB byte address map (word aligned, 4B stride) ----
`define SSYNC_REG_CFG      8'h00   // RW
`define SSYNC_REG_TXDATA   8'h04   // RW (write ignored while TX busy)
`define SSYNC_REG_TXSTATUS 8'h08   // RO  bit0 = tx_busy
`define SSYNC_REG_RXDATA   8'h0C   // RO
`define SSYNC_REG_RXSTATUS 8'h10   // RO  bit0 = rx_valid (sticky, clear on read)
`define SSYNC_REG_RXCOUNT  8'h14   // RW  preamble bit counter (32bit, wrap-around)

// ---- CFG register bit layout ----
// [0]      mode          0=preamble(default) 1=clock+data
// [2:1]    width_sel     00=1(default) 01=2 10=4
// [6:3]    length_m1     length = length_m1+1 (1..16), default 0 -> length=1
// [16:7]   clkdiv        100..1000, default 100
// [17]     rx_count_en   1=enable preamble bit counter, 0=disable (default)
// [18]     tx_en         1=TX signal generation/output active (default), 0=ss_tx_* held low
// [19]     rx_en         1=RX signal receive active (default), 0=RX ignores serial input
// [31:20]  reserved
`define SSYNC_CFG_MODE_BIT       0
`define SSYNC_CFG_WIDTH_LSB      1
`define SSYNC_CFG_WIDTH_MSB      2
`define SSYNC_CFG_LENGTH_LSB     3
`define SSYNC_CFG_LENGTH_MSB     6
`define SSYNC_CFG_CLKDIV_LSB     7
`define SSYNC_CFG_CLKDIV_MSB     16
`define SSYNC_CFG_RX_COUNT_EN_BIT 17
`define SSYNC_CFG_TX_EN_BIT       18
`define SSYNC_CFG_RX_EN_BIT       19

`endif // SSYNC_DEFINES_VH
