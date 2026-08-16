# Vortex UVM — Industrial-Grade Transformation Plan

**Owner:** Samuel · **Status:** planning (opus) · **Created:** 2026-07-14
**Decision (2026-07-14):** reference strategy = **RVVI lockstep**, golden = **SimX functional emulator (primary) + Spike (independent base-ISA audit, secondary)**; sequencing = **depth-first (flagship lockstep first)**; scope = **full transformation, planned end-to-end here**.
**Revision (2026-07-14, after reading `Vortex/sim/simx/` source):** SimX's functional `Emulator` already steps instruction-by-instruction, returns an RVVI-shaped `instr_trace_t`, holds full SIMT arch state, and reads back destination values — it is ~80% of an RVVI golden and is cleanly decoupled from the timing model (`core.cpp:223` consumes `emulator_.step()`). Therefore the **primary** lockstep golden is SimX-functional (it natively models SIMT + the 6 custom ops, which Spike cannot). Spike demotes to a **secondary independent cross-check** on the base ISA.
**Team (2026-07-14):** Samuel works solo — all lanes are his (incl. SimX/DPI C++). No hand-off or sign-off gating in this plan.

---

## ▶ RESUME HERE (session-continuity block — UPDATE AT EVERY PHASE BOUNDARY)

> Samuel `/compact`s every phase to save credits. This block is the cold-start entry point: a fresh session reads it and continues without re-deriving. Keep it current — when a milestone lands, move the marker and record what changed.

