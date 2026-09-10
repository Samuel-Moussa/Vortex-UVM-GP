# Post-scaling coverage re-run — both configs, 2026-08-15

Measures what the **device-sized kernel grids** (OBS-028/029 work: 7 kernels now size their grid
from `vx_num_cores()*vx_num_warps()*vx_num_threads()`, plus the per-config `kernel-config` rebuild
in `vortex_uvm_env/Makefile`) actually bought in coverage.

Both suites ran detached, **44 distinct programs each, 0 FAILED**. Nothing was skipped, nothing
failed, so there is no deferred-failure list.

| run | started | finished | verdict |
|---|---|---|---|
| 1CL/1C/4W/4T | 2026-08-15 04:50 | 05:44 | **44 staged, 0 FAILED** |
| 2CL/2C/4W/4T | 2026-08-15 05:45 | 08:15 | **44 staged, 0 FAILED** |

Banks (each verified by RE-READING the copy with `vcover report -summary`, not the source):
* `cov/bank_1CL_1C_4W_4T/` — new; previous bank preserved at `cov/bank_1CL_1C_4W_4T_prescale_20260814/`
* `cov/bank_2CL_2C_4W_4T/` — new; previous bank preserved at `cov/bank_2CL_2C_4W_4T_prescale_20260814/`
* Logs: `results/run_suite_logs_1CL_20260815/`, `results/run_suite_logs_2CL_20260815/` (each with `SUITE.log`)

---

## 1. Headline

### 1CL — the CONTROL (unchanged, by design)

| metric | pre-scaling | **post-scaling** | Δ |
|---|---|---|---|
| Total | 91.08% | **91.07%** | −0.01 |
| Covergroup bins | 398/403 = 98.75% | **398/403 = 98.75%** | 0 |
| Toggle | 78.42% | 78.39% | −0.03 |
| Instances | 2256 | 2256 | 0 |

At 1 cluster / 1 core, `vx_num_cores()*vx_num_warps()*vx_num_threads()` evaluates to **the same
`total` the hardcoded constant used**, so the scaled kernels emit near-identical stimulus. The
−0.03% toggle is `wide_stress` walking a slightly different address pattern.

**This is the point of running 1CL at all:** it establishes that the scaling changed nothing it
should not have, which is what makes the 2CL delta attributable to the scaling rather than to
incidental churn.

### 2CL — every category improved

| metric | pre-scaling | **post-scaling** | Δ |
|---|---|---|---|
| **Total** | 88.69% | **90.54%** | **+1.85** |
| Covergroup bins | 944/1095 = 86.21% | **962/1095 = 87.85%** | **+18 bins** |
| Covergroups (weighted) | 92.11% | **98.13%** | **+6.02** |
| Branches | 89.52% | **91.18%** | +1.66 |
| Conditions | 70.16% | **73.13%** | +2.97 |
| Statements | 96.23% | **96.88%** | +0.65 |
| Toggle | 74.23% | **75.85%** | +1.62 |
| Assertions | 98.59% | 98.59% | 0 |
| Directives | 100.00% | 100.00% | 0 |

Questa's "Total" is the **unweighted mean of the 7 categories**, so the +6.02 on weighted
covergroups is the dominant contributor to the +1.85 headline.

---

## 2. Exactly which bins moved

**18 newly covered, 0 lost** — measured by an instance-path-keyed diff of
`vcover report -cvg -details` on the two banks. Perfectly symmetric: **6 bins × the 3 cores that
were previously idle** (`CL0.C1`, `CL1.C0`, `CL1.C1`; `CL0.C0` already had all 6):

| bin | ×cores |
|---|---|
| `instr_class_cg_tcu.cp_warp.auto[0..3]` | 4 × 3 = 12 |
| `instr_class_cg_tcu.cp_active_threads.uniform` | 1 × 3 = 3 |
| `instr_class_cg_fpu.cp_active_threads.uniform` | 1 × 3 = 3 |

