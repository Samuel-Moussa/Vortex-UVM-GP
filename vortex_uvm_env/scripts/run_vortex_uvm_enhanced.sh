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
# Plusarg contract with vortex_config.sv apply_plusargs():
#   Compile-time (+define+):  NUM_CLUSTERS, NUM_CORES, NUM_WARPS, NUM_THREADS,
#                             USE_AXI_WRAPPER, FPU_TYPE, TCU_TYPE
#   Runtime    (+plusarg):    NUM_CLUSTERS, NUM_CORES, NUM_WARPS, NUM_THREADS,
#                             USE_AXI_WRAPPER, TIMEOUT, PROGRAM, WAVE, NO_WAVES,
#                             VERBOSE, UVM_TESTNAME
#
# FIXES (March 2026):
#   FIX A — STARTUP_ADDR 0x prefix stripped → $value$plusargs("%h") fix
#   FIX B — DPI shared library (-sv_lib) linked in vsim
#   FIX C — HEX validation aborts on @80000000 (baseaddr overflow / vacuous PASS)
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
print_error()   { echo -e "${RED}✗ ERROR: $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ WARNING: $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }


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
    --clusters=N             Number of clusters (default: 1)
    --cores=N                Number of cores (default: 1)
    --warps=N                Number of warps per core (default: 4)
    --threads=N              Number of threads per warp (default: 4)
    --timeout=CYCLES         Simulation timeout in cycles (default: 1000000)
    --startup-addr=ADDR      Startup PC in hex (default: 0x80000000 RV32,
                              use 0x080000000 for RV64)


${YELLOW}Optional Flags:${NC}
    --no-compile             Skip compilation
    --no-waves               Disable waveform dumping
    --gui                    Run in GUI mode (Questa only)
    --clean                  Clean before compile
    --verbose                Enable verbose output (sets +VERBOSE in sim)
    --no-tcu                 Disable TCU (exclude TCU files from flist)
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
    $0 --test=vortex_smoke_test --program=sgemm --clusters=2 --cores=2 --warps=8 --threads=4


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


# GPU configuration — must match vortex_config.sv apply_plusargs() names exactly
NUM_CLUSTERS=1
NUM_CORES=1
NUM_WARPS=4
NUM_THREADS=4
TIMEOUT_CYCLES=1000000


# Startup address — matches RTL VX_config.vh STARTUP_ADDR default (RV32)
# Override with --startup-addr=0x80000000 (RV32) or --startup-addr=0x080000000 (RV64)
STARTUP_ADDR="0x80000000"


# Interface selection
MEMORY_INTERFACE="axi"


# Compilation flags
FPU_TYPE="FPU_FPNEW"
TCU_TYPE="TCU_BHF"
NO_TCU=0
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
ORIGINAL_CMD="$0 $*"


for arg in "$@"; do
    case $arg in
        --test=*)       TEST_NAME="${arg#*=}" ;;
        --program=*)    PROGRAM="${arg#*=}" ;;
        --interface=*)  MEMORY_INTERFACE="${arg#*=}" ;;
        --clusters=*)   NUM_CLUSTERS="${arg#*=}" ;;
        --cores=*)      NUM_CORES="${arg#*=}" ;;
        --warps=*)      NUM_WARPS="${arg#*=}" ;;
        --threads=*)    NUM_THREADS="${arg#*=}" ;;
        --timeout=*)    TIMEOUT_CYCLES="${arg#*=}" ;;
        --startup-addr=*) STARTUP_ADDR="${arg#*=}" ;;
        --no-compile)   NO_COMPILE=1 ;;
        --no-waves)     NO_WAVES=1 ;;
        --gui)          GUI_MODE=1 ;;
        --clean)        CLEAN=1 ;;
        --verbose)      VERBOSE=1 ;;
        --no-tcu)       NO_TCU=1 ;;
        --help|-h)      usage ;;
        *)
            print_error "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done


