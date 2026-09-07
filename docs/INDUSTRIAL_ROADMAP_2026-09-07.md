# Vortex UVM — costed roadmap, reconciled against the project's own plans

**Prepared:** 7 Sep 2026 · **Rev 2** — reconciled against `VERIFICATION_PLAN_v2.md` (3 Sep) and
`INDUSTRIAL_TRANSFORMATION_PLAN.md` (last updated 20 Aug).

**Premise:** the intellectual work is done. Almost everything below is volume, automation, and one
targeted soundness fix.

---

## 0. What the reconciliation found

Reading both plans changed this document substantially. **Your own FW-1…FW-7 already anticipates
most of what an outside reviewer would propose.** That is itself a finding: the planning is ahead
of the execution, which is the right way round but means the gap is *doing*, not *deciding*.

Every item below is now tagged:

- **`ALREADY PLANNED`** — exists in your plans under the ID shown. My contribution is sequencing
  and costing, not the idea.
- **`ADDITIVE`** — genuinely not in either plan.
- **`INTEGRITY`** — not a capability gap but a correctness problem in what you currently claim.
  These outrank everything else.

### The single most important thing I found

**FW-1b is still open, and it contaminates numbers that are on the deck right now.**

`riscv_pmp_test` and `riscv_non_compressed_instr_test` generate **byte-identical programs**
(`.S` md5 `16be14c6…`). Both delegate to `riscv_rand_instr_test` and differ only by `gen_opts`
that are inert under `--target=rv32im`. Your own plan states the consequence plainly:

> *"at 1CL, 2 of the '45/45' passes were the same program passing twice; at 2CL their identical
> failure is ONE divergence double-counted, not two."*

The deck currently says **50 staged runs per storm bank** and **45 of 51 on the L2/L3 tier**.
If two of those are one program, the honest counts are 49 and 44 — and an examiner who reads
`INDUSTRIAL_TRANSFORMATION_PLAN.md` will find FW-1b before you mention it.

This is a half-day fix (drop both entries, restate the count, add the md5-distinctness assertion
your plan already specifies) and it outranks every capability item in this document.

### The second

**`vortex_sanity_test` cannot fail.** v2 §5.1 says D-3 *"should be top priority — a test that
cannot fail, counted in a pass tally, is the most damaging item on that list."* Confirm it is
excluded from every tally and labelled un-failable — sign-off criterion 6 requires it.

---

# PHASE 0 — Integrity and pre-defence

