#!/usr/bin/env bash

################################################################################
# File: scripts/run_vortex_uvm.sh
# Description: Production automation script for Vortex UVM verification
#
# Key Features:
# - Proper hex file detection and conversion
# - Organized timestamped results directory structure
# - Support for riscv-tests, Vortex programs, and custom hex
# - Better error handling and validation
# - RISC-V DV test generation support
#
# Author: Samuel 
# Date: February 2026
################################################################################

set -e          # Exit on error
set -o pipefail # Catch errors in pipes

################################################################################
# Color Codes
################################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${CYAN}================================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ ERROR: $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ WARNING: $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

usage() {
    cat << EOF
${CYAN}Vortex UVM Test Runner${NC}
${CYAN}=====================${NC}

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${YELLOW}Required Options:${NC}
    --test=TEST_NAME         UVM test to run

${YELLOW}Program Options (for tests needing programs):${NC}
    --program=PROGRAM        Program specification:
                              - Vortex kernel: vecadd, sgemm, etc.
                              - RISC-V test: rv32ui-p-add, rv64ui-p-add, etc.
                              - RISC-V DV: riscv_arithmetic_basic_test
                              - Custom path: /path/to/program.hex/.elf/.bin
                              - If .hex: used directly
                              - If .elf/.bin: converted to .hex

${YELLOW}Optional Configuration:${NC}
    --interface=INTERFACE    Memory interface: axi or mem (default: axi)
    --cores=N                Number of cores (default: 1)
    --warps=N                Number of warps per core (default: 4)
    --threads=N              Number of threads per warp (default: 4)
    --timeout=CYCLES         Simulation timeout in cycles (default: 1000000)
    
${YELLOW}Optional Flags:${NC}
    --no-compile             Skip compilation
    --no-waves               Disable waveform dumping
    --gui                    Run in GUI mode (Questa only)
    --clean                  Clean before compile
    --verbose                Enable verbose output
    --help                   Show this help

${YELLOW}Program Type Examples:${NC}

  ${GREEN}1. Vortex Kernels${NC} (from \$VORTEX_HOME/tests/)
     --program=vecadd        Uses: \$VORTEX_HOME/tests/opencl/vecadd/kernel.bin
     --program=sgemm         Uses: \$VORTEX_HOME/tests/opencl/sgemm/kernel.bin
     
  ${GREEN}2. RISC-V Tests${NC} (from \$RISCV/target/share/riscv-tests/isa/)
     --program=rv32ui-p-add  Uses: rv32ui-p-add ELF, converts to hex
     --program=rv64ui-p-add  Uses: rv64ui-p-add ELF, converts to hex
     
  ${GREEN}3. RISC-V DV Tests${NC} (generated from riscv-dv)
     --program=riscv_arithmetic_basic_test   Auto-generates if needed
     --program=riscv_rand_instr_test         Random instructions
     
  ${GREEN}4. Custom Programs${NC}
     --program=/path/to/prog.hex   Uses directly (no conversion)
     --program=/path/to/prog.elf   Converts ELF → HEX
     --program=/path/to/prog.bin   Converts BIN → HEX

${YELLOW}Examples:${NC}
    # Sanity test (no program needed)
    $0 --test=vortex_sanity_test

    # Smoke test with Vortex kernel
    $0 --test=vortex_smoke_test --program=vecadd

    # RISC-V compliance test
    $0 --test=vortex_smoke_test --program=rv32ui-p-add

    # RISC-V DV random test (auto-generated)
    $0 --test=vortex_smoke_test --program=riscv_rand_instr_test

    # Custom hex file
    $0 --test=vortex_smoke_test --program=/path/to/my_test.hex

    # Custom configuration
    $0 --test=vortex_smoke_test --program=sgemm --cores=2 --warps=8 --threads=4

EOF
    exit 0
}

################################################################################
# Default Configuration
################################################################################

# Path resolution
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
else
    SCRIPT_PATH="${BASH_SOURCE[0]}"
