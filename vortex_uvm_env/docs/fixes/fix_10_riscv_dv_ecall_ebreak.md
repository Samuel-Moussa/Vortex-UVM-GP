---
issue: riscv-dv sub-issue D — ecall vs ebreak
commit: 2ccef437
date: 2026-06-26
author: Samuel Moussa
---

# riscv-dv Sub-Issue D — ecall Must Become ebreak for TB Completion Detection

## Problem

riscv-dv programs terminate by issuing `ecall` to signal the test framework that execution is complete. The opcode for `ecall` is `0x00000073`.

The Vortex testbench completion probe (C3) decodes `ebreak` = `0x00100073`. These are different instructions. The TB was watching for `0x00100073` on the fetch interface; riscv-dv programs exit with `0x00000073`. The completion signal never fired.

Consequence: every riscv-dv program run would timeout after the full `TIMEOUT` cycles because `tb_probe_ebreak_seen` was never set.

---

## Fix: Replace ecall with ebreak in sed post-processing

This fix is part of the same `sed` pipeline added for [sub-issue C](fix_09_riscv_dv_rtl_csr_assertion.md):

### `vortex_uvm_env/scripts/prepare.sh`

In the `sed` command (already shown in fix_09), the final pattern:
```bash
-e 's/\becall\b/ebreak/g' \
```

This replaces every `ecall` instruction in the generated assembly with `ebreak` before compilation. Since riscv-dv places `ecall` at the end of the test program as a termination signal, this ensures:
1. The DUT fetches `0x00100073` (ebreak opcode) at program end
2. `tb_ebreak_fetch` fires (the fetch-interface probe from C3)
3. `tb_probe_ebreak_seen` latches
4. `status_if.ebreak_detected` asserts
5. UVM completion proceeds normally

---

## Why not change the TB to watch for ecall?

Three reasons:
1. The RTL `ebreak` probe (`C3`) is the designed completion mechanism. Changing it to also watch `ecall` would complicate the probe logic and create ambiguity.
2. Vortex's `ecall` handling is different from `ebreak` — `ecall` triggers an M-mode trap that Vortex doesn't implement; the behavior is undefined/assertion. We want ebreak specifically.
3. The sed replacement is done at source level — it's clean, doesn't affect binary size or alignment (ecall and ebreak are the same instruction width), and is invisible to the DUT (it fetches ebreak, exactly as the probe expects).

---

## Acceptance Check
- `grep -c ecall <test>_clean.S` returns 0 (all ecalls replaced)
- `grep -c ebreak <test>_clean.S` returns > 0 (the terminator is now ebreak)
- Simulation: `[TB_PROBE_EBREAK]` prints at the correct cycle; EBREAK detected before TIMEOUT

---

## Teammate Conflicts / Handover

**No conflicts.** `prepare.sh` is Samuel's lane.

**Ahmad — note on scoreboard ebreak detection:**
The scoreboard's `ebreak_seen` flag is set by the UVM completion monitor when `status_if.ebreak_detected` asserts. This flag is used in the vacuous-run guard (see [fix_12](fix_12_riscv_dv_vacuous_run.md)). The ecall→ebreak substitution ensures `ebreak_seen` gets set correctly for riscv-dv programs. Ahmad's coverage groups that depend on `ebreak_seen` will benefit from this fix.

**Steven — note on DPI / SimX:**
SimX is run by `prepare.sh` / `simulate.sh` via DPI before the UVM simulation. SimX uses the ELF (not the RTL fetch stream) to determine when to stop — it halts when it sees `ebreak` opcode at the current PC. Since ecall is also replaced in the `.S` before compilation, SimX will also see `ebreak` in the ELF and halt correctly. The exit code convention is `gp` register value at halt = 1 for pass.
