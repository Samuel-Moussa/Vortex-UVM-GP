# HANDOVER → Ahmad — push functional coverage from 47.20% toward 100%

**From:** Samuel (infra + config + configurable coverage) · **Date:** 2026-06-29
**Branch:** `Sudky_scoreboard_and_coverage_collector` · **HEAD:** `22caf45`
**Current combined (fresh 16-run suite, 1C/4W/4T, 2247 instances — no inflation):**
functional **47.20% (270/572)**, total **73.93%**. Report: `cov/combined_report_2026-06-29/`.

This is the **honest reachable-and-hit** number: I only `ignore_bins` bins I could
**prove** unreachable from RTL/driver evidence, and refused to waive reachable ones.
**Cardinal rule (keep it): never ignore a reachable bin to inflate the %. Cite evidence + a trip-wire for every waiver.**

---

## 0. What I already landed (so you don't redo it)
- **Config-aware coverage (`55ac424`)** — `cp_num_cores/warps/threads` carry
  `ignore_bins other_cfg = {[0:255]} with (item != CFG_*)` keyed off compile-time
  `` `NUM_* `` (available in the UVM compile via `+define+`). Each build counts ONLY
  its config's reachable bin; **auto-adapts to ANY config** (crosses too). Those
  coverpoints + `cross_cores_warps`/`cross_launch_config` = **100%**.
- **Evidence-based AXI ignores (`148ff78`)** — from `VX_axi_adapter.sv` +
  `axi_driver.sv`: `cp_size` (native only), `cp_burst`/`cp_len` (FIXED/single),
  `cp_bresp`/`cp_rresp0` (TB always OKAY, no error-inject, not SimX-verifiable),
  `cross_type_burst_size` → all **100%**. Full reachability-map comment block is in
  `vortex_coverage_collector.sv` above `covergroup axi_transaction_cg`.
- **Multi-config now works** (`cf1a827` AXI ID_WIDTH derive + `1ce1e9f` per-config
  SimX object rebuild) — any config elaborates AND verifies. Policy: **warps≥2 &
  threads≥2** (TCU needs ≥2; do not `NO_TCU`).
- **New stimulus kernels:** `spawn_tmc_sweep` (tmc_cg 60→100, wspawn reachable),
  `barrier_lite` (barrier_cg → max reachable). Run via
  `make sim TEST=kernel_launch_test PROGRAM_NAME=<k>`.

---

## 1. CONFIG-AWARE covergroups still to do (extend my pattern) — YOUR LANE
The same `with (item != CFG_*)` / `` `ifdef `` mechanism applies to more covergroups.
Make these **mode/config-aware** so they don't cap coverage in the active config:

### 1a. `mem_usage_cp` / `system_mem_cross` (system_cg) — **0%, AXI-mode unreachable**
In AXI mode (`USE_AXI_WRAPPER`) the **mem_agent is passive** → the custom-mem
usage signals never toggle → these are 0% and **cannot** be hit. Wrap them:
```systemverilog
`ifndef USE_AXI_WRAPPER
  // mem_usage_cp / system_mem_cross only meaningful on the custom-mem path
  cp ... ; cross ... ;
