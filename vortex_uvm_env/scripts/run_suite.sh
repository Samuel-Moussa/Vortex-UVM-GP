#!/bin/bash
# run_suite.sh — run the full functional suite at one config, then merge coverage.
#
#   Kernels (kernel_launch_test) + directed tests + ALL riscv-dv profiles, all at the
#   selected config, then rebuild the combined coverage report. Compiles once, then
#   sim-only per test for speed. Robust: a test that fails/aborts is skipped (only
#   runs that produced a UCDB are merged).
#
# Usage (from anywhere):
#   scripts/run_suite.sh                     # default 1CL/1C/4W/4T
#   CLUSTERS=2 CORES=2 WARPS=4 THREADS=4 scripts/run_suite.sh
#
# Config policy: keep WARPS>=2 and THREADS>=2 (TCU needs >=2; do not disable TCU).
# Cross-config note: do NOT blend different configs into one UCDB — report per-config
# (per-core probes inflate the BY-INSTANCE denominator; widths conflict).
set -u

# --- locate the UVM env root relative to this script (portable for all teammates) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENV_ROOT" || exit 1

CLUSTERS="${CLUSTERS:-1}"; CORES="${CORES:-1}"; WARPS="${WARPS:-4}"; THREADS="${THREADS:-4}"
CFG="CLUSTERS=$CLUSTERS CORES=$CORES WARPS=$WARPS THREADS=$THREADS"
LOGDIR="${ENV_ROOT}/results/run_suite_logs"; mkdir -p "$LOGDIR"
RUNS=()
echo "### run_suite.sh @ ${CLUSTERS}CL/${CORES}C/${WARPS}W/${THREADS}T"

relrun() { local p; p=$(readlink -f results/latest); echo "$(basename "$(dirname "$p")")/$(basename "$p")"; }
stage()  {
  if [ -f results/latest/reports/coverage.ucdb ]; then
    echo "  -> $(grep -m1 -E 'Test Result|TEST PASSED|TEST FAILED' results/latest/logs/simulation.log 2>/dev/null) [UCDB ok]"
    RUNS+=( "$(relrun)" )
  else
    echo "  -> NO UCDB (failed/aborted, skipped)"
  fi
}
runk() { echo "=== $1 kernel $2 ==="; make "$1" TEST=kernel_launch_test PROGRAM_NAME="$2" $CFG TIMEOUT="$3" >"$LOGDIR/k_$2.log" 2>&1; stage; }
rund() { echo "=== sim-only $1 ($2) ==="; make sim-only TEST="$1" PROGRAM_NAME="$2" $CFG TIMEOUT="$3" >"$LOGDIR/d_$1.log" 2>&1; stage; }
runrv(){ echo "=== sim-only riscv-dv $1 ==="; make sim-only TEST=random_instruction_stress_test PROGRAM="$1" RISCV_DV_REGEN=1 $CFG TIMEOUT=200000 >"$LOGDIR/rv_$1.log" 2>&1; stage; }
# regression (Ahmad's MSCRATCH kernel-launch harness): basic verifies DUT-vs-SimX;
# diverge/sgemm/dogfood run-to-completion co-sim but classify UNVERIFIABLE (spawn).
runr()  { echo "=== sim-only regression PROGRAM_KIND=$1 ==="; make sim-only TEST=regression_test PROGRAM_KIND="$1" ${2:-} $CFG TIMEOUT=10000000 >"$LOGDIR/r_$1.log" 2>&1; stage; }

# ---- kernels (first does full compile) ----
runk sim      hello           100000
for k in vecadd_lite diverge_lite fpu_test fpu_mt spawn_tmc_sweep barrier_lite fibonacci; do
  runk sim-only "$k" 200000
done
# ---- directed tests ----
rund axi_memory_test        axi_traffic     150000
rund functional_memory_test functional_mem  150000
rund warp_scheduling_test   warp_test       150000
rund barrier_sync_test      barrier_test    150000
# ---- regression kernel-launch harness (Ahmad) ----
runr basic
runr diverge
runr sgemm
runr dogfood "DOGFOOD_TESTID=4"
# ---- riscv-dv: ALL profiles (many privileged/trap ones get skipped — see
#      HANDOVER_Ahmad_coverage_pushup.md "riscv-dv profile status" for why) ----
for P in riscv_arithmetic_basic_test riscv_jump_stress_test riscv_unaligned_load_store_test \
         riscv_non_compressed_instr_test riscv_loop_test riscv_rand_instr_test \
         riscv_rand_jump_test riscv_mem_region_stress_test riscv_mmu_stress_test \
         riscv_no_fence_test riscv_illegal_instr_test riscv_full_interrupt_test \
         riscv_csr_test riscv_pmp_test riscv_hint_instr_test riscv_ebreak_test \
         riscv_ebreak_debug_mode_test riscv_instr_base_test; do
  runrv "$P"
done

echo "=== MERGING ${#RUNS[@]} runs ==="; printf '  %s\n' "${RUNS[@]}"
bash scripts/merge_coverage.sh --fresh   >"$LOGDIR/merge.log" 2>&1
bash scripts/merge_coverage.sh --collect "${RUNS[@]}" >>"$LOGDIR/merge.log" 2>&1
echo "=== DONE — combined coverage: ==="
vcover report -summary cov/merged.ucdb 2>/dev/null | grep -iE "Covergroup Bins|filtered|Instances"
