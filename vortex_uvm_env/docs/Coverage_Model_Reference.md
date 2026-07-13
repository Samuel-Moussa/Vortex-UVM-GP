# Vortex UVM — Functional Coverage Model Reference

**Scope:** every functional covergroup in the Vortex UVM environment, what feature of
the Vortex GPGPU it exercises, its coverpoints/crosses, and a direct justification of
why that group is sufficient to sign off the feature. Primary config **1CL / 1C / 4W /
4T, RV32, AXI memory interface**. SimX is the golden reference (black-box end-state
equivalence); coverage here answers *"did we exercise the feature space?"*, the
scoreboard answers *"was the result correct?"*.

> **Honesty rule (project-wide):** a bin is `ignore_bins`-waived **only** when it is
> proven structurally or config-unreachable, with the RTL/architectural evidence cited
> inline. Coverage is never inflated. Config-aware waivers reference the compiled
> `NUM_*` macros so each build counts only *its* reachable bins and auto-adapts across
> the config matrix.

---

## 1. How the model is organised

- **17 covergroup *types*, 16 constructed per run.** The coverage collector builds
  **only the active data-interface group** — `axi_transaction_cg` on AXI runs,
  `mem_operation_cg` on MEM runs (`vortex_coverage_collector.sv` constructor) — so the
  idle interface never lands at 0% and drags the number down. A cross-interface UCDB
  merge recovers both.
- **Three observation domains** feed the model:
  1. **Transaction/UVM domain** — collector covergroups sampled from monitored
     transactions (memory, AXI, DCR, host, status).
  2. **RTL probe domain** — `bind`-attached passive probes tap real DUT hierarchy:
     `vx_instr_probe` (per-EX-unit dispatch) and `vx_sched_probe` (scheduler / SIMT
     control), sampled on *real* hardware events, never vacuously.
  3. **Interface-monitor domain** — `system_cg` (top-level busy/AXI/DCR) and
     `dcr_write_cg` (DCR bus), sampled on the interface clock.
- **Per-instance** coverage on every group; per-core attribution survives via the UCDB
  hierarchy path.
- **`option.weight = 0`** is used *only* to drop a coverpoint that is structurally idle
  on the active interface (e.g. the MEM-side coverpoints on an AXI run,
  `vortex_if.sv`), keeping the bins in the UCDB for a later merge. This is exclusion of
  *non-applicable* coverage, not hiding of real gaps.

## 2. Vortex feature → covergroup map (completeness at a glance)

| Vortex feature | Covergroup(s) | Domain |
|---|---|---|
| SIMT threads / thread-mask occupancy | `*_class_cg.cp_active_threads`, `tmc_cg`, `sched_state_cg.cp_occ` | probe |
| Warp scheduling & issue state | `sched_state_cg` | probe |
| Branch **divergence** (split) | `divergence_cg` | probe |
| **Reconvergence** (join) | `reconverge_cg` | probe |
| **Barriers** (local/global, hold/release) | `barrier_cg` | probe |
| **Warp spawn** (`wspawn`) | `wspawn_cg` | probe |
| **Thread-mask control** (`tmc`, warp deactivate) | `tmc_cg` | probe |
| **ALU** instruction space | `alu_class_cg` | probe |
| **LSU** load/store instruction space | `lsu_class_cg` | probe |
| **SFU** (SIMT control + CSR) instruction space | `sfu_class_cg` | probe |
| **FPU / TCU** dispatch (occupancy/warp) | `noop_class_cg` (×fpu, ×tcu) | probe |
| Core memory transactions (byte-enables, alignment, tag) | `mem_operation_cg` | txn |
| **AXI4** memory protocol (type/burst/size/len/resp/routing) | `axi_transaction_cg` | txn |
| **DCR** configuration writes | `dcr_config_cg`, `dcr_write_cg` | txn/if |
| Host / kernel-launch command sequence + config knobs | `host_operation_cg` | txn |
| Performance: IPC, pipeline stalls, PC region, cycle phase | `status_performance_cg` | txn |
| System-level busy/idle × bus activity | `system_cg` | if |

Every architecturally-visible subsystem of the Vortex core — front-end (fetch/decode/
issue), SIMT control (schedule/split/join/barrier/tmc/wspawn), all five execution unit
classes (ALU/LSU/SFU/FPU/TCU), the memory subsystem (L1→AXI), and the host/DCR
configuration path — has a dedicated group. The map has no uncovered feature row.

