# Coverage gap push — results and remaining gaps (2026-08-15)

Follows the post-scaling banks of the same day. This round changed the **coverage model** (AXI route
re-modelled, two structural waivers re-derived) and added **three directed kernels**. Every gap was
verified hit in an individual run *before* any suite was launched — a rule that paid for itself
three times over (§5).

**Evidence:** `docs/RTL_OBSERVATIONS.md` **OBS-030 / OBS-031 / OBS-032**.
**Commits:** `d9cd75c` `6433857` `e29e836` `e36c2da` `a38c039` `90206aa` (+ obs `927be95` `e342861` `f60aa8c`).

---

## 1. Headline — 1CL/1C/4W/4T

**47 programs staged, 0 FAILED** (was 44 — the three new kernels).

| metric | post-scaling bank | **gap-push bank** | Δ |
|---|---|---|---|
| **Total** | 91.07% | **93.09%** | **+2.02** |
| Conditions | 76.03% | **85.30%** | **+9.27** |
| Branches | 91.06% | **93.14%** | +2.08 |
| Statements | 96.82% | **97.54%** | +0.72 |
| Toggles | 78.39% | **79.79%** | +1.40 |
| Covergroups (weighted) | 99.12% | **99.79%** | +0.67 |
| Covergroup bins (raw) | 398/403 = 98.75% | **370/377 = 98.14%** | denominator −26 |
| Assertions | 96.09% | 96.09% | 0 |
| Directives | 100% | 100% | 0 |

**The raw-bin percentage went DOWN while the model got more honest, and that is the expected
outcome.** The denominator dropped 403→377 because the flat `cp_id_route`/`cross_type_route` pair
(and their four literal `ignore_bins`) were withdrawn and replaced by decoded sub-fields, and
because `cp_mshr_stall.stall` is now waived on a *derived* structural bound. Raw bin % across a
changed bin set is not a like-for-like comparison; **Total, and every code-coverage category, is.**

### Why Conditions moved +9.27
The three new kernels drive paths the suite never exercised: local-memory load/store
(`lmem_stress` — the first kernel to touch the scratchpad at all), sub-word LSU ops and Zicond
(`multicore_isa`), and sustained cache miss/eviction traffic (`mshr_flood`, 67,207 dcache misses
vs 774 hits). Condition coverage is the category most sensitive to unexercised control paths, which
is why it moved most.

---

## 1b. Headline — 2CL/2C/4W/4T

**47 programs staged, 0 FAILED.**

| metric | post-scaling bank | **gap-push bank** | Δ |
|---|---|---|---|
| **Total** | 90.54% | **92.67%** | **+2.13** |
| Conditions | 73.13% | **81.27%** | **+8.14** |
| Branches | 91.18% | **93.68%** | +2.50 |
| Statements | 96.88% | **97.82%** | +0.94 |
| Toggles | 75.85% | **77.80%** | +1.95 |
| Covergroups (weighted) | 98.13% | **99.52%** | +1.39 |
| **Covergroup bins (raw)** | 962/1095 = 87.85% | **985/1032 = 95.44%** | **+7.59** |
| Assertions | 98.59% | 98.59% | 0 |
| Directives | 100% | 100% | 0 |

At 2CL the raw bin percentage moved **up 7.59 points** — unlike 1CL, where it fell. Both are the
same effect seen from two configs: the withdrawn waivers were *correct at 1CL* (so removing them
exposed genuinely-unhit bins) and *wrong at 2CL* (so removing them returned 4,488+ real transactions
to the count), while `multicore_isa` closed the 24-bin per-core gap that only exists at 2CL.

### Combined, both configs

| | 1CL | 2CL |
|---|---|---|
| programs | **47/47, 0 FAILED** | **47/47, 0 FAILED** |
| Total | **93.09%** (+2.02) | **92.67%** (+2.13) |
| Covergroup bins | 370/377 = 98.14% | 985/1032 = 95.44% |
| Covergroups weighted | 99.79% | 99.52% |
| Instances | 2256 | 8275 |

---

## 2b. Remaining gaps at 2CL — 47 bins, four root causes