These come directly from the `tcu_mt` / `tcu_test` / `fpu_mt` grid scaling (`9674de0`, `49b19ba`).
Before, those kernels sized their grid to one core's capacity, so three of four cores never
dispatched a TCU or FPU instruction at all.

**No bin regressed.** That matters as much as the gain: scaling a grid arms the OBS-026
whole-array-init race, and a lost bin would have been the first symptom.

---

## 3. ⚠ CORRECTION — the "84 per-core bins / 28 per core" figure was WRONG

The resume block claimed *"84 are per-core instr_probe on cores 1-3 (`cluster0_core0` misses 0;
the other three miss 28 each)"*. **Measured from the actual UCDBs, that is not what the gap was.**

| | core0 missing | other cores missing | **excess vs core0** |
|---|---|---|---|
| pre-scaling 2CL | 13 | 25–26 each | **14 each = 42 total** |
| post-scaling 2CL | 13 | 19–20 each | **8 each = 24 total** |

So the per-core gap was **42 bins, not 84**, and the scaling closed **18 of them**. The claim that
`cluster0_core0` misses **0** was also wrong — it misses **13**, the same structural set every core
misses (AXI route bins, weight-0 red herrings, `mshr_stall`).

Anyone quoting the 84/28 numbers should stop; use 42/14 → 24/8.

---

## 4. The three questions the run was launched to answer

**(a) Do the per-core `instr_probe` bins fill? — PARTIALLY. 18 of 42.**
The TCU/FPU dispatch bins filled completely. The remaining 8-per-core did not, and the reason is
structural and *self-inflicted in a way we chose deliberately* (§5).

**(b) Does `cp_mshr_stall.stall` move now that 4 cores contend? — NO.**
Still **0 hits on all 4 cache instances** (cluster0/1 × icache/dcache), against 5,131,366 samples
of `no_stall`. Four cores contending for a per-socket L1 was the most plausible way to backpressure
the MSHR without new stimulus, and it was not enough. This remains a **genuine stimulus gap, left
honestly uncovered** — it is now the single best-understood remaining functional bin.

**(c) Does the total beat 88.69%? — YES, 90.54%.**

---

## 5. Why the last 8 bins per core are still missing — and why that is the RIGHT trade

The residual per-core excess is identical on all three cores:

| bin | who emits it |
|---|---|
| `instr_class_cg_alu.cp_alu_op.czeq` | riscv-dv only (Zicond) |
| `instr_class_cg_alu.cp_alu_op.czne` | riscv-dv only (Zicond) |
| `instr_class_cg_lsu.cp_lsu_op.lb` | riscv-dv only (byte load) |
| `instr_class_cg_sfu.cross_sfu_threads.<bar,uniform>` | `bar_masks` / `barrier_test` |
| `instr_class_cg_sfu.cross_sfu_threads.<bar,partial[2]>` | `bar_masks` / `barrier_test` |
| `instr_class_cg_sfu.cross_sfu_threads.<bar,partial[3]>` | `bar_masks` / `barrier_test` |
| `instr_class_cg_sfu.cross_sfu_threads.<pred,partial[2]>` | `bar_masks` |
| `instr_class_cg_sfu.cross_sfu_threads.<pred,partial[3]>` | `bar_masks` |

**Every one of these traces to FIX 1 or FIX 2 — the core gates we added on purpose.**
* **FIX 1** (`prepare.sh`, OBS-027) gates riscv-dv to core 0 via `VX_CSR_CORE_ID != 0 → vx_tmc 0`,
  because riscv-dv emits a single-hart program whose result at ≥2 cores is *architecturally
  undefined*. So cores 1–3 can never see a riscv-dv instruction stream — and Zicond/`lb` have no
  other producer in the suite.
* **FIX 2** (`barrier_test`, OBS-026) scopes the barrier kernel to core 0 for the same reason.

