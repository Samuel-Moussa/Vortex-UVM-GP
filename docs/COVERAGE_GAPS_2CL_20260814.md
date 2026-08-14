# 2CL COVERAGE BANK — 2026-08-14 — RESULT, AND THE QUANTIFIED COST OF CORE-GATING

**Config:** 2CL / 2C / 4W / 4T RV32 AXI (scale point) · **44 distinct programs, 44 staged, 0 FAILED**
**Bank:** `vortex_uvm_env/cov/bank_2CL_2C_4W_4T/`
**Stale predecessor preserved as:** `cov/bank_2CL_2C_4W_4T_stale_20260710/` (85.16%, never quote it)
**Companion:** `docs/COVERAGE_GAPS_1CL_20260813.md` — ⚠ never blend the two UCDBs.

## 🏆 FIRST CLEAN 2CL SWEEP — 44/44, ZERO FAILURES

The previous attempt (2026-08-12) was **37/45 staged with 8 FAILED**. All 8 are now resolved, and
**none was a DUT defect**.

| category | bins | hits | misses | 2CL | (1CL for reference) |
|---|---|---|---|---|---|
| Assertions | 356 | 351 | 5 | **98.59%** | 96.09% |
| Branches | 10103 | 9045 | 1058 | 89.52% | 91.06% |
| Conditions | 1180 | 828 | 352 | **70.16%** | 76.03% |
| Covergroup bins | 1095 | 944 | **151** | 86.21% (92.11% weighted) | 98.75% |
| Directives | 5 | 5 | 0 | 100.00% | 100.00% |
| Statements | 15284 | 14708 | 576 | 96.23% | 96.82% |
| Toggles | 1249698 | 927655 | 322043 | 74.23% | 78.42% |
| **Total** | | | | **88.69%** | 91.08% |

Instances **8275** (vs 2256 at 1CL — per-core probe instance inflation, expected and why a
cross-config merge is invalid). Exclusions applied cleanly: **0 "had no effect"** — the first real
exercise of the repaired guard (`04db8fd`) at a NON-DEFAULT config, where a stale exclusion would
actually have mattered.

**Assertions are BETTER at 2CL (98.59% vs 96.09%)** — more cores generate more AXI traffic, so
backpressure corners that never fire at 1CL do fire here.

## ⭐ THE FOUR "EXPECTED" 2CL FAILURES WERE ONE METHODOLOGY BUG

| test | 2026-08-12 | 2026-08-14 | words compared |
|---|---|---|---|
| `riscv_no_fence_test` | FAILED — "documented, do not fix" | **PASSED**, 0 mismatches | 556 |
| `riscv_full_interrupt_test` | FAILED — "documented, do not fix" | **PASSED**, 0 mismatches | 787 |
| `riscv_mmu_stress_test` | FAILED (OBS-009 class) | **PASSED**, 0 mismatches | 729 |
| `riscv_non_compressed_instr_test` | FAILED (OBS-009 class) | **PASSED**, 0 mismatches | 787 |

All with substantial non-zero `data_compared` ⇒ real compares, not vacuous passes.

**This falsifies the plan's own guidance**, which read *"EXPECT AT BEST 43/45 — never 45/45 at 2CL"*
and explicitly instructed **not** to "fix" the first two. The single cause of all four was OBS-027:
riscv-dv emits a **single-hart** program and Vortex ran it on **every core** against the same
`.data` with no fences, so store ORDER decided the values and the RTL ordered them differently from
SimX. Core-gating (`3d0ec30`) removed the mechanism and all four became defined and correct.

**What `docs/investigations/SimX_2CL_no_fence_divergence.md` got right and wrong:** it identified
the MECHANISM correctly — unsynchronised cross-core memory ordering in a fenceless program,
resolved differently by functional SimX than by the timing-accurate RTL. Its DISPOSITION was wrong:
it concluded the divergence was inherent and filed it permanently UNVERIFIABLE at multi-cluster. The
question it stopped one step short of asking was whether the program was ever **intended** to run on
more than one hart. It was not. ⇒ **OBS-009's scope shrinks: its riscv-dv members are RESOLVED, not
unverifiable.** The weak-coherency reasoning remains valid for genuinely multi-core fenceless
kernels — it was simply never what these tests were.

