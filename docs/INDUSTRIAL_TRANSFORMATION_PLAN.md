# Vortex UVM — Industrial-Grade Transformation Plan

**Owner:** Samuel · **Status:** planning (opus) · **Created:** 2026-07-14
**Decision (2026-07-14):** reference strategy = **RVVI lockstep**, golden = **SimX functional emulator (primary) + Spike (independent base-ISA audit, secondary)**; sequencing = **depth-first (flagship lockstep first)**; scope = **full transformation, planned end-to-end here**.
**Revision (2026-07-14, after reading `Vortex/sim/simx/` source):** SimX's functional `Emulator` already steps instruction-by-instruction, returns an RVVI-shaped `instr_trace_t`, holds full SIMT arch state, and reads back destination values — it is ~80% of an RVVI golden and is cleanly decoupled from the timing model (`core.cpp:223` consumes `emulator_.step()`). Therefore the **primary** lockstep golden is SimX-functional (it natively models SIMT + the 6 custom ops, which Spike cannot). Spike demotes to a **secondary independent cross-check** on the base ISA.
**Team (2026-07-14):** Samuel works solo — all lanes are his (incl. SimX/DPI C++). No hand-off or sign-off gating in this plan.

---

## ▶ RESUME HERE (session-continuity block — UPDATE AT EVERY PHASE BOUNDARY)

> Samuel `/compact`s every phase to save credits. This block is the cold-start entry point: a fresh session reads it and continues without re-deriving. Keep it current — when a milestone lands, move the marker and record what changed.

**CURRENT MILESTONE: Phase A → A0 DONE ✅ · A1(a) divergence DONE ✅ · A1(b) multi-core DONE ✅. NEXT: A1(c) rvvi_if migration + A1(d) 2CL/suite/no_fence first-divergence.**

**A1 progress (branch `industrial_transformations`):**
- **A1(a) divergence — DONE:** `diverge_uni3` (nested asymmetric 3v1→2v1→1v1, heavy partial masks) `+LOCKSTEP` → **2668/2668 matched, 0 mismatches, PASSED.** uuid-group aggregation + tmask-union handle divergence with no code change.
- **A1(b) multi-core cid — DONE:** DUT `uuid` embeds flat `CORE_ID` (OBS-006 / `VX_uuid_gen.sv:40`), and `CORE_ID` is flat-global across clusters (`VX_socket.sv:227` + `VX_cluster.sv:132`), matching SimX `rec.cid`. Scoreboard now derives `(cid,wid)` from the uuid (`cid_of_uuid`/`wid_of_uuid`) — no probe/RTL change. All lockstep edits audited config-generic for ANY NC/NCL/NW/NT (fixed wid mask → `(1<<NW_BITS)-1` for non-power-of-2 NW). See `MEMORY.md` config-generic-edits.
- **CONFIG-MATRIX VALIDATED (empirical, all PASSED, 0 field-mismatch, 0 orphans):** 1CL/1C/4W/4T (1035/1035) · 1CL/2C/4W/4T (2 cores, 1801/1801) · **2CL/2C/4W/4T (4 cores across 2 clusters, 3333/3333 — cluster term of CORE_ID proven)** · 1CL/1C/2W/2T (855/855, nw_bits=1) · 1CL/1C/8W/4T (1423/1423, nw_bits=3). Axes covered: NCL∈{1,2}, NC∈{1,2}, NW∈{2,4,8}, NT∈{2,4}. Only unproven path = non-default `SIMD_WIDTH<NUM_THREADS` multi-beat sid-split (standard builds set `SIMD_WIDTH=NUM_THREADS` → single beat).
- **A1(c) NEXT:** migrate the D2a package-queue hand-off → **D2b `rvvi_if` + monitor** (core-v-verif `uvma_rvvi` style) — an SV interface bound at the probe, a UVM monitor publishing RVVI transactions, scoreboard subscribes via analysis port (replaces the global package queue).
- **A1(d):** run lockstep across the directed suite at 2CL/2C/4W/4T; use it to pinpoint the 2CL `no_fence`/`full_interrupt` FIRST-divergence instruction (the original motivation — currently "Future Work — needs lockstep"). Verify DUT/SimX flat-cid numbering agrees at ≥2 clusters (1CL/2C proved it at socket level; 2CL exercises the cluster term of the CORE_ID formula).

**A0 RESULT (verified in sim, branch `industrial_transformations`):** per-instruction RVVI-style lockstep working on `vecadd_lite` 1CL/1C/4W/4T → **1035/1035 architectural writebacks matched, 0 orphans, 0 field mismatches, TEST PASSED, 0 UVM_ERROR.** Injection (`+LOCKSTEP_INJECT`) caught at exact uuid/PC/lane (`DUT=5 vs SimX=4`) = non-vacuous. Default (no `+LOCKSTEP`) path byte-identical (lockstep SB not built), PASSED. Loads (187) + perf-CSRs (62) correctly scoped out of the data compare.