**This is not a regression and must not be "fixed" by removing the gates.** Coverage collected from
a program with no defined result is not coverage — it is a bin ticked by an undefined value. The
gates traded 24 bins for the ability to make a *defensible* correctness claim, which is the right
direction for this project.

**The honest way to recover those bins** is new stimulus that is multi-core-*safe*: a directed
kernel that emits Zicond and sub-word loads, and exercises barrier/predicate SFU ops, on **every**
core with each core writing only its own contiguous slice (the `vx_spawn.c:299` property that makes
the other 7 scaled kernels race-free without a barrier). That is a real work item, not a waiver.

---

## 6. Where the rest of the 2CL gap is

Of the 133 missing covergroup bins, the largest single block is **AXI**, not the cores:

| block | bins |
|---|---|
| `axi_transaction_cg.cross_type_route` | 39 |
| `axi_transaction_cg.cp_id_route` | 33 |
| per-core `instr_probe` residual (§5) | 24 |
| `cp_mshr_stall.stall` (4 cache instances) | 4 |
| weight-0 red herrings (`mem_usage_cp`, `system_mem_cross`, `axi_usage_cp`) | 10 |
| everything else (divergence, sched, reconverge, wspawn, cache events) | remainder |

**AXI = 72 of 133.** The tag space scales with the config (more cores ⇒ more distinct routing tags)
but the stimulus does not, so the extra tag values are simply never produced. This was already the
known 1CL story (`cp_id_route` waiver, `0cfec34`) and it scales *against* us: the waiver was derived
per-config, but the number of unreached reachable tags grows with core count. **This is the biggest
remaining lever at 2CL by a wide margin** — bigger than everything core-side combined.

### An asymmetry worth recording
`CL0.C0` **misses 2 bins the other three cores cover**: `warp_divergence_cg.cross_dvg_depth`
`<divergent,d[3]>` and `<uniform,d[1]>`. Core 0 is the one core that also runs the core-gated
riscv-dv and barrier workloads, so its warp-divergence history differs. Benign, but it means
"core 0 is a superset of the other cores" is **false** — do not assume it when reasoning about
per-core coverage.

---

## 7. Verification hygiene notes

* **Exclusions applied correctly at 2CL**: `coverage_exclude.gen.do` was generated for
  `2CL/2C/4W/4T (TOTAL_CORES=4, SOCKET_SIZE=2)`, 37 exclusion lines, and the (now-repaired, `04db8fd`)
  effectiveness guard reported **0 "had no effect"**. The `7863b44` fix — exporting `COV_NCL/NC/NW/NT`
  to the merge — is what keeps this from silently banking 2CL with 1CL exclusions.
* **`_unreachable` bins are a reporting-view artifact, not a waiver failure.** The per-instance
  detail view lists `cp_rw.wr_unreachable`, `cp_event.flush_unreachable`, `cp_event.wb_unreachable`
  as misses at **both** 1CL and 2CL, while the by-type headline (398/403 at 1CL) does not count
  them. Checked both banks; consistent. No action.
* **Never blend these two UCDBs.** Instance counts differ (2256 vs 8275); a cross-config merge is
  invalid.

---

## 8. What this changes for the paper

`docs/PAPER_BASE_EVALUATION.md` and `docs/paper/vortex_uvm_paper.tex` still say
*"100% functional / 43/43 tests / 91.0%"*. All three are wrong, and now differently wrong:

| paper claim | truth |
|---|---|
| "100% functional coverage" | **98.75% raw bins at 1CL** (99.12% weighted); **87.85% at 2CL** |
| "43/43 tests" | **44 distinct programs** (`riscv_pmp_test` dropped as the FW-1b byte-identical duplicate) |
| "91.0%" total | **91.07% at 1CL, 90.54% at 2CL** |

The two-config story is now genuinely stronger than the single number the paper quotes: both
configs pass **44/44 with 0 failures**, and the 2CL result improved by +1.85 points from a
correctness-motivated change rather than from waivers.
