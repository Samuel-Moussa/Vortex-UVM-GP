# Vortex UVM Verification — Paper Base (Evaluation + Evidence)

**Purpose:** the consolidated, evidence-backed base for a publication (and the mentor
walkthrough). Part I = the project as it stands on `main` (black-box environment,
pre-lockstep). Part II = the industrial-grade upgrade on branch
`industrial_transformations` (per-instruction RVVI lockstep).
**Every claim carries its evidence**: a commit SHA, a repo document, an RTL `file:line`,
or a banked report. Nothing here is asserted without a citable artifact.

**Repo:** `Samuel-Moussa/Vortex-UVM-GP` · RTL pin `7a52ee5` · QuestaSim 2021.2_1, Ubuntu 22.04
**main tip (Part I):** `5ef2139` · **branch tip (Part II):** `d9df0eb` · **Date:** 2026-07-16

---

# ⚠️ SUPERSEDING RESULT BLOCK — 2026-08-17 (READ BEFORE QUOTING ANY NUMBER)

**The 2026-07-16 audit below remains valid FOR THE BANKS THAT EXISTED THEN.** It is a dated
snapshot and is deliberately not rewritten — rewriting an audited document in place would
destroy the guarantee that made it worth auditing. Every headline number it states has since
been superseded by a later bank. Quote THIS block.

| Metric | 1CL/1C/4W/4T | 2CL/2C/4W/4T |
|---|---|---|
| Covergroup bins (raw) | **370/377 = 98.14%** | **989/1032 = 95.83%** |
| Covergroup (weighted) | 99.79% | 99.52% |
| Statement | 98.10% | 98.32% |
| Branch | 95.09% | 95.71% |
| Condition | 90.41% | 88.77% |
| Toggle | 82.83% | 80.47% |
| Assertion | 96.85% | 98.87% |
| Directive | 100.00% | 100.00% |
| **Total** | **94.72%** | **94.55%** |
| Runs staged / failed | **50 / 0** | **50 / 0** |
| Coverage instances | 2,256 | 8,275 |

Banked 2026-08-16 at `cov/bank_{1CL_1C_4W_4T,2CL_2C_4W_4T}/`, logs at
`results/run_suite_logs_{1CL,2CL}_storm_20260816/`. Both verified by RE-READING the banked
copy, not the live file. Total is still Questa's unweighted 7-category mean.

**Corrections this block makes to the audit below — all of them material:**

1. **"100% functional" was never raw-bin coverage.** It was the *weighted* covergroup metric,
   which excludes three weight-0 red herrings by design. Raw bins were 374/377 then and are
   370/377 now (the denominator moved when the coverage model was rewritten). **State both, or
   state "weighted" explicitly** — an unqualified "100% functional coverage" is the single most
   attackable claim in the old text.
2. **"43/43 tests" is wrong twice.** It is a count of *runs*, not distinct programs, and two
   riscv-dv entries (`riscv_pmp_test`, `riscv_non_compressed_instr_test`) are **byte-identical
   programs** (FW-1b) — one program counted twice. The current suite is **50 runs**, of which
   two re-run one program under a different bus mode and four are one test entry under four
   program kinds (OBS-039). **Say "50 simulation runs", never "50 programs".**
3. **"40/42 at 2CL, 2 = golden-model limits" is FALSIFIED.** All four historical 2CL failures
   now pass with real byte-exact compares; they were ONE methodology defect (OBS-027), not four
   divergences. The current result is **50/50, 0 FAILED, at BOTH configurations.**
4. **The toggle root-cause named the wrong cache.** The old text blames the write-through
   dcache. Measured: the **icache** is 51,340 bins / 22,730 missing / 55.7% versus dcache
   86,604 / 9,524 / 89.0% — **26.4% of the entire toggle gap from one subtree**, because
   `VX_socket.sv:106` instantiates it with `.WRITE_ENABLE(0)`. Positive control: `rsp_data.data`
   toggles 45–46× on all 512 bits, so the read path is alive and only the write direction is
   dead. The "~78% is the structural ceiling" conclusion was also too pessimistic — toggle is
   now 82.83% / 80.47% after config-aware waivers plus real stimulus.
5. **A merge-time integrity gate now exists** and did not when the audit was written.
   `merge_coverage.sh` applies exclusions in two stages split by justification class and
   **fails the merge** if a structural exclusion changes any COVERED bin count. It caught two
   real defects on first execution, one of which had been silently discarding a covered
   condition term for weeks. Any coverage number produced before that gate existed was
   unverified in this respect.

**New evidence available to the paper that post-dates the audit:**
- **196,868 words byte-exact** in a single end-state compare (`cache_tier`, 2CL with L2+L3
  enabled) — 6× the previous largest, 0 errors.
- **The shared cache hierarchy exercised for the first time**: L2 (both clusters) and L3 (both
  banks) hit paths covered, 13,464–15,323 hits per instance. Every prior bank had both levels
  as pure passthrough.
- **A published negative result**: enlarging a kernel's working set 16× *reduced* contention
  coverage (13→11 terms, and +4→+0 in a second independent experiment). Contention comes from
  issue density, not miss volume.
- **OBS-032 resolved by measurement, hypothesis falsified**: the testbench's 4×-deeper cache
  fill queue was suspected of suppressing back-pressure coverage; rebuilding at the RTL default
  produced **bit-identical branch, condition and statement counts**. The suspected coverpoint is
  sized by a different parameter that already matched the RTL default.
- **A third configuration (L2+L3 enabled) is being banked**; do not quote it until it lands.

---

# ✅ VERIFICATION STATEMENT (audit of this document, 2026-07-16)

Every claim in this document was re-verified against primary artifacts on 2026-07-16
(method + raw outputs in **Appendix P — Proofs**). Specifically:

- **All 60 cited commit SHAs exist** in the repo (`git cat-file -e` each) and key subjects
  match their claimed content (spot-checked 13, all correct).
- **All RTL/SimX `file:line` citations re-read from the working tree** at RTL pin
  `7a52ee5` — every one shows exactly the claimed construct (Appendix P.2).
- **Both coverage tables re-derived from the banked UCDBs with the tool itself**
  (`vcover report -summary` on `cov/bank_*/merged.ucdb`): every one of the 7 category
  percentages and both totals (**91.00% / 85.16%**) reproduce **exactly** (Appendix P.1).
  The total is Questa's unweighted 7-category mean — verified arithmetically:
  (100+97.05+91.16+76.35+78.65+93.79+100)/7 = 91.00.
- **Lockstep flagship numbers confirmed** against the committed investigation doc
  (`docs/investigations/SimX_2CL_no_fence_divergence.md`): first-divergence
  `mulhu @0x800004f4` seq 278 with both register values; 5432/5432 pass-2 residual 0;
  116→7 residual + keying-independence (Appendix P.3).
- **Two stale facts found and corrected in this revision:**
  1. *Abort-site count:* "69 `std::abort` (46 decode + 23 execute)" was the count at plan
     time (2026-07-14). Current tree measures **56 raw `std::abort` occurrences (35
     decode.cpp + 21 execute.cpp), with 14 decode sites now routed through the
     self-documenting `DECODE_ABORT` macro** (`914f778`). Corrected below.
  2. *Abort-count wording elsewhere:* Part I §9 and Part II §8 updated to the measured
     current count. (`VX_uuid_gen.sv` path double-checked: in-tree docs already cite the
     correct `core/` location; line-40 content verified: `g_wid = (CORE_ID << NW_BITS) +
     wid` concatenated above the per-warp counter.)