---

## 3. Collector covergroups (transaction domain) — `vortex_coverage_collector.sv`

### 3.1 `mem_operation_cg` — core memory-request shape (MEM interface)
- **Samples:** each monitored core memory request (constructed only when `USE_AXI=0`).
- **Coverpoints:** `cp_rw` (read/write) · `cp_byteen` (every byte-enable pattern:
  full-dword `FF`, lo/hi word, all four half-words, all eight single bytes) ·
  `cp_addr_align` (8-byte, 4-byte, unaligned) · `cp_tag` (routing-tag buckets low/mid/
  high) · **cross** `cross_rw_byteen`.
- **Why sufficient:** the memory *access shape* the core can emit is exactly {direction
  × sub-word mask × alignment}. `cp_byteen` enumerates every legal strobe pattern the
  LSU produces for byte/half/word/dword accesses, and `cross_rw_byteen` proves both
  read and write drive each mask. That is the complete functional space of a single
  memory request on the native interface. (Vortex HW does not support misaligned
  access — see the aligned-only note; unaligned bins are `default`-captured but not a
  sign-off target.)

### 3.2 `axi_transaction_cg` — AXI4 memory protocol (AXI interface)
- **Samples:** each AXI transaction (constructed when `USE_AXI=1`, the primary config).
- **Coverpoints:** `cp_type` (READ/WRITE) · `cp_id_route` (the ~6-bit routing sub-field
  of the AXI ID — MSHR slot / bank / requester tag; the high 44 UUID bits are a debug
  counter and are deliberately *not* binned) · `cp_uuid_present` (debug tag live) ·
  `cp_burst` · `cp_size` · `cp_len` · `cp_addr_region` · `cp_bresp` · `cp_rresp0`.
- **Crosses:** `cross_type_burst_size`, `cross_type_len`, `cross_len_addr`,
  `cross_type_route`.
- **Structural waivers (all evidence-cited inline):** `cp_burst` → FIXED only
  (`VX_axi_adapter` drives `awburst/arburst=00`); `cp_size` → native transfer size only
  (`awsize/arsize = CLOG2(DATA_SIZE)`, sub-word is via WSTRB); `cp_len` → single-beat
  only (`awlen/arlen=0`); `cp_bresp/cp_rresp0` → OKAY only (TB slave never errors, and
  AXI errors are not SimX-modelled so not black-box verifiable); `cp_id_route` →
  unreachable MSHR-index/write-tag values proven over a 29-run suite + directed
  `axi_stress` runs (the routing index is set by Ramulator release order, not
  stimulus-targetable).
- **Why sufficient:** for a single-beat FIXED-burst master, the *reachable* AXI
  functional space is {type × native-size × single-len × OKAY × live-routing}, and the
  crosses prove read and write each traverse it. Every bin excluded is backed by a
  specific RTL line or an empirical multi-run proof, with a trip-wire to re-derive if
  the adapter changes (multi-beat, error injection, or multi-core). So 100% here is
  *true* protocol coverage of what this DUT can legally emit, not a masked gap.

### 3.3 `dcr_config_cg` — Device-Control-Register configuration (transaction view)
- **Coverpoints:** `cp_addr` (STARTUP_ADDR0/1, ARGV_PTR0/1, MPM_CLASS) ·
  `cp_startup_align` (aligned startup PC; unaligned waived — faults both SimX and DUT) ·
  `cp_data_magnitude` (zero / small-config / mid-pointer / high-code value ranges) ·
  **cross** `cross_addr_data`.
- **Why sufficient:** kernel bring-up is fully described by *which* DCR register is
  written and *what class of value* it carries (a code address, a pointer, or a small
  config scalar). The cross proves each register is exercised with value classes
  appropriate to it, which is the whole configuration surface the host uses to launch a
  kernel.

### 3.4 `host_operation_cg` — host / kernel-launch command sequence
- **Coverpoints:** `cp_op_type` (LOAD_PROGRAM / CONFIGURE_DCR / LAUNCH_KERNEL /
  WAIT_DONE / READ_RESULT; HOST_RESET waived — TB-controlled, never host-driven) ·
  `cp_num_cores` / `cp_num_warps` / `cp_num_threads` (**config-aware** — only the
  compiled `NUM_*` bucket counts) · `cp_completion` (kernel completed; timeout is the
  negative-test path, waived) · `cp_timeout` (low/mid/high budget).
