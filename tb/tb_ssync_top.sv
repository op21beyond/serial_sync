`timescale 1ns/1ps
`include "ssync_defines.vh"
//=============================================================
// tb_ssync_top.sv
//
// Self-checking testbench. Instantiates two ssync_top chips
// (A, B) and cross-wires A's TX -> B's RX and B's TX -> A's RX,
// mimicking two real chips connected back to back.
//
// Assumes Verilator (>=5.x, --timing) as the simulator, but the
// testbench only uses plain, portable SystemVerilog constructs
// so it should also run under other simulators.
//=============================================================
module tb_ssync_top;

    // ---------------- clock / reset ----------------
    logic pclk = 0;
    logic presetn = 0;
    always #5 pclk = ~pclk; // 100MHz

    // ---------------- APB signals (2 independent buses) ----------------
    logic        a_psel, a_penable, a_pwrite;
    logic [7:0]  a_paddr;
    logic [31:0] a_pwdata, a_prdata;
    logic        a_pready;

    logic        b_psel, b_penable, b_pwrite;
    logic [7:0]  b_paddr;
    logic [31:0] b_pwdata, b_prdata;
    logic        b_pready;

    // ---------------- serial interconnect ----------------
    wire        a_tx_clk, b_tx_clk;
    wire [3:0]  a_tx_data, b_tx_data;

    int errors = 0;
    int checks = 0;

    ssync_top chip_a (
        .pclk      (pclk),
        .presetn   (presetn),
        .psel      (a_psel),
        .penable   (a_penable),
        .pwrite    (a_pwrite),
        .paddr     (a_paddr),
        .pwdata    (a_pwdata),
        .prdata    (a_prdata),
        .pready    (a_pready),
        .ss_tx_clk (a_tx_clk),
        .ss_tx_data(a_tx_data),
        .ss_rx_clk (b_tx_clk),
        .ss_rx_data(b_tx_data)
    );

    ssync_top chip_b (
        .pclk      (pclk),
        .presetn   (presetn),
        .psel      (b_psel),
        .penable   (b_penable),
        .pwrite    (b_pwrite),
        .paddr     (b_paddr),
        .pwdata    (b_pwdata),
        .prdata    (b_prdata),
        .pready    (b_pready),
        .ss_tx_clk (b_tx_clk),
        .ss_tx_data(b_tx_data),
        .ss_rx_clk (a_tx_clk),
        .ss_rx_data(a_tx_data)
    );

    // ---------------- APB helper tasks ----------------
    task automatic apb_write(input bit is_a, input [7:0] addr, input [31:0] wdata);
        @(posedge pclk);
        if (is_a) begin
            a_psel <= 1'b1; a_penable <= 1'b0; a_pwrite <= 1'b1;
            a_paddr <= addr; a_pwdata <= wdata;
        end else begin
            b_psel <= 1'b1; b_penable <= 1'b0; b_pwrite <= 1'b1;
            b_paddr <= addr; b_pwdata <= wdata;
        end
        @(posedge pclk);
        if (is_a) a_penable <= 1'b1; else b_penable <= 1'b1;
        @(posedge pclk);
        if (is_a) begin a_psel <= 1'b0; a_penable <= 1'b0; end
        else      begin b_psel <= 1'b0; b_penable <= 1'b0; end
    endtask

    task automatic apb_read(input bit is_a, input [7:0] addr, output [31:0] rdata);
        @(posedge pclk);
        if (is_a) begin
            a_psel <= 1'b1; a_penable <= 1'b0; a_pwrite <= 1'b0; a_paddr <= addr;
        end else begin
            b_psel <= 1'b1; b_penable <= 1'b0; b_pwrite <= 1'b0; b_paddr <= addr;
        end
        @(posedge pclk);
        if (is_a) a_penable <= 1'b1; else b_penable <= 1'b1;
        // Capture in the SAME simulation step that penable is asserted:
        // prdata is purely address-decoded (independent of psel/penable),
        // so this returns the value as of *before* this read's own
        // clear-on-read side effect (e.g. RXSTATUS) can take effect,
        // which is the correct "read-then-clear" APB semantics.
        rdata = is_a ? a_prdata : b_prdata;
        @(posedge pclk);
        if (is_a) begin a_psel <= 1'b0; a_penable <= 1'b0; end
        else      begin b_psel <= 1'b0; b_penable <= 1'b0; end
    endtask

    task automatic check(input bit cond, input string msg);
        checks++;
        if (!cond) begin
            errors++;
            $display("[%0t] FAIL: %s", $time, msg);
        end else begin
            $display("[%0t] PASS: %s", $time, msg);
        end
    endtask

    // configure chip (mode/width/length/clkdiv) via CFG register
    task automatic cfg_set(input bit is_a, input bit mode, input [1:0] wsel,
                            input [3:0] len_m1, input [9:0] clkdiv);
        logic [31:0] cfg;
        cfg = 32'd0;
        cfg[`SSYNC_CFG_MODE_BIT]                         = mode;
        cfg[`SSYNC_CFG_WIDTH_MSB:`SSYNC_CFG_WIDTH_LSB]   = wsel;
        cfg[`SSYNC_CFG_LENGTH_MSB:`SSYNC_CFG_LENGTH_LSB] = len_m1;
        cfg[`SSYNC_CFG_CLKDIV_MSB:`SSYNC_CFG_CLKDIV_LSB] = clkdiv;
        apb_write(is_a, `SSYNC_REG_CFG, cfg);
    endtask

    // send from chip A, wait & check reception at chip B
    task automatic send_and_check(input string label, input bit mode, input [1:0] wsel,
                                   input [3:0] len_m1, input [9:0] clkdiv, input [15:0] data);
        logic [31:0] rd;
        int          timeout;
        int          len_bits;
        len_bits = len_m1 + 1;

        // Wait for any previous frame to fully drain before reprogramming CFG
        // and issuing a new TXDATA write. RX asserting rx_valid is NOT the same
        // as TX being done: the TX still holds the last bit group on the line
        // for a final tick (S_DONE_WAIT) so the receiver's input synchronizer
        // can capture it. Writing TXDATA while tx_busy is still set would be
        // silently ignored by the register block (spec item 5).
        timeout = 0;
        do begin
            apb_read(1'b1, `SSYNC_REG_TXSTATUS, rd);
            timeout++;
        end while (rd[0] == 1'b1 && timeout < 20000);
        check(rd[0] == 1'b0, {label, ": TX idle before new frame"});

        cfg_set(1'b1, mode, wsel, len_m1, clkdiv); // TX side (chip A)
        cfg_set(1'b0, mode, wsel, len_m1, clkdiv); // RX side (chip B) - same cfg assumption

        apb_write(1'b1, `SSYNC_REG_TXDATA, {16'd0, data});

        // wait for RX valid on chip B (RXSTATUS bit0), bounded timeout
        timeout = 0;
        do begin
            @(posedge pclk);
            apb_read(1'b0, `SSYNC_REG_RXSTATUS, rd);
            timeout++;
        end while (rd[0] == 1'b0 && timeout < (clkdiv * (len_bits + 20)));

        check(rd[0] == 1'b1, {label, ": rx_valid asserted before timeout"});

        apb_read(1'b0, `SSYNC_REG_RXDATA, rd);
        begin
            logic [15:0] mask;
            mask = (len_bits >= 16) ? 16'hFFFF : ((16'h1 << len_bits) - 16'h1);
            check((rd[15:0] & mask) == (data & mask),
                  $sformatf("%s: rxdata=%0h expected=%0h (mask=%0h)", label, rd[15:0], data, mask));
        end
    endtask

    // ---------------- main sequence ----------------
    initial begin
        a_psel = 0; a_penable = 0; a_pwrite = 0; a_paddr = 0; a_pwdata = 0;
        b_psel = 0; b_penable = 0; b_pwrite = 0; b_paddr = 0; b_pwdata = 0;

        presetn = 0;
        repeat (5) @(posedge pclk);
        presetn = 1;
        repeat (5) @(posedge pclk);

        // ---- Test 1: preamble mode, width=1, length=8 ----
        send_and_check("T1 preamble/W1/L8", `SSYNC_MODE_PREAMBLE, `SSYNC_WIDTH_1, 4'd7, 10'd100, 16'hA5);

        // ---- Test 2: clock mode, width=4, length=16 ----
        send_and_check("T2 clock/W4/L16", `SSYNC_MODE_CLOCK, `SSYNC_WIDTH_4, 4'd15, 10'd100, 16'hBEEF);

        // ---- Test 3: preamble mode, width=2, length=6 ----
        send_and_check("T3 preamble/W2/L6", `SSYNC_MODE_PREAMBLE, `SSYNC_WIDTH_2, 4'd5, 10'd100, 16'h002B);

        // ---- Test 4: clock mode, width=1, length=4 ----
        send_and_check("T4 clock/W1/L4", `SSYNC_MODE_CLOCK, `SSYNC_WIDTH_1, 4'd3, 10'd100, 16'h0009);

        // ---- Test 5: write-while-busy is ignored ----
        begin
            logic [31:0] rd0, rd1, status;
            cfg_set(1'b1, `SSYNC_MODE_PREAMBLE, `SSYNC_WIDTH_1, 4'd15, 10'd300);
            apb_write(1'b1, `SSYNC_REG_TXDATA, 32'h0000_1234);
            apb_read(1'b1, `SSYNC_REG_TXSTATUS, status);
            check(status[0] == 1'b1, "T5: tx_busy asserted right after start");
            apb_read(1'b1, `SSYNC_REG_TXDATA, rd0);
            apb_write(1'b1, `SSYNC_REG_TXDATA, 32'h0000_ABCD); // should be ignored (still busy)
            apb_read(1'b1, `SSYNC_REG_TXDATA, rd1);
            check(rd0 == rd1, "T5: TXDATA write ignored while busy");
            // wait for it to finish before moving on
            do begin
                @(posedge pclk);
                apb_read(1'b1, `SSYNC_REG_TXSTATUS, status);
            end while (status[0] == 1'b1);
        end

        // ---- Test 6: back-to-back opposite direction (B -> A) ----
        begin
            logic [31:0] cfg;
            cfg = 32'd0;
            cfg[`SSYNC_CFG_MODE_BIT]                         = `SSYNC_MODE_PREAMBLE;
            cfg[`SSYNC_CFG_WIDTH_MSB:`SSYNC_CFG_WIDTH_LSB]   = `SSYNC_WIDTH_1;
            cfg[`SSYNC_CFG_LENGTH_MSB:`SSYNC_CFG_LENGTH_LSB] = 4'd7;
            cfg[`SSYNC_CFG_CLKDIV_MSB:`SSYNC_CFG_CLKDIV_LSB] = 10'd100;
            apb_write(1'b0, `SSYNC_REG_CFG, cfg); // B = TX side now
            apb_write(1'b1, `SSYNC_REG_CFG, cfg); // A = RX side now
            apb_write(1'b0, `SSYNC_REG_TXDATA, 32'h0000_00C3);

            begin
                logic [31:0] rd;
                int timeout;
                timeout = 0;
                do begin
                    @(posedge pclk);
                    apb_read(1'b1, `SSYNC_REG_RXSTATUS, rd);
                    timeout++;
                end while (rd[0] == 1'b0 && timeout < 6000);
                check(rd[0] == 1'b1, "T6: B->A rx_valid asserted");
                apb_read(1'b1, `SSYNC_REG_RXDATA, rd);
                check(rd[7:0] == 8'hC3, $sformatf("T6: B->A rxdata=%0h expected=c3", rd[7:0]));
            end
        end

        repeat (20) @(posedge pclk);

        $display("=====================================================");
        $display(" TOTAL CHECKS = %0d, ERRORS = %0d", checks, errors);
        if (errors == 0) $display(" RESULT: ALL TESTS PASSED");
        else              $display(" RESULT: FAILED");
        $display("=====================================================");

        if (errors != 0) $fatal(1, "Testbench failed with %0d errors", errors);
        $finish;
    end

    // safety watchdog
    initial begin
        #2_000_000;
        $display("FAIL: global watchdog timeout");
        $fatal(1, "watchdog timeout");
    end

endmodule
