# Handover — 1CL coverage suite re-run (post G-0/G-1/riscvISACOV)

**Written while the run is still in progress, so the next session (or you, later
today) can pick this up without re-deriving context.** Do not act on any coverage
number until the run banks — this file tells you how to tell the difference.

---

## 1. What is running right now

`scripts/run_suite.sh`, 1CL/1C/4W/4T config, launched from
`Vortex/sim/uvmsim`, **background PID 20417**, started ~16:19, still alive as of
this writing (~1h46m elapsed). It is the standard ~45-program 1CL regression suite,
**unmodified** — `coalesce_probe` and `csr_probe` are NOT in it (that's step 2 below).
Its purpose is to isolate what today's collector changes (G-0, G-1, riscvISACOV)
reveal against *existing* stimulus, before any new stimulus is added.

Check it's still alive:
```
kill -0 20417 && echo running || echo finished
```
Check progress without disturbing it:
```
ls /home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/results/run_suite_logs | wc -l   # programs logged so far
ls /home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/cov/staging | wc -l               # UCDBs staged
```
Last known-good snapshot: 30 programs logged, 29 PASSED, 0 FAILED, 177 UCDBs staged,
1 in flight (`cache_tier` — this is a known long-running program, part of the
L2/L3 sweep territory; not a hang).

**A completion watcher is armed** (background shell polling `kill -0 20417`) and
will surface a notification with the merged total the moment `run_suite.sh` exits.
If that notification was somehow missed (a prior watcher died silently once already
this session when the harness session itself restarted — the suite process survived
under `nohup` regardless), re-arm it or just check manually per §2.

---

## 2. The moment it finishes — do this, in order

1. **Confirm it actually finished clean**, don't trust silence:
   ```
   grep -c "TEST PASSED" /home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/results/run_suite_logs/*.log | grep -c ":1$"
   ```
   compare against total programs logged. Any FAILED needs root-causing before the
   bank is trusted — do not bank a suite with unexplained failures.

2. **Read the merged total** (do not re-run anything):
   ```
   vcover report -summary /home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/cov/merged.ucdb \
     | grep -E "Total coverage|Covergroup Bins|Instances"
   ```

3. **Bank it immediately**, before touching anything else — `run_suite.sh` merges
   into `cov/merged.ucdb` on every invocation, so an unbanked result is destroyed by
   the next run:
   ```
   cd /home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/cov
   mkdir bank_1CL_1C_4W_4T_postG0G1_20260903
   cp -a merged.ucdb merged_raw.ucdb report staging bank_1CL_1C_4W_4T_postG0G1_20260903/
   vcover report -summary bank_1CL_1C_4W_4T_postG0G1_20260903/merged.ucdb | grep "Total coverage"   # verify the copy reads back identically
   ```

4. **Sanity-check the frozen defence bank is still untouched** (it should be — it
   lives in a separate directory `bank_1CL_1C_4W_4T/`, `run_suite` never writes
   there — but confirm rather than assume):
   ```
   vcover report -summary /home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/cov/bank_1CL_1C_4W_4T/merged.ucdb | grep "Total coverage"
   ```
   Expected: unchanged from before this session (94.72%). A verified backup also
   exists at `bank_1CL_1C_4W_4T_DEFENCE_FROZEN_20260903/` if anything looks wrong.

5. **Compare against the frozen bank, honestly**, and expect the total to be
   *lower*, not higher — that is the correct outcome, not a regression. Two reasons,
   both already documented in `docs/VERIFICATION_PLAN_v2.md`:
   - the covergroup denominator grew (~59 new bins) with no new stimulus yet for
     most of them (`coalesce_probe`/`csr_probe` aren't in this suite),
   - `cp_alu_op` lost a false-positive: it used to read 100% because an
     `INST_ALU_CZNE`/`INST_BR_EBREAK` encoding collision let `ebreak` score a Zicond
     bin it never should have. That inflation is gone.

   Report the new total as "more honest, not worse" — the write-up in
   `docs/PPT_HANDOFF_REPORT_20260903.md` is deliberately headline-only (no
   percentages) for exactly this reason: the percentage needs this context attached,
   or it reads as a regression to someone skimming a slide.

---

## 3. What's queued after this bank lands (do not start early — one Questa work
library, concurrent runs corrupt each other)

1. **Add `coalesce_probe` and `csr_probe` to `run_suite.sh`**, re-run 1CL. This
   recovers stimulus for the G-0/G-1 coverpoints this first run won't fill
   (`cp_coalesce_kind`'s partial/scatter bins, the six Zicsr covergroups). Bank
   as `bank_1CL_1C_4W_4T_postG0G1_withstim_20260903` or similar.
2. **2CL (2-cluster) re-run**, same collector — the pass that actually stresses
   cross-cluster/cross-core behaviour (G-10). This is the one the user asked for
   alongside 1CL.
3. Only after both land: update `docs/PPT_HANDOFF_REPORT_20260903.md` with the real
   percentages, and decide whether `docs/VERIFICATION_PLAN_v2.md`'s G-2..G-10
   backlog gets picked up next or the session moves to writing up results.

---

## 4. Traps already hit this session — don't re-hit them

- **`run_suite.sh` reads `VORTEX_UVM_RESULTS_DIR`/`VORTEX_UVM_COV_DIR` from its own
  shell environment, but `local.mk` only `export`s them into `make`'s recipe
  environment.** The first launch attempt today silently ran every sim, then looked
  for the UCDB in the wrong directory and reported "NO UCDB (failed/aborted,
  skipped)" on all of them — looked exactly like total suite failure, was actually a
  path bug. Fix: pass both variables explicitly on the invocation, as this run does:
  ```
  env VORTEX_UVM_COV_DIR=.../vortex_uvm_env/cov VORTEX_UVM_RESULTS_DIR=.../vortex_uvm_env/results \
    CLUSTERS=1 CORES=1 WARPS=4 THREADS=4 bash scripts/run_suite.sh
  ```
  Worth a real fix in `run_suite.sh` (source `local.mk`, or read the vars via `make
  -p`) — filed as a to-do, not yet fixed, since editing the suite script mid-run
  was off the table today.
- **Never run two suites, or a suite plus an ad-hoc `make sim`, concurrently** — one
  shared Questa work library.
- **Never touch `run_suite.sh`, `merge_coverage.sh`, or `gen_coverage_exclude.sh`
  while a suite is running.**

---

## 5. Reference

- Coverage-model changes this session: `docs/RTL_OBSERVATIONS.md` OBS-049 addendum,
  OBS-050, OBS-051.
- Gap tracking: `docs/VERIFICATION_PLAN_v2.md` §4 (G-0, G-1 now marked CLOSED).
- PPT-drafting handoff (headline counts, no percentages — send to claude.ai):
  `docs/PPT_HANDOFF_REPORT_20260903.md`.
- Frozen defence banks, untouched: `vortex_uvm_env/cov/bank_1CL_1C_4W_4T/`,
  `bank_2CL_2C_4W_4T/`, and the L2/L3 bank. Verified backup of the 1CL one at
  `bank_1CL_1C_4W_4T_DEFENCE_FROZEN_20260903/`.
