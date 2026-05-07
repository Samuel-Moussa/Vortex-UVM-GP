env_check:
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${CYAN}Environment Check${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@if [ -z "$$VORTEX_HOME" ]; then echo -e "${RED}✗ VORTEX_HOME not set${NC}"; exit 1; else echo -e "${GREEN}✓ VORTEX_HOME: $$VORTEX_HOME${NC}"; fi
	@if [ -z "$$RISCV_TOOLCHAIN_PATH" ]; then echo -e "${RED}✗ RISC-V toolchain not found${NC}"; exit 1; else echo -e "${GREEN}✓ RISC-V toolchain found${NC}"; fi
	@echo -e "${GREEN}✓ Project root: $$VORTEX_UVM_HOME${NC}"
	@echo -e "${GREEN}✓ Simulator: Questa/ModelSim${NC}"
	@echo -e "${GREEN}✓ QUESTA_HOME: $$QUESTA_HOME${NC}"
	@echo -e "${GREEN}✓ UVM DPI: $$UVM_DPI_LIB.so${NC}"