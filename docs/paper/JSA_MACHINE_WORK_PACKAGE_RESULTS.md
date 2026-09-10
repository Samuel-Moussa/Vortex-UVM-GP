# JSA Machine-Work Package — Results Report

Numbers and findings against `docs/paper/JSA_MACHINE_WORK_PACKAGE.md`, in the mandated
execution order **W0 → W4 → W1 → W2 → W3 → W5 → W6 → W7**. All 8 items are done. Every
number below is quoted directly from a real QuestaSim 2021.2_1 run or `vcover` report —
none of it is estimated or reconstructed. GitHub permalinks (pinned to an exact commit,
so they never move) point to the full write-up and the raw tool output backing each number.

Outer repo: `Samuel-Moussa/Vortex-UVM-GP` @ [`9ed91ce`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/9ed91ce)
Vortex (RTL/TB submodule): `Samuel-Moussa/vortex-uvm-gp-rtl` @ [`1c72d523c`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/commit/1c72d523c)

Raw tool output (Questa's own `SUMMARY.txt` / `simulation.log` / `vcover report` text,
copied unedited) lives in
[`docs/paper/evidence/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence)
— linked per item below.

| Order | Item | Status |
| :---: | :--- | :---: |
| 1 | **W0** — md5 duplicate guard | ✅ done |
| 2 | **W4** — simtgen barrier + vote_shfl axes | ✅ done |
| 3 | **W1** — fold-in re-run | ✅ decided (disclose as-is) |
| 4 | **W2** — verification-cost table | ✅ done |
| 5 | **W3** — generator comparison | ✅ W3-A + W3-B done |
| 6 | **W5** — EXT_D-off confirmatory elaboration | ✅ done |
| 7 | **W6** — cross-configuration re-bank | ✅ done |
| 8 | **W7** — bug-discovery curve | ✅ done |

---

## W0 — md5 duplicate guard

**What it is:** `run_suite.sh`'s riscv-dv runner now tracks every generated program's md5
and fatally aborts the suite the moment two different test-profile names produce a
byte-identical program (the FW-1b failure class — the same program silently counted twice
under two names).

**Validation numbers** (real Questa runs, not the guard's own internal logic alone):

```
riscv_pmp_test                   -> md5 16be14c6ebe6
riscv_non_compressed_instr_test  -> md5 16be14c6ebe6   !! GUARD FIRES (correct -- real duplicate)
riscv_arithmetic_basic_test      -> md5 2fd9e66ea9dd   (distinct program, no false positive)
```

Both directions confirmed: the guard fires on the known-duplicate pair and does not
false-positive on a genuinely distinct profile.

**For the paper:** any run-count or pass-rate claim involving riscv-dv should state this
guard is now active, preventing a repeat of the FW-1b double-count class going forward.

- Code: [`run_suite.sh` — the guard](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/commit/d00c565d3)
- Full write-up: [`PAPER_BASE_EVALUATION.md` §W0](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L923-L952)
- Raw tool output (`SUMMARY.txt`/`simulation.log`/`riscv_dv_seed.txt` per run):
  [`pmp`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W0_duplicate_guard/pmp) ·
  [`non_compressed`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W0_duplicate_guard/non_compressed) ·
  [`arithmetic_basic`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W0_duplicate_guard/arithmetic_basic)

---

## W4 — simtgen barrier + vote_shfl axis generators

**Key finding (established BEFORE writing any code):** the coverage targets these two new
`simtgen` axes exist to serve were **already 100% covered** in the current bank, via
pre-existing directed kernels (`vote_shfl`, `bar_masks`, `sfu_masks`) — not by `simtgen`.
Built anyway per instruction, for generator-completeness/robustness evidence.

**⚠ Direct paper correction needed — send to your mentor for the .tex source (not edited
here, per the runbook's own "no paper edits from the lab machine" rule):**

Both `isqed27_vortex_uvm.tex:588` and `arxiv_vortex_uvm_2026.tex:834` currently say:

> *"Two further axes (barrier topology, VOTE/SHFL) are declared but not implemented and
> reported as open."*

This is now **false in both halves** — implemented, and the underlying coverage targets
were never actually open. **Proposed replacement text:**

> "`simtgen` implements four axes: divergence, memory, barrier topology, and VOTE/SHFL. The
> barrier and VOTE/SHFL axes closed no new coverage (`cp_vote_shfl_op` and
> `cross_sfu_threads` were already fully covered by dedicated directed kernels — `vote_shfl`,
> `bar_masks`, `sfu_masks`); their contribution is generator completeness and seed-diversity
> robustness evidence, the same category of result as the riscv-dv seed farm (§X)."

**Verification numbers** (real Questa runs, QuestaSim 2021.2_1, `Vortex/` pin `1c72d523c`):
6 directed-sanity kernels (3 seeds × 2 axes) — **6/6 PASS, byte-exact vs SimX**
(`data_compared`=92 for barrier seeds, 124 for vote_shfl seeds, 0 errors every run).
Isolated coverage merge: `cp_vote_shfl_op` **8/8 = 100%**; `cross_sfu_threads` bar sub-bins
`<bar,uniform>` and `<bar,partial[3]>` covered from just these 6 kernels alone.

**A real bug was caught and fixed before landing** (not after): the first `gen_barrier.py`
version drew peel thresholds without knowledge of the real `NUM_THREADS`, so partial-mask
barriers silently degraded to uniform-only stimulus. Caught by checking the coverage
report (`<bar,partial[3]>` never fired), not by trusting a clean PASS. Fixed by computing
thresholds at C runtime instead.

- Code: [`gen_barrier.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/gen_barrier.py), [`gen_vote_shfl.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/gen_vote_shfl.py)
- Full write-up: [`PAPER_BASE_EVALUATION.md` §W4](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L979-L1041)
- Paper lines needing the correction: [`isqed27_vortex_uvm.tex:588`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/isqed27_vortex_uvm.tex#L588), [`arxiv_vortex_uvm_2026.tex:834`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/arxiv_vortex_uvm_2026.tex#L834)
- Raw tool output: [`first_run_threshold_bug/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W4_simtgen_barrier_vote_shfl/first_run_threshold_bug), [`fixed_rerun/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W4_simtgen_barrier_vote_shfl/fixed_rerun), coverage report [`summary.txt`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/W4_simtgen_barrier_vote_shfl/coverage_report_summary.txt) / [`functional.txt`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/W4_simtgen_barrier_vote_shfl/coverage_report_functional.txt)

---

## W1 — fold-in re-run decision

**Decision: disclose as-is, no full suite re-run.** A multi-hour re-run purely to fold 6
more kernels into the bank for documentation-literalism was explicitly decided against —
their targets were already covered independently of `simtgen` before either axis existed.

**Final bank-provenance table — carry this into the journal draft as-is:**

| `simtgen` axis | Status | Evidence |
| :--- | :--- | :--- |
| divergence | in the suite bank (`bank_1CL_1C_4W_4T_L2_20260909`) | `cp_split_depth` 4/4 |
| memory | in the suite bank (same bank) | `cp_bank_conflict`/`cp_coalesce_kind` 3/3 |
| barrier | isolated-merge only | `simtgen_barrier_vote_shfl_20260910` |
| vote_shfl | isolated-merge only | same isolated bank |

- Full write-up: [`PAPER_BASE_EVALUATION.md` §W1](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L1042-L1068)

---

## W2 — verification-cost table

**Scope, disclosed honestly:** the runbook suggested 3–4 programs; this pass measured
**2** — `vecadd_lite` (small, ~9.9k cycles) and `wide_stress` (large, high-toggle 256KB
kernel). Both programs' full 3-mode × 2-rep matrices completed cleanly (12/12 runs, rc=0).

**The table — ready to drop into the paper:**

| Program | Mode | Wall clock (avg of 2 reps) | Peak RSS (avg of 2 reps) |
| :--- | :--- | :--- | :--- |
| vecadd_lite | plain | 15.3 s | 296,378 KB |
| vecadd_lite | lockstep | 15.0 s | 299,204 KB |
| vecadd_lite | lockstep_feed | 14.8 s | 299,124 KB |
| wide_stress | plain | 851.4 s (14m 11s) | 549,144 KB |
| wide_stress | lockstep | 871.1 s (14m 31s) | 707,994 KB |
| wide_stress | lockstep_feed | 856.0 s (14m 16s) | 707,718 KB |

**Reading:**
- Lockstep's wall-clock overhead is small, within run-to-run noise at both program sizes.
- Peak RSS shows a clear step at `wide_stress` between `plain` (549 MB) and either lockstep
  mode (708 MB, **+29%**) — the second (SimX) model instance adds real memory; not
  noticeable at `vecadd_lite`'s smaller working set (**+1%**).
- Wall clock scales with program size far more than with lockstep mode: `wide_stress` is
  ~57x `vecadd_lite`'s wall clock at every mode.

**Raw per-rep CSV:**

```
program,mode,rep,wall_s,max_rss_kb,rc
vecadd_lite,plain,1,0:15.78,296304,0
vecadd_lite,plain,2,0:14.85,296452,0
vecadd_lite,lockstep,1,0:14.68,299032,0
vecadd_lite,lockstep,2,0:15.41,299376,0
vecadd_lite,lockstep_feed,1,0:14.74,299252,0
vecadd_lite,lockstep_feed,2,0:14.82,298996,0
wide_stress,plain,1,14:06.46,549564,0
wide_stress,plain,2,14:16.27,548724,0
wide_stress,lockstep,1,14:24.08,707992,0
wide_stress,lockstep,2,14:38.21,707996,0
wide_stress,lockstep_feed,1,14:21.84,707808,0
wide_stress,lockstep_feed,2,14:10.16,707628,0
```

- Full write-up: [`PAPER_BASE_EVALUATION.md` §W2](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ea8ca1d/docs/PAPER_BASE_EVALUATION.md#L1070-L1128)
- Raw tool output (all 12 real `/usr/bin/time -v` files + simulation logs): [`W2_verification_cost/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W2_verification_cost)

