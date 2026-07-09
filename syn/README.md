# Synthesis notes

## File list

Synthesizable sources, in compile order:

```
rtl/ssync_defines.vh    (include only)
rtl/ssync_tick_gen.v
rtl/ssync_tx.v
rtl/ssync_rx.v
rtl/ssync_regs.v
rtl/ssync_top.v
```

Top module: `ssync_top`. Include directory: `rtl/`.

`tb/` is simulation-only and must not be compiled.

## Design intent relevant to synthesis / STA

- **No generated clocks.** The serial bit rate is produced by
  `ssync_tick_gen`, which emits a single-cycle *clock enable* pulse
  rather than a divided clock. Everything in the design is clocked by
  `pclk` only. This is deliberate (spec §3): a divided clock would
  force STA to treat it as a new clock source.
  Expect exactly **one** clock definition:

  ```
  create_clock -name pclk -period <T> [get_ports pclk]
  ```

- **No latches.** All combinational `always @(*)` blocks assign every
  output on every path (default branches present). Enforced by
  `lint/run_lint.sh`, which runs Verilator with `-Wall -Wwarn-LATCH`
  and fails on any warning.

- **Reset.** `presetn` is an active-low asynchronous reset, synchronously
  released (assumed to be handled by the SoC reset controller). Declare
  it as a false path or use `set_false_path -from [get_ports presetn]`
  depending on house style.

## Cross-chip timing

`ss_tx_clk` / `ss_tx_data` leave this chip and `ss_rx_clk` / `ss_rx_data`
arrive from a different chip with an independent (though nominally equal)
`pclk`. The RX path therefore treats its inputs as asynchronous and
double-flops them before use:

- `ssync_rx.clk_sync` (3-deep, for edge detection)
- `ssync_rx.data_s0` / `data_s1` (2-deep)

These synchronizer flops should be constrained accordingly, e.g.:

```
set_false_path -to [get_pins u_rx/clk_sync_reg[0]/D]
set_false_path -to [get_pins u_rx/data_s0_reg[*]/D]
```

and marked with the library's `ASYNC_REG`-equivalent attribute so the
flops are placed close together.

Because the serial bit period is `cfg.clkdiv` (100..1000) `pclk` cycles,
the synchronizer latency of 2-3 cycles is a very small fraction of a bit
period and does not eat into the sampling margin. The preamble-mode phase
lock additionally samples at the *center* of each bit (see the
`half_first` input of `ssync_tick_gen`) rather than at the bit boundary,
so the synchronizer delay is absorbed rather than raced against.

## Not included

No vendor-specific synthesis scripts are checked in. The RTL is plain
Verilog-2001 with no vendor primitives, so it should compile under any
standard flow (DC, Genus, Vivado, Yosys) using the file list above.
