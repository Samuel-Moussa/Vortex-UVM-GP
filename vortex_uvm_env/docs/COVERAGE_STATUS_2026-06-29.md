# Coverage Status & Closure Plan — 2026-06-28 → 2026-06-29

Progress toward the goal of **100% functional coverage** and **≥95% code
coverage**. Numbers are from a controlled 12-UCDB merge (AXI config, single
tb_top/dut elaboration), third-party (cvfpu/ramulator) waived via
`scripts/coverage_exclude.do`.

**Fixes applied 2026-06-29:**
1. `ignore_bins` on `axi_transaction_cg` unreachable AXI bins → functional bins
   **12.17% → 37.51%** (§1b).
2. **Directed FPU kernel** (`fpu_test`, fix_18) → `instr_class_cg_fpu` **0% → 25%**
   AND lifted code coverage (FPU RTL exercised). Also surfaced a real DUT-vs-SimX
   FP divergence (1-ULP rounding + denormal FTZ).
3. `~/.bashrc` env fix so `make sim` works in tool/non-login shells.

**Latest merged totals (19 UCDBs, incl. fpu_test):** statements **94.29%**,
branches 86.83%, toggles 70.76%, functional bins **37.83%**, total **70.92%**.
riscv-dv is SATURATED (6 fresh seeds added 0 bins) — remaining functional gaps
need FP-multi-warp (INV-1), TCU/mem ignores, and DCR variety, not more riscv-dv.

---

## 1. Current numbers (12-test merge)

Merged set: 8 kernels (hello, vecadd, fibonacci, conform, axi_traffic,
functional_mem, warp_test, barrier_test) + 4 riscv-dv (arithmetic_basic,
jump_stress, unaligned_load_store, non_compressed_instr).

| Metric | 3-test baseline | **12-test** | Goal |
|---|---|---|---|
| **Total (filtered)** | 60.90% | **70.11%** | — |
| Statements | 92.58% | **93.43%** | ≥95% (close) |
| Branches | 78.18% | **86.32%** | high |
| Conditions | 37.51% | **64.08%** | high |
| Toggles | 54.91% | **69.88%** | ≥90% (waivers) |
| Assertions | 86.42% | 85.71% | — |
| Covergroups | 45.50% | 60.09% | 100% |
| **Covergroup bins (functional)** | 9.70% | **12.17%** (236/1938) | **100%** |

Consistent with Ahmad's earlier 8-run merge (~70%).

---

## 1b. Fix: ignore_bins on unreachable AXI bins (2026-06-29) — verified

**What:** Added `ignore_bins` to `axi_transaction_cg` (`vortex_coverage_collector.sv`)
for the AXI bins Vortex can never produce — its master emits **single-beat FIXED
bursts only** (VX_axi_adapter, RTL pin 7a52ee5):
- `cp_burst`: `ignore_bins` INCR, WRAP (only FIXED reachable)
- `cp_len`: `ignore_bins` `[1:255]` (only single-beat reachable)

These propagate through the crosses (`cross_type_burst_size`, `cross_type_len`,
`cross_len_addr`), removing ~1,300 unreachable bins. Flagged in-code for Ahmad's
review (coverage lane). Trip-wire noted: revert if VX_axi_adapter ever emits
multi-beat bursts.

**Result (same 12-test set, re-run + re-merge):**

| Metric | Before | **After** |
|---|---|---|
| Covergroup total bins | 1938 | **629** (−1309 unreachable) |
| Bins hit | 236 | 236 (unchanged) |
| **Functional bins %** | 12.17% | **37.51%** |
| Covergroups | 60.09% | 61.89% |
| Total (filtered) | 70.11% | 70.36% |

Honest gain — same hits, smaller *reachable* denominator. Code coverage unchanged
(ignore_bins only affects functional counting). The remaining 393 missing bins are
now **genuinely reachable** gaps, not noise.

**Remaining functional gaps (real, post-fix):** `cp_id_route` routing combos,
`cp_size`, `cp_bresp`/`cp_rresp0` variety (→ AXI stress seqs, Ahmad bucket-c),
instr_class alu/lsu/sfu breadth (→ more riscv-dv), **FPU class (real gap — FPU is
ENABLED, do NOT ignore)**, warp-state/divergence (**blocked by INV-1**).
Further legit ignores Ahmad may add: `cp_size` non-native sizes, `mem_usage_cp`
(AXI mode), `tcu_cg` (TCU disabled).

## 2. The dominant functional-coverage finding

**One covergroup is the ceiling.** `axi_transaction_cg` holds **1,699 of the
1,938** total functional bins, and most are **unreachable by construction**:
Vortex emits only single-beat FIXED bursts, fixed size (per Steven's AXI SVA
report), but the covergroup has full `cross_type_burst_size` / `cross_type_len` /
`cross_len_addr` crosses enumerating burst/size/len combinations the DUT can
never produce.

