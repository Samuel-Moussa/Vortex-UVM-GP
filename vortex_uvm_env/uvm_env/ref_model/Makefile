################################################################################
# Makefile for Vortex SimX DPI Integration
# Fixed version with proper header paths and DCR support
################################################################################

# Paths
VORTEX_HOME   ?= /home/stev_teto_22/vortex
QUESTA_HOME   = /home/stev_teto_22/mgc/install.aol/intelFPGA/21.2/questa_sim/questasim
SIMX_DIR      = $(VORTEX_HOME)/sim/simx
COMMON_DIR    = $(VORTEX_HOME)/sim/common
THIRD_PARTY   = $(VORTEX_HOME)/third_party
HW_DIR        = $(VORTEX_HOME)/hw

# Test selection (default)
TEST_MODE     ?= simple_postmortem
# KERNEL_BIN    ?= $(VORTEX_HOME)/tests/kernel/kernel.bin
# KERNEL_BIN    ?= $(VORTEX_HOME)/build32/verification/sim/questa/simx_dpi_3/tests/pro_1.bin
KERNEL_BIN    ?= /home/stev_teto_22/vortex_uvm/uvm_env/ref_model/program_simple.bin
STEP_CYCLES   ?= 10
TIMEOUT       ?= 100000

# Compiler settings
CXX           = g++
CXXFLAGS      = -std=c++17 -fPIC -shared -Wall -Wno-unused-variable
CXXFLAGS     += -I$(QUESTA_HOME)/include

# SimX includes
CXXFLAGS     += -I$(SIMX_DIR)
CXXFLAGS     += -I$(COMMON_DIR)

# Hardware includes (for VX_config.h, VX_types.h, VX_define.vh)
CXXFLAGS     += -I$(HW_DIR)
CXXFLAGS     += -I$(HW_DIR)/rtl
CXXFLAGS     += -I$(HW_DIR)/rtl/libs
CXXFLAGS     += -I$(HW_DIR)/rtl/interfaces
CXXFLAGS     += -I$(HW_DIR)/rtl/cache

# Third-party includes
CXXFLAGS     += -I$(THIRD_PARTY)/softfloat/source/include
CXXFLAGS     += -I$(THIRD_PARTY)/ramulator/src
CXXFLAGS     += -I$(THIRD_PARTY)/cvfpu/src

# Architecture configuration to solve processor problems
ARCH_CONFIGS  = -DNUM_CLUSTERS=1
ARCH_CONFIGS += -DNUM_CORES=2
ARCH_CONFIGS += -DNUM_WARPS=4
ARCH_CONFIGS += -DNUM_THREADS=4
ARCH_CONFIGS += -DXLEN_64
CXXFLAGS     += $(ARCH_CONFIGS)
CXXFLAGS     += $(EXTRA_CXXFLAGS)

# Architecture defines (should match your Vortex build)
# CXXFLAGS     += -DXLEN_32
# CXXFLAGS     += -DNUM_CORES=2
# CXXFLAGS     += -DNUM_WARPS=4
# CXXFLAGS     += -DNUM_THREADS=4

# Debug settings
CXXFLAGS     += -DDEBUG_LEVEL=3
CXXFLAGS     += -g
CXXFLAGS     += -UNDEBUG 

# Linker flags
LDFLAGS       = $(THIRD_PARTY)/softfloat/build/Linux-x86_64-GCC/softfloat.a
LDFLAGS      += -L$(THIRD_PARTY)/ramulator -lramulator
LDFLAGS      += -Wl,-rpath,$(THIRD_PARTY)/ramulator

