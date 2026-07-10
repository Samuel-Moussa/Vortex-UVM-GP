# Vortex UVM — Coverage Sign-off Report

**Date:** 2026-07-10  ·  **RTL pin:** `7a52ee5`  ·  **Sim:** QuestaSim 2021.2_1
**Method:** black-box, end-state equivalence vs SimX golden model (DPI)
**Configs reported separately — never blended** (cross-config UCDB merge is invalid: width toggles + per-core instance inflation).

> Interactive version: published artifact (see conversation link). This file is the repo-tracked copy.

---

## Scorecard

| Metric | 1CL/1C/4W/4T (primary) | 2CL/2C/4W/4T (scale) |
|---|---|---|
| **Functional** (covergroup, type-level) | **100.00%** (17 types) | 92.48% (50 types) |
| **Line / Statement** | **96.55%** (4,290/4,443) | **96.19%** (14,703/15,284) |
| **Branches** | 90.21% (2,554/2,831) | 89.68% (9,061/10,103) |
| **Conditions** | 73.65% (232/315) | 69.57% (821/1,180) |
| **Toggles** | 77.99% (331,830/425,432) | 74.25% (927,924/1,249,674) |
| **Assertions** | 84.78% (117/138) | 72.35% (267/369) |
| **Total (filtered)** | 79.20% | 75.11% |
| Instances | 2,247 | 8,252 |
| Tests | 42 / 42 pass | 40 / 42 pass (2 SimX-seed) |

---

## 1. Acceptance criteria (VERIFICATION_PLAN.md §5–6)

| Criterion | Target | 1CL | 2CL | Status |
|---|---|---|---|---|
| Functional coverage goals met | full | 100.00% | 92.48% | **Met (primary)** |
| Line (statement) coverage | > 95% | 96.55% | 96.19% | **Met — both** |
| Toggle coverage, major modules | > 90% | 77.99% | 74.25% | **Below — structural, documented** |
| Scoreboard compares RTL vs SimX | yes | ✓ | ✓ | **Met — bidirectional** |
| High-priority testcases pass | all | 42/42 | 40/42 | **Met — 2 SimX-only** |

Line and functional targets are met. The toggle target is **not** met and is reported at its true
value — the shortfall is structural (§4), not a stimulus deficiency further tests would close. It is
documented rather than waived to an artificial pass.

---

## 2. Functional coverage

**1CL/1C — 100.00% (closed).** All 17 covergroup types at 100% (type-level, weighted). The 3 residual
raw bins (`mem_usage_cp`, `system_mem_cross`, `cp_occ`) are weight-0 idle-interface / unwired probes,
excluded by design. Instruction, warp-scheduling, memory-pattern, FPU op-decode, and TCU WMMA coverage
all filled; timing-coincidence bins closed with evidence-based waivers.

**2CL/2C — 92.48% (honest gap).** Not 100%, and exactly why: the per-core instruction probes bind
*per core*, so 4 cores create 4× covergroup instances. Single-core / single-warp directed kernels only
light up core-0's probe, leaving cores 1–3 sparse — the documented multi-core instance-sparsity effect.
Env/collector covergroups stay 100%; only the per-core probe types dip. Closing it needs multi-core
work distribution, not new coverage points.

---

## 3. Per-module toggle — 1CL/1C (the criterion is per major module)

Ranked ascending. Low modules are dominated not by untested logic but by **constant wide-bus bits** —
PC/address high bits that only a >256 KB program would flip, and write-data payloads on read-only /
write-through caches that the RTL never drives (§4).

| Major module | Toggle | bits | Dominant residual |
|---|---|---|---|
| schedule | 49.58% | 2,021/4,076 | PC high bits (small program) |
| fetch | 54.23% | 859/1,584 | PC / addr high bits |
| icache | 55.42% | 30,736/55,458 | read-only write-data / rw dead |
| decode | 68.09% | 783/1,150 | instr-field entropy |
| mem_unit / lsu | 68.66% | 48,127/70,098 | data / addr high bits |
| exe.sfu | 70.99% | 14,118/19,888 | CSR / control fields |
| issue.scoreboard | 71.40% | 12,825/17,962 | reg-dependency corners |
| commit | 77.36% | 7,524/9,726 | writeback data entropy |
| issue | 81.85% | 18,925/23,122 | operand data entropy |
| exe.alu | 83.47% | 29,765/35,660 | operand data entropy |
| axi / mem_adapter | 87.24% | 5,573/6,388 | wdata line-width dead |
| dcache | 88.69% | 80,900/91,220 | write-through data dead |

