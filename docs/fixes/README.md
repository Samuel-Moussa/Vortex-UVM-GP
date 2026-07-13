# Engineering Fix Log

Per-issue root-cause writeups for the verification environment. Each file documents
one issue: the symptom, the root cause, the exact fix, and the acceptance check that
proves it. Investigations (`INV*`) capture deeper root-cause analyses.

## Fixes

| File | Issue | Commit |
|------|-------|--------|
| [fix_01_C1_mem_tag_width.md](fix_01_C1_mem_tag_width.md) | Derive `VX_MEM_TAG_WIDTH` from RTL + hex load-address fix | `4c36bd8` |
| [fix_02_C3_ebreak_decode.md](fix_02_C3_ebreak_decode.md) | Real `EBREAK` decode drives completion | `7764ba1` |
| [fix_03_C2_real_instruction_count.md](fix_03_C2_real_instruction_count.md) | Real retired-instruction count via commit handshake | `2211586` |
| [fix_04_T4_honest_error_gate.md](fix_04_T4_honest_error_gate.md) | Remove artificial `-2` offset from the error gate | `e087a78` |
| [fix_05_I1_multicore_probes.md](fix_05_I1_multicore_probes.md) | Generate loops for all N cores/clusters | `11f7135` |
| [fix_06_riscv_dv_pipeline.md](fix_06_riscv_dv_pipeline.md) | riscv-dv pipeline: path fix, assemble step, `STRESS_ITER` | `4661f7c` |
| [fix_07_riscv_dv_simx_csr_sigabrt.md](fix_07_riscv_dv_simx_csr_sigabrt.md) | SimX abort on M-mode CSRs (`VX_CSR_MISA` + range guard) | `2ccef43` |
| [fix_08_riscv_dv_rvc_decode_crash.md](fix_08_riscv_dv_rvc_decode_crash.md) | SimX crash on RVC compressed instructions → rv32im target | `2ccef43` |
| [fix_09_riscv_dv_rtl_csr_assertion.md](fix_09_riscv_dv_rtl_csr_assertion.md) | RTL assertion on `csrw mstatus/misa` → sed strip | `2ccef43` |
| [fix_10_riscv_dv_ecall_ebreak.md](fix_10_riscv_dv_ecall_ebreak.md) | `ecall` → `ebreak` for TB completion detection | `2ccef43` |
| [fix_11_riscv_dv_uvm_stale_event.md](fix_11_riscv_dv_uvm_stale_event.md) | UVM stale-event race in `wait_trigger()` | `2ccef43` |
| [fix_12_riscv_dv_vacuous_run.md](fix_12_riscv_dv_vacuous_run.md) | Vacuous-run false error in the scoreboard | `2ccef43` |
| [fix_13_I2_elaboration_asserts.md](fix_13_I2_elaboration_asserts.md) | Elaboration asserts for topology params | `37cfce5` |
| [fix_14_I5_hygiene.md](fix_14_I5_hygiene.md) | Remove dead files + stale tag-width comments | `a42f164` |
| [fix_15_busy_low_sustained.md](fix_15_busy_low_sustained.md) | `busy==0` completion requires sustained de-assertion | `19c3d55` |
| [fix_16_i2_alias_gap.md](fix_16_i2_alias_gap.md) | I2 assert also checks CLUSTERS/CORES/WARPS/THREADS aliases | `19c3d55` |
| [fix_17_P1_commit_probe_bind.md](fix_17_P1_commit_probe_bind.md) | Passive `vx_commit_probe` bound on `commit_arb_if[*]` | `2026-06-28` |
| [fix_18_fpu_test_and_fp_divergence.md](fix_18_fpu_test_and_fp_divergence.md) | Directed FPU kernel + found DUT/SimX 1-ULP FP divergence | `2026-06-29` |

## Investigations

| File | Topic |
|------|-------|
| [INV1_kernel_completion_hang.md](INV1_kernel_completion_hang.md) | Root cause of hostless-kernel "hang" (`vx_printf` I/O volume, not a stall) |
| [INV2_dcr_write_during_busy.md](INV2_dcr_write_during_busy.md) | `assert_dcr_write_timing` at startup — root cause + reset-handshake fix |

> **Rigor note:** every code block in these writeups was re-checked against the actual
> `git show <commit>` diff, and corrected where a reconstructed snippet did not match
> the committed code — the fix log reflects what actually shipped.
