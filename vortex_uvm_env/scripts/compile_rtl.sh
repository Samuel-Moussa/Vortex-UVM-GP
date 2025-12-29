# #!/bin/bash

# ################################################################################
# # Vortex GPGPU RTL Compilation Script
# # Compiles all RTL files in dependency order from vortex_rtl.flist
# ################################################################################

# set -e  # Exit on error

# echo "=========================================="
# echo "   Vortex GPGPU RTL Compilation"
# echo "=========================================="
# echo ""

# # -----------------------------------------------------------------------------
# # Configuration
# # -----------------------------------------------------------------------------
# FLIST="flists/vortex_rtl.flist"
# WORK_LIB="work"

# # Compilation flags
# VLOG_FLAGS="-sv +acc -timescale=1ns/1ps"
# VLOG_FLAGS="$VLOG_FLAGS -suppress 2583"  # Suppress unused module warnings
# VLOG_FLAGS="$VLOG_FLAGS -suppress 2388"  # Suppress always_comb warnings

# # Simulation defines
# DEFINES="+define+SIMULATION"
# DEFINES="$DEFINES +define+NUM_CORES=1"
# DEFINES="$DEFINES +define+NUM_WARPS=4"
# DEFINES="$DEFINES +define+NUM_THREADS=4"
# DEFINES="$DEFINES +define+NUM_CLUSTERS=1"
# DEFINES="$DEFINES +define+SOCKET_SIZE=1"

# # Include directories
# VORTEX_RTL="../Vortex/hw/rtl"
# INCDIRS="+incdir+${VORTEX_RTL}"
# INCDIRS="$INCDIRS +incdir+${VORTEX_RTL}/interfaces"
# INCDIRS="$INCDIRS +incdir+${VORTEX_RTL}/core"
# INCDIRS="$INCDIRS +incdir+${VORTEX_RTL}/cache"
# INCDIRS="$INCDIRS +incdir+${VORTEX_RTL}/mem"
# INCDIRS="$INCDIRS +incdir+${VORTEX_RTL}/libs"
# INCDIRS="$INCDIRS +incdir+${VORTEX_RTL}/fpu"
# INCDIRS="$INCDIRS +incdir+${VORTEX_RTL}/tcu"

# # -----------------------------------------------------------------------------
# # Clean and setup work library
# # -----------------------------------------------------------------------------
# echo "→ Cleaning previous compilation..."
# rm -rf ${WORK_LIB} transcript* vsim.wlf *.log
# vlib ${WORK_LIB}
# vmap ${WORK_LIB} ${WORK_LIB}
# echo ""

# # -----------------------------------------------------------------------------
# # Verify flist exists
# # -----------------------------------------------------------------------------
# if [ ! -f "$FLIST" ]; then
#     echo "❌ ERROR: File list not found: $FLIST"
#     exit 1
# fi

# echo "→ Using file list: $FLIST"
# echo "→ Work library: ${WORK_LIB}"
# echo ""

# # -----------------------------------------------------------------------------
# # Compilation tracking
# # -----------------------------------------------------------------------------
# compiled=0
# skipped=0
# failed=0
# declare -a failed_files

# # -----------------------------------------------------------------------------
# # Compile a single file
# # -----------------------------------------------------------------------------
# compile_file() {
#     local file="$1"
#     local basename=$(basename "$file")
    
#     # Check if file exists
#     if [ ! -f "$file" ]; then
#         echo "  ⚠️  SKIP: $basename (not found)"
#         ((skipped++))
#         return 1
#     fi
    
#     # Compile with vlog
#     local compile_output
#     compile_output=$(vlog $VLOG_FLAGS $DEFINES $INCDIRS "$file" 2>&1)
#     local compile_status=$?
    
#     if [ $compile_status -ne 0 ]; then
#         echo "  ❌ FAILED: $basename"
#         echo "$compile_output" | grep -i "error" | head -3
#         failed_files+=("$file")
#         ((failed++))
#         return 1
#     else
#         echo "  ✓ $basename"
#         ((compiled++))
#         return 0
#     fi
# }

# # -----------------------------------------------------------------------------
# # Process file list
# # -----------------------------------------------------------------------------
# echo "=========================================="
# echo "   Compiling RTL Files"
# echo "=========================================="
# echo ""

# while IFS= read -r line || [ -n "$line" ]; do
#     # Trim whitespace
#     line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
#     # Skip empty lines and comments
#     [ -z "$line" ] && continue
#     [[ "$line" =~ ^# ]] && continue
    
#     # Handle wildcards
#     if [[ "$line" =~ \* ]]; then
#         shopt -s nullglob
        