fi

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLISTS_DIR="$PROJECT_ROOT/flists"

# Test configuration
TEST_NAME=""
PROGRAM=""
PROGRAM_HEX=""
PROGRAM_TYPE=""  # vortex, riscv-test, riscv-dv, custom-hex, custom-elf, custom-bin

# GPU configuration
NUM_CORES=1
NUM_WARPS=4
NUM_THREADS=4
TIMEOUT_CYCLES=1000000

# Interface selection
MEMORY_INTERFACE="axi"

# Compilation flags
FPU_TYPE="FPU_FPNEW"
TCU_TYPE="TCU_BHF"
NO_COMPILE=0
CLEAN=0

# Simulation options
NO_WAVES=0
GUI_MODE=0
VERBOSE=0

# Simulator
SIMULATOR=""

################################################################################
# Parse Arguments
################################################################################

# Store original command for config snapshot
ORIGINAL_CMD="$0 $@"

for arg in "$@"; do
    case $arg in
        --test=*) TEST_NAME="${arg#*=}" ;;
        --program=*) PROGRAM="${arg#*=}" ;;
        --interface=*) MEMORY_INTERFACE="${arg#*=}" ;;
        --cores=*) NUM_CORES="${arg#*=}" ;;
        --warps=*) NUM_WARPS="${arg#*=}" ;;
        --threads=*) NUM_THREADS="${arg#*=}" ;;
        --timeout=*) TIMEOUT_CYCLES="${arg#*=}" ;;
        --no-compile) NO_COMPILE=1 ;;
        --no-waves) NO_WAVES=1 ;;
        --gui) GUI_MODE=1 ;;
        --clean) CLEAN=1 ;;
        --verbose) VERBOSE=1 ;;
        --help|-h) usage ;;
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
    exit 1
fi

if [[ "$MEMORY_INTERFACE" != "axi" && "$MEMORY_INTERFACE" != "mem" ]]; then
    print_error "Invalid interface: $MEMORY_INTERFACE"
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

print_header "Environment Check"

# Check VORTEX_HOME
if [[ -z "$VORTEX_HOME" ]]; then
    print_error "VORTEX_HOME not set"
    exit 1
fi
print_success "VORTEX_HOME: $VORTEX_HOME"

# Check RISCV toolchain
if ! command -v riscv64-unknown-elf-objcopy &> /dev/null; then
    print_error "RISC-V toolchain not found"
    echo "  Install: https://github.com/riscv-collab/riscv-gnu-toolchain"
    exit 1
fi
print_success "RISC-V toolchain found"

print_success "Project root: $PROJECT_ROOT"

# Auto-detect simulator
if command -v vsim &> /dev/null; then
    SIMULATOR="questa"
    print_success "Simulator: Questa/ModelSim"
elif command -v vcs &> /dev/null; then
    SIMULATOR="vcs"
    print_success "Simulator: Synopsys VCS"
else
    print_error "No simulator found (vsim or vcs)"
    exit 1
fi

################################################################################
# Create Results Directory
################################################################################

print_header "Setting Up Results Directory"

# Timestamped results directory
RESULTS_BASE="$PROJECT_ROOT/results"
RESULTS_DATE=$(date +%Y%m%d)
RESULTS_TIME=$(date +%H%M%S)
RESULTS_RUN_DIR="$RESULTS_BASE/$RESULTS_DATE/run_${RESULTS_TIME}_${TEST_NAME}"

# Create subdirectories
mkdir -p "$RESULTS_RUN_DIR"/{logs,waves,programs,reports}

# Symlink to latest run (for convenience)
ln -sfn "$RESULTS_RUN_DIR" "$RESULTS_BASE/latest"

print_success "Results directory: $RESULTS_RUN_DIR"
print_info "Latest results:    $RESULTS_BASE/latest"

