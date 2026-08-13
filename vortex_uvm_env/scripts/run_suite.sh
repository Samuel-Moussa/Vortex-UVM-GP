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
FAILED=0
# stage <make-rc>: A5 — the make exit code IS the run verdict now (simulate.sh
# propagates it: 0=PASSED, 1=UVM fail, 2=RTL assertion fail, 3=unknown). Only
# passing runs get their UCDB staged for the coverage merge; a failing run's
# coverage must not enter a sign-off bank.
stage()  {
  local rc="${1:-0}"
  if [ "$rc" -ne 0 ]; then
    # make normalizes any recipe failure to rc=2, so classify from the transcript:
    # RTL-assert failures leave "# ** Error:" lines; anything else is UVM/verdict.
    local why="UVM/verdict"
    grep -q "^# \*\* Error" results/latest/logs/simulation.log 2>/dev/null && why="RTL assertion"
    echo "  -> FAILED ($why) — UCDB NOT staged"
    grep -m1 "^# \*\* Error" results/latest/logs/simulation.log 2>/dev/null | sed 's/^/     /'
    FAILED=$((FAILED+1))
  elif [ -f results/latest/reports/coverage.ucdb ]; then
    echo "  -> $(grep -m1 -E 'Test Result|TEST PASSED|TEST FAILED' results/latest/logs/simulation.log 2>/dev/null) [UCDB ok]"
    RUNS+=( "$(relrun)" )
  else
    echo "  -> NO UCDB (failed/aborted, skipped)"
  fi
}
runk() { echo "=== $1 kernel $2 ==="; make "$1" TEST=kernel_launch_test PROGRAM_NAME="$2" $CFG TIMEOUT="$3" >"$LOGDIR/k_$2.log" 2>&1; stage $?; }
# runthr: same as runk but with the AXI slave ready-throttle enabled (+AXI_THROTTLE) to
# exercise the AXI backpressure stability assertions + downstream stall branches.
runthr() { echo "=== throttled kernel $1 ==="; AXI_THROTTLE=1 make sim-only TEST=kernel_launch_test PROGRAM_NAME="$1" $CFG TIMEOUT="$2" >"$LOGDIR/k_thr_$1.log" 2>&1; stage $?; }
# runflood: AXI slave streams read responses back-to-back (+AXI_FLOOD) -> forces DUT
# rready backpressure to exercise assert_r_valid_stable / assert_r_data_stable.
runflood() { echo "=== flood kernel $1 ==="; AXI_FLOOD=1 make sim-only TEST=kernel_launch_test PROGRAM_NAME="$1" $CFG TIMEOUT="$2" >"$LOGDIR/k_flood_$1.log" 2>&1; stage $?; }
rund() { echo "=== sim-only $1 ($2) ==="; make sim-only TEST="$1" PROGRAM_NAME="$2" $CFG TIMEOUT="$3" >"$LOGDIR/d_$1.log" 2>&1; stage $?; }
# riscv-dv regenerates the generator into a shared work dir guarded by a Questa
# _lock. A killed/crashed prior gen can leave a STALE lock (dead owner pid) that
# makes the next gen wait ~16 min then fail. Clear it if its owner is dead.
clear_stale_dv_lock(){
  local L="${RISCV_DV_HOME:-$HOME/riscv-dv}/work/_lock"
  [ -f "$L" ] || return 0
  local p; p=$(grep -oE 'pid = [0-9]+' "$L" 2>/dev/null | grep -oE '[0-9]+')
  if [ -n "$p" ] && ! ps -p "$p" >/dev/null 2>&1; then
    echo "  (clearing stale riscv-dv vlog lock, dead owner pid=$p)"; rm -f "$L"
  fi
}
runrv(){ echo "=== sim-only riscv-dv $1 ==="; clear_stale_dv_lock; make sim-only TEST=random_instruction_stress_test PROGRAM="$1" RISCV_DV_REGEN=1 $CFG TIMEOUT=600000 >"$LOGDIR/rv_$1.log" 2>&1; stage $?; }
# regression (Ahmad's MSCRATCH kernel-launch harness): basic verifies DUT-vs-SimX;
# diverge/sgemm/dogfood run-to-completion co-sim but classify UNVERIFIABLE (spawn).
runr()  { echo "=== sim-only regression PROGRAM_KIND=$1 ==="; make sim-only TEST=regression_test PROGRAM_KIND="$1" ${2:-} $CFG TIMEOUT=10000000 >"$LOGDIR/r_$1.log" 2>&1; stage $?; }