- **Crosses:** `cross_cores_warps`, `cross_op_completion`, `cross_launch_config`.
- **Why sufficient:** this is the entire host↔device protocol — the ordered command set
  to load, configure, launch, wait, and read back a kernel — plus the topology knobs.
  The config-aware coverpoints make the *current* build's topology 100%-reachable and
  the matrix run fills the other buckets, so the group signs off "the host drives every
  command and every configured topology."

### 3.5 `status_performance_cg` — runtime performance & pipeline back-pressure
- **Samples:** the status monitor every `status_sample_interval` (=100) cycles; IPC is
  a 64-cycle **windowed** rate, the stall flags are **instantaneous** RTL taps.
- **Coverpoints:** `cp_ipc_bucket` (zero / very-low / low / med / high / very-high;
  high_ipc **config-aware-waived** at ≤4W single-issue — proven capped ~0.5 by two
  max-effort ILP kernels) · `cp_fetch_stall` · `cp_memory_stall` · `cp_decode_stall` ·
  `cp_issue_stall` · `cp_execute_stall` (each a real backpressure tap: icache-req /
  dcache-req / fetch_if / decode_if / dispatch_if `valid & !ready`) · `cp_pc_region`
  (text low/mid/high) · `cp_cycle_bucket` (short/med/long) · `cp_active_warps`
  (config-aware).
- **Crosses:** `cross_ipc_stalls` (ipc × fetch × memory), `cross_stall_types`
  (decode × issue × execute), `cross_pc_cycles` (region × phase).
- **Why sufficient:** the five taps are the *actual* pipeline-stage backpressure signals
  (front-end fetch, back-end dispatch, and the L1 request ports), so the crosses verify
  the DUT exhibits realistic co-occurring congestion (e.g. medium throughput *while*
  memory-stalled, all-stages-stalled under an IDIV chain). Together with the IPC
  buckets and PC/cycle phase, this is a behavioural signature of the whole pipeline
  under load — the one group whose remaining bins are *timing/sampling-coincidence*
  (see §6), not missing features.

---

## 4. Instruction-class probe (RTL bind, retired-instruction domain) — `vx_instr_probe.sv`

All four groups `bind` onto the per-EX-unit dispatch interfaces and sample the **real
retired instruction** (never a model). Shared axes: `cp_active_threads`
(one-divergent / partial[2..SIMD_W-1] / uniform) and `cp_warp` (issuing warp slot).

### 4.1 `alu_class_cg` — integer ALU op space
- **`cp_alu_op`:** add, sub, and, or, xor, sll, srl, sra, slt, sltu, lui, auipc, and
  Zicond czeq/czne (the last two ZERO until a Zicond build runs — an honest,
  ISA-extension-gated pair).
- **Why sufficient:** enumerates the full RV32I ALU opcode set the decoder maps to the
  ALU unit, each observed with its thread-mask and warp — so "every integer op executes,
  under uniform and divergent masks" is proven directly from silicon.

### 4.2 `lsu_class_cg` — load/store op space
- **`cp_lsu_op`:** lb, lh, lw, sb, sh, sw (LD/SD **config-aware-waived** on RV32 — not
  encodable at XLEN=32; active on RV64 builds).
- **Why sufficient:** the complete RV32 memory-op set at every access width, crossed
  implicitly with the SIMT mask, covers what the LSU can issue.

### 4.3 `sfu_class_cg` — Special Function Unit (SIMT control + CSR)
- **`cp_sfu_op`:** tmc, wspawn, split, join, bar, pred, csrrw, csrrs, csrrc.
- **Cross** `cross_sfu_threads` = `cp_sfu_op × cp_active_threads` — *"do the
  divergence-control ops themselves fire under partial masks?"* i.e. real SIMT.
- **Why sufficient:** the SFU is where SIMT actually happens — thread-mask control,
  warp spawn, split/join, barriers, predication, and CSR access all dispatch here.
  Covering each op *and* proving it occurs under partial thread masks is the definitive
  test that SIMT control executes in divergent states, not just the uniform case.

