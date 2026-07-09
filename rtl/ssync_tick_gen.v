//=============================================================
// ssync_tick_gen.v
//
// Generates a single-cycle "tick" pulse every `div` pclk cycles.
// This is a clock-ENABLE generator, not a divided clock: it never
// creates a new clock source, so STA does not see an extra clock
// domain (per spec section 3).
//
// `sync_rst` re-phases the internal counter to 0 on the same cycle
// it is asserted.
//
// `half_first`, sampled together with `sync_rst`, makes the very
// first tick after the restart occur at div/2 cycles instead of
// div cycles. This is used by the RX preamble-mode phase-lock: the
// edge that triggers the restart is only known after a 2..3 cycle
// synchronizer/detection latency, so ticking at the *center* of
// each bit period (instead of exactly at its boundary) gives margin
// against that latency instead of racing it.
//=============================================================
module ssync_tick_gen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sync_rst,   // pulse: restart phase, no tick this cycle
    input  wire        half_first, // sampled with sync_rst: first tick at div/2
    input  wire [9:0]  div,        // divide value, tick every `div` clk cycles
    output reg         tick        // 1-cycle enable pulse
);

    reg [9:0] cnt;
    reg       first_pending;

    // Guard against div==0 (out of spec range 100..1000, but keep FSM safe)
    wire [9:0] div_safe    = (div == 10'd0) ? 10'd1 : div;
    wire [8:0] half_target9 = div_safe[9:1];
    wire [9:0] half_target  = (half_target9 == 9'd0) ? 10'd0 : ({1'b0, half_target9} - 10'd1);
    wire [9:0] full_target = div_safe - 10'd1;
    wire [9:0] target      = first_pending ? half_target : full_target;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt           <= 10'd0;
            tick          <= 1'b0;
            first_pending <= 1'b0;
        end else if (sync_rst) begin
            cnt           <= 10'd0;
            tick          <= 1'b0;
            first_pending <= half_first;
        end else if (cnt == target) begin
            cnt           <= 10'd0;
            tick          <= 1'b1;
            first_pending <= 1'b0; // only the first post-restart tick uses half period
        end else begin
            cnt  <= cnt + 10'd1;
            tick <= 1'b0;
        end
    end

endmodule
