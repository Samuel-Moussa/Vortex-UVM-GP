# Session Fixes — 2026-06-26

Per-issue documentation for all fixes made in this session. Each file covers one issue: root cause, exact file edits (before/after), acceptance check, and teammate conflict/handover notes.

## Index

| File | Issue | Commit | Teammate Impact |
|------|-------|--------|----------------|
| [fix_01_C1_mem_tag_width.md](fix_01_C1_mem_tag_width.md) | C1 + ISS-01: VX_MEM_TAG_WIDTH from RTL + hex load fix | 4c36bd82 | None |
| [fix_02_C3_ebreak_decode.md](fix_02_C3_ebreak_decode.md) | C3: Real EBREAK decode drives completion | 7764ba14 / 11f71359 | Ahmad (P1-bind area), Steven (AXI SVA area) |
| [fix_03_C2_real_instruction_count.md](fix_03_C2_real_instruction_count.md) | C2: Real retired instruction count via commit handshake | 22115864 / 11f71359 | Ahmad (P1-bind handover task) |
| [fix_04_T4_honest_error_gate.md](fix_04_T4_honest_error_gate.md) | T4: Remove -2 subtraction from simulate.sh | e087a78f | None |
| [fix_05_I1_multicore_probes.md](fix_05_I1_multicore_probes.md) | I1: Generate loops for all N cores/clusters | 11f71359 | Ahmad (P1-bind), Steven (AXI SVA merge) |
| [fix_06_riscv_dv_pipeline.md](fix_06_riscv_dv_pipeline.md) | riscv-dv pipeline: path fix, assemble step, STRESS_ITER | 4661f7cb | None |
| [fix_07_riscv_dv_simx_csr_sigabrt.md](fix_07_riscv_dv_simx_csr_sigabrt.md) | SimX SIGABRT on M-mode CSRs (VX_CSR_MISA + range guard) | 2ccef437 | **Steven** (emulator.cpp is his file) |
| [fix_08_riscv_dv_rvc_decode_crash.md](fix_08_riscv_dv_rvc_decode_crash.md) | SimX crash on RVC compressed instructions → rv32im target | 2ccef437 | Steven (SimX limitation awareness) |
| [fix_09_riscv_dv_rtl_csr_assertion.md](fix_09_riscv_dv_rtl_csr_assertion.md) | RTL assertion on csrw mstatus/misa → sed strip | 2ccef437 | Ahmad (T-exc impact) |
| [fix_10_riscv_dv_ecall_ebreak.md](fix_10_riscv_dv_ecall_ebreak.md) | ecall → ebreak substitution for TB completion detection | 2ccef437 | None |
| [fix_11_riscv_dv_uvm_stale_event.md](fix_11_riscv_dv_uvm_stale_event.md) | UVM stale event: wait_trigger() misses past triggers | 2ccef437 | Ahmad (derived tests inherit fix) |
| [fix_12_riscv_dv_vacuous_run.md](fix_12_riscv_dv_vacuous_run.md) | Vacuous run false UVM_ERROR in scoreboard | 2ccef437 | **Ahmad** (scoreboard.sv is his file) |
| [fix_13_I2_elaboration_asserts.md](fix_13_I2_elaboration_asserts.md) | I2: elaboration asserts for topology params (NUM_CLUSTERS/CORES/WARPS/THREADS) | 37cfce55 | None (awareness only for Ahmad + Steven) |
| [fix_14_I5_hygiene.md](fix_14_I5_hygiene.md) | I5: remove dead files + fix stale `// 8` tag-width comments | a42f164c | None |
| [fix_15_busy_low_sustained.md](fix_15_busy_low_sustained.md) | Issue 2: busy=0 completion now requires sustained de-assertion (not single cycle) | 19c3d558 | None |
| [fix_16_i2_alias_gap.md](fix_16_i2_alias_gap.md) | Issue 3: I2 assert now also checks CLUSTERS/CORES/WARPS/THREADS aliases | 19c3d558 | None |
| [fix_17_P1_commit_probe_bind.md](fix_17_P1_commit_probe_bind.md) | P1-bind: passive `vx_commit_probe` bound on `commit_arb_if[*]` + UUID assert + liveness proof (11498 retires) | (2026-06-28) | **Ahmad** (hangs covergroups off this probe) |
| [fix_18_fpu_test_and_fp_divergence.md](fix_18_fpu_test_and_fp_divergence.md) | Directed FPU kernel: fpu_cg 0%->25% + found DUT/SimX FP divergence (1-ULP rounding + denormal FTZ) | (2026-06-29) | **Ahmad** (scoreboard FP tolerance) + **Steven** (SimX FP config) |
| [INV1_kernel_completion_hang.md](INV1_kernel_completion_hang.md) | INV-1 investigation: hostless kernels hang in `wspawn`/TLS startup (not DCR args); root cause + solution A/B + RAL + regression assessment | (2026-06-28) | Steven (SimX/microarch — Path A divergence check) |
| [HANDOVER_Steven_kernel_execution.md](HANDOVER_Steven_kernel_execution.md) | **Steven start-here (merged):** Thread A INV-1 (`wspawn`/`vx_tmc` hang — repro/evidence/ruled-out/waveform+SimX asks) + Thread B Path B host-driven launch (half-built `host_*` seqs, SimX-mirroring, regression). Supersedes the two prior Steven handovers. | (2026-06-28) | **Steven** (owns kernel execution: INV-1 + Path B SimX half) |
| [HANDOVER_Ahmad_unused_axi_dcr_sequences.md](HANDOVER_Ahmad_unused_axi_dcr_sequences.md) | **Ahmad:** dead-sequence audit Bucket (c) — wire unused AXI/DCR stress+random seqs into a coverage test to fill empty `axi_transaction_cg`/`dcr_config_cg` bins | (2026-06-28) | **Ahmad** (coverage) |