| bins | coverpoint | root cause | actionable? |
|---|---|---|---|
| 24 | `cp_route_slot` slots 4-15 + `cross_port_slot` | **measured** per-port outstanding-read concurrency is 3 (contiguous {0,1,2}); same requester-width limit as OBS-031 | not without deriving the bound — see §4 |
| 8 | `cp_write_tag` `tag[4..7]` | write tag values >=64 never occur at 2CL (`ROUTE_W`=7, buckets of 16) | stimulus, low value |
| 4 | `mem_usage_cp` + `system_mem_cross` | MEM interface idle on AXI runs; **weight 0** by design | no — structural |
| 2 | `cross_dvg_depth` `<divergent,d[3]>`, `<uniform,d[1]>` | divergence-depth combinations not produced by the current kernels | yes — a directed divergence kernel |

**The 84/42-bin per-core `instr_probe` gap is GONE.** `multicore_isa` closed it: every tracked bin
is now covered on all four cores with identical counts. That gap dominated the previous 2CL
analysis and no longer appears.

**`cross_dvg_depth` is the one clean, cheap target left** — 2 bins, ordinary stimulus, no structural
obstacle. Everything else is either a measured hardware bound or a documented weight-0 row.

---

## 2. Remaining gaps at 1CL — all seven bins accounted for

| bins | coverpoint | reason | actionable? |
|---|---|---|---|
| 4 | `cp_write_tag` `tag[4..7]` | write tag values >=32 never occur **at 1CL** | see below |
| 3 | `mem_usage_cp` (`idle`/`read`/`write`) | MEM interface is idle on AXI runs; **weight 0** by design (`vortex_if.sv:263`) | no — structural, correctly handled |
| 1 | `system_mem_cross` `<*,*>` | same weight-0 red herring | no |
| 1 | `cross_port_slot` `<*,*>` | fully ignored at 1CL — the AXI tag buffer is **not elaborated** there | no — config-structural |

**`cp_write_tag[4..7]` is the interesting one, and it VINDICATES the OBS-030 rewrite.** The old
model waived these values with `ignore_bins route_msb_unreachable = {[32:63]}` justified as *"bit5
never set @1 requester"*. That premise is **true at 1CL** — which is why the bins are genuinely
unhit here — and **false at 2CL**, where the same waiver fired on 4,488 real transactions. The new
model expresses exactly that: honestly uncovered where unreachable-by-stimulus, and counted where
reachable. No claim is made that hardware cannot produce them.

The weighted covergroup figure (99.79%) excludes the weight-0 rows, so the functional picture at
1CL is: **4 honestly-uncovered write-tag buckets, everything else closed.**

---

## 3. Kernel-by-kernel: what each bought

| kernel | target | measured result |
|---|---|---|
| `multicore_isa` | 8 per-core bins the FIX 1/FIX 2 core gates cost us | **all 11 tracked bins on all 4 cores at 2CL**, identical counts |
| `lmem_stress` | `VX_local_mem` (56.4% toggle, untouched by the suite) | **toggle 57.52% -> 73.19%, +687 bins** |
| `mshr_flood` | `cp_mshr_stall.stall`, `cp_route_slot` | bin NOT hit — **proved structurally unreachable** (OBS-031); 67,207 dcache misses |

### `multicore_isa` at 2CL — the per-core gap, closed

| bin | CL0.C0 | CL0.C1 | CL1.C0 | CL1.C1 |
|---|---|---|---|---|
| `czeq` / `czne` | 4 | 4 | 4 | 4 |
| `lb` / `lh` | 20 | 20 | 20 | 20 |
| `sb` / `sh` | 44 / 4 | 44 / 4 | 44 / 4 | 44 / 4 |
| `<bar,{uniform,partial[3],partial[2]}>` | 4 | 4 | 4 | 4 |
| `<pred,{partial[3],partial[2]}>` | 4 | 4 | 4 | 4 |

Perfect symmetry across cores is what a correctly device-sized kernel must produce, and is itself a
check that the grid scaling works. **The gates were not weakened to get this** — riscv-dv and
`barrier_test` remain core-0 only, because coverage from an architecturally-undefined program is a
bin ticked by an undefined value.

Zicond is emitted from a kernel for the first time. The compiler *cannot* produce it: kernels build
`-march=rv32imaf` (`tests/kernel/common.mk:6`), verified as 0 occurrences across three existing
ELFs. It is inline `.insn`, encoded from the RTL (`INST_R_F7_ZICOND = 7'b0000111`,
`VX_gpu_pkg.sv:168`; `funct3[1]` selects CZNE, `VX_decode.sv:189`).

