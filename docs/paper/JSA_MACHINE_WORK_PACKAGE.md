# JSA Extension — Machine-Work Package

**Purpose.** Hands-off runbook for the lab machine (QuestaSim) work needed to
upgrade the conference paper into the Journal of Systems Architecture (JSA)
extended version. Written 2026-09-10 by the session that produced the
conference submission. Every item below maps to a known reviewer demand
(major-review items M1/M7/M8 from the pre-submission review) or to a
journal-completeness requirement.

**Audience.** A co-author with access to the QuestaSim machine and basic
familiarity with the repo. No deep context needed — each item is
self-contained; ask the repo owner only where a step says ESCALATE.

**Related documents (read these first):**
- `docs/paper/PRESUBMISSION_DISCLOSURES.md` — honesty rules; §8 has the
  short-form fold-in runbook this file expands.
- `docs/PAPER_BASE_EVALUATION.md` — the audited evidence base; the format
  every new number must follow (provenance: bank name, date, config,
  tool version, commit SHA).
- `docs/VERIFICATION_PLAN_v2.md` — coverage model definition, gap
  register (G-items), simtgen axis definitions.
- `docs/RTL_OBSERVATIONS.md` — findings register (OBS-items); add new
  entries there if any run surfaces a new defect.

---

## 0. Ground rules (apply to every item)

1. **Never modify or overwrite a frozen bank.** The frozen banks
   (`bank_1CL_1C_4W_4T_relayfix_20260818` etc.) are the evidence behind
   the submitted numbers. New runs go into NEW bank directories.
2. **Record provenance for every number you produce:** bank directory
   name, date, configuration string, QuestaSim version (`vsim -version`
   output), and the repo commit SHA (`git rev-parse HEAD`). Append
   results to a new section at the end of
   `docs/paper/PAPER_BASE_EVALUATION.md` titled
   `## Journal extension evidence (YYYY-MM-DD)`.
3. **Version-consistency caveat.** The frozen banks were made with
   QuestaSim 2021.2. If the lab machine has a different version, the new
   bank's numbers may shift slightly (elaboration/coverage accounting
   differs across versions). This is acceptable IF disclosed — record
   the version, never blend new runs into comparisons against frozen
   banks without stating both versions.
4. **Environment bring-up:** `cd Vortex/sim/uvmsim && source
   scripts/prepare.sh` (expects the RISC-V toolchain where the script
   looks for it — check `RISCV` path inside the script and adapt if the
   lab layout differs) — then confirm a single sanity run passes
   (`vecadd`, exit code 0) before starting any campaign.
5. **If any run fails unexpectedly:** do not retry blindly. Capture the
   log, classify (RTL assertion / lockstep mismatch / golden-model
   abort), and if it is a genuine new finding, open an OBS entry in
   `docs/RTL_OBSERVATIONS.md` before proceeding. A new finding is
   publishable material, not an obstacle.

---

## W0 — Wire the FW-1b duplicate guard  *(pre-flight, do first)*

- **Goal:** make the suite mechanically duplicate-free, closing roadmap
  item P0.0, so the new fold-in bank can claim it.
- **Steps:** in `Vortex/sim/uvmsim/scripts/run_suite.sh`, after each
  program's `.S`/ELF is produced, compute `md5sum` and assert the hash
  is not already in this run's set; abort the suite on a duplicate.
  (History: `riscv_pmp_test` was byte-identical to
  `riscv_non_compressed_instr_test`, dropped at commit `eb8a630`.)
- **Definition of done:** suite runs to completion with the guard
  active and no false positive; one-paragraph note + diff appended to
  the evidence base.
- **Effort:** 1–2 hours.

## W4 — Finish simtgen: barrier + vote_shfl axes  *(code work — do BEFORE W1)*

- **Why:** the papers state two generator axes are "declared but not
  implemented." A journal reviewer will not accept that sentence. Doing
  W4 before the fold-in means ONE campaign closes everything, including
  `cp_vote_shfl_op` (currently 0/8 post-remediation).
- **What exists:** divergence + memory axes are implemented and closed
  three targets (see OBS-060 addendum + `cov/simtgen_*_20260907`).
  Axis definitions and RTL citations are in `VERIFICATION_PLAN_v2.md`
  (SIMT items; SFU `VX_decode.sv:507-517` for VOTE/SHFL ops).
- **Steps:** implement the two axis generators in the simtgen source
  (barrier: `wspawn`/barrier topologies under partial masks; vote_shfl:
  the 8 ops — all/any/uni/bal, up/down/bfly/idx — under divergent
  masks), emit test C programs, verify each axis's programs are
  byte-exact against SimX first (directed sanity), then bank their
  coverage in isolation exactly as the 2026-09-07 isolated merges did.
- **Definition of done:** new isolated-merge bank(s) show
  `cp_vote_shfl_op` > 0/8 and any barrier-related bins hit; programs
  pass lockstep/end-state; note appended to evidence base.
- **Effort:** 3–5 working days including debugging.
- **ESCALATE:** if the barrier axis collides with the G-1 instruction-class
  aliasing remediation, ask the repo owner which coverpoint revision to
  target.

## W1 — The fold-in re-run  *(the headline item — unblocks the "Closure" title)*

- **Goal:** one full-suite campaign WITH simtgen's axes in the stimulus
  mix, producing a new bank whose totals INCLUDE the SIMT closures. This
  upgrades the paper's "Closure Methodology" back to demonstrated
  closure and is the single most valuable run.