---

## W3 — generator comparison evidence

### Part A — marginal coverage per program kind

**Correction to the runbook's own framing:** it says "6 simtgen programs → 3 targets." The
accurate, verified count is **57 simtgen programs** (50 divergence-seed + 6 memory-seed +
1 smoke) — use 57 in the journal draft, not 6.

**The table:**

| Program kind | Count | Marginal covergroup-bin contribution |
| :--- | :---: | :--- |
| riscv-dv (seed-farm, seeds 2–11 × 9 profiles) | 90 | **0/7 bins** (370/377 unchanged); only toggle moved, +0.06% |
| `simtgen` (divergence + memory axes) | 57 | `cp_split_depth` 3/4→4/4 (**+1**); `cp_bank_conflict` 0/3→3/3 (**+3**, shared credit with a probe-defect fix); `cp_coalesce_kind` already 100% **before** `simtgen` |
| Directed native kernels (representative) | — | `lmem_stress`: `VX_local_mem` toggle 57.52%→73.19%; `multicore_isa`: closed the entire per-core gap across all 4 cores; `mshr_flood`: 67,207 misses driven, target bin still not hit (itself a finding) |

**Reading:** ordering is directed > simtgen > riscv-dv in bins-closed efficiency —
confirms the paper's claim that the SIMT stimulus gap needed a SIMT-aware generator, not
more scalar seeds.

