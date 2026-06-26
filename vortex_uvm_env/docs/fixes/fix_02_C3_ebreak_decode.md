---
issue: C3
commit: 7764ba14 (initial); extended by 11f71359 (I1 multi-core)
date: 2026-06-26
author: Samuel Moussa
---

# C3 — Real EBREAK Decode Drives Completion

## Problem

Completion in `vortex_tb_top.sv` was gated on `!busy` + an idle-cycle threshold. Two problems:
1. The `busy` signal was being checked indirectly via MMIO polling — not reliable for all programs.
2. Some kernels exit via MMIO write (not ebreak), so `busy=0` would be the only path — but `busy` (INV-1) never goes low for vecadd, causing every run to hit TIMEOUT.
3. The original code had a hardcoded PC to detect EBREAK completion — that PC was binary-specific and broke on any recompile.

The real fix: decode the actual EBREAK instruction opcode (`0x00100073`) from the fetch interface. This works regardless of PC address and regardless of which core fetches it.

---

## Files Edited

### `vortex_uvm_env/tb/vortex_tb_top.sv`

**Added constant:**
```sv
localparam [31:0] TB_EBREAK_INSTR = 32'h00100073;
```

**Added combinational wire (single-core, commit 7764ba14):**
```sv
wire tb_ebreak_fetch =
    dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.fetch_if.valid &&
    (dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.fetch_if.data.instr
     == TB_EBREAK_INSTR);
```

**Registered latch (sets once, holds):**
```sv
always_ff @(posedge clk) begin
    if (!reset_n)
        tb_probe_ebreak_seen <= 1'b0;
    else if (!tb_probe_ebreak_seen && tb_ebreak_fetch) begin
        tb_probe_ebreak_seen <= 1'b1;
        $display("[TB_PROBE_EBREAK @ %0t] ebreak fetched", $time);
    end
end
```

**Completion always_ff updated:**
Primary trigger is now `tb_probe_ebreak_seen`. The old `busy=0` + idle-threshold paths demoted to `** Warning:` fallbacks.

```sv
// Primary: EBREAK decoded from fetch interface
if (tb_probe_ebreak_seen && !status_if.ebreak_detected) begin
    status_if.ebreak_detected <= 1'b1;
end
// Fallback (warning): busy went low without ebreak
else if (!vif.busy && idle_counter >= IDLE_THRESHOLD) begin
    `uvm_warning("TB", "Completion via busy=0 fallback — no ebreak seen")
    status_if.ebreak_detected <= 1'b1;
end
```

**Extended in commit 11f71359 (I1):**
`tb_ebreak_fetch` changed from a single-core wire to an OR across all cores via generate loop.
See [fix_05_I1_multicore_probes.md](fix_05_I1_multicore_probes.md) for the generate loop details.

---

## Acceptance Check
- `kernel_launch_test` + `hello.elf`: ebreak fires at a real cycle, `Errors: 0`
- kernels that exit via MMIO (not ebreak): `** Warning: Completion via busy=0 fallback` is printed — this is expected and not an error
- No hardcoded PC in the completion logic

---

## Teammate Conflicts / Handover

**Ahmad:**
`vortex_tb_top.sv` is shared infrastructure. Ahmad's P1-bind (`commit_arb_if[*]` passive monitor) will also be added to this file. Ahmad must be aware that:
- `tb_probe_ebreak_seen` is the authoritative completion signal wired into `status_if.ebreak_detected`
- The `always_ff` completion block is around lines 430–470 (post-commit 11f71359)
- The busy=0 fallback is intentional — do not remove it

**Steven:**
No conflict — Steven's AXI SVA is in separate assertion blocks. The fetch hierarchy tap (`g_clusters[0].cluster...fetch_if`) is inside a `ifdef USE_AXI_WRAPPER` block; Steven's SVA is also inside that ifdef. Merges should be clean but check context lines.

**INV-1 note:**
The vecadd busy-never-low issue is unresolved. For vecadd, EBREAK is the only completion path. If vecadd never issues an ebreak instruction, it will always timeout. This needs investigation separately (see INV-1 in CLAUDE.md).
