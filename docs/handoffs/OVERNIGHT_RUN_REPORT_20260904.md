# Overnight run report — 2026-09-04, for morning review

**Read this before quoting any number from tonight's four new banks.** One is real and
useful, three are compromised by a mistake I made in the pipeline script. Nothing was
fixed or re-run without your input — this is a status report, not a resolution.

---

## What actually happened

Ran unattended per your instructions: (1) finish the in-flight 1CL+ISACOV suite,
(2) add `coalesce_probe`+`csr_probe` to `run_suite.sh` permanently and get a with/without
comparison via merge rather than a second full suite run, (3) same treatment for 2CL.
All four stages completed. `run_suite.sh` now permanently includes both new kernels —
that part is correct and durable regardless of everything below.

**No suite process crashed. No unexpected test failures appeared.** Both 1CL and 2CL
suites showed exactly the same 4 failures each — `basic`/`diverge`/`dogfood`/`sgemm`,
the pre-existing OBS-052 build-infra gap (missing `Vortex/runtime/libvortex.a`),
identical at both configs, nothing new. Everything else passed, including
`coalesce_probe` and `csr_probe` running at 2CL for the first time.

## The mistake — L1/riscvISACOV data from tonight is not valid

`isacov_pkg::isacov_en` (`vx_instr_word_probe.sv:35`) is armed by a **runtime** plusarg —
`$test$plusargs("ISACOV")` — which is completely separate from the `ISACOV=1`
**compile-time** env var that controls whether the riscvISACOV covergroups get built into
the design at all. My overnight script set the compile-time flag (correctly — all 80
covergroups elaborated in every bank) but never passed `EXTRA_PLUSARGS="+ISACOV"` to any
of the runtime invocations — not in the suite launches, not in the two manual
`coalesce_probe`/`csr_probe` re-runs. Confirmed directly: grepping every log from
tonight for `+ISACOV` finds only the compile-time `+define+ISACOV` string, never the
runtime plusarg.

**Consequence: `RISCV_coverage_pkg` (all 80 L1 covergroups, 6,469 bins) reads exactly
0/6,469 in all four of tonight's banks.** Not low — genuinely zero, because sampling was
never armed. This is uniform across every bank, which is itself the tell (a real
under-covered result would never plot at exactly 0.00%.)

**What is NOT affected:** everything else. Our own L2 probes sample unconditionally
(no ISACOV gate at all), so Branches/Conditions/Statements/Toggles/Assertions/Directives
and our own covergroups (`cp_coalesce_kind`, `cp_vote_shfl_op`, etc.) in all four banks
are genuinely real — verified directly, e.g. `coalesce_probe`'s standalone UCDB shows
`cp_coalesce_kind` at 100% (3/3), which is L2, not L1, and unaffected by the plusarg gap.

**What is NOT affected, separately: last night's pre-sleep L1 numbers stand.** Those
manual runs (the ones behind the "919/6,469 = 14.20%" figure I gave you before you went
to sleep) correctly included `+ISACOV +ISACOV_MAP=... +ISACOV_MODE=A` — verified by
re-checking their logs just now. That result is unaffected by tonight's mistake.

---

## What IS usable from tonight, with the L1 caveat understood

L2-only raw covergroup bins (subtracting the fixed, uniformly-zero 6,469 L1 bins out of
each blended total):

| bank | L2 covergroup bins | vs. reference |
|---|---|---|
| 1CL, without coalesce_probe/csr_probe | 425/436 = 97.48% | matches yesterday's correctly-banked 94.62% result (425/436=97.47%) almost exactly — good consistency check |
| 1CL, with coalesce_probe/csr_probe | 425/436 = 97.48% | **identical** — see below |
| 2CL, with coalesce_probe/csr_probe (first-ever 2CL run of the extended collector) | 1203/1268 = 94.88% | new data, no prior 2CL comparison exists at this collector state |
| 2CL, without coalesce_probe/csr_probe | (see OBS-054 caveat below) | |

**coalesce_probe/csr_probe added ZERO new L2 bins in the full-suite context**, at both
configs. Verified this isn't a broken-kernel artifact: both kernels individually show
real, correct coverage in isolation (`coalesce_probe` 100% on `cp_coalesce_kind`;
`csr_probe` genuine nonzero Zicsr activity). The honest read: the other 47-49 suite
programs (particularly the riscv-dv random-instruction tests) already exercise
everything these two specifically target. That's a legitimate finding, not a failure —
it just means these two kernels' real value is in isolated/targeted verification (which
they already demonstrated last night) rather than moving the full-suite number.

## A separate, real defect found along the way: OBS-054

Both 2CL merges (the official "with" bank done by `run_suite.sh` itself, and my derived
"without" bank) hit `vcover-6854`: two pairs of same-named test records
(`vecadd_lite` plain vs. throttled, `mem_stress` plain vs. flooded) collide during merge
and Questa silently keeps one, discards the other. Root cause: `runthr`/`runflood`
reuse the base program's `PROGRAM_NAME`, so `simulate.sh`'s internal UCDB test-record
naming (`${TEST_NAME}_${PROG_SHORT}`) is identical for both variants. **Confirmed this
is not new to tonight** — it's inherent to how those two suite functions have always
worked. Full detail: `docs/RTL_OBSERVATIONS.md` OBS-054.

**Open question, not checked:** whether the frozen 2CL defence bank (94.55%) has the
same collision baked in — no preserved merge log exists for that bank to check without
re-touching it, which I didn't do.

---

## What I did NOT do

- Did not restart the 2CL suite or attempt to fix the plusarg mistake myself — that's a
  ~2.5h (1CL) to ~8.75h (2CL, observed tonight) re-run decision, and per your
  instruction on errors, this is exactly the kind of thing to hold for your review
  rather than act on unilaterally overnight.
- Did not touch `simulate.sh`'s `stage_name` logic (the OBS-054 fix candidate) — shared
  script, needs a plan and your confirmation first.
- Did not touch either frozen defence bank (1CL 94.72%, 2CL 94.55%) — both re-verified
  unchanged at the end of the pipeline log.

## Recommended next step

If you want real suite-scale L1/riscvISACOV numbers, the fix is one line —
`EXTRA_PLUSARGS="+ISACOV"` added to the same env-var invocation pattern already used
tonight — and then a re-run. Given the 2CL run alone took 8h45m, that's worth deciding
deliberately rather than me just relaunching it. Say go and I'll queue it exactly the
same way, with the fix applied.