# ── FIX A ────────────────────────────────────────────────────────────────────
# $value$plusargs("STARTUP_ADDR=%h") silently returns 0 when the value has a
# 0x prefix.  Strip it here so vsim receives e.g. +STARTUP_ADDR=80000000.
# The original human-readable $STARTUP_ADDR is kept for display/config only.
STARTUP_ADDR_HEX="${STARTUP_ADDR#0x}"
STARTUP_ADDR_HEX="${STARTUP_ADDR_HEX#0X}"
# ─────────────────────────────────────────────────────────────────────────────


################################################################################
# Validate Inputs
################################################################################


if [[ -z "$TEST_NAME" ]]; then
    print_error "Test name not specified. Use --test=TEST_NAME"
    exit 1
fi


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


print_header "Environment Check"


if [[ -z "$VORTEX_HOME" ]]; then
    print_error "VORTEX_HOME not set"
    exit 1
fi
print_success "VORTEX_HOME: $VORTEX_HOME"


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


# ── FIX B ────────────────────────────────────────────────────────────────────
# Without -sv_lib the DPI functions (dpi_trace etc.) are unresolved at runtime:
#   vsim-3770: Failed to find 'dpi_trace' in shared library.
# TCU and FPU trace output is silently dropped for the entire simulation.
# Build the .so once with the command printed below; afterwards it auto-links.
# --- Vortex DPI (optional) ---
# VORTEX_DPI_LIB="$FLISTS_DIR/vortex_dpi"

# # --- UVM DPI (REQUIRED) ---
# UVM_DPI_LIB="$QUESTA_HOME/uvm-1.2/linux_x86_64/uvm_dpi"

# DPI_FLAG=""

# # Add UVM DPI FIRST (critical)
# if [[ -f "${UVM_DPI_LIB}.so" ]]; thenz
#     DPI_FLAG="$DPI_FLAG -sv_lib ${UVM_DPI_LIB}"
#     print_success "UVM DPI loaded: ${UVM_DPI_LIB}.so"
# else
#     print_error "UVM DPI not found! This WILL crash simulation."
# fi

# # Add Vortex DPI if exists
# if [[ -f "${VORTEX_DPI_LIB}.so" ]]; then
#     DPI_FLAG="$DPI_FLAG -sv_lib ${VORTEX_DPI_LIB}"
#     print_success "Vortex DPI loaded: ${VORTEX_DPI_LIB}.so"
# else
#     print_warning "Vortex DPI not found (optional)"
# DPI_LIB="$FLISTS_DIR/vortex_dpi"
# DPI_FLAG=""
# if [[ -f "${DPI_LIB}.so" ]]; then
#     DPI_FLAG="-sv_lib ${DPI_LIB}"
#     print_success "DPI library: ${DPI_LIB}.so"
# else
#     print_warning "DPI library not found: ${DPI_LIB}.so"
#     print_info    "  TCU/FPU trace (dpi_trace) will be silent — vsim-3770 expected."
#     print_info    "  Build once with:"
#     print_info    "    QUESTA_INC=\$(dirname \$(which vsim))/../include"
#     print_info    "    gcc -shared -fPIC \\"
#     print_info    "        -o ${DPI_LIB}.so \\"
#     print_info    "        \$VORTEX_HOME/hw/dpi/util_dpi.cpp \\"
#     print_info    "        \$VORTEX_HOME/hw/dpi/float_dpi.cpp \\"
#     print_info    "        -I\$VORTEX_HOME/hw/dpi -I\$QUESTA_INC"
# fi
# # ─────────────────────────────────────────────────────────────────────────────

# ── FIX B ────────────────────────────────────────────────────────────────────
# Without -sv_lib the DPI functions (dpi_trace etc.) are unresolved at runtime:
#   vsim-3770: Failed to find 'dpi_trace' in shared library.
# TCU and FPU trace output is silently dropped for the entire simulation.
# ─────────────────────────────────────────────────────────────────────────────