# ---- BUDGET POLICY (raised 2026-08-13) --------------------------------------
# Every TIMEOUT below is >=3x the MEASURED cycle count at 2CL (the slower of our
# two configs). Rationale, learned the hard way twice:
#   * TIMEOUT is a FAILSAFE CAP, not a run length. A passing test exits on
#     program completion (busy deassertion, OBS-024) long before the cap, so
#     raising a budget costs nothing unless a test genuinely hangs. There is no
#     trade-off to tune here - an under-set budget is pure downside.
#   * A timeout is staged as a FAILURE (`stage $?` stages only passing runs), so
#     it silently drops the run from the coverage bank AND masks whatever is
#     underneath it. In the 2026-08-12 2CL suite, barrier_sync_test timed out at
#     149,999/150,000 and riscv_rand_instr_test at 199,999/200,000 - both within
#     a rounding error of their cap - and each was hiding a real divergence
#     (OBS-026, OBS-027) that only surfaced once the budget was raised.
# When adding a test: measure it at the SLOWEST config you support, then set 3x.
# Do not trim a budget toward the measured value to "save time" - it saves none.
# ---- kernels (first does full compile) ----
runk sim      hello           100000
for k in vecadd_lite diverge_lite diverge_deep diverge_peel diverge_fpu fpu_test fpu_mt spawn_tmc_sweep barrier_lite fibonacci; do
  runk sim-only "$k" 200000
