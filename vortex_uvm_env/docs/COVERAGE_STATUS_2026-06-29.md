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

**Latest merged totals (incl. fpu_test + diverge_lite):** statements **94.48%**,
branches 86.83%, toggles 70.98%, functional bins **39.74%**, total **71.43%**.

**INV-1 SOLVED (2026-06-29):** the "hang" was `vx_printf` IO volume, not a wspawn
bug — printf-light multi-warp kernels complete fast. This unblocked:
- **T4 negative test** — `negative_result_test PROGRAM_NAME=vecadd_lite` proves the
  checker catches an injected fault (Gate-0 milestone).
- **Warp-state coverage** — `diverge_lite` (divergent multi-warp) lifted
  `warp_divergence_cg` 34%→81%, `warp_reconverge_cg` 15%→80%, `sched_state` →90%.

Coverage progression this session: functional bins **9.7% → 37.5%** (ignore_bins)
**→ 39.74%** (FP + divergent kernels); statements **92.6% → 94.48%**.

riscv-dv is SATURATED (more seeds add 0). Remaining functional gaps: `wspawn_cg`/
`tmc_cg` (more spawn-pattern variety), FP-multi-warp (multi-thread FP kernel),
TCU/mem legit ignores, DCR variety, AXI routing/response.

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

## 4b. Directed warp-control kernel — `spawn_tmc_sweep` (2026-06-29)

New printf-free directed kernel `tests/kernel/spawn_tmc_sweep` drives the raw
`vx_wspawn`/`vx_tmc` primitives across every spawn count and thread-mask
occupancy (following the runtime's `process_threads_stub` + `vx_wspawn(1,0)`
collapse handshake, so no warp is left running across a re-spawn). PASS, ebreak
completion, DUT==SimX (mem comparisons passed), 0 errors.

| Covergroup | Before | After (this run) |
|---|---|---|
| `tmc_cg.cp_tmc_occ` | 60% | **100%** (deactivate/one/partial[2]/partial[3]/full all hit) |
| `wspawn_cg.cp_spawn_cnt` | 25% | **75% = 100% of REACHABLE** (one, some[2], some[3]) |

**Covergroup off-by-one found (→ Ahmad):** `wspawn_cg.cp_spawn_cnt` bins
`{ one={1}; some[]={[2:NW-1]}; all={NW} }` but the probe samples
`$countones(warp_ctl_if.wspawn.wmask)` and the wmask **excludes the issuing
warp** — so it ranges `0..NW-1` and the `all={NW}` bin is **unreachable by
construction** (you can never spawn all NW warps; warp 0 is never in the mask).
`vx_wspawn(4)` on the 4-warp config registers as `some[3]`, not `all`. Fix:
redefine `all` to `{NW-1}` (or `ignore_bins all`). After that, `wspawn_cg`
reads 100%. Trip-wire: revert if wspawn semantics ever include the issuer.

**LSU unreachable (→ Ahmad):** `lsu_class_cg.cp_lsu_op` `ld`/`sd` are RV64-only
(load/store doubleword) — unreachable in the RV32 config. `ignore_bins` them;
the 6 RV32 ops (lb/lh/lw/sb/sh/sw) are all hit (reported 75% = 6/8, 100% of
reachable).

## 4c. Directed barrier kernel — `barrier_lite` (2026-06-29)

New printf-free directed kernel `tests/kernel/barrier_lite` drives `vx_barrier`
across both barrier IDs and every reachable participant count (proven
barrier_test handshake: `vx_wspawn(nw,k); k(); kernel ends vx_tmc(wid==0)`).
Completes via ebreak in ~6k cycles, all warps sync.

| Coverpoint | Before | After |
|---|---|---|
| `barrier_cg.cp_bar_id`    | 50% | **100%** (ids 0,1; NUM_BARRIERS=NW/2=2) |
| `barrier_cg.cp_bar_event` | —   | **100%** (hold + rel) |
| `barrier_cg.cp_bar_scope` | 50% | 50% = **100% of reachable** (global_bar needs GBAR_ENABLE/multi-core) |
| `barrier_cg.cp_bar_size`  | 25% | 75% = **100% of reachable** (size[0]=1-warp barrier is is_noop, never sampled) |

Net: functional bins 266 to 269 (+3), total 73.02% to 73.20%.

**Benign scoreboard MEM MISMATCH found (-> Ahmad):** barrier_lite reports ONE
mismatch at the `.got` tail word (e.g. addr=0x80001e98, DUT=0x0 vs
SimX=0x80001e88). It is NOT a barrier bug — root-caused:
- The DUT's `.bss`-clear writes the bss region that shares the GOT's 64-byte
  cache line. That line is write-allocated with zero for the never-loaded GOT
  bytes, so the cache **writeback clobbers the read-only GOT word to 0** in AXI
  memory.