# Save test configuration for reproducibility
CONFIG_SNAPSHOT="$RESULTS_RUN_DIR/reports/config.txt"
cat > "$CONFIG_SNAPSHOT" << EOF
================================================================================
Test Run Configuration
================================================================================
Date:         $(date)
Test:         $TEST_NAME
Program:      ${PROGRAM:-N/A}
Interface:    $MEMORY_INTERFACE
Cores:        $NUM_CORES
Warps:        $NUM_WARPS
Threads:      $NUM_THREADS
Timeout:      $TIMEOUT_CYCLES cycles
Simulator:    $SIMULATOR

Environment:
  VORTEX_HOME:  $VORTEX_HOME
  PROJECT_ROOT: $PROJECT_ROOT
  RISCV:        ${RISCV:-N/A}

Command Line:
  $ORIGINAL_CMD

Results:
  Run Directory: $RESULTS_RUN_DIR
  Date:          $RESULTS_DATE
  Time:          $RESULTS_TIME
================================================================================
EOF

################################################################################
# Program Resolution and Conversion
################################################################################

if [[ -n "$PROGRAM" ]]; then
    print_header "Program Resolution"
    
    # Detect program type and locate source
    PROGRAM_SOURCE=""
    
    # Case 1: Already a .hex file?
    if [[ "$PROGRAM" == *.hex ]]; then
        if [[ -f "$PROGRAM" ]]; then
            PROGRAM_TYPE="custom-hex"
            PROGRAM_HEX="$PROGRAM"
            print_success "Found hex file: $PROGRAM_HEX"
        else
            print_error "Hex file not found: $PROGRAM"
            exit 1
        fi
    
    # Case 2: Vortex OpenCL kernel?
    elif [[ -f "$VORTEX_HOME/tests/opencl/$PROGRAM/kernel.bin" ]]; then
        PROGRAM_TYPE="vortex"
        PROGRAM_SOURCE="$VORTEX_HOME/tests/opencl/$PROGRAM/kernel.bin"
        print_info "Detected Vortex kernel: $PROGRAM"
        print_info "Source: $PROGRAM_SOURCE"
    
    # Case 3: RISC-V test (check common locations)
    elif [[ "$PROGRAM" == rv* ]]; then
        PROGRAM_TYPE="riscv-test"
        
        # Try common RISC-V test locations
        RISCV_TEST_DIRS=(
            "$RISCV/target/share/riscv-tests/isa"
            "$RISCV/share/riscv-tests/isa"
            "${RISCV_PREFIX:-/opt/riscv}/share/riscv-tests/isa"
            "$VORTEX_HOME/tests/riscv-tests/isa"
        )
        
        for dir in "${RISCV_TEST_DIRS[@]}"; do
            if [[ -f "$dir/$PROGRAM" ]]; then
                PROGRAM_SOURCE="$dir/$PROGRAM"
                break
            fi
        done
        
        if [[ -z "$PROGRAM_SOURCE" ]]; then
            print_error "RISC-V test not found: $PROGRAM"
            echo "  Searched in:"
            for dir in "${RISCV_TEST_DIRS[@]}"; do
                echo "    - $dir"
            done
            echo ""
            echo "  Build riscv-tests first:"
            echo "    git clone https://github.com/riscv/riscv-tests.git"
            echo "    cd riscv-tests"
            echo "    git submodule update --init --recursive"
            echo "    autoconf"
            echo "    ./configure --prefix=\$RISCV/target"
            echo "    make"
            echo "    make install"
            exit 1
        fi
        
        print_info "Found RISC-V test: $PROGRAM_SOURCE"
    
    # Case 4: RISC-V DV test (pre-generated)?
    elif [[ -f "$VORTEX_HOME/third_party/riscv-dv/out/$PROGRAM/$PROGRAM" ]]; then
        PROGRAM_TYPE="riscv-dv"
        PROGRAM_SOURCE="$VORTEX_HOME/third_party/riscv-dv/out/$PROGRAM/$PROGRAM"
        print_info "Found RISC-V DV test: $PROGRAM_SOURCE"
    
    # Case 5: RISC-V DV test needs generation?
    elif [[ "$PROGRAM" == riscv_* ]]; then
        PROGRAM_TYPE="riscv-dv"
        print_info "RISC-V DV test needs generation: $PROGRAM"
        
        # Check if riscv-dv exists
        if [[ ! -d "$VORTEX_HOME/third_party/riscv-dv" ]]; then
            print_error "RISC-V DV not found at \$VORTEX_HOME/third_party/riscv-dv"
            echo "  Clone it:"
            echo "    cd \$VORTEX_HOME/third_party"
            echo "    git clone https://github.com/chipsalliance/riscv-dv.git"
            echo "    cd riscv-dv"
            echo "    pip3 install -r requirements.txt"
            exit 1
        fi
        
        # Generate the test
        print_info "Generating with riscv-dv..."
        cd "$VORTEX_HOME/third_party/riscv-dv" || exit 1
        
        if python3 run.py \
            --test="$PROGRAM" \
            --simulator=questa \
            --isa=rv32imc \
            --iterations=1 \
            --steps=gen \
            2>&1 | tee "$RESULTS_RUN_DIR/logs/riscv_dv_gen.log"; then
            
            # Find the generated binary
            PROGRAM_SOURCE=$(find out/ -name "$PROGRAM.0" -type f | head -1)
            if [[ -z "$PROGRAM_SOURCE" ]]; then
                print_error "Generated test not found in out/ directory"
                exit 1
            fi
            PROGRAM_SOURCE="$VORTEX_HOME/third_party/riscv-dv/$PROGRAM_SOURCE"
            print_success "Generated: $PROGRAM_SOURCE"
        else
            print_error "RISC-V DV generation failed"
            cat "$RESULTS_RUN_DIR/logs/riscv_dv_gen.log"
            exit 1
        fi
        cd "$FLISTS_DIR" || exit 1
    
    # Case 6: Custom ELF/BIN file?
    elif [[ -f "$PROGRAM" ]]; then
        if [[ "$PROGRAM" == *.elf ]]; then
            PROGRAM_TYPE="custom-elf"
        elif [[ "$PROGRAM" == *.bin ]]; then
            PROGRAM_TYPE="custom-bin"
        else
            # Try to detect by file command
            FILE_TYPE=$(file "$PROGRAM" 2>/dev/null | grep -o "ELF\|data" || echo "unknown")
            if [[ "$FILE_TYPE" == "ELF" ]]; then
                PROGRAM_TYPE="custom-elf"
            else
                PROGRAM_TYPE="custom-bin"
            fi
        fi
        PROGRAM_SOURCE="$PROGRAM"
        print_info "Detected custom program: $PROGRAM_SOURCE (type: $PROGRAM_TYPE)"
    
    else
        print_error "Program not found: $PROGRAM"
        echo ""
        echo "  Supported formats:"
        echo "    1. Vortex kernel name: vecadd, sgemm, etc."
        echo "    2. RISC-V test name: rv32ui-p-add, rv64ui-p-add, etc."
        echo "    3. RISC-V DV test: riscv_arithmetic_basic_test (auto-generated)"
        echo "    4. Path to .hex file (used directly)"
        echo "    5. Path to .elf or .bin file (converted to .hex)"
        exit 1
    fi
    
    # Convert if needed
    if [[ -z "$PROGRAM_HEX" ]]; then
        print_header "Program Conversion"
        
        # Output hex file in results directory
        PROGRAM_BASENAME=$(basename "$PROGRAM_SOURCE" | sed 's/\.[^.]*$//')
        PROGRAM_HEX="$RESULTS_RUN_DIR/programs/${PROGRAM_BASENAME}.hex"
        
        print_info "Converting: $PROGRAM_SOURCE"
        print_info "Output: $PROGRAM_HEX"
        
        # Perform conversion based on type
        OBJCOPY_LOG="$RESULTS_RUN_DIR/logs/objcopy.log"
        
        if [[ "$PROGRAM_TYPE" == "vortex" ]]; then
            # Vortex kernel.bin uses specific format
            if riscv64-unknown-elf-objcopy \
                -I binary \
                -O verilog \
                --change-addresses=0x80000000 \
                --verilog-data-width=1 \
                --reverse-bytes=4 \
                "$PROGRAM_SOURCE" \
                "$PROGRAM_HEX" 2>&1 | tee "$OBJCOPY_LOG"; then
                print_success "Vortex kernel converted"
            else
                print_error "Conversion failed"
                cat "$OBJCOPY_LOG"
                exit 1
            fi
            
        elif [[ "$PROGRAM_TYPE" == "riscv-test" || "$PROGRAM_TYPE" == "riscv-dv" ]]; then
            # RISC-V tests are ELF format
            if riscv64-unknown-elf-objcopy \
                -O verilog \
                --verilog-data-width=1 \
                --reverse-bytes=4 \
                "$PROGRAM_SOURCE" \
                "$PROGRAM_HEX" 2>&1 | tee "$OBJCOPY_LOG"; then
                print_success "RISC-V test converted"
            else
                print_error "Conversion failed"
                cat "$OBJCOPY_LOG"
                exit 1
            fi
            
        elif [[ "$PROGRAM_TYPE" == "custom-elf" ]]; then
            # Custom ELF
            if riscv64-unknown-elf-objcopy \
                -O verilog \
                --verilog-data-width=1 \
                --reverse-bytes=4 \
                "$PROGRAM_SOURCE" \
                "$PROGRAM_HEX" 2>&1 | tee "$OBJCOPY_LOG"; then
                print_success "Custom ELF converted"
            else
                print_error "Conversion failed"
                cat "$OBJCOPY_LOG"
                exit 1
            fi
            
        elif [[ "$PROGRAM_TYPE" == "custom-bin" ]]; then
            # Custom binary
            if riscv64-unknown-elf-objcopy \
                -I binary \
                -O verilog \
                --change-addresses=0x80000000 \
                --verilog-data-width=1 \
                --reverse-bytes=4 \
                "$PROGRAM_SOURCE" \
                "$PROGRAM_HEX" 2>&1 | tee "$OBJCOPY_LOG"; then
                print_success "Custom binary converted"
            else
                print_error "Conversion failed"
                cat "$OBJCOPY_LOG"
                exit 1
            fi
        fi
        
        # Validate hex format
        if [[ -f "$PROGRAM_HEX" ]]; then
            if [[ ! -s "$PROGRAM_HEX" ]]; then
                print_error "HEX file is empty"
                exit 1
            fi
            
            FIRST_LINE=$(head -1 "$PROGRAM_HEX")
            if [[ "$FIRST_LINE" =~ ^@[0-9a-fA-F]{8} ]]; then
                print_success "HEX format validated"
            else
                print_warning "HEX format may be incorrect (should start with @address)"
                print_info "First line: $FIRST_LINE"
            fi
            
            # Show size
            PROGRAM_SIZE=$(wc -l < "$PROGRAM_HEX")
            print_info "HEX file: $PROGRAM_SIZE lines"
            
            if [[ $VERBOSE -eq 1 ]]; then
                echo ""
                echo "First 5 lines:"
                head -5 "$PROGRAM_HEX" | sed 's/^/  /'
            fi
        else
            print_error "HEX file not created"
            exit 1
        fi
    fi