**Implication:** no amount of stimulus can reach 100% functional. The unlock is
**`ignore_bins`/`illegal_bins`** on the unreachable crosses (and the always-zero
`mem_usage_cp` in AXI mode, `instr_class_cg_fpu`/`_tcu` with no FPU/TCU,
64-bit-only bins). This shrinks the denominator to *reachable* bins, after which
the reachable set fills quickly. **Owner: Ahmad (covergroup definition).**

### Reachable covergroups (fillable by stimulus — partial today)
| Covergroup | Now | Needs |
|---|---|---|
| `dcr_write_cg` | 75% | a bit more DCR variety |
| `system_cg` | 78% (`mem_usage_cp` 0% = AXI mode → ignore) | — |
| `sched_state_cg` | 77% | multi-warp activity |
| `divergence_cg` / `reconverge_cg` | 15–34% | **divergent kernels (needs INV-1 fixed)** |
| `tmc_cg` / `wspawn_cg` | 25–60% | completing spawn kernels (INV-1) |
| `instr_class` alu/lsu/sfu | 57–78% | broader riscv-dv ISA |
| `instr_class` fpu/tcu | 0% | no FPU/TCU in config → ignore |
| `axi_transaction_cg` | 4.94% | ignore_bins (above) |

---

## 3. Sweep results (this session)

### Kernel sweep (8) — INV-1 pattern
| Result | Kernels | Note |
|---|---|---|
| ✅ PASS via ebreak | hello, fibonacci | single-threaded |
| ✗ TIMEOUT (INV-1) | vecadd, conform, axi_traffic, functional_mem, warp_test, barrier_test | all `vx_spawn_threads` (worker-warp hang) |

All 8 saved UCDBs (coverage collected regardless of verdict).

### riscv-dv sweep (12 profiles)
| Result | Profiles | Cause / owner |
|---|---|---|
| ✅ PASS | jump_stress | — |
| ran, UCDB_OK, UVM err | unaligned_load_store, non_compressed_instr | gave coverage |
| **SimX SIGABRT** | loop, no_fence | **Steven — SimX bug (these should be SimX-safe!)** |
| SimX abort (expected) | illegal_instr, full_interrupt, rand_instr | privileged/traps — inapplicable to SimX |
| DUT-internal asserts | rand_jump (68 RTL asserts on random jumps) | DUT behavior, not infra |
| gen failed | mem_region_stress, csr | not in rv32im testlist |
| no status | hint_instr | wrapper |

**Note:** `assert_dcr_write_timing` (INV-2) fires 2× at startup but is a
`$warning`, not an error — it does **not** fail tests.

---

## 4. Path to the goal — and what gates it

| Target | Status | Action | Owner |
|---|---|---|---|
| **Functional 100%** | 12% (capped by AXI cg) | **`ignore_bins` on `axi_transaction_cg` + zeros** ← the unlock | **Ahmad** |
| | | broader riscv-dv ISA → instr_class | Samuel |
| | | divergence/warp-state bins | **blocked by INV-1** (Steven) |
| **Statements ≥95%** | 93.43% | a little more stimulus + line exclusions | Samuel/Ahmad |
| **Branches** | 86.32% | stimulus breadth | Samuel |
| **Toggles ≥90%** | 69.88% | **documented waivers** (third-party + unreachable) | Ahmad |
| Conditions | 64.08% | stimulus + waivers | Ahmad |

**Critical dependencies:**
- **INV-1 (Steven)** — warp-state/divergence/spawn coverage needs *completing*
  multi-warp kernels. Until INV-1 is fixed, those covergroups can't close.
- **AXI `ignore_bins` (Ahmad)** — the single biggest functional-coverage move.

---

## 5. Handover asks

- **Ahmad:** (1) `ignore_bins`/`illegal_bins` on `axi_transaction_cg` unreachable
  crosses + always-zero coverpoints — biggest functional unlock; (2) toggle/line
  waivers for the code-coverage targets. (See also
  `HANDOVER_Ahmad_unused_axi_dcr_sequences.md` for stimulus to fill reachable AXI
  bins.)
- **Steven:** `riscv_loop_test` and `riscv_no_fence_test` SIGABRT SimX at
  `simx_run()` although the DUT completes — these are SimX-safe profiles, so it's
  a **real SimX bug**, not an inapplicable-profile case. Plus INV-1 (gates
  warp-state coverage). See `HANDOVER_Steven_kernel_execution.md`.

---

## 6. Reproduce
```bash
cd vortex_uvm_env
bash scripts/merge_coverage.sh --fresh
bash scripts/merge_coverage.sh --collect <results/<run> ...>   # one AXI-config set
# report: cov/report/{functional.txt,code.txt,html/index.html}
```
