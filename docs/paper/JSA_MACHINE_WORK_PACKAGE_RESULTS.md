# JSA Machine-Work Package — Results Index

Status against `docs/paper/JSA_MACHINE_WORK_PACKAGE.md`, in the mandated execution order
**W0 → W4 → W1 → W2 → W3 → W5 → W6 → W7**. Every link below is a GitHub permalink pinned to
the exact commit that produced it (not a branch link — it will not move under you).

Outer repo: `Samuel-Moussa/Vortex-UVM-GP` @ [`9ed91ce`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/9ed91ce)
Vortex (RTL/TB submodule): `Samuel-Moussa/vortex-uvm-gp-rtl` @ [`1c72d523c`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/commit/1c72d523c)

| Order | Item | Status | Evidence |
| :---: | :--- | :---: | :--- |
| 1 | **W0** — md5 duplicate guard | ✅ done | see below |
| 2 | **W4** — simtgen barrier + vote_shfl axes | ✅ done | see below |
| 3 | **W1** — fold-in re-run | ✅ decided (disclose as-is) | see below |
| 4 | **W2** — verification-cost table | ✅ done | see below |
| 5 | **W3** — generator comparison | ⚠️ W3-A done, W3-B not started | see below |
| 6 | **W5** — EXT_D-off confirmatory elaboration | ✅ done | see below |
| 7 | **W6** — cross-configuration re-bank | ✅ done | see below |
| 8 | **W7** — bug-discovery curve | ✅ done | see below |

---

## W0 — md5 duplicate guard

- Code: [`run_suite.sh` — the guard itself](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/commit/d00c565d3) (Vortex submodule commit `d00c565d3`)
- Write-up + validation evidence (real Questa runs, positive + negative control): [`PAPER_BASE_EVALUATION.md` §W0](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L923-L952)
- Commit that landed the write-up: [`2be2419`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/2be2419)

## W4 — simtgen barrier + vote_shfl axis generators

- Code: [`gen_barrier.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/gen_barrier.py), [`gen_vote_shfl.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/gen_vote_shfl.py), [`knobs.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/knobs.py), [`simtgen.py`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/scripts/simtgen/simtgen.py) — commit [`1c72d523c`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/commit/1c72d523c)
- **Key finding + proposed paper correction**: [`PAPER_BASE_EVALUATION.md` §W4](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L979-L1041)
- Commit that landed the write-up: [`f06529e`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/f06529e)
- Paper lines that need the correction (not edited by this campaign — corresponding-author call):
  [`isqed27_vortex_uvm.tex:588`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/isqed27_vortex_uvm.tex#L588),
  [`arxiv_vortex_uvm_2026.tex:834`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/arxiv_vortex_uvm_2026.tex#L834)

## W1 — fold-in re-run decision

- Decision + final bank-provenance table (divergence/memory in-bank, barrier/vote_shfl isolated-merge, no full re-run): [`PAPER_BASE_EVALUATION.md` §W1](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L1042-L1068)
- Commit: [`9ed91ce`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/9ed91ce)

## W2 — verification-cost table

- Write-up (2 programs × 3 lockstep modes × 2 reps; scope reduced from the runbook's suggested
  3-4 programs, disclosed): [`PAPER_BASE_EVALUATION.md` §W2](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/ea8ca1d/docs/PAPER_BASE_EVALUATION.md#L1070-L1128)
- Commit: [`2595ba7`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/2595ba7)

## W3 — generator comparison evidence

- **Part A (done)**: marginal coverage per program kind — [`PAPER_BASE_EVALUATION.md` §W3-A](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L953-L978)
- Commit: [`acd9107`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/acd9107)
- **Part B (not started)**: FuzzGPU PoC repro at our pin — 1–2 day stretch item, not attempted this pass.

## W5 — EXT_D-off confirmatory elaboration

- Write-up (includes the correction to the runbook's own `+define+EXT_D_DISABLE` instruction, which does not exist as a real control): [`PAPER_BASE_EVALUATION.md` §W5](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L886-L910)
- The real mechanism this scoped: [`vortex_rtl.flist:22`](https://github.com/Samuel-Moussa/vortex-uvm-gp-rtl/blob/1c72d523c/sim/uvmsim/flists/vortex_rtl.flist#L22)
- Commit: [`dd8fa91`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/dd8fa91)

## W6 — cross-configuration re-bank (relay-fixed design)

- Write-up + coverage table (2CL, 110 runs, 0 failures, 93.39% cg bins / 94.29% total): [`PAPER_BASE_EVALUATION.md` §W6](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md#L848-L885)
- Commit: [`dd8fa91`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/dd8fa91)
- Coverage bank itself (`vortex_uvm_env/cov/bank_2CL_2C_4W_4T_relayfix_20260910/`) is machine-local (large UCDB binaries, per repo convention) — not on GitHub; the write-up above is the citable evidence.

## W7 — bug-discovery curve

- Figure + data + reading: [`bug_discovery_curve.png`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/figures/bug_discovery_curve.png), [`bug_discovery_curve.csv`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/figures/bug_discovery_curve.csv), [`bug_discovery_curve.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/figures/bug_discovery_curve.md)
- Commit: [`e0a68c8`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/commit/e0a68c8)

---

## Source documents

- The work package itself: [`JSA_MACHINE_WORK_PACKAGE.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/JSA_MACHINE_WORK_PACKAGE.md)
- Full evidence log (all sections above live inside this one file): [`PAPER_BASE_EVALUATION.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/PAPER_BASE_EVALUATION.md)
- Honesty/provenance rules every number above follows: [`PRESUBMISSION_DISCLOSURES.md`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/blob/9ed91ce/docs/paper/PRESUBMISSION_DISCLOSURES.md)