fi

################################################################################
# Compilation
################################################################################

cd "$FLISTS_DIR" || exit 1

if [[ $CLEAN -eq 1 ]]; then
    print_header "Cleaning"
    rm -rf work
    print_success "Clean complete"
fi

if [[ $NO_COMPILE -eq 0 ]]; then
    print_header "Compilation"
    
    # Create work library
    if [[ ! -d "work" && "$SIMULATOR" == "questa" ]]; then
        vlib work
    fi
    
    # Compile options
    COMPILE_OPTS="+define+$FPU_TYPE +define+$TCU_TYPE"
    COMPILE_OPTS="$COMPILE_OPTS +define+NUM_CORES=$NUM_CORES"
    COMPILE_OPTS="$COMPILE_OPTS +define+NUM_WARPS=$NUM_WARPS"
    COMPILE_OPTS="$COMPILE_OPTS +define+NUM_THREADS=$NUM_THREADS"
    
    if [[ "$MEMORY_INTERFACE" == "axi" ]]; then
        COMPILE_OPTS="$COMPILE_OPTS +define+USE_AXI_WRAPPER"
        print_info "Using AXI interface"
    else
        print_info "Using custom memory interface"
    fi
    
    # Compile RTL
    print_info "Compiling Vortex RTL..."
    if [[ "$SIMULATOR" == "questa" ]]; then
        vlog -sv $COMPILE_OPTS \
            +incdir+"$VORTEX_HOME/third_party/cvfpu/src/common_cells/include" \
            -f vortex_rtl.flist \
            2>&1 | tee "$RESULTS_RUN_DIR/logs/compile_rtl.log"
    fi
    
    if [[ $? -ne 0 ]]; then
        print_error "RTL compilation failed"
        exit 1
    fi
    print_success "RTL compiled"
    
    # Compile UVM
    print_info "Compiling UVM environment..."
    if [[ "$SIMULATOR" == "questa" ]]; then
        vlog -sv \
            +incdir+/opt/questa_sim-2021.2_1/questasim/verilog_src/questa_uvm_pkg-1.2/src \
            -f uvm_env.flist \
            2>&1 | tee "$RESULTS_RUN_DIR/logs/compile_uvm.log"
    fi
    
    if [[ $? -ne 0 ]]; then
        print_error "UVM compilation failed"
        exit 1
    fi
    print_success "UVM compiled"