# --- UVM DPI (REQUIRED) ---
UVM_DPI_LIB="${QUESTA_HOME:-/opt/questa_sim-2021.2_1/questasim}/uvm-1.2/linux_x86_64/uvm_dpi"
DPI_FLAG=""

if [[ -f "${UVM_DPI_LIB}.so" ]]; then
    DPI_FLAG="-sv_lib ${UVM_DPI_LIB}"
    print_success "UVM DPI loaded: ${UVM_DPI_LIB}.so"
else
    print_error "UVM DPI not found! This WILL crash simulation."
fi

# --- Vortex DPI (OPTIONAL) ---
VORTEX_DPI_LIB="$FLISTS_DIR/vortex_dpi"

if [[ -f "${VORTEX_DPI_LIB}.so" ]]; then
    DPI_FLAG="$DPI_FLAG -sv_lib ${VORTEX_DPI_LIB}"
    print_success "Vortex DPI loaded: ${VORTEX_DPI_LIB}.so"
else
    print_warning "Vortex DPI not found (optional)"
    print_info    "  TCU/FPU trace (dpi_trace) will be silent — vsim-3770 expected."
    print_info    "  Build once with:"
    print_info    "    QUESTA_INC=\$(dirname \$(which vsim))/../include"
    print_info    "    gcc -shared -fPIC \\"
    print_info    "        -o ${VORTEX_DPI_LIB}.so \\"
    print_info    "        \$VORTEX_HOME/hw/dpi/util_dpi.cpp \\"
    print_info    "        \$VORTEX_HOME/hw/dpi/float_dpi.cpp \\"
    print_info    "        -I\$VORTEX_HOME/hw/dpi -I\$QUESTA_INC"
fi

################################################################################
# Create Results Directory
################################################################################


print_header "Setting Up Results Directory"


RESULTS_BASE="$PROJECT_ROOT/results"
RESULTS_DATE=$(date +%Y%m%d)
RESULTS_TIME=$(date +%H%M%S)
RESULTS_RUN_DIR="$RESULTS_BASE/$RESULTS_DATE/run_${RESULTS_TIME}_${TEST_NAME}"


mkdir -p "$RESULTS_RUN_DIR"/{logs,waves,programs,reports}
ln -sfn "$RESULTS_RUN_DIR" "$RESULTS_BASE/latest"


print_success "Results directory: $RESULTS_RUN_DIR"
print_info    "Latest results:    $RESULTS_BASE/latest"


