SIMX_DIR := $(VORTEX_HOME)/sim/simx
UVM_REF_MODEL_DIR := $(VORTEX_UVM_HOME)/uvm_env/ref_model
SIMX_SO := $(UVM_REF_MODEL_DIR)/simx_model.so

# Huge g++ command derived exactly from your log
CXX := g++
CXXFLAGS := -std=c++17 -fPIC -shared -Wall -Wno-unused-variable \
	-I$(QUESTA_HOME)/include -I$(SIMX_DIR) -I$(VORTEX_HOME)/sim/common \
	-I$(VORTEX_HOME)/hw -I$(VORTEX_HOME)/hw/rtl -I$(VORTEX_HOME)/hw/rtl/libs \
	-I$(VORTEX_HOME)/hw/rtl/interfaces -I$(VORTEX_HOME)/hw/rtl/cache \
	-I$(VORTEX_HOME)/third_party/softfloat/source/include \
	-I$(VORTEX_HOME)/third_party/ramulator/src \
	-I$(VORTEX_HOME)/third_party/cvfpu/src \
	-DNUM_CLUSTERS=$(CLUSTERS) -DNUM_CORES=$(CORES) -DNUM_WARPS=$(WARPS) \
	-DNUM_THREADS=$(THREADS) -DXLEN_32 -DDEBUG_LEVEL=3 -g -UNDEBUG

LDFLAGS := -static-libstdc++ -static-libgcc \
	$(VORTEX_HOME)/third_party/softfloat/build/Linux-x86_64-GCC/softfloat.a \
	-L$(VORTEX_HOME)/third_party/ramulator -lramulator \
	-Wl,-rpath,$(VORTEX_HOME)/third_party/ramulator

build_simx: env_check
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${CYAN}SimX Golden Model${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${BLUE}ℹ Building SimX DPI library...${NC}"
	@echo -e "=== Checking SimX Build ==="
	@if ls $(SIMX_DIR)/obj/*.o >/dev/null 2>&1; then echo "SimX objects found"; else echo -e "${RED}SimX objects not found! Run make in sim/simx first.${NC}"; exit 1; fi
	@echo -e "=== Building DPI Shared Library ==="
	@cd $(UVM_REF_MODEL_DIR) && $(CXX) $(CXXFLAGS) simx_dpi.cpp $(SIMX_DIR)/obj/*.o $(SIMX_DIR)/obj/common/*.o $(LDFLAGS) -o simx_model.so
	@echo -e "=== DPI Library built successfully ==="
	@ls -lh $(SIMX_SO)
	@echo -e "${GREEN}✓ SimX DPI built and linked: simx_model.so${NC}"