`endif
```
(`USE_AXI_WRAPPER` is in the UVM compile via `+define+`, same as `` `NUM_* ``.)
Removes ~10 always-0 bins from the AXI-config denominator. Trip-wire: revert for non-AXI runs.

### 1b. Structural waivers in the **probe covergroups** (`tb/vx_sched_probe.sv`)
These are config/structural, evidence-clear — ignore them:
- **`cp_spawn_cnt` `all`={NW}** (wspawn_cg, 75%) — the probe samples
  `$countones(wspawn.wmask)` and **the wmask excludes the issuing warp**, so it maxes
  at NW-1. `all`={NW} is unreachable. Fix: `bins all = {NW-1}` (or `ignore_bins all`).
- **`cp_bar_scope` `global_bar`** (barrier_cg, 50%) — `is_global` needs
  `` `GBAR_ENABLE `` (verified in `VX_wctl_unit.sv:136`); our build never defines it →
  unreachable. `` `ifndef GBAR_ENABLE `` ignore (or `ignore_bins global_bar`).
- **`cp_bar_size` `size[0]`** (barrier_cg, 75%) — `size_m1==0` (1-warp barrier) is
  `is_noop` and never sampled → unreachable. `ignore_bins size_0`.

### 1c. `cp_lsu_op` `ld`/`sd` (lsu_class_cg, 75%) — `tb/vx_instr_probe.sv`
RV64-only doubleword ops; XLEN_32 build can't emit them. `` `ifdef XLEN_64 ``-guard
or `ignore_bins`. (Leaves lb/lh/lw/sb/sh/sw = 100% of RV32-reachable.)

> After 1a–1c: ~20–25 more bins leave the denominator legitimately.

---

## 2. The BIG lever — `cp_id_route` + `cross_type_route` (≈ half the remaining gap)
`axi_transaction_cg`: `cp_id_route` 21.9% (64 vals), `cross_type_route` 14%.
**Reachable — do NOT blanket-ignore.** Empirically the **even-≥4** routing values
never occur (covered: 0,1,2,3,5,7,9,11,13,15,17…; ZERO: 4,6,8,10,…). This is the
config bypass-tag encoding (`NUM_DCACHES=0`, `DCACHE_NUM_BANKS=1`).
Two correct ways to close it (pick or combine):
- **(A) Structural decode** — trace the last-level mem-bus tag layout
  (`CACHE_CLUSTER_*_MEM_TAG_WIDTH` macros + the `NUM_DCACHES=0` bypass path in
  `VX_gpu_pkg.sv`) to PROVE which of the 6 routing bits are constant at this config,
  then `ignore_bins` only the proven-impossible values. Needs AXI/tag judgment.
- **(B) Stimulus** — varied memory traffic (many outstanding requests across
  MSHR ids / ports) to fill the reachable routing values.
This is the single biggest move toward 100%.

---

## 3. STIMULUS gaps (need workloads, not waivers) — coordinate with Samuel/Steven
| Covergroup / coverpoint | Now | What fills it |
|---|---|---|
| `status_performance_cg`: `cp_pc_region`(0%), `cp_occ`(0%), `cp_ipc_bucket`(50%), `cp_*_stall`(50%), `cross_ipc_stalls`/`cross_stall_types`(12.5%), `cross_pc_cycles`(0%) | low | **varied workloads** — different IPC/stall/PC-region profiles (compute-bound vs mem-bound vs branchy kernels). Biggest stimulus chunk. |
| `divergence_cg`/`reconverge_cg`: `cp_split_depth`/`cp_join_depth`/`cp_join_occ`(75%), `cross_dvg_depth`/`cross_join`(50–75%) | partial | **deeper nested divergence** (depth-3+ data-dependent branches) — a `diverge_deep` kernel (extend `diverge_lite`). |
| `sched_state_cg`: `cp_active_warps`/`cp_stalled_warps`(80%), `cp_active_threads`(50%) | partial | more concurrent warp activity / partial-mask kernels |
| `host_operation_cg`: `cp_op_type`(50%), `cp_completion`(50%), `cp_timeout`(66%), `cross_op_completion`(8%) | partial | host **READ_RESULT** ops + a **timeout** scenario (only LAUNCH/WAIT + completed seen today) — needs Path-B host flow (Steven) or a deliberate timeout test |
| `dcr_write_cg`/`dcr_config_cg`: `wr_data_cp`(50%), `wr_addr_cp`(75%), `cp_startup_align`/`cp_data_magnitude`(50%), `cross_addr_data`(25%) | partial | **DCR write variety** — the unused dcr sequences (see `HANDOVER_Ahmad_unused_axi_dcr_sequences.md`) |
| `sfu_class_cg`: `cross_sfu_threads`(53%) | partial | SFU ops across more thread-mask occupancies |
| `alu_class_cg`: `cp_alu_op`(85.7%) | partial | only `czeq`/`czne` missing → needs a **Zicond build** (`-march=…zicond`) — Samuel/Steven build knob, not a waiver |

---

## 4. SCOREBOARD items (your lane) — needed for Gate-0 / honest verification
- **SB-DIR (Gate-0 blocker)** — `compare_all_written()` is DUT-write-only; can't
  detect a **dropped store** (SimX wrote, DUT didn't). Add the reverse direction
  (iterate SimX-written addrs too). See `HANDOVER_Ahmad_scoreboard_dropped_stores.md`.
- **SB-GOT (NEW, found via barrier_lite)** — false MEM MISMATCH at a read-only
  `.got` word: the DUT cache writeback zero-clobbers a word the program never
  stored, and `shadow_memory` has **no image preload**, so it compares 0 vs SimX's
  real pointer. Fix: **preload `shadow_memory` from the program image**, or ignore
  writeback of never-stored read-only `.got`/`.rodata` words (mirror the existing
  stack/poison gates). Detail: `COVERAGE_STATUS_2026-06-29.md` §4c.

---

## 5. P1 commit probe — covergroups
`tb/vx_commit_probe.sv` is bound and live (passive, per-lane `retire_fire`, exposes
uuid/wid/sid/tmask/PC/wb/rd/data/sop/eop). **Hang covergroups off it** — retired-instr
count, per-warp/sid activity, writeback-reg distribution. (Samuel built the bind; sampling is yours.)

---

## 6. How to measure (reproduce the 47.20%)
```bash
cd vortex_uvm_env
scripts/run_suite.sh                              # 1CL/1C/4W/4T (compile once, sim-only rest, auto-merge)
CLUSTERS=2 CORES=2 WARPS=4 THREADS=4 scripts/run_suite.sh   # any config (warps/threads >= 2)
# report: cov/report/{functional.txt,summary.txt,html/}  +  cov/merged.ucdb
```
`scripts/run_suite.sh` (installed this session) runs kernels + directed + all
riscv-dv, skips runs that produce no UCDB, and merges. Keep the **headline at
1C/4W/4T** (single-config = no instance inflation). **Never blend configs into one
UCDB** (vcover-6821 width-toggle conflicts + per-core instance inflation make the %
DROP — report per-config).

## 7. riscv-dv profile status (which contribute, which fail, why, owner)
Of the 18 rv32imc profiles, **only ~3–4 produce coverage today**; the rest fail for
classifiable reasons. This bounds how much riscv-dv can add to functional coverage.

| Profile | Result | Cause / disposition | Owner |
|---|---|---|---|
| `arithmetic_basic` | ✅ PASS (UCDB) | baseline ALU stream | — |
| `ebreak_debug_mode` | ✅ PASS (UCDB) | completes via ebreak | — |
| `loop` | ✅ PASS (UCDB) | now passes (per-config SimX rebuild fixed its earlier SIGABRT) | — |
| `jump_stress`, `unaligned_load_store`, `ebreak` | ⚠️ ran, **Test failed (code 1/3)** | completed but UVM_ERROR (DUT-vs-SimX mismatch / exit path) — **investigate**; may yield UCDB if it reaches coverage-save | Steven (SimX) / Samuel (prepare post-proc) |
| `full_interrupt`, `illegal_instr`, `mmu_stress`, `pmp` | ✗ **Fatal in sim → coverage save disabled** | privileged / trap / MMU instrs Vortex's user-mode model doesn't implement — **inapplicable** (expected). Could be skipped from the suite. | n/a (inapplicable) |
| `no_fence`, `non_compressed`, `rand_instr`, `rand_jump` | ✗ **Fatal in sim** | *should* be applicable → likely SimX abort or RTL assertion on a generated instr; needs the `prepare.sh` sed post-process to cover more cases, or a SimX fix | Steven (SimX) / Samuel (prepare) |
| `csr`, `instr_base`, `mem_region_stress` | ✗ **riscv-dv generation failed** | not in the rv32imc generator config / unsupported knobs | Samuel (riscv-dv setup) |
| `hint_instr` | ✗ **asm not generated** | generator produced no `asm_test/` output | Samuel (riscv-dv setup) |

**Coverage takeaway:** riscv-dv is effectively **saturated** for this env — the
contributing profiles add ALU/jump/loop breadth but nothing new functionally beyond
a few `instr_class`/`cp_id_route` values. **Do not block coverage closure on the
failing profiles** — the inapplicable (privileged) ones should simply be excluded;
the SimX-fatal ones are Steven's; the gen-failed ones are a riscv-dv-setup tail.
The real functional gains are §1–§4, not more riscv-dv seeds.

---

## 8. Suggested order (fastest % per effort)
1. **§1 config/structural ignores** (mem_usage, spawn_cnt, bar_scope/size, lsu ld/sd) — quick, denominator drops, several coverpoints jump to 100%.
2. **§3 status_performance + divergence-depth stimulus** — biggest *reachable* chunk; coordinate a couple directed kernels with Samuel.
3. **§2 cp_id_route** (option A decode or stimulus) — the last big AXI piece.
4. **§4 scoreboard** (SB-DIR Gate-0, SB-GOT).
5. **§5 P1 covergroups**, **§3 dcr/sfu/zicond** tail.

Estimated: §1 alone → high-50s%; +§3 → ~80%; +§2 → low-90s%; tail → ~100% reachable.