CONFIG_SNAPSHOT="$RESULTS_RUN_DIR/reports/config.txt"
cat > "$CONFIG_SNAPSHOT" << EOF
================================================================================
Test Run Configuration
================================================================================
Date:         $(date)
Test:         $TEST_NAME
Program:      ${PROGRAM:-N/A}
Interface:    $MEMORY_INTERFACE
Clusters:     $NUM_CLUSTERS
Cores:        $NUM_CORES
Warps:        $NUM_WARPS
Threads:      $NUM_THREADS
Startup Addr: $STARTUP_ADDR (passed to vsim as $STARTUP_ADDR_HEX)
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


    PROGRAM_SOURCE=""


    # Case 1: Already a .hex file
    if [[ "$PROGRAM" == *.hex ]]; then
        if [[ -f "$PROGRAM" ]]; then
            PROGRAM_TYPE="custom-hex"
            PROGRAM_HEX="$PROGRAM"
            print_success "Found hex file: $PROGRAM_HEX"

            # ── FIX C (Case 1) ───────────────────────────────────────────────
            # Validate immediately — a pre-existing .hex with @80000000 causes
            # the exact same baseaddr overflow as a freshly converted one.
            _FIRST=$(head -1 "$PROGRAM_HEX")
            if [[ "$_FIRST" == "@80000000" ]]; then
                print_error "HEX file starts with @80000000 — absolute address bug!"
                echo ""
                echo "  mem_model.load_hex_file(file, baseaddr=0x80000000) adds the @ offset"
                echo "  on top of baseaddr:"
                echo "    @80000000 + 0x80000000 = 0x100000000  ← overflow (data lost)"
                echo "    0x80000000 stays EMPTY → DUT fetches zeros → vacuous PASS"
                echo ""
                echo "  Quick fix — edit the hex file first line in place:"
                echo "    sed -i 's/^@80000000/@00000000/' $PROGRAM_HEX"
                exit 1
            fi
            # ─────────────────────────────────────────────────────────────────
        else
            print_error "Hex file not found: $PROGRAM"
            exit 1
        fi


    # Case 2: Vortex OpenCL kernel
    elif [[ -f "$VORTEX_HOME/tests/opencl/$PROGRAM/kernel.bin" ]]; then
        PROGRAM_TYPE="vortex"
        PROGRAM_SOURCE="$VORTEX_HOME/tests/opencl/$PROGRAM/kernel.bin"
        print_info "Detected Vortex kernel: $PROGRAM"
        print_info "Source: $PROGRAM_SOURCE"


    # Case 3: RISC-V test
    elif [[ "$PROGRAM" == rv* ]]; then
        PROGRAM_TYPE="riscv-test"
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
            for dir in "${RISCV_TEST_DIRS[@]}"; do echo "    - $dir"; done
            echo ""
            echo "  Build riscv-tests first:"
            echo "    git clone https://github.com/riscv/riscv-tests.git"
            echo "    cd riscv-tests && git submodule update --init --recursive"
            echo "    autoconf && ./configure --prefix=\$RISCV/target"
            echo "    make && make install"
            exit 1
        fi
        print_info "Found RISC-V test: $PROGRAM_SOURCE"


    # Case 4: RISC-V DV test (pre-generated)
    elif [[ -f "$VORTEX_HOME/third_party/riscv-dv/out/$PROGRAM/$PROGRAM" ]]; then
        PROGRAM_TYPE="riscv-dv"
        PROGRAM_SOURCE="$VORTEX_HOME/third_party/riscv-dv/out/$PROGRAM/$PROGRAM"
        print_info "Found RISC-V DV test: $PROGRAM_SOURCE"


    # Case 5: RISC-V DV test needs generation
    elif [[ "$PROGRAM" == riscv_* ]]; then
        PROGRAM_TYPE="riscv-dv"
        print_info "RISC-V DV test needs generation: $PROGRAM"
        if [[ ! -d "$VORTEX_HOME/third_party/riscv-dv" ]]; then
            print_error "RISC-V DV not found at \$VORTEX_HOME/third_party/riscv-dv"
            echo "    cd \$VORTEX_HOME/third_party"
            echo "    git clone https://github.com/chipsalliance/riscv-dv.git"
            echo "    cd riscv-dv && pip3 install -r requirements.txt"
            exit 1
        fi
        print_info "Generating with riscv-dv..."
        cd "$VORTEX_HOME/third_party/riscv-dv" || exit 1
        if python3 run.py \
            --test="$PROGRAM" \
            --simulator=questa \
            --isa=rv32imc \
            --iterations=1 \
            --steps=gen \
            2>&1 | tee "$RESULTS_RUN_DIR/logs/riscv_dv_gen.log"; then
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


    # Case 6: Custom ELF/BIN
    elif [[ -f "$PROGRAM" ]]; then
        if [[ "$PROGRAM" == *.elf ]]; then
            PROGRAM_TYPE="custom-elf"
        elif [[ "$PROGRAM" == *.bin ]]; then
            PROGRAM_TYPE="custom-bin"
        else
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
        echo "  Supported: Vortex kernel, rv* test, riscv_* DV, .hex, .elf, .bin"
        exit 1
    fi


    # Convert if needed
    if [[ -z "$PROGRAM_HEX" ]]; then
        print_header "Program Conversion"


        PROGRAM_BASENAME=$(basename "$PROGRAM_SOURCE" | sed 's/\.[^.]*$//')
        PROGRAM_HEX="$RESULTS_RUN_DIR/programs/${PROGRAM_BASENAME}.hex"
        OBJCOPY_LOG="$RESULTS_RUN_DIR/logs/objcopy.log"
        OBJCOPY="riscv64-unknown-elf-objcopy"


        print_info "Converting: $PROGRAM_SOURCE"
        print_info "Output:     $PROGRAM_HEX"
        print_info "Startup addr for objcopy: $STARTUP_ADDR"


        if [[ "$PROGRAM_TYPE" == "vortex" || "$PROGRAM_TYPE" == "custom-bin" ]]; then
            if $OBJCOPY \
                -I binary -O verilog \
                --change-addresses=$STARTUP_ADDR \
                --verilog-data-width=1 \
                "$PROGRAM_SOURCE" "$PROGRAM_HEX" 2>&1 | tee "$OBJCOPY_LOG"; then
                print_success "${PROGRAM_TYPE} converted"
            else
                print_error "Conversion failed"; cat "$OBJCOPY_LOG"; exit 1
            fi


        elif [[ "$PROGRAM_TYPE" == "riscv-test" || \
                "$PROGRAM_TYPE" == "riscv-dv"   || \
                "$PROGRAM_TYPE" == "custom-elf" ]]; then
            if $OBJCOPY \
                -O verilog \
                --change-addresses=$STARTUP_ADDR \
                --verilog-data-width=1 \
                "$PROGRAM_SOURCE" "$PROGRAM_HEX" 2>&1 | tee "$OBJCOPY_LOG"; then
                print_success "${PROGRAM_TYPE} converted"
            else
                print_error "Conversion failed"; cat "$OBJCOPY_LOG"; exit 1
            fi
        fi


        # Validate hex
        if [[ -f "$PROGRAM_HEX" ]]; then
            if [[ ! -s "$PROGRAM_HEX" ]]; then
                print_error "HEX file is empty"; exit 1
            fi
            FIRST_LINE=$(head -1 "$PROGRAM_HEX")

            # ── FIX C (converted files) ──────────────────────────────────────
            # objcopy --change-addresses=0x80000000 on a binary that is already
            # linked at 0x80000000 produces @80000000 in the output.
            # mem_model adds baseaddr on top → 0x100000000 overflow → empty RAM
            # → DUT fetches nops/zeros → test may PASS vacuously (1 instr, 154 cy).
            if [[ "$FIRST_LINE" == "@80000000" ]]; then
                print_error "Converted HEX starts with @80000000 — address overflow bug!"
                echo ""
                echo "  The ELF is already linked at 0x80000000."
                echo "  Do NOT use --change-addresses with a pre-linked ELF."
                echo "  Use --change-section-address to subtract the link base instead:"
                echo ""
                echo "    riscv64-unknown-elf-objcopy -O verilog \\"
                echo "        --verilog-data-width=1 \\"
                echo "        --change-section-address .text-0x80000000 \\"
                echo "        $PROGRAM_SOURCE $PROGRAM_HEX"
                echo ""
                echo "  Or fix in-place and re-run:"
                echo "    sed -i 's/^@80000000/@00000000/' $PROGRAM_HEX"
                exit 1
            fi
            # ─────────────────────────────────────────────────────────────────

            if [[ "$FIRST_LINE" =~ ^@[0-9a-fA-F]{8} ]]; then
                print_success "HEX format validated"
            else
                print_warning "HEX format may be incorrect (should start with @address)"
                print_info "First line: $FIRST_LINE"
            fi
            PROGRAM_SIZE=$(wc -l < "$PROGRAM_HEX")
            print_info "HEX file: $PROGRAM_SIZE lines"
            if [[ $VERBOSE -eq 1 ]]; then
                echo ""; echo "First 5 lines:"; head -5 "$PROGRAM_HEX" | sed 's/^/  /'
            fi
        else
            print_error "HEX file not created"; exit 1
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


    if [[ ! -d "work" && "$SIMULATOR" == "questa" ]]; then
        vlib work
    fi


    # -------------------------------------------------------------------------
    # COMPILE_OPTS — compile-time +define+ flags only
    # These bake the hardware configuration into the RTL and UVM at elaboration.
    # -------------------------------------------------------------------------
    COMPILE_OPTS="+define+$FPU_TYPE"


    # TCU handling — must remove ALL tcu file references from flist, not just the define
    if [[ $NO_TCU -eq 0 ]]; then
        COMPILE_OPTS="$COMPILE_OPTS +define+$TCU_TYPE"
        RTL_FLIST="vortex_rtl.flist"
        print_info "TCU: enabled ($TCU_TYPE)"
    else
        # Generate temp flist with ALL tcu lines commented out.
        # Just commenting +define+EXT_TCU_ENABLE is not enough — the tcu .sv files
        # still compile and reference undefined package symbols. Must remove them all.
        RTL_FLIST="$RESULTS_RUN_DIR/vortex_rtl_notcu.flist"
        sed '/[\/]tcu[\/]/s/^/# NOTCU: /' vortex_rtl.flist | \
        sed '/[\/]tcu$/s/^/# NOTCU: /' | \
        sed '/+define+EXT_TCU_ENABLE/s/^/# NOTCU: /' > "$RTL_FLIST"
        print_info "TCU: disabled (--no-tcu) — using temp flist without TCU files"
    fi


    COMPILE_OPTS="$COMPILE_OPTS +define+NUM_CLUSTERS=$NUM_CLUSTERS"
    COMPILE_OPTS="$COMPILE_OPTS +define+NUM_CORES=$NUM_CORES"
    COMPILE_OPTS="$COMPILE_OPTS +define+NUM_WARPS=$NUM_WARPS"
    COMPILE_OPTS="$COMPILE_OPTS +define+NUM_THREADS=$NUM_THREADS"
    COMPILE_OPTS="$COMPILE_OPTS +define+ICACHE_MSHR_SIZE=16"
    COMPILE_OPTS="$COMPILE_OPTS +define+DCACHE_MSHR_SIZE=16"
    COMPILE_OPTS="$COMPILE_OPTS +define+ICACHE_MREQ_SIZE=16"
    COMPILE_OPTS="$COMPILE_OPTS +define+DCACHE_MREQ_SIZE=16"


    if [[ "$MEMORY_INTERFACE" == "axi" ]]; then
        COMPILE_OPTS="$COMPILE_OPTS +define+USE_AXI_WRAPPER"
        print_info "Interface: AXI (USE_AXI_WRAPPER)"
    else
        print_info "Interface: Custom MEM"
    fi


    # Compile RTL
    print_info "Compiling Vortex RTL..."
    if [[ "$SIMULATOR" == "questa" ]]; then
        vlog -sv $COMPILE_OPTS \
            +incdir+"$VORTEX_HOME/third_party/cvfpu/src/common_cells/include" \
            -f "$RTL_FLIST" \
            2>&1 | tee "$RESULTS_RUN_DIR/logs/compile_rtl.log"
    fi
    if [[ $? -ne 0 ]]; then print_error "RTL compilation failed"; exit 1; fi
    print_success "RTL compiled"


    # Compile UVM
    print_info "Compiling UVM environment..."
    if [[ "$SIMULATOR" == "questa" ]]; then
        # AFTER (use the env var already set correctly in your .bashrc):
        UVM_SRC="${UVM_HOME:-/opt/questa_sim-2021.2_1/questasim/verilog_src/uvm-1.2/src}"
        vlog -sv $COMPILE_OPTS +incdir+${UVM_SRC} ${UVM_SRC}/uvm_pkg.sv \
            2>&1 | tee -a "$RESULTS_RUN_DIR/logs/compile_uvm.log"
        vlog -sv $COMPILE_OPTS \
            +incdir+${UVM_SRC} \
            -f uvm_env.flist \
            2>&1 | tee -a "$RESULTS_RUN_DIR/logs/compile_uvm.log"
    fi


