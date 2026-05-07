# Include all sub-makefiles
include config.mk
include env.mk
include simx.mk
include program.mk
include compile.mk
include simulate.mk
include report.mk

.PHONY: all clean_all help env_check build_simx setup_dirs prepare_program compile simulate report

all: report

clean_all:
	@echo -e "${BLUE}ℹ Cleaning up workspace...${NC}"
	rm -rf work transcript *.log *.vcd $(RESULTS_BASE)/latest $(UVM_REF_MODEL_DIR)/simx_model.so

help:
	@echo -e "${CYAN}Vortex UVM Test Runner (Makefile version)${NC}"
	@echo -e "${CYAN}=========================================${NC}"
	@echo -e "${YELLOW}Usage:${NC}"
	@echo "  make all [OPTIONS]"
	@echo ""
	@echo -e "${YELLOW}Options:${NC}"
	@echo "  TEST=test_name       (Default: vortex_sanity_test)"
	@echo "  PROGRAM=prog_name    (e.g., vecadd, rv32ui-p-add, or path to .hex)"
	@echo "  CORES=N              (Default: 1)"
	@echo "  WARPS=N              (Default: 4)"
	@echo "  CLEAN=1              Clean work dir before compile"