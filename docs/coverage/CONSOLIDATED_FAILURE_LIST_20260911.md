# Consolidated failure list — every run with UVM_ERROR/UVM_FATAL, 2026-09-11

Scope: all 779 `simulation.log` files under `vortex_uvm_env/results/` (every run ever
performed in this project, across all sessions). Method: grepped each for the final
`UVM_ERROR :`/`UVM_FATAL :` counts; any non-zero count was pulled and its cause
classified by reading the actual `UVM_ERROR` message text and cross-checking against
existing docs — no run was reclassified without a source citation.

**Result: 20 of 779 runs show a non-zero error count. All 20 are already accounted for
by prior documented work — deliberate fault-injection proofs, known/fixed generator or
kernel-development bugs (all superseded by a later passing re-run), or kernels that were
never part of the verified suite in the first place. Zero unexplained/unclassified
failures found.**

| Runs | Program | ERR | Class | Disposition |
|---|---|---|---|---|
| `20260902/run_222128` | `vecadd_lite` (`+LOCKSTEP_INJECT`) | 2 | **Deliberate fault injection** — proves the per-instruction lockstep checker is non-vacuous (Gate-0 class, same purpose as `negative_result_test`/`negative_dropped_store_test`). `DATA mismatch ... DUT=5 vs SimX=4` at the injected PC. | Expected RED. Not a defect. |
| `20260907/run_155829,155852,155914,155939,160003,160027` (6) | `simtgen_mem_s{100,101,104,109,112,116}` | 9 each | **Pre-fix baseline of our own stimulus generator's address-math bug** — `gen_memory.py`'s `base = wid*nt` overlapped adjacent warps' LMEM slot windows (cross-warp aliasing, not an RTL defect). Root-caused and fixed (`base = wid*nt*nt`) same day — see [`RTL_OBSERVATIONS.md` OBS-060](../RTL_OBSERVATIONS.md) ("An earlier version of this generator additionally had a cross-WARP address-aliasing bug ... caught by 6/6 real scoreboard MEM MISMATCHes"). All 6 programs PASS byte-exact post-fix (`cov/simtgen_mem_probefix_20260907/`). | Fixed, superseded. Not a current defect. |
| `20260905/run_103435` | `isacov_fill` | 2 | **Vacuous-run guard (T4 honest gate) firing correctly** on an early development iteration that ran with lockstep disabled — `"no functional verification performed (no memory or console comparison, and lockstep is disabled)"`. | Gate working as designed. Not a defect. |
| `20260905/run_103803, 104127` | `isacov_fill` | 17 each | **Pre-fix `isacov_fill` kernel-development bug** — the first version fed `bge` per-lane-differing operands, a genuine hand-assembled-branch SIMT-divergence pitfall (no compiler-inserted reconvergence), caught immediately as a `DUT-ORPHAN` cascade from the branch PC. See `RTL_OBSERVATIONS.md` (isacov_fill section): fixed by making the `bge` comparison operand warp-uniform; kernel then verified byte-exact vs SimX with `LOCKSTEP=1`, 0 errors. | Fixed, superseded. Not a defect. |
| `20260901/run_221210, 221349` | `fft_par16` | 46 each | **Stale-ELF / `.kernel_config.stamp` config-drift artifact** — documented root cause in `docs/riscvisacov/RISCVISACOV_REEVALUATION.md` ("this project has already been burned by exactly that failure mode (`fft_par16`, 2026-09-01, the `.kernel_config.stamp` gap)"). `fft_par`/`fft_par16` is an FFT proof-of-concept **deliberately run outside the coverage bank** (`docs/appendices/APPENDIX_PROGRAM_INVENTORY_FOR_PPT.md`: "run outside the bank"), never part of the verified suite. | Known config-drift artifact on a non-suite PoC kernel. Not a current defect. |
| `20260831/run_192339,193652,193956,194624,194825` (5) | `fft_par` | 35–39 | Same PoC family as above — `fft_par`/`fft_par16`, explicitly documented as run outside the bank. | Non-suite PoC kernel. Not a current defect. |
| `20260910/run_193916, 193936` | `fpu_test` (`LOCKSTEP=1`, no `LOCKSTEP_LOADFEED`) | 3 each | **OBS-014, the documented pre-existing 1-ULP `fsqrt.s` residual** — exact signature match: `LOAD-DATA mismatch ... DUT=3fef7750 vs SimX=...3fef7751`, off by 1 in the low mantissa bit. `CLAUDE.md`: *"Running fpu_test with only LOCKSTEP=1 shows 2 legitimate OBS-014 1-ULP sqrt mismatches ... that is the documented residual, not a regression."* | Known, non-regression, disclosed residual. Not a new defect. |
| `20260910/run_181718` | `fuzzgpu_repro` | 4 | **OBS-064** — SimX golden-model decode bug (not RTL) on a reserved-`funct7` encoding; `MEM MISMATCH ... DUT=0x...08 SimX=0x...0f` (DUT correctly falls through the ALU default; SimX misdecodes as RV32M). Deliberately **not** added to `run_suite.sh` — see `RTL_OBSERVATIONS.md` OBS-064: "it is not meant to pass, and folding it into the regression suite would report a real DUT correctness finding as a suite failure." | Deliberate, documented, non-suite repro kernel. Not an RTL defect. |

## Bottom line

- **0 unexplained failures** across the entire run history.
- **0 of the 20 failing runs are in any banked coverage config** (`bank_*` directories) —
  every bank on disk was produced only from staged, passing runs via
  `merge_coverage.sh`'s `--collect`/`--fresh` staging discipline, so none of these 20
  polluted any reported coverage number.
- Gate-0's `negative_result_test`/`negative_dropped_store_test` runs (6 found under
  `results/`, all `ERR=0` in the final tally) were also checked directly: their expected
  injected error is caught and *demoted* by the UVM expected-error mechanism
  (`Number of demoted UVM_ERROR reports : 2`, final `UVM_ERROR : 0`), which is why they
  don't appear in the table above — the demotion count matching the injection count **is**
  the pass criterion for these tests, per `CLAUDE.md` Gate-0. They remain the standing
  regression guard and must stay RED-on-injection after every change, per that same rule.
- Combined with the table above, **every failure and every deliberate-failure proof in
  this project's entire run history is accounted for.** No open, unexplained defect
  exists in the log corpus as of this scan.
