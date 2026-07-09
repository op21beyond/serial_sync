#!/bin/sh
#=============================================================
# lint/run_lint.sh
#
# RTL lint using Verilator. This checks the synthesizable RTL
# only (not the testbench) and treats every warning as fatal,
# which is what enforces the two hard requirements from the
# spec: the design must be synthesizable, and it must not infer
# any latches.
#
# Usage:  ./lint/run_lint.sh      (from repo root)
#=============================================================
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL="$ROOT/rtl"

RTL_SRCS="$RTL/ssync_top.v \
          $RTL/ssync_regs.v \
          $RTL/ssync_tx.v \
          $RTL/ssync_rx.v \
          $RTL/ssync_tick_gen.v"

echo "== Verilator lint (-Wall, warnings are errors) =="
verilator --lint-only -Wall \
    -Wno-DECLFILENAME \
    -Wwarn-LATCH \
    -I"$RTL" \
    --top-module ssync_top \
    $RTL_SRCS

echo ""
echo "LINT CLEAN: no warnings, no inferred latches."