done
# text_big: large resident .text so executed PC crosses into cp_pc_region.text_high
# (fills cross_pc_cycles <text_high,med>/<text_high,short>). Bigger timeout for the sweep.
# BUDGET: measured 490,468 cycles / 56,537 instructions to completion (2026-08-07). The old
# 400000 was 23% short, so the run was truncated mid-execution and reported as a TIMEOUT +
# assert_busy_eventually_idles failure — NOT a hang: retired instructions and mem ops were
# still climbing monotonically with busy=1 at cycle 399,999 (the INV-1 signature). This kernel
# is fetch-bound by design (232KB resident .text, 600 noinline fns, runtime-indexed reverse
# sweep) and retires at ~0.12 IPC, so it is the most cache-configuration-sensitive test we
# have — keep generous headroom rather than trimming to the measured value.
runk sim-only text_big 1600000
# mem_stress: co-activates memory-request backpressure with med/low-IPC windows and
# a dependent IDIV chain -> fills cross_ipc_stalls <med_ipc,*,mem-stalled> /
# <med_ipc,fetch-stalled,*>. Completes ~290k cycles; 400k timeout for headroom.
runk sim-only mem_stress 900000
# sfu_masks: register-form csrrw (fsrm) + csrrc on FP CSRs under peeled thread masks
# -> fills cross_sfu_threads <csrrw|csrrc, {uniform,partial[2],partial[3]}> (CSR-WRITE
# ops otherwise fire only single-threaded from crt0). Fast (~32k cyc), deterministic.
runk sim-only sfu_masks 200000
# bar_masks: single-warp kernel issuing vx_barrier(id,1) under peeled thread masks ->
# fills cross_sfu_threads <bar,{uniform,partial[2],partial[3]}>. num_warps=1 self-releases
# so a barrier under a divergent mask cannot deadlock. Fast (~9k cyc), deterministic.
runk sim-only bar_masks 200000
# diverge_uni3: three nested ASYMMETRIC real divergences (3v1->2v1->1v1) push the IPDOM
# stack to depth 3 with one thread active, then a 4th data-dependent branch fires with a
# single active thread (is_dvg=0) -> fills cross_dvg_depth <uniform,d3>. Fast, deterministic.
runk sim-only diverge_uni3 200000
# cache_stress: 600-function resident .text swept by runtime index (icache miss -> fetch_stall)
# INTERLEAVED with a compute-free independent-load burst (dcache backpressure -> memory_stall)
# -> fills cross_ipc_stalls <*,fetch-stalled,mem-stalled> (both caches stalled at once).
runk sim-only cache_stress 1600000
# mem_zero: compute-free 128-block independent-load saturation -> zero/very-low-IPC windows
# co-sampled with mem/fetch stalls (cross_ipc_stalls <zero|very_low,*,stalled> family).
runk sim-only mem_zero 1000000
# axi_edge: minimal store-and-exit (x=5). Short run makes the idle<->busy transitions
# dominate; best-effort stimulus for system_axi_cross edge tuples (system_cg samples every
# cycle). Note: empirically the AXI beats do not land on the busy toggle (pipeline gap +
# busy=~no_pending keeps AXI in the busy state) -> documents that gap; cheap fast run.
runk sim-only axi_edge 50000
# tcu_test: single warp-collective WMMA (INST_TCU_WMMA) -> exercises + VERIFIES the Tensor
# Core Unit (VX_tcu_unit + BHF bf16 datapath) vs SimX's tensor_unit. Requires the SimX DPI
# built with -DEXT_TCU_ENABLE (prepare.sh) and the probe built with global +define+
# EXT_TCU_ENABLE (compile.sh) so instr_class_cg_tcu samples. A=1.0,B=2.0,C=0 -> exact
# integer output -> byte-exact compare. Fills instr_class_cg_tcu <uniform>.
runk sim-only tcu_test 200000
# tcu_mt: one warp-collective WMMA per warp (total = NUM_THREADS*NUM_WARPS flat grid)
# -> spreads INST_TCU_WMMA across all warps, filling instr_class_cg_tcu cp_warp bins
# (tcu_test single-warp only hit one wis). Deterministic exact int result per tile.
runk sim-only tcu_mt 200000
# vote_shfl: warp-collective VOTE (vx_vote_all/any/uni/ballot) + SHFL (vx_shfl_up/down/
# bfly/idx) custom-0 ops -> the ONLY source of ALU_TYPE_OTHER (VX_alu_int.sv:193
# `xtype==3`), the last uncovered ALU condition term. Multi-core-aware, printf-free,
# deterministic -> byte-exact vs SimX. Closes the 4 xtype lane conditions.
runk sim-only vote_shfl 200000
# wide_stress: 256KB sparse working set (1 word/64B line across the span) with 8
# complementary high-entropy patterns -> flips DATA-address high bits far beyond the
# 32KB toggle_stress (real toggle gain: aggregate 77.99->78.61%). Multi-core, byte-exact.
runk sim-only wide_stress 40000000
# AXI backpressure: vecadd_lite under slave ready wait-states -> covers the AXI
# aw/w/ar stability assertions (assert_*_stable) + backpressure branches. Byte-exact
# (throttle only delays ready; data preserved). Assertions 84.78->93.07%.
runthr vecadd_lite 2000000
# div_edge: raw div/rem/divu/remu at every ISA corner (div-by-0, INT_MIN/-1, sign combos)
# -> covers VX_serial_div corner branches. Byte-exact (corners ISA-defined).
runk sim-only div_edge 2000000
# AXI read-flood: mem_stress (12-load bursts) with the slave streaming R back-to-back
# (+AXI_FLOOD) -> DUT deasserts rready -> assert_r_valid/r_data_stable. Byte-exact.
runflood mem_stress 4000000
# ---- directed tests ----
rund axi_memory_test        axi_traffic     400000
rund functional_memory_test functional_mem  400000
rund warp_scheduling_test   warp_test       400000
rund barrier_sync_test      barrier_test    500000
rund host_coverage_test     vecadd_lite     200000   # DCR/host coverage sweep (dcr_config_cg)
# ---- regression kernel-launch harness (Ahmad) ----
runr basic
runr diverge
runr sgemm
runr dogfood "DOGFOOD_TESTID=4"
# ---- riscv-dv: ALL profiles (many privileged/trap ones get skipped — see
#      HANDOVER_Ahmad_coverage_pushup.md "riscv-dv profile status" for why) ----
# riscv-dv list curated to tests that are VALID and runnable on rv32im Vortex.
# EXCLUDED (root-caused 2026-07-02, not DUT bugs — see HANDOVER_Steven_simx_review):
#   riscv_mem_region_stress_test : not defined in any riscv-dv testlist (gen "Cannot find")
#   riscv_csr_test               : in base testlist only, NOT rv32im (needs privileged CSRs)
#   riscv_instr_base_test        : abstract base class, not a standalone runnable test
#   riscv_ebreak_debug_mode_test : uses RISC-V debug mode (dret/dcsr) unimplemented in Vortex
#   riscv_hint_instr_test        : riscv-dv generator emits no asm ("Generated assembly not found")
#   riscv_ebreak_test            : ebreak-heavy program keeps a warp busy after ebreak so the
#                                  completion (busy=0) never idles -> harness timeout (DUT DOES
#                                  reach ebreak: STATUS ebreak:1 sampled 5525x). Needs stress-vseq
#                                  completion rework; parked.
#   riscv_illegal_instr_test     : EXCLUDED 2026-07-16 (INV-4/A5). Its purpose is illegal-
#                                  instruction TRAP verification; Vortex has no trap architecture
#                                  (OBS-013): deliberately-illegal SYSTEM encodings
#                                  (.4byte # kIllegalSystemInstr) decode as bogus-CSR ops and fire
#                                  the invalid-CSR RUNTIME_ASSERT (VX_csr_data.sv:150, e.g. 0x6f3/
#                                  0xca2) -> honest FAILED under the A5 gate; SimX aborts on them
#                                  too (UNVERIFIABLE). Zero verifiable intent on this DUT.
# JALR-DERAIL FIX (2026-07-16, INV-4): riscv-dv deliberately generates jalr targets = label+1
# (riscv_directed_instr_lib.sv "JALR is expected to set lsb to 0"). Vortex does NOT clear the
# jalr LSB (OBS-012) -> odd architectural PC -> auipc-derived addresses skewed -> misaligned
# data accesses (all 12 profiles fired the LSU RUNTIME_ASSERT; OBS-013 silent corruption).
# Patched LOCALLY in ~/riscv-dv (offset -> 0, marked "VORTEX LOCAL PATCH (INV-4)"); regen
# (RISCV_DV_REGEN=1, already set) picks it up. Revert the patch if the RTL ever implements & ~1.
# MISALIGNED FIX (2026-07-03): Vortex HW does not support misaligned accesses
# (VX_lsu_slice.sv "memory misalignment not supported!"; halfword byte-enable drops
# addr bit 0; RUNTIME_ASSERT on alignment — confirmed vs upstream master). riscv-dv's
# rv32im target was wrongly set support_unaligned_load_store=1, so it generated
# misaligned accesses -> asserts. Fixed at the source:
# riscv-dv/target/rv32im/riscv_core_setting.sv support_unaligned_load_store=1'b0.
# CORRECTION (2026-07-16, INV-4): riscv_unaligned_load_store_test does NOT become a
# normal aligned test under that setting — its base_testlist gen_opts force
# +enable_unaligned_load_store=1 (7020 LSU asserts even after the jalr fix). Its
# purpose (verify unaligned-data support) is unimplementable on Vortex (OBS-013)
# -> EXCLUDED, same class as riscv_illegal_instr_test.
# NOTE: several RETAINED tests pass on liveness but are UNVERIFIABLE (SimX golden model aborts on
# some random sequences — Steven's SimX-robustness lane); they run the DUT to EBREAK cleanly.
# FW-1b (2026-08-13): riscv_pmp_test REMOVED — it is not a distinct test.
# It generated a program BYTE-IDENTICAL to riscv_non_compressed_instr_test
# (both .S md5 16be14c6ebe6). Both testlist entries delegate to
# `gen_test: riscv_rand_instr_test` and differ only by gen_opts that are INERT
# at --target=rv32im: +disable_compressed_instr=1 is vacuous (rv32im has no C
# extension — measured 0 compressed instructions) and the PMP options produced
# 0 pmpcfg/pmpaddr writes (and prepare.sh seds M-mode CSR writes away anyway).
# So the suite was counting 2 results where there was 1 program, and NEITHER
# tested the feature its name claims. Keeping it inflated the pass count and
# double-counted its 2CL failure as two divergences.
# Verified by md5-ing all 10 generated programs: this is the ONLY duplicate
# pair; the other 8 are distinct. Suite is now 44 DISTINCT programs.
# Do not re-add without making the gen_opts effective on a target that
# implements the feature.
for P in riscv_arithmetic_basic_test riscv_jump_stress_test \
         riscv_non_compressed_instr_test riscv_loop_test riscv_rand_instr_test \
         riscv_rand_jump_test riscv_mmu_stress_test riscv_no_fence_test \
         riscv_full_interrupt_test; do
  runrv "$P"
done

echo "=== SUITE VERDICT: ${#RUNS[@]} staged, $FAILED FAILED ==="
echo "=== MERGING ${#RUNS[@]} runs ==="; printf '  %s\n' "${RUNS[@]}"
# The exclusion generator is CONFIG-KEYED (gen_coverage_exclude.sh NCL NC NW NT),
# but merge_coverage.sh reads the config from COV_* env vars that default to
# 1/1/4/4 (merge_coverage.sh:48). Without this export a 2CL suite would be banked
# with 1CL exclusions -- e.g. the single-core `is_global` barrier waiver applied to
# a build where that barrier IS reachable. Pass through the config we actually ran.
export COV_NCL="$CLUSTERS" COV_NC="$CORES" COV_NW="$WARPS" COV_NT="$THREADS"
bash scripts/merge_coverage.sh --fresh   >"$LOGDIR/merge.log" 2>&1
bash scripts/merge_coverage.sh --collect "${RUNS[@]}" >>"$LOGDIR/merge.log" 2>&1
echo "=== DONE — combined coverage: ==="
vcover report -summary cov/merged.ucdb 2>/dev/null | grep -iE "Covergroup Bins|filtered|Instances"
