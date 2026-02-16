#!/bin/bash

#=============================================================================
# UVM Environment Compilation Script for QuestaSim/ModelSim
# This script compiles all UVM testbench files in the correct order
#=============================================================================

# Exit on error
set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print with color
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#=============================================================================
# Configuration
#=============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use environment variables or set defaults
VORTEX_UVM_HOME="${VORTEX_UVM_HOME:-$HOME/Vortex_UVM_GP/vortex_uvm_env}"
VORTEX_HOME="${VORTEX_DUT_HOME:-$HOME/Vortex_UVM_GP/Vortex}"

# Verify paths
if [ ! -d "$VORTEX_UVM_HOME" ]; then
    print_error "VORTEX_UVM_HOME not found: $VORTEX_UVM_HOME"
    print_info "Set it in your environment or update this script"
    exit 1
fi

if [ ! -d "$VORTEX_HOME" ]; then
    print_error "VORTEX_HOME not found: $VORTEX_HOME"
    print_info "Set VORTEX_DUT_HOME in your environment"
    exit 1
fi

print_info "VORTEX_UVM_HOME: $VORTEX_UVM_HOME"
print_info "VORTEX_HOME: $VORTEX_HOME"
print_info "Script Directory: $SCRIPT_DIR"
print_info "Project Root: $PROJECT_ROOT"

# Detect QuestaSim version
if [ -n "$QUESTA_HOME" ]; then
    print_info "Using QUESTA_HOME: $QUESTA_HOME"
    MTI_HOME="$QUESTA_HOME"
elif [ -n "$QUESTA2021_HOME" ]; then
    print_info "Using QUESTA2021_HOME: $QUESTA2021_HOME"
    MTI_HOME="$QUESTA2021_HOME"
elif [ -n "$QUESTA2024_HOME" ]; then
    print_info "Using QUESTA2024_HOME: $QUESTA2024_HOME"
    MTI_HOME="$QUESTA2024_HOME"
else
    print_error "No QuestaSim installation found!"
    print_error "Please source your environment setup or run: source ~/.bashrc"
    exit 1
fi

# QuestaSim/ModelSim commands
VLOG="vlog"
VLIB="vlib"
VMAP="vmap"

# Check if commands are available
if ! command -v $VLOG &> /dev/null; then
    print_error "vlog command not found. Is QuestaSim in your PATH?"
    print_info "Current PATH: $PATH"
    exit 1
fi

print_info "QuestaSim version:"
vsim -version | head -n 1

#=============================================================================
# Compilation Options
#=============================================================================

# Compilation options for UVM
VLOG_OPTS="-sv -work work +acc -timescale=1ns/1ps"
VLOG_OPTS="$VLOG_OPTS +define+UVM_NO_DEPRECATED"
VLOG_OPTS="$VLOG_OPTS +define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR"
VLOG_OPTS="$VLOG_OPTS +define+SIMULATION"

# Suppress common warnings
VLOG_OPTS="$VLOG_OPTS -suppress 2223"  # Suppress timescale warnings
VLOG_OPTS="$VLOG_OPTS -suppress 13314" # Suppress empty module warnings
VLOG_OPTS="$VLOG_OPTS -suppress 2244"  # Suppress 'binding' warnings
VLOG_OPTS="$VLOG_OPTS -suppress 2388"  # Suppress always_comb warnings

# Add UVM library
VLOG_OPTS="$VLOG_OPTS -L mtiUvm"

# Include directories
VLOG_OPTS="$VLOG_OPTS +incdir+$VORTEX_HOME/hw/rtl"
VLOG_OPTS="$VLOG_OPTS +incdir+$VORTEX_HOME/hw/rtl/interfaces"
VLOG_OPTS="$VLOG_OPTS +incdir+$VORTEX_UVM_HOME/tb"
VLOG_OPTS="$VLOG_OPTS +incdir+$VORTEX_UVM_HOME/uvm_env"
VLOG_OPTS="$VLOG_OPTS +incdir+$VORTEX_UVM_HOME/uvm_tests"

# In scripts/compile_uvm.sh, after existing +incdir lines

VLOG_OPTS="$VLOG_OPTS +incdir+$VORTEX_HOME/hw/rtl/cache"
VLOG_OPTS="$VLOG_OPTS +incdir+$VORTEX_HOME/hw/rtl/fpu"
VLOG_OPTS="$VLOG_OPTS +incdir+$VORTEX_HOME/hw/rtl/mem"


