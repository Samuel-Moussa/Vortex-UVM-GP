# W7 — Bug-discovery curve (JSA_MACHINE_WORK_PACKAGE.md)

**Method.** No QuestaSim needed — pure git/doc archaeology, as the work package specifies.
For each `OBS-NNN` entry currently in `docs/RTL_OBSERVATIONS.md`, walked the file's full
commit history (`git log --follow -p`, oldest-first) and recorded the timestamp of the
**earliest** commit whose diff adds that entry's `##`/`### OBS-NNN` header line — i.e. the
date the finding was actually logged, not today's date. 61 of the register's entries
resolved to a real add-date this way (`docs/paper/figures/bug_discovery_curve.csv`).

**One gap, disclosed rather than guessed:** `OBS-048` is referenced exactly once in the
register, as `"(OBS-048-adjacent)"` inside the text of OBS-047 — it was never written as its
own numbered entry. The number was evidently reserved and the finding folded elsewhere (or
never independently filed); the CSV correctly has no row for it rather than fabricating one.
This means 61 dated entries, not "OBS-001..062 = 62" — state the true denominator in the
journal draft, the same discipline as the FW-1b run-count rule.

**R1/R2/R3/R10 (README's findings table) are relabelings of existing OBS entries, not
separate findings with their own dates** — R1=OBS-012 (JALR), R2=OBS-011 (STALL_TIMEOUT),
R3=OBS-013 (misaligned access), R10=OBS-045 (reset-relay X-window). They are not double-
counted in the curve.

**Methodology milestones** (also real commit dates, resolved the same way, from the outer
repo's pre-submodule-move history where the relevant files originally lived):

| Milestone | Date |
| :--- | :--- |
| Lockstep on (Phase A0, per-instruction RVVI-style lockstep) | 2026-07-14 |
| Two-pass load-feed armed (`LOCKSTEP_LOADFEED` introduced) | 2026-07-16 |
| Blocking hits-invariant waiver gate added to the coverage merge | 2026-08-16 |
| `simtgen` (original SIMT-aware random generator) | 2026-09-07 |

**Reading.** The curve is not smooth — it steps in bursts that track methodology
investment, not calendar time. The two largest bursts (mid-July, ~6→13 and ~14→24; early
August, ~24→38) immediately follow lockstep/load-feed coming online and the run-up to the
hits-invariant gate, consistent with each new checking layer surfacing findings the prior
layer could not see (a firing checker is evidence to investigate, not proof of a DUT bug —
the same lesson recorded for OBS-060/B1 elsewhere in this register). The curve is *not*
flattening as of `simtgen`'s introduction (2026-09-07) or afterward (OBS-057, OBS-062) —
findings are still arriving from the newest stimulus/tooling additions, which argues against
reading the current total as close to the discovery ceiling. This figure is descriptive of
*where in the project's tooling investment* findings were logged, not a claim about DUT
defect density or convergence.

**Deliverable:** `bug_discovery_curve.csv` (dated, machine-readable) +
`bug_discovery_curve.png` (the figure) in this directory.