else
    print_header "Skipping Compilation"
fi

################################################################################
# Simulation
################################################################################

print_header "Simulation"

# Build simulation options
SIM_OPTS="+UVM_TESTNAME=$TEST_NAME"
SIM_OPTS="$SIM_OPTS +TIMEOUT=$TIMEOUT_CYCLES"
SIM_OPTS="$SIM_OPTS +NUM_CORES=$NUM_CORES"
SIM_OPTS="$SIM_OPTS +NUM_WARPS=$NUM_WARPS"
SIM_OPTS="$SIM_OPTS +NUM_THREADS=$NUM_THREADS"

if [[ -n "$PROGRAM_HEX" ]]; then
    SIM_OPTS="$SIM_OPTS +PROGRAM=$PROGRAM_HEX"
fi

if [[ $NO_WAVES -eq 0 ]]; then
    WAVE_FILE="$RESULTS_RUN_DIR/waves/${TEST_NAME}_${MEMORY_INTERFACE}.vcd"
    SIM_OPTS="$SIM_OPTS +WAVE=$WAVE_FILE"
else
    SIM_OPTS="$SIM_OPTS +NO_WAVES"
fi

print_info "Test: $TEST_NAME"
print_info "Config: ${NUM_CORES}C ${NUM_WARPS}W ${NUM_THREADS}T"
if [[ -n "$PROGRAM" ]]; then
    print_info "Program: $PROGRAM ($PROGRAM_TYPE)"
