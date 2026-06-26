---
issue: riscv-dv sub-issue A — SimX SIGABRT on M-mode CSRs
commit: 2ccef437
date: 2026-06-26
author: Samuel Moussa
lane-note: EDIT IN STEVEN'S FILE — requires Steven's awareness
---

# riscv-dv Sub-Issue A — SimX SIGABRT on Machine-Mode CSRs (VX_CSR_MISA + M-mode Range)

## Problem

Running `simx` against any riscv-dv generated program that includes CSR instructions caused SIGABRT:
```
simx: emulator.cpp:XXX: void Emulator::set_csr(...): Assertion `false' failed.
Aborted (core dumped)
```

Root cause: `Vortex/sim/simx/emulator.cpp`'s `set_csr()` and `get_csr()` functions had `default: assert(false)` as the fallback for any CSR not in the switch case. Machine-mode CSRs (`0x300–0x3FF`, e.g., `mstatus=0x300`, `misa=0x301`, `mtvec=0x305`) and read-only machine CSRs (`0xF00–0xFFF`, e.g., `mvendorid=0xF11`) are not in the Vortex CSR switch — Vortex is not a full M-mode implementation. riscv-dv's `riscv_arithmetic_basic_test` program happens to include `csrw mstatus, ...` and similar instructions.

Two CSR-related failures:
1. `VX_CSR_MISA` (`0x301`) was not in `set_csr`'s case list → assert(false) → SIGABRT
2. Any M-mode range CSR read/write in the `default:` branch → assert(false) → SIGABRT

---

## Files Edited

### `Vortex/sim/simx/emulator.cpp`

**Fix 1 — Add `VX_CSR_MISA` to the silent-ignore list in `set_csr`:**
```cpp
// Before: VX_CSR_MISA was missing from the switch entirely

// After: added alongside other ignored CSRs:
case VX_CSR_MISA:
    // Vortex is not a full M-mode implementation — ignore writes to misa
    break;
```

**Fix 2 — Guard the `default:` with an M-mode range check:**

In `get_csr()`:
```cpp
default:
    // Before:
    assert(false);

    // After:
    if ((addr >= 0x300 && addr < 0x400) || (addr >= 0xF00 && addr < 0x1000)) {
        // M-mode CSR range: silently return 0 (Vortex not full M-mode)
        return 0;
    }
    assert(false);  // still fatal for truly unknown CSRs outside M-mode range
```

In `set_csr()`:
```cpp
default:
    // Before:
    assert(false);

    // After:
    if ((addr >= 0x300 && addr < 0x400) || (addr >= 0xF00 && addr < 0x1000)) {
        // M-mode CSR range: silently ignore writes
        break;
    }
    assert(false);
```

---

## Acceptance Check
- `simx` runs to completion on a riscv-dv generated program with M-mode CSR instructions
- No SIGABRT from `emulator.cpp`
- SimX exit code is 1 (normal: `gp=1` before ebreak → exit code 1 = test passed in riscv-dv convention)

---

## CONFLICT: This is Steven's file

**`Vortex/sim/simx/emulator.cpp` is in Steven's lane (SimX/DPI).**

Samuel edited this file to unblock the riscv-dv end-to-end flow. Steven must be informed:
1. Two changes were made to `emulator.cpp`: the `VX_CSR_MISA` case addition and the M-mode range guard in both `get_csr` and `set_csr`.
2. These changes are conservative — they only affect CSR addresses not already handled by Vortex, so they should not break any existing SimX test.
3. However, if Steven has a different strategy for handling unknown CSRs (e.g., returning an error code instead of 0 for M-mode reads), he must reconcile.

**Steven's handover task:**
- Review the two changes in `emulator.cpp` (commit 2ccef437)
- Confirm that the M-mode range guard is acceptable for D-matrix and D-simx work
- If Steven's CSR model evolves (adding more M-mode CSRs), he may want to replace the range guard with individual case entries

**CRITICAL rebuild note for Steven:**
After any edit to `emulator.cpp`, the DPI Makefile does NOT reliably detect the change. **Manually delete `simx_model.so`** before rebuilding:
```bash
rm -f Vortex/sim/simx/simx_model.so
make -C Vortex/sim/simx
```
Otherwise the stale `.so` is loaded by QuestaSim and the fix won't be active.
