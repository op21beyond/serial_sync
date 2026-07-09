#=============================================================
# sim/Makefile
# Verilator-based simulation for the ssync IP.
#
#   make        : build + run testbench, print PASS/FAIL summary
#   make wave   : build + run with FST waveform dump (build/tb_ssync_top.fst)
#   make clean  : remove build artifacts
#=============================================================
TOP        := tb_ssync_top
RTL_DIR    := ../rtl
TB_DIR     := ../tb
BUILD_DIR  := build

RTL_SRCS := $(RTL_DIR)/ssync_top.v \
            $(RTL_DIR)/ssync_regs.v \
            $(RTL_DIR)/ssync_tx.v \
            $(RTL_DIR)/ssync_rx.v \
            $(RTL_DIR)/ssync_tick_gen.v

TB_SRCS  := $(TB_DIR)/tb_ssync_top.sv

VERILATOR       := verilator
# -Wall is used for RTL cleanliness (see lint target); for the sim binary we
# additionally waive a few cosmetic/testbench-only warnings so build failures
# only happen on real issues.
VERILATOR_FLAGS := --binary --timing -sv -Wall -Wno-DECLFILENAME \
                    -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-BLKSEQ -Wno-INITIALDLY -Wno-SYNCASYNCNET \
                    --timescale 1ns/1ps \
                    -I$(RTL_DIR) \
                    --Mdir $(BUILD_DIR) \
                    --top-module $(TOP) \
                    --trace-fst

.PHONY: all run wave clean lint

all: run

$(BUILD_DIR)/V$(TOP): $(RTL_SRCS) $(TB_SRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL_SRCS) $(TB_SRCS)

run: $(BUILD_DIR)/V$(TOP)
	$(BUILD_DIR)/V$(TOP)

wave: $(BUILD_DIR)/V$(TOP)
	$(BUILD_DIR)/V$(TOP) --trace

lint:
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -I$(RTL_DIR) \
		--top-module ssync_top $(RTL_SRCS)

clean:
	rm -rf $(BUILD_DIR)
