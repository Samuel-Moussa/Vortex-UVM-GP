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
#      FIX C: LD_PRELOAD forces system libstdc++ to avoid GLIBCXX_3.4.29 from Questa's GCC 7
#             This ensures libramulator.so (linked by simx_model.so) finds correct symbols.
if [[ "$SIMULATOR" == "questa" ]]; then
    # Preload correct libstdc++ to resolve GLIBCXX_3.4.29 from ramulator.so dependency
    export LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6

    if [[ $GUI_MODE -eq 1 ]]; then
        vsim vortex_tb_top $SIM_OPTS $DPI_FLAG \
            -do "add wave -r /*; run -all"
    else
        vsim -c vortex_tb_top $SIM_OPTS $DPI_FLAG \
            -do "run -all; quit -f" \
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