- **Steps:**
  1. Confirm W0 guard active, W4 merged (otherwise run with 2 axes and
     disclose — still valuable, but say which axes).
  2. Run the full 1CL/1C/4W/4T suite (the 51-run relay-fix composition,
     plus simtgen axis programs appended as new suite members — do NOT
     drop existing members; the bank must be a superset experience).
  3. `vcover merge` into `cov/bank_1CL_1C_4W_4T_simtgen_<date>/`.
     The blocking **hits-invariant waiver gate** must run and pass
     (same exclusions file; any waiver whose bin has hits in the
     unwaived run aborts the merge — this gate caught two real waiver
     defects historically; if it fires, investigate, do not bypass).
  4. `vcover report -summary` + per-category report; save transcripts.
  5. Expected, minimally: `cp_split_depth` 4/4, `lmem_bank_cg` 3/3,
     `coalesce_cg` 3/3 **in the suite bank** (not just isolated merges);
     with W4 done, `cp_vote_shfl_op` ≥ 1/8. Report whatever is true.
  6. Record totals + provenance per ground rule 2. Compare to the
     relay-fix bank (94.72% total) and report the delta honestly —
     totals may go DOWN if the denominator grew; that is a result, not
     a failure.
- **Definition of done:** new bank + summary report committed (or its
  transcripts, if UCDBs stay machine-local per repo convention) +
  evidence-base section updated.
- **Effort:** 1–2 days wall-clock (campaign hours + merge/report).

## W2 — Verification-cost table  *(unblocks M7)*

- **Goal:** wall-clock cost of the methodology. Table: 3–4
  representative programs (e.g., vecadd, a divergence kernel, fpu_test,
  one large memory kernel) × three modes: (a) plain env (lockstep
  capture off), (b) lockstep on, (c) lockstep + two-pass feed armed.
  Plus: per-suite totals for the W1 campaign, and compile/elaboration
  time once.
- **Steps:** use `/usr/bin/time -v` (record wall + peak RSS), fixed
  seed per program, three repetitions each, report median. Same
  machine, same load conditions — note CPU model and load.
- **Definition of done:** markdown table with program, mode, wall-clock
  median, RSS; evidence-base entry.
- **Effort:** half a day (can share the W1 campaign for suite totals).

## W3 — Generator comparison evidence  *(unblocks M8)*

- **Part A (required):** marginal coverage per program kind on the SAME
  model — you already have: 90 riscv-dv programs → 0 bins (OBS-046),
  6 simtgen programs → 3 targets. Add: directed kernels' contribution
  (from frozen-bank data) and, after W1, per-kind bins/program on the
  new bank. Deliver as one table.
- **Part B (stretch):** X1–X3 repro attempts — FuzzGPU's three Vortex
  RTL bugs were filed at commit `2189194`; we run pin `7a52ee5` with 18
  local modifications (OBS-040). Fetch their PoCs from the upstream PRs
  (#356/#358/#359), try each at our pin under this environment; record
  reproduce / not-reproduce / not-applicable with one line of why.
  Do not over-claim either direction; pins differ and that is the
  disclosed reason.
- **Definition of done:** Part A table in evidence base; Part B short
  note appended to the FuzzGPU section of
  `PRESUBMISSION_DISCLOSURES.md` §7.
- **Effort:** Part A: 2–3 hours of analysis (mostly re-reading existing
  reports). Part B: 1–2 days if attempted.

## W5 — EXT_D-off confirmatory elaboration  *(cheap, closes M5 empirically)*

- **Goal:** empirically confirm the static scoping (papers already
  claim it from code inspection — this makes it bulletproof).
- **Steps:** rebuild the 1CL configuration with
  `+define+EXT_D_DISABLE` (see `hw/rtl/VX_config.vh:45`); elaborate;
  diff the covergroup bin count (377 expected unchanged) and run ONE
  short program to confirm no functional-bin change. Record `vsim`
  elaboration warnings diff if any.
- **Effort:** ~1 hour. **Definition of done:** one-paragraph note +
  numbers in evidence base.

## W6 — Cross-configuration re-bank  *(optional; restores comparability)*

- **Goal:** the 2CL and L2/L3 banks predate the R10 relay fix. Re-run
  both on the relay-fixed design so cross-configuration comparisons
  become valid (or keep the current disclosure — journal can live with
  it if stated; this item removes the need to).
- **Effort:** 1–2 days wall-clock. Only if time permits before the
  journal draft freeze.

## W7 — Bug-discovery curve  *(NO QuestaSim needed — can start today)*

- **Goal:** a figure: cumulative findings (OBS-001…061 / R1–R10) over
  project time, annotated with methodology milestones (lockstep on,
  feed armed, simtgen, waiver gate). Source data:
  `docs/COMMIT_HISTORY.md` + OBS entry dates. This is git/doc
  archaeology — any co-author can do it without the lab machine.
- **Definition of done:** dated CSV + plot (matplotlib fine) + one
  paragraph reading; goes into the journal draft as a new figure.
- **Effort:** half a day.

---

## Recommended order and total effort

```
W7 (anytime, no sim) ─┐
W0 (1–2 h) ──► W4 (3–5 d) ──► W1 (1–2 d) ──► W2 (0.5 d) ──► W3-A (2–3 h)
                                   │
                                   └─► W5 (1 h, anytime after bring-up)
W6 (optional, last)          W3-B (stretch)
```

Realistic total: **~2 working weeks** for a co-author already familiar
with the flow (W0–W5), plus W6/W3-B optional.

## What NOT to do

- Do not re-run anything "to see if numbers improve" without a defined
  item above — every run needs a purpose and a provenance entry.
- Do not delete or move frozen bank directories or their transcripts.
- Do not update the conference/arXiv papers from the lab machine — send
  new numbers to the corresponding author; the papers carry
  provenance-checked wording that must not drift.
- Do not waive a newly-unhit bin to make a total look better — that is
  exactly what the gate and the paper's thesis exist to prevent.