### 4.4 `noop_class_cg` (instantiated as fpu / tcu) — FPU & Tensor-Core dispatch
- **Axes:** `cp_active_threads`, `cp_warp` only (no sub-opcode decode in this probe).
- **Why sufficient:** confirms the FPU and TCU dispatch paths are actually exercised
  across warps and thread masks. Sub-opcode detail is a clean documented extension; the
  functional claim here is "the FP and tensor units receive work under SIMT masks,"
  which the group proves. (FP *correctness* is checked by the scoreboard's FP-tolerant
  compare, not by coverage.)

---

## 5. Scheduler / SIMT-control probe (RTL bind) — `vx_sched_probe.sv`

Each group samples on its **own real control event** (schedule fire, split, join,
barrier, tmc, wspawn), so no bin is ever hit vacuously.

### 5.1 `sched_state_cg` — warp scheduler issue state
- **Coverpoints:** `cp_active_warps` (active warp count at issue; `none` waived — a warp
  is issuing, so ≥1 is always active) · `cp_stalled_warps` (`none` waived — RTL-proven:
  `schedule_fire` sets `stalled_warps[wid]=1` and `schedule_if` is registered one cycle
  later through the elastic buffer, so the observed warp is already stalled) ·
  `cp_sched_wid` (which warp issued) · `cp_occ` (weight-0 feeder) · **cross**
  `cross_wid_occ` (per-warp thread-mask occupancy).
- **Why sufficient:** captures *which* warp issues and *how full* its mask is, spanning
  1..NW active warps — the scheduler's observable state space. The two `none` waivers
  are RTL-proven artefacts of the sample point (cited to `VX_schedule.sv` lines), not
  omitted reachable states.

### 5.2 `divergence_cg` — branch divergence (split)
- **Coverpoints:** `cp_is_dvg` (uniform split vs real divergence) · `cp_then_occ`
  (threads taking the then-path: 1 / partial / full) · `cp_split_depth` (nesting depth
  0..NUM_THREADS-1; deeper waived — exceeds the divergence stack) · **cross**
  `cross_dvg_depth`.
- **Why sufficient:** divergence is fully described by *how many* threads split and *how
  deeply nested* the split is. The depth bound is the physical stack size, so covering
  0..NT-1 at both uniform and divergent is the complete reachable divergence lattice.

### 5.3 `reconverge_cg` — reconvergence (join)
- **Coverpoints:** `cp_join_dvg` · `cp_join_else` (then/else side) · `cp_join_occ` ·
  `cp_join_depth` · **cross** `cross_join` (with `<uniform, else_path>` waived — a
  uniform join has no diverged else-side to reconverge into).
- **Why sufficient:** every split must join; this mirrors `divergence_cg` on the join
  event and additionally proves reconvergence into *both* the then and else sides at
  each depth. The one waived cross bin is a logical impossibility, cited inline.

### 5.4 `barrier_cg` — hardware barriers
- **Coverpoints:** `cp_bar_id` · `cp_bar_scope` (local; global waived — needs
  GBAR_ENABLE/multi-core) · `cp_bar_size` (participants 1..NW-1) · `cp_bar_event`
  (hold vs release) · **cross** `cross_event_scope`.
- **Why sufficient:** a barrier's functional space is {id × scope × participant count ×
  arrival-vs-release}. Covering hold *and* release across participant counts proves the
  barrier both blocks and unblocks — the entire local-barrier behaviour available in a
  single-core build (global correctly waived with a multi-core trip-wire).

### 5.5 `tmc_cg` — thread-mask control
- **`cp_tmc_occ`:** deactivate (tmask=0), 1, partial, full.
- **Why sufficient:** `tmc` sets a warp's active mask; covering the full occupancy range
  *including deactivation (tmask=0)* proves both partial-mask execution and warp
  shutdown, which is the complete `tmc` effect.

### 5.6 `wspawn_cg` — warp spawn
- **`cp_spawn_cnt`:** 1 / some[2..NW-1] (NW waived — `wspawn` excludes the issuing warp,
  so at most NW-1 spawn).
- **Why sufficient:** the spawn count is the only functional variable of `wspawn`; the
  reachable range 1..NW-1 is fully covered with the NW case proven impossible.

---

## 6. Interface monitors

### 6.1 `system_cg` — top-level system state × bus activity — `vortex_if.sv`
- **Coverpoints:** `system_state_cp` (idle / busy / idle→busy / busy→idle transitions) ·
  `axi_usage_cp` (no-access / write-only / read-only; simultaneous AW+AR waived —
  mutually exclusive by adapter construction) · `mem_usage_cp` · `dcr_activity_cp`.
