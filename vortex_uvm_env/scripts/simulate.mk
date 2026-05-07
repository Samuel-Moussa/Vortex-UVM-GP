SIM_OPTS := +UVM_TESTNAME=$(TEST) +NUM_CLUSTERS=$(CLUSTERS) +NUM_CORES=$(CORES) +NUM_WARPS=$(WARPS) +NUM_THREADS=$(THREADS) +TIMEOUT=$(TIMEOUT) +STARTUP_ADDR=80000000
ifeq ($(INTERFACE),axi)
	SIM_OPTS += +USE_AXI_WRAPPER
endif
ifeq ($(VERBOSE),1)
	SIM_OPTS += +VERBOSE=1
endif
ifeq ($(NO_WAVES),0)
	SIM_OPTS += +WAVE=$(RUN_DIR)/waves/$(TEST)_$(INTERFACE).vcd
endif

DPI_FLAG := -sv_lib $(UVM_DPI_LIB) -sv_lib $(VORTEX_UVM_HOME)/uvm_env/ref_model/simx_model

simulate: compile
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${CYAN}Simulation${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${BLUE}ℹ Test:      $(TEST)${NC}"
	@echo -e "${BLUE}ℹ Config:    $(CLUSTERS)CL $(CORES)C $(WARPS)W $(THREADS)T${NC}"
	@echo -e "${BLUE}ℹ Interface: $(INTERFACE)${NC}"
	@EXTRA_SIM_OPTS=""; \
	if [ -f "$(RUN_DIR)/programs/current_hex_path.txt" ]; then \
		HEX_PATH=$$(cat $(RUN_DIR)/programs/current_hex_path.txt); \
		if [ -n "$$HEX_PATH" ]; then \
			EXTRA_SIM_OPTS="+PROGRAM=$$HEX_PATH"; \
			echo -e "${BLUE}ℹ Program:   $$HEX_PATH${NC}"; \
		fi; \
	fi; \
	cd $(VORTEX_UVM_HOME)/flists && export LD_LIBRARY_PATH="$(VORTEX_HOME)/hw/dpi:$$LD_LIBRARY_PATH" && \
	vsim -c vortex_tb_top $(SIM_OPTS) $$EXTRA_SIM_OPTS $(DPI_FLAG) -do "run -all; quit -f" 2>&1 | tee $(RUN_DIR)/logs/simulation.log