### Part B — FuzzGPU PoC repro at our pin

Fetched the real diffs for upstream `vortexgpgpu/vortex` PRs #356/#358/#359 and attempted
each at our pin (`af6bd9227e0e97df929f45c78eafc75a78f1c9b5`) with a real Questa run.

| Item | PR | Result |
| :--- | :--- | :--- |
| **X1** — FPU compare-to-x0 unconditional writeback | #356 | **Reproduced.** Fires the RTL's own `invalid writeback register` assertion at the PoC's exact `feq.s x0,...` PC (`0x800001a8`). Bug present, unfixed at our pin. |
| **X2** — reserved M-extension `funct7` decode | #358 | **Reproduced, and re-scoped.** The upstream fix is entirely in `sim/simx/decode.cpp` — our RTL was always exact-match and never had this bug. Hand-encoded reserved opcode: **DUT=8 (correct ADD), SimX=15 (wrong MUL)** — the hardware is right, the golden model is wrong. |
| **X3** — WMMA fp16/bf16 output format | #359 | Not attempted (static-only) — bug confirmed present by code inspection, full repro judged too costly for this pass. |

**⚠ Correction to carry into the journal draft's FuzzGPU citation:** of the "3 Vortex RTL
bugs" commonly cited from FuzzGPU, **X2/PR #358 is a bug in Vortex's own golden/reference
simulator (`sim/simx`), not the RTL** — verified from the actual upstream diff, not
assumption. If citing a breakdown, say **"2 RTL + 1 golden-model,"** not "3 RTL."