- **Evidence-strength note:** the config-matrix lockstep tallies (1035/1801/3333/855/1423)
  are recorded in the plan doc (`e21a130`) and RTL_OBSERVATIONS; their raw sim logs were
  session scratch and are not retained. All coverage, investigation, and commit evidence
  is retained in-tree.

---

# 🗺 THE JOURNEY — project timeline (from full commit archaeology, 328 commits)

> Source: `docs/COMMIT_HISTORY.md` (all branches, 2025-10 → 2026-07). This is the paper's
> "project narrative" backbone; each phase cites representative commits.

| Phase | Period | What happened (representative commits) |
|---|---|---|
| **0. Bootstrap** | 2025-10 | Repo created 2025-10-23 (`dc4124a`) — **as an extension of the OpenHW core-v-verif CV32E40P UVM environment toward the Vortex GPGPU** (`d324a00`: "Extended the CV32E40P UVM verification environment to support the Vortex GPGPU"). This origin matters for the paper: the env descends from the same methodology family (core-v-verif) that Part II's RVVI lockstep later rejoins. |
| **1. Planning & research** | 2025-11 | Verification plan (`0dc8b0f`), interface mappings (`9cc5c02`), architecture research notes (`953d3c4`), deliverables definition. |
| **2. SimX DPI integration** | 2025-12 → 2026-01 | Golden-model bring-up: the "MALL error" fix (`e3a0bbd` — Issue 15: uninitialized x3 read as ASCII 'MALL'), x3 exit-code protocol (`3ec8458`), post-mortem exit handling (`7877dd2`), DPI Makefile (`2465cf1`). |
| **3. Interfaces & memory** | 2026-02 | Interface/memory-config refactor (`23d246e`), first comprehensive smoke test (`4848695`). |
| **4. First light** | 2026-03 | **Smoke test SUCCESS 2026-03-16** (`03643d1`); run-script hardening (startup-addr parsing, DPI linking, hex overflow — `c6fa229`, the vacuous-PASS fix); scoreboard/coverage-collector bring-up (`5d30f4e`, `a4626e5`); AXI4-compliance interface refactor (`4518334`); mem_model R-beat checking (`f2f8736`). |
| **5. Architecture restructure** | 2026-04 → 2026-05 | EBREAK infinite-loop fix + monitor optimization (`9b69d68`); GLIBCXX ABI fix (`ee11d66`); **the major restructure** (`cc83410`, 2026-05-05): tb_top → pure structural wrapper, memory responses fully delegated to UVM agent drivers, clean package hierarchy (= §5.5 of the 43-issue report); XLEN→32 (`0f92090`); SimX arch configurable from scripts (`4dfe44e`). |
| **6. Trust the bench (Gate-0)** | 2026-06 | Derived widths (`5f19a67`), decoded-EBREAK completion (`a46a109`), real instr count (`b14efc5`), honest error gate (`df6206e`), riscv-dv end-to-end (`5f6ddff`), passive commit probe, INV-1/INV-2 root-causes, negative fault-injection validation. History rewritten 2026-06-28 to strip attribution trailers. |
| **7. Coverage closure** | 2026-06 → 2026-07-10 | *(historical row — these figures are SUPERSEDED, see the top block.)* Weighted covergroup metric 100% (17 covergroups, `d65441d`/`ff37765`); config-aware exclusion generator (`ae809f4`); two per-config banks; total 79.20→**91.00%** (`199401c`…`6e6a81b`); bidirectional scoreboard (`fe10b83`); 2CL divergence investigation. |
| **8. Industrial upgrade** | 2026-07-14 → 2026-08-06 | RVVI lockstep A0 (`7aac709`) → divergence/multi-core (`eb08c04`) → first-divergence pinpoint (`b029fe7`/`28c84ab`) → SimX fetch-bug fix (`6dfe665`) → RVVI load-bus, residual 0 (`2dd48ea`) → interrupt-timing boundary characterized (`2614ee0`). |
| **9. Methodology repairs** | 2026-08-07 → 2026-08-15 | B2 scoreboard collapsed to a single source of truth (`f279357`); Spike independent base-ISA audit, 11,076/11,076 agree (`8e1a3b2`); per-config kernel rebuild — kernels had been compiled for one topology regardless of the requested config (OBS-028, `3ffa321`); OBS-027 methodology defect resolved ⇒ the four "expected" 2CL failures all pass with real compares; device-sized grids in 7 kernels. |
| **10. Coverage maximisation** | 2026-08-16 → 2026-08-17 | Toggle root-caused to the read-only **icache**, not the dcache (OBS-033/034); three targeted kernels (`isa_probe`, `unit_storm`, `storm_big`); **blocking hits-invariant merge gate** which found two waivers deleting real coverage; L2/L3 plumbed end-to-end and their hit paths covered for the first time via `cache_tier` (196,868 words byte-exact); OBS-032 resolved by measurement with the hypothesis falsified; OBS-035…039 filed. **Banks: 1CL 94.72%, 2CL 94.55%, 50/50 runs, 0 failures at both.** |

---

# PART I — The black-box environment (main branch)

## 1. What it is (abstract material)

- A complete **UVM verification environment for the Vortex GPGPU** (Georgia Tech
  open-source RISC-V GPU: RV32IMAF + 6 custom SIMT instructions —
  `wspawn/tmc/split/join/bar/tex`, tex disabled in this build).