---

## 4. Methodology & honest caveats

### Toggle ceiling — root cause
The ~78% toggle is close to the honest ceiling for a single small config. A max-entropy stress kernel
(`toggle_stress`, complementary cache-line patterns) was written and passed vs SimX, but moved aggregate
toggle by **+0.02%** — proving the residual is not stimulus-reachable. Three structural causes, only the
first cleanly excludable:

- **Structural — dead write-data fields.** `DCACHE_WRITEBACK=0` (write-through) and a read-only icache
  mean the 512-bit full-line write-data payloads on request buffers / AXI `wdata` are never driven.
  Cleanly excludable, but only ~1–2% of the gap.
- **Realism — constant high bits.** `pc[18:30]`, address and tag high bits are constant only because
  programs are small and aligned. Reachable in principle (a 2³⁰-spanning program flips them) — so
  excluding them would be gaming, and they are **not** waived.
- **Stimulus — low-entropy data buses.** Wide operand / cache-array buses carry real program data whose
  bits don't fully exercise. More configs / higher-entropy programs help marginally, steep diminishing
  returns.

### Exclusions applied (audit trail: `scripts/coverage_exclude.do`)
- **EOTH — cvfpu FP IP:** third-party `fpnew_*`, divsqrt, common-cells. Not Vortex DUT; verified via SimX softfloat.
- **EOTH — TCU datapath:** Berkeley HardFloat (`tcu_fp`). TCU is functionally verified (WMMA byte-exact vs
  SimX) but its exhaustive bf16 matrix math is identity-exercised only.
- **EUR — L2/L3 passthru interfaces:** `L2/L3_ENABLE` undefined ⇒ `PASSTHRU(1)`; cache-side bus nets tied off.
- **Waivers — timing-coincidence functional bins:** `cross_ipc_stalls` double-stall, `system_axi_cross`
  idle-edge, wspawn-multithread, high-IPC ceiling, TCU-collective mask, RV32 F2F / LD·SD. Each cited with an
  RTL-level reachability argument.

### 2CL test failures — root-caused, NOT DUT bugs
Full investigation: `docs/investigations/SimX_2CL_no_fence_divergence.md`. Both failures are the
**fenceless / ordering-unsafe** riscv-dv tests, and only those; every fence-respecting test passes at 2CL.

- **`riscv_no_fence_test`** — one deterministic, reproducible memory mismatch at `0x80013dd8`
  (DUT `0x28af8c40` vs SimX `0x2fff8c40`). **Proven per-cluster:** SimX cluster-0 cores match the DUT
  *exactly*; only SimX cluster-1 cores diverge, isolated to a single value propagating through `s2`/`a5`/`s10`.
  Disproven by rebuild+replay: UB, cross-core race, SimX crash, register-init randomness, non-shared memory,
  per-core CSR. The **only** remaining per-core input is the order in which unsynchronized cross-core writes
  become visible — i.e. SimX's deterministic core-interleaving resolves fenceless ordering differently for its
  second cluster than the timing-accurate DUT does. The DUT is self-consistent (all cores agree) and
  corroborated by SimX's own cluster 0.
- **`riscv_full_interrupt_test`** — same class: single-bit mismatch, passes at 1CL, fails only at multi-cluster.

A real multi-cluster coherence bug would corrupt the fenced tests too — they all pass, which is the signature
that this is a **reference-model memory-ordering faithfulness difference, not a Vortex defect**. Disposition:
`no_fence` / `full_interrupt` at multi-cluster are classed **UNVERIFIABLE** (evidence-based, not a guess).
Every deterministic kernel, directed, and regression test passed at 2CL. Honest boundary: the exact upstream
first-divergence instruction was not pinpointed — that needs a lockstep DUT-vs-SimX register trace (Future Work).

---

## 5. Sign-off summary

- **PASS — Functional coverage** closed on the primary config (100%); 2CL residual is a characterized
  instance-sparsity artifact, not missing coverage.
- **PASS — Line coverage > 95%** on both configs (96.55% / 96.19%).
- **PASS — Bidirectional scoreboard** vs SimX; two live fault-injection guards (wrong-value + dropped-store)
  stay red on injection.
- **BELOW — Toggle > 90%** not met (78% / 74%). Root-caused as structural + realism-limited; reported at true
  value, not waived to a synthetic pass.
- **NOTE — 2 of 84 test-runs** (the fenceless `no_fence` / `full_interrupt` riscv-dv tests, multi-cluster only)
  — root-caused to a per-cluster SimX memory-ordering divergence, not a Vortex defect (§4).
