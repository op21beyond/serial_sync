# CLAUDE.md

Project guidance for working in this repository.

## What this is

`ssync` — a chip-to-chip serial sync signal transceiver in Verilog.
APB-programmable, one TX path and one independent RX path.

The authoritative specification is **`doc/spec.md`**. Read it before
changing RTL. It also records, in a separate section, the decisions that
were made where the original spec was silent — do not silently change
those; if a decision turns out wrong, update the spec section too.

## Layout

| Dir    | Contents |
|--------|----------|
| `doc/` | Specification (`spec.md`) |
| `rtl/` | Synthesizable Verilog. This is the deliverable. |
| `tb/`  | SystemVerilog testbench. Simulation only, never synthesized. |
| `sim/` | Verilator Makefile |
| `syn/` | Synthesis file list and STA notes |
| `lint/`| Lint script |

## Commands

```sh
./lint/run_lint.sh      # RTL lint; must be clean before committing
cd sim && make run      # build + run testbench, prints PASS/FAIL summary
cd sim && make wave     # same, plus FST waveform in sim/build/
cd sim && make clean
```

The simulator is **Verilator** (5.x, uses `--binary --timing`).

## Hard requirements

These come from the spec and are not negotiable:

1. **Synthesizable.** No `initial` blocks, no delays, no non-synthesizable
   constructs in `rtl/`.
2. **No inferred latches.** Every `always @(*)` assigns all its outputs on
   every path. `lint/run_lint.sh` enforces this and fails on any warning.
3. **No generated clocks.** The serial bit rate comes from a clock-*enable*
   pulse (`ssync_tick_gen`), never a divided clock. Everything is clocked by
   `pclk`. Do not introduce a second clock source.
4. **`cfg.length` must be a multiple of N** (`cfg.width`), 1..16.
5. **TXDATA writes are ignored while `tx_busy`.**

## Conventions

- Verilog-2001 in `rtl/`, SystemVerilog allowed in `tb/`.
- All flops use `always @(posedge pclk or negedge presetn)` with async
  active-low reset.
- All module outputs are registered.
- Cross-chip inputs (`ss_rx_clk`, `ss_rx_data`) are treated as
  asynchronous and double-flopped before use. Never use them raw.

## Gotchas learned the hard way

- **`rx_valid` does not mean TX is done.** The TX holds the final bit group
  on the line for one extra tick so the receiver's synchronizer can capture
  it. A testbench that starts the next frame on `rx_valid` will have its
  `TXDATA` write silently dropped by the busy check. Poll `TXSTATUS.tx_busy`.
- **APB side effects must be edge-triggered.** `psel & penable` can be
  observed high on more than one `pclk` edge. Register-block side effects
  (the `TXDATA` write pulse, the `RXSTATUS` clear-on-read) fire on the
  *rising edge* of that condition, exactly once per transfer. Do not revert
  this to a level check.
- **Preamble mode samples at the bit center, not the bit boundary.** RX locks
  its tick counter to the detected preamble edge with `half_first=1`, so the
  first tick lands mid-bit. The input synchronizer costs 2-3 cycles; sampling
  at the boundary races it.

## Before committing

1. `./lint/run_lint.sh` — clean
2. `cd sim && make run` — `RESULT: ALL TESTS PASSED`