#         # Handle recursive wildcards (**/*.sv)
#         if [[ "$line" =~ \*\*/\* ]]; then
#             base_dir="${line%%/**/*}"
#             extension="${line##*.}"
            
#             if [ -d "$base_dir" ]; then
#                 # Find and sort files
#                 mapfile -t files < <(find "$base_dir" -name "*.$extension" 2>/dev/null | sort)
#                 for file in "${files[@]}"; do
#                     compile_file "$file" || true
#                 done
#             else
#                 echo "  ⚠️  Directory not found: $base_dir"
#                 ((skipped++))
#             fi
#         else
#             # Handle simple wildcards (*.sv)
#             files=($line)
#             if [ ${#files[@]} -eq 0 ]; then
#                 echo "  ⚠️  No files match: $line"
#                 ((skipped++))
#             else
#                 for file in "${files[@]}"; do
#                     compile_file "$file" || true
#                 done
#             fi
#         fi
        
#         shopt -u nullglob
#     else
#         # Regular file - compile directly
#         compile_file "$line" || true
#     fi
    
# done < "$FLIST"

# # -----------------------------------------------------------------------------
# # Compilation Summary
# # -----------------------------------------------------------------------------
# echo ""
# echo "=========================================="
# echo "   Compilation Summary"
# echo "=========================================="
# echo "  Compiled:  $compiled files"
# echo "  Skipped:   $skipped files"
# echo "  Failed:    $failed files"
# echo "=========================================="
# echo ""

# # -----------------------------------------------------------------------------
# # Show failed files if any
# # -----------------------------------------------------------------------------
# if [ $failed -gt 0 ]; then
#     echo "❌ COMPILATION FAILED!"
#     echo ""
#     echo "Failed files:"
#     for file in "${failed_files[@]}"; do
#         echo "  - $file"
#     done
#     echo ""
#     exit 1
# fi

# # -----------------------------------------------------------------------------
# # Success - show compiled modules
# # -----------------------------------------------------------------------------
# echo "✅ RTL COMPILATION SUCCESSFUL!"
# echo ""
# echo "→ Compiled modules in work library:"
# vdir ${WORK_LIB} | head -40
# echo ""
# echo "=========================================="
# echo "   Ready for simulation!"
# echo "=========================================="


#!/bin/bash

#=============================================================================
# Vortex RTL Compilation Script for QuestaSim/ModelSim
# This script compiles all RTL files in the correct order
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


# Verify paths
if [ ! -d "$VORTEX_HOME" ]; then
    print_error "VORTEX_HOME not found: $VORTEX_HOME"
    exit 1
fi

print_info "VORTEX_HOME: $VORTEX_HOME"
print_info "Script Directory: $SCRIPT_DIR"

# QuestaSim/ModelSim commands
VLOG="vlog"
VCOM="vcom"

# Compilation options
VLOG_OPTS="-sv -work work +acc -timescale=1ns/1ps"
VLOG_OPTS="$VLOG_OPTS -suppress 2223"  # Suppress timescale warnings
VLOG_OPTS="$VLOG_OPTS -suppress 13314" # Suppress empty module warnings

# DPI library paths
DPI_LIB="$VORTEX_HOME/hw/dpi/libdpi.so"

#=============================================================================
# Create work library if it doesn't exist
#=============================================================================
print_info "Setting up work library..."
if [ ! -d "work" ]; then
    vlib work
    print_info "Work library created"
else
    print_info "Work library already exists"
fi

#=============================================================================
# Check if DPI library exists
#=============================================================================
if [ -f "$DPI_LIB" ]; then
    print_info "DPI library found: $DPI_LIB"
    VLOG_OPTS="$VLOG_OPTS -sv_lib $DPI_LIB"
else
    print_warn "DPI library not found: $DPI_LIB"
    print_warn "Compiling without DPI support"
fi

#=============================================================================
# Compile RTL using file list
#=============================================================================
print_info "Starting RTL compilation..."

FLIST="$SCRIPT_DIR/../flists/vortex_rtl.flist"

if [ ! -f "$FLIST" ]; then
    print_error "RTL file list not found: $FLIST"
    exit 1
fi

print_info "Using file list: $FLIST"

# Compile with vlog
$VLOG $VLOG_OPTS -f $FLIST

if [ $? -eq 0 ]; then
    print_info "RTL compilation completed successfully!"
else
    print_error "RTL compilation failed!"
    exit 1
fi

#=============================================================================
# Summary
#=============================================================================
print_info "================================================"
print_info "RTL Compilation Summary"
print_info "================================================"
print_info "Status: ${GREEN}SUCCESS${NC}"
print_info "Work library: $(pwd)/work"
print_info "================================================"

exit 0