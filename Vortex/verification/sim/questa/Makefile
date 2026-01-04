# Vortex QuestaSim Makefile - RTL Only (No SimX)
# Simple standalone RTL simulation without DPI-C dependencies

# Paths
VORTEX_ROOT := $(shell cd $(CURDIR)/../../.. && pwd)
RTL_DIR := $(VORTEX_ROOT)/hw/rtl
DPI_DIR := $(VORTEX_ROOT)/hw/dpi
TB_DIR := $(CURDIR)/tb
SCRIPT_DIR := $(VORTEX_ROOT)/sim/scripts
#SCRIPT_DIR := $(VORTEX_ROOT)/verification/sim/questa/scripts
WORK_DIR := $(CURDIR)/work
VXBIN_ROOT_BUILD32 := $(VORTEX_ROOT)/build/tests/regression

# Detect XLEN from current path
CUR_PATH := $(shell pwd)
ifneq (,$(findstring build32,$(CUR_PATH)))
    XLEN := 32
else ifneq (,$(findstring build64,$(CUR_PATH)))
    XLEN := 64
else
    XLEN := 32
endif

# QuestaSim tools
VLIB := vlib
VMAP := vmap
VLOG := vlog
VSIM := vsim
LIB := vortex_lib

# Compilation flags for RTL
VLOG_FLAGS := -sv
VLOG_FLAGS += -timescale=1ns/1ps
VLOG_FLAGS += +define+SIMULATION
VLOG_FLAGS += +define+XLEN_$(XLEN)
VLOG_FLAGS += +define+EXT_TEX_DISABLE
VLOG_FLAGS += +define+EXT_RASTER_DISABLE
VLOG_FLAGS += +define+EXT_ROP_DISABLE
VLOG_FLAGS += +define+EXT_IOMMU_DISABLE
VLOG_FLAGS += +define+EXT_F_DISABLE
VLOG_FLAGS += -suppress 2583
VLOG_FLAGS += -suppress 13314
VLOG_FLAGS += -suppress 2730
VLOG_FLAGS += -suppress 7061
#for off the counter flags in ~vortex/hw/rtl/libs/VX_pending_size.sv file 
VLOG_FLAGS += -suppress 8386  # Counter overflow
VLOG_FLAGS += -suppress 8387  # Counter underflow

# Include directories
VLOG_FLAGS += +incdir+$(RTL_DIR)
VLOG_FLAGS += +incdir+$(RTL_DIR)/libs
VLOG_FLAGS += +incdir+$(RTL_DIR)/interfaces
VLOG_FLAGS += +incdir+$(RTL_DIR)/core
VLOG_FLAGS += +incdir+$(RTL_DIR)/mem
VLOG_FLAGS += +incdir+$(RTL_DIR)/cache
VLOG_FLAGS += +incdir+$(RTL_DIR)/fpu
VLOG_FLAGS += +incdir+$(DPI_DIR)

# Configuration
NUM_CORES ?= 2
NUM_WARPS ?= 4
NUM_THREADS ?= 4
VLOG_FLAGS += +define+NUM_CORES=$(NUM_CORES)
VLOG_FLAGS += +define+NUM_WARPS=$(NUM_WARPS)
VLOG_FLAGS += +define+NUM_THREADS=$(NUM_THREADS)

# DPI-C flags (minimal, for RTL DPI functions only, not SimX)
DPI_FLAGS := -dpiheader $(WORK_DIR)/dpi_types.h

# File lists
RTL_FLIST := $(WORK_DIR)/rtl_files.f

# Simulation flags
VSIM_FLAGS := -lib $(LIB)
VSIM_FLAGS += -c
VSIM_FLAGS += -do "run -all; quit -f"

# Test configuration
KERNEL_FILE ?= kernel.bin

ifdef WAVES
    VSIM_FLAGS += +DUMP_VCD
    VSIM_FLAGS += -wlf vortex_sim.wlf
    VSIM_FLAGS += -do "log -r /*; run -all; quit -f"
endif

ifdef GUI
    VSIM_FLAGS := -lib $(LIB)
    VSIM_FLAGS += -do "log -r /*;"
endif

