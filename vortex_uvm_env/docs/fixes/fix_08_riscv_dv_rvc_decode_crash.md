---
issue: riscv-dv sub-issue B — SimX RVC decode abort
commit: 2ccef437
date: 2026-06-26
author: Samuel Moussa
lane-note: prepare.sh edit (Samuel); riscv-dv config edit (outside repo, Samuel); SimX affected (Steven)
---

# riscv-dv Sub-Issue B — SimX Crashes on RVC (16-bit Compressed) Instructions

## Problem

riscv-dv was configured to generate `rv32imc` programs (ISA includes RVC compressed instructions). `simx`'s `decode.cpp` does not have a 16-bit instruction decoder. When a compressed instruction appeared in the instruction stream, SimX would either:
- Decode a garbage 32-bit word (misaligned fetch of two 16-bit instrs)
- Assert false on an unknown opcode

The symptoms were SimX SIGABRT or wrong-PC execution, not a clean error message.

---

## Fix: Remove RVC from riscv-dv target

The fix is in the riscv-dv configuration, not in SimX. SimX does not need RVC support for Vortex (the RTL does not implement RVC either).

### `/home/samuel_ubuntu22/riscv-dv/target/rv32im/riscv_core_setting.sv` (created)

This file is **outside the repo** (in the riscv-dv install directory). It defines which ISA extensions are enabled for the `rv32im` target:

```sv
// New target: rv32im (no compressed)
// File: /home/samuel_ubuntu22/riscv-dv/target/rv32im/riscv_core_setting.sv
parameter supported_isa[$] = {RV32I, RV32M};  // NO RV32C
parameter XLEN = 32;
parameter NUM_HARTS = 1;
// ... rest of Vortex-appropriate settings
```

The `rv32imc` target that was previously used included `RV32C` in `supported_isa`. The new `rv32im` target removes it.

### `/home/samuel_ubuntu22/riscv-dv/run.py` (modified, outside repo)

Added the `rv32im` case to the ISA dispatch:
```python
elif args.target == "rv32im":
    args.mabi = "ilp32"
    args.isa = "rv32im_zicsr_zifencei"
```

### `vortex_uvm_env/scripts/prepare.sh`

riscv-dv invocation changed from the `rv32imc` ISA to the `rv32im` target
(verbatim from commit 2ccef437 — note the flag itself changed `--isa` → `--target`):
```bash
# Before:
            --isa=rv32imc \
# After:
                --target=rv32im \
```

GCC compile arch also updated (verbatim):
```bash
# Before:
                    -march=rv32imc_zicsr_zifencei -mabi=ilp32 \
# After:
                    -march=rv32im_zicsr_zifencei -mabi=ilp32 \
```

---

## Acceptance Check
- riscv-dv generated `.S` contains no 16-bit compressed instructions (no `c.addi`, `c.lw`, etc.)
- `simx` processes the generated program without decode aborts
- `file` on the compiled ELF shows `ELF 32-bit LSB executable, RISC-V, RVC/RVE (embedded ABI)` — if you see "RVC" absent, the target is correct

---

## Teammate Conflicts / Handover

**Steven (SimX lane):**
The underlying root cause is that SimX has no 16-bit decoder. This is a known limitation. If Steven ever adds RVC support to SimX, the riscv-dv target can be changed back to `rv32imc`. For now, `rv32im` is correct.

Steven should be aware that `prepare.sh` now passes `-march=rv32im_zicsr_zifencei` to gcc. If Steven's D-simx invocation also compiles code for SimX, he should use the same ISA string for consistency.

**Ahmad:** No conflict.

**Note on riscv-dv install:**
The files modified are outside the repo (`/home/samuel_ubuntu22/riscv-dv/`). If riscv-dv is reinstalled or updated, the `rv32im` target files must be recreated. Consider committing `riscv_core_setting.sv` to the repo under `vortex_uvm_env/riscv_dv_patches/` for reproducibility — this is a future task.
