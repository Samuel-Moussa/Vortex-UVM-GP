#!/bin/bash
# lockstep_sweep_2cl.sh — Phase-A closing sweep: run the DETERMINISTIC directed
# kernels under per-instruction lockstep (DUT commit stream vs SimX golden) at
# 2CL/2C/4W/4T and bucket each into { lane-exact | OBS-009 race class }.
#
# This is a CHECKING-DEPTH validation, NOT a coverage bank — it does NOT merge any
# UCDB and does NOT touch run_suite.sh. Purpose: prove the lockstep comparator
# aligns DUT<->SimX 1:1 across TWO clusters (cid routing, OBS-006) on well-behaved
# programs, and classify any residual divergence honestly.
#
# Usage (from anywhere):
#   scripts/lockstep_sweep_2cl.sh tier1        # 15 deterministic kernels
#   scripts/lockstep_sweep_2cl.sh tier2        # 5 memory-heavy (+ load-feed classify)
#   scripts/lockstep_sweep_2cl.sh all
#
# Config is PINNED to 2CL/2C/4W/4T (the sweep's whole point). Work lib must already
# be compiled at that config (make sim-only, no recompile). If a run trips the
# I2 topology $fatal, the lib is at the wrong config — recompile first.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENV_ROOT" || exit 1

CFG="CLUSTERS=2 CORES=2 WARPS=4 THREADS=4"
LOGDIR="${ENV_ROOT}/results/lockstep_sweep_2cl"; mkdir -p "$LOGDIR"
TIER="${1:-tier1}"

# Tier-1: disjoint per-thread outputs, no cross-core shared reads -> expect lane-exact.
TIER1=( vecadd_lite diverge_lite diverge_deep diverge_peel diverge_fpu diverge_uni3 \
        fpu_test fpu_mt tcu_test tcu_mt vote_shfl div_edge spawn_tmc_sweep bar_masks sfu_masks )
# Tier-2: memory-heavy -> may read another core's racy write (OBS-009). Load-feed classifies.
TIER2=( mem_stress cache_stress mem_zero wide_stress text_big )

# per-kernel timeout (cycles) — mirror run_suite.sh values; big ones get headroom
timeout_for() {
  case "$1" in
    wide_stress) echo 40000000 ;;
    cache_stress) echo 600000 ;;
    mem_stress|mem_zero|text_big) echo 400000 ;;
    div_edge) echo 2000000 ;;
    *) echo 200000 ;;
  esac
}

# extract the A0 LOCKSTEP SUMMARY numbers from a captured run log
summarize() {  # <log>
  local L="$1"
  local cmp mat pc rd da lo verdict
  cmp=$(grep -oE 'compared pairs +: [0-9]+' "$L" | grep -oE '[0-9]+$' | tail -1)
  mat=$(grep -oE 'matched +: [0-9]+' "$L" | grep -oE '[0-9]+$' | tail -1)
  pc=$(grep -oE 'field_mismatch PC +: [0-9]+' "$L" | grep -oE '[0-9]+$' | tail -1)
  rd=$(grep -oE 'field_mismatch rd +: [0-9]+' "$L" | grep -oE '[0-9]+$' | tail -1)
  da=$(grep -oE 'field_mismatch data +: [0-9]+' "$L" | grep -oE '[0-9]+$' | tail -1)
  lo=$(grep -oE 'field_mismatch LOAD +: [0-9]+' "$L" | grep -oE '[0-9]+' | head -1)
  verdict=$(grep -m1 "VERDICT:" "$L" | sed 's/.*VERDICT: //')
  echo "    compared=$cmp matched=$mat  mm[PC=$pc rd=$rd data=$da LOAD=$lo]"
  [ -n "$verdict" ] && echo "    VERDICT: $verdict"
}

run_one() {  # <kernel> <loadfeed:0|1>
  local k="$1" feed="$2" to; to=$(timeout_for "$k")
  local log="$LOGDIR/${k}$([ "$feed" = 1 ] && echo _feed).log"
  echo "=== [$TIER] $k  (2CL, LOCKSTEP$([ "$feed" = 1 ] && echo +LOADFEED), timeout=$to) ==="
  local envs="LOCKSTEP=1"
  [ "$feed" = 1 ] && envs="$envs LOCKSTEP_LOADFEED=1"
  env $envs make sim-only TEST=kernel_launch_test PROGRAM_NAME="$k" $CFG TIMEOUT="$to" \
      >"$log" 2>&1
  local rc=$?
  # make rc: 0=PASSED, !=0 -> classify (make normalizes to 2)
  if grep -q "A0 LOCKSTEP SUMMARY" "$log"; then
    summarize "$log"
  else
    echo "    !! no lockstep summary — run aborted/timed out (make rc=$rc)"
    grep -m1 "^# \*\* Error\|Fatal\|I2-ASSERT" "$log" | sed 's/^/    /'
  fi
  # LOCKSTEP uvm_error -> non-zero verdict; report it explicitly
  if [ "$rc" -ne 0 ]; then echo "    make rc=$rc (verdict RED — see VERDICT line above)"; fi
  echo ""
}

echo "########## 2CL DIRECTED-SUITE LOCKSTEP SWEEP ($TIER) ##########"
case "$TIER" in
  tier1) for k in "${TIER1[@]}"; do run_one "$k" 0; done ;;
  tier2) for k in "${TIER2[@]}"; do run_one "$k" 0; done ;;
  all)   for k in "${TIER1[@]}"; do run_one "$k" 0; done
         for k in "${TIER2[@]}"; do run_one "$k" 0; done ;;
  *) echo "unknown tier '$TIER' (use tier1|tier2|all)"; exit 1 ;;
esac
echo "########## SWEEP DONE ($TIER) — logs in $LOGDIR ##########"