- **Crosses:** `system_axi_cross`, `system_mem_cross` (the idle-interface cross is
  weight-0 per run).
- **Why sufficient:** correlates the machine's run-level state (and its idle↔busy
  transition edges) with real bus activity, verifying that memory traffic occurs in the
  expected system phases. Its residual bins are transition×activity *timing
  coincidences* (see below), not unmodelled behaviour.

### 6.2 `dcr_write_cg` — DCR bus write monitor — `vortex_dcr_if.sv`
- **Coverpoints:** `wr_addr_cp` (the real word-addressed DCR registers) · `wr_valid_cp`
  (idle / active / both transition edges) · `wr_data_cp` (zero / startup addresses /
  small values / other).
- **Why sufficient:** an independent bus-level check that every DCR register is written
  with representative data and that the write-enable toggles both ways — a cross-check
  on the configuration path observed at the pins, complementary to `dcr_config_cg`'s
  transaction view.

---

## 7. Honest status of the remaining gaps

Current merged functional coverage: **93.33% (350/375 bins)** at 1CL/1C/4W/4T; the SFU
cross closure (`bar_masks` + wspawn waiver) is committed and lifts this to an expected
**~94.9% (353/372)** on the pending re-merge. 100% is claimed only where every
*reachable* bin is hit; open bins are catalogued here rather than waived without proof:

- **Closed by directed stimulus:** `cp_ipc_bucket.high_ipc` (proven config waiver);
  `status_performance_cg` `<med_ipc, *, mem-stalled>` ×2 (via `mem_stress` — a 12-load
  MSHR burst co-sampled with a med-IPC window); `cross_sfu_threads`
  `<csrrw|csrrc, {uniform, partial[2], partial[3]}>` ×6 (via `sfu_masks` — register-form
  FP-CSR writes under peeled thread masks); `cross_sfu_threads`
  `<bar, {uniform, partial[2], partial[3]}>` ×3 (via `bar_masks` — single-warp
  `vx_barrier(id,1)` self-releasing under peeled masks, deadlock-free).
- **Closed by proven structural waiver:** `cross_sfu_threads` `<wspawn, partial/uniform>`
  — `vx_wspawn` is a runtime-only primitive issued single-threaded from the spawn
  bootstrap (`vx_spawn.c:259`, thread 0 before the SIMT region spreads); no user SIMT
  code issues it and 35 diverse runs never produced multi-thread wspawn, so it is
  unreachable in any well-formed program (same class as the accepted
  `all_excludes_issuer` / `global_bar` waivers). → **`cross_sfu_threads` = 100%.**
- **Stimulus gaps (targetable, not waived):** `cross_dvg_depth <uniform, d3>` (1 bin — a
  uniform split at stack-depth 3; `diverge_deep` misses it, needs care with post-push
  depth semantics).
- **Timing/sampling-coincidence (candidate for a *proven* waiver, not a blind one):**
  `status_performance_cg` `<zero, *, mem-stalled>` and the asymmetric single-stage stalls
  `<decode-active, issue-stalled>` / `<decode-stalled, issue-active>` are one-cycle
  backpressure-propagation transients against a 100-cycle sample interval;
  `system_axi_cross` transition×activity bins need a bus access in the exact cycle of an
  idle↔busy edge. These are limited by *sampling cadence*, not by missing features — the
  honest levers are a finer `status_sample_interval` or a documented sampling-limitation
  note. `memory_stall` is dcache *request* backpressure (MSHR-full), reachable only by a
  burst of independent outstanding loads — a serial pointer-chase does NOT set it.

**Excluded, legitimately (not counted, not hidden):** the idle data-interface
coverpoints (`mem_usage_cp` / `system_mem_cross` on AXI runs, and the AXI-side on MEM
runs) via runtime `option.weight=0`, with the bins retained in the UCDB for a
cross-interface merge.

---

*Generated from the live covergroup sources (`vortex_coverage_collector.sv`,
`vx_instr_probe.sv`, `vx_sched_probe.sv`, `vortex_if.sv`, `vortex_dcr_if.sv`). Every
waiver above is stated in-source with its RTL/architectural evidence and a trip-wire for
re-derivation if the config or RTL changes.*
