COMPILE_OPTS := +define+FPU_FPNEW +define+NUM_CLUSTERS=$(CLUSTERS) +define+NUM_CORES=$(CORES) \
                +define+NUM_WARPS=$(WARPS) +define+NUM_THREADS=$(THREADS) +define+XLEN_$(XLEN) \
                +define+ICACHE_MSHR_SIZE=16 +define+DCACHE_MSHR_SIZE=16 \
                +define+ICACHE_MREQ_SIZE=16 +define+DCACHE_MREQ_SIZE=16

ifeq ($(INTERFACE),axi)
	COMPILE_OPTS += +define+USE_AXI_WRAPPER
endif
ifeq ($(DEBUG_ADDR),1)
    COMPILE_OPTS += +define+DBG_ADDR_CALC +define+DBG_LSU_ADDR
endif
ifeq ($(NO_TCU),0)
	COMPILE_OPTS += +define+TCU_BHF
endif

SIMX_REF_DIR := $(VORTEX_UVM_HOME)/uvm_env/ref_model
# Pass XLEN to the C++ SimX model as well!
SIMX_ARCH_FLAGS := -DNUM_CLUSTERS=$(CLUSTERS) -DNUM_CORES=$(CORES) -DNUM_WARPS=$(WARPS) -DNUM_THREADS=$(THREADS) -DXLEN_$(XLEN)

build_simx:
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${CYAN}SimX Golden Model${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${BLUE}ℹ Building SimX DPI library...${NC}"
	@$(MAKE) -C $(SIMX_REF_DIR) build \
		VORTEX_HOME="$(VORTEX_HOME)" \
		QUESTA_HOME="$(QUESTA_HOME)" \
		EXTRA_CXXFLAGS="$(SIMX_ARCH_FLAGS)"
	@echo -e "${GREEN}✓ SimX DPI built and linked: simx_model.so${NC}"

compile: prepare_program build_simx
	@if [ "$(CLEAN)" = "1" ]; then \
		echo -e "${CYAN}================================================================================${NC}"; \
		echo -e "${CYAN}Cleaning${NC}"; \
		echo -e "${CYAN}================================================================================${NC}"; \
		cd $(VORTEX_UVM_HOME)/flists && rm -rf work; echo -e "${GREEN}✓ Clean complete${NC}"; \
	fi
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${CYAN}Compilation${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@RTL_FLIST="vortex_rtl.flist"; \
	if [ "$(NO_TCU)" = "1" ]; then \
		echo -e "${YELLOW}⚠ WARNING: TCU disabled. Generating stripped flist...${NC}"; \
		RTL_FLIST="$(RUN_DIR)/vortex_rtl_notcu.flist"; \
		cd $(VORTEX_UVM_HOME)/flists && sed '/[\/]tcu[\/]/s/^/# NOTCU: /' vortex_rtl.flist | sed '/[\/]tcu$$/s/^/# NOTCU: /' | sed '/+define+EXT_TCU_ENABLE/s/^/# NOTCU: /' > "$$RTL_FLIST"; \
	else \
		echo -e "${BLUE}ℹ TCU: enabled (TCU_BHF)${NC}"; \
	fi; \
	echo -e "${BLUE}ℹ Interface: $(shell echo $(INTERFACE) | tr a-z A-Z) ${NC}"; \
	echo -e "${BLUE}ℹ Compiling Vortex RTL...${NC}"; \
	cd $(VORTEX_UVM_HOME)/flists && vlog -sv $(COMPILE_OPTS) +incdir+$(VORTEX_HOME)/third_party/cvfpu/src/common_cells/include -f $$RTL_FLIST 2>&1 | tee $(RUN_DIR)/logs/compile.log
	@echo -e "${GREEN}✓ RTL compiled${NC}"
	@echo -e "${BLUE}ℹ Compiling UVM environment...${NC}"
	@echo -e "${BLUE}ℹ Using UVM source from: $(UVM_HOME)${NC}"
	@cd $(VORTEX_UVM_HOME)/flists && vlog -sv $(COMPILE_OPTS) +incdir+$(UVM_HOME) $(UVM_HOME)/uvm_pkg.sv 2>&1 | tee -a $(RUN_DIR)/logs/compile.log
	@cd $(VORTEX_UVM_HOME)/flists && vlog -sv $(COMPILE_OPTS) +incdir+$(UVM_HOME) -f uvm_env.flist 2>&1 | tee -a $(RUN_DIR)/logs/compile.log