# SimX objects - you need to build SimX first!
SIMX_OBJS     = $(SIMX_DIR)/obj/*.o $(SIMX_DIR)/obj/common/*.o

# DPI library
DPI_LIB       = simx_model.so
DPI_LIB_NAME  = simx_model

# Verilog sources
RTL_INCLUDE   = +incdir+$(VORTEX_HOME)/hw/rtl
RTL_INCLUDE  += +incdir+$(VORTEX_HOME)/hw/rtl/libs
RTL_INCLUDE  += +incdir+$(VORTEX_HOME)/hw/rtl/interfaces
SV_SOURCES    = vortex_config.sv
SV_PKG        = simx_pkg.sv
UVM_HOME      = $(QUESTA_HOME)/uvm-1.2
# VLOG_UVM_FLAGS = +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm_pkg.sv
VLOG_UVM_FLAGS = +incdir+$(UVM_HOME)

# Questa simulator settings
VSIM          = vsim
VLOG          = vlog
VLIB          = vlib
VSIM_FLAGS    = -c -sv_lib $(DPI_LIB_NAME) -voptargs="+acc"
VSIM_FLAGS   += -suppress 8887  # Suppress DPI warnings
VSIM_FLAGS   += -suppress 3116  # Suppress time unit warnings
export LD_LIBRARY_PATH := $(LD_LIBRARY_PATH):$(THIRD_PARTY)/ramulator

################################################################################
# Build Rules
################################################################################

.PHONY: all clean help build check_simx

all: help

# Check if SimX is built
check_simx:
	@echo "=== Checking SimX Build ==="
	@if [ ! -d "$(SIMX_DIR)/obj" ]; then \
		echo "ERROR: SimX not built! Build it first:"; \
		echo "  cd $(VORTEX_HOME)/sim/simx"; \
		echo "  make"; \
		exit 1; \
	fi
	@echo "SimX objects found"

# Build DPI library
$(DPI_LIB): check_simx simx_dpi.cpp
	@echo "=== Building DPI Shared Library ==="
	@echo "Compiler: $(CXX)"
	@echo "Flags: $(CXXFLAGS)"
	@echo "Objects: $(SIMX_OBJS)"
	$(CXX) $(CXXFLAGS) simx_dpi.cpp $(SIMX_OBJS) $(LDFLAGS) -o $(DPI_LIB)
	@echo "=== DPI Library built successfully ==="
	@ls -lh $(DPI_LIB)

build: $(DPI_LIB)


###############################################################################
# On The Fly testes
###############################################################################
# ── all on-the-fly hex tests ─────────────────────────────────────────────────
HEX_TESTS := test_alu test_lsu test_mext test_fpu test_simt test_mwarp test_branch test_pipeline 

# Map test name → result address (must match the hex file's lui x20, ...)
RESULT_ADDR_alu      := 0x80010000
RESULT_ADDR_lsu      := 0x80020000
RESULT_ADDR_mext     := 0x80030000
RESULT_ADDR_fpu      := 0x80040000
RESULT_ADDR_simt     := 0x80050000
RESULT_ADDR_mwarp    := 0x80060000
RESULT_ADDR_branch   := 0x80070000
RESULT_ADDR_pipeline := 0x80080000

# Watch words: how many 32-bit result words each test writes
WATCH_WORDS_alu      := 20
WATCH_WORDS_lsu      := 16
WATCH_WORDS_mext     := 16
WATCH_WORDS_fpu      := 16
WATCH_WORDS_simt     := 8
WATCH_WORDS_mwarp    := 8
WATCH_WORDS_branch   := 12
WATCH_WORDS_pipeline := 10

# On the fly testes
# Generic rule — run any test:  make otf_alu  /  make otf_fpu  / etc.
otf_%: $(DPI_LIB)
	@echo "=== OTF test: $* ============================================"
	$(VLIB) work
	$(VLOG) -sv $(VLOG_UVM_FLAGS) \
	        $(RTL_INCLUDE) $(SV_SOURCES) $(SV_PKG) \
	        test_otf_full.sv
	$(VSIM) $(VSIM_FLAGS) test_otf_full \
	        +HEX=$(CURDIR)/test_$*.hex \
	        +RESULT_ADDR=$(RESULT_ADDR_$*) \
	        +WATCH_WORDS=$(WATCH_WORDS_$*) \
	        +STEP=$(STEP_CYCLES) \
	        +TIMEOUT=$(TIMEOUT) \
	        -do "run -all; quit" \
	        | tee logs/otf_$*.log
	@echo "=== Done: $* exit=$$? ======================================="

# Run all hex tests in sequence
otf_all: $(DPI_LIB)
	@mkdir -p logs
	@for t in $(HEX_TESTS); do \
	    $(MAKE) otf_$$t || echo "FAILED: $$t"; \
	done
	@echo "=== All OTF tests complete ==================================="

.PHONY: otf_all $(addprefix otf_,$(HEX_TESTS))

################################################################################
# Test Targets
################################################################################

# 1. Simple Post-Mortem Test (inline program)
test_simple_postmortem: $(DPI_LIB)
	@echo "=== Running Simple Post-Mortem Test ==="
	$(VLIB) work
	$(VLOG) -sv $(VLOG_UVM_FLAGS) \
	        $(RTL_INCLUDE) \
	        $(SV_SOURCES) $(SV_PKG) \
	        test_top.sv
	$(VSIM) $(VSIM_FLAGS) test_top \
	        +dump_waves \
	        -do "run -all; quit"

# 2. Simple On-the-Fly Test (inline program)
test_simple_onthefly: $(DPI_LIB)
	@echo "=== Running Simple On-the-Fly Test ==="
	$(VLIB) work
	$(VLOG) -sv $(VLOG_UVM_FLAGS) \
	        $(RTL_INCLUDE) \
	        $(SV_SOURCES) $(SV_PKG) \
	        test_top_on_the_fly.sv
	$(VSIM) $(VSIM_FLAGS) test_top_on_the_fly \
	        +dump_waves \
	        +STEP_CYCLES=$(STEP_CYCLES) \
	        +TIMEOUT=$(TIMEOUT) \
	        -do "run -all; quit"

# 3. Binary Post-Mortem Test (load .bin file)
test_bin_postmortem: $(DPI_LIB)
	@echo "=== Running Binary Post-Mortem Test ===" 
	@if [ ! -f "$(KERNEL_BIN)" ]; then \
	    echo "ERROR: Kernel binary not found: $(KERNEL_BIN)"; \
	    exit 1; \
	fi
	$(VLIB) work
	$(VLOG) -sv $(VLOG_UVM_FLAGS) \
	        $(RTL_INCLUDE) \
	        $(SV_SOURCES) $(SV_PKG) \
	        test_bin.sv
	$(VSIM) $(VSIM_FLAGS) test_bin \
	        +BIN=$(KERNEL_BIN) \
	        +dump_waves \
	        +TIMEOUT=$(TIMEOUT) \
	        -do "run -all; quit"

# 4. Binary On-the-Fly Test (load .bin file, step execution)
test_bin_onthefly: $(DPI_LIB)
	@echo "=== Running Binary On-the-Fly Test ==="
	@if [ ! -f "$(KERNEL_BIN)" ]; then \
	    echo "ERROR: Kernel binary not found: $(KERNEL_BIN)"; \
	    exit 1; \
	fi
	$(VLIB) work
	$(VLOG) -sv $(VLOG_UVM_FLAGS) \
	        $(RTL_INCLUDE) \
	        $(SV_SOURCES) $(SV_PKG) \
	        test_bin_on_the_fly.sv
	$(VSIM) $(VSIM_FLAGS) test_bin_on_the_fly \
	        +BIN=$(KERNEL_BIN) \
	        +dump_waves \
	        +STEP_CYCLES=$(STEP_CYCLES) \
	        +TIMEOUT=$(TIMEOUT) \
	        -do "run -all; quit"

# 5. UVM Test (compiles full package chain)
test_uvm: $(DPI_LIB)
	@echo "=== Running UVM Package Test ==="
	$(VLIB) work
	$(VLOG) -sv $(VLOG_UVM_FLAGS) \
	        $(RTL_INCLUDE) \
	        $(SV_SOURCES) $(SV_PKG) \
	        test_top.sv
	$(VSIM) $(VSIM_FLAGS) test_top \
	        +dump_waves \
	        -do "run -all; quit"

# 6- testing on-the-fly for alu unit 
test_otf_alu: $(DPI_LIB)
	$(VLIB) work
	$(VLOG) -sv $(VLOG_UVM_FLAGS) $(RTL_INCLUDE) $(SV_SOURCES) $(SV_PKG) \
	        test_otf_full.sv
	$(VSIM) $(VSIM_FLAGS) test_otf_full \
	        +HEX=test_alu.hex \
	        +RESULT_ADDR=80010000 \
	        +STEP=1 \
	        +TIMEOUT=10000 \
	        +WATCH_WORDS=16 \
	        +LOG_INTERVAL=500 \
	        -do "run -all; quit"
################################################################################
# Interactive GUI Mode (for debugging)
################################################################################

gui_%: $(DPI_LIB)
	@echo "=== Running $* in GUI mode ==="
	$(VLIB) work
	@case "$*" in \
		simple_postmortem) \
			$(VLOG) $(RTL_INCLUDE) test_top.sv; \
			$(VSIM) -gui test_top -sv_lib $(DPI_LIB_NAME) -voptargs="+acc" +dump_waves;; \
		simple_onthefly) \
			$(VLOG) $(RTL_INCLUDE) test_top_on_the_fly.sv; \
			$(VSIM) -gui test_top_on_the_fly -sv_lib $(DPI_LIB_NAME) -voptargs="+acc" +dump_waves +STEP_CYCLES=$(STEP_CYCLES);; \
		bin_postmortem) \
			$(VLOG) $(RTL_INCLUDE) test_bin.sv; \
			$(VSIM) -gui test_bin -sv_lib $(DPI_LIB_NAME) -voptargs="+acc" +BIN=$(KERNEL_BIN) +dump_waves;; \
		bin_onthefly) \
			$(VLOG) $(RTL_INCLUDE) test_bin_on_the_fly.sv; \
			$(VSIM) -gui test_bin_on_the_fly -sv_lib $(DPI_LIB_NAME) -voptargs="+acc" +BIN=$(KERNEL_BIN) +dump_waves +STEP_CYCLES=$(STEP_CYCLES);; \
		uvm) \
			$(VLOG) $(RTL_INCLUDE) $(SV_SOURCES) test_top.sv; \
			$(VSIM) -gui test_top -sv_lib $(DPI_LIB_NAME) -voptargs="+acc" +dump_waves;; \
		*) echo "Unknown test mode: $*"; exit 1;; \
	esac

################################################################################
# Debug and Testing
################################################################################

# Test DPI library loading
test_lib:
	@echo "=== Testing DPI Library ==="
	@if [ -f $(DPI_LIB) ]; then \
		echo "Library exists: $(DPI_LIB)"; \
		file $(DPI_LIB); \
		nm -D $(DPI_LIB) | grep simx_ || echo "Warning: No simx_ symbols found"; \
		ldd $(DPI_LIB); \
	else \
		echo "ERROR: Library not found!"; \
		exit 1; \
	fi

# Show configuration
show_config:
	@echo "=== Build Configuration ==="
	@echo "VORTEX_HOME:  $(VORTEX_HOME)"
	@echo "QUESTA_HOME:  $(QUESTA_HOME)"
	@echo "SIMX_DIR:     $(SIMX_DIR)"
	@echo "THIRD_PARTY:  $(THIRD_PARTY)"
	@echo ""
	@echo "CXX:          $(CXX)"
	@echo "CXXFLAGS:     $(CXXFLAGS)"
	@echo ""
	@echo "DPI_LIB:      $(DPI_LIB)"
	@echo "KERNEL_BIN:   $(KERNEL_BIN)"

################################################################################
# Batch test runner
################################################################################

run: build
	@case "$(TEST_MODE)" in \
		simple_postmortem) $(MAKE) test_simple_postmortem;; \
		simple_onthefly) $(MAKE) test_simple_onthefly;; \
		bin_postmortem) $(MAKE) test_bin_postmortem;; \
		bin_onthefly) $(MAKE) test_bin_onthefly;; \
		uvm) $(MAKE) test_uvm;; \
		*) echo "Unknown TEST_MODE: $(TEST_MODE)"; $(MAKE) help; exit 1;; \
	esac

# Run all tests
test_all: build
	@echo "=== Running All Tests ==="
	@$(MAKE) test_simple_postmortem || echo "Simple post-mortem FAILED"
	@$(MAKE) test_simple_onthefly || echo "Simple on-the-fly FAILED"
	@$(MAKE) test_bin_postmortem || echo "Binary post-mortem skipped (no kernel)"
	@$(MAKE) test_bin_onthefly || echo "Binary on-the-fly skipped (no kernel)"
	@echo "=== All Tests Complete ==="

################################################################################
# Utility Targets
################################################################################
# Compile only the package chain (fast syntax/elaboration check)
compile_pkg: $(DPI_LIB)
	@echo "=== Compiling Package Chain ==="
	$(VLIB) work
	$(VLOG) -sv $(VLOG_UVM_FLAGS) \
	        $(RTL_INCLUDE) \
	        $(SV_SOURCES) $(SV_PKG)
	@echo "=== Package compilation successful ==="

clean:
	@echo "=== Cleaning build artifacts ==="
	rm -rf work
	rm -f $(DPI_LIB)
	rm -f vsim.wlf
	rm -f transcript
	rm -f *.vcd
	rm -f *.log

distclean: clean
	@echo "=== Deep clean ==="
	rm -rf modelsim.ini

help:
	@echo "================================================================================"
	@echo "  Vortex SimX DPI Makefile (Fixed DCR Support)"
	@echo "================================================================================"
	@echo ""
	@echo "Prerequisites:"
	@echo "  1. Build SimX first: cd $(VORTEX_HOME)/sim/simx && make"
	@echo "  2. Ensure Ramulator is built: $(THIRD_PARTY)/ramulator"
	@echo ""
	@echo "Build Targets:"
	@echo "  make build               - Build DPI shared library"
	@echo "  make show_config         - Show build configuration"
	@echo "  make test_lib            - Test DPI library loading"
	@echo ""
	@echo "Test Targets:"
	@echo "  make test_simple_postmortem   - Post-mortem with inline program"
	@echo "  make test_simple_onthefly     - On-the-fly with inline program"
	@echo "  make test_bin_postmortem      - Post-mortem with .bin file"
	@echo "  make test_bin_onthefly        - On-the-fly with .bin file"
	@echo "  make test_all                 - Run all available tests"
	@echo ""
	@echo "GUI Mode:"
	@echo "  make gui_simple_postmortem    - Debug in GUI"
	@echo "  make gui_simple_onthefly      - Debug in GUI"
	@echo "  make gui_bin_postmortem       - Debug in GUI"
	@echo "  make gui_bin_onthefly         - Debug in GUI"
	@echo ""
	@echo "Configuration Variables:"
	@echo "  KERNEL_BIN=$(KERNEL_BIN)"
	@echo "  STEP_CYCLES=$(STEP_CYCLES)"
	@echo "  TIMEOUT=$(TIMEOUT)"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make test_simple_postmortem"
	@echo "  make test_bin_onthefly KERNEL_BIN=mykernel.bin STEP_CYCLES=50"
	@echo "  make gui_simple_postmortem"
	@echo ""
	@echo "Troubleshooting:"
	@echo "  - If 'SimX not built' error: cd $(VORTEX_HOME)/sim/simx && make"
	@echo "  - If DCR errors: Check VX_config.h and VX_types.h are accessible"
	@echo "  - If library load errors: make test_lib"
	@echo ""
	@echo "Clean:"
	@echo "  make clean          - Remove build artifacts"
	@echo "  make distclean      - Deep clean"
	@echo "================================================================================"

.PHONY: test_simple_postmortem test_simple_onthefly test_bin_postmortem test_bin_onthefly
.PHONY: test_all run help clean distclean gui_% test_lib show_config compile_pkg test_otf_alu
