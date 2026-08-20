# Samuel Moussa — Detailed Contributions

Vortex UVM GPGPU Verification Project (Oct 2025 – Jul 2026)
Collected from all branches, deduplicated and grouped by area.

## Environment bring-up & infrastructure
- Initialized the Vortex UVM GP project and repository structure; authored and
  iterated the project README and top-level documentation.
- Converted the Vortex RTL into a local in-repo folder and integrated the full
  Vortex GPGPU RTL with the UVM verification environment.
- Fixed numerous Vortex RTL source/compilation bugs (FPU, TCU, `VX_tcu_pkg`) to get
  the design elaborating under QuestaSim 2021.2.
- Resolved QuestaSim strict-optimization failures (`vortex_top`, `VX_cache_bypass`,
  `VX_operands`) and RTL modifications for the SimX DPI-C flow on Questa 21.
- Fixed GLIBCXX / `simx_model.so` linking and library-path issues; added GLIBCXX
  fix documentation.
- Refactored the UVM environment interfaces and memory-model integration across the
  environment (driver/monitor clocking-block compatibility).

## Test bench & simulation flow
- Built a comprehensive smoke test for the Vortex GPGPU and drove it to first
  success (`program_simple.kex`); wrote the smoke-test bring-up report.
- Enhanced the run script (`run_vortex_uvm_enhanced.sh`) with startup-address
  handling, DPI library linking, HEX validation to prevent load-address overflow,
  and QUESTA_HOME auto-detection.
- Added AXI and functional-memory virtual sequences; enhanced the functional-memory
  test and direct `mem_model` access path.
- Added a results-checking / error-logging script.

## Gate-0 bench-correctness fixes (trust the testbench)
- C1: Derived `VX_MEM_TAG_WIDTH` from the real RTL package instead of a hardcoded
  value; added an elaboration assert that UVM params match DUT params; fixed the hex
  load-address overflow (ISS-01).
- C2: Removed the fabricated `tb_mem_ops % 3` instruction count and wired the real
  retired-instruction count from the commit stage; restored true IPC (multi-core
  correct).
- C3: Decoded real EBREAK (`0x00100073`) to drive execution-complete as the primary
  completion trigger, demoting the idle/busy fallback to a warning.
- T4: Removed the `-2` UVM_ERROR subtraction in `simulate.sh`; fully validated the
  negative test (injected fault on `vecadd_lite` is caught by the checker).

## Configurability (any N clusters/cores/warps/threads)
- I1: Made commit-count and ebreak probes configurable for N cores/clusters via
  generate loops.
- I2: Added elaboration asserts comparing UVM topology plusargs against RTL macros
  (fail-loud on mismatch).
- I5: Removed dead files and fixed stale `// 8` tag-width comments.
- P1-bind: Built a passive commit-retire monitor bound on `commit_arb_if[*]` for
  observability (handed to coverage).
- Derived AXI interface `ID_WIDTH` from `VX_MEM_TAG_WIDTH` so any config elaborates.
- Fixed the multi-config SimX golden model by rebuilding SimX core objects
  per-config in the DPI build (fixed multi-core crash).

## Constrained-random (riscv-dv) pipeline
- Stood up the riscv-dv randomization pipeline end-to-end: fixed paths, added
  assemble+link steps, wired stress iterations.
- Got `random_instruction_stress_test` / `riscv_arithmetic_basic_test` passing
  (fixed 6 root causes across SimX, prepare.sh, and the base test).
- Made arithmetic tests self-checking via GPR-dump + `vx_tmc 0` exit; fixed epilogue
  injection and a gawk `\b` bug that truncated assembly.

## Co-simulation & coverage enablement
- Restored DUT-vs-SimX co-simulation for kernel, regression, and riscv-dv test types
  (SimX reset-before-step fix).
- Root-caused INV-1 (kernels "hanging"): proved it was `vx_printf` I/O volume, not a
  SIMT/wspawn bug; created printf-light kernel variants (`vecadd_lite`,
  `diverge_lite`) that complete multi-warp with DUT==SimX.
- Authored directed kernels driving coverage: `fpu_test`, `fpu_mt`,
  `spawn_tmc_sweep`, `barrier_lite`, `axi_stress`, `host_coverage_test`.
- Added evidence-based and config-aware `ignore_bins` for unreachable AXI / route
  bins (with full reachability maps); wired real PC and fetch/memory pipeline stalls
  into `status_if`.
- Fixed the scoreboard byte-valid mask so sub-word stores no longer false-mismatch
  vs SimX.
- Ran full-suite coverage merges and reporting (functional coverage lifted from ~12%
  to ~73% total across sessions).
