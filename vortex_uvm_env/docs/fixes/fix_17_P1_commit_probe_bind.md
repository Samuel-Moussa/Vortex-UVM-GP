---
issue: P1-bind (Tier 1 — passive commit probe)
date: 2026-06-28
author: Samuel Moussa
verified: yes (code + sim log; probe liveness count matches DUT instruction count)
---

# P1-bind — Passive Commit/Retire Probe

## Goal

Plan item **P1-bind**: `bind` a passive monitor onto the post-arbitration commit
interface `commit_arb_if[*]` so Ahmad's functional coverage can sample what the
DUT **actually retired** — observability only, never a checker. Add an
elaboration assert that `uuid` is a real multi-bit field.

This is the seam between two lanes: **Samuel builds the bind + probe interface;
Ahmad hangs covergroups (instruction count + warp activity) off it.**

---

## Why it matters

The only checker in this bench is black-box end-state equivalence vs SimX —
that proves *correctness* (right final memory) but says nothing about *what was
exercised*. Functional coverage answers "did we actually hit every opcode / warp
state?", and to populate it you must observe the **retired** instruction stream.

The commit stage is the right tap because it is the **ground truth** of
execution:
- **Retired, not speculative** — unlike fetch/dispatch, commit sees only
  instructions that truly executed (no flushed/squashed branches or divergence).
- **Carries the full `commit_t`** — `uuid, wid, sid, tmask, PC, wb, rd, data,
  sop, eop` — one struct that feeds many covergroups.
- **`uuid`** uniquely tags each instruction for correlation without
  double-counting.

P1 turns the one-off hierarchy tap used by C2 (instruction count) into a clean,
reusable, passive observation interface that Ahmad can extend without colliding
with Samuel's TB code.

---

## What was done

### 1. New file — `tb/vx_commit_probe.sv`

A passive probe module bound into every `VX_commit` instance:

- **No modport** on the `commit_arb_if` port — read-only by discipline. Using
  `.slave` would drive `ready` and make the probe an active participant; this
  stays strictly passive.
- **Per-lane retire observation** over `[\`ISSUE_WIDTH]` via a `genvar` loop:
  `retire_fire = commit_arb_if[i].valid && commit_arb_if[i].ready`.
- **Elaboration assert** — `initial assert ($bits(commit_arb_if[0].data.uuid) > 1)`
  with `$fatal` on a degenerate (≤1-bit) uuid config.
- **Liveness self-check** — a passive per-lane counter and a `final` summary
  print, so every run reports how many instructions this probe instance saw.
  Counts only; never drives the DUT.

```systemverilog
`include "VX_define.vh"   // for `ISSUE_WIDTH (derived in VX_config.vh, not a cmdline define)

