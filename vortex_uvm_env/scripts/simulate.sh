#!/usr/bin/env bash
################################################################################
# File: scripts/simulate.sh
# Description: Simulation, results analysis, summary report, and final output.
#              Sourced by run.sh — all variables from run.sh, prepare.sh and
#              compile.sh (DPI_FLAG, PROGRAM_HEX, RESULTS_RUN_DIR, etc.) are
#              directly available here.
################################################################################


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
SIM_OPTS="$SIM_OPTS +UVM_TESTNAME=$TEST_NAME"
SIM_OPTS="$SIM_OPTS +NUM_CLUSTERS=$NUM_CLUSTERS"
SIM_OPTS="$SIM_OPTS +NUM_CORES=$NUM_CORES"
SIM_OPTS="$SIM_OPTS +NUM_WARPS=$NUM_WARPS"
SIM_OPTS="$SIM_OPTS +NUM_THREADS=$NUM_THREADS"
SIM_OPTS="$SIM_OPTS +TIMEOUT=$TIMEOUT_CYCLES"
SIM_OPTS="$SIM_OPTS +STARTUP_ADDR=$STARTUP_ADDR_HEX"   # FIX A: no 0x prefix

# Regression harness: program kind selects the kernel_arg_t layout in
# regression_test.sv; dogfood sub-kernel selector is optional.
if [[ -n "$PROGRAM_KIND" ]]; then
    SIM_OPTS="$SIM_OPTS +PROGRAM_KIND=$PROGRAM_KIND"
fi
if [[ -n "$DOGFOOD_TESTID" ]]; then
    SIM_OPTS="$SIM_OPTS +DOGFOOD_TESTID=$DOGFOOD_TESTID"
fi


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

# Stress iterations — read by random_instruction_stress_test via +NUM_STRESS_ITER
if [[ "${STRESS_ITER:-1}" -gt 1 ]]; then
    SIM_OPTS="$SIM_OPTS +NUM_STRESS_ITER=$STRESS_ITER"
fi