fi

# Run simulation
LOG_FILE="$RESULTS_RUN_DIR/logs/simulation.log"

if [[ "$SIMULATOR" == "questa" ]]; then
    if [[ $GUI_MODE -eq 1 ]]; then
        vsim vortex_tb_top $SIM_OPTS \
            -do "add wave -r /*; run -all"
    else
        vsim -c vortex_tb_top $SIM_OPTS \
            -do "run -all; quit -f" \
            2>&1 | tee "$LOG_FILE"
    fi
fi

SIM_EXIT_CODE=$?

################################################################################
# Results Analysis
################################################################################

print_header "Results"

if [[ $SIM_EXIT_CODE -eq 0 ]]; then
    if grep -q "TEST PASSED" "$LOG_FILE" 2>/dev/null; then
        print_success "TEST PASSED ✓"
        TEST_STATUS="PASSED"
        EXIT_CODE=0
    elif grep -q "TEST FAILED" "$LOG_FILE" 2>/dev/null; then
        print_error "TEST FAILED ✗"
        TEST_STATUS="FAILED"
        EXIT_CODE=1
    else
        print_warning "Test result unknown"
        TEST_STATUS="UNKNOWN"
        EXIT_CODE=3
    fi
    
    # Extract statistics
    if grep -q "Total Cycles\|Cycles:" "$LOG_FILE" 2>/dev/null; then
        echo ""
        print_info "Statistics:"
        grep -E "Total Cycles|Cycles:|Instructions|IPC" "$LOG_FILE" | sed 's/^/  /'
    fi
