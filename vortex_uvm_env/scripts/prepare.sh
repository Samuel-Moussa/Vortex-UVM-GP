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

# ── RISCV-DV HOME ────────────────────────────────────────────────────────────
# Default: ~/riscv-dv. Override with env var RISCV_DV_HOME before calling make.
RISCV_DV_HOME="${RISCV_DV_HOME:-$HOME/riscv-dv}"
if [[ -d "$RISCV_DV_HOME" ]]; then
    print_success "riscv-dv: $RISCV_DV_HOME"
else
    print_info "riscv-dv not found at $RISCV_DV_HOME (only needed for riscv_* programs)"
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
        # TCU: the RTL is compiled with EXT_TCU_ENABLE (vortex_rtl.flist), so the SimX
        # golden model MUST match — otherwise SimX has no tensor_unit, can't decode the
        # WMMA op, and aborts (run classified UNVERIFIABLE). The simx Makefile keys the
        # tensor_unit.cpp source off -DEXT_TCU_ENABLE in CONFIGS; the DPI wrapper needs
        # the same define so its decode path matches. Format (bf16/…) is decoded from the
        # instruction at runtime, so no separate TCU_BHF define is required for SimX.
        ARCH_FLAGS="$ARCH_FLAGS -DEXT_TCU_ENABLE"
        # Rebuild the SimX CORE objects with the per-config macros, not just the DPI
        # wrapper. SimX sizes ibuffers_/etc. at runtime from arch.num_warps() but
        # bounds its issue loops with COMPILE-TIME macros (PER_ISSUE_WARPS,
        # ISSUE_WIDTH = UP(NUM_WARPS/16)). If obj/*.o were built with a different
        # NUM_WARPS than the run config, Core::issue() over-indexes ibuffers_ and
        # SimX aborts (vector::_M_range_check) — leaving memory poison and a vacuous
        # scoreboard. The simx Makefile keys a CONFIG_FILE off CONFIGS, so this only
        # recompiles when the config actually changes. (Fixes multi-config SimX;
        # enables the D-matrix to verify at any NUM_WARPS/NUM_THREADS.)
        make -C "$VORTEX_HOME/sim/simx" CONFIGS="$ARCH_FLAGS" 2>&1
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


    # Case 4/5: RISC-V DV test — use PROGRAM= to name the riscv-dv profile exactly.
    # RISCV_DV_REGEN=1 forces fresh generation; RISCV_DV_REGEN=0 (default) uses the
    # newest pre-generated assembly under $RISCV_DV_HOME/out_*/asm_test/ if it exists.
    #
    # SimX-compatible profiles (no privileged instructions):
    #   riscv_arithmetic_basic_test   — arithmetic only, no load/store/branch  ← safe with SimX
    #   riscv_loop_test               — loops + branches
    #   riscv_jump_stress_test        — jump-heavy
    # Full random profiles (mret/trap handlers → SimX will SIGABRT):
    #   riscv_rand_instr_test         — full random, use without SimX comparison
    elif [[ "$PROGRAM" == riscv_* ]]; then
        RISCV_DV_TEST="$PROGRAM"
        PROGRAM_TYPE="riscv-dv"

        if [[ ! -d "$RISCV_DV_HOME" ]]; then
            print_error "riscv-dv not found at $RISCV_DV_HOME"
            echo "  Install: git clone https://github.com/chipsalliance/riscv-dv.git ~/riscv-dv"
            echo "           cd ~/riscv-dv && pip3 install -r requirements.txt"
            echo "  Or set: export RISCV_DV_HOME=/path/to/riscv-dv"
            exit 1
        fi

        # ── FW-1: SEED CONTROL + REPRODUCIBILITY ────────────────────────────
        # Before this, riscv-dv was invoked with --iterations=1 and NO seed, so
        # every regeneration produced a DIFFERENT program: a random-stimulus
        # failure could not be reproduced, bisected or regressed. (That is the
        # most likely cause of riscv_non_compressed_instr_test / riscv_rand_jump_test
        # failing in the 2026-08-06 sweep having passed earlier.)
        #
        #   RV_SEED=<n>        pin the seed (DEFAULT 1 => the committed suite is a
        #                      STABLE regression gate: a failure means a real change,
        #                      not merely a different program)
        #   RV_START_SEED=<n>  + RV_ITERATIONS=<k> => sweep k consecutive seeds
        #                      (the FW-1 seed-farm mode; mutually exclusive with RV_SEED)
        #
        # The generated program is cached in a SEED-KEYED output directory, so
        # reuse is deterministic. The previous "newest .S found on disk" lookup was
        # itself a second reproducibility hole: which program you got depended on
        # what happened to be generated last, across all seeds and all profiles.
        RV_SEED="${RV_SEED:-1}"
        RV_ITERATIONS="${RV_ITERATIONS:-1}"
        if [[ -n "${RV_START_SEED:-}" ]]; then
            RV_SEED_ARGS="--start_seed=${RV_START_SEED} --iterations=${RV_ITERATIONS}"
            RV_SEED_TAG="s${RV_START_SEED}n${RV_ITERATIONS}"
            RV_SEED_DESC="start_seed=${RV_START_SEED} iterations=${RV_ITERATIONS}"
        else
            # --seed implies --iterations=1 in riscv-dv; do not pass both.
            RV_SEED_ARGS="--seed=${RV_SEED}"
            RV_SEED_TAG="s${RV_SEED}"
            RV_SEED_DESC="seed=${RV_SEED}"
        fi
        RV_OUT_DIR="$RISCV_DV_HOME/out_vortex_${RISCV_DV_TEST}_${RV_SEED_TAG}"
        print_info "riscv-dv randomization: ${RV_SEED_DESC}  (out: $(basename "$RV_OUT_DIR"))"

        # Try the SEED-KEYED cache first unless RISCV_DV_REGEN=1
        RISCV_DV_ASM=""
        if [[ "${RISCV_DV_REGEN:-0}" != "1" ]]; then
            RISCV_DV_ASM=$(find "$RV_OUT_DIR" -path "*/asm_test/${RISCV_DV_TEST}_0.S" \
                               -type f 2>/dev/null | sort | head -1)
            if [[ -n "$RISCV_DV_ASM" ]]; then
                PROGRAM_SOURCE="$RISCV_DV_ASM"
                print_info "Using cached assembly for ${RV_SEED_DESC} (RISCV_DV_REGEN=1 to force refresh): $PROGRAM_SOURCE"
            fi
        fi

        if [[ -z "$RISCV_DV_ASM" ]]; then
            print_info "Generating riscv-dv test: $RISCV_DV_TEST"
            cd "$RISCV_DV_HOME" || exit 1
            if python3 run.py \
                --test="$RISCV_DV_TEST" \
                --simulator=questa \
                --target=rv32im \
                $RV_SEED_ARGS \
                -o "$RV_OUT_DIR" \
                --steps=gen \
                2>&1 | tee "$RESULTS_RUN_DIR/logs/riscv_dv_gen.log"; then
                PROGRAM_SOURCE=$(find "$RV_OUT_DIR" \
                    -path "*/asm_test/${RISCV_DV_TEST}_0.S" -type f 2>/dev/null | sort | head -1)
                if [[ -z "$PROGRAM_SOURCE" ]]; then
                    print_error "Generated assembly not found — expected: out_*/asm_test/${RISCV_DV_TEST}_0.S"
                    exit 1
                fi
                print_success "Generated: $PROGRAM_SOURCE"
            else
                print_error "riscv-dv generation failed"
                cat "$RESULTS_RUN_DIR/logs/riscv_dv_gen.log"
                exit 1
            fi
            cd "$FLISTS_DIR" || exit 1
        fi

        # FW-1: make the run self-describing. The seed and the EXACT program are
        # recorded next to the results, so a failure found months later can be
        # reproduced from the log alone without guessing what riscv-dv produced.
        # ── FW-1b GUARD: detect two profiles that emit the SAME program ─────
        # riscv_pmp_test and riscv_non_compressed_instr_test generated
        # BYTE-IDENTICAL programs (md5 16be14c6ebe6): both testlist entries
        # delegate to `gen_test: riscv_rand_instr_test` and their distinguishing
        # gen_opts are INERT at --target=rv32im. The suite counted 2 results for
        # 1 program, so a pass was double-counted and their single 2CL failure
        # looked like two divergences. Nothing detected it — both names are in
        # the testlist and generation succeeded, so there was no error to catch.
        # Record every program's md5 and say so loudly on a collision.
        # WARNING, not fatal: a duplicate does not make a result WRONG, it makes
        # the test COUNT wrong — and failing the run would block a legitimate
        # rerun over a bookkeeping issue.
        RV_MD5=$(md5sum "$PROGRAM_SOURCE" 2>/dev/null | cut -d' ' -f1)
        RV_MANIFEST="$RISCV_DV_HOME/vortex_program_md5.manifest"
        if [[ -n "$RV_MD5" ]]; then
            if [[ -f "$RV_MANIFEST" ]]; then
                RV_DUP=$(awk -v m="$RV_MD5" -v t="$RISCV_DV_TEST" -v s="$RV_SEED_TAG" \
                         '$1==m && $3==s && $2!=t {print $2}' "$RV_MANIFEST" 2>/dev/null \
                         | sort -u | tr '\n' ' ')
                if [[ -n "$RV_DUP" ]]; then
                    print_warning "FW-1b: '${RISCV_DV_TEST}' produced a program IDENTICAL to: ${RV_DUP}(md5 ${RV_MD5:0:12}, seed ${RV_SEED_TAG})"
                    print_warning "  These are NOT distinct tests — do not count them separately."
                    print_warning "  Their gen_opts are almost certainly inert at this --target."
                fi
            fi
            grep -qs "^${RV_MD5} ${RISCV_DV_TEST} ${RV_SEED_TAG}\$" "$RV_MANIFEST" 2>/dev/null || \
                echo "${RV_MD5} ${RISCV_DV_TEST} ${RV_SEED_TAG}" >> "$RV_MANIFEST" 2>/dev/null || true
        fi

        {
            echo "riscv_dv_test   = $RISCV_DV_TEST"
            echo "randomization   = $RV_SEED_DESC"
            echo "program_md5     = ${RV_MD5:-unknown}"
            echo "reproduce_with  = make sim TEST=random_instruction_stress_test PROGRAM=$RISCV_DV_TEST RV_SEED=${RV_SEED} RISCV_DV_REGEN=1"
            echo "program_source  = $PROGRAM_SOURCE"
            echo "out_dir         = $RV_OUT_DIR"
        } > "$RESULTS_RUN_DIR/riscv_dv_seed.txt" 2>/dev/null || true
        cp "$PROGRAM_SOURCE" "$RESULTS_RUN_DIR/" 2>/dev/null || true
        print_info "SEED RECORD: ${RV_SEED_DESC} -> $RESULTS_RUN_DIR/riscv_dv_seed.txt"


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

            # riscv-dv sources are raw .S assembly — must compile to ELF first.
            # riscv-test and custom-elf sources are already ELFs → skip this step.
            if [[ "$PROGRAM_TYPE" == "riscv-dv" && "$PROGRAM_SOURCE" == *.S ]]; then
                # Vortex RTL does not implement machine-mode CSRs (0x300–0x3FF, 0xF14)
                # or mret — strip them from the generated assembly to avoid RTL assertion
                # errors. nop replaces mret; machine-mode csrw/csrr become plain nop.
                ASM_CLEAN="${PROGRAM_HEX%.hex}_clean.S"
                sed \
                    -e 's/\bcsrw\s\+0x3[0-9a-fA-F][0-9a-fA-F]\b.*/nop/g' \
                    -e 's/\bcsrr\s\+[a-z0-9]*,\s*0x3[0-9a-fA-F][0-9a-fA-F]\b.*/nop/g' \
                    -e 's/\bcsrr\s\+[a-z0-9]*,\s*0xf14\b.*/nop/g' \
                    -e 's/\bmret\b/nop/g' \
                    -e 's/\becall\b/ebreak/g' \
                    "$PROGRAM_SOURCE" > "$ASM_CLEAN"
                print_info "Stripped machine-mode CSRs/mret, replaced ecall→ebreak → $ASM_CLEAN"

                # ── OBS-027: CORE GATE (must run AFTER the sed above) ────────
                # riscv-dv emits a SINGLE-HART program whose hart dispatch is a
                # structural no-op: `csrr x5,0xf14; li x6,0; beq x5,x6,0f` where the
                # branch target IS the next instruction (confirmed in the linked
                # binary: `beq t0,t1,80000018` at 0x80000014). The sed above then
                # rewrites that csrr to nop, so even the vestigial hart read is gone.
                # Vortex cores ALL self-start from reset (VX_schedule.sv:230), so at
                # >=2 cores every core executes the same stream against the same
                # .data with no fences => store ORDER decides the surviving values,
                # and the timing-accurate RTL orders them differently from SimX.
                # Both models are deterministic and self-consistent; they simply
                # disagree. Result: every riscv-dv run at >=2 cores was
                # architecturally undefined. Gate it for real.
                #
                # VX_CSR_CORE_ID (0xCC2), NOT VX_CSR_MHARTID (0xF14), because:
                #  (1) 0xF14 is stripped by the sed above; 0xCC2 matches none of
                #      those patterns, so this carries no ordering dependency.
                #  (2) MHARTID returns a COMPOSED gtid
                #      (CORE_ID<<(NW_BITS+NT_BITS)) + (wid<<NT_BITS) + tid
                #      (VX_csr_unit.sv:125,132), so testing it !=0 is only valid
                #      because reset leaves warp0/thread0 alone
                #      (VX_schedule.sv:230-233). VX_csr_data.sv:179 returns CORE_ID
                #      directly — no warp/thread terms, no config arithmetic, valid
                #      at ANY NCL/NC/NW/NT.
                #  (3) Both models compose the global core id identically: RTL
                #      VX_cluster.sv:132 -> VX_socket.sv:227; SimX processor.cpp:37
                #      -> cluster.cpp:39 -> socket.cpp:100, read back at
                #      emulator.cpp:501. Equal on both sides by construction.
                # vx_tmc 0 (.insn r 0x0B,0,0,x0,x0,x0) retires the warp: empty tmask
                # -> SimX active_warps_.reset(wid) (execute.cpp:1638-1640), matching
                # the RTL retire. ebreak would NOT work — it has no execute-side
                # consumer in Vortex (OBS-024).
                # On 1 core this is a fall-through and the program is unchanged.
                sed -i '/^_start:/a\                  csrr x5, 0xCC2\n                  beqz x5, _vortex_core0\n                  .insn r 0x0B, 0, 0, x0, x0, x0\n_vortex_core0:' "$ASM_CLEAN"
                if grep -q "^_vortex_core0:" "$ASM_CLEAN"; then
                    print_info "Injected core gate (VX_CSR_CORE_ID != 0 → vx_tmc 0): only core 0 runs"
                else
                    print_error "Core gate NOT injected — no '^_start:' anchor in $ASM_CLEAN."
                    print_error "OBS-027: without it every core runs the same single-hart program"
                    print_error "against the same .data, so a multi-core result is UNDEFINED."
                    exit 1
                fi

                # ── Self-checking signature epilogue ─────────────────────────
                # Pure-arithmetic riscv-dv tests compute only in registers and write
                # nothing to memory → the black-box end-state scoreboard has nothing
                # to compare (vacuous pass). Make them self-checking like a kernel:
                # replace just the test_done exit (test_done: li gp,N; ecall/ebreak)
                # with a dump of x1..x30 to a linked .data buffer (vortex_sig), then
                # vx_tmc 0 to retire the warp. DUT and SimX run identical code → buffer
                # → real DUT-vs-SimX comparison. Three things make this work:
                #   1. LINKED buffer (not a bare absolute addr): Vortex L1 is
                #      write-allocate, so the first store to a fresh line issues a
                #      FILL READ. An unloaded address (e.g. 0x80100000) gets no read
                #      response → the store wedges. A .data buffer of explicit zeros
                #      is in the loaded image, so the fill returns data and completes.
                #   2. vx_tmc 0 (RISCV_CUSTOM0=0x0B) RETIRES the warp. Vortex ebreak
                #      does NOT deactivate the warp — without a real retire the core
                #      never quiesces, the dirty-line write-back never drains, and the
                #      completion gate (tb_execution_complete && axi_idle && mem_idle)
                #      never opens (the prior hangs). Retiring = the kernel busy=0 path.
                #   3. NO fence (would stall the warp before it can retire).
                # x31 is the base pointer (la). write_tohost/_exit labels are kept (a
                # trap handler does `la x20, write_tohost`) but share the retire path.
                # Replace ONLY the 3-line test_done exit block (test_done: li gp,N;
                # ecall/ebreak). riscv-dv places the sub_N sub-programs and the
                # write_tohost handshake AFTER test_done, so spanning the range up to
                # `j write_tohost` would delete the sub-programs and break linking for
                # loop/jump profiles. vx_tmc 0 retires the warp right at test_done, so
                # write_tohost is never reached and is left untouched.
                # Bounded + portable: buffer the test_done block and inject on its
                # ecall/ebreak terminator (plain match — gawk treats \b as backspace,
                # not a word boundary, so it is NOT used). If the terminator is not
                # within a few lines (unexpected exit shape), flush the buffer
                # UNCHANGED — never run to EOF deleting the rest of the file.
                awk '
                  /^test_done:/ && !injected { inblk = 1; buf = ""; cnt = 0 }
                  inblk {
                    buf = buf $0 "\n"; cnt++;
                    if ($0 ~ /ebreak/ || $0 ~ /ecall/) {
                      print "test_done:";
                      print "                  la x31, vortex_sig";
                      for (i = 1; i <= 30; i++)
                        print "                  sw x" i ", " (i-1)*4 "(x31)";
                      print "                  .insn r 0x0B, 0, 0, x0, x0, x0";  # vx_tmc 0 — retire warp
                      print "_vortex_done:     j _vortex_done";                 # safety (unreached after retire)
                      inblk = 0; injected = 1; next;
                    }
                    if (cnt >= 6) { printf "%s", buf; inblk = 0; next; }        # not the exit block — emit unchanged
                    next;
                  }
                  { print }
                  END {
                    if (injected) {
                      print ".section .data";
                      print ".align 6";
                      print "vortex_sig:";
                      print ".rept 32";
                      print ".4byte 0";
                      print ".endr";
                    }
                  }
                ' "$ASM_CLEAN" > "${ASM_CLEAN}.sig" && mv "${ASM_CLEAN}.sig" "$ASM_CLEAN"
                if grep -q "^_vortex_done:" "$ASM_CLEAN"; then
                    print_info "Injected self-checking GPR dump (x1..x30 → vortex_sig) + vx_tmc 0 retire"
                else
                    print_warning "No 'test_done:'..'j write_tohost' exit block found — signature epilogue NOT injected (run stays vacuous)"
                fi

                PROGRAM_SOURCE="$ASM_CLEAN"

                ASM_ELF="${PROGRAM_HEX%.hex}.elf"
                RISCV_GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
                print_info "Compiling riscv-dv assembly → ELF: $ASM_ELF"
                if $RISCV_GCC \
                    -static -mcmodel=medany -fvisibility=hidden \
                    -nostdlib -nostartfiles \
                    -I"$RISCV_DV_HOME/user_extension" \
                    -T"$RISCV_DV_HOME/scripts/link.ld" \
                    "$PROGRAM_SOURCE" \
                    -o "$ASM_ELF" \
                    -march=rv32im_zicsr_zifencei -mabi=ilp32 \
                    2>&1 | tee "$OBJCOPY_LOG"; then
                    print_success "riscv-dv compiled to ELF"
                    PROGRAM_SOURCE="$ASM_ELF"
                else
                    print_error "riscv-dv assembly compilation failed"
                    cat "$OBJCOPY_LOG"; exit 1
                fi
            fi

            # No --change-addresses: ELF is already linked at 0x80000000.
            # objcopy without the flag outputs @00000000 (relative offset 0),
            # and mem_model adds baseaddr=0x80000000 on top → correct placement.
            # Using --change-addresses=0x80000000 causes @80000000 in the hex,
            # then 0x80000000+0x80000000=0x100000000 overflow → empty RAM → X-prop.
            if $OBJCOPY \
                -O verilog \
                --verilog-data-width=1 \
                "$PROGRAM_SOURCE" "$PROGRAM_HEX" 2>&1 | tee "$OBJCOPY_LOG"; then
                print_success "${PROGRAM_TYPE} converted"
            else
                print_error "Conversion failed"; cat "$OBJCOPY_LOG"; exit 1
            fi
            # Strip Windows CRLF if objcopy emitted them (WSL2 toolchain quirk).
            tr -d '\r' < "$PROGRAM_HEX" > "${PROGRAM_HEX}.tmp" && mv "${PROGRAM_HEX}.tmp" "$PROGRAM_HEX"
            # ELFs linked at 0x80000000 produce @80000000; mem_model expects @00000000
            # (it adds baseaddr on top). Remap silently — both conventions are valid.
            if [[ "$(head -1 "$PROGRAM_HEX")" == "@80000000" ]]; then
                # Remap ALL section markers: @80XXXXXX → @00XXXXXX (subtract link base)
                sed -i 's/^@80/@00/' "$PROGRAM_HEX"
                print_info "Remapped @80XXXXXX → @00XXXXXX for all sections (ELF linked at 0x80000000)"
            fi
        fi


        # Validate hex
        if [[ -f "$PROGRAM_HEX" ]]; then
            if [[ ! -s "$PROGRAM_HEX" ]]; then
                print_error "HEX file is empty"; exit 1
            fi
            FIRST_LINE=$(head -1 "$PROGRAM_HEX" | tr -d '\r')

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