else
    print_header "Skipping Compilation"
fi


################################################################################
# Simulation
################################################################################


print_header "Simulation"


# -------------------------------------------------------------------------
# SIM_OPTS — runtime +plusarg flags only — NO +define+ here
# These are read by vortex_config.sv apply_plusargs() at simulation start.
# Every name here must exactly match a $test$plusargs or $value$plusargs
# call in apply_plusargs().
# -------------------------------------------------------------------------
SIM_OPTS="+UVM_TESTNAME=$TEST_NAME"
SIM_OPTS="$SIM_OPTS +NUM_CLUSTERS=$NUM_CLUSTERS"
SIM_OPTS="$SIM_OPTS +NUM_CORES=$NUM_CORES"
SIM_OPTS="$SIM_OPTS +NUM_WARPS=$NUM_WARPS"
SIM_OPTS="$SIM_OPTS +NUM_THREADS=$NUM_THREADS"
SIM_OPTS="$SIM_OPTS +TIMEOUT=$TIMEOUT_CYCLES"
SIM_OPTS="$SIM_OPTS +STARTUP_ADDR=$STARTUP_ADDR_HEX"   # FIX A: no 0x prefix


# FIX: USE_AXI_WRAPPER must be a runtime plusarg so apply_plusargs()
#      can read it via $test$plusargs("USE_AXI_WRAPPER").
#      +define+ is compile-only and is NOT readable at sim time.
if [[ "$MEMORY_INTERFACE" == "axi" ]]; then
    SIM_OPTS="$SIM_OPTS +USE_AXI_WRAPPER"