else
    print_error "Simulation failed"
    TEST_STATUS="ERROR"
    EXIT_CODE=$SIM_EXIT_CODE
fi

################################################################################
# Create Summary Report
################################################################################

SUMMARY_FILE="$RESULTS_RUN_DIR/reports/SUMMARY.txt"

cat > "$SUMMARY_FILE" << EOF
================================================================================
Vortex UVM Test Summary
================================================================================
Date:         $(date)
Test:         $TEST_NAME
Status:       $TEST_STATUS
Exit Code:    $EXIT_CODE

Configuration:
  Interface:  $MEMORY_INTERFACE
  Cores:      $NUM_CORES
  Warps:      $NUM_WARPS
  Threads:    $NUM_THREADS
  Timeout:    $TIMEOUT_CYCLES cycles

Program:
  Name:       ${PROGRAM:-N/A}
  Type:       ${PROGRAM_TYPE:-N/A}
  Source:     ${PROGRAM_SOURCE:-N/A}
  HEX:        ${PROGRAM_HEX:-N/A}

Files:
  Log:        logs/simulation.log
  Waveform:   ${WAVE_FILE:+waves/$(basename "$WAVE_FILE")}
  Config:     reports/config.txt
  Directory:  $RESULTS_RUN_DIR

Statistics:
EOF

if grep -q "Total Cycles\|Cycles:" "$LOG_FILE" 2>/dev/null; then
    grep -E "Total Cycles|Cycles:|Instructions|IPC" "$LOG_FILE" >> "$SUMMARY_FILE"
else
    echo "  (No statistics available)" >> "$SUMMARY_FILE"
fi

echo "================================================================================" >> "$SUMMARY_FILE"

################################################################################
# Final Output
################################################################################

print_header "Summary"

# Show result first (most important)
if [[ $EXIT_CODE -eq 0 ]]; then
    print_success "TEST PASSED ✓"
else
    print_error "TEST FAILED ✗"
fi

echo ""
echo "Test:      $TEST_NAME"
echo "Program:   ${PROGRAM:-N/A}"
echo "Status:    $TEST_STATUS"
echo ""
echo "Files:"
echo "  Run Dir:   $RESULTS_RUN_DIR"
echo "  Log:       logs/simulation.log"
if [[ $NO_WAVES -eq 0 ]]; then
    echo "  Waveform:  waves/$(basename "${WAVE_FILE:-N/A}")"
fi
echo "  Summary:   reports/SUMMARY.txt"
echo "  Config:    reports/config.txt"
echo ""
echo "Quick access:"
echo "  cd results/latest"
echo "  cat reports/SUMMARY.txt"
if [[ $NO_WAVES -eq 0 && "$SIMULATOR" == "questa" ]]; then
    echo "  vsim -view waves/*.vcd"
fi

if [[ $EXIT_CODE -eq 0 ]]; then
    echo ""
    print_success "All done! ✓"
else
    echo ""
    print_error "Test failed with code $EXIT_CODE"
    echo "Check logs: $LOG_FILE"
fi

exit $EXIT_CODE
