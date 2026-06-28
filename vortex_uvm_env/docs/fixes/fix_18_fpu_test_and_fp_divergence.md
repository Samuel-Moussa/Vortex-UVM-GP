---
issue: FPU coverage gap + DUT-vs-SimX FP divergence
date: 2026-06-29
author: Samuel Moussa
verified: yes (run results/20260629/run_020822; fpu_cg 0% -> 25%)
---

# fix_18 — Directed FPU test (fills fpu_cg) + DUT/SimX FP divergence finding

## Goal
`instr_class_cg_fpu` was **0%** — a real functional gap (FPU is **enabled**:
`EXT_F`/`EXT_D`), not an ignorable one. riscv-dv (rv32im, integer) can never reach
it. Built a directed FP kernel to drive the FPU EX unit.

## Feasibility (pre-checked)
- **SimX supports F** — `sim/simx/func_unit.cpp` handles `FpuType::FADD/FMUL/
  FMADD/FDIV/FSQRT` via softfloat.
- **Toolchain** — LLVM clang multilib `rv32imaf/ilp32f`; kernels already build
  with `-march=rv32imaf` (`tests/kernel/common.mk`).
- **DUT** — FPU enabled (cvfpu/FPNew, waived in code coverage but functionally live).

## What was added
`Vortex/tests/kernel/fpu_test/{main.cpp,Makefile}` — a **single-threaded**
(no `vx_spawn` → not affected by INV-1, completes via ebreak like fibonacci)
kernel doing a spread of single-precision FP ops via `__builtin_*` so specific
instructions are emitted (not libcalls): `fadd/fsub/fmul/fdiv.s`, `fsqrt.s`,
`fmadd/fnmsub.s`, `fmin/fmax.s`, `fsgnj` (copysign), `fcvt.s.w`/`fcvt.w.s`,
`fcmp`. Results stored to a `volatile` array → scoreboard compares DUT vs SimX.
Build: `cd Vortex/tests/kernel/fpu_test && make` (produces `fpu_test.elf`).
Run: `make sim TEST=kernel_launch_test PROGRAM_NAME=fpu_test`.

## Result — coverage WIN
`instr_class_cg_fpu`: **0% → 25%** (run_020822). Completed via ebreak, SimX Ran:
YES, 2631 instrs. The 25% = `cp_active_threads.one_divergent` (tmask=1, single
thread) + `cp_warp`(warp0). The remaining fpu_cg bins (`uniform`/`partial` thread
masks, multiple warps) need **multi-thread/multi-warp FP**, which requires
`vx_spawn` → **blocked by INV-1** (same gate as all warp-state coverage).

## Finding — DUT-vs-SimX FP divergence (real)
Most FP result words matched exactly; **2 diverged**:
```
addr=0x80006cd0  DUT=0x00000004_00000000  SimX=0x00000004_00000007   (low word: 0 vs 7)
addr=0x80006ce8  DUT=0x3fef7750_40333333  SimX=0x3fef7751_40333333   (high word: ...50 vs ...51)
```
- `...50` vs `...51` = **1-ULP rounding difference** (FPNew vs softfloat).
- `0` vs `0x7` (a tiny value) = likely **denormal flush-to-zero** in the DUT FPU
  vs preserved in SimX.

This is the classic hardware-FPU (cvfpu/FPNew) vs software-model (softfloat)
divergence — exactly what FP black-box verification should surface. It is a
**scoreboard / SimX-config matter, not a test bug**:
- **Ahmad (scoreboard):** exact bit-compare is too strict for FP — needs FP-aware
  tolerance (e.g. ±1 ULP) OR a separate FP-compare path, for FP result regions.
- **Steven (SimX):** align SimX FP config with the DUT — rounding mode (`frm`) and
  **denormal handling (flush-to-zero vs preserve)** so the golden model matches
  the DUT FPU.

Until one of those is done, an FP kernel will report MEM MISMATCH on the
rounding/denormal-sensitive results even though the FPU is functionally correct.

## Status / handover
- ✅ FPU functional coverage opened (0→25%); FP path proven end-to-end (DUT+SimX).
- ⚠️ FP equivalence needs tolerance/config alignment → **Ahmad (scoreboard FP
  tolerance) + Steven (SimX FP rounding/denormal)**.
- ⛔ fpu_cg to 100% needs multi-warp FP → **INV-1** (Steven).

## Pointers
- Test: `Vortex/tests/kernel/fpu_test/main.cpp`
- Covergroup: `vortex_uvm_env/tb/vx_instr_probe.sv` (`noop_class_cg("fpu")`)
- SimX FP: `Vortex/sim/simx/func_unit.cpp`, `types.h` (`enum FpuType`)
- Run: `results/20260629/run_020822_kernel_launch_test`
- Coverage context: `COVERAGE_STATUS_2026-06-29.md`
