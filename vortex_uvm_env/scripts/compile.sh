#!/usr/bin/env bash
################################################################################
# File: scripts/compile.sh
# Description: RTL and UVM compilation. Sourced by run.sh so all variables
#              set in run.sh and prepare.sh (SIMULATOR, QUESTA_HOME,
#              RESULTS_RUN_DIR, etc.) are directly available here.
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
    # ─ DEBUG OPTIONS ─────────────────────────────────────────────────────────────
    COMPILE_OPTS="+define+$FPU_TYPE"

    if [[ $DEBUG_ADDR_CALC -eq 1 ]]; then
        COMPILE_OPTS="$COMPILE_OPTS +define+DBG_ADDR_CALC"
        COMPILE_OPTS="$COMPILE_OPTS +define+DBG_LSU_ADDR"
        print_info "Debug: Address calculation tracing ENABLED"
    fi
    # ─────────────────────────────────────────────────────────────────────────────


    # TCU handling — must remove ALL tcu file references from flist, not just the define
    if [[ $NO_TCU -eq 0 ]]; then
        COMPILE_OPTS="$COMPILE_OPTS +define+$TCU_TYPE"
        # EXT_TCU_ENABLE is defined inside vortex_rtl.flist for the RTL, but the passive
        # probes (vx_instr_probe.sv) live in uvm_env.flist and gate their TCU covergroup on
        # `ifdef EXT_TCU_ENABLE`. Promote it to a GLOBAL compile define so the probe builds
        # its instr_class_cg_tcu covergroup and can actually sample TCU dispatches.
        COMPILE_OPTS="$COMPILE_OPTS +define+EXT_TCU_ENABLE=1"
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

    # ── Cache hierarchy (terminal-controlled: make L2=1 L3=1 / --l2=1 --l3=1) ──
    # These are PRESENCE guards in the RTL — defined with NO value. L2/L3 are the
    # optional levels: VX_cluster.sv:107 / Vortex.sv:96 pass PASSTHRU=!L{2,3}_ENABLED
    # and VX_cache_wrap.sv:160 instantiates the real VX_cache storage only when
    # PASSTHRU==0, so leaving them off means pure bypass (no cache array at all).
    # I/D caches are ON unless explicitly disabled (VX_config.vh:531-534, 586-589
    # define {I,D}CACHE_ENABLE unless {I,D}CACHE_DISABLE is set), so we emit the
    # *_DISABLE guard for the off case rather than an *_ENABLE for the on case.
    [[ "${ENABLE_L2:-0}" == "1" ]] && COMPILE_OPTS="$COMPILE_OPTS +define+L2_ENABLE"
    [[ "${ENABLE_L3:-0}" == "1" ]] && COMPILE_OPTS="$COMPILE_OPTS +define+L3_ENABLE"
    [[ "${ENABLE_ICACHE:-1}" == "0" ]] && COMPILE_OPTS="$COMPILE_OPTS +define+ICACHE_DISABLE"
    [[ "${ENABLE_DCACHE:-1}" == "0" ]] && COMPILE_OPTS="$COMPILE_OPTS +define+DCACHE_DISABLE"
    print_info "Caches: icache=${ENABLE_ICACHE:-1} dcache=${ENABLE_DCACHE:-1} L2=${ENABLE_L2:-0} L3=${ENABLE_L3:-0}"

    # Escape hatch for any OTHER non-default RTL define, without editing this script:
    #   EXTRA_RTL_DEFINES="+define+DCACHE_WRITEBACK=1" make sim ...
    # Empty by default => byte-identical. Appended last so it can override the above.
    if [[ -n "${EXTRA_RTL_DEFINES:-}" ]]; then
        COMPILE_OPTS="$COMPILE_OPTS $EXTRA_RTL_DEFINES"
        print_info "Extra RTL defines: $EXTRA_RTL_DEFINES"
    fi


    if [[ "$MEMORY_INTERFACE" == "axi" ]]; then
        COMPILE_OPTS="$COMPILE_OPTS +define+USE_AXI_WRAPPER"
        print_info "Interface: AXI (USE_AXI_WRAPPER)"
    else
        print_info "Interface: Custom MEM"
    fi


    # Compile RTL  (＋cover instruments ONLY the Vortex RTL — UVM stays uninstrumented)
    print_info "Compiling Vortex RTL..."
    if [[ "$SIMULATOR" == "questa" ]]; then
        vlog -sv -cover bcst $COMPILE_OPTS \
            +incdir+"$VORTEX_HOME/third_party/cvfpu/src/common_cells/include" \
            -f "$RTL_FLIST" \
            2>&1 | tee "$RESULTS_RUN_DIR/logs/compile_rtl.log"
    fi
    if [[ $? -ne 0 ]]; then print_error "RTL compilation failed"; exit 1; fi
    print_success "RTL compiled"


    # Compile UVM
    print_info "Compiling UVM environment..."
    if [[ "$SIMULATOR" == "questa" ]]; then
        # Build UVM path from QUESTA_HOME or use fallback
        if [[ -n "$QUESTA_HOME" && -d "$QUESTA_HOME/verilog_src/uvm-1.2/src" ]]; then
            UVM_SRC="$QUESTA_HOME/verilog_src/uvm-1.2/src"
        else
            # Fallback to standard Questa 2021.2 path
            UVM_SRC="${QUESTA_HOME:-/opt/questa_sim-2021.2_1/questasim}/verilog_src/uvm-1.2/src"
        fi

        if [[ ! -f "${UVM_SRC}/uvm_pkg.sv" ]]; then
            print_error "UVM source not found at: $UVM_SRC"
            print_info "Checked paths:"
            print_info "  - $QUESTA_HOME/verilog_src/uvm-1.2/src"
            print_info "  - /opt/questa_sim-2021.2_1/questasim/verilog_src/uvm-1.2/src"
            exit 1
        fi

        print_info "Using UVM source from: $UVM_SRC"
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