---

## 4. Two structural findings that replaced "stimulus gaps"

### OBS-031 — `cp_mshr_stall.stall` was never reachable
Called "a genuine stimulus gap, honestly uncovered" in every prior doc. It is not:
`LSUQ_IN_SIZE = 2*(SIMD_WIDTH/NUM_LSU_LANES)` is **2 for every configuration**, giving
`LSUQ_OUT_SIZE` = **4** at `NUM_THREADS=4` against `MSHR_SIZE` = **16**. The LSU physically cannot
present enough concurrent misses. Waived **config-awarely** on `MAX_OUTSTANDING < MSHR_SIZE`
(computed at the bind site) so it auto-reactivates at `NUM_THREADS>=16`.

### `cp_route_slot` — measured, and deliberately NOT waived
At 2CL (tag buffer present) the covered slots are **{0,1,2} — contiguous**. Since the allocator is
strictly lowest-free (`VX_allocator.sv:49`), a contiguous prefix is the only pattern a correct
decode can produce, and it bounds per-port concurrency at **3**. The remaining 13 slots share
OBS-031's root cause.
**They are left in the denominator, uncovered.** The mechanism is clear but the exact concurrency
bound has not been derived from RTL parameters (measured 3 < the naive `LSUQ_OUT_SIZE * cores/port`
= 8), and waiving on an unproven bound is the very mistake OBS-030 documents. `cross_port_slot` is
kept for the same reason: deleting a coverpoint because it reads low is tuning the metric.

---

## 5. Four errors caught before they reached a bank

Every one would have passed a 47/47 sweep while proving nothing. This is the argument for verifying
each gap individually *before* spending hours on a suite.

1. **`lmem_stress` tested nothing.** Hardcoded `0x7FFF0000`; the real base is `0xFFFF0000`
   (`STACK_BASE_ADDR`, `VX_config.vh:196`). It hammered ordinary memory, self-checked correctly,
   passed, and moved coverage **0.00%** — the OBS-029 failure mode, committed while writing a kernel
   that cites OBS-029. Now reads `VX_CSR_LOCAL_MEM_BASE` with a non-vacuity guard.
2. **OBS-031's first draft blamed the wrong queue.** It argued the fill queue throttles at 2
   entries — true of the RTL default, false of what we build: `compile.sh:70-73` silently forces
   `MREQ_SIZE` 4 -> 16 (**OBS-032**). Caught by reading the compile transcript instead of the header.
3. **`cp_route_slot` was mis-decoded at 1CL.** The tag buffer is not elaborated there, so the read
   `id` is a raw cache tag. Exposed by the *measurement*: bins `{0,2,3,7,11,15}` with 1,4,5,6 at
   zero is impossible under lowest-free allocation.
4. **`mshr_flood` v1 did not miss.** Blocked slots spread each thread's lines over 4 sets, 2 per
   set — comfortably inside a 4-way cache, so the read-back hit. Fixed with thread-interleaved slots
   that collapse each thread onto one set.

**Reusable technique:** on any allocator-indexed coverpoint, **contiguity is a free self-check**. A
gappy prefix under lowest-free allocation means the decode is wrong, not the stimulus.

---

## 6. Open items

* **OBS-032 (OPEN)** — `compile.sh:70-73` forces `{I,D}CACHE_MREQ_SIZE=16` over an RTL default of 4,
  so **no bank has ever measured the default cache configuration**. Decide before the paper: drop it
  and re-measure, or keep it and state it in the configuration table.
* **`cp_route_slot` bound** — derive the true per-port concurrency limit from RTL parameters, then
  either waive config-awarely or target it. Not before.
* **L2/L3 — DEFERRED, not done.** `run_suite.sh` never sets `L2=1 L3=1`, so both levels are
  `PASSTHRU` in every bank; no kernel can reach them. OBS-016/017 are FIXED and OBS-018 proved they
  elaborate (timing moved 12,215 -> 21,968 cycles on `tcu_test`). It needs its **own bank** as a
  third config. Verify elaboration with `vcover report -recursive | grep l2cache`, **never** by
  grepping the sim log — OBS-018 notes `dcache` does not appear there either.
