# Paths (Adjust to your WSL directory)
VORTEX_HOME   ?= /home/samuel_ubuntu22/Vortex_UVM_GP/Vortex
QUESTA_HOME   = /home/samuel_ubuntu22/opt/questa_sim-2021.2_1/questasim
SIMX_DIR      = $(VORTEX_HOME)/sim/simx
COMMON_DIR    = $(VORTEX_HOME)/sim/common
THIRD_PARTY   = $(VORTEX_HOME)/third_party

# Compiler
# --- ADDED QUESTA INCLUDE PATH HERE ---

CXX           = g++
CXXFLAGS      = -std=c++17 -fPIC -shared -Wall
CXXFLAGS    += -I$(QUESTA_HOME)/include
CXXFLAGS     += -I$(SIMX_DIR) -I$(COMMON_DIR) -I$(VORTEX_HOME)/hw -I$(VORTEX_HOME)/hw/rtl/libs
CXXFLAGS     += -I$(THIRD_PARTY)/softfloat/source/include
CXXFLAGS     += -I$(THIRD_PARTY)/ramulator/src
CXXFLAGS     += -DXLEN_32 -DNUM_CORES=2 -DNUM_WARPS=4 -DNUM_THREADS=4

# Linker flags from the original SimX Makefile
LDFLAGS       = $(THIRD_PARTY)/softfloat/build/Linux-x86_64-GCC/softfloat.a
LDFLAGS      += -L$(THIRD_PARTY)/ramulator -lramulator

# Objects from the pre-built SimX
SIMX_OBJS     = $(SIMX_DIR)/obj/*.o $(SIMX_DIR)/obj/common/*.o

DPI_LIB       = simx_model.so

$(DPI_LIB): simx_dpi.cpp
	@echo "--- Compiling DPI Shared Library ---"
	$(CXX) $(CXXFLAGS) simx_dpi.cpp $(SIMX_OBJS) $(LDFLAGS) -o $(DPI_LIB)

run: $(DPI_LIB)
	vlib work
	vlog +incdir+$(VORTEX_HOME)/hw/rtl vortex_config.sv test_top.sv
	# Add the ramulator path to LD_LIBRARY_PATH so Questa can find it at runtime
	LD_LIBRARY_PATH=$(LD_LIBRARY_PATH):$(THIRD_PARTY)/ramulator \
	vsim -c test_top -sv_lib $(DPI_LIB) -do "run -all; quit"

clean:
	rm -rf work vsim.wlf $(DPI_LIB) transcript