- SimX models flat memory (no cache writeback) and keeps the GOT value.
- `vortex_scoreboard.sv` `shadow_memory` is built from observed AXI writes only
  with **no program-image preload**, so it records the DUT's spurious 0 and
  compares it against SimX's real pointer.

Triggered whenever `__bss_start` is not 8-byte aligned AND shares a cache line
with `.got` (passing kernels happen to have 8-aligned `__bss_start`). Fix
belongs in the scoreboard — same class as its existing stack/poison gates:
either (a) **preload `shadow_memory` from the program image** so read-only words
are correct, or (b) **ignore writeback of read-only `.got`/`.rodata` words the
DUT never genuinely stored**. Until then barrier_lite's *coverage* is valid
(collected before the verdict; barriers executed correctly).

## 4d. Config matrix (D-matrix) — multi-core runs (2026-06-29)

The config-dependent coverpoints (`host_operation_cg.cp_num_cores`/`cp_num_warps`/
`cp_num_threads`, each previously 33% = the 1-core/4-warp/4-thread value only) are
**unreachable in the primary config by construction** — they need other configs.
Ran the matrix via `make sim ... CORES=n WARPS=n THREADS=n` (recompiles RTL +
rebuilds SimX + matching plusargs; I2 asserts confirm RTL==UVM):

| Config | Result | New bins |
|---|---|---|
| 1C/4W/4T (primary) | baseline | single, mid, t4 |
| **4C/2W/1T** (A) | ebreak, I2 OK | `cp_num_cores.sm`, `cp_num_warps.low`, `cp_num_threads.t1` |
| **8C/8W/2T** (B) | ebreak, I2 OK | `cp_num_cores.lg`, `cp_num_warps.high`, `cp_num_threads.t2` |

Across the matrix: **`cp_num_cores`, `cp_num_warps`, `cp_num_threads` all reach
100%**. Crosses `cross_cores_warps`/`cross_launch_config` at 33% (need ~9 config
combos each to fully close — diminishing returns).

**Infra unblocked (committed `cf1a827`):** multi-core was blocked by the AXI
`ID_WIDTH` hardcoded default (vsim-8451 virtual-interface resolution). Now derives
from `VX_MEM_TAG_WIDTH` → any config elaborates. (Extends C1 to the AXI agent.)

**Two D-matrix infra findings (Samuel lane, for SIGN sign-off):**
1. **Cross-config UCDB merge is INVALID.** Merging configs raises `vcover-6821`
   object-type mismatches — config-dependent signal widths (e.g.
   `schedule_if/data.wid` width tracks NUM_WARPS) make toggle/code-coverage nodes
   structurally incompatible, and per-core probes multiply instances (1-core 2247
   instances → 4-core 3590 → distorts BY-INSTANCE %). **Do NOT blend configs into
   one number.** SIGN must report **per-config** functional+code coverage + matrix
   status. (The 1-core combined headline stays the clean 43.31%; the matrix is a
   separate per-config artifact.)
2. **Multi-core verification is currently VACUOUS.** Both A and B ran to ebreak
   but the scoreboard reported `data_compared=0` (all captured writes skipped as
   stack/MMIO + poison; result-region `g_dst` not compared). Coverage is valid
   (config bins come from launch plusargs + execution probes) but DUT==SimX is not
   verified at multi-core — the AXI-monitor result capture / SimX shared-mem
   readback needs fixing before a real multi-config sign-off.

## 5. Handover asks

- **Ahmad:** (1) `ignore_bins`/`illegal_bins` on `axi_transaction_cg` unreachable
  crosses + always-zero coverpoints — biggest functional unlock; (2) toggle/line
  waivers for the code-coverage targets; (3) **`wspawn_cg.cp_spawn_cnt` `all`
  off-by-one** + **`lsu_class_cg` `ld`/`sd` RV64-only** ignore_bins (§4b);
  (4) **`barrier_cg` ignore_bins** `cp_bar_scope.global_bar` (needs GBAR/multi-core)
  + `cp_bar_size.size[0]` (1-warp barrier is is_noop) (§4c); (5) **scoreboard
  `shadow_memory` GOT/cache-writeback gate** — preload from image or ignore
  read-only `.got`/`.rodata` words the DUT zero-clobbers (§4c, fixes the lone
  barrier_lite mismatch). (See also `HANDOVER_Ahmad_unused_axi_dcr_sequences.md`
  for stimulus to fill reachable AXI bins.)
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
