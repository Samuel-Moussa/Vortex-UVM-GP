#!/usr/bin/env bash

################################################################################
# File: scripts/run_vortex_uvm.sh
# Description: Complete automation script for Vortex UVM verification
#
# Author: Vortex UVM Team
# Date: January 2026
################################################################################

set -e  # Exit on error

################################################################################
# Color Codes for Pretty Output
################################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

usage() {
    cat << EOF
${CYAN}Vortex UVM Test Runner${NC}
${CYAN}=====================${NC}

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${YELLOW}Required Options:${NC}
    --test=TEST_NAME         UVM test to run (e.g., vortex_sanity_test, vortex_smoke_test)
    --program=PROGRAM        Program to run (vecadd, sgemm, bfs, or path to .elf/.bin/.hex)

${YELLOW}Optional Configuration:${NC}
    --interface=INTERFACE    Memory interface: axi or mem (default: axi)
    --cores=N                Number of cores (default: 1)
    --warps=N                Number of warps per core (default: 4)
    --threads=N              Number of threads per warp (default: 4)
    --timeout=CYCLES         Simulation timeout in cycles (default: 1000000)
    
${YELLOW}Optional Flags:${NC}
    --no-compile             Skip compilation, use existing work library
    --no-waves               Disable waveform dumping
    --gui                    Run in GUI mode (Questa only)
    --clean                  Clean before compile
    --verbose                Enable verbose output
    --help                   Show this help message

${YELLOW}Examples:${NC}
    # Run sanity test (no program needed)
    $0 --test=vortex_sanity_test

    # Run smoke test with vecadd on AXI interface
    $0 --test=vortex_smoke_test --program=vecadd

    # Run with custom configuration
    $0 --test=vortex_smoke_test --program=sgemm --cores=2 --warps=8 --interface=mem

EOF
    exit 0
}

################################################################################
# Default Configuration
################################################################################

# Environment - FIXED PATH RESOLUTION
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    # Script is a symlink - resolve it
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
else
    # Script is the actual file
    SCRIPT_PATH="${BASH_SOURCE[0]}"
fi

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLISTS_DIR="$PROJECT_ROOT/flists"
PROGRAMS_DIR="$PROJECT_ROOT/uvm_env/agents/host_agent"

# Test configuration
TEST_NAME=""
PROGRAM=""
PROGRAM_HEX=""

# GPU configuration (defaults from VX_config.h)
NUM_CORES=1
NUM_WARPS=4
NUM_THREADS=4
TIMEOUT_CYCLES=1000000

# Interface selection
MEMORY_INTERFACE="axi"  # Default to AXI

# Compilation flags
FPU_TYPE="FPU_FPNEW"    # Default: FPNEW (stable)
TCU_TYPE="TCU_BHF"      # Default: BHF (stable)
NO_COMPILE=0
CLEAN=0

# Simulation options
NO_WAVES=0
GUI_MODE=0
VERBOSE=0

# Simulator (auto-detect)
SIMULATOR=""

################################################################################
# Parse Command-Line Arguments
################################################################################

for arg in "$@"; do
    case $arg in
        --test=*)
            TEST_NAME="${arg#*=}"
            ;;
        --program=*)
            PROGRAM="${arg#*=}"
            ;;
        --interface=*)
            MEMORY_INTERFACE="${arg#*=}"
            ;;
        --cores=*)
            NUM_CORES="${arg#*=}"
            ;;
        --warps=*)
            NUM_WARPS="${arg#*=}"
            ;;
        --threads=*)
            NUM_THREADS="${arg#*=}"
            ;;
        --timeout=*)
            TIMEOUT_CYCLES="${arg#*=}"
            ;;
        --no-compile)
            NO_COMPILE=1
            ;;
        --no-waves)
            NO_WAVES=1
            ;;
        --gui)
            GUI_MODE=1
            ;;
        --clean)
            CLEAN=1
            ;;
        --verbose)
            VERBOSE=1
            ;;
        --help|-h)
            usage
            ;;
        *)
            print_error "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

################################################################################
# Validate Inputs
################################################################################

if [[ -z "$TEST_NAME" ]]; then
    print_error "Test name not specified. Use --test=TEST_NAME"
    echo "Available tests: vortex_sanity_test, vortex_smoke_test"
    exit 1
fi

# Validate memory interface
if [[ "$MEMORY_INTERFACE" != "axi" && "$MEMORY_INTERFACE" != "mem" ]]; then
    print_error "Invalid interface: $MEMORY_INTERFACE. Must be 'axi' or 'mem'"
    exit 1