- Methodology: **black-box end-state equivalence** — the DUT executes real compiled GPU
  kernels and constrained-random RISC-V programs; the correctness verdict is a byte-exact
  final-memory comparison against **SimX** (Vortex's own functional simulator) integrated
  as a golden reference via **DPI-C co-simulation**.
- Headline results (**UPDATED 2026-08-16** — the old line read "100% functional / 91.00% /
  43/43", which is superseded and, on the first two counts, misleading; see the superseding
  block at the top): **98.14% of covergroup bins (99.79% weighted), 94.72% total coverage on
  the primary configuration, 50/50 simulation runs passing, 0 failures**; a second full bank at a scaled
  multi-cluster configuration (85.16% total).
  - *Evidence:* `docs/Coverage_Report_2026-07-10.md` (banked report, both configs);
    coverage banks `vortex_uvm_env/cov/bank_1CL_1C_4W_4T/` and `bank_2CL_2C_4W_4T/`.

## 2. Novelty candidates (the paper's argument)

- **GPGPU verification is not CPU verification.** The DUT is a *program-executing bus
  master*, not a transaction slave: stimulus is programs, not sequence items. The env
  inverts the usual UVM roles — **DUT = AXI master, testbench agents = reactive slaves**
  backed by a memory model.
  - *Evidence:* agent architecture in `vortex_uvm_env/uvm_env/` (axi/mem agents are
    active responders); `docs/INTERFACE_MAPPING.md`.
- **"Trust the bench" (Gate-0) methodology.** Before any coverage number is reported, the
  bench is proven non-vacuous with **permanent negative fault-injection tests**:
  (a) wrong-value injection (`+INJECT_FAULT` flips one bit in a DUT store — caught at
  `0x800075d8`), (b) dropped-store injection (caught by the reverse scoreboard pass).
  **Both must stay RED on injection** and run as regression guards after every scoreboard
  change.
  - *Evidence:* negative_result_test validation 2026-06-29 (fault injected on
    `vecadd_lite`, checker detected → "Verdicts are not vacuous"); SB-DIR bidirectional
    scoreboard + `negative_dropped_store_test` commit `fe10b83`; Gate-0 closure doc
    commit `fe6277c`.
- **Honest coverage closure.** Every exclusion is **structural, RTL-cited (`file:line`),
  and machine-generated per-configuration** by a config-aware exclusion generator;
  unreachable-vs-unhit distinguished with evidence; reachable-but-not-hit bins left
  honestly uncovered rather than waived. Architecture-literature corroboration where
  applicable (CARRV'19 §6.3 warp-scheduler latency for the IPC ceiling; MICRO'21 §4.1.4
  weak coherence for the multi-cluster ordering class).
  - *Evidence:* generator `vortex_uvm_env/scripts/gen_coverage_exclude.sh` (commits
    `ae809f4`, `9fc45ae`, `855f61e`); merge script verifies **0 "had no effect"** waivers;
    example citations: `b_valid_stable` unreachable because the adapter hardwires
    `m_axi_bready = 1'b1` (`VX_axi_adapter.sv:313`); MSHR slot = priority-encoder
    lowest-free (`VX_cache_mshr.sv:125-132`); wspawn single-warp bootstrap
    (`VX_schedule.sv:126`); `is_global` barrier config-keyed to ≥2 cores
    (`VX_schedule.sv:168`).
- **UNVERIFIABLE as a first-class verdict.** Runs where the golden model cannot render a
  verdict (SimX aborts; multi-cluster memory-ordering divergence) are *classified with
  root-cause evidence*, never force-compared and never silently dropped.
  - *Evidence:* `docs/investigations/SimX_2CL_no_fence_divergence.md`; crash-guard →
    exit `-3` UNVERIFIABLE classification in the DPI bridge (commit `55661d7`).
- **Full configurability with elaboration-time self-checks.** One environment runs any
  `clusters × cores × warps × threads` topology from plusargs; UVM-vs-RTL parameter
  mismatches fail loud at elaboration.
  - *Evidence:* I2 topology asserts (commit `b55f392`, `[I2-ASSERT]` fatal on mismatch);
    derived tag width + elaboration assert (C1, commit `5f19a67`); per-config SimX
    rebuild (commit `1ce1e9f`); validated configs incl. 2C/4W/4T, 2CL/2C/4W/4T, 4C/2W,
    8C/8W/2T (session record 2026-06-29).

## 3. Environment architecture

- **5 UVM agents**: host + DCR + AXI (active), memory (active responder or passive),
  status (passive); virtual sequencer orchestration.
- **Golden reference over DPI-C**: `simx_init/load/dcr_write/run` drive SimX per run;
  RTL **and** SimX rebuilt per configuration so DUT and reference always match topology
  (commit `1ce1e9f`).
- **Passive observability layer**: a `bind`-ed commit probe on the retire arbiter
  (per-lane `valid && ready`, full commit record uuid/wid/tmask/PC/rd/data), auto-scaling
  across all clusters × sockets × cores × issue lanes; observability only, never a checker.
  - *Evidence:* `vortex_uvm_env/tb/vx_commit_probe.sv` (P1-bind, 2026-06-28).
- **Tests ⊥ Programs separation**: the UVM TEST class defines *how* to drive (launch,
  config, injection modes); the PROGRAM (compiled ELF kernel or riscv-dv assembly)
  defines *what* executes; composed at the Makefile level.
- **Bidirectional end-state scoreboard**: forward pass (every DUT-written word vs SimX)
  **and** reverse pass (SimX-written words the DUT never wrote → catches dropped stores);
  per-byte validity masking for sub-word stores (commit `4b7c55c`); FP-tolerant compare
  where IEEE rounding paths legitimately differ; `.got`/read-only-section handling
  (commit `bc96979`).

## 4. Infrastructure-correctness work (Gate-0 — all closed)

The bench itself was audited and repaired before any metric was trusted:

- **C1 — derived widths** (commit `5f19a67`): memory tag/ID width taken from the RTL
  package (was hardcoded 50 with a false `// 8` comment); elaboration assert
  UVM-param == DUT-param.
- **C3 — real completion event** (commit `a46a109`): completion from **decoded EBREAK
  (`0x00100073`) at fetch** across all cores, not an idle-threshold heuristic (heuristic
  demoted to warning-only fallback).
- **C2 — real retired-instruction count** (commit `b14efc5`, multi-core `11f71359`-era
  fix): tapped from the commit arbiter across all clusters/cores/lanes; replaced a
  fabricated `mem_ops % 3` estimate → real IPC (measured: 12798 instrs, IPC 0.128 on
  vecadd).
- **T4 — honest error gate** (commit `df6206e`): the run verdict counts true
  `UVM_ERROR`s — a discovered `-2` subtraction that masked errors was removed; validated
  by the fault-injection test.
- **INV-2 — startup protocol race root-caused & fixed** (commits `47b29e5`, `e8ca365`,
  `2e51118`): the core self-starts from reset (`VX_schedule.sv:230`) while DCR base
  registers have no reset value (`VX_dcr_data.sv:27`); reset now held until a
  DCR-bootstrap-done handshake. Writeup: `docs/fixes/INV2_dcr_write_during_busy.md`.
- **INV-1 — "kernels never complete" root-caused** as printf MMIO volume, not a hang
  (each char = fenced MMIO write; program at ~1–2% when the timeout cut it); printf-light
  kernel variants complete in ~10k cycles. Writeup:
  `docs/fixes/INV1_kernel_completion_hang.md`.

## 5. Stimulus

- **~30 directed kernels** (real Vortex C kernels compiled with the Vortex toolchain):
  vecadd, FPU (all 13 `INST_FPU_*` op classes — commit `d65441d`), TCU/WMMA tensor ops
  (commit `0984bdf` + multi-warp `ff37765`), divergence towers (nested IPDOM
  split/join), barriers under partial masks (`bar_masks`, commit `41a7c38`), wspawn/tmc
  sweeps, MSHR/memory stress (`mem_stress`, commit `d10c05a`), 232 KB-text kernel
  (`text_big`), 256 KB high-entropy store stress (`wide_stress`, commit `dcadb3d`),
  div/rem corners (`div_edge`, commit `c525dfd`), CSR-writes-under-SIMT-mask
  (`sfu_masks`, commit `df044e5`), VOTE/SHFL (`vote_shfl`, commit `199401c`).
- **Constrained-random**: a working **riscv-dv pipeline** (rv32im) — generation,
  GPU-target post-processing (M-mode CSR stripping, `ecall→ebreak`), execution,
  end-state verification; ~12 random-program seeds in the suite.
  - *Evidence:* commit `5f6ddff`; per-issue root-cause docs `docs/fixes/fix_06–fix_12`;
    guide `docs/RISCV_DV_GUIDE.md`.
- **AXI protocol stress modes** (plusarg-gated, **default-off proven byte-identical**):
  slave-side **throttle** (`+AXI_THROTTLE`, ready wait-states) and **read flood**
  (`+AXI_FLOOD`, back-to-back R beats) to exercise backpressure/stability assertions
  (commits `dcadb3d`, `c525dfd`, `6e6a81b`; AXI assertion coverage 84.78→93%).
- **Host/DCR coverage sequences**: real launch + SimX-safe DCR sweeps (commits
  `058ee9c`, `1b14388`).

## 6. Checking & assertions

- End-state equivalence up to **32,836 words compared byte-exact in one test**
  (`wide_stress`); ~29 suite tests render real DUT-vs-SimX data verdicts; **0 failures**.
- **AXI4 SVA layer**: ~15–18 protocol properties + 11 handshake-stability assertions
  inline on the AXI interface (burst legality, outstanding-count consistency, stability
  under backpressure) — all pass; every plan-vs-implemented drop documented with RTL
  evidence. *Evidence:* `docs/AXI_SVA_report.md`.
- Assertion coverage 93.79% (1CL) with residual reachability analysis documented
  (e.g. `b_valid_stable` structurally unreachable — `VX_axi_adapter.sv:313`;
  `r_valid/r_data_stable` reachable-but-not-hit, left honestly uncovered).

## 7. Coverage results (per-config banks, never blended)

> ⚠️ **SUPERSEDED — this table is the 2026-07-10 bank.** Current banked numbers are in the
> superseding block at the top of this document (1CL **94.72%**, 2CL **94.55%**, 50/50 runs
> passing at both). Kept for provenance: it is the bank the 2026-07-16 audit verified.

| Metric | 1CL/1C/4W/4T (primary) | 2CL/2C/4W/4T (scale) |
|---|---|---|
| Functional (covergroups) | **100%** (17 groups) | 92.48% |
| Statement | 97.05% | 96.19% |
| Branch | 91.16% | 89.68% |
| Condition | 76.35% | 69.57% |
| Toggle | 78.65% | 74.25% |
| Assertion | 93.79% | 73.96% |
| Directive | 100% | 100% |
| **Total** | **91.00%** | **85.16%** |
| Tests | 43/43 | 40/42 (2 = golden-model seed limits, root-caused) |

- *Evidence:* `docs/Coverage_Report_2026-07-10.md`; banks under `vortex_uvm_env/cov/`.
- **Functional model**: 17 covergroups — instruction classes per execution unit
  (ALU/FPU/LSU/SFU/TCU, op-decoded), SIMT divergence × IPDOM depth, warp/thread-mask
  crosses, barrier/wspawn/tmc, stall taxonomy × IPC, AXI fields, DCR/host, system state —
  each with a written "why sufficient" rationale: `docs/Coverage_Model_Reference.md`
  (commit `fc34b3f`).
- **Cross-config UCDB merging shown invalid** (instance inflation 2247→8260 + width
  toggles ⇒ by-instance % drops) → per-config reporting rule (session record 2026-06-29).
- **Toggle ceiling root-caused, not gamed**: write-through cache ⇒ 512-bit line
  write-data fields never driven (`DCACHE_WRITEBACK=0`; `VX_cache_mshr.sv:242-247`
  class); PC/address high bits constant for realistic programs. A max-entropy adversarial
  kernel (`toggle_stress`, multi-core complementary cache-line patterns, PASS vs SimX)
  moved aggregate toggle **+0.02%** — the ceiling (~78%) is structural.
- **Metric insight (methodological)**: Questa "Total" is the **unweighted mean of the 7
  categories** regardless of bin count — the lowest category is the largest lever;
  verified arithmetically and used to direct effort (Directives 31.25%→100% moved the
  total more than 425k toggle bins).

## 8. Engineering record (real findings)

### 8.0 Bring-up phase (pre-Gate-0) — the 43-issue report

- The team's bring-up phase is documented in a standalone report: **"UVM Verification
  Environment for the Vortex GPGPU — Comprehensive Issues Report"** (Minia University,
  5 authors, supervised; `Vortex_UVM_Issues_Report_Final.docx`) — **43 distinct issues**
  with symptom / root-cause / fix across three domains: QuestaSim RTL simulation, the
  SimX DPI-C golden-model integration, and the UVM testbench architecture. It gives the
  paper a quantified "integration cost" narrative (C++ ABI `GLIBCXX` mismatch vs the
  simulator's bundled GCC, RAM page-size bug producing zero-reads, DCR block-base vs
  register-offset confusion, X-state floods from late program loading, DPI stepping API
  gaps, byte-order corruption, ...).