.PHONY: all help clean compile sim lib flist info list_tests sim_vecadd sim_test sim_minimal

all: compile

help:
	@echo "Vortex RTL-Only QuestaSim Makefile"
	@echo "===================================="
	@echo ""
	@echo "This Makefile simulates Vortex RTL WITHOUT SimX"
	@echo "(No DPI-C integration, no library conflicts)"
	@echo ""
	@echo "Targets:"
	@echo "  make lib              - Create QuestaSim library"
	@echo "  make flist            - Generate RTL file list"
	@echo "  make compile          - Compile RTL and testbench"
	@echo "  make sim_vecadd       - Run vecadd test"
	@echo "  make sim_test TEST=<n> - Run any test"
	@echo "  make list_tests       - Show available built tests"
	@echo "  make clean            - Remove generated files"
	@echo "  make info             - Show configuration"
	@echo ""
	@echo "Options:"
	@echo "  NUM_CORES=N          - Set number of cores (default: 2)"
	@echo "  NUM_WARPS=N          - Set number of warps (default: 4)"
	@echo "  NUM_THREADS=N        - Set number of threads (default: 4)"
	@echo "  WAVES=1              - Enable waveform generation"
	@echo "  GUI=1                - Run in GUI mode"
	@echo ""
	@echo "Examples:"
	@echo "  make compile NUM_CORES=2"
	@echo "  make sim_vecadd WAVES=1"
	@echo "  make sim_test TEST=sgemm GUI=1"
	@echo ""
	@echo "Building tests (use Vortex blackbox.sh):"
	@echo "  cd ~/vortex"
	@echo "  ./ci/blackbox.sh --driver=simx --app=vecadd"

lib:
	@echo "Creating QuestaSim library: $(LIB)"
	@mkdir -p $(WORK_DIR)
	@mkdir -p $(TB_DIR)
	@rm -rf $(WORK_DIR)/$(LIB)
	$(VLIB) $(WORK_DIR)/$(LIB)
	$(VMAP) work $(WORK_DIR)/$(LIB)
	@echo "Library created successfully"

flist: lib
	@echo "Generating RTL file list..."
	@python3 $(SCRIPT_DIR)/generate_flist.py $(RTL_DIR) $(RTL_FLIST) $(XLEN)

compile_dpi: lib
	@echo "Compiling DPI sources (utility functions only)..."
	$(VLOG) $(VLOG_FLAGS) $(DPI_FLAGS) -work $(LIB) \
		$(DPI_DIR)/util_dpi.vh $(DPI_DIR)/float_dpi.vh
	@echo "DPI compilation complete"

compile_rtl: flist
	@echo "Compiling RTL files (XLEN=$(XLEN), NUM_CORES=$(NUM_CORES))..."
	$(VLOG) $(VLOG_FLAGS) $(DPI_FLAGS) -work $(LIB) -f $(RTL_FLIST)
	@echo "RTL compilation complete"

compile_tb: compile_rtl compile_dpi
	@echo "Compiling RTL-only testbench..."
	$(VLOG) $(VLOG_FLAGS) -work $(LIB) $(TB_DIR)/tb_top_rtl_only.sv
	@echo "Testbench compilation complete"
	
compile_minimal: compile_rtl compile_dpi
	@echo "Compiling minimal sanity test..."
	$(VLOG) $(VLOG_FLAGS) -work $(LIB) $(TB_DIR)/tb_minimal_test.sv
	@echo "Minimal test compilation complete"

compile: lib compile_dpi compile_rtl compile_tb
	@echo ""
	@echo "===================================="
	@echo "Compilation successful!"
	@echo "XLEN:        $(XLEN)"
	@echo "NUM_CORES:   $(NUM_CORES)"
	@echo "NUM_WARPS:   $(NUM_WARPS)"
	@echo "NUM_THREADS: $(NUM_THREADS)"
	@echo "===================================="

sim: compile
	@echo "Running simulation with kernel: $(KERNEL_FILE)"
	$(VSIM) $(VSIM_FLAGS) +KERNEL=$(KERNEL_FILE) tb_top_rtl_only

