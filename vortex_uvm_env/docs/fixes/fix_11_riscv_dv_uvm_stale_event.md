---
issue: riscv-dv sub-issue E — UVM stale event race in wait_for_completion
commit: 2ccef437
date: 2026-06-26
author: Samuel Moussa
---

# riscv-dv Sub-Issue E — UVM Stale Event: wait_trigger() Misses Past Triggers

## Problem

After all the infrastructure fixes (ecall→ebreak, CSR strips, etc.), the program ran and EBREAK was detected — but the test still timed out with:
```
UVM_ERROR ... Timeout after 1000000 cycles!
```

Root cause: the call sequence in `vortex_base_test.sv::run_phase()` is:
```sv
run_test_stimulus();   // sends DCR config sequences; waits internally for some time
wait_for_completion(); // supposed to wait for EBREAK
```

For fast programs (like riscv-dv arithmetic), EBREAK fires while `run_test_stimulus()` is still executing (the DCR sequences take time, but EBREAK fires earlier than expected). By the time `wait_for_completion()` is called, `cfg.ebreak_event` has **already been triggered**.

`uvm_event::wait_trigger()` is **edge-sensitive** — it only returns if the event is triggered **after** the `wait_trigger()` call starts blocking. If the event was triggered before `wait_trigger()` starts, the call blocks forever. This is a fundamental UVM property, not a bug.

Result: `wait_for_completion()` enters `wait_trigger()`, which blocks indefinitely because the event already fired → timeout.

---

## Fix: Fast-Path Check at the Top of wait_for_completion()

### `vortex_uvm_env/uvm_tests/vortex_base_test.sv`

Added a fast-path RTL signal check before entering the `wait_trigger()` path:

```sv
virtual task wait_for_completion();
    // Fast path: run_test_stimulus() may have already waited for EBREAK.
    // wait_trigger() misses past triggers; check the RTL signal directly.
    if (vif.status_if.ebreak_detected) begin
        repeat(5) @(posedge vif.clk);
        `uvm_info(get_type_name(), "EBREAK already detected (fast path)", UVM_LOW)
        return;
    end
    // ... rest of original implementation with wait_trigger() + timeout fork
```

**Why `vif.status_if.ebreak_detected` and not `cfg.ebreak_event.is_on()`?**
- `is_on()` would work if the event had been triggered and never reset. However, `is_on()` reflects the *level* state of the event, which can be unreliable across delta cycles in simulation.
- The RTL signal `status_if.ebreak_detected` is a registered latch (set by `tb_probe_ebreak_seen` in `vortex_tb_top.sv`). It is guaranteed stable at the time `wait_for_completion()` is called (always_ff, clock edge). Checking the RTL signal directly is the most reliable approach.
- The `repeat(5)` buffer after the fast-path return gives AXI transactions and analysis ports time to flush before `check_results()` runs.

---

## Acceptance Check
- Simulation log shows `"EBREAK already detected (fast path)"` instead of `"Timeout after 1000000 cycles!"` for fast programs
- 0 UVM_ERROR for `random_instruction_stress_test` + `riscv_arithmetic_basic_test`
- For slow programs (hello.elf), the fast path is NOT taken (ebreak hasn't fired yet when `wait_for_completion()` is called) — verify the normal `wait_trigger()` path still works

---

## Teammate Conflicts / Handover

**All derived tests inherit this fix safely.** The fast-path only returns early if ebreak is already asserted. For any test where ebreak hasn't fired yet, the fast-path check fails and execution falls through to the original `wait_trigger()` + timeout fork — no change in behavior.

**Ahmad:**
Ahmad's tests extend `vortex_base_test`. If Ahmad's tests call `run_test_stimulus()` in a way that could trigger EBREAK early (e.g., a very short program), the fast-path will fire correctly. Ahmad does not need to change anything.

**Ahmad — conflict note on scoreboard:**
The scoreboard fires `cfg.ebreak_event` when it detects ebreak from the monitor. With the fast-path fix, `check_results()` is called immediately after `wait_for_completion()` returns. If the scoreboard's `ebreak_event` hasn't been triggered yet (Ahmad's monitor is slightly behind), the scoreboard state may not be fully set up. The `repeat(5)` buffer in the fast-path is designed to allow this to settle, but if Ahmad's scoreboard does heavier processing in the ebreak handler, he may need to increase this buffer or add a synchronization point. Flag this to Ahmad.

**Steven:** No conflict.

---

## Design Note: Why is_on() Would Also Work (But RTL is Better)

For completeness: `uvm_event::is_on()` returns 1 if the event has been triggered at least once. Using it as:
```sv
if (cfg.ebreak_event != null && cfg.ebreak_event.is_on()) begin
    // fast path
end
```
would also work. However, `is_on()` can return 1 if the event was triggered by a stale simulation from a previous test iteration (unlikely but possible in multi-test environments). The RTL signal is authoritative and resets on `!reset_n`, making it the safer choice.