fi

# Check if test needs a program
TESTS_NEEDING_PROGRAM=("vortex_smoke_test" "functional_memory_test" "kernel_launch_test")
NEEDS_PROGRAM=0
for test in "${TESTS_NEEDING_PROGRAM[@]}"; do
    if [[ "$TEST_NAME" == "$test" ]]; then
        NEEDS_PROGRAM=1
        break
    fi
done

if [[ $NEEDS_PROGRAM -eq 1 && -z "$PROGRAM" ]]; then
    print_error "Test '$TEST_NAME' requires a program. Use --program=PROGRAM"
    exit 1
fi

################################################################################
# Environment Checks
################################################################################

print_header "Vortex UVM Test Runner - Environment Check"

# Debug path resolution
if [[ $VERBOSE -eq 1 ]]; then
    echo "Debug Paths:"
    echo "  SCRIPT_PATH: $SCRIPT_PATH"
    echo "  SCRIPT_DIR: $SCRIPT_DIR"
    echo "  PROJECT_ROOT: $PROJECT_ROOT"
    echo "  FLISTS_DIR: $FLISTS_DIR"
    echo "  PROGRAMS_DIR: $PROGRAMS_DIR"
    echo ""
fi

# Check VORTEX_HOME
if [[ -z "$VORTEX_HOME" ]]; then
    print_error "VORTEX_HOME not set"
    echo "  export VORTEX_HOME=/path/to/vortex"
    exit 1
fi
print_success "VORTEX_HOME: $VORTEX_HOME"

# Check if flists directory exists
if [[ ! -d "$FLISTS_DIR" ]]; then
    print_error "flists directory not found: $FLISTS_DIR"
    echo "Expected structure:"
    echo "  $PROJECT_ROOT/"
    echo "  ├── flists/"
    echo "  ├── scripts/"
    echo "  └── uvm_env/"
    exit 1
fi
print_success "Project root: $PROJECT_ROOT"

# Auto-detect simulator
if command -v vsim &> /dev/null; then
    SIMULATOR="questa"
    print_success "Simulator detected: Questa/ModelSim"
elif command -v vcs &> /dev/null; then
    SIMULATOR="vcs"
    print_success "Simulator detected: Synopsys VCS"
elif command -v iverilog &> /dev/null; then
    SIMULATOR="icarus"
    print_success "Simulator detected: Icarus Verilog"
else
    print_error "No simulator found (vsim, vcs, or iverilog)"
    exit 1
fi

# Check for RISC-V toolchain if program conversion needed
if [[ -n "$PROGRAM" ]]; then
    if ! command -v riscv64-unknown-elf-objcopy &> /dev/null; then
        print_warning "riscv64-unknown-elf-objcopy not found"
        print_info "Program conversion may fail if input is ELF/BIN"
    else
        print_success "RISC-V toolchain found"
    fi
fi

################################################################################
# Program Conversion (ELF/BIN → HEX)
################################################################################