## Review artifacts (Opus engineering pass, 2026-06-26)

| File | Purpose |
|------|---------|
| [EVALUATION_2026-06-26.md](EVALUATION_2026-06-26.md) | Per-fix logic verdict + the 4 defects found, ranked by severity/lane |
| [HANDOVER_Ahmad_scoreboard_dropped_stores.md](HANDOVER_Ahmad_scoreboard_dropped_stores.md) | **Issue 1 (CRITICAL, Ahmad's lane):** scoreboard can't detect dropped stores; proposed SimX-driven comparison + tightened vacuous guard |

> **Verification status (Opus review, 2026-06-26):** every code block in these
> docs was re-checked against the actual `git show <commit>` diff. fix_01, 02,
> 03, 06, 07, 08 were corrected where the reconstructed snippet did not match the
> committed code (the commit IDs and file paths were always right; some
> before/after code was idealized from memory). fix_04, 05, 09, 10, 11, 12, 13,
> 14 matched on first pass.

## Teammate Summary

### Ahmad must review
- **fix_12**: `vortex_scoreboard.sv` was edited to add a guard for pure arithmetic programs. Ahmad owns this file and must verify the `ebreak_seen && simx_ran` guard, the wiring of both flags, and coverage impact.
- **fix_03**: P1-bind handover — Ahmad must implement the `commit_arb_if[*]` passive bind. The generate loop structure is defined in fix_05.
- **fix_11**: `wait_for_completion()` fast-path — Ahmad's derived tests inherit this. May need `repeat(5)` buffer increase if scoreboard ebreak processing is slow.

### Steven must review
- **fix_07**: `Vortex/sim/simx/emulator.cpp` was edited (Samuel's territory was CSR handling, Steven owns SimX). Two changes: VX_CSR_MISA case and M-mode range guard in both `get_csr`/`set_csr`. Must delete `simx_model.so` and rebuild after any emulator.cpp change.
- **fix_08**: SimX has no 16-bit RVC decoder. riscv-dv is now configured `rv32im` (no RVC). Steven must know this if he extends SimX ISA support.
- **fix_05**: The generate loop in `vortex_tb_top.sv` is in the same `ifdef USE_AXI_WRAPPER` block as Steven's AXI SVA. Merge requires checking generate block names for conflicts.
