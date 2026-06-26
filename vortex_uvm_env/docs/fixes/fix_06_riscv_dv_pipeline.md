---
issue: riscv-dv pipeline plumbing
commit: 4661f7cb
date: 2026-06-26
author: Samuel Moussa
---

# riscv-dv Pipeline Plumbing — Path Fix, Assemble+Link Step, STRESS_ITER Wiring

## Problem

The riscv-dv pipeline had never been run end-to-end before this session. Three independent plumbing bugs prevented it from even starting:

1. **Wrong path**: `prepare.sh` was not locating the generated `.S` assembly. riscv-dv writes to `<RISCV_DV_HOME>/out_<date>/asm_test/<test_name>_0.S` (directory `asm_test`, singular; file suffixed `_0.S`). The fix searches the riscv-dv home for `*/asm_test/${PROGRAM}_0.S` and takes the newest.

2. **Missing assemble+link step**: `prepare.sh` was trying to load a `.hex` file directly from riscv-dv output, but riscv-dv generates `.S` (assembly source), not `.hex`. The compile step (gcc assemble + link + objcopy to hex) was entirely missing.

3. **STRESS_ITER not wired**: `random_instruction_stress_test.sv` reads `+NUM_STRESS_ITER` from plusargs to control how many programs to run, but `simulate.sh` never passed this plusarg — the test always ran with the default (1 iteration).

---

## Files Edited (code copied verbatim from commit 4661f7cb)

> NOTE: at this commit the gcc target was still `rv32imc` and the linker used
> riscv-dv's own `link.ld`. The switch to `rv32im` (no RVC) and the sed
> post-processing came LATER, in commit 2ccef437 — see
> [fix_08](fix_08_riscv_dv_rvc_decode_crash.md) and
> [fix_09](fix_09_riscv_dv_rtl_csr_assertion.md). Don't conflate the two.

### `vortex_uvm_env/scripts/prepare.sh`

**riscv-dv home + path discovery** — riscv-dv writes to
`out_<date>/asm_test/<test>_0.S` (note: `asm_test` singular, `_0.S` suffix):
```bash
RISCV_DV_HOME="${RISCV_DV_HOME:-$HOME/riscv-dv}"
# find the newest matching generated assembly:
PROGRAM_SOURCE=$(find "$RISCV_DV_HOME" -path "*/asm_test/${PROGRAM}_0.S" -type f 2>/dev/null | sort -r | head -1)
```

**Assemble + link step** — added because riscv-dv emits raw `.S`, not ELF/hex.
The actual compiler call at this commit (rv32imc, riscv-dv link script):
```bash
ASM_ELF="${PROGRAM_HEX%.hex}.elf"
RISCV_GCC="${RISCV_GCC:-riscv64-unknown-elf-gcc}"
if $RISCV_GCC \
    -T"$RISCV_DV_HOME/scripts/link.ld" \
    -march=rv32imc_zicsr_zifencei -mabi=ilp32 \
    -o "$ASM_ELF" \
    "$PROGRAM_SOURCE" 2>&1 | tee "$OBJCOPY_LOG"; then
    PROGRAM_SOURCE="$ASM_ELF"   # downstream objcopy→hex now has a real ELF
fi
```
(`riscv64-unknown-elf-gcc` with `-mabi=ilp32`/`-march=rv32*` produces a 32-bit
ELF — the 64-bit toolchain is just what's installed; the ABI/arch flags pin it
to RV32.)

### `vortex_uvm_env/scripts/simulate.sh`

**STRESS_ITER wiring** — added plusarg for stress iteration count (verbatim):
```bash
# Stress iterations — read by random_instruction_stress_test via +NUM_STRESS_ITER
if [[ "${STRESS_ITER:-1}" -gt 1 ]]; then
    SIM_OPTS="$SIM_OPTS +NUM_STRESS_ITER=$STRESS_ITER"
fi
```

`vortex_uvm_env/Makefile` and `scripts/run.sh` were also touched (4 + 2 lines)
to expose `STRESS_ITER=N` as a make variable and forward it through.

---

## Acceptance Check
- `prepare.sh` finds the `.S` file and compiles it to `.hex` without errors
- `make sim TEST=random_instruction_stress_test PROGRAM=riscv_arithmetic_basic_test TIMEOUT=1000000` runs without "file not found" errors
- With `STRESS_ITER=3`, the test runs 3 programs (check log for "Iteration 1/3", "2/3", "3/3")

---

## Teammate Conflicts / Handover

**No conflicts for this specific fix.** `prepare.sh` and `simulate.sh` are Samuel's lane.

**Steven — important note on `prepare.sh`:**
Steven's D-simx task involves wiring SimX to run with the correct multi-core parameters. `prepare.sh` is where the program ELF/hex is generated. If D-simx needs a differently-linked ELF (different start address, extra sections), coordinate with Samuel. As of this commit the riscv-dv compile uses riscv-dv's own link script and `rv32imc`:
```
riscv64-unknown-elf-gcc -T<RISCV_DV_HOME>/scripts/link.ld -march=rv32imc_zicsr_zifencei -mabi=ilp32
```
(Later changed to `rv32im` by commit 2ccef437 — see fix_08.)

**Note on riscv-dv output directory structure:**
riscv-dv creates `<RISCV_DV_HOME>/out_<date>/asm_test/<test_name>_0.S`. `prepare.sh`
discovers it via `find "$RISCV_DV_HOME" -path "*/asm_test/${PROGRAM}_0.S"`. Override
the search root with `export RISCV_DV_HOME=/path/to/riscv-dv` before invoking make.
