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

## Files Edited (code copied verbatim from commit 7764ba14)

### `vortex_uvm_env/tb/vortex_tb_top.sv`

**Module-level declarations added:**
```sv
logic        tb_probe_ebreak_seen;   // C3: registered — set when ebreak first seen at fetch
wire         tb_ebreak_fetch;        // C3: combinational — same-cycle ebreak detect
```

**Constant + combinational wire (inside the probe block; uses the existing
`fetch_valid`/`fetch_instr` display taps that point at core[0] at this commit):**
```sv
localparam [31:0] TB_EBREAK_INSTR   = 32'h00100073;
// C3: drive module-level wire — same-cycle ebreak detection
assign tb_ebreak_fetch = fetch_valid && (fetch_instr == TB_EBREAK_INSTR);
```

**Registered latch (sets once on first ebreak fetch):**
```sv
if (!tb_probe_ebreak_seen && fetch_valid && (fetch_instr == TB_EBREAK_INSTR)) begin
    tb_probe_ebreak_seen <= 1'b1;
    // ... $display ...
end
```

**Completion `always_ff` — note the real signal is `tb_execution_complete`,
NOT `status_if.ebreak_detected` directly:**
```sv
// C3 PRIMARY: ebreak (0x00100073) decoded at fetch stage
// tb_ebreak_fetch is combinational (same-cycle); tb_probe_ebreak_seen is registered
// (latched one cycle earlier) — either fires the primary path.
if (tb_execution_started && !tb_execution_complete && (tb_ebreak_fetch || tb_probe_ebreak_seen)) begin
    tb_execution_complete <= 1;
    $display("\n╔═══════════════════════════════════════════════════╗");
    $display("║  EXECUTION COMPLETE (ebreak 0x00100073 decoded)  ║");
    $display("╚═══════════════════════════════════════════════════╝");
// C3 FALLBACK 1: busy=0 without ebreak — should not happen in a correct run
end else if (tb_execution_started && !tb_execution_complete && !vif.status_if.busy) begin
    tb_execution_complete <= 1;
    $display("\n** Warning: [TB_TOP @ %0t] EXECUTION COMPLETE via busy=0 fallback — ebreak not decoded", $time);
// C3 FALLBACK 2: idle threshold — program may be hung
end else if (tb_execution_started && !tb_execution_complete &&
             tb_idle_cycles >= idle_threshold_val) begin
    tb_execution_complete <= 1;
    $display("\n** Warning: [TB_TOP @ %0t] EXECUTION COMPLETE via idle safety net (%0d cyc) — ebreak not decoded", ...);
end
```

`status_if.ebreak_detected` is a *separate* continuous assign downstream:
```sv
assign vif.status_if.ebreak_detected = tb_execution_complete && axi_channels_idle && mem_channels_idle;
```
So the primary trigger sets `tb_execution_complete`, which (once the bus
drains) drives `ebreak_detected` that the UVM side waits on.

**Extended in commit 11f71359 (I1):**
At commit 7764ba14, `tb_ebreak_fetch` was driven from the core[0] `fetch_valid`/
`fetch_instr` display taps. I1 (11f71359) replaced that with an OR across all
cores: `assign tb_ebreak_fetch = |tb_ebreak_fetch_all;` fed by a generate loop.
See [fix_05_I1_multicore_probes.md](fix_05_I1_multicore_probes.md).

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