# UVM Home (for includes)
if [ -n "$UVM_HOME" ]; then
    print_info "UVM_HOME: $UVM_HOME"
    VLOG_OPTS="$VLOG_OPTS +incdir+$UVM_HOME"
fi

#=============================================================================
# Check if work library exists
#=============================================================================
cd "$PROJECT_ROOT"

if [ ! -d "work" ]; then
    print_warn "Work library not found. Please run compile_rtl.sh first!"
    print_info "Creating work library..."
    $VLIB work
    $VMAP work work
fi

#=============================================================================
# Compile DPI C++ code for reference model (if exists)
#=============================================================================
#SIMX_DPI="$VORTEX_UVM_HOME/uvm_env/ref_model/simx_dpi.cpp"

if [ -f "$SIMX_DPI" ]; then
    print_info "Compiling reference model DPI code..."
    
    # Compile C++ to shared library
    DPI_DIR="$(dirname $SIMX_DPI)"
    DPI_LIB="$DPI_DIR/libsimx_dpi.so"
    
    # Use correct include path for QuestaSim
    g++ -shared -fPIC -I$MTI_HOME/include \
        -I$VORTEX_HOME/hw \
        -o $DPI_LIB $SIMX_DPI 2>&1
    
    if [ $? -eq 0 ]; then
        print_info "DPI library compiled: $DPI_LIB"
        VLOG_OPTS="$VLOG_OPTS -sv_lib $(basename $DPI_LIB .so)"
        export LD_LIBRARY_PATH="$DPI_DIR:$LD_LIBRARY_PATH"
    else
        print_warn "DPI compilation failed, continuing without reference model"
    fi
else
    print_warn "Reference model DPI source not found: $SIMX_DPI"
    print_info "Continuing without reference model integration"
fi

#=============================================================================
# Compile UVM Environment using file list
#=============================================================================
print_info "=========================================="
print_info "Starting UVM environment compilation..."
print_info "=========================================="

FLIST="$PROJECT_ROOT/flists/uvm_env.flist"

if [ ! -f "$FLIST" ]; then
    print_error "UVM file list not found: $FLIST"
    exit 1
fi

print_info "Using file list: $FLIST"

# Count files
FILE_COUNT=$(grep -v '^#' "$FLIST" | grep -v '^$' | wc -l)
print_info "Files to compile: $FILE_COUNT"
echo ""

# Compile with vlog
print_info "Running vlog..."
$VLOG $VLOG_OPTS -f $FLIST 2>&1 | tee compile_uvm.log

COMPILE_STATUS=${PIPESTATUS[0]}

if [ $COMPILE_STATUS -eq 0 ]; then
    echo ""
    print_info "=========================================="
    print_info "✅ UVM environment compilation SUCCESS!"
    print_info "=========================================="
else
    echo ""
    print_error "=========================================="
    print_error "❌ UVM environment compilation FAILED!"
    print_error "=========================================="
    print_error "Check compile_uvm.log for details"
    exit 1
fi

#=============================================================================
# Verify compiled modules
#=============================================================================
print_info ""
print_info "Compiled UVM modules:"
vdir work | grep -E "(vortex|mem_|axi_|dcr_|host_|status_)" | head -20
echo ""

#=============================================================================
# Summary
#=============================================================================
print_info "================================================"
print_info "        UVM Compilation Summary"
print_info "================================================"
print_info "Status: ${GREEN}SUCCESS${NC}"
print_info "Work library: $PROJECT_ROOT/work"
print_info "Log file: $PROJECT_ROOT/compile_uvm.log"
print_info "UVM Version: QuestaSim/ModelSim UVM-1.2"
print_info "QuestaSim: $MTI_HOME"
print_info "================================================"
print_info ""
print_info "Ready to run simulation:"
print_info "  cd $PROJECT_ROOT"
print_info "  vsim -c work.vortex_tb_top +UVM_TESTNAME=vortex_smoke_test"
print_info ""
print_info "Or with GUI:"
print_info "  vsim work.vortex_tb_top +UVM_TESTNAME=vortex_smoke_test"
print_info "================================================"

exit 0
