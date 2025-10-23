#!/usr/bin/env bash
echo "=== GP environment check ==="
printf "QUESTASIM_HOME: %s\n" "${QUESTASIM_HOME:-<not set>}"
printf "UVM_HOME:        %s\n" "${UVM_HOME:-<not set>}"
printf "VORTEX_HOME:     %s\n" "${VORTEX_HOME:-<not set>}"
printf "CORE_V_VERIF:    %s\n" "${CORE_V_VERIF_HOME:-<not set>}"
printf "RISCV:           %s\n" "${RISCV:-<not set>}"
printf "VERILATOR_ROOT:  %s\n" "${VERILATOR_ROOT:-<not set>}"
echo
echo "Tool availability:"
which vsim 2>/dev/null || echo "vsim  : not found"
which verilator 2>/dev/null || echo "verilator : not found"
which ${CV_SW_PREFIX}gcc 2>/dev/null || which riscv32-unknown-elf-gcc 2>/dev/null || echo "${CV_SW_PREFIX}gcc : not found"
echo "============================"