- **The origin story of the Gate-0 non-vacuity methodology** — the report documents
  *three independent vacuous-PASS incidents* that motivated the fault-injection guards:
  - **Issue 32:** the scoreboard mirrored every DUT write into SimX RAM before running
    it → SimX computed from DUT-contaminated memory → **comparisons always passed
    regardless of RTL correctness**.
  - **Issue 4:** a smoke test reported PASS having executed 1 instruction with 0
    comparisons.
  - **§5.1 Fix C:** a hex base-address overflow left the code region empty → **vacuous
    PASS from NOP fetches**.
  - Narrative arc for the paper: *burned by vacuous verdicts three times → verdicts must
    be proven non-vacuous → permanent negative fault-injection tests as regression
    guards* (§2, Gate-0).
- **A genuine RTL bug found during bring-up (Issue 8):** `STALL_TIMEOUT` is defined as
  `100000 * (1 ** (L2_ENABLED + L3_ENABLED))` — `1**N ≡ 1`, so the timeout never scales
  with cache-hierarchy depth. Verified in-tree at `VX_config.vh:246`; logged as OBS-011
  in `docs/RTL_OBSERVATIONS.md`.
- **Methodology artifacts distilled from the bug inventory:** 12 mandatory hex-program
  authoring rules for the golden model + a three-layer program-loading/memory reference
  (cache-line address shift, 512-bit line layout, DCR startup sequence) — citable as
  "we codified golden-model program-authoring rules from the failure inventory."
- **The report's own future-work list was since largely executed** (independent early
  corroboration of the roadmap): coverage closure (§7.8) → done (Part I §7); full-region
  kernel co-verification (§7.5) → done (`compare_all_written`, 32k words); barrier/warp
  tests (§7.7) → largely done (T-cache still open); runtime cluster config (§7.2) →
  solved via per-config rebuild (`1ce1e9f`); true incremental stepping (§7.1) → exactly
  the ENH-1 step-follower architecture (Part II §6); RAL (§7.4) → still open = Phase B1.
- **⚠ Stale-facts caveat:** the report predates Gate-0 and the coverage/lockstep work —
  cite it as history only. In particular its "ID_WIDTH corrected to 8" / "50 is a
  placeholder" (§5.4/Issue 34) is **superseded by C1**: the true derived
  `VX_MEM_TAG_WIDTH` *is* 50, now taken from the RTL package with an elaboration assert;
  and its "current state" (§7: vecadd only) is long superseded.

### 8.1 Golden-model and co-sim findings

- **Golden-model bugs found & fixed (7+)** during co-sim bring-up: SimX reset placement
  (commit `55661d7` — the core co-sim bug), startup-address clobber, per-config core
  object rebuild (`vector::_M_range_check` crash at non-default warp counts, commit
  `1ce1e9f`), CSR-range SIGABRT, RVC decode abort, missing `EXT_TCU_ENABLE` in the DPI
  build (commit `0984bdf`), hex load-address overflow (with C1).
  *Docs:* `docs/fixes/` (fix_01–18).
