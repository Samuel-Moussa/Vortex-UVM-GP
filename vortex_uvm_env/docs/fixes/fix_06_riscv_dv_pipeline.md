---
issue: riscv-dv pipeline plumbing
commit: 4661f7cb
date: 2026-06-26
author: Samuel Moussa
---

# riscv-dv Pipeline Plumbing — Path Fix, Assemble+Link Step, STRESS_ITER Wiring

## Problem

The riscv-dv pipeline had never been run end-to-end before this session. Three independent plumbing bugs prevented it from even starting:

1. **Wrong path**: `prepare.sh` was looking for the generated `.S` assembly in the wrong directory. The riscv-dv `run.py` outputs to `out/asm_tests/<test_name>/<iter>/`, but `prepare.sh` was searching `out/<test_name>/` — file was never found.

2. **Missing assemble+link step**: `prepare.sh` was trying to load a `.hex` file directly from riscv-dv output, but riscv-dv generates `.S` (assembly source), not `.hex`. The compile step (gcc assemble + link + objcopy to hex) was entirely missing.

3. **STRESS_ITER not wired**: `random_instruction_stress_test.sv` reads `+NUM_STRESS_ITER` from plusargs to control how many programs to run, but `simulate.sh` never passed this plusarg — the test always ran with the default (1 iteration).

---

## Files Edited

### `vortex_uvm_env/scripts/prepare.sh`

**Path fix** — find the `.S` file in the correct riscv-dv output directory:
```bash
# Before:
PROGRAM_SOURCE=$(find "$RISCVDV_OUT_DIR/$PROGRAM" -name "*.S" | head -1)

# After:
PROGRAM_SOURCE=$(find "$RISCVDV_OUT_DIR/asm_tests/$PROGRAM" -name "*.S" 2>/dev/null | head -1)
```

**Assemble + link step** — added before hex conversion:
```bash
# Compile: assemble and link to ELF
PROGRAM_ELF="${PROGRAM_HEX%.hex}.elf"
riscv32-unknown-elf-gcc \
    -march=rv32im_zicsr_zifencei -mabi=ilp32 \
    -nostdlib -static \
    -Ttext=0x80000000 \
    -o "$PROGRAM_ELF" \
    "$ASM_CLEAN"   # see fix_07 for why we compile the cleaned version, not the raw .S

# Convert ELF to hex
riscv32-unknown-elf-objcopy -O verilog \
    --verilog-data-width=4 \
    "$PROGRAM_ELF" "$PROGRAM_HEX"
```

### `vortex_uvm_env/scripts/simulate.sh`

**STRESS_ITER wiring** — added plusarg for stress iteration count:
```bash
# Stress iterations — read by random_instruction_stress_test via +NUM_STRESS_ITER
if [[ "${STRESS_ITER:-1}" -gt 1 ]]; then
    SIM_OPTS="$SIM_OPTS +NUM_STRESS_ITER=$STRESS_ITER"
fi
```

The Makefile exposes `STRESS_ITER=N` as a make variable which is forwarded to `simulate.sh` via the environment.

---

## Acceptance Check
- `prepare.sh` finds the `.S` file and compiles it to `.hex` without errors
- `make sim TEST=random_instruction_stress_test PROGRAM=riscv_arithmetic_basic_test TIMEOUT=1000000` runs without "file not found" errors
- With `STRESS_ITER=3`, the test runs 3 programs (check log for "Iteration 1/3", "2/3", "3/3")

---

## Teammate Conflicts / Handover

**No conflicts for this specific fix.** `prepare.sh` and `simulate.sh` are Samuel's lane.

**Steven — important note on `prepare.sh`:**
Steven's D-simx task involves wiring SimX to run with the correct multi-core parameters. The `prepare.sh` script is where the program ELF/hex is generated. If Steven's SimX integration requires a differently-linked ELF (e.g., different start address, additional sections), he needs to coordinate with Samuel on the gcc flags in `prepare.sh`. The current flags are:
```
-march=rv32im_zicsr_zifencei -mabi=ilp32 -nostdlib -static -Ttext=0x80000000
```

**Note on riscv-dv output directory structure:**
riscv-dv `run.py` creates: `out/asm_tests/<test_name>/<iter>/<test_name>_<iter>.S`
The `RISCVDV_OUT_DIR` variable in `prepare.sh` must point to the riscv-dv `out/` directory. If the riscv-dv install location changes, this path must be updated.