## THE 151 MISSING COVERGROUP BINS — WHERE THEY ACTUALLY ARE

Measured from the bank's own `report/functional.txt`.

### 84 bins (56%) = THE MEASURED COST OF CORE-GATING

| instance | missing instr_probe bins |
|---|---|
| `cluster0_core0` | **0** |
| `cluster0_core1` | 28 |
| `cluster1_core0` | 28 |
| `cluster1_core1` | 28 |

**Global core 0 is complete; the other three are each missing exactly 28.** Core-gating means only
core 0 executes riscv-dv (9 tests) and `barrier_test`, so the other cores' instruction-mix
covergroups — `alu_class_cg.cp_alu_op`, `sfu_class_cg.cross_sfu_threads`, `tcu_class_cg.cp_warp`,
`lsu_class_cg.cp_lsu_op`, `fpu_class_cg.cp_active_threads` — never see that instruction variety.

**This is a real trade, honestly made.** Before the fix those cores were running the SAME program
against the SAME shared data with no synchronisation, so their coverage was purchased with
architecturally UNDEFINED results. Defined-but-lower beats higher-but-meaningless. **The correct
recovery is not to un-gate — it is to add kernels that are genuinely multi-core.**

### 32 bins = AXI `cp_id_route` (32 missing of 45, 28.88% hit)

Routing-tag bins scale with config. At 1CL the unreachable ones are config-waived by
`gen_coverage_exclude.sh`; at 2CL more tags are architecturally reachable and our stimulus does not
drive them. Needs an outstanding-transaction stress sized for 2CL, or a config-aware waiver PROVEN
per-config (do not waive without RTL proof — see the `cp_id_route` precedent, commit `0cfec34`).

### ~35 bins = the remainder
`cross_type_route` (same cause as `cp_id_route`), `cp_mshr_stall.stall` ×4 (icache+dcache × 2
clusters — same genuine gap as 1CL), `mem_usage_cp` / `system_mem_cross` (weight-0 red herrings,
MEM interface idle on AXI runs), `tcu_class_cg.cp_warp`, `divergence_cg.cross_dvg_depth`.

## ORDERED PLAN TO PUSH 2CL COVERAGE

1. **Multi-core kernels with PER-CORE data regions** (index `vx_core_id()*nw + wid`, size by
   `NUM_CORES*NUM_WARPS`). Recovers the 84 bins **legitimately** — every core doing real, defined,
   synchronised work instead of racing on one shared array. Also the single largest remaining
   verification gap in the project: nothing currently exercises multiple cores against shared data
   with correct synchronisation. Addresses FW-3 and FW-7.
2. **AXI route bins at 2CL** (~32+): outstanding-transaction stress sized for the 2CL tag space, or
   a per-config waiver proven from the RTL.
3. **`cp_mshr_stall.stall`** ×4 — see the 1CL doc for the exact stimulus each needs.
4. **Conditions 70.16%** — lowest category, so the biggest lever on Questa's unweighted 7-category
   mean. Even less explored at 2CL than at 1CL.
5. **Stop at toggles (74.23%)** — structural, same root cause as 1CL (write-through leaves the
   512-bit write-data fields undriven).

## CLAIM DISCIPLINE

Defensible from this bank: *"44 distinct programs pass at both 1CL and 2CL with byte-exact
end-state equivalence against an independent-ish golden model; 91.08% / 88.69% total coverage;
first clean multi-cluster sweep."*
**NOT defensible:** *"the design is verified"* or *"we stressed the design"* — FW-1 (1 seed per
profile), FW-4 (exception axis absent), FW-7 (no soak) all still stand, and multi-core stimulus is
now WEAKER than before by design (see the 84 bins above) until item 1 is built.
