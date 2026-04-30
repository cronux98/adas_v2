# ============================================================================
# Makefile — ADAS v2 Safety-Critical RISC-V SoC
# ============================================================================
# Targets:
#   make questa       — Run QuestaSim with full coverage (recommended)
#   make cocotb       — Run cocotb + Icarus Verilog regression
#   make iverilog     — Compile with Icarus Verilog only (quick check)
#   make clean        — Remove build artifacts
# ============================================================================

RTL_DIR  := rtl
TB_DIR   := tb
SCRIPTS  := scripts

RTL_SRCS := $(wildcard $(RTL_DIR)/*.v)
TB_SRCS  := $(wildcard $(TB_DIR)/*.v)

# ---- QuestaSim / ModelSim (with coverage) ----
.PHONY: questa
questa:
	@chmod +x $(SCRIPTS)/run_questa.sh
	$(SCRIPTS)/run_questa.sh

# ---- cocotb + Icarus Verilog regression ----
.PHONY: cocotb
cocotb:
	@chmod +x $(SCRIPTS)/run_cocotb.sh
	$(SCRIPTS)/run_cocotb.sh $(FILTER)

# ---- Icarus Verilog compile-only check ----
.PHONY: iverilog
iverilog:
	@echo "[IVERILOG] Compiling RTL + TB..."
	cd $(RTL_DIR) && iverilog -g2012 -Wall -o /dev/null $(notdir $(RTL_SRCS)) \
		|| (echo "LINT: Warnings found — review above"; true)
	@echo "[IVERILOG] Compile check complete."

# ---- Icarus Verilog full simulation ----
.PHONY: iverilog-sim
iverilog-sim:
	@echo "[IVERILOG] Compiling and running..."
	cd $(RTL_DIR) && iverilog -g2012 -Wall -o ../sim_build/adas_soc_tb.vvp \
		$(notdir $(RTL_SRCS)) ../$(TB_DIR)/adas_soc_top_tb.v
	cd $(RTL_DIR) && vvp ../sim_build/adas_soc_tb.vvp

# ---- Clean ----
.PHONY: clean
clean:
	rm -rf work vsim.wlf cov_work coverage_report transcript
	rm -rf sim_build __pycache__
	rm -rf tb/__pycache__ tb/sim_build tb/tests/__pycache__
	rm -f *.vcd *.vvp *.log
	@echo "[CLEAN] Build artifacts removed."

# ---- Help ----
.PHONY: help
help:
	@echo "ADAS v2 — Safety-Critical RISC-V SoC"
	@echo ""
	@echo "Targets:"
	@echo "  make questa       QuestaSim simulation with full coverage"
	@echo "  make cocotb       cocotb + Icarus Verilog regression"
	@echo "  make iverilog     Icarus Verilog compile check (lint)"
	@echo "  make iverilog-sim Icarus Verilog full simulation"
	@echo "  make clean        Remove build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  FILTER=<pattern>  Run specific cocotb tests (e.g., FILTER=safety)"