fi


if [[ -n "$PROGRAM_HEX" ]]; then
    SIM_OPTS="$SIM_OPTS +PROGRAM=$PROGRAM_HEX"
fi


if [[ $NO_WAVES -eq 0 ]]; then
    WAVE_FILE="$RESULTS_RUN_DIR/waves/${TEST_NAME}_${MEMORY_INTERFACE}.vcd"
    SIM_OPTS="$SIM_OPTS +WAVE=$WAVE_FILE"
else
    SIM_OPTS="$SIM_OPTS +NO_WAVES"
fi


# FIX: --verbose flag must send +VERBOSE so apply_plusargs() can read it
if [[ $VERBOSE -eq 1 ]]; then
    SIM_OPTS="$SIM_OPTS +VERBOSE"
fi




print_info "Test:      $TEST_NAME"
print_info "Config:    ${NUM_CLUSTERS}CL ${NUM_CORES}C ${NUM_WARPS}W ${NUM_THREADS}T"
print_info "Interface: $MEMORY_INTERFACE"
if [[ -n "$PROGRAM" ]]; then
    print_info "Program:   $PROGRAM ($PROGRAM_TYPE)"
fi


LOG_FILE="$RESULTS_RUN_DIR/logs/simulation.log"


# FIX: vsim must NOT have +define+ — that flag is only for vlog/vcs compile.
#      USE_AXI_WRAPPER is now correctly passed via $SIM_OPTS as a plusarg.
#      FIX B: $DPI_FLAG links the DPI shared library when present.
if [[ "$SIMULATOR" == "questa" ]]; then
    if [[ $GUI_MODE -eq 1 ]]; then
        vsim vortex_tb_top $SIM_OPTS $DPI_FLAG \
            -do "add wave -r /*; run -all"
    else
        vsim -c vortex_tb_top $SIM_OPTS $DPI_FLAG \
            -do "run -all; quit -f" \
            2>&1 | tee "$LOG_FILE"
    fi