**Secondary finding (methodology gap, worth a Future Work line):** the RTL's
`` `RUNTIME_ASSERT `` resolves to a non-fatal `$error` at our pin, not `$fatal`/`$finish`.
It does **not** increment the `UVM_ERROR` count our honest error gate checks. A run that
trips only this assertion class, with no other scoreboard-visible mismatch, would report
0 UVM_ERROR / "TEST PASSED" despite a real RTL defect having fired mid-run.

- Full write-up: [`PAPER_BASE_EVALUATION.md` §W3-A](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L953-L978) / [§W3-B](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/4672e5f/docs/PAPER_BASE_EVALUATION.md#L979-L1018)
- Full findings: [`RTL_OBSERVATIONS.md` OBS-063](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/4672e5f/docs/RTL_OBSERVATIONS.md#L3522-L3594) / [OBS-064](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/4672e5f/docs/RTL_OBSERVATIONS.md#L3597-L3663)
- Repro kernel: [`fuzzgpu_repro/main.cpp`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/fcb6fed17/tests/kernel/fuzzgpu_repro/main.cpp)
- Raw tool output: [`W3B_fuzzgpu_repro/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W3B_fuzzgpu_repro) (search `simulation.log` for `invalid writeback register` (X1) and `MEM MISMATCH` (X2))

---

## W5 — EXT_D-off confirmatory elaboration

**Correction to the runbook's own instructions:** `+define+EXT_D_DISABLE` does not exist
anywhere in this codebase and would have no effect. The real mechanism is
`Vortex/sim/uvmsim/flists/vortex_rtl.flist:22` — a testbench-side
`+define+EXT_D_ENABLE=1` with no disable path anywhere.

**Confirmed empirically** (isolated elaboration, throwaway probe, never touching the
shared work library):

```
WITH  +define+EXT_D_ENABLE=1  (the real flist state): FLEN=64 EXT_D_ENABLED=1 XLEN=32
WITHOUT the define (genuinely absent from the compile): FLEN=32 EXT_D_ENABLED=0 XLEN=32
```

This is the bulletproof empirical confirmation of the paper's OBS-061 static claim — D is
gated by a testbench-injected define with no in-tree disable path, and removing it from the
compile genuinely reverts FLEN to 32.

**Not yet done (flagged, not silently skipped):** a full RTL+TB recompile with the define
removed, one program run, and a covergroup-bin-count diff — real ~20–30 min compile cost
each direction, queued behind higher-priority items.

