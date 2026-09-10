# JSA Machine-Work Package — Results Index

Status against `docs/paper/JSA_MACHINE_WORK_PACKAGE.md`, in the mandated execution order
**W0 → W4 → W1 → W2 → W3 → W5 → W6 → W7**. Every link below is a GitHub permalink pinned to
the exact commit that produced it (not a branch link — it will not move under you).

Outer repo: `Samuel-Moussa/Vortex-UVM-GP` @ [`9ed91ce`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/9ed91ce)
Vortex (RTL/TB submodule): `Samuel-Moussa/vortex-uvm-gp-rtl` @ [`1c72d523c`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/commit/1c72d523c)

**Raw tool output, not just write-ups:** every item below with a run behind it now has a
"Raw tool output" line pointing into
[`docs/paper/evidence/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence)
— QuestaSim's own `SUMMARY.txt` / `simulation.log` / `vcover report` text, copied unedited
from `vortex_uvm_env/results/` and `vortex_uvm_env/cov/` (both normally gitignored — too
large to track wholesale). See that folder's own `README.md` for what is and is not
included in full (a few very large lockstep logs are excerpted, disclosed there).

| Order | Item | Status | Evidence |
| :---: | :--- | :---: | :--- |
| 1 | **W0** — md5 duplicate guard | ✅ done | see below |
| 2 | **W4** — simtgen barrier + vote_shfl axes | ✅ done | see below |
| 3 | **W1** — fold-in re-run | ✅ decided (disclose as-is) | see below |
| 4 | **W2** — verification-cost table | ✅ done | see below |
| 5 | **W3** — generator comparison | ✅ W3-A + W3-B done | see below |
| 6 | **W5** — EXT_D-off confirmatory elaboration | ✅ done | see below |
| 7 | **W6** — cross-configuration re-bank | ✅ done | see below |
| 8 | **W7** — bug-discovery curve | ✅ done | see below |

---

## W0 — md5 duplicate guard

- Code: [`run_suite.sh` — the guard itself](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/commit/d00c565d3) (Vortex submodule commit `d00c565d3`)
- Write-up + validation evidence (real Questa runs, positive + negative control): [`PAPER_BASE_EVALUATION.md` §W0](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L923-L952)
- Commit that landed the write-up: [`2be2419`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/2be2419)
- **Raw tool output** — real `SUMMARY.txt` / `simulation.log` / `riscv_dv_seed.txt` (with the
  actual `program_md5` values) for each of the 3 validation runs:
  [`pmp`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W0_duplicate_guard/pmp),
  [`non_compressed`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W0_duplicate_guard/non_compressed)
  (md5 matches `pmp` — the FW-1b duplicate),
  [`arithmetic_basic`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W0_duplicate_guard/arithmetic_basic)
  (md5 differs — no false positive)

## W4 — simtgen barrier + vote_shfl axis generators

- Code: [`gen_barrier.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/gen_barrier.py), [`gen_vote_shfl.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/gen_vote_shfl.py), [`knobs.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/knobs.py), [`simtgen.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/simtgen.py) — commit [`1c72d523c`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/commit/1c72d523c)
- **Key finding + proposed paper correction**: [`PAPER_BASE_EVALUATION.md` §W4](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L979-L1041)
- Commit that landed the write-up: [`f06529e`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/f06529e)
- Paper lines that need the correction (not edited by this campaign — corresponding-author call):
  [`isqed27_vortex_uvm.tex:588`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/isqed27_vortex_uvm.tex#L588),
  [`arxiv_vortex_uvm_2026.tex:834`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/arxiv_vortex_uvm_2026.tex#L834)
- **Raw tool output** — the threshold-bug first run (`<bar,partial[3]>` never actually hit,
  the bug this session caught before banking anything) vs. the fixed re-run:
  [`first_run_threshold_bug/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W4_simtgen_barrier_vote_shfl/first_run_threshold_bug),
  [`fixed_rerun/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W4_simtgen_barrier_vote_shfl/fixed_rerun)
  (SUMMARY.txt + full simulation.log per kernel), and the isolated-merge bank's real `vcover
  report` text: [`coverage_report_summary.txt`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/W4_simtgen_barrier_vote_shfl/coverage_report_summary.txt),
  [`coverage_report_functional.txt`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/W4_simtgen_barrier_vote_shfl/coverage_report_functional.txt)

## W1 — fold-in re-run decision

- Decision + final bank-provenance table (divergence/memory in-bank, barrier/vote_shfl isolated-merge, no full re-run): [`PAPER_BASE_EVALUATION.md` §W1](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L1042-L1068)
- Commit: [`9ed91ce`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/9ed91ce)

## W2 — verification-cost table

- Write-up (2 programs × 3 lockstep modes × 2 reps; scope reduced from the runbook's suggested
  3-4 programs, disclosed): [`PAPER_BASE_EVALUATION.md` §W2](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ea8ca1d/docs/PAPER_BASE_EVALUATION.md#L1070-L1128)
- Commit: [`2595ba7`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/2595ba7)
- **Raw tool output** — all 12 real `/usr/bin/time -v` files (the actual wall-clock/RSS
  numbers in the table) plus the matching Questa simulation logs (full for `vecadd_lite` and
  `wide_stress plain`; tail excerpt of the tool's own final Results block for the two ~37MB
  `wide_stress` lockstep logs — see the folder's `README.md`):
  [`W2_verification_cost/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W2_verification_cost)

