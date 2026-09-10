# Raw tool evidence — index

This directory holds **QuestaSim's own generated output** for the JSA machine-work
campaign (`docs/paper/JSA_MACHINE_WORK_PACKAGE.md`), copied verbatim from
`vortex_uvm_env/results/` and `vortex_uvm_env/cov/` (both gitignored — too large to
track wholesale, 1.5G+ across the project's history) so the mentor has direct GitHub
links to the tool's actual output, not only the prose write-up in
`docs/PAPER_BASE_EVALUATION.md`. Every file here is either:
- a Questa `reports/SUMMARY.txt` / `config.txt` / `logs/simulation.log` from a real
  `make sim-only` run, copied unedited, or
- a real `vcover report` text export (`report/summary.txt`, `report/functional.txt`)
  from a merged coverage bank, or
- a real `/usr/bin/time -v` output file, or
- a `vcover report -details` invocation's own output, saved to a file.

Nothing in this directory was authored or reconstructed — it is the tool's own text,
copied. Where a file was too large to commit in full (see W2 below), the excerpt taken
is the tool's own trailing Results/Statistics block, not a summary I wrote.

Provenance for everything below: QuestaSim 2021.2_1, Vortex submodule HEAD
`af6bd9227e0e97df929f45c78eafc75a78f1c9b5` (except W0/W4/W2, run against the HEAD at
the time, see each write-up section in `PAPER_BASE_EVALUATION.md` for the exact SHA),
config 1CL/1C/4W/4T unless noted, all dated 2026-09-10 unless noted.

## Contents

| Folder | What it backs | Full tool output? |
| :--- | :--- | :--- |
| `W0_duplicate_guard/` | `PAPER_BASE_EVALUATION.md` §W0 — the 3 real `riscv_dv_seed.txt` MD5 values (pmp/non_compressed identical, arithmetic_basic different) | ✅ full |
| `W2_verification_cost/` | §W2 — all 12 `/usr/bin/time -v` files; `vecadd_lite` + `wide_stress plain` sim logs in full (228K–2.0M); `wide_stress lockstep`/`lockstep_feed` sim logs as a **tail excerpt** (full files are ~37MB each — see note in each `*_sim_tail.log`) | ⚠️ tail excerpt for 4 of 12 sim logs (the `/usr/bin/time` metrics, which are the actual W2 numbers, are always full) |
| `W3B_fuzzgpu_repro/` | §W3-B / OBS-063 / OBS-064 — the run that reproduced both X1 and X2 | ✅ full |
| `W4_simtgen_barrier_vote_shfl/` | §W4 — the buggy first run (threshold bug, `<bar,partial[3]>` never hit) and the fixed re-run, plus the isolated-merge coverage bank's real `vcover` text report | ✅ full |
| `G1_axi_stress_cp_write_tag/` | This session's `axi_stress` vs. `cp_write_tag` check — both the undersized-timeout failure and the correct-budget pass, plus a real `vcover report -details` bin-by-bin listing showing tag[4]–tag[7] still unhit | ✅ full |
| `W6_2CL_relayfix_rebank/` | §W6 — the 2CL cross-configuration re-bank's real `vcover` text report | ✅ full (report only — the underlying per-program run logs are the same suite as `run_suite_logs_2CL_relayfix_20260910`, not individually copied here; ask if a specific program's log is needed) |
| `1CL_bank_20260909_coverage_report/` | The primary 1CL bank (`bank_1CL_1C_4W_4T_L2_20260909`) backing most headline numbers in the write-up | ✅ full |

## What is NOT here, and why

- **W5 (EXT_D-off elaboration)**: the two elaboration runs were interactive `vsim -c`
  invocations whose console output was read directly, not redirected to a saved log
  file. The FLEN/EXT_D_ENABLED/XLEN values quoted in §W5 are real (re-derivable in under
  a minute by re-running the two elaboration commands cited there), but no raw transcript
  survives to link here. Disclosed rather than reconstructed after the fact.
- **Full `wide_stress` lockstep/lockstep_feed simulation logs** (4 files, ~37MB each) —
  the `_sim_tail.log` files here are genuine excerpts (the tool's own final
  Results/Statistics block via `tail -300`), not the complete per-cycle trace. The full
  files exist locally on the lab machine if needed.
- **Per-program run logs inside the W6 2CL suite** — the suite is dozens of programs;
  only the bank's aggregate `vcover` report is copied. The bank itself
  (`vortex_uvm_env/cov/bank_2CL_2C_4W_4T_relayfix_20260910/`) has the full merged UCDB,
  gitignored per the project's standing coverage-binary policy.