if [[ -n "$PROGRAM" ]]; then
    print_header "Program Conversion"
    
    # Determine program location and type
    if [[ -f "$PROGRAM" ]]; then
        # Absolute or relative path provided
        PROGRAM_PATH="$PROGRAM"
    elif [[ -f "$PROGRAMS_DIR/$PROGRAM.hex" ]]; then
        # Already converted
        PROGRAM_HEX="$PROGRAMS_DIR/$PROGRAM.hex"
        print_success "Found existing HEX: $PROGRAM_HEX"
    elif [[ -f "$VORTEX_HOME/tests/opencl/$PROGRAM/kernel.bin" ]]; then
        # Vortex OpenCL program
        PROGRAM_PATH="$VORTEX_HOME/tests/opencl/$PROGRAM/kernel.bin"
    elif [[ -f "$VORTEX_HOME/tests/regression/$PROGRAM/$PROGRAM.elf" ]]; then
        # Vortex regression test
        PROGRAM_PATH="$VORTEX_HOME/tests/regression/$PROGRAM/$PROGRAM.elf"
    else
        print_error "Program not found: $PROGRAM"
        echo "  Searched:"
        echo "    - $PROGRAM (as path)"
        echo "    - $PROGRAMS_DIR/$PROGRAM.hex"
        echo "    - $VORTEX_HOME/tests/opencl/$PROGRAM/kernel.bin"
        echo "    - $VORTEX_HOME/tests/regression/$PROGRAM/$PROGRAM.elf"
        exit 1
    fi
    
    # Convert if necessary
    if [[ -z "$PROGRAM_HEX" ]]; then
        PROGRAM_HEX="$PROGRAMS_DIR/$(basename "$PROGRAM" | sed 's/\.[^.]*$//').hex"
        
        print_info "Converting: $PROGRAM_PATH"
        print_info "Output: $PROGRAM_HEX"
        
        # Perform conversion
        if riscv64-unknown-elf-objcopy \
            -O verilog \
            --verilog-data-width=1 \
            --reverse-bytes=4 \
            "$PROGRAM_PATH" \
            "$PROGRAM_HEX" 2>&1 | tee /tmp/objcopy.log; then
            
            print_success "Program converted successfully"
            
            # Verify format (should start with @xxxxxxxx)
            FIRST_LINE=$(head -1 "$PROGRAM_HEX")
            if [[ "$FIRST_LINE" =~ ^@[0-9a-fA-F]{8}$ ]]; then
                print_success "HEX format validated"
            else
                print_warning "HEX file may not have correct format"
                print_info "First line: $FIRST_LINE"
            fi
        else
            print_error "Program conversion failed"
            cat /tmp/objcopy.log
            exit 1
        fi
    fi
    
    # Show program info
    PROGRAM_SIZE=$(stat -c%s "$PROGRAM_HEX" 2>/dev/null || stat -f%z "$PROGRAM_HEX" 2>/dev/null || echo "unknown")
    print_info "Program size: $PROGRAM_SIZE bytes"
fi

################################################################################
# Compilation
################################################################################

cd "$FLISTS_DIR" || exit 1

if [[ $CLEAN -eq 1 ]]; then
    print_header "Cleaning"
    print_info "Removing work library..."
    rm -rf work
    print_success "Clean complete"
fi

if [[ $NO_COMPILE -eq 0 ]]; then
    print_header "Compilation"
    
    # Create work library
    if [[ ! -d "work" ]]; then
        print_info "Creating work library..."
        if [[ "$SIMULATOR" == "questa" ]]; then
            vlib work
        fi
    fi
    
    # Compile options
    COMPILE_OPTS="+define+$FPU_TYPE +define+$TCU_TYPE"

# Add config as compile-time defines too
COMPILE_OPTS="$COMPILE_OPTS +define+NUM_CORES=$NUM_CORES"
COMPILE_OPTS="$COMPILE_OPTS +define+NUM_WARPS=$NUM_WARPS"
COMPILE_OPTS="$COMPILE_OPTS +define+NUM_THREADS=$NUM_THREADS"

    
    # Add memory interface define
    if [[ "$MEMORY_INTERFACE" == "axi" ]]; then
        COMPILE_OPTS="$COMPILE_OPTS +define+USE_AXI_WRAPPER"
        print_info "Using AXI memory interface"
    else
        print_info "Using custom memory interface"
    fi
    
    # Compile RTL
    print_info "Compiling Vortex RTL..."
    if [[ "$SIMULATOR" == "questa" ]]; then
        vlog -sv $COMPILE_OPTS \
            +incdir+"$VORTEX_HOME/third_party/cvfpu/src/common_cells/include" \
            -f vortex_rtl.flist \
            2>&1 | tee compile_rtl.log
    elif [[ "$SIMULATOR" == "vcs" ]]; then
        vcs -sverilog $COMPILE_OPTS \
            +incdir+"$VORTEX_HOME/third_party/cvfpu/src/common_cells/include" \
            -f vortex_rtl.flist \
            2>&1 | tee compile_rtl.log
    fi
    
    if [[ $? -ne 0 ]]; then
        print_error "RTL compilation failed"
        exit 1
    fi
    print_success "RTL compilation complete"
    
    # Compile UVM environment
    print_info "Compiling UVM environment..."
    if [[ "$SIMULATOR" == "questa" ]]; then
        vlog -sv \
            +incdir+/opt/questa_sim-2021.2_1/questasim/verilog_src/questa_uvm_pkg-1.2/src \
            -f uvm_env.flist \
            2>&1 | tee compile_uvm.log
    fi
    
    if [[ $? -ne 0 ]]; then
        print_error "UVM compilation failed"
        exit 1
    fi
    print_success "UVM environment compilation complete"
    
else
    print_header "Skipping Compilation"
    print_info "Using existing work library"
