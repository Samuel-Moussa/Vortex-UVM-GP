# Combined Coverage Report — 2026-06-29

Merged from **19 UCDBs** (AXI config, single tb_top/dut elaboration), third-party
(cvfpu/ramulator) waived via `scripts/coverage_exclude.do`, AXI unreachable bins
`ignore_bins`'d (single-beat FIXED — see fix_18 / COVERAGE_STATUS).

## Totals (BY INSTANCES, 2247 instances)
| Metric | Hit/Total | Coverage |
|---|---|---|
| **Functional (covergroup bins)** | 256 / 629 | **40.69%** |
| Statements | 9097 / 9628 | **94.48%** |
| Branches | 6986 / 8034 | 86.95% |
| Conditions | 616 / 941 | 65.46% |
| Toggles | 377583 / 531920 | 70.98% |
| **Total (filtered)** | — | **71.44%** |

## Merged test set
- Kernels: hello, vecadd, fibonacci, conform (kernel_launch_test)
- Directed: axi_memory, functional_memory, warp_scheduling, barrier_sync
- printf-light (INV-1 fix): **vecadd_lite**, **diverge_lite**, **fpu_test**
- riscv-dv: arithmetic_basic, jump_stress, unaligned_load_store, non_compressed
  (+ fresh seeds)

## Files
- `summary.txt` — vcover summary
- `functional.txt` — per-covergroup / per-coverpoint detail
- `code_summary.txt` — code-coverage header sample
- `merged.ucdb` — the merged DB (view: `vsim -viewcov merged.ucdb`)

## Regenerate
```
cd vortex_uvm_env
bash scripts/merge_coverage.sh --fresh
bash scripts/merge_coverage.sh --collect <run dirs...>
```

See `docs/COVERAGE_STATUS_2026-06-29.md` for the closure plan and the path to
100% functional.
