`include "ssync_defines.vh"
//=============================================================
// ssync_regs.v
//
// APB3 slave register block for the ssync IP.
// Zero-wait-state slave (pready tied high). Access happens when
// psel & penable (APB access phase).
//
// See doc/spec.md for the register map.
//=============================================================
module ssync_regs (
    input  wire        pclk,
    input  wire        presetn,

    // APB
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] pwdata,  // [31:17] reserved, unused
    /* verilator lint_on UNUSEDSIGNAL */
    output reg  [31:0] prdata,
    output wire        pready,

    // cfg outputs to tx/rx cores
    output reg          cfg_mode,
    output reg  [1:0]   cfg_width_sel,
    output reg  [3:0]   cfg_length_m1,
    output reg  [9:0]   cfg_clkdiv,
    output reg          cfg_rx_count_en,

    // tx core interface
    input  wire        tx_busy,
    output reg          tx_start,
    output reg  [15:0]  tx_wdata,

    // rx core interface
    input  wire [15:0] rx_data,
    input  wire        rx_valid,
    input  wire [31:0] preamble_bit_count
);

    assign pready = 1'b1; // zero wait-state

    // apb_access (psel & penable) can, depending on how the master holds
    // PSEL/PENABLE, be observed as high for more than one pclk edge (e.g.
    // a master that inserts wait states, or - as seen in simulation - a
    // testbench driving these signals with non-blocking assigns one cycle
    // apart from when the DUT samples them). A register block must not
    // repeat a write/read side effect (like TXDATA-write or the RXSTATUS
    // clear-on-read) for every such edge: it must fire exactly once per
    // transfer. We therefore edge-detect apb_access and only act on its
    // rising edge.
    wire apb_access = psel & penable;
    reg  apb_access_d;
    wire apb_access_pulse = apb_access & ~apb_access_d;
    wire apb_wr = apb_access_pulse & pwrite;
    wire apb_rd = apb_access_pulse & ~pwrite;

    // sticky rx_valid flag, cleared on RXSTATUS read
    reg rx_valid_sticky;
    // preamble bit counter register
    reg [31:0] rx_count;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            apb_access_d    <= 1'b0;
            cfg_mode        <= `SSYNC_MODE_PREAMBLE;
            cfg_width_sel   <= `SSYNC_WIDTH_1;
            cfg_length_m1   <= 4'd0;      // length = 1
            cfg_clkdiv      <= 10'd100;
            cfg_rx_count_en <= 1'b0;      // counter disabled by default
            tx_wdata        <= 16'd0;
            tx_start         <= 1'b0;
            rx_valid_sticky <= 1'b0;
            rx_count        <= 32'd0;
        end else begin
            apb_access_d <= apb_access;
            tx_start     <= 1'b0; // default: 1-cycle pulse only on a fresh write

            // counter: update from rx core unless APB is writing to RXCOUNT
            if (apb_wr && (paddr == `SSYNC_REG_RXCOUNT))
                rx_count <= pwdata[31:0];
            else
                rx_count <= preamble_bit_count;

            if (apb_wr) begin
                case (paddr)
                    `SSYNC_REG_CFG: begin
                        cfg_mode        <= pwdata[`SSYNC_CFG_MODE_BIT];
                        cfg_width_sel   <= pwdata[`SSYNC_CFG_WIDTH_MSB:`SSYNC_CFG_WIDTH_LSB];
                        cfg_length_m1   <= pwdata[`SSYNC_CFG_LENGTH_MSB:`SSYNC_CFG_LENGTH_LSB];
                        cfg_clkdiv      <= pwdata[`SSYNC_CFG_CLKDIV_MSB:`SSYNC_CFG_CLKDIV_LSB];
                        cfg_rx_count_en <= pwdata[`SSYNC_CFG_RX_COUNT_EN_BIT];
                    end
                    `SSYNC_REG_TXDATA: begin
                        // spec item 5: while TX busy, writes to data reg are ignored
                        if (!tx_busy) begin
                            tx_wdata <= pwdata[15:0];
                            tx_start <= 1'b1;
                        end
                    end
                    default: begin
                        // RXCOUNT, TXSTATUS, RXDATA, RXSTATUS are read-only, writes ignored
                    end
                endcase
            end

            // latch new rx data availability
            if (rx_valid)
                rx_valid_sticky <= 1'b1;
            else if (apb_rd && (paddr == `SSYNC_REG_RXSTATUS))
                rx_valid_sticky <= 1'b0;
        end
    end

    always @(*) begin
        prdata = 32'd0;
        case (paddr)
            `SSYNC_REG_CFG: begin
                prdata[`SSYNC_CFG_MODE_BIT]                             = cfg_mode;
                prdata[`SSYNC_CFG_WIDTH_MSB:`SSYNC_CFG_WIDTH_LSB]       = cfg_width_sel;
                prdata[`SSYNC_CFG_LENGTH_MSB:`SSYNC_CFG_LENGTH_LSB]     = cfg_length_m1;
                prdata[`SSYNC_CFG_CLKDIV_MSB:`SSYNC_CFG_CLKDIV_LSB]     = cfg_clkdiv;
                prdata[`SSYNC_CFG_RX_COUNT_EN_BIT]                      = cfg_rx_count_en;
            end
            `SSYNC_REG_TXDATA:    prdata = {16'd0, tx_wdata};
            `SSYNC_REG_TXSTATUS:  prdata = {31'd0, tx_busy};
            `SSYNC_REG_RXDATA:    prdata = {16'd0, rx_data};
            `SSYNC_REG_RXSTATUS:  prdata = {31'd0, rx_valid_sticky};
            `SSYNC_REG_RXCOUNT:   prdata = rx_count;
            default:              prdata = 32'd0;
        endcase
    end

endmodule