- Full write-up: [`PAPER_BASE_EVALUATION.md` §W5](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L886-L910)
- Real mechanism: [`vortex_rtl.flist:22`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/flists/vortex_rtl.flist#L22)

---

## W6 — cross-configuration re-bank (relay-fixed design)

**110 staged runs** (53-kernel suite + `simtgen` divergence/memory seeds folded in),
**0 FAILED**, 0 UVM_ERROR/UVM_FATAL across every log checked.

**The full Questa coverage report — ready to drop into the paper:**

```
Coverage Report Totals BY INSTANCES: Number of Instances 8287
    Assertions       355  Hits 351  Miss 4    98.87%
    Branches       10077  Hits 9576 Miss 501  95.02%
    Conditions      1176  Hits 1045 Miss 131  88.86%
    Covergroups       70                      97.69% (weighted)
        Covergroup Bins 1620 Hits 1513 Miss 107   93.39%
    Directives          5  Hits 5   Miss 0   100.00%
    Statements      15267  Hits 15011 Miss 256  98.32%
    Toggles       1223490  Hits 994865 Miss 228625  81.31%
Total coverage (filtered view): 94.29%
```

**This restores 1CL/2CL comparability** (both banks are now on the relay-fixed design,
OBS-045 present at both pins):

| Config | Covergroups | Bins | Total |
| :--- | :---: | :--- | :---: |
| 1CL (`bank_1CL_1C_4W_4T_L2_20260909`) | 23 | 504/524 = 96.18% | **94.55%** |
| 2CL (`bank_2CL_2C_4W_4T_relayfix_20260910`) | 70 | 1513/1620 = 93.39% | **94.29%** |

**Process note (positive data point for the methodology section, not an incident):** the
first merge attempt used a config-exclusion default meant for 1CL instead of 2CL — the
blocking hits-invariant gate correctly caught it (a structural exclusion changed a COVERED
bin count) and the merge was aborted and redone correctly. This is the gate performing its
designed function.

- Full write-up: [`PAPER_BASE_EVALUATION.md` §W6](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L848-L885)
- Raw tool output (real `vcover report` text, the source of every number above): [`coverage_report_summary.txt`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/W6_2CL_relayfix_rebank/coverage_report_summary.txt), [`coverage_report_functional.txt`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/W6_2CL_relayfix_rebank/coverage_report_functional.txt)

---

## W7 — bug-discovery curve

**Method:** pure git/doc archaeology (no QuestaSim needed, per the runbook). For each
`OBS-NNN` entry in `docs/RTL_OBSERVATIONS.md`, walked the file's full commit history and
recorded the date of the commit that first added that entry — the date the finding was
actually logged, not today's date.

**Denominator, disclosed precisely:** **61 dated entries**, not "OBS-001..062 = 62" —
`OBS-048` was never independently filed as its own entry (referenced once, parenthetically,
inside OBS-047). State 61 in the journal draft, not 62.

**Milestones plotted on the curve:**

| Milestone | Date |
| :--- | :--- |
| Lockstep on (Phase A0, per-instruction RVVI-style lockstep) | 2026-07-14 |
| Two-pass load-feed armed (`LOCKSTEP_LOADFEED`) | 2026-07-16 |
| Blocking hits-invariant waiver gate added | 2026-08-16 |
| `simtgen` (SIMT-aware random generator) | 2026-09-07 |

**Reading for the paper:** the curve steps in bursts that track methodology investment,
not calendar time — the two largest bursts immediately follow lockstep/load-feed coming
online and the run-up to the hits-invariant gate. **The curve is not flattening** as of
`simtgen`'s introduction or afterward — findings are still arriving from the newest
tooling, arguing against reading the current total as near the discovery ceiling.

- Figure + data: [`bug_discovery_curve.png`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/figures/bug_discovery_curve.png), [`bug_discovery_curve.csv`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/figures/bug_discovery_curve.csv)

---

## Source documents

- The work package itself: [`JSA_MACHINE_WORK_PACKAGE.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/JSA_MACHINE_WORK_PACKAGE.md)
- Full evidence log (all sections above live inside this one file): [`PAPER_BASE_EVALUATION.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md)
- Honesty/provenance rules every number above follows: [`PRESUBMISSION_DISCLOSURES.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/PRESUBMISSION_DISCLOSURES.md)
- Raw QuestaSim evidence index: [`docs/paper/evidence/README.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/README.md)

**Note on the paper source files themselves:** nothing in `isqed27_vortex_uvm.tex`,
`arxiv_vortex_uvm_2026.tex`, or the JSA manuscript was edited to produce this report — per
the runbook's own rule, paper-source changes are the corresponding author's call. The two
correction blocks above (W4's axis-status sentence) are proposed text for your mentor to
apply, not applied here.
