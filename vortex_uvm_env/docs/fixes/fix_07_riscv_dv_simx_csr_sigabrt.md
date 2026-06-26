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

### `Vortex/sim/simx/emulator.cpp` (code copied verbatim from commit 2ccef437)

**Fix 1 — Add `VX_CSR_MISA` to the existing M-mode fall-through `case` list in
`set_csr` (it joins MSTATUS/MEDELEG/MIDELEG/MIE/... which already no-op):**
```cpp
  case VX_CSR_MSTATUS:
+ case VX_CSR_MISA:
  case VX_CSR_MEDELEG:
  case VX_CSR_MIDELEG:
  case VX_CSR_MIE:
  // ... (these all fall through to the same silent handling)
```

**Fix 2a — `get_csr()`: M-mode range guard inserted BEFORE the existing
`VX_CSR_MPM_BASE` branch (returns 0 instead of falling to the abort path):**
```cpp
    if ((addr >= 0x300 && addr < 0x400) || (addr >= 0xF00 && addr < 0x1000)) {
      // silently return 0 for unimplemented machine-mode / hw-id CSRs
      // (covers riscv-dv boilerplate: 0x343/MTINST, 0x344/MIP, etc.)
      return 0;
    } else if ((addr >= VX_CSR_MPM_BASE && addr < (VX_CSR_MPM_BASE + 32))
            || (addr >= VX_CSR_MPM_BASE_H && addr < (VX_CSR_MPM_BASE_H + 32))) {
      // ... existing user-defined MPM handling ...
```

**Fix 2b — `set_csr()`: M-mode range guard inserted in the default branch,
right before the existing `std::abort()`:**
```cpp
      if ((addr >= 0x300 && addr < 0x400) || (addr >= 0xF00 && addr < 0x1000))
        return; // silently ignore unimplemented machine-mode / hw-id CSR writes
      std::cerr << "Error: invalid CSR write addr=0x" << std::hex << addr << ...;
      std::flush(std::cout);
      std::abort();
```

Net: 9 lines changed in `emulator.cpp`. The abort path is preserved for any CSR
**outside** the M-mode/hw-id ranges, so a genuinely unknown CSR still fails loud.

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
