---
title: Engineering Evaluation — Session Fixes (logic & structure, not prose)
date: 2026-06-26
reviewer: Opus review pass
scope: actual UVM/TB/script code that landed this session
---

# Engineering Evaluation — 2026-06-26 Session

This is a review of the **logic and structure** of the fixes, traced through the
real committed code (not the doc text). Verdict per fix, then the concrete
defects with severity and owning lane.

## Verdict table

| Fix | Lane | Logic correct? | Note |
|-----|------|----------------|------|
| C1 — tag width + `$bits` assert | Samuel | ✅ | `$bits(axi_awid[0])` proves UVM param == DUT port width, not just UVM==UVM |
| C2/I1 — commit-tap instr count | Samuel | ✅ | popcount over `commit_arb_if[*].valid&&ready` across all lanes — correct retirement count |
| C3 — ebreak-decode completion (primary) | Samuel | ✅ | fetch-stage decode of `0x00100073`, OR'd across cores |
| C3 — `busy=0` fallback | Samuel | ⚠️ | **Issue 2**: fires on a single cycle of `busy` low → premature completion for non-ebreak kernels with idle gaps |
| I2 — topology elaboration asserts | Samuel | ⚠️ | **Issue 3**: only checks `NUM_*` plusargs, not the `CLUSTERS/CORES/...` aliases the config also reads |
| T4 — honest error gate | Samuel | ✅ | `-2` removal correct once phantom errors root-caused |
| fix_11 — wait_for_completion fast-path | Samuel | ✅ | `cfg.ebreak_event` is triggered by `scoreboard.write_status()`; fast-path handles the already-fired case |
| fix_12 — vacuous-run → warning | Samuel edit in Ahmad's file | ❌ | **Issue 1**: widened a real verification hole (see below) |
| scoreboard `compare_all_written` | Ahmad | ❌ | **Issue 1 root**: DUT-write-driven loop cannot detect dropped stores |

## Defects

### Issue 1 — CRITICAL — scoreboard is blind to dropped stores (Ahmad's lane; fix_12 widened it)

`compare_all_written()` ([vortex_scoreboard.sv:498](../../uvm_env/vortex_scoreboard.sv#L498))
iterates `foreach (shadow_memory[addr])` — **only addresses the DUT wrote**. Each
DUT write is compared against SimX. This catches *wrong values* but is
structurally blind to *missing writes*: a dropped store leaves no `shadow_memory`
entry, so the loop never visits that address and nothing fails.

The fault-injection negative test does **not** cover this. At
[line 520](../../uvm_env/vortex_scoreboard.sv#L520) it flips a word that the DUT
**already wrote and that already matches SimX** — proving "mismatch on a corrupted
DUT word is reported," not "dropped store is caught." Gate-0 explicitly requires
the second claim ("dropped-store fails").

fix_12 (Samuel's edit) converted the zero-checks case to
`ebreak_seen && simx_ran → UVM_WARNING`
([vortex_scoreboard.sv:717](../../uvm_env/vortex_scoreboard.sv#L717)). Consequence:
a program whose stores were **all** dropped (empty `shadow_memory`) now reports
**pass-with-warning** instead of error. **Total store loss = silent pass.**

**Impact:** the black-box "end-state equivalence vs SimX" guarantee is only
half-enforced. Gate-0 sign-off ("dropped-store fails") cannot go red with the
current loop. See the dedicated handover: [HANDOVER_Ahmad_scoreboard_dropped_stores.md](HANDOVER_Ahmad_scoreboard_dropped_stores.md).

### Issue 2 — MEDIUM — `busy=0` fallback completes kernels prematurely (Samuel's lane)

[vortex_tb_top.sv:421](../../tb/vortex_tb_top.sv#L421): the `busy=0` branch latches
`tb_execution_complete` on the **first single cycle** `busy` drops. Any non-ebreak
kernel with a transient idle gap (busy de-asserts between phases) completes early
and runs the comparison on a half-finished program. The idle-threshold fallback
below it (sustained 5000 cycles) is the safe pattern.

**Fixed this session** (see commit log): `busy=0` now requires sustained
de-assertion via a dedicated counter. The ebreak primary path is unchanged, so
ebreak programs are unaffected; non-ebreak programs are now safe.

### Issue 3 — MINOR — I2 assert misses plusarg aliases (Samuel's lane)

The I2 block read only `+NUM_CLUSTERS/CORES/WARPS/THREADS`. The config object also
accepts the `+CLUSTERS/CORES/WARPS/THREADS` aliases
([vortex_config.sv:800](../../uvm_env/vortex_config.sv#L800)). An alias-form
override would diverge from the compiled RTL without the assert catching it.
`simulate.sh` only emits the `NUM_` form, so it isn't hit today.

**Fixed this session**: the assert now checks the `NUM_` form first, then falls
back to the alias form (mirroring the config's own logic).

### Issue 4 — COSMETIC — instr_count counts past ebreak (Samuel's lane)

[vortex_tb_top.sv:395](../../tb/vortex_tb_top.sv#L395) increments unconditionally;
commits that drain after `tb_execution_complete` latches inflate the count/IPC
slightly. Does not affect end-state compare. Left as-is (low value, would
complicate the counter).

## Bottom line

Samuel's infrastructure fixes (C1, C2, C3-primary, I1, I2, T4) are logically
correct and the bench is genuinely more trustworthy than before. Issues 2 and 3
(Samuel's lane) are fixed this session. **Gate-0 sign-off remains blocked** by
Issue 1 (Ahmad's scoreboard comparison direction) and the open INV-1
(vecadd `busy` never idles).