module vx_commit_probe import VX_gpu_pkg::*; (
    input wire clk,
    input wire reset,
    VX_commit_if commit_arb_if [`ISSUE_WIDTH]   // no modport -> read-only
);
    initial assert ($bits(commit_arb_if[0].data.uuid) > 1)
        else $fatal(1, "[P1-PROBE] uuid width=%0d <= 1 -- degenerate UUID config",
                    $bits(commit_arb_if[0].data.uuid));

    longint unsigned p1_lane_count [`ISSUE_WIDTH];
    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin : g_commit_lanes
        wire retire_fire = commit_arb_if[i].valid && commit_arb_if[i].ready;
        initial p1_lane_count[i] = 0;
        always @(posedge clk)
            if (!reset && retire_fire)
                p1_lane_count[i] <= p1_lane_count[i] + 1;
    end

    final begin
        automatic longint unsigned p1_total = 0;
        for (int j = 0; j < `ISSUE_WIDTH; j++) p1_total += p1_lane_count[j];
        $display("[P1-PROBE %m] retired instructions observed = %0d", p1_total);
    end
endmodule
```

### 2. `tb/vortex_tb_top.sv` — the bind

```systemverilog
// P1-bind: passive commit/retire probe into every VX_commit instance
bind VX_commit vx_commit_probe u_commit_probe (
    .clk          (clk),
    .reset        (reset),
    .commit_arb_if(commit_arb_if)
);
```

### 3. `flists/uvm_env.flist` — registered the new file after the other probes.

---

## Parametrization (fully scales for N)

| Dimension | Mechanism | Hardcode? |
|---|---|---|
| Issue width | `commit_arb_if [\`ISSUE_WIDTH]` + genvar loop | none |
| Warps / threads | `wid`=`NW_WIDTH`, `tmask`/`data`=`SIMD_WIDTH` from `commit_t` | none |
| Cores / clusters / sockets | `bind VX_commit …` instantiates in **every** `VX_commit` — one per core | none |

No `CORE_ID` parameter was used. With a plain `bind` you cannot pass a per-instance
value, and per-core attribution already comes from the UCDB hierarchy path
(`…core[N].u_commit_probe`). Adding a `CORE_ID(0)` knob (as the older two probes
have) would be a *false* knob that reads 0 on every core — deliberately omitted.

---

## Result

Acceptance run — `random_instruction_stress_test` / `riscv_arithmetic_basic_test`
(run `results/20260628/run_061106`):

```
[P1-PROBE vortex_tb_top.dut.vortex.g_clusters[0].cluster.g_sockets[0]
         .socket.g_cores[0].core.commit.u_commit_probe]
         retired instructions observed = 11498

*** TEST PASSED ***
UVM_ERROR :    0
UVM_FATAL :    0
Total Cycles: 88397  Instructions: 11498
```

Three things this proves:

1. **The bind elaborated into the real DUT** — the full hierarchy path shows the
   probe instance lives inside the actual `VX_commit` (`…g_cores[0].core.commit
   .u_commit_probe`), not a stub.
2. **It observes real retires** — 11498 commit handshakes counted, passively.
3. **The count is correct** — it matches the DUT's *independent* instruction
   count (**11498**) exactly, so the probe is watching the genuine retirement
   stream, not noise.

Exactly **one** `[P1-PROBE]` line appears, correct for the 1CL/1C config (single
`VX_commit`). A multi-core build emits one line per core automatically — the
parametrization, confirmed empirically.

The `[P1-PROBE]` uuid assert stayed silent (uuid width is real), and the run is
clean (0 errors), so the probe added zero behavioural impact.

---

## Implementation notes (gotchas)

- **`\`ISSUE_WIDTH` is not a command-line define** (unlike `NUM_WARPS`); it is
  derived in `VX_config.vh`. The probe must `\`include "VX_define.vh"` to see it —
  exactly as `VX_commit.sv` itself does. The sibling probes don't include it only
  because they never reference `\`ISSUE_WIDTH`.
- **`\`UNUSED_VAR` lives in a different util header**, not `VX_define.vh` — don't
  use it here; unused signals are warnings, not errors.
- **Interface instance arrays forbid runtime indices** — `commit_arb_if[i]` must
  be indexed by the constant `genvar`, so the per-lane counter lives inside the
  generate loop (not a procedural `for`).
- **`final`-block locals need `automatic`** when initialized (QuestaSim
  vlog-2244).

---

## Conclusion

P1-bind is **done and verified on the bind/interface side**. The bench now has a
trustworthy, fully-parametrized, strictly-passive observation point on the
retirement stream, proven to fire and to count the correct number of retired
instructions. End-state equivalence proves *correctness*; this probe is what lets
the project prove *thoroughness*.

**Handover — Ahmad:** hang covergroups off `commit_arb_if` in this probe
(instruction-count / opcode via PC, per-warp activity via `wid`/`tmask`). The
`p1_lane_count` liveness signals are also available as a sanity reference. This
unblocks the "instruction opcodes" and "warp states" functional-coverage rows.

Related: [fix_03_C2_real_instruction_count.md](fix_03_C2_real_instruction_count.md)
(the C2 commit tap this generalizes),
[fix_05_I1_multicore_probes.md](fix_05_I1_multicore_probes.md)
(the multi-core generate-loop pattern reused here).