**CURRENT MILESTONE (2026-08-12): Phase A COMPLETE · B2 CLOSED · B1 FULLY CLOSED (2CL gate discharged, `3c622cd`) · `.svh` DONE (`59b7ea2`) · icache waivers APPLIED (`5c4b70f`) · I3 CLOSED (verified from `simx_config.stamp`) · 1CL RE-BANKED CLEAN & SAVED (`3217dbc`: 45/45, total 91.08%, cg bins 398/403).**
**NEXT: fix the three 2CL budgets + the two TB defects they exposed, THEN re-bank 2CL.** The first 2CL attempt gave 37/45 staged / 8 FAILED and is NOT a bank — see ▶▶ NEXT ACTION. None of the 8 is a DUT defect: 3 are budget (SimX's own `MAX_CYCLES` cap and two DUT `+TIMEOUT`s), 3 runs are 2 real OBS-009-class divergences, 2 are the documented expected pair. Two genuine TB defects were found in the process (scoreboard ignored the `-2` sentinel; `MAX_CYCLES` hardcoded) — both fixed, not yet committed.

**B1 ✅ (2026-08-11, `8ff86a4`) — DCR RAL with a per-core `bind`-probe backdoor.**
Achieved **real read-back checking**, which this plan previously said was impossible. New files:
`vortex_uvm_env/tb/vx_dcr_probe.sv` (bound into `VX_dcr_data`, peek-only) and
`vortex_uvm_env/uvm_env/ral/vortex_dcr_ral_pkg.sv` (reg block + adapter + checker).
**Measured: `host_coverage_test` 15/15 observations checked, 0 failed** — the RTL stored every
DCR write correctly including `MPM_CLASS`'s 8-bit truncation. Non-vacuity proven with
`+DCR_RAL_INJECT` (default OFF): names register, probe path and both values. No regression —
`vecadd_lite data_compared=84` unchanged, both Gate-0 guards still RED on injection.
**⚠ TWO TESTBENCH BUGS FOUND DURING B1 — the DUT was correct both times.** Recorded because the
failure signature looks exactly like a DUT defect:
1. **`set_auto_predict` leaves a stale mirror.** It only updates the model for writes issued
   *through* the RAL, but most DCR traffic comes from legacy sequences driving the agent
   directly (bootstrap, `host_coverage_vseq`). RTL held the right value, mirror held 0 ⇒ **11
   false errors**. Fixed with a `uvm_reg_predictor` on the **monitor**, which also extends the
   check to legacy stimulus (strictly more valuable than RAL-only coverage).
2. **End-state mirror vs historical observation.** Comparing every observation against the
   *final* mirrored value is wrong whenever an address is written more than once —
   `host_coverage_test` sweeps DCR values, so `RTL(actual)` legitimately showed `0x0`/`0x40`/
   `0x10000` while the mirror held `0x80000000` ⇒ **10 false errors**. Fixed by comparing each
   observation against the write that produced it, truncated to the field width the register
   model supplies.
**Lesson to carry:** a firing checker is not evidence of a DUT bug. Both times the correct move
was to investigate which side was right, not to loosen the check.

**B2 ✅ (2026-08-07) — end-state scoreboard collapsed to a single source of truth.**
`shadow_memory` (a parallel 64-bit reconstruction assembled from snooped write transactions)
is **deleted**; the DUT value now comes only from `dut_mem` (`mem_model`), which is preloaded
with the program image (`vortex_tb_top.sv:185`) and written byte-accurately by both responders
(`axi_driver.svh:218`, `mem_driver.svh:129`). Dead `compare_result_region` (53 lines, never
called) deleted. `mem_model` is now **mandatory** — absent ⇒ `uvm_fatal`, because a missing DUT
side would otherwise yield a green run that checked nothing.
**⚠ `shadow_valid` was NOT deleted** despite the original plan text saying so — it is renamed
`dut_write_mask` and is load-bearing: it makes the SimX-poison gate byte-granular, and it is
what separates the forward pass from the reverse dropped-store pass. Deleting it would have
silently lost checks. **Do not "finish the job" by removing it.**
**Validated by differential, not by assertion — 18,749 word comparisons reproduced EXACTLY:**
cache_tier 16,452 · riscv-dv 1,414/490/436/15 · sfu_masks 124 · vecadd_lite 84 · tcu_test 76 ·
fpu_test 8 — every one bit-identical to its pre-B2 baseline, with `skipped_*` counts identical
too. **Both Gate-0 guards still RED on injection at the same address `0x800075d8`**
(`negative_result_test`, `negative_dropped_store_test`). New: **OBS-023** (a dropped *sub-word*
store into a partially-written dword is invisible — pre-existing, bounded, OPEN).
**A6 ✅ (2026-08-07):** Spike independence audit done — DUT/SimX/Spike all retire **exactly 11,076** writebacks on `riscv_arithmetic_basic_test_0.elf` and agree on every PC/rd/value (**0 mismatches**); non-vacuity proven by injection. Scope is warp0/lane0/base-ISA only — **SIMT still has no independent reference**. New trace hook `+LOCKSTEP_TRACE=<path>` (default OFF) + `scripts/spike_audit.py`. See [`docs/A6_SPIKE_INDEPENDENCE_AUDIT.md`](A6_SPIKE_INDEPENDENCE_AUDIT.md) and **OBS-022** (lockstep is writeback-domain only: branches/stores not directly compared).

**PRIOR MILESTONE LINE (superseded by the A6 close above):** A0 ✅ · A1(a–e) ✅ · A2 ✅ · **A3 ✅ CLOSED (2026-08-06)** — golden refusals are now NAMED halts (-4 GOLDEN_HALT) not anonymous crashes (-3); disassembler never aborts (33 sites); 39 semantic sites record pc/instr/sub-field; verified prefix preserved, truncated tail excluded. **MEASURED: the UNVERIFIABLE bucket is EMPTY** — all 10 retained riscv-dv re-run, zero SimX aborts, real byte-exact compares (15..1414 words); the "~10 still abort / 69 std::abort" claim was STALE. Non-vacuity proven via `SIMX_FORCE_HALT` (default OFF). · A4 ✅ (2CL divergence grounded in MICRO'21 §4.1.4 + RTL proof) · A5 ✅ · A6 ❄️ FROZEN (**not a blocker for A3 — Spike has no SIMT model and cannot run a Vortex kernel; the bucket emptied without it**). **2CL sweep 5→12 of 15 verified.** TCU ✅ · FPU ✅ (OBS-014) · SFU ✅ (OBS-015). **L2/L3 buildable + green** (OBS-016/017/018). **Config fidelity closed** (OBS-019). **cache_tier VALIDATED @1CL** (460,769 cyc, 64,772 instr, 16,452 byte-exact words, 0 err). NEXT ACTION: (1) L2/L3 cache-tier coverage confirmation + 15-kernel L2/L3 sweep re-run; (2) **Phase B — B2 scoreboard→mem_model**. See ▶▶ block. **⚠ Before making any "we verified / we stressed it" claim, read the 🎯 VERIFICATION-MATURITY ASSESSMENT & FUTURE WORK section (FW-1..FW-7) — FW-1 seed control is now DONE (reproducibility verified 2026-08-12); the OPEN half is seed VOLUME, plus new FW-1b (two vacuous duplicate riscv-dv entries).**

**PAPER (2026-07-17): final generic rewrite committed — `docs/paper/vortex_uvm_paper.tex`, title "A UVM-Based Per-Instruction Verification Methodology for the Vortex RISC-V GPGPU". No internal jargon (Gate-0 reframed as non-vacuity discipline; OBS-x → R1–R9); sections: env / verdicts+non-vacuity / SIMT lockstep (5 rules) / two-pass load feed / stimulus / coverage / RTL findings / ref-model findings / limits+soundness boundary / enhancements. On branch (`f2ecd37`) AND main (`d83c5cb`), both pushed.**

### ▶▶ NEXT ACTION (exact, resumable — 2026-08-12)

**PHASE A COMPLETE · B2 CLOSED · B1 FULLY CLOSED (gate discharged) · `.svh` DONE · 1CL RE-BANKED
CLEAN · icache WAIVERS APPLIED. ONE STEP REMAINS: the 2CL re-bank.**

### ▶▶ RESUME HERE — 2026-08-16 (LATE) · COVERAGE MAXIMISED AND BANKED · ONE RE-RUN IN FLIGHT

**Full analysis: `docs/COVERAGE_MAX_20260816.md`. Evidence: OBS-035 / OBS-036 / OBS-037 / OBS-038,
and the OBS-032 update.** This block SUPERSEDES the toggle block below it (which is still correct,
just earlier).

| bank | programs | total | conditions | toggle | cg bins |
|---|---|---|---|---|---|
| 1CL/1C/4W/4T | **49/49, 0 FAILED** | **94.71%** (+1.62) | 90.41% | 82.76% | 370/377 |
| 2CL/2C/4W/4T | **49/49, 0 FAILED** | **94.44%** (+1.77) | 88.43% | 80.33% | 985/1032 |

Previous banks preserved as `cov/bank_{1CL,2CL}_*_prev_20260816/`; logs at
`results/run_suite_logs_{1CL,2CL}_max_20260816/`.

**⚠ ONE THING IS IN FLIGHT** — a 1CL re-run (**50** programs, adding `storm_big`) is executing. If it
is gone when you resume, check `results/latest` and the log for `SUITE VERDICT`; if no verdict was
reached, the 49-program banks above remain the truth. **Do NOT start 2CL until 1CL is banked** —
`run_suite` merges into `cov/merged.ucdb` and an unbanked result is destroyed by the next merge.

**THREE NEW KERNELS**, each verified against its target before any suite ran:
* `isa_probe` — M-mode CSR read/write + `fclass.s`/`fmv.x.w`/`fmsub.s`/`fnmsub.s`. CSR reads are
  OR-accumulated **and stored**, so a wrong value fails the scoreboard instead of passing silently.
  MISA/MVENDORID/MARCHID/MIMPID deliberately never read — see **OBS-036**.
* `unit_storm` — first kernel producing real internal back-pressure; **13 of 24** missing condition
  terms at 1CL (lmem response path + wctl `rsp_buf`).
* `storm_big` — 33KB hot `.text` interleaved with data traffic (a second memory stream `unit_storm`
  cannot make, since its loop stays resident in the 16KB icache). **+4 condition terms at 2CL.**

**⚠⚠ THE MEMORY-PRESSURE RESULT — DO NOT "OPTIMISE" THESE KERNELS BY ENLARGING THEIR TABLES.**
Measured twice, independently: `unit_storm` 4KB→64KB table went **13 → 11** terms (LOST
`wctl_unit/rsp_buf`); `storm_big` 4KB→64KB went **+4 → +0**. More memory pressure made coverage
WORSE. Mechanism: these bins need two requests live at one port in the SAME cycle. A large working
set misses to DRAM, every warp blocks, nothing issues, and requests arrive spread thin — each fully
drained before the next. Total traffic up, *concurrent* traffic down. **Contention comes from ISSUE
DENSITY, not miss volume.** Both kernels carry this in-source with the measured numbers.

**NEW SAFETY NET — `merge_coverage.sh` HITS-INVARIANT GATE (blocking).** Exclusions are now applied
in two stages split by reason code (EOTH third-party first, then structural), and the merge **fails
hard** if any structural exclusion changes a COVERED bin count. It caught two real defects on its
first run: a waiver written that same session, and a **pre-existing** one (`VX_schedule.sv:168
-code c`) that had been silently discarding a covered condition term since it was added — now
withdrawn. **Root cause worth remembering: Questa's FEC cannot waive a single input term of a
condition** — waiving `(init_valid | flush_valid)` discards the whole expression including its
covered rows.

**LEFT UNCOVERED AND DELIBERATELY NOT WAIVED** (both would need a bound derived from RTL params, and
waiving on "we could not hit it" is the OBS-030 mistake): the AXI read-stability assertions
(**OBS-038** — survive flood + congestion, `pass=0`) and the `SIZE==0` elastic-buffer port nodes
(4,667 dead nodes, 12.7% of the toggle gap, but 97 nodes on the SAME ports are live ⇒ Questa alias
artifact, not dead logic).

**▶ NEXT, in this order:** (1) bank the in-flight 1CL, (2) re-run + bank 2CL with `storm_big`,
(3) L2/L3 plumbing — `run_suite.sh:24` never passes `L2`/`L3` to `make`, `merge_coverage.sh:47`
never forwards them, and `gen_coverage_exclude.sh:95-102` waives the L2/L3 cache-side buses
**unconditionally** (would waive LIVE logic once enabled — the new gate would catch it, but it
should be correct by construction), (4) **OBS-032** — drop `MREQ_SIZE` to the RTL default 4 and
re-measure, (5) the L2/L3 third bank, (6) the paper.
**⚠ Never edit `run_suite.sh` / `merge_coverage.sh` / `gen_coverage_exclude.sh` while a suite is
running** — bash reads a script incrementally from disk, and the latter two are invoked at the end
of the run to produce the bank.

---

### ▶▶ RESUME HERE — 2026-08-16 · TOGGLE ROOT-CAUSED AND WAIVED · NOTHING IN FLIGHT

**Full analysis: `docs/COVERAGE_TOGGLE_20260816.md`. Evidence: OBS-033 / OBS-034.**
**NO SIMULATION WAS RUN** — both banks were RE-REPORTED from their own `merged_raw.ucdb` with an
extended exclusion set. Stimulus, 47/47 pass results and every functional number are unchanged.

| bank | toggle | total | cg bins | hits |
|---|---|---|---|---|
| 1CL/1C/4W/4T | 79.79 → **82.16%** | 93.09 → **93.43%** | 370/377 = 98.14% (unchanged) | 339,487 → **339,487** |
| 2CL/2C/4W/4T | 77.80 → **79.47%** | 92.67 → **92.91%** | 985/1032 = 95.44% (unchanged) | 972,317 → **972,317** |

**Acceptance met at BOTH configs: not one covered bin moved (hits identical, only the denominator
shrank) and 0 "had no effect".** Same non-vacuity gate the icache covergroup waiver passed in
`5c4b70f`, plus the OBS-030 cross-config gate.

**⚠ THE OLD TOGGLE EXPLANATION NAMED THE WRONG CACHE.** Every doc since 2026-07-10 blamed
*"write-through dcache => 512-bit write-data never driven"*. Measured: **icache 51,340 bins /
22,730 missing / 55.7%** vs **dcache 86,604 / 9,524 / 89.0%**. The icache is half the size and
carries 2.4x the misses — **26.4% of the design's entire toggle gap from one subtree** — because
`VX_socket.sv:106` instantiates it `.WRITE_ENABLE (0)`. Counter-check: `rsp_data.data` toggles 45-46
times on all 512 bits, so the read path is fully exercised and only the write direction is dead.
This is the SAME citation already accepted for `cp_rw.wr` in `5c4b70f`; the toggle bins from that
identical tie-off had never been waived.

**Second cause — `VX_uuid_gen.sv:40-41`: `uuid = { g_wid[11:0], counter[31:0] }`,
`g_wid = (CORE_ID << NW_BITS) + wid`.** g_wid bits above the topology bound are waived
config-awarely (1CL `uuid[43:34]` → 4CL/16W `uuid[43:40]`; it SHRINKS as the topology grows).
**Counter bits [18:31] are deliberately NOT waived** — infeasible (bit 31 needs ~2.1e9 instructions
on one warp) is not the same as structurally dead, and this project excludes only the latter.
**Do NOT set `NDEBUG` to make them go away** — it sets `UUID_WIDTH=1` and would destroy the uuid key
that `lockstep_scoreboard.svh` / `vx_commit_probe.sv` / `vx_lsu_probe.sv` / `simx_dpi.cpp` depend on.

**Third factor — Questa toggle is BY INSTANCE.** `VX_mem_bus_if` is 2,456 bins @96.49% by design
unit but 98,160 bins with 15,951 missing by instance; eight parameterisations sit at *exactly*
46.96%. One tie-off costs the metric ~10x what it costs the design.

**⚠ OPEN, NOT WAIVED: `mem_req_buf` / `mem_rsp_queue` internal `data_in`/`data_out`** (654+560 nodes,
measured 100% dead). Both degenerate to passthrough (`MEM_REQ_BUF_ENABLE = (NUM_BANKS != 1)`,
`VX_cache.sv:105`; `ICACHE_MRSQ_SIZE 0`, `VX_config.vh:577`) and the passthru branch shows an ALIAS
signature (`genblk1/__unused = 47` vs `genblk2/__unused = 0`). Excluding an alias of a covered net
would hide real coverage — left in the denominator pending investigation.

**▶ NEXT: the paper** (headline still wrong on all three counts), then optionally L2/L3 as a third
bank. Remaining cheap targets unchanged: `cross_dvg_depth` 2 bins; OBS-032 decision.

---

### ▶▶ PREVIOUS — 2026-08-15 · BOTH CONFIGS BANKED CLEAN · CONFIG FIDELITY CLOSED

**✅✅ BOTH POST-SCALING RE-RUNS DONE AND BANKED (2026-08-15). 44/44, 0 FAILED, BOTH CONFIGS.**
**FULL ANALYSIS: `docs/COVERAGE_POSTSCALE_20260815.md`** — read that before quoting any number.

| bank | total | cg bins | Δ total | Δ bins |
|---|---|---|---|---|
| 1CL/1C/4W/4T | **91.07%** | 398/403 = 98.75% | −0.01 (control) | 0 |
| 2CL/2C/4W/4T | **90.54%** | **962/1095 = 87.85%** | **+1.85** | **+18** |

**+18 bins, 0 lost, all at 2CL: exactly 6 per previously-idle core** (`CL0.C1`,`CL1.C0`,`CL1.C1`) —
TCU `cp_warp.auto[0..3]` + TCU/FPU `cp_active_threads.uniform`, from the `tcu_mt`/`tcu_test`/
`fpu_mt` grid scaling. **Every 2CL category improved**; weighted covergroups 92.11→98.13 is what
drives the headline (Questa Total = unweighted mean of 7 categories).
**⚠ CORRECTION — the "84 per-core bins / 28 each / core0 misses 0" figure was WRONG.** Measured:
the per-core excess vs core0 was **14 each = 42 total** (now **8 each = 24**), and core0 misses
**13**, not 0. Stop quoting 84/28.
**`cp_mshr_stall.stall` did NOT move** — still 0/4 instances vs 5,131,366 `no_stall` samples. Four
cores contending was not enough; genuine stimulus gap, honestly uncovered.
**The residual 8-per-core are a DELIBERATE consequence of FIX 1 + FIX 2** (riscv-dv and
`barrier_test` are core-gated to core 0, so Zicond `czeq`/`czne`, `lb` and the `<bar,*>`/`<pred,*>`
SFU crosses have no producer on cores 1-3). **Do NOT recover them by removing the gates** — coverage
from an architecturally-undefined program is not coverage. Recover them with a multi-core-SAFE
directed kernel (per-core contiguous slice, `vx_spawn.c:299`).
**BIGGEST REMAINING 2CL LEVER IS AXI, NOT THE CORES: 72 of 133 missing bins** are
`cross_type_route` (39) + `cp_id_route` (33) — tag space scales with config, stimulus does not.
**Asymmetry to remember:** core0 MISSES 2 divergence bins the other cores cover
(`cross_dvg_depth.<divergent,d[3]>`, `<uniform,d[1]>`) ⇒ "core0 is a superset" is FALSE.
Pre-scaling banks preserved: `cov/bank_{1CL_1C_4W_4T,2CL_2C_4W_4T}_prescale_20260814/`.
Logs: `results/run_suite_logs_{1CL,2CL}_20260815/`.

**▶ NEXT: update `docs/PAPER_BASE_EVALUATION.md` + `docs/paper/vortex_uvm_paper.tex`** — the
headline "100% functional / 43/43 / 91.0%" is wrong on all three counts (98.75% raw bins 1CL /
87.85% 2CL; **44** distinct programs; 91.07% 1CL / 90.54% 2CL).

---

**1CL detail (2026-08-15 05:44).** `44 staged, 0 FAILED`.
**Total 91.07% · covergroup bins 398/403 = 98.75% · 2256 instances** — i.e. **statistically
identical to the pre-scaling bank** (91.08%, 398/403, 2256). Only toggle moved, 78.42→78.39%
(`wide_stress` walks a slightly different address pattern at the device-sized grid).
**This is the EXPECTED result and it is the control for the 2CL measurement:** at 1 cluster / 1
core, `vx_num_cores()*vx_num_warps()*vx_num_threads()` evaluates to the SAME `total` the hardcoded
constant used, so the seven scaled kernels emit near-identical stimulus. It confirms the scaling
changed nothing it should not have ⇒ **any 2CL movement is attributable to the scaling.**
Pre-scaling 1CL bank preserved at `cov/bank_1CL_1C_4W_4T_prescale_20260814/`; 1CL per-test logs +
suite log archived to `vortex_uvm_env/results/run_suite_logs_1CL_20260815/`.

**2CL detail (2026-08-15 08:15).** `44 staged, 0 FAILED`, ~2.5 h wall clock.
⚠ **NOTHING IS IN FLIGHT.** Both runs are finished and banked; no background sim is running.
⚠ `run_suite` merges into `cov/merged.ucdb`, so an UNBANKED result is destroyed by the next
config's merge. Archive `results/run_suite_logs/` before each run — it is overwritten.

**STATE: both configs re-run post-scaling, banked, and verified by re-reading the copies.**

---

### ▶▶ COVERAGE-GAP PUSH — 2026-08-15
**✅✅ GAP-PUSH COMPLETE — BOTH CONFIGS RE-RUN AND BANKED (2026-08-15/16). 47/47, 0 FAILED, BOTH.**
**NOTHING IS IN FLIGHT.** Full analysis: **`docs/COVERAGE_GAPPUSH_20260815.md`**. Evidence:
**OBS-030 / OBS-031 / OBS-032**.

| bank | programs | total | cg bins (raw) | cg weighted |
|---|---|---|---|---|
| 1CL/1C/4W/4T | **47/47, 0 FAILED** | **93.09%** (+2.02) | 370/377 = 98.14% | **99.79%** |
| 2CL/2C/4W/4T | **47/47, 0 FAILED** | **92.67%** (+2.13) | 985/1032 = **95.44%** (+7.59) | **99.52%** |

Every code category improved at BOTH configs: conditions **+9.27 / +8.14**, branches +2.08 / +2.50,
statements +0.72 / +0.94, toggle +1.40 / +1.95.
Previous banks preserved as `cov/bank_{1CL,2CL}_..._postscale_20260815/`; logs at
`results/run_suite_logs_{1CL,2CL}_gap_20260815/`.

**THREE NEW KERNELS (47 programs, was 44), each verified against its target BEFORE any suite ran:**
* `multicore_isa` — **closed the per-core gap entirely.** All tracked bins on all 4 cores with
  identical counts. Zicond `czeq`/`czne` from a kernel for the FIRST time (compiler cannot emit at
  `-march=rv32imaf`; inline `.insn`). Recovers what FIX 1/FIX 2's core gates cost **without
  weakening the gates**.
* `lmem_stress` — first kernel to touch the scratchpad. `VX_local_mem` toggle **57.52 → 73.19%**.
* `mshr_flood` — 67,207 dcache misses; its bin was NOT hit and that IS the finding (OBS-031).

**COVERAGE MODEL REWRITTEN (OBS-030).** Flat `cp_id_route`/`cross_type_route` + four literal
`ignore_bins` withdrawn — three fired on REAL traffic at 2CL (4488/10605/88 hits). Replaced by
`cp_route_port` / `cp_route_slot` / `cp_write_tag` / `cross_port_slot`, bounds derived from
`VX_MEM_PORTS` + adapter `TAG_BUFFER_SIZE`. ⚠ The AXI tag buffer is **config-dependent** — ABSENT at
1CL, present per-port at 2CL — so `cp_route_slot` is gated on it. **Never compare the AXI block
across this change.**

**⚠ REMAINING GAPS — 1CL: 7 bins · 2CL: 47 bins. All accounted for:**
* **24 (2CL)** `cp_route_slot` slots 4-15 + `cross_port_slot` — **measured** per-port concurrency is
  3 (contiguous {0,1,2} proves the decode; lowest-free allocator). Same requester-width bound as
  OBS-031. **Left uncovered, deliberately NOT waived** — the exact bound is not derived from RTL
  params (measured 3 < naive 8), and waiving on an unproven bound is the OBS-030 mistake.
* **8 (2CL) / 4 (1CL)** `cp_write_tag` high buckets — stimulus, low value.
* **4** `mem_usage_cp`/`system_mem_cross` — weight-0 by design, MEM idle on AXI runs.
* **2 (2CL)** `cross_dvg_depth` `<divergent,d[3]>`,`<uniform,d[1]>` — **the one clean cheap target
  left**; ordinary stimulus, no structural obstacle.

**⚠ OBS-032 STILL OPEN — WE HAVE NEVER MEASURED THE RTL's DEFAULT CACHE CONFIG.**
`compile.sh:70-73` forces `{I,D}CACHE_MREQ_SIZE=16` over an RTL default of **4**. Decide before the
paper: drop it and re-measure, or state it in the configuration table.

**DEFERRED — L2/L3.** Suite never sets `L2=1 L3=1`, so both are PASSTHRU in every bank; no kernel
can reach them. OBS-016/017 FIXED, OBS-018 proved they elaborate. Needs its OWN bank as a third
config; verify with `vcover report -recursive | grep l2cache`, never by grepping the sim log.

**▶ NEXT: the paper.** `docs/PAPER_BASE_EVALUATION.md` + `docs/paper/vortex_uvm_paper.tex` say
"100% functional / 43/43 / 91.0%" — wrong on all three (**47** programs; 98.14%/95.44% raw bins;
93.09%/92.67%).

**WHAT LANDED**

| commit | change |
|---|---|
| `d9cd75c` | AXI route re-modelled by decoded sub-field; `cp_num_clusters` added; dead `SINGLE_CORE` retired |
| `6433857` | 3 gap-directed kernels + config-aware `cp_mshr_stall` waiver; hardcoded config ceilings removed |
| `e29e836` | `cp_route_slot` gated on tag-buffer presence |
| `927be95` `e342861` `f60aa8c` | OBS-030 / OBS-031 / OBS-032 |

**MEASURED (individually, per the "verify the gap is hit before running the suite" rule)**
* `multicore_isa` — **all 8 per-core target bins covered** (`czeq`,`czne`,`lb`,`lh`,`sb`,`sh`,
  `<bar,{uniform,partial[3],partial[2]}>`, `<pred,{...}>`). Zicond emitted from a kernel for the
  FIRST time: the compiler cannot produce it at `-march=rv32imaf` (verified 0 occurrences in three
  existing ELFs), so it is inline `.insn` encoded from `VX_gpu_pkg.sv:168` + `VX_decode.sv:189`.
* `lmem_stress` — **`VX_local_mem` toggle 57.52% -> 73.19% (+687 bins)**, measured by merging the
  run into the 1CL bank. First suite kernel to touch the scratchpad at all.
* `mshr_flood` — 67,207 dcache misses vs 774 hits, **`cp_mshr_stall.stall` still 0**: see OBS-031.

**⚠ OBS-032 — WE HAVE NEVER MEASURED THE RTL's DEFAULT CACHE CONFIGURATION.**
`scripts/compile.sh:70-73` unconditionally passes
`+define+{I,D}CACHE_MSHR_SIZE=16 +define+{I,D}CACHE_MREQ_SIZE=16`. `MREQ_SIZE` defaults to **4**
(`VX_config.vh:633`), so every bank describes a machine with a **4x deeper cache fill queue** than a
default Vortex build. That queue's almost-full threshold is `MREQ_SIZE - PIPELINE_STAGES`
(2 by default, **14** as we build it) and it is one of the two terms gating `core_req_ready`
(`VX_cache_bank.sv:232`) — i.e. it directly controls when a bank stops accepting misses, which is
exactly what several coverage bins try to observe. Provenance: the initial upload commit, no
comment, no doc. **It nearly produced a false structural waiver** (the first OBS-031 draft).
**Disposition OPEN — decide before the paper:** (a) drop the override and re-measure the default,
or (b) keep it and state it in the bank metadata + the paper's configuration table. Until then,
every cache back-pressure claim must be qualified with the queue depths we actually built.

**⚠ OPEN QUESTION TO SETTLE AT 2CL — is `cp_route_slot` reachable?**
The AXI tag buffer is **config-dependent**: absent at 1CL (`g_none`, read `id` = raw cache tag),
present per-port at 2CL (`g_tag_buf[i]/g_enabled/tag_buf`) — verified from the UCDB hierarchy with
`vcover report -recursive`, not inferred. So the slot index only MEANS anything at >=2 ports, and
the coverpoint is now gated on that.
**Hypothesis, NOT yet established:** the 10 unhit slots may be bounded by the SAME structural limit
as OBS-031 — the allocator is strictly lowest-free (`VX_allocator.sv:49`), so slot N requires N
concurrent outstanding reads on that port, and `LSUQ_OUT_SIZE` is 4 at `NUM_THREADS=4`.
**Do NOT waive on this hypothesis until measured.** The 2CL verification run is what decides it;
if confirmed it is a config-aware waiver like OBS-031, if not it is a stimulus target.

**▶ NEXT, IN ORDER**
1. ~~Register the 3 kernels in `run_suite.sh`~~ ✅ done (`runk sim-only` entries).
2. **2CL verification of the 3 kernels** (in flight) — confirms the 8 per-core bins fill on cores
   1-3, and answers the `cp_route_slot` question above.
3. Full 1CL + 2CL sweeps, **banking each immediately**.
4. Then the paper.
**DEFERRED — L2/L3.** The suite never enables them (`L2=0 L3=0`), so both levels are PASSTHRU in
every banked run. OBS-016/017 are FIXED so it is buildable, and OBS-018 already proved the levels
genuinely elaborate (timing moved 12,215 -> 21,968 cycles on `tcu_test`). It is a THIRD config
needing its own bank — do it after these two are solid, and verify elaboration with
`vcover report -recursive | grep l2cache`, never by grepping the sim log (OBS-018 notes `dcache`
does not appear there either).

**⚠ EXPECT THE HEADLINE TO MOVE BOTH WAYS.** Removing three false `ignore_bins` puts genuinely
reachable bins back in the denominator (lowers %), while `lmem_stress` and `multicore_isa` add real
coverage (raises %). The resulting number is more defensible either way; do not tune it.

| bank | programs | total | covergroup bins | instances |
|---|---|---|---|---|
| **1CL/1C/4W/4T** (`cov/bank_1CL_1C_4W_4T/`) | **44/44, 0 FAILED** | **91.07%** | 398/403 = 98.75% | 2256 |
| **2CL/2C/4W/4T** (`cov/bank_2CL_2C_4W_4T/`) | **44/44, 0 FAILED** | **90.54%** | 962/1095 = 87.85% | 8275 |

**⭐ FIRST CLEAN 2CL SWEEP EVER** (previous attempt: 37/45 with 8 FAILED). Stale 2CL bank
(85.16%) preserved as `bank_2CL_2C_4W_4T_stale_20260710/` — never quote it.
⚠ Suite is **44 DISTINCT programs**, not 45 — `riscv_pmp_test` was dropped (FW-1b duplicate).

**⭐ THE "EXPECTED" 2CL FAILURES WERE ONE METHODOLOGY BUG, AND ARE GONE.** All four now PASS with
real non-zero compares: `riscv_no_fence_test` (556 words), `riscv_full_interrupt_test` (787),
`riscv_mmu_stress_test` (729), `riscv_non_compressed_instr_test` (787).
**This FALSIFIES this plan's own "EXPECT AT BEST 43/45 — never 45/45 at 2CL"**, which also said not
to "fix" the first two. Root cause was OBS-027 (riscv-dv single-hart program on every core), not
inherent SimX weak-coherency. ⇒ **`docs/investigations/SimX_2CL_no_fence_divergence.md` got the
MECHANISM right and the DISPOSITION wrong** — it filed the divergence as permanently UNVERIFIABLE,
stopping one question short of asking whether the program was ever MEANT to run on >1 hart.
**OBS-009's riscv-dv members are RESOLVED.**

**⭐ OBS-028 — KERNELS WERE PINNED TO 1/1/4/4 REGARDLESS OF THE COMMAND LINE.**
`Vortex/hw/VX_config.h:99-111` hardcodes `NUM_CLUSTERS 1 · NUM_CORES 1 · NUM_WARPS 4 ·
NUM_THREADS 4`; `common.mk:24` has always honoured `$(CONFIGS)` but **nothing ever passed it**, and
`Makefile:60` pointed `PROGRAM` at a PREBUILT `.elf`. So `wide_stress` — commented *"Multi-core
aware"* — computed `TOTAL = NUM_CLUSTERS*NUM_CORES*NUM_WARPS*NUM_THREADS = 16` and ran with
`per_cluster_busy=01` for its ENTIRE ~1.4M-cycle run at 2CL. **The kernels were not naive, they were
misinformed: the arithmetic was right and its inputs were frozen.** This, not the DUT and not the
core-gating fix, is why 84 of the 151 missing 2CL bins sat on cores 1-3 (`cluster0_core0` missing
**0**, the other three missing **28 each**).

**⭐ OBS-029 — DIFFERENTIAL TESTING IS STRUCTURALLY BLIND TO A FAULT IN THE STIMULUS.**
`tcu_*` build their WMMA from `wmma_context<NUM_THREADS,…>` — a **TEMPLATE argument**, so tile
geometry is part of the type and can never be runtime-derived. At the wrong warp width the kernel
is invalid, and **no checker here can detect it**: DUT and SimX execute the SAME binary, so both are
wrong identically — end-state compare passes, lockstep passes, coverage fills. **A green run with 0
mismatches is fully compatible with the kernel having verified nothing.** Only what DIFFERS between
the models is validated; everything SHARED (binary, memory image, launch geometry, DCR config) is
common-mode and needs an INDEPENDENT assertion. **Read this before writing any "verified by
golden-model equivalence" claim.**

**WHAT LANDED (all measured, all committed):**
| item | commit | evidence |
|---|---|---|
| 7 kernels sized from the DEVICE | `81ffa24` `49b19ba` `5a6dde0` `171cc10` `9674de0` | every one `per_cluster_busy` `01→11`, byte-exact, 0 mismatches |
| `wide_stress` real parallel speed-up | `5a6dde0` | 1,420,210 → **1,172,065 cycles** for the SAME work (−17.5%) |
| TCU core-dim scaled + geometry guard | `9674de0` | `data_compared` 292 → **740** (2.5×); guard non-vacuous (`tcu_test` still passes) |
| **per-config PROGRAM build** | `3ffa321` | `kernel-config` + `.kernel_config.stamp`; 10 kernels build at THREADS=2 incl. both TCU templates |
| coverage exclusion guard repaired | `04db8fd` | `grep -c ... \|\| echo 0` made `HNE="0\n0"` ⇒ the guard could NEVER report a true count |
| OBS-026 hex misparse corrected | `2b6c1cf` | `bar2_stall` is `0x300`/`0x600` (768/1536), **not** 3/6 — SimX lost ZERO updates, DUT exactly half |

**CONFIG FIDELITY IS NOW CLOSED ON ALL LEGS — every stage propagates AND is guarded:**
| stage | propagation | guard |
|---|---|---|
| RTL | `compile.sh:66-69` `+define+` | I2 assert (`$fatal`) |
| SimX | `prepare.sh:105,123` `CONFIGS` | `simx_config.stamp` |
| **program** | `Makefile:88` `KERNEL_CONFIGS` | **`.kernel_config.stamp`, `exit 1` on failure** |
| UVM | `simulate.sh:26-29` plusargs | I2 assert |
| coverage | `run_suite.sh:241` `COV_*` | `gen_coverage_exclude` + "had no effect" (repaired) |
| tag width | — | C1 assert |
**GATE-0 RE-PROVEN after the per-config rebuild** (rule 5): both guards RED — fault at
`0x800075d8` detected, dropped store at `0x800075d8` detected via the reverse pass.

**▶ NEXT ACTION:** the re-run is measuring whether the kernel scaling BUYS coverage — (a) do the 84
per-core bins fill at 2CL, (b) does `cp_mshr_stall.stall` (the only genuine 1CL functional gap,
icache+dcache) finally move now that 4 cores contend, (c) 1CL should barely change (at one core the
scaled grids still compute 16). **Bank each config IMMEDIATELY after its merge** — `run_suite`
merges into `cov/merged.ucdb`, so an unbanked result is destroyed by the next config's merge.
Only after that: update `docs/PAPER_BASE_EVALUATION.md` + `docs/paper/vortex_uvm_paper.tex`, whose
headline "100% functional / 43/43 tests / 91.0%" is now wrong on all three counts.

---

### ▶ THE FOUR FIXES — ✅ ALL FOUR DONE AND MEASURED (2026-08-13)

**Status: COMPLETE. Next action is the TWO BANK RUNS (1CL then 2CL), not these fixes.**

| fix | commit | measured result |
|---|---|---|
| 1 — core-gate riscv-dv | `3d0ec30` | `riscv_rand_instr_test` @2CL **`MEM MISMATCH` 6 → 0**, `data_compared=780` UNCHANGED (non-vacuous), `per_cluster_busy=01` |
| 2 — core-scope `barrier_test` | `47d6e7a` | @2CL **`MEM MISMATCH` 2 → 0, `CONSOLE FAIL` 1 → 0**, kernel prints `ALL PASSED` from core 0 only |
| 3 — budgets ≥3x measured | `eb8a630` | **nine** tests were under 1.6x, not the two the plan named |
| 4 — FW-1b duplicate | `eb8a630` | `riscv_pmp_test` dropped; md5 sweep proves it was the ONLY duplicate ⇒ suite is **44 distinct programs** |

**Three corrections this work forced — do NOT resume from the superseded text below:**
1. **Use `VX_CSR_CORE_ID` (`0xCC2`), NOT `VX_CSR_MHARTID` (`0xF14`)** as FIX 1's text says. `0xF14`
   is stripped by our own sed (`prepare.sh:454`), and MHARTID returns a COMPOSED gtid whose `!=0`
   test is only valid because reset leaves warp0/thread0 alone. `0xCC2` returns `CORE_ID` directly.
2. **FIX 2's stated cause (`bar2_stall`) was wrong.** T2 passed on all four cores. The `errors==1`
   came from `test_accumulator_barrier()`'s own `bar3_contrib[w]=0` init loop running on a LATER
   core's main thread and wiping an EARLIER core's contributions (`FAIL accumulator=2 expected 10`).
   `bar2_stall` was real but was one of the two MEMORY mismatches, not the test failure.
3. **FIX 3's two budgets were the symptom, not the disease.** Nine tests sat under 1.6x margin;
   `cache_stress` was at 1.14x and `axi_memory_test` at 1.19x, both one config-slowdown from a
   masked timeout. All raised to ≥3x, with the policy recorded in `run_suite.sh`.

**Also corrected in `docs/RTL_OBSERVATIONS.md` (`2b6c1cf`):** OBS-026's `bar2_stall` table read
DUT=3 / SimX=6 and concluded "three orders of magnitude below nominal". That was a hex misparse —
the true values are `0x300`=768 and `0x600`=1536 against a nominal 1536, i.e. **SimX lost ZERO
updates and the DUT lost exactly half**, a clean 2:1.

**⚠ BOTH banks must now be re-run, not just 2CL.** FIX 1 changed all 10 riscv-dv programs (3
instructions at `_start`, all addresses shift 12 bytes) and FIX 2 changed `barrier_test`'s `.data`
layout. The clean 1CL bank of 2026-08-12 was produced from the OLD programs, so quoting it beside a
new 2CL bank would compare two different stimulus sets.

**⚠ The "expect at best 43/45" guidance below may now be WRONG.** `riscv_no_fence_test` and
`riscv_full_interrupt_test` fail by the same cross-core mechanism FIX 1 removes, so they may now
PASS. Treat 43/45 as a hypothesis to test, not a ceiling to assume — and if they still fail after
core-gating, the OBS-009 diagnosis for them needs re-opening.

---

#### (superseded detail — kept for the reasoning, not as instructions)

**All 8 of the first 2CL attempt's failures are root-caused and NONE is a DUT defect.** Do these
four, then re-run 2CL ONCE. Everything below is MEASURED — do not re-derive or re-guess it.

**FIX 1 — core-gate riscv-dv programs (OBS-027, the big one).** riscv-dv emits a **single-hart**
program and its hart dispatch is a structural NO-OP (`csrr x5,0xf14; li x6,0; beq x5,x6,0f` where
the branch target falls through to the same `h0_start`), so **every core runs the identical stream
regardless of `mhartid`**. Vortex cores all self-start from reset (`VX_schedule.sv:230`) ⇒ at 2CL
four cores concurrently execute one single-hart program against the SAME `.data` addresses with no
fences. Store ORDER then decides each value, and the timing-accurate RTL orders differently from
functional SimX. *Do:* add post-processing in `prepare.sh` so non-zero cores exit immediately (read
`VX_CSR_MHARTID`/gtid, `vx_tmc(0)` if != 0). *Accept:* `riscv_rand_instr_test` at 2CL gives 0
mismatches. ⚠ **Until this lands, EVERY riscv-dv result at ≥2 cores is architecturally undefined
and must not be quoted as a DUT pass OR failure.**

**FIX 2 — core-scope `barrier_test` (OBS-026).** `bar2_stall` is a shared `volatile int` incremented
NON-ATOMICALLY by every warp purely as a delay, read by nothing ⇒ no architecturally-defined value.
At 2CL, 4 cores x 4 warps race on it. The DUT is RIGHT: the kernel self-grades and the DUT wrote
`0x900DCAFE` (errors==0) while SimX wrote `1`; every CHECKED array matches. *Do:* make all cores
except core 0 exit, and make the delay loop warp-local. *Accept:* 0 mismatches at 2CL.

**FIX 3 — raise the two MEASURED budgets** (both were only 3–10% short, i.e. fragile even when
passing, and the shortfall was MASKING the divergences above):
| test | MEASURED need | current | where |
|---|---|---|---|
| `barrier_sync_test` | **164,602** cyc | 150,000 | `run_suite.sh:152` |
| riscv-dv (all) | **205,982** cyc | 200,000 | `run_suite.sh:71` |
Set them with real margin (≥3x), not to the measured number.
*(SimX's own cap is already fixed: `f90a18c` raised the default 2,000,000 → 20,000,000 from the
measurement that `wide_stress` @2CL needs **2,584,300** SimX cycles. `wide_stress` now PASSES —
33,004 words compared, 0 mismatches.)*

**FIX 4 — decide FW-1b.** `riscv_pmp_test` ≡ `riscv_non_compressed_instr_test` are BYTE-IDENTICAL
programs (`.S` md5 `16be14c6…`) testing neither PMP nor non-compressed instructions — measured 0
`pmpcfg`/`pmpaddr` writes and 0 compressed instrs, because their `gen_opts` are inert at
`--target=rv32im`. Either drop both and state the honest test count, or make the options effective.
*Accept:* every riscv-dv entry in `run_suite.sh` produces a program with a DISTINCT md5 — assert it
in the suite so it cannot regress.

**THEN re-run 2CL once.** Expect at best 43/45 (`riscv_no_fence_test` +
`riscv_full_interrupt_test` remain documented SimX cross-cluster divergences — do not "fix" them).
**BANK IT IMMEDIATELY**: `run_suite` merges into `cov/merged.ucdb`, so an unbanked result is
destroyed by the next config's merge (this nearly lost the clean 1CL bank on 2026-08-12).

**(3) RE-BANK 2CL — ATTEMPTED 2026-08-12, RESULT REJECTED (37/45 staged, 8 FAILED). DO NOT QUOTE
its 88.76% / 947-1095 bins: an incomplete merge is not a bank.** Full root-cause of all 8 in the
"2CL FAILURE TRIAGE" block below; none is a DUT defect. **Prerequisites before re-running:**
(a) measure and raise the three budgets — do NOT guess, `text_big` was fixed at a MEASURED
490,468 cycles; (b) commit the two TB fixes (scoreboard `-2` handling, `SIMX_MAX_CYCLES`) with a
non-vacuity proof for each; (c) decide FW-1b (the duplicate/vacuous riscv-dv pair).
**Expect AT BEST 43/45 — never 45/45 at 2CL.**
The banked 2CL numbers are from 2026-07-10
(total 85.16%) and are **stale** — they predate L2/L3 enablement, the G1 cache probe, A3, A6, B2,
B1, the icache waivers and the `.svh` change. Requires an RTL + SimX rebuild for the config:
`CLUSTERS=2 CORES=2 WARPS=4 THREADS=4 bash scripts/run_suite.sh`.
**EXPECT 43/45, NOT 45/45** — `riscv_no_fence_test` and `riscv_full_interrupt_test` fail at 2CL by
documented SimX cross-cluster divergence (`docs/investigations/SimX_2CL_no_fence_divergence.md`),
NOT a DUT bug. `run_suite` stages only passing runs, so the bank stays clean either way; do not
"fix" those two.
**`7863b44` is required for this step to be valid** — `run_suite.sh` now exports
`COV_NCL/NC/NW/NT` to the merge. Before it, `merge_coverage.sh` fell back to its 1/1/4/4 defaults
(`merge_coverage.sh:48`) and would have banked 2CL with **1CL exclusions** — e.g. the single-core
`is_global` barrier waiver applied to a build where that barrier IS reachable.

**(1) ✅ DONE `59b7ea2` — `.svh` convention.** 53 `` `include ``-d class files renamed; all 53
verified to contain only a class first. Packages/modules/interfaces/tb_top keep `.sv`.
**It also exposed a real defect:** 27 of those files were BOTH `` `include ``-d into their agent
package AND listed standalone in `uvm_env.flist`. Questa runs single-file-compilation-unit mode
(no `-mfcu`, `compile.sh:109-140`), so each compiled a second time into its own `$unit` package
("Compiling package axi_driver_sv_unit", vlog-13233) that under SFCU **nothing could reference**.
Removed. Note `uvm_env.flist` is **CRLF** — path edits must be CRLF-aware or they silently match
nothing.

**(2) ✅ DONE — 1CL RE-BANKED CLEAN, 45/45, 0 FAILED.** First bank that includes `text_big` and
carries B2+B1+A3+A6+L2/L3+G1+icache waivers, from ONE consistent compile with staging cleared
(`run_suite.sh:207` calls `--fresh` itself). **Total 91.08%** · stmt 96.82% · branch 91.06% ·
cond 76.03% · toggle 78.42% · assert 96.09% · directives 100% · **covergroup bins 398/403 =
98.75%** · 2,256 instances. Supersedes the 44-run merge (90.90%, 398/407) which must never be
quoted.

**(4) ✅ DONE `5c4b70f` — icache structural waivers, PREDICTION CONFIRMED.** Predicted 398/403;
measured 398/403. The denominator fell 407→403 and **not one covered bin moved** — the signature
of a correct structural waiver.
- **icache `cp_rw.wr`** + the two `cross_rw_hit <wr,*>` bins — **STRUCTURAL**: icache is
  instantiated `.WRITE_ENABLE (0)` at **`Vortex/hw/rtl/VX_socket.sv:106`** (NOTE: the old plan text
  said `hw/rtl/core/VX_socket.sv:107` — **both the path and the line were wrong**; verified 106,
  with the `.WRITE_ENABLE(1)` dcache at :152). `VX_cache_bank.sv:271`/`:590` are generate-gated on
  it, so there is no write datapath at all.
- **icache `cp_event.flush`** — **STRUCTURAL**: `MEM_REQ_FLAG_FLUSH` has exactly **one** producer,
  `core/VX_lsu_slice.sv:73` `= req_is_fence`, driving the **dcache**; `VX_fetch.sv` has no flush
  logic and `cache/VX_cache_init.sv:91` is the consumer.
- **ONLY TWO `ignore_bins` WERE NEEDED.** Waiving `cp_rw.wr` removes `<wr,hit>`/`<wr,miss>` from
  `cross_rw_hit` automatically — a cross is built from the coverpoint's REMAINING bins. Waiving
  the cross bins separately would have been wrong.
- `WRITE_ENABLE` is passed through the existing `bind` from the bank's own parameter, so the
  waiver is per-instance and config-generic. Measured: dcache 15 bins, icache 11.
- **icache + dcache `cp_mshr_stall.stall`** — **NOT structural**, a genuine stimulus gap. Left
  honestly uncovered; they are 2 of the 5 residual misses. The other 3 are the long-documented
  weight-0 red herrings (`mem_usage_cp`, `system_mem_cross`, `cp_occ`), which is why the weighted
  covergroup metric reads 99.12% against 98.75% raw bins.

### 2CL FAILURE TRIAGE (2026-08-12) — all 8 root-caused, NONE a DUT defect

**First, the thing that will be assumed and is WRONG: the laptop slept mid-run, and that is NOT
the cause.** Every failure is a simulation-time or model-internal cap; a suspend freezes the
process without advancing simulation time and cannot produce any of them. The run is sound.

| test | evidence | class |
|---|---|---|
| `wide_stress` | SimX exit **-2** = hit its own `MAX_CYCLES=2000000`; golden image truncated ⇒ **all 4,115** mismatches read `SimX=0x0` while DUT retired 577,569 instrs correctly. DUT budget was already 40M — only the GOLDEN model was starved | **budget** |
| `barrier_sync_test` | DUT TIMEOUT @150,000 (`run_suite.sh:152`) | **budget** |
| `riscv_rand_instr_test` | DUT TIMEOUT @200,000 (`run_suite.sh:71`) | **budget** |
| `riscv_mmu_stress_test` | clean exits both sides; mismatches are two DIFFERENT non-zero values; passed at 1CL | **OBS-009 divergence** |
| `riscv_non_compressed_instr_test` | same as ↓ — these two are the SAME PROGRAM (FW-1b) | **OBS-009, double-counted** |
| `riscv_pmp_test` | `.S` md5 `16be14c6…` identical to non_compressed | **OBS-009, double-counted** |
| `riscv_no_fence_test` | documented SimX cross-cluster divergence | **expected** |
| `riscv_full_interrupt_test` | documented SimX cross-cluster divergence | **expected** |

**TWO REAL TB DEFECTS THIS EXPOSED — the important output of the whole exercise:**
1. **The scoreboard ignored the `-2` sentinel.** `-4` (GOLDEN_HALT) and `-3` (CRASH) return early
   and skip the end-state compare; **`-2` (CAPPED) fell straight through into
   `compare_all_written()`**. That is the exact mechanism by which "the golden model ran out of
   budget" became 4,115 `MEM MISMATCH` errors indistinguishable from DUT data corruption. Fixed:
   `-2` now skips the compare and classifies the run UNVERIFIABLE, naming the cap and the env var
   to raise it. **This is the same lesson as the B1 DCR bugs and OBS-024: a firing checker is NOT
   evidence of a DUT defect until you establish which side is right.**
2. **`MAX_CYCLES` was hardcoded** at 2,000,000 with the comment *"basic needs ~1800; huge margin"* —
   sized for small kernels. A fixed cap cannot be right across program sizes and core counts, and
   when it is wrong it FABRICATES failures rather than reporting a budget problem. Now overridable
   via **`SIMX_MAX_CYCLES`** (env, default unchanged).

**B2 ✅ CLOSED — do not re-open it, and specifically do not "finish" it by deleting the write
mask.** What actually landed (see the milestone block above for the full result table):
- `shadow_memory` deleted; `dut_mem` (`mem_model`) is the **single** DUT value source.
- `shadow_valid` → `dut_write_mask`, **kept deliberately**. It is a write-SET, not a data
  shadow. It supplies (a) byte-granular SimX-poison filtering and (b) the forward/reverse
  discrimination that keeps the `fe10b83` dropped-store guard alive. The plan's original
  "delete both" wording was wrong and is corrected here.
- Dead `compare_result_region` (never called) deleted; `mem_model` now mandatory (`uvm_fatal`).
- **Differential validation:** 11 tests re-run against stored pre-B2 baselines, **18,749 word
  comparisons reproduced exactly**, both negative tests still RED at the same address.
- **OBS-023** logged: dropped *sub-word* store into a partially-written dword is invisible
  (pre-existing, bounded, OPEN — closing it needs its own non-vacuity proof).

**B1 (start here):** UVM RAL model for the DCR register space. Preconditions are already met —
the DCR agent is active and `write_dcr` mirrors into SimX (`vortex_scoreboard.svh`
`simx_dcr_write`), so a RAL frontdoor has a working path. Gate: DCR-driven tests unchanged and
`host_coverage_test` still green.

**CLOSED 2026-08-07 (session: L2/L3 + cache coverage + A6 + B2):**
- **B2 ✅ scoreboard → single `mem_model`** (above).
- **A6 ✅ Spike independence audit** — Spike/SimX/DUT all retire **exactly 11,076** writebacks
  on `riscv_arithmetic_basic_test_0.elf`, **0 mismatches**, all 11,076 value-compared,
  non-vacuity proven by injecting at record 5000 (named exactly, exit 1). New: `+LOCKSTEP_TRACE=<path>`
  (default OFF) in `lockstep_scoreboard.svh`, `LOCKSTEP_TRACE` env in `simulate.sh`,
  `scripts/spike_audit.py`. Commit `8e1a3b2`. Doc: [`docs/A6_SPIKE_INDEPENDENCE_AUDIT.md`](A6_SPIKE_INDEPENDENCE_AUDIT.md).
- **cache_tier @2CL L2+L3** — 57,379 lockstep pairs all matched, 16,620 byte-exact end-state
  words, 0 errors, **0 memsched response timeouts** (OBS-017 guard holding).
- **15-kernel L2/L3 sweep @2CL** — **12/15 residual 0, identical to the pre-L2/L3 baseline**
  ⇒ enabling the shared caches changes timing but **no architectural outcome** (corroborates
  OBS-018). Non-zero: `diverge_lite` 372 (raw 58) and `diverge_fpu` 328 (raw 254) — residual
  **larger** than raw ⇒ ENH-2 feed non-convergence ⇒ **INCONCLUSIVE, not a DUT bug**;
  `fpu_mt` 89→81 is a genuine partial residual.
- **Gap G1 closed** — `tb/vx_cache_probe.sv` (`cache_event_cg`) bound into `VX_cache_bank`;
  8 instances @2CL L2+L3. Config-aware **by construction**: `VX_cache_wrap.sv:160` builds
  `VX_cache` only when `PASSTHRU==0`, so L2/L3-off creates no instance and no bins to waive.

**⚠ THREE THINGS A FRESH SESSION MUST NOT RE-DERIVE**
1. **`lockstep_sweep_2cl.sh:84` calls `run_one "$k" 0`** — a bare tier1 sweep runs **without**
   `+LOCKSTEP_LOADFEED` and reports 8/15 "failing". Those are raw pass-1 divergences and are
   **NOT comparable** to the feed-armed 12/15. Always state which mode a number came from.
2. **Lockstep is writeback-domain only** (OBS-022): `lockstep_scoreboard.svh:16`,
   `vx_commit_probe.sv:99`, `lockstep_scoreboard.svh:311`. Branches/`jalr x0`/`nop` never enter
   the stream (a wrong branch is caught only indirectly, via the successor's PC), and **stores
   are outside lockstep entirely** — they are covered by the end-state compare. This bounds
   what "per-instruction lockstep" may be claimed to mean, and it matters directly for B2.
3. **A6 does not cover SIMT.** Spike is scalar: warp0/lane0/base-ISA, stopping at the first
   Vortex custom op. Never let A6 be quoted as "independently verified the design".

---

### ▶▶ PRIOR NEXT ACTION (2026-08-06)

**SESSION 2026-08-06 — per-instruction closure (TCU/FPU/SFU) + cache-config integrity.**
16 commits: `24818e3` `2ca64d0` `8cc455a` `483a655` `250765c` `11e0e48` `76d4360` `ce68a4e`
`e5f1cd8` `cc55469` `a915788` `14a3692` `5e636e7` `1ae1864` `96fc7e0` `81b104e` `fa31cbb`.

**CLOSED THIS SESSION**
- **TCU ✅ lane-exact @1CL AND @2CL** (tcu_test 785/785 · 2789/2789; tcu_mt 1179/1179 · 3399/3399).
  Four COMPARATOR representation layers fixed (DUT proven correct throughout): FP rd-index
  (unified 32+n vs local+is_fp), FP writeback NaN-box, FP **load** NaN-box, and WMMA
  multi-register retirement (instruction-grouped alignment; `po_base`/`po_order` fold the
  tile sub-index in uuid[31:28]).
- **FPU ✅ CLOSED — OBS-014 is a REAL RTL BUG.** DUT hardware `fsqrt.s` is **1 ULP off** the
  IEEE-correct SoftFloat result. End-state's FP tolerance had been HIDING it; per-instruction
  lockstep exposed it. Handled two-layer, sqrt-ONLY: bounded 1-ULP tolerance (logged+tallied,
  `+ - * / fma cvt` stay bit-exact) + **two-pass sqrt reconvergence feed** (`compfeed_*`)
  that forces the certified DUT sqrt into SimX's FP regfile so downstream ops are re-checked
  bit-exact. fpu_test 1675 ✅, fpu_mt ✅.
- **SFU ✅ CLOSED — OBS-015 (ref-model bug).** SimX's CSR ops looped lanes sequentially over
  the shared per-warp `fcsr`, so lane t read what lane t-1 wrote. Fixed to read-once/write-once
  (lowest ACTIVE lane). sfu_masks data-mismatch **109 → 0** (3178 matched). The RTL's
  unconditional `rs1_data[0]` write is deliberately NOT mirrored → stays visible.
- **Non-vacuity gate phase-ordering bug** (`11e0e48`): the gate read its counters in run_phase,
  but under `+LOCKSTEP_LOADFEED` the end-state compare is deferred to report_phase and lockstep
  compares in check_phase ⇒ false "no functional verification performed". fpu_mt actually does
  68 end-state comparisons + 1412 lockstep pairs. Verdict moved to report_phase.

**2CL SWEEP: 5 → 12 of 15 verified** — 7 lane-exact (vecadd_lite, tcu_test, tcu_mt, vote_shfl,
div_edge, spawn_tmc_sweep, bar_masks) · 5 race-explained residual=0 (diverge_deep/peel/uni3,
fpu_test, sfu_masks) · **3 inconclusive** (diverge_lite 372, diverge_fpu 328, fpu_mt 81).
⚠️ The 3 are **feed NON-CONVERGENCE** (ENH-2: fed loads steer control flow ⇒ SimX walks a new
path and meets fresh unfed races), **NOT evidence of a DUT bug** — all are lane-exact at 1CL.

**OBS-009 NOW ARCHITECTURALLY GROUNDED (not inference):** MICRO'21 §4.1.4 — *"Flush operations
among caches are provided as a means of providing **weak coherent memory space**"*; §3.1 uses
the RISC-V `fence`. RTL confirms: **zero** hits for `snoop|coheren|invalidat|MESI|probe_req`
across `hw/rtl/cache/*.sv`; only `flush` exists. L1 dcache is per-SOCKET (`VX_socket.sv:135-138`),
L2 per-cluster, L3 per-GPU. ⇒ a fenceless cross-cluster kernel has **no architecturally-defined
single result**; DUT≠SimX there is expected, not a bug.

**CACHE-CONFIG INTEGRITY (unplanned but prerequisite — dead config was hiding real bugs)**
- **OBS-016** — L2/L3 were **UNBUILDABLE**: `vortex_config.sv` expanded RTL *presence* guards as
  if they had values (``l2_enable = `L2_ENABLE;`` → ``= ;``). So those two cache levels had
  **never been exercised**, and the L2/L3 coverage waivers were unreachable-by-TB-construction.
- **OBS-017** — fixing the build immediately exposed a real RTL guard bug: `VX_mem_scheduler.sv`
  hardcoded a **~1000-cycle** response timeout (TIME units, shadowing the configurable global) →
  22,187 FALSE timeouts on runs that completed correctly. Promotes **OBS-011** (`1 ** N ≡ 1`,
  the scaling that never scaled) from latent to CONFIRMED. Fixed via `STALL_TIMEOUT_SCALE`.
  ⚠️ The two guards are in DIFFERENT units (cycles vs `$time` ps) — do NOT merge them.
- **OBS-018** — enabling L2+L3 does **NOT** remove the cross-cluster races: results bit-identical
  on all 15 kernels while cycles moved **+80%** (tcu_test 12,215 → 21,968), i.e. timing changed
  a lot and architectural outcome not at all ⇒ the divergences are structural, not timing flukes.
- **OBS-019** — `vortex_config.sv` duplicated the RTL cache geometry as hand-written fallbacks
  that were ALWAYS used (UVM compile never includes `VX_config.vh`) and had **drifted**
  (L3 said 1 MB, RTL is 2 MB; line size hardcoded 64). Fixed: `VX_gpu_pkg` now EXPORTS the
  elaborated geometry and the TB reads it ⇒ drift impossible by construction. Also gated the
  **structural-plusarg hazard** (`+L2CACHE`/`+L3CACHE`/`+XLEN_64` used to OVERRIDE at runtime,
  making the TB believe hardware that isn't there) — now I2-style asserts, **proven non-vacuous**
  (both abort rc=2 with an explanatory message naming the rebuild command).

**TERMINAL CONTROL (no hardcoding):** `make sim ... L2=1 L3=1 ICACHE=0 DCACHE=0`
(Makefile → `--l2/--l3/--icache/--dcache` → `+define+`), plus `EXTRA_RTL_DEFINES` (compile) and
`EXTRA_PLUSARGS` (sim) escape hatches. Defaults mirror RTL ⇒ default build byte-identical.

**▶ OPEN / NEXT (in order)**
1. **Close the cache thread:** `cache_tier` kernel is BUILT + fully parametrized but **NOT
   VALIDATED** (`Vortex/tests/kernel/cache_tier/`, phases default OFF; run
   `make CT_P1=1 CT_P2=1` then `make sim ... L2=1`). Then confirm from the coverage DB that
   L2/L3 **hit-path** bins actually moved. Also **re-run the 15-kernel L2/L3 sweep** — only
   `tcu_test` has been re-checked since the OBS-017 fix.
2. **Phase B — B2 scoreboard → single `mem_model`** (the designated plan next-action).
3. **A3 abort hardening** — see below.

**WHY A3 IS "PARTIAL":** A3 = *retire the UNVERIFIABLE bucket* by hardening SimX's
`std::abort()` paths. Done so far: OBS-008 (misaligned fetch) fixed, `DECODE_ABORT()` now
self-documents (prints faulting PC + instr word), and BOTH 2CL cases (`no_fence`,
`full_interrupt`) now RUN to EBREAK instead of aborting. NOT done: **~10 riscv-dv / regression
programs still abort** (SIGABRT → exit −3 → UNVERIFIABLE), and **69 `std::abort()` remain**
**SUPERSEDED 2026-08-06 — A3 IS CLOSED.** The count above was never re-measured and was
stale twice over. (a) Most of the "69" lived in `op_string()`, the DISASSEMBLY pretty-printer
— off the execution path entirely, so aborting there voided runs for a purely cosmetic reason
(OBS-020). The real semantic surface was 39, not 69. (b) The "~10 riscv-dv still abort" claim
was also stale: re-running all 10 retained tests gives **zero SimX aborts** and real byte-exact
compares (15..1414 words each). Earlier SimX fixes had already retired the bucket.
The RVC premise behind the A6 note was wrong too — RVC is excluded upstream at the toolchain
level (`prepare.sh:321` `--target=rv32im`), so no compressed instruction is ever generated, and
Spike (no SIMT model, cannot execute a Vortex kernel) could never have supplied the missing
verdict anyway. What shipped instead: refusals are KEPT (a golden must refuse, not fabricate)
but now RECORD pc/instr/sub-field → DPI returns **-4 GOLDEN_HALT** vs **-3 CRASH**, the verified
prefix survives, and `SIMX_FORCE_HALT` proves the path non-vacuous. See OBS-020.

### ▶▶ NEXT ACTION (exact, resumable — 2026-07-17)
**2CL DIRECTED-SUITE LOCKSTEP SWEEP = DONE (this session).** Ran the 15 deterministic
directed kernels under per-instruction lockstep at 2CL/2C/4W/4T (`scripts/lockstep_sweep_2cl.sh`),
then load-feed-classified every RED, then ran a 1CL control to separate multi-cluster race
artifacts from genuine differences. Findings:
- **5 lane-exact at 2CL** (vecadd_lite, vote_shfl, div_edge, spawn_tmc_sweep, bar_masks).
- **diverge/Bucket-B REDs = 2CL cross-cluster RACE artifacts, DUT CORRECT** (diverge_lite
  lane-exact 1850/1850 at 1CL; deep/peel/uni3 verify residual=0 modulo racy loads; lite/fpu/fpu_mt
  hit the two-pass fixed-point boundary = ENH-2). NOT bugs — end-state hides them, lockstep exposes
  them at instruction granularity. Same OBS-009 class.
- **TCU + FP REDs = COMPARATOR representation gaps, DUT PROVEN CORRECT** (ELF ground truth +
  end-state + SimX value agreement; SimX emits 0 qNaN FP writebacks — decisive). Root-caused to
  FOUR layers: (1) FP register index — DUT unified 64-entry (fp=32+n) vs SimX local-idx+is_fp;
  (2) FP writeback NaN-box width — SimX 64-bit boxed (upper32=0xFFFFFFFF) vs F-only DUT 32-bit;
  (3) FP **load** NaN-box width (flw) — same, on the LOAD-data compare path; (4) **WMMA multi-
  register retirement** — SimX exports one retire record per output-tile register (uuid high-nibble
  = tile index), the DUT merges its per-register commits by uuid into ONE record → the retire
  streams slip by ~N at the WMMA → the whole downstream PC/rd/data residual is that one cascade.
- **FIXES 1–3 COMMITTED + VALIDATED** (`lockstep_scoreboard.svh`, all `g.is_fp`-guarded so integer
  kernels are provably unaffected; low-32/FLEN compare keeps the FP VALUE bit-exact — real fixes,
  NOT waivers): vecadd_lite 1035/1035 (no regression) · **diverge_fpu RED→GREEN 2738/2738** ·
  fpu_mt data-mismatch 907→4. New `scripts/lockstep_sweep_2cl.sh` (checking-depth sweep, no UCDB merge).
- **LAYER 4 (multi-register WMMA retirement) = DONE for TCU, comparator-side (industrial choice —
  golden model kept faithful).** Implemented in `lockstep_scoreboard.svh`: (a) `build_dut` keys the
  merge by (uuid,rd) so multi-register retires split per-register; (b) `run_compare` rewritten to
  **instruction-grouped alignment** — group the DUT stream by instruction, take gold's leading
  same-PC records as that instruction's register writes, match by rd, and count tile registers the
  DUT doesn't expose as an explicit `multireg end-state-covered` bucket (their values verified by
  the end-state memory compare — honest, reported, never dropped); (c) `po_base`/`po_order` handle
  the WMMA tile's beat/round SUB-INDEX in uuid bits[31:28] (the RTL counter increments by 1, but the
  tile writebacks carry round<<28) — fold it for grouping, order it below the counter for the sort,
  so tile records stay at their program position instead of scattering. **Result: tcu_test 785/785,
  tcu_mt 1179/1179 — fully lane-exact, 0 mismatch, 0 orphan, PASS.** Zero regression (diverge_fpu
  2738/2738, vecadd_lite 1035/1035, diverge_deep 3264/3264). Config bound: per-warp retire < 2^28.
- **✅ CLOSED — fpu_test + fpu_mt (OBS-014, 2026-08-06, commit `483a655`).** Root cause was NOT a
  comparator gap: the DUT hardware **`fsqrt.s` rounds 1 ULP off** the IEEE-correct SoftFloat
  reference (real RTL FPU accuracy limitation — end-state's FP-tolerance had masked it; lockstep
  exposed it). The 1-ULP result then propagates through a spill/reload + a dependent `fmul`,
  producing the downstream cascade (the earlier "112 orphans / 4 mismatches" characterization was
  that propagation, not a libcall). Handled two-layer, sqrt-ONLY, keeping `+-*/` bit-exact:
  (1) **bounded 1-ULP tolerance** for `fsqrt` writebacks (SimX exports `is_fsqrt`; comparator
  `fp32_within_ulp`, each toleranced op logged + tallied); (2) **two-pass sqrt reconvergence feed**
  (`compfeed_*`, mirrors the OBS-009 load-bus feed) forces the certified DUT sqrt value into SimX's
  FP regfile at pass 2 so every downstream op is re-checked bit-exact. **fpu_test GREEN** (pass-2
  residual 0, matched 1675); **fpu_mt lockstep GREEN** (residual 0, 4 reconvergences). Gated on
  `+LOCKSTEP_LOADFEED`; default single-pass byte-identical. Full detail: `docs/RTL_OBSERVATIONS.md`
  OBS-014. **Follow-on FIXED (same session):** fpu_mt's residual 2 UVM_ERRORs were a
  **phase-ordering false verdict** in the non-vacuity gate, NOT a missing checker — under
  `+LOCKSTEP_LOADFEED` the end-state MEM compare is deferred to the scoreboard's report_phase and
  lockstep compares in check_phase, so both counters read 0 in run_phase where the gate sat.
  fpu_mt actually does 68 end-state comparisons + 1412 lockstep pairs. Gate moved to the test's
  `report_phase` (after both); still FAILS if both are 0. Regression: fpu_mt PASS, vecadd_lite PASS
  (84 + 1035), and BOTH Gate-0 negative guards still DETECT their injected faults.
- **FUTURE WORK (user-directed 2026-07-17): FLEN=64 / XLEN=64 support.** Current env is pinned
  RV32IMAF (XLEN=32, FLEN=32). The comparator's FP-box fix deliberately stays STRICT for FLEN=64
  (non-boxed gold → full-width compare). A real 64-bit build (D extension / RV64) needs its own
  config bring-up AND a dedicated coverage push (new tests to close 64-bit-specific bins) — do this
  ONLY AFTER all the 32-bit work is closed. Recorded here so the trajectory is on file (see C5/I6/D-matrix).

### ▶▶ PRIOR NEXT ACTION (2026-07-16)
**A5 RTL-ASSERT GATE = DONE (this session, pending commit).** Investigation found the gate
HALF-EXISTED since the original import: `simulate.sh` already counted `^# ** Error:` lines and set
EXIT_CODE=2 — but the verdict was **print-only** (simulate.sh never `exit`ed with it; run.sh sources
it last ⇒ `make sim`/`sim-only` always returned 0; `run_suite.sh stage()` grepped UVM's own "TEST
PASSED" from the transcript ⇒ RTL-assert failures invisible at suite level AND their UCDBs merged).
Fixes: ① `simulate.sh` final `exit $EXIT_CODE` (make now returns the real verdict 0/1/2/3);
② `Makefile compile:` tolerates verdict {2,3} from the 1-cycle smoke (TB's own "TIMEOUT after 1
cycles!" $error lands in the RTL branch); ③ `run_suite.sh` runners pass make's rc to `stage` — a
failing run prints `FAILED (RTL assertion|UVM/verdict)` + first error line, is NOT staged for the
coverage merge, and the suite prints a `SUITE VERDICT: N staged, M FAILED` line (make normalizes all
recipe failures to rc=2, so the label is classified from the transcript, not the rc); ④ legacy
`run_vortex_uvm_enhanced.sh` pre-T4 "-2" subtraction removed (hygiene; script is no longer the run
path — the make flow is). **NEW negative guard `Vortex/tests/kernel/misalign_neg/`** (deliberate
misaligned `lhu`, value discarded, constant store ⇒ scoreboard PASSES, ONLY the RTL-assert branch can
fail it — isolates the gate; keep OUT of run_suite, re-run after any verdict-logic change).
**Acceptance (2CL/2C/4W/4T):** misalign_neg → `TEST FAILED — 4 RTL assertion error(s)` (LSU assert at
PC=0x8000009c, addr=g_src+1) with UVM `TEST PASSED, 0 UVM_ERROR` ⇒ RED came ONLY through the RTL
branch, make rc≠0 ✓ · vecadd_lite → PASSED (0 UVM, 0 RTL), make rc=0 ✓ · `make compile` → rc=0 ✓ ·
bonus: config-mismatch run proved I2-fatal → crash verdict → make rc≠0 (previously silent 0) ✓.
**INV-4 RESOLVED (2026-07-16, same session — see below for the original finding):**
① TWO riscv-dv generator idioms deliberately set the jalr target LSB (spec-legal, expects `& ~1`):
`riscv_directed_instr_lib.sv:164` (jump-stream `offset=$urandom_range(0,1)`) AND
`riscv_instr_sequence.sv:295` (sub-program return routine `rand_lsb`). Both patched LOCALLY in
`~/riscv-dv` (`offset/rand_lsb → 0`, marked "VORTEX LOCAL PATCH (INV-4)"; revert when RTL
implements `& ~1`). First validation missed the second idiom (30→120 errors) — the derail is
multi-source; sweep generated `.S` for imbalanced `addi rd,ra,{1}`+`jalr` pairs when in doubt.
② `riscv_jump_stress_test` post-patch: **0 RTL error lines, TEST PASSED, rc=0** (was 30 asserts).
③ `riscv_unaligned_load_store_test` EXCLUDED from run_suite: its base_testlist gen_opts force
`+enable_unaligned_load_store=1` (7020 genuine misaligned asserts even post-patch) — the
2026-07-03 "becomes a normal aligned test" claim was WRONG; unaligned-data verification is
unimplementable on Vortex (OBS-013). ④ `riscv_illegal_instr_test` EXCLUDED: `.4byte
kIllegalSystemInstr` encodings decode as bogus-CSR ops on the trap-less DUT (OBS-013 CSR flavor).
⑤ `riscv_rand_jump_test`@2CL post-patch: 0 RTL errors but 7 end-state MEM MISMATCHes — load-feed
classified it as the **OBS-009 race class** (cid0 exact, byte-granular racy `lb`s, post-feed
end-state 0 mismatches) with a NEW method boundary: residual 15 (load=13) = racy loads STEER
CONTROL FLOW in a jump test → two-pass replay has no fixed point (ENH-2 iterated feed is the
closer). Left honestly RED at multi-core; expect it (like no_fence/full_interrupt) in the 2CL
lane. Suite now retains 10 riscv-dv profiles. Full evidence: RTL_OBSERVATIONS OBS-009 (extended).

**⚠️ INV-4 OPENED (riscv-dv jalr derail):** 12/12 riscv-dv suite profiles fire misaligned RUNTIME_ASSERTs
(30–7616/run) and now classify FAILED under the toothed gate. Root cause = OBS-012 (JALR LSB non-clear,
spec deviation) + riscv-dv's deliberate `label+1` jalr idiom (`riscv_directed_instr_lib.sv:162-165`,
`offset=$urandom_range(0,1)`) → odd PC → auipc-derived addresses inherit the skew → misaligned data
(OBS-013 silent corruption; SimX byte-accurate ⇒ divergence). NOT generated misaligned load/stores
(`support_unaligned_load_store=0` works). `riscv_illegal_instr_test` additionally trips the
invalid-CSR-write assert (0x6f3). Sign-off honesty note: the 2026-07-10 coverage banks contain those
13 UCDBs (gate was toothless then). **INV-4 fix (next box, user-confirmed plan):** patch riscv-dv
jalr `offset → 0` + decide illegal_instr disposition (drop from suite vs prepare.sh sed), regen,
validate 1–2 previously-flipping profiles → 0 `# ** Error` lines. Full detail: RTL_OBSERVATIONS
OBS-012/OBS-013 (+ OBS-008 "benign" note corrected).

#### Prior (A1(c), same day — context)
**A1(c) RVVI MONITOR MIGRATION = DONE, COMMITTED.** The D2a package-queue hand-off is replaced by
the D2b core-v-verif pattern: each bound probe (`vx_commit_probe`, `vx_lsu_probe`) instantiates its
own `rvvi_if` and self-registers in `rvvi_registry_pkg` at t=0; a `rvvi_monitor` (created only under
`cfg.enable_lockstep`) snapshots the registry at #1, drains every vif on `@(posedge vif.clk)` +
an `extract_phase` final sweep (extract precedes every check_phase ⇒ stream complete), and publishes
`rvvi_txn` on its analysis port; `lockstep_scoreboard` subscribes via `uvm_analysis_imp_rvvi`,
routing on `rec.kind` (COMMIT/LOAD) into local queues — `build_dut()`/feed logic byte-for-byte
unchanged. Transaction-level by design (no interface parameters ⇒ ONE `virtual rvvi_if` type for any
NCL/NC/NW/NT/SIMD/ISSUE); no clocking block needed (no class-domain signal sampling — signal-level
RVVI-TRACE + `mon_cb` is the ENH-1-era upgrade path, documented in `rvvi_if.sv`). Tool patterns
(interface-in-bound-module, package virtual-if registry, vif drain) pre-proven on Questa 2021.2 POC.
**4-run acceptance, every tally diffed vs pre-migration logs — ALL IDENTICAL, incl. end-of-sim
timestamps (@102995000 / @191515000):** ① vecadd_lite+LOCKSTEP 1035/1035 (74 load-cmp / 113
load-skip / 62 volatile / uuid 1034/1035) · ② inject caught at uuid=0/PC=0x80000000/lane0 DUT=5 vs
SimX=4 · ③ default run clean (no RVVI built) · ④ pinned no_fence@2CL feed: 20 racy → 138 cascade →
pass-2 residual 0 over 5432/5432, 936 load-cmp, pushed=consumed=20, PASSED. Monitor vif counts match
bind topology (2 @1CL/1C, 8 @2CL/2C) = config-generic proven. Files: `tb/rvvi_if.sv` (new),
`uvm_env/{rvvi_txn,rvvi_monitor}.sv` (new), `lockstep_pkg.sv` (queues deleted), both probes,
`lockstep_scoreboard.svh`, `vortex_env{,_pkg}.sv`, `flists/uvm_env.flist`.
**This closes the ENH-1 prerequisite** (streaming analysis path exists); ENH-1/2/3 stay PARKED.

#### Prior (A1(e), same day — context)
**A1(e) RVVI LOAD-BUS + mem_model end-state = DONE, both COMMITTED.** Real fix (option 1) as a sound **two-pass trace-replay**. Result on pinned no_fence@2CL: pass-1 **20** racy loads → **138** cascade; pass-2 **residual 0** over **5432/5432**; deferred end-state compare (real `dut_mem` vs post-feed SimX) → racy word matches → **TEST PASSED, 0 UVM_ERROR**. Commit `2dd48ea` (RVVI load-bus) + follow-on (end-state value source `shadow_memory`→`dut_mem`, keep `shadow_valid` for the write-set). Validated: vecadd_lite 1035/1035 (no-feed byte-identical) · negative fault-injection PASS (caught, non-vacuous) · negative dropped-store PASS (caught via reverse) · 2CL no_fence feed PASS. Files: `Vortex/sim/simx/{cosim_loadfeed.h,emulator.cpp,execute.cpp}`, `ref_model/{simx_dpi.cpp,simx_pkg.sv}`, `lockstep_scoreboard.svh`, `vortex_scoreboard.svh`, `scripts/simulate.sh`. Full writeup: `docs/investigations/SimX_2CL_no_fence_divergence.md` → "REAL FIX IMPLEMENTED".

**`full_interrupt`@2CL feed = DONE, honest result (2026-07-16):** load-bus collapses **116 → 7
residual** (data=1, load=6; consumed==pushed=82), does NOT reach 0. **Re-keyed the feed ordinal →
(cid,wid,PC,occurrence)** (robust to interrupt-inserted instructions) → residual **IDENTICAL (7)**,
which DISPROVES the ordinal-drift hypothesis: the residual is **keying-independent** = a genuine
interrupt-timing divergence (same-PC occurrence-count drift and/or feed-exposed new divergence; the
interrupt-affected PC executes a different count in DUT vs SimX). Not fixable by better *load* keying —
needs interrupt-*delivery* alignment. **NOT a DUT bug — end-state MEM compare (dut_mem vs post-feed
SimX) PASSES.** Method boundary: sound for data-only divergence (no_fence, residual 0), the load-feed
is not a fixed point for interrupt tests. Kept PC-occ key (more robust; no_fence stays 0). Documented:
RTL_OBSERVATIONS OBS-010. Do NOT force green.

**NEXT:**
1. ~~Resume A1(c)~~ **DONE 2026-07-16** (see block above).
2. **(Optional) run the feed across the 2CL directed suite** to confirm no other test regresses (feed
   default-OFF, so only explicit `+LOCKSTEP_LOADFEED` runs use it).
3. **A5 — harvest DUT native assertions** (route RTL `RUNTIME_ASSERT`s into the UVM error gate;
   see A.4 milestones). A6 (Spike audit) remains the independent secondary.

**DEFERRED ENHANCEMENTS (parked, revisit after priorities):** the full_interrupt instruction-
granularity residual and the true-RVVI step-follower rework are captured in the **🔮 DEFERRED
ENHANCEMENTS** section near the end of this doc — **ENH-1** (single-pass step-follower lockstep with
interrupt-delivery alignment — the real fix; A1(c) is its prerequisite), **ENH-2** (bounded iterated
feed — cheaper interim, may not converge), **ENH-3** (residual root-cause pinpoint). Do NOT start these
until the current milestone is done; full_interrupt end-state is already VERIFIED.

**Two-pass RVVI recap (how it works):** `cosim_loadfeed.h` holds a per-(cid,wid,LOAD-ordinal) override map (uuids differ DUT↔SimX so ordinal is the key; `consumed==pushed` self-checks alignment). `execute.cpp` LOAD case calls `loadfeed_next()` and, if a lane is flagged, overrides the aligned `rd_data`. `lockstep_scoreboard.check_phase` runs pass 1 (capture racy loads), pushes them via `simx_cosim_load_feed_push`, re-runs `simx_run()` (pass 2), re-compares; pass-1 divergences demoted to diagnostic ONLY when feed armed (residual is the verdict; unexplained divergences stay hard errors). `vortex_scoreboard` defers the end-state mem compare to `report_phase` (post-feed) when `+LOCKSTEP_LOADFEED`.

**Replay:** `LOCKSTEP=1 LOCKSTEP_LOADFEED=1 make -C vortex_uvm_env sim TEST=random_instruction_stress_test PROGRAM=<ABS hex> CLUSTERS=2 CORES=2 WARPS=4 THREADS=4 TIMEOUT=200000` (pinned no_fence `results/20260710/run_125857_.../riscv_no_fence_test_0.hex` — ABSOLUTE path; relative fails MEM_MODEL open). **Rebuild note:** after editing `Vortex/sim/simx/*`, the `make sim` path rebuilds SimX per-config; the enhanced-script DPI relink alone does NOT rebuild `core.o`.

### Session 2026-07-15 results (all committed)
- **SimX BUG FOUND + FIXED (`6dfe665`, OBS-008):** SimX fetched at the exact byte `warp.PC`. The DUT debug build keeps the **full odd PC** after a jalr-to-odd-target (`PC_BITS=XLEN`, identity `to/from_fullPC`, `VX_gpu_pkg.sv:75-82`) but its icache request is **word-aligned** (`VX_fetch.sv:101`). SimX mirrored the odd PC (correct) but read misaligned bytes → undecodable `0xb3018cd0` → `decode.cpp default: std::abort()` → run wrongly UNVERIFIABLE. Fix: `emulator.cpp` fetch `warp.PC & ~Word(3)`. **A `& ~1` on JALR was tried and REVERTED** — it de-syncs SimX from the DUT's odd PC (21968 phantom PC mismatches).
- **Decode-abort observability KEPT:** `decode.cpp` `DECODE_ABORT()` prints faulting PC + instr word before aborting → every UNVERIFIABLE-by-abort now self-documents.
- **Both 2CL UNVERIFIABLE cases now RUN (no abort):** regen `no_fence` and pinned `full_interrupt` reach EBREAK and do real compares. **No DUT bug found anywhere** — every divergence is fenceless/interrupt ordering or an unobservable-operand artifact.
- **A1(d) pinpoint (`28c84ab`):** pinned `no_fence` first divergence = `mulhu s0,s3,a3 @0x800004f4`, cluster-1 cores only, cluster-0 byte-exact.
- **OBS-009 root-caused:** the `mulhsu` divergence is **LOAD-FED** (first divergence moves to a load at seq 742), not a compute/CSR bug.

**A1(d) DONE (2026-07-15, commits `b029fe7` + this) — the original motivation, closed:**
- Enhanced `lockstep_scoreboard.svh`: **first-divergence-per-(cid,wid) capture** + dedicated report block + per-key uvm_error spew cap (config-generic; true n_mm_* tallies unaffected). Committed `b029fe7`.
- **Pinned no_fence hex REPLAYED under lockstep** (`results/20260710/run_125857_.../riscv_no_fence_test_0.hex`, regen OFF, 2CL/2C/4W/4T): reproduced the documented end-state mismatch (`0x80013dd8 DUT=0x28af8c40 SimX=0x2fff8c40`) AND **pinpointed first divergence = `mulhu s0,s3,a3` @ PC 0x800004f4, seq 278, cluster-1 cores (cid 2,3) only; DUT s0=0x3d75a09d vs SimX 0x3d009f79.** cluster-0 (cid 0,1) = 0 divergences (byte-exact). 0 orphans, 118 data-mismatches, PC/rd exact. Confirms per-cluster fenceless-ordering verdict at instruction granularity (mulhu inputs already diverged ⇒ upstream shared-load; NOT a DUT/compute bug). Full writeup: `docs/investigations/SimX_2CL_no_fence_divergence.md` → "First divergence — PINPOINTED".
- **REGENERATED no_fence@2CL is a DIFFERENT case:** SimX *aborts* (SIGABRT→exit −3, UNVERIFIABLE), lockstep proves DUT≡SimX byte-exact for all 17664 retires up to the crash. Non-vacuity proven by `+LOCKSTEP_INJECT` (17664→17663 matched, 1 caught DATA mismatch). See RTL_OBSERVATIONS OBS-007.
- **Not yet done in A1(d):** `full_interrupt` pinpoint (same method, one replay) and naming the exact upstream shared-load (needs LSU-writeback/regfile probe per OBS-002).

**A1 progress (branch `industrial_transformations`):**
- **A1(a) divergence — DONE:** `diverge_uni3` (nested asymmetric 3v1→2v1→1v1, heavy partial masks) `+LOCKSTEP` → **2668/2668 matched, 0 mismatches, PASSED.** uuid-group aggregation + tmask-union handle divergence with no code change.
- **A1(b) multi-core cid — DONE:** DUT `uuid` embeds flat `CORE_ID` (OBS-006 / `VX_uuid_gen.sv:40`), and `CORE_ID` is flat-global across clusters (`VX_socket.sv:227` + `VX_cluster.sv:132`), matching SimX `rec.cid`. Scoreboard now derives `(cid,wid)` from the uuid (`cid_of_uuid`/`wid_of_uuid`) — no probe/RTL change. All lockstep edits audited config-generic for ANY NC/NCL/NW/NT (fixed wid mask → `(1<<NW_BITS)-1` for non-power-of-2 NW). See `MEMORY.md` config-generic-edits.
- **CONFIG-MATRIX VALIDATED (empirical, all PASSED, 0 field-mismatch, 0 orphans):** 1CL/1C/4W/4T (1035/1035) · 1CL/2C/4W/4T (2 cores, 1801/1801) · **2CL/2C/4W/4T (4 cores across 2 clusters, 3333/3333 — cluster term of CORE_ID proven)** · 1CL/1C/2W/2T (855/855, nw_bits=1) · 1CL/1C/8W/4T (1423/1423, nw_bits=3). Axes covered: NCL∈{1,2}, NC∈{1,2}, NW∈{2,4,8}, NT∈{2,4}. Only unproven path = non-default `SIMD_WIDTH<NUM_THREADS` multi-beat sid-split (standard builds set `SIMD_WIDTH=NUM_THREADS` → single beat).
- **A1(c) NEXT:** migrate the D2a package-queue hand-off → **D2b `rvvi_if` + monitor** (core-v-verif `uvma_rvvi` style) — an SV interface bound at the probe, a UVM monitor publishing RVVI transactions, scoreboard subscribes via analysis port (replaces the global package queue).
- **A1(d):** run lockstep across the directed suite at 2CL/2C/4W/4T; use it to pinpoint the 2CL `no_fence`/`full_interrupt` FIRST-divergence instruction (the original motivation — currently "Future Work — needs lockstep"). Verify DUT/SimX flat-cid numbering agrees at ≥2 clusters (1CL/2C proved it at socket level; 2CL exercises the cluster term of the CORE_ID formula).

**A0 RESULT (verified in sim, branch `industrial_transformations`):** per-instruction RVVI-style lockstep working on `vecadd_lite` 1CL/1C/4W/4T → **1035/1035 architectural writebacks matched, 0 orphans, 0 field mismatches, TEST PASSED, 0 UVM_ERROR.** Injection (`+LOCKSTEP_INJECT`) caught at exact uuid/PC/lane (`DUT=5 vs SimX=4`) = non-vacuous. Default (no `+LOCKSTEP`) path byte-identical (lockstep SB not built), PASSED. Loads (187) + perf-CSRs (62) correctly scoped out of the data compare.

**What was built (12 files, all in main repo — Vortex/ is tracked, not an active submodule):**
- **NEW:** `lockstep_pkg.sv` (RTL↔class hand-off: global `dut_retire_q[$]` + `lockstep_en`/`inject_en` gates, macro-free struct), `lockstep_scoreboard.svh` (`check_phase` comparator + 4-way taxonomy + report).
- **MODIFY (env):** `vx_commit_probe.sv` (passive per-beat capture on `+LOCKSTEP`, `to_fullPC`, `+LOCKSTEP_INJECT` 1-bit flip; `LS_LANES` derived from signal width — `` `SIMD_WIDTH `` NOT visible in probe compile unit), `vortex_config.sv` (`rand bit enable_lockstep`, `+LOCKSTEP` forces `simx_enable`), `vortex_env.svh` (gated `m_lockstep_scoreboard`), `vortex_env_pkg.sv` (import+include), `flists/uvm_env.flist` (lockstep_pkg before probe), `scripts/simulate.sh` (`LOCKSTEP`/`LOCKSTEP_INJECT` env→plusarg).
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

> **RECONCILED 2026-07-14 — W1 export is ALREADY BUILT** (committed `554080e` "changes in simx to verify microarch"). Present in-tree: `simx_retire_t` record ([simx_cosim_record.h](../Vortex/sim/simx/simx_cosim_record.h): uuid/cid/wid/pc/tmask/wb/is_fp/rd/sop/eop/result[32]); export hook at [core.cpp](../Vortex/sim/simx/core.cpp):229 (writeback instrs); queue in `processor_impl.h`; DPI exports `simx_cosim_pop/_pending/_clear` ([simx_dpi.cpp](../vortex_uvm_env/uvm_env/ref_model/simx_dpi.cpp):869); SV DPI **imports** + `simx_retire_s` mirror in `simx_pkg.sv:60-95`. **What's MISSING = the consumer** — nothing calls `simx_cosim_pop()`; `vortex_scoreboard.svh:83` marks lockstep "out of scope"; `vx_commit_probe` only counts (no publish path); the `simx_golden_model` component in `simx_pkg.sv` is a **dead stub** (never instantiated, `ap.write` commented out); the LIVE SimX driver is `vortex_scoreboard.svh` (`simx_init/load/dcr_write/run`). A0 is therefore *the DUT capture path + comparator + wiring*, not the export.

#### Phase-A locked design decisions (2026-07-14)
- **D1 = b + c (compose):** repurpose the dead `simx_golden_model` stub → the **golden agent** (drains `simx_cosim_pop()` after the run, publishes golden retire txns on its `ap`); add a **dedicated `lockstep_scoreboard`** comparator. Producer/checker separation. Delete the dead-stub behaviour, keep the shell.
- **D2 = a → b (staged):** A0 uses a **package-scope retire queue** the bound probe pushes to (simplest, keyed by `cid`); **A1 migrates to the professional `core-v-verif` pattern** — a bound **`rvvi_if`** driven by the probe + a UVM **monitor** obtaining the vif via a registry (mirrors `uvma_rvvi`). **[D2b DONE 2026-07-16 — A1(c); registry package instead of config_db (no UVM dependency in the module domain), see RESUME block.]**
- **D3 = post-run `uuid`-map alignment:** SimX runs to completion in one `simx_run` call and queues ALL retirements; the DUT retires live. Align by **`uuid` (instruction identity), not by cycle** — `dut_map[uuid]` built live, `gold_map[uuid]` drained after `simx_run`, compared per active lane. Both maps must drain empty (dropped/extra retirement check).
- **SimX-run coordination:** keep `simx_run` in the end-state scoreboard (path untouched); the golden agent drains the retire queue *after* it, sequenced via UVM objections — SimX is never run twice.

- **A0 — Lockstep PoC (the actual remaining work):** (1) extend `vx_commit_probe` to push each `retire_fire` record `{uuid,wid,PC,rd,wb,tmask,data[lane]}` into a package-scope queue (D2a); (2) repurpose the stub into a `simx_golden_agent` that drains `simx_cosim_pop()` post-run and emits golden retire txns; (3) a `lockstep_scoreboard` that builds `dut_map`/`gold_map` by `uuid` and compares per active lane `{PC, rd, result[lane]}`; (4) add `cfg.enable_lockstep` (+plusarg) gating so default runs are byte-identical; run `vecadd_lite`. *Accept: (a) lane-exact match to completion; (b) an injected 1-bit corruption is caught at the exact `uuid/PC/lane`; (c) **PROVE `uuid` identity aligns DUT↔SimX 1:1** (the key A0 risk — else fall back to `(wid, per-warp seq)` alignment). Reuse the existing `simx_retire_t` export as-is.*
- **A1 — Multi-thread + divergence:** compare all active lanes through split/join. SimX already models IPDOM, so this exercises the comparator's tmask/lane alignment, not new golden logic. *Accept: `diverge_lite`/`diverge_deep` match lane-exact through divergence/reconvergence.*
- **A2 — Multi-warp + wspawn + barrier + LSU mem-compare:** warp scheduling, `wspawn`, `bar` (local); extend the record with `LsuTraceData.mem_addrs` for load/store address+data compare. *Accept: `spawn_tmc_sweep`, `barrier_lite`, a memory-heavy kernel match.*
- **A3 — W2 abort hardening → retire the UNVERIFIABLE bucket:** as the ~10 riscv-dv/regression programs hit `std::abort()`, fix the encoding (RVC/CSR) or convert to graceful-unsupported. Re-run under lockstep. *Accept: each renders a real per-instruction verdict (pass or pinpointed divergence); 0 remain "UNVERIFIABLE" for handled encodings, the rest cleanly classified.*
- **A4 — 2CL first-divergence pinpoint:** run `riscv_no_fence_test` at 2CL under lockstep; report the exact first divergent instruction (closes the documented 2CL "Future Work"). *Accept: a proven SimX modeling limit or a real DUT bug, cited to an instruction + `file:line`.*
- **A5 — Harvest DUT native assertions:** route the RTL's own `RUNTIME_ASSERT`s into the UVM error count — IPDOM over/underflow ([VX_ipdom_stack.sv](../Vortex/hw/rtl/core/VX_ipdom_stack.sv) lines 50-52), MSHR integrity ([VX_cache_mshr.sv](../Vortex/hw/rtl/cache/VX_cache_mshr.sv) lines 210-217), `STALL_TIMEOUT` ([VX_schedule.sv](../Vortex/hw/rtl/core/VX_schedule.sv) line 415). *Accept: an injected violation fails the run through the UVM error gate.*
- **A6 — Spike independence audit (secondary): ✅ DONE (2026-08-07).** Cross-check the base-ISA subset per-thread against Spike. *Accept: base-ISA retirements agree Spike↔SimX↔DUT; any Spike/SimX disagreement documented.* **MET** on `riscv_arithmetic_basic_test_0.elf`: all three models retire **exactly 11,076** architectural writebacks and **all 11,076 agree on PC, destination register and value — 0 mismatches**. Proven non-vacuous by fault injection (record 5000 perturbed → named exactly, exit 1). Two annotated skips (Spike bootrom prefix; `x5` uninitialised by design because `prepare.sh` seds `csrr x5,0xf14`→`nop`), both verified benign. **Scope limit, do not overstate:** Spike is scalar — warp 0 / lane 0 / base-ISA only, stopping at the first Vortex custom op; SIMT has no independent reference and will not get one from Spike. Zero Spike modification (extending it to SIMT was rejected — it would recreate the very dependence FW-2 is about). Writeback-domain limitation logged **OBS-022**. Full method + results: [`docs/A6_SPIKE_INDEPENDENCE_AUDIT.md`](A6_SPIKE_INDEPENDENCE_AUDIT.md).

### A.5 Effort / risk
A0 (W1 + comparator) is the critical build and de-risks the rest — because the SimX golden already steps, traces, and reads back values, A0 is mostly the DPI export hook + a `uuid`-aligned comparator, not new golden logic. A1/A2 mostly stress the comparator. A3 (W2) is incremental C++ per abort. Primary risk = `uuid`/lane alignment between the DUT commit stream and SimX retirement order (SIMT interleaving) — mitigated by aligning on `uuid` (monotonic per core) rather than cycle. A6 (Spike) is independent and can slip without blocking A0–A5.

---

## Phase B — Verification structure

> ⚠️ **PROVISIONAL — the acceptance criteria and design notes in the boxes below were written
> BEFORE the corresponding RTL investigation. They are HYPOTHESES, not commitments.** Twice now
> plan text written ahead of the RTL has turned out wrong in a way that would have caused harm if
> followed literally: **B2** said "delete `shadow_memory` + `shadow_valid`" (deleting the mask
> would have silently killed the dropped-store guard and byte-granular poison filtering), and
> **B1** said the RAL could give "not read-back checking" and that CSR "can use readback if a path
> exists" (readback IS achievable via a bind probe; CSR has no bus at all). When a box is worked,
> **read the RTL first and correct this text in place** — do not treat a forward-looking criterion
> as a constraint.

- **B1 — RAL for DCR. ✅ DONE (2026-08-11, `8ff86a4`).** `uvm_reg_block` over the DCR base registers, write frontdoor through the existing `dcr_agent`, read side via the `bind`-ed `vx_dcr_probe`. Measured 15/15 observations checked / 0 failed on `host_coverage_test`; non-vacuity proven via `+DCR_RAL_INJECT`. **GATE DISCHARGED 2026-08-12 (`3c622cd`): at 2CL/2C the check reports `observations=60 checked=60 failed=0 cores_observed=4` — exactly 15×4, every core observed every write, zero mismatches.** The event-driven arming therefore survives the DCR broadcast tree (the OBS-025 hazard) with no tree-latency false positives, so it is now trustworthy as an INV-2 race detector.
  **`3c622cd` also added a COMPLETENESS check**, because the original checker validated every observation it *received* while nothing noticed observations that never *arrived* — a probe that silently failed to bind on a deep core produced a green result, and deep cores are exactly where OBS-025 lives. It now counts distinct probe `%m` paths against `NUM_CLUSTERS*NUM_CORES` (`VX_dcr_data` has one instantiation site, `VX_core.sv:82`; sockets subdivide cores rather than multiplying them, `VX_gpu_pkg.sv:99`), and `expected_instances==0` skips rather than guesses.
  **Config-generic across NCL/NC by construction; NW/NT are not a dimension** — DCR storage is per-core only, with no per-warp or per-thread state. XLEN is handled too: `STARTUP_ADDR1`/`ARG1` are `` `ifdef XLEN_64 `` in RTL, so on RV32 the reg block does not create them and the probe reports them `unmapped` rather than inventing storage.

  > ⚠️ **The original text of this box was written ahead of the RTL investigation and was wrong in two directions. Both are corrected here (see the PROVISIONAL note at the top of this section).** The superseded wording claimed the RAL would give *"abstraction + predicted mirror + reg coverage, **not** read-back checking (documented limitation)"*, and that *"CSR side can use readback if a path exists"*.

  **CORRECTION (a) — read-back checking IS achieved, exceeding the stated limitation.** DCR is indeed write-only (`Vortex/hw/rtl/interfaces/VX_dcr_bus_if.sv:18-31` has only `write_valid`/`write_addr`/`write_data`), so no *frontdoor* read exists. But a **`bind`-based probe on `VX_dcr_data` with a custom `uvm_reg_backdoor`** gives a real peek at `dcrs`, so `mirror(UVM_CHECK)` becomes a genuine check that each DCR write landed in the RTL register — something **nothing in the bench verifies today**. Same construction principle as `vx_commit_probe`/`vx_cache_probe`: `bind` instantiates once per RTL instance, so it is **config-aware by construction** and per-core coverage is free (no hierarchical path enumeration, no `add_hdl_path_slice`).
  **Peek only, never poke.** The scoreboard mirrors DCR writes into SimX off the monitored interface (`vortex_scoreboard.svh:403 simx_dcr_write`); a backdoor *write* would bypass that and silently desync the golden model. The frontdoor must remain the existing `dcr_agent` path so the waveform stays byte-identical.

  **CORRECTION (b) — CSR is OUT OF SCOPE, for two cited reasons. No B1b box is opened**, because an open box that can never honestly close is debt, not a decision.
  1. **No host-side bus.** There is no `VX_csr_bus_if` anywhere in `hw/rtl/`; `interfaces/` contains only `VX_commit_csr_if` and `VX_sched_csr_if`, both internal core plumbing. CSRs are architectural state reached by `csrr`/`csrw` **instructions**, so there is no protocol for a RAL frontdoor to model.
  2. **No verification content** (the stronger reason). Architectural CSRs are **already** verified by stronger checks: a kernel doing `csrr` + store feeds that value into both the end-state compare vs SimX and per-instruction lockstep. A `uvm_reg` backdoor compare would be a second, weaker check of something already covered. And the volatile MPM CSRs **cannot** be verified by a RAL at all — they are hardware performance counts whose RTL cycle behaviour legitimately differs from SimX, which is exactly why that range is marked `is_volatile` and excluded. A mirror has no reference to compare against.

  **Per-core check is ALWAYS ON and EVENT-DRIVEN (not bootstrap-gated) — see OBS-025.** Arming off the global TB `dcr_bootstrap_done` handshake produces a **false RED at ≥2 sockets/clusters**: the write traverses up to two `DEPTH=1` pipe stages (`Vortex.sv:138`, `VX_cluster.sv:129`) before reaching a deep core, so a bootstrap-armed check samples `dcrs` before the write arrives. Each bound probe must compare only after observing **its own** `write_valid` retire into `dcrs` — no latency constant, correct if the tree ever deepens.
  **Extra gate item:** run the per-core check at 2CL/2C **once** and confirm **zero** mismatches before trusting it as an INV-2 race detector — otherwise "found the race" is indistinguishable from "armed too early".
- **B2 — Scoreboard → single `mem_model`. ✅ DONE (2026-08-07).** `compare_all_written` now reads the DUT value **only** from `mem_model`; `shadow_memory` deleted; `.got`/POISON/FP-tolerance/inject-fault/drop-store logic all retained in the one pass. Validation gate met by **differential** against stored pre-B2 baselines (18,749 word comparisons bit-identical) + both negative tests still RED.
  **CORRECTION to the original spec above:** it predicted "`mem_model` holds real init bytes → the sub-word byte-mask hack becomes unnecessary". That is **half right**. The mask's *original* purpose (the sparse shadow reading back 0 on unwritten lanes) does dissolve once the value comes from `mem_model` — but the mask acquired a *second*, still-live purpose: it makes the SimX-`BAADF00D` poison gate **byte-granular**, and it is the forward/reverse discriminator for dropped-store detection. So `shadow_valid` was **kept** (renamed `dut_write_mask`), and only `shadow_memory` was deleted. Removing the mask would silently drop checks — see **OBS-023** for the residual blind spot and the clean way to close it.
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
- **D4 — Seed farm.** riscv-dv scaled to hundreds of seeds. **SUPERSEDED/ABSORBED by FW-1** (see the Verification-Maturity Assessment section) — seed control now EXISTS (prepare.sh:303-331, RV_SEED default 1, seed-keyed cache); what remains is seed VOLUME. (The old parenthetical here — "C-extension enabled once Spike is the reference, it decodes RVC where SimX aborts" — is obsolete: RVC is excluded upstream at the toolchain level, `prepare.sh:321 --target=rv32im`.)
- **D5 — Automated sign-off.** One report: pass rate, merged per-config coverage vs goal, matrix status, **requirements traceability matrix**, tool versions + seeds logged (reproducibility).

---

## Phase E — HW/SW co-verification & SoC integration (FUTURE WORK — out of current A–D scope)

> Scope note (added 2026-07-16): the current project is deliberately scoped as **GPU-core
> verification** — the DUT is `Vortex_axi` standalone, checked against a golden ISS. Phase E
> names the two scope *extensions* beyond that, so the trajectory is on record. Neither is
> part of the "industrial-grade" acceptance above; do NOT start these before A–D close.
>
> What we already have, honestly stated: **kernel-level HW/SW co-verification exists today** —
> every stimulus is real software (C kernels via the Vortex LLVM toolchain + `crt0`/`vx_spawn`
> runtime, riscv-dv programs) executing on the RTL with per-instruction lockstep vs SimX, and
> the host/dcr agents replay the real launch protocol (DCR STARTUP_ADDR/ARGV → start → busy).
> What Phase E adds is the *host-side software* and the *system around the GPU*.

- **E1 — Driver-in-the-loop co-verification.** Run the real Vortex host runtime
  (`libvortex` API: `vx_dev_open/vx_mem_alloc/vx_copy_to_dev/vx_start/vx_ready_wait`) as the
  actual sequence source — compiled to host code and bridged via DPI into the host/dcr agents,
  so the driver's own register-programming and completion-polling logic is what drives the DUT
  (today the agents replay a hand-modeled protocol). Payoff: verifies the SW/HW contract
  (launch, argument passing, completion, MMIO console) end-to-end; catches driver↔RTL protocol
  drift. Cost: DPI bridge + driver build for co-sim ≈ 1–2 weeks. Trigger: after A–D acceptance,
  or if the driver protocol changes upstream.
- **E2 — SoC-level integration & verification.** Minimal SoC top: RISC-V host core (or host
  BFM) + AXI interconnect + `Vortex_axi` as a peripheral + shared memory controller. Our AXI
  agent flips from active slave to **passive monitor** on the interconnect; system-level checks:
  address decode/map, host↔GPU shared-memory consistency (write-through GPU cache vs host view),
  DMA paths, interrupt/completion signaling at SoC level. Payoff: verifies the GPU *in situ*
  (role inversion removed); prerequisite for any FPGA/virtual-platform prototyping. Cost: weeks
  (SoC assembly + new checkers). Trigger: only if the project scope formally grows to SoC, or
  as the follow-on project after GPU-core sign-off.

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
- **Phase E (driver-in-the-loop, SoC integration) is strictly AFTER A–D acceptance** — future-work scope extension, not part of the industrial-grade definition of done below.

## Acceptance for "industrial-grade" (definition of done)
1. Every stimulus renders a per-instruction verdict against a spec-complete golden model (0 UNVERIFIABLE), OR is classified with a formal/RTL-cited reason.
2. DUT native assertions + SVA layer active in the error gate.
3. RAL-based register access; single-source-of-truth scoreboard.
4. Traceable coverage plan; per-config sign-off across the config matrix.
5. CI-driven parallel/graded regression with reproducible, auto-generated sign-off + traceability.

## 🎯 VERIFICATION-MATURITY ASSESSMENT & FUTURE WORK (added 2026-08-06)

Honest self-assessment against the industrial sign-off yardstick above, written to keep the
project's claims defensible. **The distinguishing weakness is NOT the checkers — it is how many
scenarios the checkers have been shown.** Blunt summary: *a good microscope pointed at ~42 slides.*

### What is defensible TODAY
> "We built a per-instruction lockstep verification environment with **proven-non-vacuous**
> checkers, achieved 100% functional and 91% total code coverage on the primary configuration,
> and found and documented real RTL defects — including an **ISA spec deviation** (OBS-012 JALR)
> and an **IEEE-754 accuracy bug** (OBS-014 `fsqrt.s`). Stimulus breadth, reference-model
> independence, and the error/exception axis are identified as remaining work."

Every number in that sentence is reproducible on demand. **Do NOT upgrade it to "the design is
verified" or "we stressed the design"** — neither is currently supportable (see FW-1, FW-7).

**Genuine strengths (keep these visible — they are the project's real credibility):**
- **Non-vacuity discipline.** Two checking layers (end-state byte-exact + per-instruction
  lockstep) and BOTH proven able to fail (`negative_result_test`, `negative_dropped_store_test`).
  A checker never observed to fail is not a checker; most benches skip this.
- **Track record, not just claims.** Real RTL defects found: OBS-011/012/013/014/017, plus
  infrastructure defects OBS-016/019/020. A bench that finds real bugs is doing real work.
- **Config fidelity by construction** (`VX_gpu_pkg` exports elaborated geometry; elaboration
  asserts proven non-vacuous) rather than by convention.

### Maturity by axis
| Axis | Status |
|---|---|
| Checker strength / non-vacuity | **Strong** — above typical |
| Reference-model quality | Good but **NOT independent** (hard ceiling — see FW-2) |
| Bug-discovery track record | **Strong** |
| Stimulus volume & randomization | **Weak** — reproducible now (seed default 1), but still 1 seed per profile; 2 entries vacuous duplicates (FW-1, FW-1b) |
| Config coverage | **Weak** — 2 points, but now cheap (FW-3) |
| Error/exception handling | **Absent** (FW-4) |
| X-prop / reset randomization / GLS | **Absent** (FW-5) |
| Coverage-model provenance | **Moderate** — self-authored, not spec-traced (FW-6) |
| Stress / soak | **Weak** — directed single-shots (FW-7) |

### FUTURE WORK — ordered by claim-strength gained per unit effort

- **FW-1 — Seed control. ✅ REPRODUCIBILITY HALF IS DONE (verified 2026-08-12).** The text below
  was written before the fix and is **STALE — do not re-derive from it**. `prepare.sh:303-331`
  now implements: `RV_SEED` (**default 1**, so the committed suite is a stable regression gate),
  `RV_START_SEED` + `RV_ITERATIONS` for sweeps, and **seed-keyed output directories**
  (`out_vortex_<test>_s<seed>`) so reuse is deterministic rather than "newest `.S` on disk".
  **Measured proof:** in the 2CL suite, repeated runs of the same profile produced
  BYTE-IDENTICAL programs (`riscv_no_fence_test`, `riscv_full_interrupt_test`,
  `riscv_pmp_test` each ran twice, identical md5). Results are now reproducible.
  ⚠ The OLD claim — "`grep -i seed` returns NOTHING", "each `RISCV_DV_REGEN=1` generates a
  different program", "the top gap" — is FALSE as of today and must not be repeated in the
  paper or report.
  **STILL OPEN (the volume half):** one seed per profile is still **directed testing wearing a
  CRV costume**. *Do:* run the seed farm (`RV_START_SEED`/`RV_ITERATIONS` already exist).
  *Accept:* ≥100-seed sweep green or triaged. Supersedes/absorbs the older, thinner **D4**.

- **FW-1b — TWO riscv-dv SUITE ENTRIES ARE VACUOUS AND DUPLICATE EACH OTHER (found 2026-08-12,
  OPEN).** `riscv_pmp_test` and `riscv_non_compressed_instr_test` generate **byte-identical
  programs** (`.S` md5 `16be14c6…`, `.hex` md5 `4885c234…`). Root cause: both testlist entries
  delegate to the same generator (`gen_test: riscv_rand_instr_test`,
  `riscv-dv/target/rv32im/testlist.yaml:36,56`) and differ ONLY by `gen_opts` that are **inert
  under `--target=rv32im`**:
  - `+disable_compressed_instr=1` — **vacuous by construction**: rv32im has no C extension, so
    there were never compressed instructions to disable. **Measured: 0 compressed instrs.**
  - `+pmp_randomize=0 +pmp_num_regions=1 …` — **produced ZERO `pmpcfg`/`pmpaddr` writes**
    (measured). Vacuous twice over, since `prepare.sh` also sed-strips M-mode CSR writes for
    Vortex.
  **Verification impact — this inflates the pass count with coverage that was not earned:**
  the suite reports these as 2 independent results when they are 1 program. At 1CL, 2 of the
  "45/45" passes were the same program passing twice; at 2CL their identical failure is ONE
  divergence double-counted, not two. Neither test verifies the feature its name claims.
  ⚠ **NOT a silent-fallback bug** — both names ARE in the testlist and `prepare.sh:361` hard
  -errors if generation fails. The mechanism is *inert options*, which is quieter and worse:
  nothing fails, you simply get a duplicate wearing a distinct name.
  *Do:* either make the options effective (needs a target that actually has the feature — PMP
  is arguably out of scope for Vortex, which has no PMP) or **drop both entries and state the
  honest test count**. *Accept:* every riscv-dv entry in `run_suite.sh` produces a program whose
  md5 is distinct from every other entry's — assert it in the suite so this cannot regress.

- **FW-2 — Reference-model independence. ✅ PARTLY CLOSED 2026-08-07 (A6 done) — scalar axis
  closed, SIMT axis still fully open.** SimX is written by the Vortex team ⇒ shared assumptions
  ⇒ **shared blind spots**: the bug class where DUT and golden are wrong in the SAME way is
  structurally invisible, regardless of how many instructions match.
  **What A6 closed:** on `riscv_arithmetic_basic_test_0.elf`, Spike (independent) / SimX / DUT
  all retire **exactly 11,076** architectural writebacks and agree on every PC, destination
  register and value — **0 mismatches**, all 11,076 value-compared, non-vacuity proven by
  injection. So for the **scalar RV32IM subset** the shared-blind-spot ceiling is lifted.
  **What remains open — do not overstate A6:** Spike is a scalar ISS with no SIMT model, so
  warps, divergence, reconvergence, lanes 1..N-1 and every Vortex custom op still have **no
  independent reference at all**. That is the larger half of the design and it remains
  SimX-only. Extending Spike to SIMT was considered and **rejected**: it would produce a second
  Vortex-specific model and recreate the very dependence this item exists to remove.
  Closing the SIMT half needs a genuinely independent SIMT model, which does not exist today.
  See [`docs/A6_SPIKE_INDEPENDENCE_AUDIT.md`](A6_SPIKE_INDEPENDENCE_AUDIT.md) and **OBS-022**.

- **FW-3 — Config-matrix breadth.** Two points sampled (1CL/1C/4W/4T, 2CL/2C/4W/4T) of
  clusters × cores × warps × threads × L1/L2/L3 × XLEN × extensions; coverage cannot be blended
  across configs, so each needs independent closure. **Now compute time, not engineering** —
  the terminal-control work (2026-08-06) already made every knob settable.

- **FW-4 — Error/exception axis (currently ABSENT).** AXI `bresp`/`rresp` were waived as
  *"TB always OKAY, no error-inject test"* — so there is **zero evidence** about behaviour when
  something goes wrong. Add a plusarg-gated slave error-injection mode (infrastructure already
  exists from the throttle/flood modes in `axi_driver.svh`), un-waive those coverpoints, and
  close the open **T-exc** checklist item.

- **FW-5 — X-propagation, randomized reset, gate-level.** Reset is a single deterministic
  sequence. X-prop is likely to find real bugs here — INV-2 already established that the base
  DCRs have **no reset**.

- **FW-6 — Spec-traced coverage model. ✅ MATRIX DONE (2026-08-07), gaps now named:
  `docs/COVERAGE_TRACEABILITY_MATRIX.md`.** Traces 17 design features → 18 covergroup types, and
  — the actual payoff — names the features **no covergroup observes at all**:
  - **G1 — ✅ CLOSED 2026-08-07** (`tb/vx_cache_probe.sv`, commit `f017814`): `cache_event_cg`
    bound into `VX_cache_bank` gives hit/miss, fill, writeback, flush, MSHR replay and MSHR
    back-pressure **per cache level**, validated @2CL L2+L3 with 8 instances (L1 I$/D$ x2
    clusters, L2 x2 clusters, L3 x2 banks). Config-aware by construction: no bank exists when a
    level is PASSTHRU, so the default build gains no bins and needs no waiver. This is now the
    proper instrument for the L2/L3 hit-path question. ORIGINAL GAP TEXT:
    **NO cache-event coverage at any level.** Zero coverpoints matching
    `hit|miss|evict|writeback|mshr|flush` exist; the only cache-adjacent points (`cp_id_route`,
    `cross_type_route`) sample **routing tag bits**, not cache events. So the cache hierarchy —
    a prime location for real bugs — is covered only by code coverage plus end-state/lockstep
    equivalence, which a buggy cache can still satisfy. This is also **why the L2/L3 hit-path
    question can only be answered from CODE coverage today.**
  - **G2** exceptions/errors: only `cp_ebreak` (a status bit); no illegal-instruction,
    misaligned or bus-error coverage (couples with FW-4).
  - **G3** double-precision FP: `EXT_D_ENABLE` **is** in `flists/vortex_rtl.flist` (hardware is
    built) but kernels compile `-march=rv32imaf` and riscv-dv targets `rv32im` — **built and
    never stimulated by any path**, so it dilutes every coverage number. Either stimulate it or
    drop the extension from the build.
  - **G4** reset/init sequencing (with FW-5) · **G5** cross-cluster arbitration (with FW-7).
  **NOT a gap:** atomics — `EXT_A_ENABLE` is absent from the RTL flist, so the A extension is out
  of scope by configuration, not untested.
  **Claim to use:** *"100% of a coverage model spanning 17 design features; the model does not
  observe cache events, exception behaviour or double-precision FP — named gaps, not passing
  results."* Feeds acceptance criterion #4.

- **FW-7 — Real stress / soak.** The directed stress kernels (`mem_stress`, `wide_stress`,
  `cache_stress`, `axi_stress`, throttle/flood, `cache_tier`) are each **one short run**. They
  demonstrate a path WORKS; they do not stress it. Industrial stress = sustained randomized
  pressure, long soak, arbitration fairness/starvation, saturated outstanding transactions,
  multi-core contention. **Until this exists, do not use the word "stressed" in any claim.**

## Non-negotiables carried from CLAUDE.md
Black-box honesty (no fabricated verdicts); per-config coverage never blended; negative tests stay RED after any scoreboard change; announce/confirm expensive sim runs; no Claude attribution on commits.

---

## 🔮 DEFERRED ENHANCEMENTS (backlog — revisit AFTER current priorities)
Real, scoped enhancements intentionally parked. Each has a WHY (what it unlocks), a
COST, and a TRIGGER (when it becomes worth doing). Do NOT start these until the
current-milestone priorities (RESUME block) are done.

### ENH-1 — True single-pass step-follower lockstep (with interrupt-delivery alignment)
- **What:** Replace the current **two-pass trace-replay** RVVI load-bus (A1(e)) with a
  **single-pass step-driven follower**: SimX is stepped ONE instruction at a time as a
  follower of the DUT's retire stream, instead of run-to-completion + replay. On each DUT
  retirement, SimX executes that instruction and, for inputs it cannot independently
  predict, consumes the DUT-observed value **in real time**: (a) shared/racy LOAD data (as
  today), AND crucially (b) **interrupt delivery** — SimX takes the interrupt at the SAME
  retired instruction boundary the DUT did (an interrupt-inject hook driven by the DUT
  trace), plus (c) volatile/CSR reads.
- **WHY (what it unlocks):** closes the one class the two-pass trace-replay provably CANNOT
  resolve — **interrupt-timing divergence**. `full_interrupt`@2CL collapses only 116→7 and
  the residual 7 is proven **keying-independent** (identical under ordinal AND
  (cid,wid,PC,occurrence) keys → not a feed/alignment artifact; it is genuine interrupt
  timing: the interrupt-affected PC executes a different count in the timing-accurate DUT
  vs functional SimX). Feeding LOAD data can't fix WHEN the interrupt fires; only aligning
  interrupt **delivery** can. Would take `full_interrupt` (and any async-input timing test)
  from end-state-VERIFIED / instruction-UNVERIFIABLE → fully instruction-granularity
  VERIFIED. It is also the RVVI-standard architecture (ImperasDV-style), so it generalises.
- **COST:** major SimX rework — invert `simx_run()` from a bounded run-to-completion loop
  into a stepper the SV drives per DUT-retirement; add an interrupt-delivery injection point
  in the SimX interrupt path; wire the DUT retire stream to drive the stepper (naturally
  built on the **A1(c) `rvvi_if` monitor** — that interface is the enabler/prerequisite).
- **TRIGGER:** when instruction-granularity verification of interrupt / async-timing tests
  is required for sign-off. Until then, `full_interrupt`@multi-cluster is dispositioned
  **end-state VERIFIED** (real `dut_mem` vs post-feed SimX passes) which is sufficient for
  black-box equivalence. See RTL_OBSERVATIONS **OBS-010** for the full evidence.

### ENH-2 — Bounded fixed-point iterated feed (cheaper interim for ENH-1's goal)
- **What:** Iterate the two-pass load-bus — feed each pass's residual divergent loads, re-run
  SimX (in-process, cheap), repeat until residual stabilises or a small iteration bound.
- **WHY:** MIGHT drive `full_interrupt` residual → 0 without the full step-follower rework.
- **COST/RISK:** small SV change in `lockstep_scoreboard.check_phase` + 1 sim run to test.
  **May NOT converge** for interrupts (feeding LOAD data doesn't align interrupt timing, so
  each iteration can expose new divergences); bound the iterations and report honestly.
- **TRIGGER:** a quick experiment before committing to ENH-1; if it converges, it's a much
  cheaper path. If it doesn't, it confirms ENH-1 is the only real fix.

### ENH-3 — full_interrupt residual root-cause pinpoint (diagnostic)
- **What:** Add a per-(cid,wid,PC) execution-count dump to prove which sub-mechanism drives
  the residual 7: same-PC occurrence-count drift vs feed-exposed new divergence.
- **WHY:** removes the "by elimination" hedge in OBS-010; makes the interrupt-timing claim
  a measured fact. Low value unless ENH-1/2 are pursued.
- **COST:** small SimX/SV instrumentation + 1 replay.

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
4. Add `cfg.enable_lockstep` + plusarg; wire golden agent + scoreboard in `vortex_env.svh`; sequence the drain after the end-state scoreboard's `simx_run`.
5. Run `vecadd_lite`; prove lane-exact match, injected-corruption catch, and `uuid` 1:1 identity (A0 accept).