- **Multi-cluster divergence root-caused as a golden-model limit, not a DUT bug**:
  fenceless random programs at 2 clusters diverge deterministically per-cluster (SimX
  cluster-0 cores match the DUT exactly = `0x28af8c40`; cluster-1 diverges =
  `0x2fff8c40`), isolated to one propagating value; UB/race/crash/reg-init/mem-sharing/
  per-core-CSR all ruled out; mechanism = unsynchronized cross-core memory ordering
  resolved differently by functional interleaving vs the timing-accurate DUT.
  *Evidence:* `docs/investigations/SimX_2CL_no_fence_divergence.md`; corroborated
  MICRO'21 §4.1.4 (weak coherence).
- **Scoreboard verdict inventory (honesty table)**: ~29 tests real byte-exact compare;
  ~10 riscv-dv + 3 regression UNVERIFIABLE (SimX aborts — classified); 2 liveness-only
  (no data footprint). **0 failures.** (Extracted from run logs, session 11.)

## 9. Limitations (set up Part II)

- Checking is **end-state only**: a transient corruption that cancels, or a wrong-path
  store later overwritten, is invisible.
- **SimX is not independent of the DUT** (same team ⇒ shared assumptions can hide shared
  bugs); no independent-ISS audit yet.
- ~10 riscv-dv + 3 regression runs **UNVERIFIABLE** (SimX decoder/executor `std::abort()`
  on exotic encodings — measured 2026-07-16: **56 raw `std::abort` occurrences in-tree**,
  35 in decode.cpp + 21 in execute.cpp, with 14 decode sites routed through the
  self-documenting `DECODE_ABORT` macro; the plan-time count was 69).
- Toggle > 90% founding goal unmet (structural ceiling, documented, not gamed).
- Founding-plan status: met **except** toggle>90% and two planned test families
  (T-cache, T-exc). *Evidence:* `docs/VERIFICATION_PLAN.md` vs
  `docs/Coverage_Report_2026-07-10.md`.

---

# PART II — Industrial-grade upgrade: per-instruction RVVI lockstep (branch `industrial_transformations`)

## 1. Motivation (the bridge)

- Part I's limitation is architectural: end-state equivalence cannot **localize a failure
  in time** — it says *that* memory differs, never *which instruction* diverged; and
  every SimX abort left a run UNVERIFIABLE.
- Industrial RISC-V practice (OpenHW core-v-verif, ImperasDV) compares **every retired
  instruction** against a stepping golden model — the **RVVI** pattern. The upgrade
  brings that class of checking to a **SIMT GPGPU**, which no off-the-shelf RVVI flow
  supports.
- Enabling observation (from SimX source, not assumption): the functional `Emulator`
  already steps per-instruction, returns an RVVI-shaped `instr_trace_t`, holds full SIMT
  arch state, and is decoupled from the timing model (`core.cpp:223` consumes
  `emulator_.step()`) — ~80% of an RVVI golden. Spike cannot execute the 6 SIMT ops, so
  **SimX-functional = primary golden; Spike = planned base-ISA independence audit**.
  *Evidence:* plan decision record `docs/INDUSTRIAL_TRANSFORMATION_PLAN.md` (2026-07-14).

## 2. What was built (A0 — lockstep core, commit `7aac709`)

- **DUT side:** the passive commit probe captures every retirement beat
  `{uuid, wid, PC, rd, wb, tmask, per-lane data}`, `+LOCKSTEP`-gated so default runs are
  **proven byte-identical**.
- **Golden side:** SimX per-retirement records over the existing DPI bridge
  (`simx_retire_t` export, pre-existing commit `554080e`, extended with
  `fu_type`/`is_volatile` at zero ABI change).
- **Comparator (`lockstep_scoreboard.sv`):** aligns both streams and compares **per
  active SIMT lane**: PC, destination register, written value; 4-way taxonomy
  (matched / field-mismatch / data-mismatch / orphan) + drain-empty check both sides —
  dropped or extra retirements are caught.
- **Non-vacuity by injection (Part-I discipline reapplied):** `+LOCKSTEP_INJECT` flips
  one bit in one retirement → caught at the **exact uuid/PC/lane** (`DUT=5 vs SimX=4`).
- **A0 result:** vecadd_lite 1CL/1C/4W/4T → **1035/1035 architectural writebacks
  matched, 0 orphans, 0 field mismatches, 0 UVM_ERROR**; loads (187) and perf-CSRs (62)
  correctly scoped.

## 3. Five SIMT-specific design corrections (each forced by sim evidence — paper material)

A CPU-RVVI flow never meets these; they are the transferable lessons:

1. **DUT retire order ≠ program order.** The commit arbiter takes whichever execution
   unit is ready (observed uuid `0x59` retiring after `0x5a/0x5c`); SimX retires in
   program order → align by **uuid (per-warp issue counter), sorted**, never by
   position or cycle.
2. **The golden's uuid is not a cross-key** (SimX leaves it 0) → alignment key =
   per-`(core, warp)` program order; DUT wid embeds in high uuid bits.
3. **One instruction ≠ one retirement record.** SIMD beat splits AND load partial-mask
   writebacks (LSU commits lanes as memory responses arrive — one `lw` observed as two
   records, masks `0xd`/`0xe`) → **aggregate records by uuid with tmask union** before
   comparing.
4. **Load data is unobservable at the commit arbiter** (async LSU response path → stale
   data field). All initial data mismatches were `lw`. Loads scoped to
   PC/rd/ordering compare — then solved soundly in §5 (load-bus).
5. **Performance-counter CSRs are model-divergent by definition** (timing DUT vs
   functional golden — `mcycle` 1167 vs 1166); the golden flags them `is_volatile`
   (MPM CSR range `0xB00-B1F`/`0xB80-B9F`) and they are excluded, exactly as
   RVVI/ImperasDV do.

## 4. Generalization proven (A1a/b — divergence + multi-core, commit `eb08c04`)

- **SIMT divergence:** nested asymmetric split/join kernel (`diverge_uni3`,
  3v1→2v1→1v1 heavy partial masks) under lockstep → **2668/2668 matched** through
  divergence/reconvergence — uuid-aggregation + tmask-union needed zero comparator
  changes.
- **Multi-core/cluster attribution from RTL proof:** DUT uuid embeds a flat global
  `CORE_ID` (`VX_uuid_gen.sv:40`; flat across clusters via `VX_socket.sv:227` +
  `VX_cluster.sv:132`) matching SimX `cid` → `(cid,wid)` derived from uuid alone, no
  RTL change; wid mask config-generic (`(1<<NW_BITS)-1`).
- **Config-matrix validation (all lane-exact, 0 mismatches, 0 orphans, commit
  `e21a130`):** 1CL/1C/4W/4T (1035) · 1CL/2C (1801) · **2CL/2C (3333 — cluster term of
  the CORE_ID formula proven)** · 2W/2T (855, nw_bits=1) · 8W (1423, nw_bits=3).
  Axes: NCL∈{1,2} × NC∈{1,2} × NW∈{2,4,8} × NT∈{2,4}.

## 5. Flagship result — retiring the UNVERIFIABLE bucket (A1d/e)

Closes Part I's two biggest open items.

