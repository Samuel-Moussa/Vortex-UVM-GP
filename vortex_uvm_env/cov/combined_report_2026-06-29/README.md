# Combined Coverage Report — 2026-06-29

Merged from **12 UCDBs** (new TCU-guarded probe, AXI config, single tb_top/dut
elaboration), third-party (cvfpu/ramulator) waived via `scripts/coverage_exclude.do`,
AXI unreachable bins `ignore_bins`'d (single-beat FIXED — see fix_18 / COVERAGE_STATUS).

## Totals (BY INSTANCES, 2247 instances)
| Metric | Hit/Total | Coverage |
|---|---|---|
| **Functional (covergroup bins)** | 269 / 621 | **43.31%** (TCU guarded; +spawn_tmc_sweep +barrier_lite) |
| Statements | 9064 / 9628 | **94.14%** |
| Branches | 6978 / 8034 | 86.85% |
| Conditions | 639 / 941 | 67.90% |
| Toggles | 378160 / 531920 | 71.09% |
| **Total (filtered)** | — | **73.20%** |

**+spawn_tmc_sweep (2026-06-29):** directed warp-control kernel → `tmc_cg` 60%→**100%**,
`wspawn_cg` 25%→**75%** (=100% of reachable; `all`={NW} bin unreachable, off-by-one →
Ahmad). Functional bins 258→266 (+8), total 72.05%→73.02%.

**+barrier_lite (2026-06-29):** directed barrier kernel; `barrier_cg` 55% to max-reachable
(`cp_bar_id` **100%**, `cp_bar_event` **100%**, `cp_bar_scope` 50%=100% reachable [global
needs GBAR/multi-core], `cp_bar_size` 75%=100% reachable [size[0]=1-warp noop]). Functional
bins 266 to 269 (+3), total 73.02% to 73.20%. NOTE: barrier_lite trips ONE benign scoreboard
MEM MISMATCH at the .got tail (DUT cache writeback zero-clobbers a read-only GOT word; SimX
flat memory keeps it; shadow_memory has no image preload). Coverage is valid; scoreboard
gate is an Ahmad ask (see COVERAGE_STATUS sec 4c).

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
