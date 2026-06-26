---
issue: C2
commit: 22115864 (initial); extended by 11f71359 (I1 multi-core)
date: 2026-06-26
author: Samuel Moussa
---

# C2 — Real Instruction Count via Commit Handshake

## Problem

`tb_instr_count` was being incremented by a fabricated heuristic tied to the
memory-op counter:
```sv
if (tb_mem_ops % 3 == 0) tb_instr_count <= tb_instr_count + 1;  // fabricated: +1 every 3rd mem op
```
`tb_mem_ops` counts AXI/mem handshakes. Bumping the instruction count once every
3 memory ops was a guess with no basis in the RTL — wrong for any program. IPC
derived from it was meaningless.

The real fix: tap the `commit_arb_if[*].valid && ready` handshake from
`VX_commit` — this fires exactly once per retired instruction.

---

## Files Edited (code copied verbatim from commit 22115864)

### `vortex_uvm_env/tb/vortex_tb_top.sv`

**Removed fabricated counter (the single removed line in the diff):**
```sv
// REMOVED:
if (tb_mem_ops % 3 == 0) tb_instr_count <= tb_instr_count + 1;
```

**Added real commit tap.** Module-level wire + counter increment:
```sv
wire tb_commit_fire;   // C2: real commit handshake from VX_commit.commit_arb_if[0]
// ...in the always_ff:
// C2: real retired instruction count from VX_commit.commit_arb_if[0]
if (tb_commit_fire) tb_instr_count <= tb_instr_count + 1;
```

The hierarchy tap (AXI path), copied verbatim:
```sv
// C2: real retired count — commit_arb_if[0] is the single-issue-lane commit bus
// (ISSUE_WIDTH=UP(NUM_WARPS/16)=1 for default 4W config). Instance: VX_core.commit.
assign tb_commit_fire =
    dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.commit.commit_arb_if[0].valid &&
    dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.commit.commit_arb_if[0].ready;
```

Non-AXI path uses the same instance name without the `.vortex` wrapper:
```sv
assign tb_commit_fire =
    dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.commit.commit_arb_if[0].valid &&
    dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.commit.commit_arb_if[0].ready;
```

**Status wiring** (`vif.status_if.instr_count` is assigned from `tb_instr_count`
in the existing continuous-assign block — unchanged by C2).

**Extended in commit 11f71359 (I1):**
Single `tb_commit_fire` replaced with `tb_commit_fires_all[TB_NUM_LANES-1:0]` + popcount accumulator.
The counter now increments by the number of lanes that committed in the same clock cycle.
```sv
tb_instr_count <= tb_instr_count + 64'(tb_commit_count_cyc);
```
See [fix_05_I1_multicore_probes.md](fix_05_I1_multicore_probes.md) for the generate loop details.

---

## Acceptance Check
- vecadd 100k cycles: `Instructions=12798`, `IPC=0.128` — real numbers, not mem_ops/3
- SimX RAM verification: PASSED (end-state match)
- `kernel_launch_test` with `hello.elf`: Errors: 0

---

## Teammate Conflicts / Handover

**Ahmad (P1-bind coupling):**
C2 was listed as coupling with Ahmad's P1 sampling. The current implementation taps `commit_arb_if[0].valid&&ready` directly from TB — no UVM monitor is involved. Ahmad's P1-bind task is to add a **passive bind module** on `commit_arb_if[*]` for coverage sampling. That is a separate task from C2. The TB tap is observability-only; Ahmad's bind will add an additional passive observer on the same interface. They do not conflict — two readers on a wire.

**Ahmad — handover task for P1-bind:**
The commit interface path is:
```
dut.vortex.g_clusters[cl].cluster.g_sockets[sk].socket.g_cores[co].core.commit.commit_arb_if[lw]
```
The generate loop parameters are `TB_NUM_CLUSTERS`, `TB_NUM_SOCKETS`, `TB_SOCK_SIZE`, `TB_ISSUE_W` (all localparams in `vortex_tb_top.sv`). Ahmad's bind module should use these same dimensions. The `initial assert ($bits(uuid) > 1)` is also part of P1-bind and is not yet implemented.

**Steven:** No conflict.