- **First-divergence pinpoint (A1d, commits `b029fe7`, `28c84ab`):** the 2-cluster
  fenceless divergence — Part I could only say "final memory differs, cluster-scoped."
  Lockstep replay of the pinned failing program pinpoints **the exact first divergent
  instruction: `mulhu s0,s3,a3` @ PC `0x800004f4`, seq 278, cluster-1 cores only
  (DUT s0=`0x3d75a09d` vs SimX `0x3d009f79`); cluster-0 byte-exact (0 divergences)** —
  and its *inputs* already diverged ⇒ upstream shared load, confirming at instruction
  granularity: golden-model ordering limit, **not a DUT bug**.
  *Writeup:* `docs/investigations/SimX_2CL_no_fence_divergence.md` §"First divergence —
  PINPOINTED".
- **A real golden-model bug found by lockstep (commit `6dfe665`, OBS-008):** SimX fetched
  at the exact byte PC; the DUT keeps the full odd PC after jalr-to-odd-target
  (`PC_BITS=XLEN`, `VX_gpu_pkg.sv:75-82`) but fetches word-aligned (`VX_fetch.sv:101`).
  SimX read misaligned bytes → undecodable word → `decode.cpp default: std::abort()` →
  runs falsely UNVERIFIABLE. Fix: word-align the emulator fetch (`PC & ~3`); a naive
  `& ~1` on JALR was tried and **reverted** with evidence (21968 phantom PC mismatches).
  Decoder now prints PC + instruction word before any abort — **every remaining abort
  self-documents**. *Lesson: lockstep verifies the reference model as much as the DUT.*
- **RVVI "load bus" for racy shared memory (A1e, commit `2dd48ea`) — the novel
  mechanism.** For fenceless multi-core programs the golden *cannot* predict racy load
  values (any interleaving is legal). Industrial RVVI feeds DUT-observed load data to
  the reference. Ours is a **sound two-pass trace-replay**:
  - Pass 1 captures divergent loads keyed `(cid, wid, PC, occurrence)`; they are fed to
    SimX via DPI (`cosim_loadfeed.h`, `execute.cpp` LOAD override); pass 2 re-runs and
    re-compares. **The residual is the verdict** — unexplained divergences stay hard
    errors; a `consumed==pushed` self-check guards feed alignment; pass-1 divergences
    are demoted to diagnostics **only when the feed is armed**.
  - **Result (pinned 2CL fenceless test):** 20 racy loads → 138 cascade → **residual 0
    over 5432/5432 retires**; deferred end-state compare (real `dut_mem` vs post-feed
    SimX) passes → a formerly-UNVERIFIABLE run is now **fully instruction-granularity
    VERIFIED** (commit `2dd48ea`, non-waiver reclassification `d29355a`/`2e6637e`).
  - Regression: vecadd_lite no-feed byte-identical (1035/1035); both Part-I injection
    guards still RED (wrong-value + dropped-store caught); no suite regression.
- **End-state compare re-sourced to the real memory model** (commit `2e6637e`):
  DUT values now come from `mem_model`, not `shadow_memory` — half of the planned
  single-source-of-truth scoreboard refactor landed as a byproduct.
- **Per-instruction LOAD-data compare made sound and default-on** (OBS-002 closed,
  commit `97c4e30`; LSU load-writeback probe `f8a1acc`).

## 6. The honest boundary (a precisely-stated negative result — keeps the paper credible)

- The interrupt-random test at 2CL collapses **116 → 7** residual divergences under the
  load feed and does **not** reach 0 (data=1, load=6; `consumed==pushed=82`).
- The 7 are proven **keying-independent**: re-keying the feed from ordinal to
  `(cid, wid, PC, occurrence)` leaves the residual **identical** (commit `2614ee0`) —
  this *disproves* feed-alignment artifacts. The residual is **genuine interrupt-delivery
  timing**: the timing-accurate DUT and the functional golden take the interrupt at
  different instruction boundaries; no amount of load-data feeding can align *when* an
  interrupt fires.
- Disposition: end-state memory compare (real `mem_model` vs post-feed golden)
  **passes** → end-state VERIFIED; instruction-granularity residual classified with
  evidence (OBS-010, commits `cc15697`, `ee4fea8`). **Not forced green.**
- This defines the method's **soundness boundary**: *two-pass trace-replay is a fixed
  point for data-only divergence; asynchronous-input timing requires a step-follower
  golden* — the documented next enhancement (ENH-1: single-pass step-driven SimX with
  interrupt-delivery alignment, ImperasDV-style; ENH-2/3 scoped alternatives; commit
  `d9df0eb`, plan §🔮 DEFERRED ENHANCEMENTS).

## 7. Supporting infrastructure landed with Part II

- First-divergence-per-(core,warp) capture + per-key error-spew caps in the lockstep
  scoreboard (usable failure reports at scale, commit `b029fe7`).
- A running **RTL observations register** `docs/RTL_OBSERVATIONS.md` (OBS-001…010,
  commit `02773ef` + updates): every microarchitectural quirk/limit/finding with
  evidence and disposition — the audit trail a sign-off review expects.
- Decode-abort observability (faulting PC + word printed before abort).

## 8. Status vs the full industrial plan (roadmap slide)

*Source:* `docs/INDUSTRIAL_TRANSFORMATION_PLAN.md` (single source of truth).

- **DONE (Phase A core):** A0 lockstep ✅ · A1a divergence ✅ · A1b multi-core ✅ ·
  A1d first-divergence pinpoint ✅ · A1e load-bus ✅ · config-matrix ✅ ·
  end-state→`mem_model` ✅.
- **IN PROGRESS:** A1c — migrate the probe hand-off to a bound `rvvi_if` + UVM
  monitor/analysis-port (core-v-verif `uvma_rvvi` pattern); also the prerequisite for
  the ENH-1 step-follower.
- **PLANNED (scoped in the plan):** A2 LSU address/data compare · A3 abort-hardening
  sweep (56 remaining `std::abort` occurrences → drive UNVERIFIABLE to 0) · A5 harvest DUT native
  `RUNTIME_ASSERT`s into the error gate · A6 Spike base-ISA independence audit ·
  Phase B (RAL, formal on MSHR/cache arbiter, SVA extension, single-scoreboard
  completion) · Phase C (traceable coverage plan, 2CL push, CDV, matrix sign-off) ·
  Phase D (CI, parallel/graded regression, seed farm, automated sign-off).
- Note: the founding plan's own "Future Work M1–M4" **is** this transformation
  (M1=lockstep, M3=SVA, M2=per-unit scoreboards, M4=cache/hazard) — we are executing the
  project's parked white-box roadmap.

## 9. Suggested paper claims

**Part I:**
1. A complete black-box UVM environment for an open-source SIMT GPGPU with a
   role-inverted (master-DUT) agent architecture and a DPI-integrated functional golden.
2. **Gate-0 non-vacuity methodology**: permanent fault-injection negative tests as
   regression guards — verdicts demonstrated non-vacuous, not assumed.
3. **Honest coverage closure**: config-aware, RTL-cited, machine-generated structural
   exclusions; structural-ceiling root-causing (toggle) instead of gaming; per-config
   banks with a proof that cross-config merging is invalid.
4. UNVERIFIABLE as a first-class, evidence-classified verdict.

**Part II:**
5. **First (to our knowledge) RVVI-style per-instruction lockstep for a SIMT GPGPU**,
   with five SIMT-specific alignment corrections as transferable design rules.