fi

################################################################################
# Build Simulation Command
################################################################################

print_header "Simulation Configuration"

# Base simulation options
SIM_OPTS="+UVM_TESTNAME=$TEST_NAME"
SIM_OPTS="$SIM_OPTS +TIMEOUT=$TIMEOUT_CYCLES"

# Add program if provided
if [[ -n "$PROGRAM_HEX" ]]; then
    SIM_OPTS="$SIM_OPTS +PROGRAM=$PROGRAM_HEX"
    print_info "Program: $PROGRAM_HEX"
fi

# GPU configuration
SIM_OPTS="$SIM_OPTS +NUM_CORES=$NUM_CORES"
SIM_OPTS="$SIM_OPTS +NUM_WARPS=$NUM_WARPS"
SIM_OPTS="$SIM_OPTS +NUM_THREADS=$NUM_THREADS"

print_info "Configuration:"
echo "  Test: $TEST_NAME"
echo "  Interface: $MEMORY_INTERFACE"
echo "  Cores: $NUM_CORES"
echo "  Warps: $NUM_WARPS"
echo "  Threads: $NUM_THREADS"
echo "  Timeout: $TIMEOUT_CYCLES cycles"

# Waveform options
if [[ $NO_WAVES -eq 1 ]]; then
    SIM_OPTS="$SIM_OPTS +NO_WAVES"
    print_info "Waveforms: disabled"
else
    WAVE_FILE="vortex_${TEST_NAME}_${MEMORY_INTERFACE}.vcd"
    SIM_OPTS="$SIM_OPTS +WAVE=$WAVE_FILE"
    print_info "Waveforms: $WAVE_FILE"
fi

################################################################################
# Run Simulation
################################################################################

print_header "Running Simulation"

if [[ "$SIMULATOR" == "questa" ]]; then
    if [[ $GUI_MODE -eq 1 ]]; then
        print_info "Starting GUI mode..."
        vsim vortex_tb_top $SIM_OPTS \
            -do "add wave -r /*; run -all"
    else
        print_info "Starting simulation..."
        vsim -c vortex_tb_top $SIM_OPTS \
            -do "run -all; quit -f" \
            2>&1 | tee sim_${TEST_NAME}.log
    fi
elif [[ "$SIMULATOR" == "vcs" ]]; then
    print_info "Starting simulation..."
    ./simv $SIM_OPTS 2>&1 | tee sim_${TEST_NAME}.log
fi

SIM_EXIT_CODE=$?

################################################################################
# Check Results
################################################################################

print_header "Simulation Results"

if [[ $SIM_EXIT_CODE -eq 0 ]]; then
    # Check for test pass/fail
    if grep -q "TEST PASSED" sim_${TEST_NAME}.log 2>/dev/null; then
        print_success "TEST PASSED ✓"
        EXIT_CODE=0
    elif grep -q "TEST FAILED" sim_${TEST_NAME}.log 2>/dev/null; then
        print_error "TEST FAILED ✗"
        EXIT_CODE=1
    elif grep -q "SIMULATION TIMEOUT" sim_${TEST_NAME}.log 2>/dev/null; then
        print_error "SIMULATION TIMEOUT ⏰"
        EXIT_CODE=2
    else
        print_warning "Test result unknown - check logs"
        EXIT_CODE=3
    fi
    
    # Show statistics if available
    if grep -q "Total Cycles" sim_${TEST_NAME}.log 2>/dev/null; then
        echo ""
        print_info "Execution Statistics:"
        grep -E "Total Cycles|Instructions|IPC" sim_${TEST_NAME}.log | sed 's/^/  /'
    fi
else
    print_error "Simulation failed with exit code $SIM_EXIT_CODE"
    EXIT_CODE=$SIM_EXIT_CODE
fi

################################################################################
# Summary
################################################################################

print_header "Summary"

echo "Test:      $TEST_NAME"
echo "Interface: $MEMORY_INTERFACE"
echo "Program:   ${PROGRAM:-N/A}"
echo "Log:       sim_${TEST_NAME}.log"

if [[ $NO_WAVES -eq 0 ]]; then
    echo "Waveform:  $WAVE_FILE"
    if [[ "$SIMULATOR" == "questa" ]]; then
        echo "View with: vsim -view $WAVE_FILE"
    fi
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    print_success "All done! ✓"
else
    print_error "Test failed with code $EXIT_CODE"
fi

exit $EXIT_CODE
