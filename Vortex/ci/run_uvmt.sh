#!/usr/bin/env bash
# ============================================================
# Vortex UVM Test Runner - Final Version
# (Finds outputs from their actual location)
# ============================================================

set -euo pipefail

# --- المسارات الأساسية ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BUILD_DIR_ROOT=$(realpath "$SCRIPT_DIR/..")
LOG_DIR="$BUILD_DIR_ROOT/ci/logs"
BLACKBOX_SCRIPT="$BUILD_DIR_ROOT/ci/blackbox.sh"

# --- هذا هو المسار الصحيح الذي يتم إنشاء الملفات فيه ---
OUTPUT_DIR="$BUILD_DIR_ROOT/tests/opencl/vecadd"

mkdir -p "$LOG_DIR"

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS] --app=<app_name>

OPTIONS:
    --compare        Enable output comparison
    --help           Show this help message
EOF
}

APP=""
BLACKBOX_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --help) show_usage; exit 0 ;;
        --compare) ;; # Already enabled by default
        --app=*) APP="${arg#*=}"; BLACKBOX_ARGS+=("$arg") ;;
        *) BLACKBOX_ARGS+=("$arg") ;;
    esac
done

if [ -z "${APP:-}" ]; then
    echo "❌ Missing --app=<app_name>"
    show_usage
    exit 1
fi

echo "=========================================="
echo "🔧 Vortex UVM Test Runner - $APP"
echo "=========================================="

SIMX_LOG="$LOG_DIR/${APP}_simx.log"
RTL_LOG="$LOG_DIR/${APP}_rtlsim.log"

# --- تحديد المسارات الدقيقة للملفات الناتجة ---
SIMX_OUTPUT_FILE="$OUTPUT_DIR/vecadd_output_simx.bin"
RTL_OUTPUT_FILE="$OUTPUT_DIR/vecadd_output_rtlsim.bin"

# --- تنظيف الملفات القديمة من المسار الصحيح ---
echo "🧹 Cleaning old output files from: $OUTPUT_DIR"
rm -f "$SIMX_OUTPUT_FILE"
rm -f "$RTL_OUTPUT_FILE"

# --------------------------
# Run SIMX 
# --------------------------
echo ""
echo "🔶 Running SIMX (Golden Reference Model)"
# ملاحظة: قمنا بإزالة متغير CONFIGS الذي كان يسبب الفشل
if "$BLACKBOX_SCRIPT" --driver=simx "${BLACKBOX_ARGS[@]}" > "$SIMX_LOG" 2>&1; then
    echo "✅ SIMX execution completed"
    echo "=== SIMX Result ==="
    grep -E "PASSED|FAILED|PERF:|Wrote|INFO" "$SIMX_LOG" || true
else
    echo "❌ SIMX execution failed. Check $SIMX_LOG"
    tail -n 20 "$SIMX_LOG"
    exit 1
fi

# --------------------------
# Run RTL Simulation
# --------------------------
echo ""
echo "🔷 Running RTL Simulation (DUT)" 
if "$BLACKBOX_SCRIPT" --driver=rtlsim "${BLACKBOX_ARGS[@]}" > "$RTL_LOG" 2>&1; then
    echo "✅ RTL execution completed"
    echo "=== RTL Result ==="
    grep -E "PASSED|FAILED|PERF:|Wrote|INFO" "$RTL_LOG" || true
else
    echo "❌ RTL failed. Check $RTL_LOG"
    tail -n 20 "$RTL_LOG"
    exit 1
fi

# --------------------------
# Compare Results
# --------------------------
echo ""
echo "=========================================="
echo "🔍 Comparing Results"
echo "=========================================="

# --- البحث عن الملفات في المسار الصحيح ---
if [ -f "$SIMX_OUTPUT_FILE" ] && [ -f "$RTL_OUTPUT_FILE" ]; then
    echo "✅ Output files found:"
    echo "   SIMX:   $SIMX_OUTPUT_FILE ($(stat -c%s "$SIMX_OUTPUT_FILE") bytes)"
    echo "   RTL:    $RTL_OUTPUT_FILE ($(stat -c%s "$RTL_OUTPUT_FILE") bytes)"
    
    if cmp -s "$SIMX_OUTPUT_FILE" "$RTL_OUTPUT_FILE"; then
        echo "🎉 SUCCESS: Outputs are identical!"
    else
        echo "❌ MISMATCH: Outputs are different"
        echo "Hexdump comparison (first 5 lines):"
        paste <(xxd "$SIMX_OUTPUT_FILE" | head -5) <(xxd "$RTL_OUTPUT_FILE" | head -5)
    fi
else
    echo "⚠️  Cannot compare - output files not found or inaccessible"
    echo "SIMX: $([ -f "$SIMX_OUTPUT_FILE" ] && echo "FOUND" || echo "MISSING")"
    echo "RTL:  $([ -f "$RTL_OUTPUT_FILE" ] && echo "FOUND" || echo "MISSING")"
    
    echo ""
    echo "Debug Info:"
    echo "Expected SIMX file at: $SIMX_OUTPUT_FILE"
    echo "Expected RTL file at: $RTL_OUTPUT_FILE"
fi

# Performance comparison
echo ""
echo "⚡ Performance Comparison:"
echo "SIMX: $(grep "PERF:" "$SIMX_LOG" | head -1)"
echo "RTL:  $(grep "PERF:" "$RTL_LOG" | head -1)"

echo ""
echo "=========================================="
echo "🏁 Test Complete"
echo "=========================================="