6. **A sound two-pass load-feed** rendering racy fenceless multi-core programs
   instruction-granularity verifiable — residual-as-verdict, injection-proven
   non-vacuous, residual 0 on the flagship case.
7. **A characterized soundness boundary**: data races solvable by trace-replay;
   asynchronous interrupt timing requires a step-follower — with the keying-independence
   proof of the residual.
8. **The golden model is a verification target too**: lockstep found and fixed a
   reference-model fetch bug that had been silently misclassifying runs.

## 10. Suggested paper skeleton

| § | Content | Source |
|---|---|---|
| 1 | Introduction, Vortex DUT, why GPGPU ≠ CPU verification | Part I §1–2 |
| 2 | Environment architecture + Gate-0 non-vacuity | Part I §3–4 |
| 3 | Stimulus + coverage-closure discipline + results | Part I §5–7 |
| 4 | Lockstep architecture + the five SIMT corrections | Part II §2–3 |
| 5 | Results: config matrix, UNVERIFIABLE retirement, golden-model bug | Part II §4–5 |
| 6 | Soundness boundary & limitations | Part II §6, Part I §9 |
| 7 | Related work: core-v-verif, ImperasDV/RVVI, riscv-dv | plan §A.1–A.3 |
| 8 | Future work: step-follower, Spike audit, formal, CI | Part II §8 |

---

## Appendix — Evidence index

### Key commits (main / Part I)
| SHA | What |
|---|---|
| `5f19a67` / `a46a109` / `b14efc5` / `df6206e` | Gate-0: C1 derived widths / C3 EBREAK completion / C2 real instr count / T4 honest error gate |
| `fe10b83` | Bidirectional scoreboard + dropped-store negative test |
| `47b29e5` `e8ca365` `2e51118` | INV-2 DCR/reset startup race root-cause + fix |
| `55661d7` | Core co-sim fix (SimX reset placement) + crash-guard → UNVERIFIABLE |
| `1ce1e9f` | Per-config SimX rebuild (multi-config end-to-end) |
| `5f6ddff` | riscv-dv pipeline |
| `0984bdf` / `d65441d` / `ff37765` | TCU verification / FPU op-decode / TCU multi-warp + timing waivers |
| `9fc45ae` `855f61e` `ae809f4` | RTL-cited structural exclusions + config-aware generator |
| `6692541` | Coverage report (two banks) |
| `199401c` `dcadb3d` `c525dfd` `6e6a81b` | Total-coverage push: vote_shfl, wide_stress+throttle, div_edge+flood-infra, flood run → 91.00% *(the 2026-07 bank; superseded)* |
| `554080e` | SimX RVVI export (`simx_retire_t` + cosim DPI) — pre-built enabler for Part II |

### Key commits (branch / Part II)
| SHA | What |
|---|---|
| `7aac709` | A0: per-instruction RVVI lockstep (SimX golden) |
| `eb08c04` / `e21a130` | A1a/b divergence + multi-core cid / config-matrix validation record |
| `b029fe7` `28c84ab` | A1d: first-divergence pinpoint infrastructure + 2CL no_fence pinpoint |
| `914f778` / `6dfe665` | OBS-007 decoder-abort root-cause / SimX word-aligned-fetch bug fix |
| `f8a1acc` / `97c4e30` | LSU load-writeback probe / sound default-on load-data compare (OBS-002) |
| `d29355a` / `2dd48ea` | OBS-009/010 root-cause / A1e RVVI load-bus (two-pass trace-replay) |
| `2e6637e` | End-state compare sourced from real `mem_model` |
| `cc15697` `2614ee0` `ee4fea8` `d9df0eb` | OBS-010 interrupt-timing boundary + keying-independence proof + ENH-1/2/3 backlog |

### Documents
- `docs/Coverage_Report_2026-07-10.md` — banked two-config coverage report
- `docs/Coverage_Model_Reference.md` — all 17 covergroups + sufficiency rationale
- `docs/AXI_SVA_report.md` — SVA layer, drops with RTL evidence
- `docs/investigations/SimX_2CL_no_fence_divergence.md` — multi-cluster divergence + real fix
- `docs/RTL_OBSERVATIONS.md` — OBS-001…010 running register (branch)
- `docs/fixes/` — fix_01–18, INV-1/INV-2 root-cause writeups
- `docs/VERIFICATION_PLAN.md` — founding plan (goals baseline)
- `docs/INDUSTRIAL_TRANSFORMATION_PLAN.md` — transformation plan + status (branch)
- `Vortex_UVM_Issues_Report_Final.docx` (external, team) — 43-issue bring-up report:
  symptom/root-cause/fix per issue, hex-authoring rules, program-loading guide (§8.0)
- `docs/COMMIT_HISTORY.md` — full chronological commit-content extraction (328 unique
  commits, all branches, names redacted) — the raw engineering timeline

### RTL citations used in waivers/findings
`VX_axi_adapter.sv:313` (bready≡1) · `VX_cache_mshr.sv:125-132` (MSHR priority-encoder) ·
`VX_cache_mshr.sv:242-247` (write-through) · `VX_schedule.sv:126/168/202/230` (wspawn
bootstrap / is_global / IPC ceiling / self-start) · `VX_dcr_data.sv:27` (no DCR reset) ·
`VX_gpu_pkg.sv:75-82` + `VX_fetch.sv:101` (odd-PC vs word-aligned fetch) ·
`core/VX_uuid_gen.sv:40` + `VX_socket.sv:227` + `VX_cluster.sv:132` (flat CORE_ID) ·
`core.cpp:223` (emulator/timing decoupling) · Papers: MICRO'21 §4.1.4, CARRV'19 §5.3/§6.3.

---

## Appendix P — Proofs (raw verification outputs, audit of 2026-07-16)

### P.1 Coverage tables — reproduced from the banked UCDBs with the tool

`vcover report -summary vortex_uvm_env/cov/bank_1CL_1C_4W_4T/merged.ucdb` (QuestaSim-64
vcover 2021.2_1, run 2026-07-16):

```
Coverage Report Totals BY INSTANCES: Number of Instances 2247
    Enabled Coverage              Bins      Hits    Misses    Weight  Coverage
    Assertions                     129       121         8         1    93.79%
    Branches                      2831      2581       250         1    91.16%
    Conditions                     313       239        74         1    76.35%
    Covergroups                     17        na        na         1   100.00%
            Covergroup Bins        377       374         3         1    99.20%
    Directives                       5         5         0         1   100.00%
    Statements                    4443      4312       131         1    97.05%
    Toggles                     425432    334632     90800         1    78.65%
Total coverage (filtered view): 91.00%
```

> ⚠️ **The raw tool output in this appendix is the 2026-07-10 bank, reproduced exactly as the
> 2026-07-16 audit verified it. It is EVIDENCE OF THAT AUDIT and is deliberately not updated —
> altering archived tool output would defeat the purpose of archiving it.** For current
> numbers re-run the same command against the present banks:
> `vcover report -summary vortex_uvm_env/cov/bank_1CL_1C_4W_4T/merged.ucdb` → total 94.72%.

`vcover report -summary vortex_uvm_env/cov/bank_2CL_2C_4W_4T/merged.ucdb`:

```
Coverage Report Totals BY INSTANCES: Number of Instances 8252
    Enabled Coverage              Bins      Hits    Misses    Weight  Coverage
    Assertions                     361       267        94         1    73.96%
    Branches                     10103      9061      1042         1    89.68%
    Conditions                    1180       821       359         1    69.57%
    Covergroups                     50        na        na         1    92.48%
            Covergroup Bins       1043       899       144         1    86.19%
    Directives                       5         5         0         1   100.00%
    Statements                   15284     14703       581         1    96.19%
    Toggles                    1249674    927924    321750         1    74.25%
Total coverage (filtered view): 85.16%
```

Every number in the Part I §7 table reproduces exactly. The 374/377 covergroup raw bins
(99.20%) also confirms the documented "3 weight-0 red-herring bins" (weighted metric
100.00%, 17 groups). The 43/43 and 40/42 pass counts are recorded in
`docs/Coverage_Report_2026-07-10.md` (banked, committed `6692541`).

### P.2 RTL / SimX citations — excerpts re-read from the working tree (pin `7a52ee5`)

| Citation | Verified content (exact line) |
|---|---|
| `VX_axi_adapter.sv:313` | `assign m_axi_bready[i] = 1'b1;` — B-channel backpressure structurally impossible |
| `VX_cache_mshr.sv:125-132` | `VX_priority_encoder #(.N(MSHR_SIZE)) allocate_sel (.data_in(~valid_table_n), ...)` — lowest-free slot allocation |
| `VX_cache_mshr.sv:242-247` | `end else begin : g_pending_wt // exclude write requests if writethrough` |
| `VX_schedule.sv:126` | `if (wspawn.valid && is_single_warp)` — wspawn only from single-warp state |
| `VX_schedule.sv:168-170` | `if (~warp_ctl_if.barrier.is_global && ...)` — local/global barrier split |
| `VX_schedule.sv:202-204` | `// stall the warp until decode stage` + `stalled_warps_n[schedule_wid] = 1;` — the IPC-ceiling mechanism |
| `VX_schedule.sv:230-232` | `warp_pcs[0] <= from_fullPC(base_dcrs.startup_addr); active_warps[0] <= 1;` — core self-starts from reset (INV-2) |
| `VX_dcr_data.sv:27` | `` `UNUSED_VAR (reset) `` — DCR registers have no reset (INV-2) |
| `VX_gpu_pkg.sv:75-82` | `` `ifndef NDEBUG localparam PC_BITS = `XLEN; `` + identity `to/from_fullPC` — debug build keeps full (odd) PC (OBS-008) |
| `VX_fetch.sv:101` | `icache_req_addr = schedule_if.data.PC[2-(XLEN-PC_BITS) +: ICACHE_ADDR_WIDTH]; // 4-byte aligned` — DUT fetch word-aligned (OBS-008) |
| `core/VX_uuid_gen.sv:40-41` | `g_wid = (GNW_WIDTH'(CORE_ID) << NW_BITS) + GNW_WIDTH'(wid); uuid = {g_wid, ...}` — uuid embeds flat core id (A1b) |
| `VX_socket.sv:227` / `VX_cluster.sv:132` | `CORE_ID = (SOCKET_ID * SOCKET_SIZE) + core_id` / `SOCKET_ID = (CLUSTER_ID * NUM_SOCKETS) + socket_id` — flat-global CORE_ID formula |
| `VX_commit.sv:56-60` | `VX_stream_arb #(.NUM_INPUTS(NUM_EX_UNITS), .ARBITER("P"), .OUT_BUF(1))` — priority commit arb (OBS-001 out-of-order retires) |
| `VX_commit.sv:164-174` | `commit_arb_if[i].data.{uuid,wid,sid,PC,tmask,rd,data,sop,eop}` — exactly the probe-captured fields |
| `VX_ipdom_stack.sv:50-52` | 3× `` `RUNTIME_ASSERT`` (full-push / empty-pop / push+pop) — A5 harvest targets |
| `VX_cache_mshr.sv:210+` | `` `RUNTIME_ASSERT`` inuse-allocation / invalid-release — A5 harvest targets |
| `VX_schedule.sv:415` | `` `RUNTIME_ASSERT(timeout_ctr < STALL_TIMEOUT, ...)`` — consumer of the OBS-011 buggy macro |
| `VX_config.vh:246` | `` `define STALL_TIMEOUT (100000 * (1 ** (`L2_ENABLED + `L3_ENABLED))) `` — `1**N ≡ 1` (OBS-011) |
| `sim/simx/core.cpp:223-225` | `auto trace = emulator_.step();` — functional emulator decoupled from timing |
| `sim/simx/emulator.h:93/54-58/107` | `instr_trace_t* step();` / `warp_t {ireg_file, freg_file, ibuffer, ipdom_stack,...}` / `read_dst_reg(wid, dst)` |
| `sim/simx/instr_trace.h:46-56/35` | `instr_trace_t {uuid, cid, wid, tmask, PC,...}` / `LsuTraceData.mem_addrs` |
| `ref_model/simx_dpi.cpp:~869` | "M1 COSIM RETIRE-RECORD INTERFACE … SV-side scoreboard polls simx_cosim_pop()" |
| 183 RTL modules | `find Vortex/hw/rtl -name "*.sv" \| wc -l` → 183 |
| Abort sites (2026-07-16) | `grep -c std::abort` → decode.cpp 35, execute.cpp 21 (= 56); 14 `DECODE_ABORT` call sites in decode.cpp |

### P.3 Lockstep flagship numbers — confirmed in the committed investigation doc

From `docs/investigations/SimX_2CL_no_fence_divergence.md` (verbatim lines):

```
first divergence:  cid=2 & cid=3 (cluster 1)  seq=278  PC=0x800004f4  uuid=…144
    800004f4:  02d9b433   mulhu s0,s3,a3      DUT s0=0x3d75a09d  vs  SimX s0=0x3d009f79
Tallies: compared 5432, matched 5314, field_mismatch data = 118 (59 per cluster-1 core)
Pass 2: residual mismatch = 0 (PC=0 rd=0 data=0 load=0 orphan=0/0) over the full 5432/5432
... The same feed only PARTIALLY collapses it (116→7 residual). Re-keying the feed to
(cid,wid,PC,occurrence) left the residual IDENTICAL (7)
```

Cross-checked with `docs/RTL_OBSERVATIONS.md` OBS-009/OBS-010 (incl. the 2CL injection
non-vacuity run: `matched 17664→17663`, one caught DATA mismatch) and the plan doc RESUME
block. Config-matrix tallies (1035/1801/3333/855/1423) are recorded in the plan
(`e21a130`); their raw sim logs were session scratch (not retained) — the only Part II
numbers whose primary logs are not in-tree; all were, however, recorded in committed docs
in the same session they were produced.

### P.4 Commit evidence

All 60 SHAs cited in this document verified to exist (`git cat-file -e <sha>^{commit}`,
0 missing); 13 key subjects spot-checked against their claimed content (all match, incl.
`5f19a67` "derive VX_MEM_TAG_WIDTH from RTL", `fe10b83` "bidirectional scoreboard —
dropped-store (reverse) pass + proof", `2dd48ea` "A1(e) RVVI load-bus: … VERIFIED
(non-waiver)", `6dfe665` "SimX fix: word-align instruction fetch"). Full chronological
content extraction: `docs/COMMIT_HISTORY.md` (328 unique commits, names redacted).