| # | Task | Tag | Days | Acceptance |
|---|---|---|---|---|
| **P0.0** | **Close FW-1b** — drop or fix the two duplicate riscv-dv entries; restate the honest test count on the deck; assert md5-distinctness in the suite | `INTEGRITY` FW-1b | 0.5 | Every riscv-dv entry produces a program whose md5 differs from every other; the suite fails if that regresses |
| **P0.0b** | **Confirm `vortex_sanity_test` is excluded from all pass tallies** and labelled un-failable | `INTEGRITY` D-3 | 0.2 | Sign-off criterion 6 demonstrably met |
| **P0.1** | **Fix W-13 in v2 — it is stale.** It says *"quote the 42.6% figure … never the bare 10.3%"*, but §1 and §2 of the same document give the headline as **83.14%** (raw 22.32%). Two different number pairs for the same waiver | `INTEGRITY` | 0.2 | W-13 quotes the same figures as §1 |
| **P0.2** | **Resolve the RV32D contradiction between the two plans.** Transformation plan FW-6/G3 says `EXT_D_ENABLE` *is* in the flist, hardware *is* built, and it *"dilutes every coverage number"*. v2 §1 says D is *"structurally absent at the primary config"* because `EXT_D_ENABLE` is gated by `` `ifdef XLEN_64 ``. Both cannot be true, and the answer decides whether unstimulated D hardware is in your coverage denominator | `INTEGRITY` | 0.3 | One statement, one citation, the stale one struck |
| **P0.3** | Settle the 1CL Branch/Toggle numbers against the frozen UCDB | `INTEGRITY` | 0.5 | One row, one source; no two slides can disagree |
| **P0.4** | Collapse R-numbers and OBS-numbers into one scheme deck-wide | — | 0.5 | Any deck finding is findable in `RTL_OBSERVATIONS.md` |
| **P0.5** | Q&A → appendix-slide index (hidden slide + printed sheet) | `ADDITIVE` | 0.5 | Any appendix slide reachable in <5 s |
| **P0.6** | **Config-matrix sweep** — 8–12 topologies | `ALREADY PLANNED` FW-3 / C5 | 1.5 | A table of N configs × pass/fail with zero testbench edits. Your plan already says this is *"compute time, not engineering"* — so spend the compute |
| **P0.7** | Bug-discovery curve from git history | `ADDITIVE` | 0.5 | A plot showing discovery rate flattening |
| **P0.8** | Verify the agent appendix against source (AXI "8 sequences" on a responder; memory agent "7 sequences") | — | 0.5 | Every agent-slide claim traceable to file:line |

**Total ≈ 5 days.** The first four are integrity items and should happen before the defence
regardless of anything else.

---

# PHASE 1 — The stimulus engine

**Tag: `ADDITIVE` — and this is the finding that matters most for capability.**

Your plans' stimulus axis is **FW-1 (seed volume)** and **C4 (CDV-steered riscv-dv)**. Both are
about running *more seeds of riscv-dv*. But **riscv-dv is a scalar RISC-V program generator** — it
has no concept of a warp, a thread mask, a divergence tree or a barrier. A hundred more riscv-dv
seeds gets you a richer scalar instruction mix. It gets you **zero** additional divergence
topologies.

So the position today is: *the GPU-specific half of your stimulus is entirely directed*, and
neither plan proposes changing that. FW-7 asks for "sustained randomized pressure" without saying
what generates it.

**That is the gap.** You have a comparison engine that will check any program against a golden
model, and you are feeding it 33 hand-written kernels.

### Design

Randomise at the **program** layer. A Python generator emits C (or inline asm where you need
control the compiler won't give you); the existing flow compiles it and runs it down the path you
already built. **Self-checking programs are unnecessary** — SimX is the reference, so correctness
is free. The generator's only job is to produce *interesting* programs.

| # | Task | Days | Acceptance |
|---|---|---|---|
| **S1** | Randomised **divergence trees** — shape, depth (1…IPDOM max), nesting, uniform vs divergent, peeled masks | 6 | 50 generated programs lockstep-clean; `cp_split_depth` reaches max from random stimulus alone |
| **S2** | **Memory pattern** randomisation — stride, scatter degree, alignment mix, bank-hostile sequences | 3 | `coalesce_cg` hits all three kinds from random programs; **G-9's `conflict` bin finally non-zero** |
| **S3** | **Barrier topology** randomisation — participant subsets, nesting, barriers under peeled masks | 2 | `barrier_cg` size/event bins filled from random stimulus |
| **S4** | **VOTE/SHFL** randomisation — the 8 ops your `cp_vote_shfl_op` measured at **0/8** | 1 | `cp_vote_shfl_op` non-zero; closes the residual on G-1 |
| **S5** | **Seed harness** — `run_seeds.sh N`, one results CSV, deterministic replay | 2 | 200 rows; any failing seed replays bit-identically |
| **S6** | Nightly cron + dated summary | 1 | A results file appears each morning untouched |
| **S7** | **Auto-triage** — on failure emit first mismatch (PC, warp, lane, uuid), SimX vs DUT values, ±200-cycle waveform window | 3 | A failing run produces a one-page report with no manual debugging |

**Total ≈ 18 days.** Minimum viable = S1 + S5 + S7 (11 days).

**Note S4:** your own G-1 closure measured `cp_vote_shfl_op` at **0/8** — the only coverage model
in existence that can score Vortex's VOTE/SHFL ops (W-12), and nothing has hit it. That is a
one-day win sitting in plain sight.

---

# PHASE 2 — The independence question

**Tag: `ALREADY CONSIDERED AND REJECTED` — FW-2. Read this section carefully; I am partially
disagreeing with your plan and you should decide, not me.**

FW-2 says:

> *"Extending Spike to SIMT was considered and **rejected**: it would produce a second
> Vortex-specific model and recreate the very dependence this item exists to remove. Closing the
> SIMT half needs a genuinely independent SIMT model, which does not exist today."*

**That reasoning is correct for the thing it rejects.** Extending Spike into a full SIMT ISS would
mean re-implementing Vortex's execution semantics, by you, having read SimX — and the
independence would be illusory.

**My proposal is narrower and I think it survives the objection, but not completely.**

| | Extending Spike to SIMT (rejected) | Mask oracle (proposed) |
|---|---|---|
| Scope | Full execution: arithmetic, memory, control | **Control only** — IPDOM stack, `split`, `join`, `tmc`, `bar`, `wspawn` |
| Output | Architectural state | **The `tmask` sequence per warp**, nothing else |
| Size | A simulator | A few hundred lines |
| Checks | The same property SimX checks | A **different property**, against a field your RVVI record already publishes |
| Independence | Illusory — author has read SimX | **Only if written from the ISA spec by someone who has not read SimX** |

The honest position: this does **not** deliver the "genuinely independent SIMT model" FW-2 says
does not exist. It delivers a **partial, control-layer cross-check** that reduces the shared
blind-spot risk on the one axis where the risk is highest and the semantics are simplest to
specify. Arithmetic stays SimX-only.

**The independence is entirely contingent on authorship.** If you write it, having spent months
in SimX, it is worth much less. **If a different team member writes it from the ISA documentation
without reading SimX, it is worth a great deal.** That is a real option you have and it costs you
coordination, not engineering.

| # | Task | Days | Acceptance |
|---|---|---|---|
| **I1** | Mask oracle — IPDOM/`split`/`join`/`tmc`/`bar`/`wspawn` only, **written from the spec**, no arithmetic, no memory, no timing | 5 | Predicts the mask sequence for all 33 kernels |
| **I2** | Diff harness vs the published `tmask` field | 2 | Zero divergences across regression, with a fault-injection proof it *can* diverge |

**Total ≈ 7 days.** My recommendation: **do it, with a different author, and claim it precisely** —
*"an independently-authored control-layer oracle agrees on the mask sequence for every program"*,
never *"we have an independent SIMT reference"*. FW-2's ceiling stays where your plan puts it.

---

# PHASE 3 — Coverage depth

**Tag: mostly `ALREADY PLANNED` — v2's G-2, G-5, G-8, G-10 and the G-9 stimulus half.** Your
backlog is better itemised than mine, with RTL citations. I am only adding sequencing and one idea.

| # | Task | Tag | Days | Acceptance |
|---|---|---|---|---|
| **C1** | **G-9 stimulus half** — the bank-hostile kernel | `ALREADY PLANNED` G-9 | 1 | `cp_bank_conflict.conflict` non-zero (also falls out of S2) |
| **C2** | **G-2 branch direction** — new bind on `VX_branch_ctl_if` | `ALREADY PLANNED` G-2 | 1 | taken/not-taken bins live |
| **C3** | **G-5 GPR bank conflicts** | `ALREADY PLANNED` G-5 | 1 | `cp_bank_conflict_degree` live |
| **C4** | **G-8 ibuffer occupancy** | `ALREADY PLANNED` G-8 | 0.5 | per-warp occupancy binned |
| **C5** | **G-10 cross-core interaction** | `ALREADY PLANNED` G-10 | 1 | `cp_core_concurrency` + `cp_mem_arb_winner` live |
| **C6** | **G-3 residual** — the `by_zero`/`overflow` pure bins your own note says stayed 0 because `div_edge` rotates operands per lane. A kernel with all lanes on the identical corner | `ALREADY PLANNED` G-3 residual | 0.5 | Pure bins non-zero |
| **C7** | **G-6 residual** — `zero`/`inf`/`nan` FP class bins need dedicated special-value stimulus | `ALREADY PLANNED` G-6 residual | 1 | 6/6 on `cp_rs1_class` |
| **C8** | **Ten crosses**, chosen not sprayed: divergence depth × mask density; depth × memory op class; cache state × MSHR occupancy × request type; warps × barrier participants; coalescing class × access size; hazard class × unit | `ADDITIVE` | 3 | Ten crosses, each with a stated reason it is interesting |
| **C9** | Auto-generated closure report — per-covergroup hit/total, misses classed *unhit* / *EUR* / *EOTH* with citations | `ALREADY PLANNED` D5 | 2 | One command; no hand-maintained tables |

**Total ≈ 11 days.** C6 and C7 are your own honestly-recorded residuals — closing them is cheap and
removes two "still zero" caveats from the story.

---

# PHASE 4 — The axis I under-weighted

**Tag: `ALREADY PLANNED` FW-5 — and your plan is more right than my first draft was.**

I proposed formal before X-propagation. Reading FW-5, that ordering is wrong:

> *"X-prop is likely to find real bugs here — INV-2 already established that the base DCRs have
> **no reset**."*

A known un-reset register plus X-propagation is a concrete lead, not a speculative one. You also
already have R10 (a reset relay in a flop nothing resets, producing X for a cycle) as direct
evidence this class of bug exists in this design.

| # | Task | Tag | Days | Acceptance |
|---|---|---|---|---|
| **X1** | X-propagation run with pessimistic X settings, targeting the un-reset DCRs | `ALREADY PLANNED` FW-5 | 3 | X-prop clean, or a finding |
| **X2** | Randomised reset sequencing — release timing, mid-run assert | `ALREADY PLANNED` FW-5 | 2 | No new failures, or a finding |
| **F1** | Formal on the **IPDOM stack**: push/pop balance, no underflow, reconvergence restores the entry mask | `ALREADY PLANNED` (Phase A/B "formal on control blocks") | 5 | Proven, or a counterexample |
| **F2** | Formal on **MSHR** allocate/release | `ALREADY PLANNED` | 5 | Proven bounded |

**Total ≈ 15 days.** If you do one: **X1**, because the lead is concrete. If you do two: **X1 + F1**
— F1 complements the Phase 2 oracle exactly (formal proves the stack *implementation*, the oracle
checks the *observed sequence*).

---

# PHASE 5 — Infrastructure

**Tag: `ALREADY PLANNED` — this is your D1–D5, essentially unchanged.** I have nothing to add
beyond costing, except R4.

| # | Task | Tag | Days | Acceptance |
|---|---|---|---|---|
| **D1** | Parallel + graded regression, `vcover ranktest` minimal sign-off set | D1 | 3 | Wall-clock down, licence-respecting |
| **D3** | CI + results database + coverage trend | D3 | 3 | Queryable history; "which seed first hit this bin?" answerable |
| **D5** | Automated sign-off report + requirements traceability | D5 | 3 | Thesis appendix generated, not typed |
| **R1** | One-command reproducibility from clean clone | D5 | 2 | `./setup && ./run_all` reproduces the defence banks |
| **R4** | **Re-run against upstream Vortex `master`; report which findings still reproduce** | `ADDITIVE` | 2 | A table: finding × still-present-upstream × commit |

**Total ≈ 13 days.** R4 is the sleeper — you already have two findings confirmed upstream; a
systematic re-check turns "confirmed upstream" from an anecdote into a method.

---

# Sequencing

## 1 week (pre-defence)
**Phase 0 only.** ≈5 days. The four integrity items are non-negotiable — FW-1b in particular,
because the affected numbers are on slides today.

## 1 month
Phase 0 → **S1, S4, S5, S7** → **C1, C6, C7**.
≈18 days. You gain a random program generator, a nightly regression, auto-triage, and three of
your own recorded residuals closed.

## 3 months — the version that reads as mid-decile industrial
Phase 0 → Phase 1 complete → Phase 2 (**with a second author**) → Phase 3 → **X1** → R1, R4.
≈55 days. Publishable rather than a good project report.

## 6 months
Add F1, F2 and Phase 5 complete.

---

# What each phase does to the four criticisms

| Criticism | Closed by | Your own plan's ID |
|---|---|---|
| Stimulus is thin, and the GPU half is entirely directed | **Phase 1** | *not in either plan* — the real gap |
| No independent SIMT reference | Phase 2, **partially and contingent on authorship** | FW-2, which correctly bounds the claim |
| Coverage is shallow | Phase 3 | G-2, G-5, G-8, G-10, G-3/G-6/G-9 residuals |
| No automation, one config point | P0.6, S5–S7, Phase 5 | FW-3, D1–D5 |

---

# Assessment of the two plans

Worth saying, because it bears on how much of this document you should trust over your own.

**`VERIFICATION_PLAN_v2.md` is a genuinely strong document** — better than most industrial
verification plans I have seen. Specifically: the three-layer model with named owners and
"blind to" columns; the disjointness *proof* rather than assertion; the EUR/EOTH split with the
hits-invariant gate; §5's explicit list of corrections to its own predecessor including "D-8 is
FALSE"; and waivers that cite RTL lines rather than convenience. The habit of recording a closure
*and* its residual honestly (G-3's pure bins, G-6's `zero`/`inf`/`nan`, G-9's `conflict`) is the
single best signal in it.

**`INDUSTRIAL_TRANSFORMATION_PLAN.md` has become two documents wearing one filename.** It is a
1,593-line hybrid of a plan and a chronological working log, with stale layers explicitly marked
(*"the text below is STALE — do not re-derive from it"*). The continuity value is real and the
FW-1…FW-7 assessment is excellent — the line *"a good microscope pointed at ~42 slides"* is the
most accurate one-sentence summary of this project anyone has written, including me.

But it is now hard to navigate, and stale content marked as stale is still content a reader can
quote back at you. **Recommendation: split it.** `TRANSFORMATION_PLAN.md` keeps §0, Phases A–E,
sequencing, acceptance and FW-1…FW-7. `PROJECT_LOG.md` takes every dated RESUME block. Fifteen
minutes of work, and the plan becomes quotable again.

**Two things in it are now superseded and unmarked:** FW-6/G3's RV32D claim (see P0.2) and D4
(absorbed into FW-1, which is noted — good).
