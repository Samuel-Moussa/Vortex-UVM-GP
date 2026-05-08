#!/usr/bin/env bash
################################################################################
# File: scripts/prepare.sh
# Description: Environment checks, results directory setup, and program
#              resolution/conversion. Sourced by run.sh — all variables
#              (SIMULATOR, DPI_FLAG, RESULTS_RUN_DIR, PROGRAM_HEX, etc.)
#              flow directly into compile.sh and simulate.sh.
################################################################################


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

# ── QUESTA_HOME DETECTION ───────────────────────────────────────────────────
# Try to auto-detect QUESTA_HOME if not already set
if [[ -z "$QUESTA_HOME" ]]; then
    # Try standard installation paths
    if [[ -d "/opt/questa_sim-2021.2_1/questasim" ]]; then
        QUESTA_HOME="/opt/questa_sim-2021.2_1/questasim"
    elif [[ -d "$HOME/intelFPGA/21.2/questa_sim/questasim" ]]; then
        QUESTA_HOME="$HOME/intelFPGA/21.2/questa_sim/questasim"
    elif command -v vsim &> /dev/null; then
        # Try to derive from vsim location
        QUESTA_HOME="$(dirname $(dirname $(which vsim)))"
    else
        print_warning "QUESTA_HOME not set and auto-detection failed"
        QUESTA_HOME=""
    fi
fi

if [[ -n "$QUESTA_HOME" ]]; then
    print_success "QUESTA_HOME: $QUESTA_HOME"
fi

# ── DPI LIBRARY PATHS ────────────────────────────────────────────────────────
UVM_DPI_LIB="$QUESTA_HOME/uvm-1.2/linux_x86_64/uvm_dpi"
SIMX_REF_DIR="$PROJECT_ROOT/uvm_env/ref_model"
SIMX_MODEL_LIB="$SIMX_REF_DIR/simx_model"

DPI_FLAG=""
SIMX_ENABLED=0

# --- UVM DPI (REQUIRED) ---
if [[ -f "${UVM_DPI_LIB}.so" ]]; then
    DPI_FLAG="$DPI_FLAG -sv_lib ${UVM_DPI_LIB}"
    print_success "UVM DPI: ${UVM_DPI_LIB}.so"
else
    print_error "UVM DPI not found! Simulation will crash."
fi

# --- SimX Golden Model (build if needed) ---
print_header "SimX Golden Model"

if [[ -z "$VORTEX_HOME" ]]; then
    print_warning "VORTEX_HOME not set — skipping SimX build"
elif [[ ! -d "$VORTEX_HOME/sim/simx/obj" ]]; then
    print_warning "SimX not built (no obj/ in $VORTEX_HOME/sim/simx)"
    print_info  "Build SimX first: cd \$VORTEX_HOME/sim/simx && make"
else
    print_info "Building SimX DPI library..."
    (
        cd "$SIMX_REF_DIR" || exit 1
        ARCH_FLAGS="-DNUM_CLUSTERS=${NUM_CLUSTERS} -DNUM_CORES=${NUM_CORES}"
        ARCH_FLAGS="$ARCH_FLAGS -DNUM_WARPS=${NUM_WARPS} -DNUM_THREADS=${NUM_THREADS}"
        make build \
            VORTEX_HOME="$VORTEX_HOME" \
            QUESTA_HOME="$QUESTA_HOME" \
            EXTRA_CXXFLAGS="$ARCH_FLAGS" 2>&1
    )
    if [[ $? -eq 0 && -f "${SIMX_MODEL_LIB}.so" ]]; then
        DPI_FLAG="$DPI_FLAG -sv_lib ${SIMX_MODEL_LIB}"
        SIMX_ENABLED=1
        print_success "SimX DPI built and linked: simx_model.so"
    else
        print_warning "SimX DPI build failed — running without golden model"
    fi
fi

# Add NO_SIMX plusarg if SimX not available
if [[ $SIMX_ENABLED -eq 0 ]]; then
    SIM_OPTS="$SIM_OPTS +NO_SIMX"
    print_info "SimX disabled (add +NO_SIMX to suppress this)"
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
