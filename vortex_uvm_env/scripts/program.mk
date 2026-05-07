prepare_program: build_simx setup_dirs
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${CYAN}Setting Up Results Directory${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${GREEN}✓ Results directory: $(RUN_DIR)${NC}"
	@echo -e "${BLUE}ℹ Latest results:    $(RESULTS_BASE)/latest${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${CYAN}Program Resolution${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@if [ -n "$(PROGRAM)" ]; then \
		PROGRAM_HEX=""; \
		if [[ "$(PROGRAM)" == *.hex ]]; then \
			if [ -f "$(PROGRAM)" ]; then \
				PROGRAM_HEX="$(PROGRAM)"; \
			elif [ -f "$${PROGRAM/\/scripts\//\/}" ]; then \
				PROGRAM_HEX="$${PROGRAM/\/scripts\//\/}"; \
				echo -e "${YELLOW}⚠ Auto-corrected hex path: $$PROGRAM_HEX${NC}"; \
			else \
				echo -e "${RED}✗ ERROR: Program $(PROGRAM) not found!${NC}"; exit 1; \
			fi; \
			echo -e "${GREEN}✓ Found hex file: $$PROGRAM_HEX${NC}"; \
			_FIRST=$$(head -1 "$$PROGRAM_HEX"); \
			if [[ "$$_FIRST" == "@80000000" ]]; then sed -i '1d' "$$PROGRAM_HEX"; fi; \
		elif [ -f "$(VORTEX_HOME)/tests/opencl/$(PROGRAM)/kernel.bin" ]; then \
			echo -e "${BLUE}ℹ Converting Vortex kernel: $(PROGRAM)${NC}"; \
			cp "$(VORTEX_HOME)/tests/opencl/$(PROGRAM)/kernel.bin" "$(RUN_DIR)/programs/kernel.bin"; \
			hexdump -v -e '1/4 "%08x\n"' "$(RUN_DIR)/programs/kernel.bin" > "$(RUN_DIR)/programs/kernel.hex"; \
			PROGRAM_HEX="$(RUN_DIR)/programs/kernel.hex"; \
		elif [ -f "$(RISCV_TOOLCHAIN_PATH)/target/share/riscv-tests/isa/$(PROGRAM)" ]; then \
			echo -e "${BLUE}ℹ Converting RISC-V test: $(PROGRAM)${NC}"; \
			elf2hex --bit-width 32 --input "$(RISCV_TOOLCHAIN_PATH)/target/share/riscv-tests/isa/$(PROGRAM)" > "$(RUN_DIR)/programs/rv_test.hex"; \
			PROGRAM_HEX="$(RUN_DIR)/programs/rv_test.hex"; \
		else \
			echo -e "${RED}✗ ERROR: Program $(PROGRAM) not found!${NC}"; exit 1; \
		fi; \
		echo "$$PROGRAM_HEX" > $(RUN_DIR)/programs/current_hex_path.txt; \
	fi