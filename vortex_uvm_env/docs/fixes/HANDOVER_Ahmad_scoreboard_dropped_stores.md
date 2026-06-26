---
to: Ahmad (scoreboard + coverage owner)
from: Samuel
date: 2026-06-26
severity: CRITICAL — blocks Gate-0 sign-off ("dropped-store fails")
files: vortex_uvm_env/uvm_env/vortex_scoreboard.sv
---

# Handover — Scoreboard cannot detect dropped stores

## TL;DR
The end-state comparison is **DUT-write-driven**: it only checks addresses the
DUT wrote. A store the DUT *drops* (SimX wrote it, DUT didn't) is never compared
and never fails. The fault-injection negative test does not cover this case. And
my fix_12 (vacuous-run → warning) means a **total** store loss now passes as a
warning. This must be fixed before Gate-0 can claim "dropped-store fails."

This is your lane (scoreboard). I'm flagging it precisely with the exact lines
and a proposed fix. I did **not** change the comparison logic myself — that's
your design call.

---

## Where it is

### 1. The comparison loop is DUT-driven
[vortex_scoreboard.sv:493-540](../../uvm_env/vortex_scoreboard.sv#L493) —
`compare_all_written()`:
```sv
foreach (shadow_memory[addr]) begin      // ← only addresses the DUT WROTE
    ...
    simx_read_mem(simx_base, 8, simx_bytes);
    if (dut_word === simx_word) num_mem_passed++;
    else                        `uvm_error("SCOREBOARD", "MEM MISMATCH ...");
end
```
If the DUT drops a store at `addr`, there is no `shadow_memory[addr]` entry, so
the loop body never runs for it. The drop is invisible.

### 2. The negative test only proves mismatch detection, not drop detection
[vortex_scoreboard.sv:520](../../uvm_env/vortex_scoreboard.sv#L520):
```sv
// injects ONLY on a word that currently MATCHES
if (inject_fault && !fault_injected && (dut_word === simx_word)) begin
    dut_word = dut_word ^ 64'h1;   // corrupt a DUT-written word
```
This corrupts a word the DUT *did* write. It proves the comparator reports a
mismatch — it never exercises the "SimX wrote, DUT didn't" path.

### 3. My fix_12 widened the hole (please review)
[vortex_scoreboard.sv:712-724](../../uvm_env/vortex_scoreboard.sv#L712):
```sv
else if (total_checks > 0)
    `uvm_info("SCOREBOARD", "SIMULATION PASSED — all checks matched!", ...)
else if (ebreak_seen && simx_ran)
    `uvm_warning("SCOREBOARD",
        "No memory writes to compare — DUT and SimX both completed (pure arithmetic program)")
else
    `uvm_error("SCOREBOARD", "No checks were performed — vacuous run")
```
I added the `ebreak_seen && simx_ran → WARNING` branch so riscv-dv
`riscv_arithmetic_basic_test` (genuinely no data-region stores) stops failing.
But the guard does not distinguish:
- **genuine arithmetic program**: SimX also wrote nothing to the data region → warning is correct
- **total store loss**: SimX wrote results, DUT dropped them all → `shadow_memory`
  empty → `total_checks==0` → **same warning** → silent pass (WRONG)

---

## Proposed fix (your call on the exact shape)

### A. Make the comparison cover SimX's write set, not just the DUT's
The robust black-box check iterates the **union** of written addresses, or at
minimum SimX's data-region writes, and asserts the DUT matched each:

Option A1 — if SimX can enumerate its data-region writes via DPI, iterate that
set and flag any address SimX wrote that `shadow_memory` is missing:
```sv
// pseudo: for each addr SimX wrote in [RAM_BASE, DATA_LIMIT):
foreach (simx_written[addr]) begin
    if (!shadow_memory.exists(addr)) begin
        num_mem_failed++;
        `uvm_error("SCOREBOARD",
            $sformatf("DROPPED STORE  addr=0x%08h  DUT=<none>  SimX=0x%016h", addr, simx_word));
    end else if (shadow_memory[addr] !== simx_word) begin
        ... existing mismatch ...
    end
end
```
Then keep the existing DUT-driven loop to catch *extra* DUT writes (DUT wrote
where SimX didn't), so together they enforce true set equality.

Option A2 — if SimX can't enumerate writes, have the directed tests declare a
**result region** `[base, size]` (you already have `compare_result_region()` at
[line 347](../../uvm_env/vortex_scoreboard.sv#L347)) and require every word in it
to exist in `shadow_memory`. A missing word in the declared region = dropped store
= error, instead of the current `num_skipped++` warning at
[line 377-382](../../uvm_env/vortex_scoreboard.sv#L377).

### B. Tighten the vacuous-run guard
Only treat zero-checks as a pass when **SimX also produced zero data-region
writes**. If SimX wrote to the data region but `shadow_memory` is empty, that is a
total drop → error:
```sv
else if (ebreak_seen && simx_ran && simx_dataregion_writes == 0)
    `uvm_warning("SCOREBOARD", "No data-region writes in DUT or SimX — pure arithmetic program")
else if (ebreak_seen && simx_ran)   // SimX wrote, DUT didn't → all stores dropped
    `uvm_error("SCOREBOARD", "DUT produced no data-region writes but SimX did — stores dropped")
else
    `uvm_error("SCOREBOARD", "No checks were performed — vacuous run")
```
(`simx_dataregion_writes` is whatever signal you can derive from the DPI side —
even a coarse "did SimX touch [RAM_BASE, DATA_LIMIT)" boolean is enough.)

---

## How to verify the fix went red

1. Keep `riscv_arithmetic_basic_test` passing (SimX also wrote nothing → warning).
2. Add a directed drop test: a program that stores a known value, plus a driver/
   monitor hook that **suppresses** that AXI write to the model. Expect:
   `UVM_ERROR ... DROPPED STORE addr=...` and a FAILED run (exit code from
   [simulate.sh](../../scripts/simulate.sh) — T4 already gates on real
   UVM_ERROR, no subtraction, so it will propagate).
3. Confirm the existing `inject_fault` mismatch test still goes red (it tests a
   different path — value corruption — and must keep working).

Once (1)(2)(3) all hold, Gate-0's "dropped-store fails" box is genuinely
satisfiable.

---

## What I did NOT touch
I left `compare_all_written()`, `compare_result_region()`, and the report logic
exactly as they are (other than the fix_12 warning branch I already flagged). The
comparison-direction redesign is your decision. Ping me if you want the directed
drop test or the AXI-write-suppression hook built on my side — that part
(stimulus/driver) is my lane.