sim_vecadd: compile
	@echo "Preparing vecadd test..."
	@if [ ! -f $(VXBIN_ROOT_BUILD32)/vecadd/kernel.vxbin ]; then \
		echo "ERROR: vecadd not built yet!"; \
		echo "Please build it first:"; \
		echo "  cd $(VORTEX_ROOT)"; \
		echo "  ./ci/blackbox.sh --driver=simx --app=vecadd"; \
		exit 1; \
	fi
	@echo "Copying kernel from: $(VXBIN_ROOT_BUILD32)/vecadd/kernel.vxbin"
	@cp $(VXBIN_ROOT_BUILD32)/vecadd/kernel.vxbin $(WORK_DIR)/kernel.bin
	@echo "Running vecadd simulation (RTL only)..."
	$(VSIM) $(VSIM_FLAGS) +KERNEL=$(WORK_DIR)/kernel.bin tb_top_rtl_only

sim_minimal: compile_minimal
	@echo "=========================================="
	@echo "Running Minimal Sanity Test"
	@echo "  - No kernel required"
	@echo "  - Just tests clock, reset, basic signals"
	@echo "  - Generates waveform: vortex_minimal.vcd"
	@echo "=========================================="
	$(VSIM) $(VSIM_FLAGS) tb_minimal_test
	@echo ""
	@echo "Test complete! View waveform with:"
	@echo "  gtkwave vortex_minimal.vcd &	
	
sim_test: compile
	@if [ -z "$(TEST)" ]; then \
		echo "ERROR: TEST not specified!"; \
		echo "Usage: make sim_test TEST=<testname>"; \
		make list_tests; \
		exit 1; \
	fi
	@if [ ! -f $(VXBIN_ROOT_BUILD32)/$(TEST)/kernel.vxbin ]; then \
		echo "ERROR: $(TEST) not built yet!"; \
		echo "Please build it first:"; \
		echo "  cd $(VORTEX_ROOT)"; \
		echo "  ./ci/blackbox.sh --driver=simx --app=$(TEST)"; \
		exit 1; \
	fi
	@echo "Preparing $(TEST) test..."
	@echo "Copying kernel from: $(VXBIN_ROOT_BUILD32)/$(TEST)/kernel.vxbin"
	@cp $(VXBIN_ROOT_BUILD32)/$(TEST)/kernel.vxbin $(WORK_DIR)/kernel.bin
	@echo "Running $(TEST) simulation (RTL only)..."
	$(VSIM) $(VSIM_FLAGS) +KERNEL=$(WORK_DIR)/kernel.bin tb_top_rtl_only

list_tests:
	@echo "Available built tests:"
	@echo "====================="
	@for dir in $(VXBIN_ROOT_BUILD32)/*; do \
		if [ -d "$$dir" ] && [ -f "$$dir/kernel.vxbin" ]; then \
			test_name=$$(basename $$dir); \
			size=$$(stat -c%s "$$dir/kernel.vxbin" 2>/dev/null || stat -f%z "$$dir/kernel.vxbin" 2>/dev/null); \
			printf "  %-15s (%'d bytes)\n" "$$test_name" "$$size"; \
		fi; \
	done
	@echo ""
	@echo "Usage:"
	@echo "  make sim_vecadd              # Run vecadd"
	@echo "  make sim_test TEST=sgemm     # Run any test"

clean:
	@echo "Cleaning generated files..."
	rm -rf $(WORK_DIR)
	rm -rf transcript vsim.wlf *.vcd modelsim.ini
	@echo "Clean complete"

info:
	@echo "Configuration:"
	@echo "  VORTEX_ROOT    : $(VORTEX_ROOT)"
	@echo "  RTL_DIR        : $(RTL_DIR)"
	@echo "  DPI_DIR        : $(DPI_DIR)"
	@echo "  VXBIN_DIR      : $(VXBIN_ROOT_BUILD32)"
	@echo "  XLEN           : $(XLEN)"
	@echo "  NUM_CORES      : $(NUM_CORES)"
	@echo "  NUM_WARPS      : $(NUM_WARPS)"
	@echo "  NUM_THREADS    : $(NUM_THREADS)"
	@echo "  LIB            : $(LIB)"
	@echo "  KERNEL_FILE    : $(KERNEL_FILE)"