elif [[ "$SIMULATOR" == "vcs" ]]; then
    ./simv $SIM_OPTS 2>&1 | tee "$LOG_FILE"
fi


SIM_EXIT_CODE=$?


################################################################################
# Results Analysis
################################################################################


print_header "Results"


# Count UVM errors directly — this is the authoritative source
# Subtract the 2 expected end-of-test UVM_ERRORs (base_test + smoke_test banners)
# that fire ONLY when test_passed=0 — they are symptoms, not causes.
# Real errors are the ones fired DURING simulation.
UVM_ERRORS=$(grep -c "^# UVM_ERROR /" "$LOG_FILE" 2>/dev/null || true)
UVM_ERRORS=${UVM_ERRORS:-0}
UVM_FATALS=$(grep -c "^# UVM_FATAL /" "$LOG_FILE" 2>/dev/null || true)
UVM_FATALS=${UVM_FATALS:-0}
REAL_UVM_ERRORS=$((UVM_ERRORS > 2 ? UVM_ERRORS - 2 : UVM_ERRORS))

# Count RTL assertion errors — lines starting with "# ** Error:" in the log.
# These are real DUT failures that must cause the run to be marked FAILED
# even when UVM itself reports TEST PASSED (UVM doesn't see RTL asserts).
RTL_ERRORS=$(grep -c "^# \*\* Error:" "$LOG_FILE" 2>/dev/null || true)
RTL_ERRORS=${RTL_ERRORS:-0}


