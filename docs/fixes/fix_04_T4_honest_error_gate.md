---
issue: T4
commit: e087a78f
date: 2026-06-26
author: Samuel Moussa
---

# T4 — Honest Error Gate: Remove the -2 Subtraction

## Problem

`vortex_uvm_env/scripts/simulate.sh` line 123 had:
```bash
REAL_UVM_ERRORS=$((UVM_ERRORS > 2 ? UVM_ERRORS - 2 : UVM_ERRORS))
```

This was added as a workaround to hide two phantom `UVM_ERROR`s that fired on every run:
1. `Timeout after 1000000 cycles` — from `wait_for_completion()` being called after ebreak was already seen (stale event race).
2. `No checks were performed — vacuous run` — from the scoreboard when `riscv_arithmetic_basic_test` had no memory stores.

The subtraction masked real errors. A test with 1 real error + the 2 phantom errors would report 1 after subtraction — and pass. A test with exactly 1 real error and no phantom errors would subtract 0 (1 ≤ 2) — also pass. The gate was completely ineffective.

Both phantom errors were fixed at their root causes (commits 2ccef437 and 11f71359), making the subtraction no longer needed and actively harmful.

---

## Files Edited

### `vortex_uvm_env/scripts/simulate.sh` (lines 115–124)

Before:
```bash
UVM_ERRORS=$(grep -c "^# UVM_ERROR /" "$LOG_FILE" 2>/dev/null || true)
UVM_ERRORS=${UVM_ERRORS:-0}
UVM_FATALS=$(grep -c "^# UVM_FATAL /" "$LOG_FILE" 2>/dev/null || true)
UVM_FATALS=${UVM_FATALS:-0}
REAL_UVM_ERRORS=$((UVM_ERRORS > 2 ? UVM_ERRORS - 2 : UVM_ERRORS))
```

After:
```bash
# Count UVM errors directly — this is the authoritative source.
# T4: no subtraction. Every UVM_ERROR in the log is a real failure.
# The old "-2" workaround was hiding real errors; root causes that
# generated phantom errors (wait_for_completion stale event, vacuous-run)
# were fixed directly (commits 2ccef437, 11f71359).
UVM_ERRORS=$(grep -c "^# UVM_ERROR /" "$LOG_FILE" 2>/dev/null || true)
UVM_ERRORS=${UVM_ERRORS:-0}
UVM_FATALS=$(grep -c "^# UVM_FATAL /" "$LOG_FILE" 2>/dev/null || true)
UVM_FATALS=${UVM_FATALS:-0}
REAL_UVM_ERRORS=$UVM_ERRORS
```

The gating logic downstream (`if [[ $REAL_UVM_ERRORS -gt 0 ]]`) is unchanged — it just now sees the true count.

---

## Acceptance Check
- A deliberately injected UVM_ERROR (e.g., a known-bad test) must cause the run to FAIL
- A clean run (`kernel_launch_test` + `hello.elf`) must produce 0 errors and PASS
- No `-2` or any subtraction anywhere in the results analysis section

Gate-0 sign-off constraint: "negative test RED on injection" — this means if you add a `uvm_error("TEST", "deliberate injection")` to any test and run it, the result must say FAILED. With this fix that is guaranteed; without it, the subtraction could swallow 1-2 errors.

---

## Teammate Conflicts / Handover

**No conflicts.** `simulate.sh` is Samuel's lane (scripts infrastructure).

**Ahmad — note for negative fault injection (Gate-0):**
The Gate-0 sign-off requires the "dropped-store fails (Ahmad's SB-DIR)" test. With T4 fixed, when Ahmad's SB-DIR test deliberately drops a store and the scoreboard fires a UVM_ERROR, that error will now correctly propagate to FAILED exit code. Previously the -2 subtraction would have swallowed it if ≤ 2 errors fired. Ahmad does not need to change anything for this — the script fix is sufficient.

**Steven:** No conflict.
