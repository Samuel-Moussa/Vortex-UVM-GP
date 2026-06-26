---
issue: riscv-dv sub-issue C — RTL assertion on machine-mode CSR writes
commit: 2ccef437
date: 2026-06-26
author: Samuel Moussa
---

# riscv-dv Sub-Issue C — RTL Assertion Fires on csrw mstatus/misa/mtvec

## Problem

Even after fixing SimX (sub-issue A), the RTL DUT itself asserts and prints `** Error:` when it encounters `csrw` instructions targeting machine-mode CSRs (`0x300–0x3FF`). Vortex's CSR unit has a check that triggers an RTL assertion for unsupported CSR addresses. This is correct RTL behavior — Vortex does not implement M-mode CSRs.

The error appears in the simulation log as:
```
** Error: (vsim-3601) [CSRUNIT] Unsupported CSR write: addr=0x300 (mstatus)
```

These RTL errors are counted by `simulate.sh`'s `RTL_ERRORS` counter and cause the test to FAIL even if UVM reports 0 errors.

---

## Fix: sed Post-Processing in prepare.sh to Strip M-mode CSR Instructions

Rather than modifying the RTL (which is correct behavior) or modifying SimX more, the fix is to strip out M-mode CSR instructions from the riscv-dv generated assembly before compiling. This is done with `sed` in `prepare.sh` immediately after the `.S` file is found and before gcc compilation.

### `vortex_uvm_env/scripts/prepare.sh`

Added `sed` post-processing step between "find the .S file" and "gcc compile":
```bash
# Post-process: strip M-mode CSR instructions that Vortex does not support.
# Replace with nop to preserve instruction count and alignment.
ASM_CLEAN="${PROGRAM_HEX%.hex}_clean.S"
sed \
    -e 's/\bcsrw\s\+0x3[0-9a-fA-F][0-9a-fA-F]\b.*/nop/g' \
    -e 's/\bcsrr\s\+[a-z0-9]*,\s*0x3[0-9a-fA-F][0-9a-fA-F]\b.*/nop/g' \
    -e 's/\bcsrr\s\+[a-z0-9]*,\s*0xf14\b.*/nop/g' \
    -e 's/\bmret\b/nop/g' \
    -e 's/\becall\b/ebreak/g' \
    "$PROGRAM_SOURCE" > "$ASM_CLEAN"
```

The gcc compile step then uses `$ASM_CLEAN` instead of `$PROGRAM_SOURCE`.

**What each sed pattern strips:**
| Pattern | CSR range | Examples |
|---------|-----------|---------|
| `csrw 0x3XX` | M-mode read/write CSRs | mstatus (0x300), misa (0x301), mtvec (0x305) |
| `csrr rX, 0x3XX` | M-mode reads | same range |
| `csrr rX, 0xf14` | `mhartid` — always 0 for single core, not worth keeping | |
| `mret` | Machine-mode return — Vortex has no M-mode trap handler | |
| `ecall` | → `ebreak` | See [fix_10](fix_10_riscv_dv_ecall_ebreak.md) |

Note on `mret`: replacing with `nop` means the program won't return from a fake trap handler. For riscv-dv arithmetic tests this is fine — the test flow doesn't use the trap handler. For interrupt-driven tests (T-exc) this approach must be revisited.

---

## Acceptance Check
- Simulation log contains no `** Error: [CSRUNIT] Unsupported CSR write` messages
- `RTL_ERRORS=0` in `simulate.sh` result analysis
- The clean `.S` file can be inspected: `grep -E 'csrw|mret|csrr.*0x3' <test>_clean.S` should return empty

---

## Teammate Conflicts / Handover

**No conflicts.** `prepare.sh` is Samuel's lane.

**Ahmad — note for T-exc:**
Samuel's future `T-exc` task (exception/interrupt stimulus) is supposed to feed Ahmad's `exception_cg` coverage group. The current `mret` → `nop` substitution means that exception return paths through `mret` will be suppressed in riscv-dv generated code. For T-exc, Samuel will need a different approach — either write directed assembly that exercises the exception path directly (bypassing riscv-dv's M-mode scaffolding) or remove the `mret` suppression for T-exc specifically.

**Steven:** No conflict. The sed step is purely a compile-time transformation on the assembly source; SimX and the DPI interface are not affected.