**What was built (12 files, all in main repo — Vortex/ is tracked, not an active submodule):**
- **NEW:** `lockstep_pkg.sv` (RTL↔class hand-off: global `dut_retire_q[$]` + `lockstep_en`/`inject_en` gates, macro-free struct), `lockstep_scoreboard.sv` (`check_phase` comparator + 4-way taxonomy + report).
- **MODIFY (env):** `vx_commit_probe.sv` (passive per-beat capture on `+LOCKSTEP`, `to_fullPC`, `+LOCKSTEP_INJECT` 1-bit flip; `LS_LANES` derived from signal width — `` `SIMD_WIDTH `` NOT visible in probe compile unit), `vortex_config.sv` (`rand bit enable_lockstep`, `+LOCKSTEP` forces `simx_enable`), `vortex_env.sv` (gated `m_lockstep_scoreboard`), `vortex_env_pkg.sv` (import+include), `flists/uvm_env.flist` (lockstep_pkg before probe), `scripts/simulate.sh` (`LOCKSTEP`/`LOCKSTEP_INJECT` env→plusarg).
- **MODIFY (SimX golden export — the W1 record was extended, NOT reused as-is):** `Vortex/sim/simx/simx_cosim_record.h` (+`fu_type`,+`is_volatile`, repurposed pad bytes → zero ABI change), `core.cpp` (populate both), `execute.cpp` (set `volatile_result` for MPM CSR range `0xB00-B1F`/`0xB80-B9F`), `instr_trace.h` (+`volatile_result` field). Bridge: `ref_model/simx_dpi.cpp` + `simx_pkg.sv` (`simx_cosim_pop` gains `fu_type`,`is_volatile` outputs + `simx_retire_s` fields).

**KEY DESIGN CORRECTIONS vs the original locked spec (all forced by real sim evidence — record these, they matter for A1):**
1. **Alignment is by `uuid`, NOT retire-position.** The DUT retires OUT of program order (execution-unit latency; commit arbiter takes whoever's ready — observed uuid `0x59` after `0x5a/0x5c`). SimX retires in strict program order. `uuid` = per-warp issue counter = program order, so we **sort each DUT per-warp FIFO by uuid** then compare position-wise vs SimX. (The spec's "k-th vs k-th retire" was wrong.)
2. **SimX does NOT populate `uuid` (always 0).** So uuid genuinely can't be the cross-key; it's reported (accept-c answer = schemes diverge) and per-warp program order is the alignment key. `wid` embeds in high uuid bits on the DUT side (e.g. `0x2_0000_00ee` = wid2) — sorting within a per-`(cid,wid)` bucket is still correct.
3. **Aggregate DUT records by `uuid`, NOT `sop/eop`.** One instruction emits MULTIPLE commit records with the same uuid: SIMD-beat splits AND **load partial-mask writebacks** (LSU commits lanes as memory responses arrive — observed one `lw` as two records, overlapping masks `0xd`/`0xe`). A single sop/eop in-progress slot corrupts on interleave. Group-by-uuid (union tmask, place active lanes) → one merged retirement per uuid, 1:1 with SimX. `LS_LANES=4`, `ISSUE_WIDTH=1` for this config (single beat normally).
4. **Load data is NOT observable at the commit-arb probe** (async LSU response path → `data` stale/address). ALL data mismatches were `lw`. Scope loads out of the DATA compare (keep PC/rd/ordering); load correctness = end-state memory compare (passes). Identified via SimX `fu_type==LSU`.
5. **Performance-counter CSRs are model-divergent by definition** (`mcycle`/`minstret`/`mhpmcounter*` — timing DUT vs functional SimX, `1167` vs `1166`). SimX flags `is_volatile`; excluded from DATA compare, as RVVI/core-v-verif do.

**A1 EXECUTION (next — refine at phase start):** extend beyond `vecadd_lite`: (a) run divergent/multi-thread kernels (partial tmask, IPDOM split/join) through lockstep — the uuid-group aggregation + tmask-union should already handle divergence; verify. (b) 2CL/multi-core: DUT-side `cid` is hardcoded 0 in the probe (A0 single-core TODO) — add real per-core attribution (parse `VX_commit` INSTANCE_ID or add a bind param) so `(cid,wid)` keys are correct at ≥2 cores/clusters. (c) migrate the D2a package-queue hand-off → **D2b `rvvi_if` + monitor** (core-v-verif `uvma_rvvi` style). (d) run the lockstep across the existing directed suite (find first-divergence on the 2CL `no_fence` case — the original motivation). Then A2→A6 per §A.4.

**NEXT ACTION:** commit A0 on branch `industrial_transformations`; then start A1(a) — pick a divergent kernel already in `run_suite` and run it `+LOCKSTEP`, confirm tmask-partial retirements align.

---

## 📊 CONSOLIDATED PROJECT CONTEXT & STATUS (SINGLE SOURCE OF TRUTH — distilled from ALL docs)

> This section absorbs the key facts from every doc under `docs/` and `vortex_uvm_env/docs/` so **this file is the only doc you need** for status + direction. Source docs stay for deep detail (indexed at the end). Update this section when status changes.

### Identity & config
Vortex GPGPU (Georgia Tech), open-source RISC-V **RV32IMAF + 6 SIMT ops** (`wspawn/tmc/split/join/bar/tex`; tex disabled). **Primary config 1CL/1C/4W/4T RV32 AXI**; scale config 2CL/2C/4W/4T. RTL pin `7a52ee5`. QuestaSim 2021.2_1, Ubuntu 22.04 WSL. **Method = black-box end-state equivalence vs SimX golden (DPI); coverage probes observe, never gate.** Samuel works **solo** (all lanes).

### Verified current status (2026-07-10)
| Metric | 1CL (primary) | 2CL (scale) |
|---|---|---|
| Functional (type) | **100%** | 92.48% |
| Line | 97.05% | 96.19% |
| Branch | 91.16% | 89.68% |
| Condition | 76.35% | 69.57% |
| Toggle | 78.65% | 74.25% |
| Assertion | 93.79% | 73.96% |
| Directive | 100% | 100% |
| **Total** | **91.00%** | **85.16%** |
| Tests | 43/43 pass | 40/42 (2 SimX-seed) |
- **Gate-0 CLOSED**; bidirectional scoreboard + **2 live fault-injection guards** (wrong-value + dropped-store) stay RED on injection.
- **Only unmet founding goal: toggle > 90%** (structural ceiling ~78%; write-through dead write-data + constant PC/addr high bits; documented, NOT gamed).
- **Scoreboard reality:** ~29 tests real byte-exact DUT-vs-SimX; ~10 riscv-dv + 3 regression **UNVERIFIABLE** (SimX aborts); 2 liveness-only. **0 failures.**

### In-tree / DONE — do NOT rebuild
5 agents (axi/dcr/host active, status passive, mem active-or-passive) · virtual sequencer · DPI-C scoreboard · coverage collector · plusarg config · Gate-0 (C1/C2/C3/T4/I1/I2/I5) · P1 commit-probe bind · INV-1/INV-2 closed · functional cov 100% (1CL) · config-aware exclusion generator + 2 banks · **AXI SVA layer ~15–18 props all-pass (B3-AXI done)** · **W1 lockstep golden export (`simx_retire_t`+cosim DPI, `554080e`)** · riscv-dv pipeline (rv32im).

### Architecture (distilled)
Hierarchy `Vortex_axi → VX_axi_adapter + Vortex → cluster → socket → (L2 cache_cluster + core)`, 183 RTL modules. Core = 5-stage in-order RISC-V + SIMT (warp scheduler w/ 4 masks, IPDOM divergence stack, banked GPRs, HW barrier); execute = ALU/FPU/LSU/SFU/TCU. Cache = multi-bank non-blocking **write-through**, per-bank MSHR (priority-encoder slot alloc), virtual ports, early-full deadlock mitigation. **AXI role inversion: DUT master, TB slave; `mem_model` backs responses.**

### SimX golden — status & limits
Cycle-level DSE model doubling as functional golden; **functional `Emulator` decoupled from timing** (`core.cpp:223` consumes `step()`). **FIXED co-sim bugs:** reset-place · startup-addr-from-data · crash-guard(→`-3` UNVERIFIABLE) · per-config build · CSR SIGABRT · RVC decode · missing `EXT_TCU`. **INTRINSIC limits (lockstep targets):** aborts on RVC/random/exotic (**69 `std::abort` in decode/execute**) · 2CL `no_fence`/`full_interrupt` per-cluster memory-ordering divergence (UNVERIFIABLE, NOT a DUT bug) · RV32-D no golden. **SimX is NOT independent of the DUT** (same team) → Spike as base-ISA audit (secondary).

### RTL-cited waiver facts (for sign-off)
- `cp_id_route`: MSHR slot = priority-encoder lowest-free, timing-driven (`VX_cache_mshr.sv:125-132`).
- toggle write-data dead: writethrough excludes writes (`VX_cache_mshr.sv:242-247`).
- `high_ipc` ceiling: warp stalled schedule→decode L≈8cy (`VX_schedule.sv:202`); IPC≈min(ISSUE,NW/L). Corroborated **CARRV'19 §6.3**.
- `wspawn` single-warp bootstrap (`VX_schedule.sv:126`); corroborated **CARRV'19 §5.3** (SW/HW warp model).
- `is_global` barrier config-keyed to ≥2 cores (`VX_schedule.sv:168`).
- weak coherence → 2CL `no_fence` UNVERIFIABLE (**MICRO'21 §4.1.4**).

### Founding plan status & M1–M4 → transformation mapping
Founding `VERIFICATION_PLAN.md` met **except** toggle>90% + a few planned tests (`cache_coherence`→T-cache, exception→T-exc). **Formal was OUT of scope → our B4 extends scope.** The founding **"Future Work M1–M4" IS this transformation** (`Vortex_UVM_Final_Plan.md:163`): **M1=Phase A lockstep · M3=B3 SVA extension · M2=B6 per-unit scoreboards · M4=cache/hazard.** We are executing the project's own parked white-box roadmap.

### Open coverage crumbs (Phase C, cheap real gains)
Wire unused `dcr_random_seq` + AXI sequences · **Zicond build** (`-march=…zicond`) for `czeq/czne` · make collector fully config-aware (still 1CL-hardcoded in places) · `cp_num_clusters` unused.

### Source-doc index (deep detail)
- Coverage: `docs/Coverage_Report_2026-07-10.md`, `docs/Coverage_Model_Reference.md`
- AXI SVA: `docs/AXI_SVA_report.md` · 2CL divergence: `docs/investigations/SimX_2CL_no_fence_divergence.md`
- Founding/plans: `docs/VERIFICATION_PLAN.md`, `vortex_uvm_env/docs/Vortex_UVM_Final_Plan.md`, `vortex_uvm_env/docs/Vortex_UVM_Plan_Current.md`
- Fixes/investigations: `docs/fixes/` (fix_01–18, INV1/INV2, HANDOVER_*), `docs/fixes/HANDOVER_Steven_simx_review.md` (SimX edits)
- Architecture record: `vortex_uvm_env/docs/vortex_uvm_full_report.md` · Papers: MICRO'21 + CARRV'19 (in `/mnt/d/GP_Project/DOCs/`)

---

> This document is the roadmap to take the Vortex UVM environment from a strong end-state-equivalence bench to a genuinely industrial-grade verification environment (OpenHW `core-v-verif` methodology class). Phase A (the checking-depth flagship) is detailed to execution level; Phases B–D are detailed enough to execute later, refined at each phase boundary.

---

## 0. Target state — capability gap map

| Capability | Today | Industrial target | Phase |
|---|---|---|---|
| Checking depth | End-state memory equivalence only | **Per-instruction lockstep (RVVI step-and-compare)** | A |
| Golden reference | SimX (perf/DSE model, aborts → UNVERIFIABLE bucket) | **Spike** spec-complete ISS for correctness; SimX for perf only | A |
| Assertions | Few TB asserts; DUT `RUNTIME_ASSERT`s unused | SVA protocol layer + harvest DUT asserts + **formal** on control blocks | A/B |
| Registers | Raw DCR driver | **RAL** (uvm_reg) for DCR/CSR | B |
| Scoreboard | shadow_memory + mem_model (dual) | Single `mem_model` source of truth | B |
| Coverage | Func 100%, code ~91/85% | + assertion coverage + **traceable coverage plan** + auto-closure | C |
| Stimulus | Directed + riscv-dv (12 seeds) | Layered/virtual sequences + **CDV feedback** + seed farm | C |
| Config | Randomizable, elaboration-checked | + full **config-matrix** sweep sign-off | C |
| Regression/CI | Manual serial `run_suite.sh` | **CI**, parallel + **graded** regression, results DB, trend | D |
| Sign-off | Manual reports | Automated merged sign-off + **requirements traceability matrix** + reproducibility | D |

**Principle preserved:** black-box methodology stays honest. Lockstep *adds* a defined-domain checker; it does not fabricate verdicts. Anything outside the golden model's defined domain stays classified, not force-compared.

---

## Phase A — Checking depth: RVVI lockstep + Spike (FLAGSHIP)

### A.1 Why this is the industrial jump
Today the only checker is final-memory-image equality vs SimX. Industrial RISC-V verification (core-v-verif, Imperas) compares **every retired instruction** — PC, opcode, architectural writeback — against a stepping golden model, catching divergence at the exact instruction and retiring the UNVERIFIABLE bucket. Two of our biggest open items collapse into this: the **2CL `no_fence` first-divergence instruction** (currently "Future Work — needs lockstep") and the **~10 riscv-dv/regression UNVERIFIABLE runs** (SimX aborts; Spike does not).

### A.2 Assets already present (grounding — verified in source)
- **SimX functional golden, already ~80% there:** [emulator.h](../Vortex/sim/simx/emulator.h) `Emulator::step()` (line 93) returns an `instr_trace_t*`; `warp_t` (lines 54-67) holds full SIMT arch state (ireg/freg files, `ipdom_stack`, `tmask`, `PC`, `uuid`); `read_dst_reg(wid, dst)` (line 107) reads back the written value. Decoupled from timing — [core.cpp](../Vortex/sim/simx/core.cpp) line 223 does `auto trace = emulator_.step();`.
- **RVVI-shaped retirement record already exists:** [instr_trace.h](../Vortex/sim/simx/instr_trace.h) `instr_trace_t` carries `{uuid, cid, wid, tmask, PC, wb, dst_reg, src_regs, fu_type, op_type, sop, eop}` (lines 46-76) + `LsuTraceData.mem_addrs` (line 35). Its `operator<<` (lines 131-156) already prints a near-identical format to the DUT trace.
- **DUT retire stream already exposed:** [VX_commit.sv](../Vortex/hw/rtl/core/VX_commit.sv) `commit_arb_if[i]` carries `{uuid,wid,sid,PC,tmask,rd,wb,data[SIMD_WIDTH],sop,eop}` (lines 164-174); passive `vx_commit_probe` already binds it; `DBG_TRACE_PIPELINE` (lines 177-191) already emits a per-instruction textual retire trace.
- **Spike (secondary/audit):** `~/riscv/bin/spike` (binary) + `core-v-verif/vendor/riscv/riscv-isa-sim` (source, patchable).
- **RVVI UVM agents to adapt:** `core-v-verif/lib/uvm_agents/uvma_rvvi` (+ `uvma_rvvi_ovpsim`) — agent/cfg/cntxt/tdefs pattern.
- **Trace-compare precedent:** `Vortex/tools/compare_dumps.py`.

### A.3 Architecture — SimX-functional primary golden, Spike secondary audit
SimX's `Emulator` natively models Vortex's SIMT execution + the 6 custom ops (`wspawn/tmc/split/join/bar/tex`). Spike is a scalar base-RISC-V ISS and cannot execute a Vortex kernel without a SIMT harness. So SimX-functional is the primary golden; Spike is an independent base-ISA cross-check.

**Two SimX workstreams (both in-scope, Samuel's lane):**
- **W1 — RVVI export:** after `emulator_.step()` ([core.cpp](../Vortex/sim/simx/core.cpp):223), serialize each retirement `{uuid, cid, wid, tmask, PC, dst_reg, dst_value = read_dst_reg(...), mem_addrs}` in a canonical RVVI record over the DPI bridge. The data already exists — this is a bounded hook, not a rewrite. **Interface spec: see Appendix W1.**
- **W2 — Abort hardening:** [execute.cpp](../Vortex/sim/simx/execute.cpp) has 23 `std::abort()` and [decode.cpp](../Vortex/sim/simx/decode.cpp) 46 — all "unknown-encoding" default branches (RVC, exotic CSRs). Replace with (a) proper handling for the fixable ones, or (b) a graceful "unsupported → return sentinel → mark UNVERIFIABLE" so one exotic instruction never crashes the whole sim. Incremental; each fix shrinks the UNVERIFIABLE bucket.

**Comparison granularity:** a Vortex warp-instruction retires `SIMD_WIDTH` lanes gated by `tmask`. Golden hart = `(core, warp, thread)`. Compare each *active* lane's `{PC, rd, wdata}` (and mem addr/data for LSU ops) between the DUT `commit_arb_if` stream and the SimX `instr_trace_t`+`read_dst_reg` stream, aligned by `uuid`.

**Spike as independence audit (secondary, later):** SimX-functional is written by the Vortex team → **not independent of the DUT** (shared assumptions ⇒ shared bugs it cannot catch). Spike, the RISC-V spec authority, cross-checks the **base-ISA subset** per-thread (where independence matters most and where SimX aborts today). Layered in after the SimX-functional lockstep works.

### A.4 Milestones

> **RECONCILED 2026-07-14 — W1 export is ALREADY BUILT** (committed `554080e` "changes in simx to verify microarch"). Present in-tree: `simx_retire_t` record ([simx_cosim_record.h](../Vortex/sim/simx/simx_cosim_record.h): uuid/cid/wid/pc/tmask/wb/is_fp/rd/sop/eop/result[32]); export hook at [core.cpp](../Vortex/sim/simx/core.cpp):229 (writeback instrs); queue in `processor_impl.h`; DPI exports `simx_cosim_pop/_pending/_clear` ([simx_dpi.cpp](../vortex_uvm_env/uvm_env/ref_model/simx_dpi.cpp):869); SV DPI **imports** + `simx_retire_s` mirror in `simx_pkg.sv:60-95`. **What's MISSING = the consumer** — nothing calls `simx_cosim_pop()`; `vortex_scoreboard.sv:83` marks lockstep "out of scope"; `vx_commit_probe` only counts (no publish path); the `simx_golden_model` component in `simx_pkg.sv` is a **dead stub** (never instantiated, `ap.write` commented out); the LIVE SimX driver is `vortex_scoreboard.sv` (`simx_init/load/dcr_write/run`). A0 is therefore *the DUT capture path + comparator + wiring*, not the export.

#### Phase-A locked design decisions (2026-07-14)
- **D1 = b + c (compose):** repurpose the dead `simx_golden_model` stub → the **golden agent** (drains `simx_cosim_pop()` after the run, publishes golden retire txns on its `ap`); add a **dedicated `lockstep_scoreboard`** comparator. Producer/checker separation. Delete the dead-stub behaviour, keep the shell.
- **D2 = a → b (staged):** A0 uses a **package-scope retire queue** the bound probe pushes to (simplest, keyed by `cid`); **A1 migrates to the professional `core-v-verif` pattern** — a bound **`rvvi_if`** driven by the probe + a UVM **monitor** obtaining the vif via `config_db` (mirrors `uvma_rvvi`).
- **D3 = post-run `uuid`-map alignment:** SimX runs to completion in one `simx_run` call and queues ALL retirements; the DUT retires live. Align by **`uuid` (instruction identity), not by cycle** — `dut_map[uuid]` built live, `gold_map[uuid]` drained after `simx_run`, compared per active lane. Both maps must drain empty (dropped/extra retirement check).
- **SimX-run coordination:** keep `simx_run` in the end-state scoreboard (path untouched); the golden agent drains the retire queue *after* it, sequenced via UVM objections — SimX is never run twice.

- **A0 — Lockstep PoC (the actual remaining work):** (1) extend `vx_commit_probe` to push each `retire_fire` record `{uuid,wid,PC,rd,wb,tmask,data[lane]}` into a package-scope queue (D2a); (2) repurpose the stub into a `simx_golden_agent` that drains `simx_cosim_pop()` post-run and emits golden retire txns; (3) a `lockstep_scoreboard` that builds `dut_map`/`gold_map` by `uuid` and compares per active lane `{PC, rd, result[lane]}`; (4) add `cfg.enable_lockstep` (+plusarg) gating so default runs are byte-identical; run `vecadd_lite`. *Accept: (a) lane-exact match to completion; (b) an injected 1-bit corruption is caught at the exact `uuid/PC/lane`; (c) **PROVE `uuid` identity aligns DUT↔SimX 1:1** (the key A0 risk — else fall back to `(wid, per-warp seq)` alignment). Reuse the existing `simx_retire_t` export as-is.*
- **A1 — Multi-thread + divergence:** compare all active lanes through split/join. SimX already models IPDOM, so this exercises the comparator's tmask/lane alignment, not new golden logic. *Accept: `diverge_lite`/`diverge_deep` match lane-exact through divergence/reconvergence.*
- **A2 — Multi-warp + wspawn + barrier + LSU mem-compare:** warp scheduling, `wspawn`, `bar` (local); extend the record with `LsuTraceData.mem_addrs` for load/store address+data compare. *Accept: `spawn_tmc_sweep`, `barrier_lite`, a memory-heavy kernel match.*
- **A3 — W2 abort hardening → retire the UNVERIFIABLE bucket:** as the ~10 riscv-dv/regression programs hit `std::abort()`, fix the encoding (RVC/CSR) or convert to graceful-unsupported. Re-run under lockstep. *Accept: each renders a real per-instruction verdict (pass or pinpointed divergence); 0 remain "UNVERIFIABLE" for handled encodings, the rest cleanly classified.*
- **A4 — 2CL first-divergence pinpoint:** run `riscv_no_fence_test` at 2CL under lockstep; report the exact first divergent instruction (closes the documented 2CL "Future Work"). *Accept: a proven SimX modeling limit or a real DUT bug, cited to an instruction + `file:line`.*
- **A5 — Harvest DUT native assertions:** route the RTL's own `RUNTIME_ASSERT`s into the UVM error count — IPDOM over/underflow ([VX_ipdom_stack.sv](../Vortex/hw/rtl/core/VX_ipdom_stack.sv) lines 50-52), MSHR integrity ([VX_cache_mshr.sv](../Vortex/hw/rtl/cache/VX_cache_mshr.sv) lines 210-217), `STALL_TIMEOUT` ([VX_schedule.sv](../Vortex/hw/rtl/core/VX_schedule.sv) line 415). *Accept: an injected violation fails the run through the UVM error gate.*
- **A6 — Spike independence audit (secondary):** cross-check the base-ISA subset per-thread against Spike on a sample of tests. *Accept: base-ISA retirements agree Spike↔SimX↔DUT; any Spike/SimX disagreement documented.*

### A.5 Effort / risk
A0 (W1 + comparator) is the critical build and de-risks the rest — because the SimX golden already steps, traces, and reads back values, A0 is mostly the DPI export hook + a `uuid`-aligned comparator, not new golden logic. A1/A2 mostly stress the comparator. A3 (W2) is incremental C++ per abort. Primary risk = `uuid`/lane alignment between the DUT commit stream and SimX retirement order (SIMT interleaving) — mitigated by aligning on `uuid` (monotonic per core) rather than cycle. A6 (Spike) is independent and can slip without blocking A0–A5.

---

## Phase B — Verification structure

- **B1 — RAL for DCR/CSR.** `uvm_reg_block` modeling DCR (STARTUP_ADDR0/1, ARGV_PTR0/1, MPM) + CSR mirror. Note DCR is **write-only** ([vortex_dcr_if.sv](../vortex_uvm_env/tb/vortex_dcr_if.sv)) → RAL gives abstraction + predicted mirror + reg coverage, **not** read-back checking (documented limitation). CSR side can use readback if a path exists. *Accept: DCR sequences issue through the reg model; reg coverage collected.*
- **B2 — Scoreboard → single `mem_model`.** *Detailed spec (from `vortex_uvm_env/docs/Vortex_UVM_Plan_Current.md` §Phase 3):* collapse `compare_all_written` to ONE `mem_model`-vs-SimX end-state compare (inherently bidirectional; `mem_model` holds real init bytes → the sub-word byte-mask hack becomes unnecessary). Migrate `.got`/POISON/FP-tolerance/inject-fault/drop-store logic into the single pass; **delete `shadow_memory`+`shadow_valid`**. **Validation gate:** full 35-run suite + BOTH negative tests (`negative_result_test`, `negative_dropped_store_test`) green, zero regression, before deleting the legacy path.
- **B3 — SVA protocol layer.** Assertions on internal elastic handshakes + the cache arbiter/MSHR + AXI. Formalizes the "reachable-but-not-hit" bins (e.g. `b_valid_stable`, `r_data_stable`).
- **B4 — Formal on control blocks.** Questa formal / JasperGold on the cache arbiter (priority: replay>mem-rsp>flush>core, [VX_cache_bank.sv](../Vortex/hw/rtl/cache/VX_cache_bank.sv) lines 204-207) and MSHR allocator. Formal unreachability > our current structural waiver argument. *Accept: waived bins proven unreachable formally, or a reachable path found.*
- **B5 — Layered / virtual sequences.** Promote ad-hoc test control to a virtual-sequencer orchestrating host+dcr+axi/mem agents.
- **B6 (optional, deeper white-box) — per-unit scoreboards** (from `Vortex_UVM_Plan_Current.md` §FUTURE-WORK M2/M4): ALU/FPU-IEEE754/LSU per-execution-unit output checkers + cache/coherence & hazard coverage — a layer *beyond* lockstep+SVA. Effort sizing from that doc: M1(lockstep)+M3(SVA) ≈ 3 weeks minimal; full M1–M4 ≈ 6–9 weeks.

---

## Phase C — Coverage & closure

- **C1 — Traceable coverage plan.** Promote `docs/Coverage_Model_Reference.md` to a reviewed plan mapping each covergroup → a named spec requirement (ISA op, microarch feature, protocol). Requirements sourced from the MICRO'21 paper §3–4 + RTL.
- **C2 — 2CL coverage push.** Multi-core directed kernels spawning ≥ `NCL×NC×NW×NT` so every per-core probe instance fires (func 92.48%→higher). Honest, real stimulus.
- **C3 — Assertion coverage.** Add SVA cover directives; include in the merged metric.
- **C4 — CDV feedback loop.** riscv-dv seed generation steered by functional-coverage holes.
- **C5 — Config-matrix sign-off.** Full D-matrix (1C/1W…2CL) + XLEN 32/64 (I3/I6/D-matrix boxes), per-config banks (never blended — plan rule).
- **T-cache / T-exc (from RTL study).** Directed cache suite: MSHR saturation, same-line pending-chain coalescing, fill/replay ordering, flush-vs-request precedence (spec derived from [VX_cache_mshr.sv](../Vortex/hw/rtl/cache/VX_cache_mshr.sv) + bank arbiter). Exception/interrupt stimulus for `exception_cg`.

---

## Phase D — Infrastructure & sign-off

- **D1 — Parallel + graded regression.** Bounded worker pool in `run_suite.sh` (riscv-dv regen lane kept serial; respect QuestaSim licenses). `vcover ranktest` for a minimal sign-off set.
- **D2 — Coverage-off dev fast path.** `COVERAGE=0` compile/sim mode for verdict-only iteration; scope toggle instrumentation off third-party (cvfpu/HardFloat).
- **D3 — CI.** Nightly regression, results database, coverage-trend tracking, auto-triage.
- **D4 — Seed farm.** riscv-dv scaled to hundreds of seeds (C-extension enabled once Spike is the reference — it decodes RVC where SimX aborts).
- **D5 — Automated sign-off.** One report: pass rate, merged per-config coverage vs goal, matrix status, **requirements traceability matrix**, tool versions + seeds logged (reproducibility).

---

## Sequencing & dependencies

```
A0 → A1 → A2 → A3 → A4 → A5        (flagship, depth-first — do first)
                    │
        B2 (SB→mem_model) ──► B1 (RAL) ──► B3/B4 (SVA/formal) ──► B5 (vseq)
                                                    │
        C1 (cov plan) → C2/C3/C4/C5 + T-cache/T-exc │
                                                    │
        D1/D2 (regression speed — can land anytime) → D3/D4/D5 (CI/seed/sign-off)
```

- **D1/D2 are independent** — land them early for turnaround (cheap, contained, zero coverage risk) even though they're "Phase D."
- **B2 (scoreboard→mem_model)** is a natural companion to Phase A (a single clean memory model helps the lockstep comparator too).
- **A3/A4 depend on the Spike harness (A1/A2)** — the UNVERIFIABLE payoff comes after the SIMT model works.

## Acceptance for "industrial-grade" (definition of done)
1. Every stimulus renders a per-instruction verdict against a spec-complete golden model (0 UNVERIFIABLE), OR is classified with a formal/RTL-cited reason.
2. DUT native assertions + SVA layer active in the error gate.
3. RAL-based register access; single-source-of-truth scoreboard.
4. Traceable coverage plan; per-config sign-off across the config matrix.
5. CI-driven parallel/graded regression with reproducible, auto-generated sign-off + traceability.

## Non-negotiables carried from CLAUDE.md
Black-box honesty (no fabricated verdicts); per-config coverage never blended; negative tests stay RED after any scoreboard change; announce/confirm expensive sim runs; no Claude attribution on commits.

---

## Appendix W1 — RVVI export interface (SimX → UVM)

> **STATUS 2026-07-14: the export described below is ALREADY IMPLEMENTED** (`554080e`). The live artifact is `simx_retire_t` ([simx_cosim_record.h](../Vortex/sim/simx/simx_cosim_record.h)) + `simx_cosim_pop()` DPI ([simx_dpi.cpp](../vortex_uvm_env/uvm_env/ref_model/simx_dpi.cpp):869) + `simx_retire_s`/import in `simx_pkg.sv`. The field design below matches it (add `mem_addr/mem_data` for A2). This appendix now documents the interface + the **SV consumer** to build (A0), not new C++.

**Goal:** consume the existing per-retirement record in the UVM lockstep comparator, aligned to the DUT `commit_arb_if` stream by `uuid`.

### W1.1 Record (one per retired warp-instruction)
Populated from [instr_trace.h](../Vortex/sim/simx/instr_trace.h) `instr_trace_t` + [emulator.h](../Vortex/sim/simx/emulator.h) `read_dst_reg()`:

| Field | Source | Notes |
|---|---|---|
| `uuid` | `trace->uuid` | **alignment key** — monotonic per core |
| `cid` | `trace->cid` | core id |
| `wid` | `trace->wid` | warp id |
| `tmask` | `trace->tmask` | which of `SIMD_WIDTH` lanes are active/valid |
| `pc` | `trace->PC` | retired instruction PC |
| `wb` | `trace->wb` | writeback present |
| `rd_type,rd_idx` | `trace->dst_reg` | dest register (int/fp/none) |
| `rd_data[SIMD_WIDTH]` | `emulator.read_dst_reg(wid, dst_reg)` | **per-lane written value** (gated by `tmask`) |
| `is_mem, mem_addr[SIMD_WIDTH], mem_data[…], mem_size, mem_rw` | `dynamic_cast<LsuTraceData*>(trace->data)` `->mem_addrs` + dcache read/write | LSU ops only (A2) |
| `fu_type, op_type` | `trace->fu_type/op_type` | debug/coverage context |

### W1.2 DPI boundary
- **Producer (SimX, C++):** at [core.cpp](../Vortex/sim/simx/core.cpp):223 after `emulator_.step()`, on a *retirement* (non-null trace, `eop`), pack the record and push to a bounded ring exposed to the DPI layer (extend `ref_model/simx_dpi.cpp`). Guard with a `+RVVI_LOCKSTEP` build/runtime flag so default runs are unchanged (byte-identical, per regression discipline).
- **Consumer (UVM, SV):** an `rvvi_golden_agent` (adapted from `core-v-verif/lib/uvm_agents/uvma_rvvi`) pulls records via an imported DPI function `int simx_rvvi_pop(output rvvi_record_t rec)`, emits them as `uvm_seq_item`s to the lockstep scoreboard.

### W1.3 Comparator (UVM)
- Two streams keyed by `uuid`: DUT (`vx_commit_probe` → `commit_arb_if`) and GOLDEN (SimX RVVI). Maintain per-core `uuid`-indexed maps; when both sides have `uuid=k`, compare.
- **Per active lane** (`tmask[l]==1`): assert `dut.PC==gold.pc`, and if `wb`: `dut.data[l]==gold.rd_data[l]`; for `is_mem`: `dut.mem_addr[l]==gold.mem_addr[l]` (+ data on store). Mismatch → `uvm_error` naming `uuid`, `wid`, lane, PC, both values → **exact-instruction divergence report**.
- End-of-test: both `uuid` maps must drain empty (no unmatched retirements either side) — catches dropped/extra retirements.

### W1.4 Alignment risks & mitigations
- **SIMT interleaving:** DUT commits and SimX retirements need not be in the same *cycle* order → align on `uuid` (issued monotonically per core in [VX_schedule.sv](../Vortex/hw/rtl/core/VX_schedule.sv) `VX_uuid_gen`), not time. Buffer out-of-order arrivals in the `uuid` maps.
- **Multi-issue:** `ISSUE_WIDTH` lanes retire per cycle on the DUT; the probe already exposes per-slot `commit_arb_if[i]` — key each by its own `uuid`.
- **Non-writeback / store ops:** compare PC (+ mem for stores) only; skip `rd_data`.
- **Default-off guarantee:** `+RVVI_LOCKSTEP`-gated so a normal regression run produces an identical UCDB/verdict (regression-verified, like the AXI_THROTTLE/FLOOD precedent).

### W1.5 First artifacts to build (A0) — SV only, export reused as-is
1. Extend `vx_commit_probe.sv`: on `retire_fire[i]`, push `{uuid,wid,PC,rd,wb,tmask,data[lane]}` to a package-scope retire queue (D2a), `cfg.enable_lockstep`-gated.
2. Repurpose `simx_golden_model` stub → `simx_golden_agent`: post-`simx_run`, drain `simx_cosim_pop()` (already imported), emit golden retire txns on `ap`.
3. `lockstep_scoreboard`: `dut_map`/`gold_map` by `uuid`, per-active-lane compare `{PC,rd,result[lane]}` (W1.3), drain-empty check.
4. Add `cfg.enable_lockstep` + plusarg; wire golden agent + scoreboard in `vortex_env.sv`; sequence the drain after the end-state scoreboard's `simx_run`.
5. Run `vecadd_lite`; prove lane-exact match, injected-corruption catch, and `uuid` 1:1 identity (A0 accept).