if [[ $SIM_EXIT_CODE -ne 0 ]]; then
    print_error "Simulation crashed (exit code: $SIM_EXIT_CODE)"
    TEST_STATUS="ERROR"
    EXIT_CODE=$SIM_EXIT_CODE


elif [[ $UVM_FATALS -gt 0 ]]; then
    print_error "TEST FAILED — $UVM_FATALS UVM_FATAL(s)"
    TEST_STATUS="FAILED"
    EXIT_CODE=1


elif [[ $REAL_UVM_ERRORS -gt 0 ]]; then
    print_error "TEST FAILED — $REAL_UVM_ERRORS UVM_ERROR(s) during simulation"
    TEST_STATUS="FAILED"
    EXIT_CODE=1


elif grep -q "^\# \*\*\* TEST FAILED" "$LOG_FILE" 2>/dev/null; then
    print_error "TEST FAILED — UVM test_passed=0"
    TEST_STATUS="FAILED"
    EXIT_CODE=1


elif [[ $RTL_ERRORS -gt 0 ]]; then
    FIRST_RTL=$(grep "^# \*\* Error:" "$LOG_FILE" | head -1 | sed 's/^# \*\* Error: *//')
    print_error "TEST FAILED — $RTL_ERRORS RTL assertion error(s)"
    print_error "  First: $FIRST_RTL"
    TEST_STATUS="FAILED"
    EXIT_CODE=2

elif grep -qE "UVM_ERROR :[[:space:]]+0" "$LOG_FILE" 2>/dev/null && \
     grep -q "TEST PASSED\|SMOKE TEST PASSED" "$LOG_FILE" 2>/dev/null; then
    print_success "TEST PASSED ✓  (0 UVM errors, 0 RTL errors)"
    TEST_STATUS="PASSED"
    EXIT_CODE=0


else
    print_warning "Test result unknown"
    TEST_STATUS="UNKNOWN"
    EXIT_CODE=3
fi


if grep -q "Total Cycles\|Cycles:" "$LOG_FILE" 2>/dev/null; then
    echo ""
    print_info "Statistics:"
    grep -E "Total Cycles|Cycles:|Instructions|IPC" "$LOG_FILE" | sed 's/^/  /'
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
  Clusters:   $NUM_CLUSTERS
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