## W3 — generator comparison evidence

- **Part A (done)**: marginal coverage per program kind — [`PAPER_BASE_EVALUATION.md` §W3-A](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L953-L978)
- Commit: [`acd9107`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/acd9107)
- **Part B (done)**: FuzzGPU PoC repro at our pin — [`PAPER_BASE_EVALUATION.md` §W3-B](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/4672e5f/docs/PAPER_BASE_EVALUATION.md#L979-L1018)
  · X1 and X2 **reproduced with real Questa runs** (X2 also corrects the paper's "3 Vortex RTL
  bugs" framing — it is a golden-model/SimX bug, not RTL); X3 static-only (engineering cost)
  · full findings: [`RTL_OBSERVATIONS.md` OBS-063](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/4672e5f/docs/RTL_OBSERVATIONS.md#L3522-L3594) / [OBS-064](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/4672e5f/docs/RTL_OBSERVATIONS.md#L3597-L3663)
  · repro kernel: [`fuzzgpu_repro/main.cpp`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/fcb6fed17/tests/kernel/fuzzgpu_repro/main.cpp)
  · Commit: [`4672e5f`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/4672e5f)
  · **Raw tool output** — the real run that fired both X1's RTL assertion and X2's
    DUT-vs-SimX memory mismatch: [`W3B_fuzzgpu_repro/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/ecf62c0/docs/paper/evidence/W3B_fuzzgpu_repro)
    (`SUMMARY.txt`, `config.txt`, full `simulation.log` — search it for
    `invalid writeback register` (X1) and `MEM MISMATCH` (X2))

## W5 — EXT_D-off confirmatory elaboration

- Write-up (includes the correction to the runbook's own `+define+EXT_D_DISABLE` instruction, which does not exist as a real control): [`PAPER_BASE_EVALUATION.md` §W5](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L886-L910)
- The real mechanism this scoped: [`vortex_rtl.flist:22`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/flists/vortex_rtl.flist#L22)
- Commit: [`dd8fa91`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/dd8fa91)

## W6 — cross-configuration re-bank (relay-fixed design)

- Write-up + coverage table (2CL, 110 runs, 0 failures, 93.39% cg bins / 94.29% total): [`PAPER_BASE_EVALUATION.md` §W6](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L848-L885)
- Commit: [`dd8fa91`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/dd8fa91)
- **Raw tool output** — the bank's real `vcover report` text (the actual source of every
  number in the table above): [`coverage_report_summary.txt`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/W6_2CL_relayfix_rebank/coverage_report_summary.txt),
  [`coverage_report_functional.txt`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ecf62c0/docs/paper/evidence/W6_2CL_relayfix_rebank/coverage_report_functional.txt)
- The raw UCDB binary itself (`vortex_uvm_env/cov/bank_2CL_2C_4W_4T_relayfix_20260910/merged.ucdb`)
  is machine-local, per the repo's standing coverage-binary policy — the text reports above are
  Questa's own export of that same UCDB, not a re-derivation.

## W7 — bug-discovery curve

- Figure + data + reading: [`bug_discovery_curve.png`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/figures/bug_discovery_curve.png), [`bug_discovery_curve.csv`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/figures/bug_discovery_curve.csv), [`bug_discovery_curve.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/figures/bug_discovery_curve.md)
- Commit: [`e0a68c8`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/e0a68c8)

---

## Source documents

- The work package itself: [`JSA_MACHINE_WORK_PACKAGE.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/JSA_MACHINE_WORK_PACKAGE.md)
- Full evidence log (all sections above live inside this one file): [`PAPER_BASE_EVALUATION.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md)
- Honesty/provenance rules every number above follows: [`PRESUBMISSION_DISCLOSURES.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/PRESUBMISSION_DISCLOSURES.md)
