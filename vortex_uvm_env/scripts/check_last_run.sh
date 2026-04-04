#!/usr/bin/env bash
L="results/latest"

echo "=== SUMMARY ==="
cat "$L/reports/SUMMARY.txt"

echo ""
echo "=== UVM ERRORS / FATALS ==="
grep -n "UVM_ERROR /\|UVM_FATAL /" "$L/logs/simulation.log" || echo "(none)"

echo ""
echo "=== RTL ASSERTION ERRORS ==="
grep -n "^\# \*\* Error:" "$L/logs/simulation.log" || echo "(none)"

echo ""
echo "=== COMPILE ERRORS ==="
grep -n "^\*\* Error" "$L/logs/compile_rtl.log" \
                      "$L/logs/compile_uvm.log" 2>/dev/null || echo "(none)"

echo ""
echo "=== LAST 30 LINES OF SIM LOG ==="
tail -30 "$L/logs/simulation.log"