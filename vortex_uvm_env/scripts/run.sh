#!/usr/bin/env bash
################################################################################
# File: scripts/run.sh
# Description: Main entry point for Vortex UVM verification.
#              Contains: colors, helpers, usage, arg parsing, validation.
#              Calls prepare.sh → compile.sh → simulate.sh in sequence.
#
# Called directly or via Makefile:
#   scripts/run.sh --test=vortex_smoke_test --program=vecadd [OPTIONS]
#   make sim TEST=vortex_smoke_test PROGRAM=vecadd
#
# Plusarg contract with vortex_config.sv apply_plusargs():
#   Compile-time (+define+):  NUM_CLUSTERS, NUM_CORES, NUM_WARPS, NUM_THREADS,
#                             USE_AXI_WRAPPER, FPU_TYPE, TCU_TYPE
#   Runtime    (+plusarg):    NUM_CLUSTERS, NUM_CORES, NUM_WARPS, NUM_THREADS,
#                             USE_AXI_WRAPPER, TIMEOUT, PROGRAM, WAVE, NO_WAVES,
#                             VERBOSE, UVM_TESTNAME
################################################################################

set -e
set -o pipefail

# ── Resolve paths (symlink-safe) ──────────────────────────────────────────────
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
else
    SCRIPT_PATH="${BASH_SOURCE[0]}"
fi
SCRIPTS_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
FLISTS_DIR="$PROJECT_ROOT/flists"


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

print_header()  { echo -e "${CYAN}================================================================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}================================================================================${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ ERROR: $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ WARNING: $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }


################################################################################
# Usage
################################################################################

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
    --debug-addr             Enable LSU address calculation debug tracing
    --no-tcu                 Disable TCU (exclude TCU files from flist)
    --help                   Show this help
    --cov-report             Also write per-run coverage .txt reports (slow; off by default — use merge_coverage.sh for the real number)

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
    $0 --test=vortex_sanity_test
    $0 --test=vortex_smoke_test --program=vecadd
    $0 --test=vortex_smoke_test --program=rv32ui-p-add
    $0 --test=vortex_smoke_test --program=riscv_rand_instr_test
    $0 --test=vortex_smoke_test --program=/path/to/my_test.hex
    $0 --test=vortex_smoke_test --program=sgemm --clusters=2 --cores=2 --warps=8 --threads=4
EOF
    exit 0
}


################################################################################
# Default Configuration
################################################################################

# Test configuration
TEST_NAME=""
PROGRAM=""
PROGRAM_HEX=""
PROGRAM_TYPE=""       # vortex | riscv-test | riscv-dv | custom-hex | custom-elf | custom-bin
PROGRAM_SOURCE=""
PROGRAM_KIND=""
DOGFOOD_TESTID=""

# GPU configuration — must match vortex_config.sv apply_plusargs() names exactly
NUM_CLUSTERS=1
NUM_CORES=1
NUM_WARPS=4
NUM_THREADS=4
TIMEOUT_CYCLES=1000000

# Startup address — matches RTL VX_config.vh STARTUP_ADDR default (RV32)
STARTUP_ADDR="0x80000000"

# Interface
MEMORY_INTERFACE="axi"

# Compilation flags
FPU_TYPE="FPU_FPNEW"
TCU_TYPE="TCU_BHF"
NO_TCU=0
NO_COMPILE=0
CLEAN=0
DEBUG_ADDR_CALC=0

# Simulation options
NO_WAVES=0
GUI_MODE=0
VERBOSE=0
PER_RUN_COV_REPORT=0
STRESS_ITER=1

# Simulator (auto-detected in prepare.sh)
SIMULATOR=""

# DPI flags (built in prepare.sh, used in simulate.sh)
DPI_FLAG=""
SIMX_ENABLED=0
SIM_OPTS=""


################################################################################
# Parse Arguments
################################################################################

ORIGINAL_CMD="$0 $*"

for arg in "$@"; do
    case $arg in
        --test=*)           TEST_NAME="${arg#*=}" ;;
        --program=*)        PROGRAM="${arg#*=}" ;;
        --program-kind=*)   PROGRAM_KIND="${arg#*=}" ;;
        --dogfood-testid=*) DOGFOOD_TESTID="${arg#*=}" ;;
        --interface=*)      MEMORY_INTERFACE="${arg#*=}" ;;
        --clusters=*)       NUM_CLUSTERS="${arg#*=}" ;;
        --cores=*)          NUM_CORES="${arg#*=}" ;;
        --warps=*)          NUM_WARPS="${arg#*=}" ;;
        --threads=*)        NUM_THREADS="${arg#*=}" ;;
        --timeout=*)        TIMEOUT_CYCLES="${arg#*=}" ;;
        --startup-addr=*)   STARTUP_ADDR="${arg#*=}" ;;
        --stress-iter=*)    STRESS_ITER="${arg#*=}" ;;
        --no-compile)       NO_COMPILE=1 ;;
        --no-waves)         NO_WAVES=1 ;;
        --cov-report)       PER_RUN_COV_REPORT=1 ;;
        --gui)              GUI_MODE=1 ;;
        --clean)            CLEAN=1 ;;
        --verbose)          VERBOSE=1 ;;
        --debug-addr)       DEBUG_ADDR_CALC=1 ;;
        --no-tcu)           NO_TCU=1 ;;
        --help|-h)          usage ;;
        *)
            print_error "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ── FIX A — Strip 0x prefix from STARTUP_ADDR ────────────────────────────────
# $value$plusargs("STARTUP_ADDR=%h") silently returns 0 when the value has a
# 0x prefix. Strip it here; $STARTUP_ADDR kept for display/config only.
STARTUP_ADDR_HEX="${STARTUP_ADDR#0x}"
STARTUP_ADDR_HEX="${STARTUP_ADDR_HEX#0X}"


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

# Check if this test requires a program
TESTS_NEEDING_PROGRAM=("vortex_smoke_test" "functional_memory_test" "kernel_launch_test" "regression_test" "axi_memory_test" "barrier_sync_test" "negative_result_test" "random_instruction_stress_test" "warp_scheduling_test")
NEEDS_PROGRAM=0
for t in "${TESTS_NEEDING_PROGRAM[@]}"; do
    if [[ "$TEST_NAME" == "$t" ]]; then NEEDS_PROGRAM=1; break; fi
done

if [[ $NEEDS_PROGRAM -eq 1 && -z "$PROGRAM" ]]; then
    print_error "Test '$TEST_NAME' requires a program. Use --program=PROGRAM"
    exit 1
fi


################################################################################
# Orchestrate sub-scripts (sourced so all variables are shared)
################################################################################

source "$SCRIPTS_DIR/prepare.sh"
source "$SCRIPTS_DIR/compile.sh"
source "$SCRIPTS_DIR/simulate.sh"
