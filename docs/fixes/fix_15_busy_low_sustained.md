---
issue: Issue 2 (Opus review finding)
commit: 19c3d558
date: 2026-06-26
author: Samuel Moussa
verified-against-commit: yes (code copied from the actual edit + sim log)
---

# Issue 2 — busy=0 Completion Must Be Sustained, Not a Single-Cycle Glitch

## Problem

The C3 completion logic in `vortex_tb_top.sv` has three triggers, checked in
order: (1) ebreak decoded at fetch [primary], (2) `busy==0` [fallback], (3) idle
threshold [fallback]. The `busy==0` fallback fired on the **first single cycle**
`vif.status_if.busy` went low:

```sv
// BEFORE (vortex_tb_top.sv:421):
end else if (tb_execution_started && !tb_execution_complete && !vif.status_if.busy) begin
    tb_execution_complete <= 1;
    $display("\n** Warning: ... EXECUTION COMPLETE via busy=0 fallback ...");
```

For any program that does **not** end with ebreak (e.g. kernels that exit via an
MMIO write), `busy==0` is the intended completion path. But `busy` can also drop
to 0 **transiently** mid-execution — between kernel phases, during a pipeline
drain, or a barrier. A single such cycle would latch `tb_execution_complete` and
run the SimX comparison on a **half-finished** program → spurious mismatch or
truncated result.

The idle-threshold fallback right below it already used the safe pattern
(sustained `tb_idle_cycles >= 5000`). The `busy==0` branch did not.

This was a latent trap: the ebreak primary path is checked first, so all
ebreak-terminating tests (riscv-dv) never reached this branch and never exposed
it. Only non-ebreak kernels with idle gaps are at risk.

---

## Fix (code copied verbatim from commit 19c3d558)

### `vortex_uvm_env/tb/vortex_tb_top.sv`

**1. New threshold (configurable via `+BUSY_LOW_THRESHOLD`, default 100):**
```sv
int idle_threshold_val = 5000;
// Issue 2 fix: busy=0 completion must be SUSTAINED, not a single-cycle glitch.
// A transient busy de-assertion between kernel phases must NOT end the test.
int busy_low_threshold_val = 100;
initial begin
    int tmp;
    if ($value$plusargs("IDLE_THRESHOLD=%d", tmp))     idle_threshold_val     = tmp;
    if ($value$plusargs("BUSY_LOW_THRESHOLD=%d", tmp)) busy_low_threshold_val = tmp;
end
```

**2. New consecutive-low counter (declared with the other tb_ signals):**
```sv
int          tb_busy_low_cycles;     // Issue 2: consecutive cycles with busy==0
```

**3. Counter update in the main `always_ff` (reset on any busy-high cycle so a
transient gap can never accumulate):**
```sv
// reset block:
tb_busy_low_cycles    <= 0;
// ...in the else (running) block:
// Issue 2: track SUSTAINED busy de-assertion. Reset on any busy-high
// cycle so a transient gap can never accumulate to the threshold.
if (tb_execution_started && !tb_execution_complete && !vif.status_if.busy)
    tb_busy_low_cycles <= tb_busy_low_cycles + 1;
else
    tb_busy_low_cycles <= 0;
```

**4. Fallback now gated on the sustained count:**
```sv
// AFTER (FALLBACK 1):
end else if (tb_execution_started && !tb_execution_complete &&
             tb_busy_low_cycles >= busy_low_threshold_val) begin
    tb_execution_complete <= 1;
    $display("\n** Warning: [TB_TOP @ %0t] EXECUTION COMPLETE via sustained busy=0 fallback (%0d cyc) — ebreak not decoded",
             $time, busy_low_threshold_val);
```

**Why no false negatives:** if a program genuinely completed, `busy` stays low,
so the counter keeps incrementing and crosses the threshold after
`busy_low_threshold_val` cycles. Completion is only *delayed* by the threshold,
never missed. A transient gap shorter than the threshold is correctly ignored.

---

## Acceptance Check

`make sim TEST=kernel_launch_test PROGRAM_NAME=hello TIMEOUT=500000`
(hello exits via MMIO, not ebreak → uses this fallback):
```
# [I2-ASSERT] Topology OK: 1CL 1C 4W 4T (RTL == UVM plusargs)
# ** Warning: [TB_TOP @ 74985000] EXECUTION COMPLETE via sustained busy=0 fallback (100 cyc) — ebreak not decoded
# *** TEST PASSED ***
# UVM_ERROR :    0   UVM_FATAL :    0
```
PASS, 0 errors — the fallback now reports "sustained busy=0 fallback (100 cyc)"
instead of firing on the first low cycle. ebreak-terminating tests (riscv-dv)
are unaffected (primary path checked first).

---

## Teammate Conflicts / Handover

**No conflicts.** `vortex_tb_top.sv` completion logic is Samuel's lane.

**Ahmad / Steven — awareness:**
- The new `+BUSY_LOW_THRESHOLD=N` plusarg tunes how many sustained busy-low
  cycles count as completion (default 100). If a directed test has a known long
  internal idle phase, bump it.
- This does not affect the ebreak primary path or `status_if.ebreak_detected`
  wiring — only the non-ebreak fallback.