# AXI backpressure test — env AXI_THROTTLE=1 makes the AXI slave inject ready
# wait-states (read by axi_driver.sv $test$plusargs). Exercises the AXI stability
# assertions + downstream backpressure conditions/branches. Default unset = OFF.
if [[ -n "${AXI_THROTTLE:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +AXI_THROTTLE=$AXI_THROTTLE"
fi

# AXI read-flood test — env AXI_FLOOD=1 makes the AXI slave stream read responses
# back-to-back so the DUT deasserts rready (exercises r_valid/r_data stable). OFF by default.
if [[ -n "${AXI_FLOOD:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +AXI_FLOOD=$AXI_FLOOD"
fi

# Phase-A0 lockstep — env LOCKSTEP=1 enables per-instruction DUT-vs-SimX checking
# (forces SimX on in vortex_config). LOCKSTEP_INJECT=1 adds a 1-bit fault to the
# first captured wb lane to prove the comparator is non-vacuous. Both OFF by default.
if [[ -n "${LOCKSTEP:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +LOCKSTEP"
fi
if [[ -n "${LOCKSTEP_INJECT:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +LOCKSTEP_INJECT"
fi
if [[ -n "${LSU_DEBUG:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +LSU_DEBUG"
fi
# Per-instruction LOAD-DATA comparison (LSU probe overlay) is now ON by default —
# sound via the SimX effective-address region filter (OBS-002). LOCKSTEP_LOADS=1 is
# retained as a harmless no-op; NO_LOCKSTEP_LOADS=1 falls back to PC/rd/ordering-only
# for loads (their data then covered by the end-state memory check).
if [[ -n "${LOCKSTEP_LOADS:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +LOCKSTEP_LOADS"
fi
if [[ -n "${NO_LOCKSTEP_LOADS:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +NO_LOCKSTEP_LOADS"
fi
# RVVI load-bus two-pass feed (Phase A1(e)) — when pass-1 lockstep finds provably
# -racy in-region load divergences, re-run SimX driven by the DUT's loaded values
# on exactly those loads and re-compare; residual mismatches are REAL divergences,
# not unsynchronizable races. OFF by default (single pass). For multi-cluster
# single-hart random tests (no_fence/full_interrupt) this makes them verifiable.
if [[ -n "${LOCKSTEP_LOADFEED:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +LOCKSTEP_LOADFEED"
fi
# A6 — dump the aligned DUT/SimX retirement streams for the OFFLINE Spike
# independence audit (scripts/spike_audit.py). Observability only: it writes a
# file and touches no verdict, so an armed run and a bare run reach the same
# conclusion. OFF unless a path is given.
if [[ -n "${LOCKSTEP_TRACE:-}" ]]; then
    SIM_OPTS="$SIM_OPTS +LOCKSTEP_TRACE=${LOCKSTEP_TRACE}"
fi

# Generic runtime plusarg passthrough — the sim-time counterpart of
# EXTRA_RTL_DEFINES (compile time). Lets any TB/UVM plusarg be driven from the
# terminal without editing this script, e.g.
#   EXTRA_PLUSARGS="+L2CACHE" make sim ...
# Empty by default => byte-identical. Appended last so it can override.
if [[ -n "${EXTRA_PLUSARGS:-}" ]]; then
    SIM_OPTS="$SIM_OPTS $EXTRA_PLUSARGS"
    print_info "Extra plusargs: $EXTRA_PLUSARGS"
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
#      FIX C: LD_PRELOAD forces system libstdc++ to avoid GLIBCXX_3.4.29 from Questa's GCC 7
#             This ensures libramulator.so (linked by simx_model.so) finds correct symbols.

PROG_SHORT="$(basename "${PROGRAM%.*}")"   # strips path + .elf → "functional_mem"

if [[ "$SIMULATOR" == "questa" ]]; then
    # Preload correct libstdc++ to resolve GLIBCXX_3.4.29 from ramulator.so dependency
    export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6

    if [[ $GUI_MODE -eq 1 ]]; then
        vsim -coverage vortex_tb_top $SIM_OPTS $DPI_FLAG \
            -do "add wave -r /*; run -all"
    else
        vsim -coverage -c vortex_tb_top $SIM_OPTS $DPI_FLAG \
            -onfinish stop \
            -do "run -all; coverage save -testname ${TEST_NAME}_${PROG_SHORT} $RESULTS_RUN_DIR/reports/coverage.ucdb; quit -f" \
            2>&1 | tee "$LOG_FILE"
    fi

    unset LD_PRELOAD
elif [[ "$SIMULATOR" == "vcs" ]]; then
    ./simv $SIM_OPTS 2>&1 | tee "$LOG_FILE"
fi


SIM_EXIT_CODE=$?


################################################################################
# Results Analysis
################################################################################


print_header "Results"


# Count UVM errors directly — this is the authoritative source.
# T4: no subtraction. Every UVM_ERROR in the log is a real failure.
# The old "-2" workaround was hiding real errors; root causes that
# generated phantom errors (wait_for_completion stale event, vacuous-run)
# were fixed directly (commits 2ccef437, 11f71359).
UVM_ERRORS=$(grep -c "^# UVM_ERROR /" "$LOG_FILE" 2>/dev/null || true)
UVM_ERRORS=${UVM_ERRORS:-0}
UVM_FATALS=$(grep -c "^# UVM_FATAL /" "$LOG_FILE" 2>/dev/null || true)
UVM_FATALS=${UVM_FATALS:-0}
REAL_UVM_ERRORS=$UVM_ERRORS

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


elif grep -q "^# \*\*\* TEST FAILED" "$LOG_FILE" 2>/dev/null; then
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
# Coverage report (per-run; merge across runs via merge_coverage.sh)
################################################################################


COV_UCDB="$RESULTS_RUN_DIR/reports/coverage.ucdb"
if [[ "$SIMULATOR" == "questa" && -f "$COV_UCDB" && $PER_RUN_COV_REPORT -eq 1 ]]; then
    EXCLUDE_DO="$SCRIPTS_DIR/coverage_exclude.do"
    EXCL_CMD=""
    [[ -f "$EXCLUDE_DO" ]] && EXCL_CMD="do $EXCLUDE_DO;"
    print_info "Coverage: generating per-run report (--cov-report)"
    vsim -viewcov "$COV_UCDB" -c -do "
        ${EXCL_CMD}
        coverage report -details -cvg -code bcst -output $RESULTS_RUN_DIR/reports/coverage.txt;
        coverage report -details -byfile -output $RESULTS_RUN_DIR/reports/coverage_by_file.txt;
        quit -f;" >/dev/null 2>&1 || true
fi

# auto-stage this run's UCDB for the next merge (one slot PER PROGRAM, so
# re-running a kernel overwrites its own slot instead of piling up)
if [[ -f "$COV_UCDB" ]]; then
    mkdir -p "$PROJECT_ROOT/cov/staging"
    stage_name="${TEST_NAME}_${PROG_SHORT}"
    stage_name="$(echo "$stage_name" | tr '/ ' '__')"   # sanitize path/space
    cp "$COV_UCDB" "$PROJECT_ROOT/cov/staging/${stage_name}.ucdb"
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

# A5: propagate the verdict. This file is sourced as run.sh's last line, so this
# exit IS run.sh's exit code — `make sim`/`sim-only` now return the real verdict
# (0=PASSED, 1=UVM fail, 2=RTL assertion fail, 3=unknown) instead of always 0.
# Without this, the RTL-assert gate above was print-only (verdict never left the
# script) and DUT RUNTIME_ASSERT firings could not fail a run at suite level.
exit $EXIT_CODE
