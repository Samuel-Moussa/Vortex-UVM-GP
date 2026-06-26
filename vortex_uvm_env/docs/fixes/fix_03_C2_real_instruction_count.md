---
issue: C2
commit: 22115864 (initial); extended by 11f71359 (I1 multi-core)
date: 2026-06-26
author: Samuel Moussa
---

# C2 — Real Instruction Count via Commit Handshake

## Problem

`status_if.instr_count` was being populated with:
```sv
instr_count <= mem_ops / 3;  // fabricated
```
`mem_ops` was an AXI transaction counter. Dividing by 3 was a guess based on rough vecadd profiling — it had no basis in the RTL and would be wrong for any other program. IPC computed from this was meaningless.

The real fix: tap the `commit_arb_if[*].valid && ready` handshake from `VX_commit` — this fires exactly once per retired instruction.

---

## Files Edited

### `vortex_uvm_env/tb/vortex_tb_top.sv`

**Removed fabricated counter:**
```sv
// REMOVED:
if (axi_if.wvalid && axi_if.wready) mem_ops <= mem_ops + 1;
// REMOVED in report:
instr_count <= mem_ops / 3;
```

**Added real commit tap (single-core, commit 22115864):**
```sv
wire tb_commit_fire =
    dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.commit.commit_arb_if[0].valid &&
    dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.commit.commit_arb_if[0].ready;

always_ff @(posedge clk) begin
    if (!reset_n)
        tb_instr_count <= '0;
    else if (tb_commit_fire)
        tb_instr_count <= tb_instr_count + 1;
end
```

**Wired into status interface:**
```sv
assign status_if.instr_count = tb_instr_count;
```

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
