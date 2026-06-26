---
issue: I1
commit: 11f71359
date: 2026-06-26
author: Samuel Moussa
---

# I1 — Multi-Core Configurability: Generate Loops for Commit + EBREAK Probes

## Problem

After C2 and C3 were implemented, both probes were hardcoded to `cluster[0]/socket[0]/core[0]/lane[0]`. For any config with N > 1 cores or clusters, the other cores' commits were silently dropped and ebreaks from other cores were never detected. This was a critical correctness gap for the configurability goal.

The check: I was asked "is the UVM fully configurable for N cores/clusters/warps/threads?" The answer at that point was no — the probe side only watched core[0].

---

## Files Edited

### `vortex_uvm_env/tb/vortex_tb_top.sv`

#### Module-level declarations replaced

Before:
```sv
wire tb_commit_fire;  // single lane, core[0] only
wire tb_ebreak_fetch; // single core, core[0] only
```

After:
```sv
localparam TB_NUM_CLUSTERS = `NUM_CLUSTERS;
localparam TB_NUM_SOCKETS  = VX_gpu_pkg::NUM_SOCKETS;
localparam TB_SOCK_SIZE    = `SOCKET_SIZE;
localparam TB_ISSUE_W      = `ISSUE_WIDTH;
localparam TB_NUM_CORES_T  = TB_NUM_CLUSTERS * TB_NUM_SOCKETS * TB_SOCK_SIZE;
localparam TB_NUM_LANES    = TB_NUM_CORES_T * TB_ISSUE_W;

wire [TB_NUM_LANES-1:0]   tb_commit_fires_all;
wire [TB_NUM_CORES_T-1:0] tb_ebreak_fetch_all;
wire                       tb_ebreak_fetch;   // OR reduction of all cores
logic [$clog2(TB_NUM_LANES+1)-1:0] tb_commit_count_cyc;

// Popcount: how many lanes committed this clock edge
always_comb begin : u_commit_popcount
    tb_commit_count_cyc = '0;
    for (int _i = 0; _i < TB_NUM_LANES; _i++)
        tb_commit_count_cyc += TB_NUM_LANES'(tb_commit_fires_all[_i]);
end

assign tb_ebreak_fetch = |tb_ebreak_fetch_all;
```

#### Counter update

Before:
```sv
if (tb_commit_fire) tb_instr_count <= tb_instr_count + 1;
```

After:
```sv
tb_instr_count <= tb_instr_count + 64'(tb_commit_count_cyc);
```

#### Generate loop for AXI path (`ifdef USE_AXI_WRAPPER` block)

Before (both in a single assign):
```sv
assign tb_ebreak_fetch_all = dut.vortex.g_clusters[0]...fetch_if.valid && ...;
assign tb_commit_fires_all[0] = dut.vortex.g_clusters[0]...commit_arb_if[0].valid && ...;
```

After (full generate loop, AXI path):
```sv
genvar _cl, _sk, _co, _lw;
generate
    for (_cl = 0; _cl < TB_NUM_CLUSTERS; _cl++) begin : g_axi_cl
        for (_sk = 0; _sk < TB_NUM_SOCKETS; _sk++) begin : g_axi_sk
            for (_co = 0; _co < TB_SOCK_SIZE; _co++) begin : g_axi_co
                localparam _CORE_IDX = _cl * TB_NUM_SOCKETS * TB_SOCK_SIZE
                                     + _sk * TB_SOCK_SIZE + _co;
                localparam _LANE_BASE = _CORE_IDX * TB_ISSUE_W;
                assign tb_ebreak_fetch_all[_CORE_IDX] =
                    dut.vortex.g_clusters[_cl].cluster
                        .g_sockets[_sk].socket
                        .g_cores[_co].core.fetch_if.valid &&
                    (dut.vortex.g_clusters[_cl].cluster
                        .g_sockets[_sk].socket
                        .g_cores[_co].core.fetch_if.data.instr == TB_EBREAK_INSTR);
                for (_lw = 0; _lw < TB_ISSUE_W; _lw++) begin : g_axi_lw
                    assign tb_commit_fires_all[_LANE_BASE + _lw] =
                        dut.vortex.g_clusters[_cl].cluster
                            .g_sockets[_sk].socket
                            .g_cores[_co].core.commit.commit_arb_if[_lw].valid &&
                        dut.vortex.g_clusters[_cl].cluster
                            .g_sockets[_sk].socket
                            .g_cores[_co].core.commit.commit_arb_if[_lw].ready;
                end
            end
        end
    end
endgenerate
```

**Non-AXI path** (inside `else` of `ifdef USE_AXI_WRAPPER`) is identical, with generate block names `g_mem_cl`, `g_mem_sk`, `g_mem_co`, `g_mem_lw` and DUT path `dut.g_clusters[...]` (no `.vortex` wrapper).

#### EBREAK latch updated (both AXI and non-AXI paths)

Before:
```sv
if (!tb_probe_ebreak_seen && fetch_valid && (fetch_instr == TB_EBREAK_INSTR)) begin
```

After:
```sv
if (!tb_probe_ebreak_seen && tb_ebreak_fetch) begin
    // tb_ebreak_fetch is already the OR of all cores (see generate loop)
    $display("[TB_PROBE_EBREAK @ %0t] ... (core[0] PC shown; any core triggered)", ...);
```

Note: the PC display wire still points to core[0] — this is intentional telemetry, not pass/fail.

---

## Acceptance Check
- Primary config (1CL/1C/4W/4T): `TB_NUM_LANES=1`. Generate loop iterates once. Behaviour identical to pre-I1. No regression.
- `hello.elf` kernel_launch_test: PASS
- `random_instruction_stress_test` with `riscv_arithmetic_basic_test`: PASS (0 UVM_ERROR)

---

## Teammate Conflicts / Handover

**Ahmad (P1-bind — critical handover):**
Ahmad's next task is to add a `bind` module on `commit_arb_if[*]` for coverage. The generate loop structure above defines how to reach each lane. Ahmad must use the same parameterization:
- `TB_NUM_CLUSTERS`, `TB_NUM_SOCKETS`, `TB_SOCK_SIZE`, `TB_ISSUE_W` are localparams already declared in `vortex_tb_top.sv`
- The bind would be inside the innermost `for (_lw)` loop, or Ahmad can write a separate generate block after the existing one
- Ahmad should NOT add a second `genvar` declaration — `_cl, _sk, _co, _lw` are already declared at module scope

**Steven (AXI SVA — merge warning):**
The generate loop is added inside the `ifdef USE_AXI_WRAPPER` probe section of `vortex_tb_top.sv`, roughly lines 471–620 at commit 11f71359. Steven's AXI SVA is also in or near this `ifdef` block. When Steven merges his branch:
- Check for duplicate `genvar` declarations
- Check that the generate block names (`g_axi_cl`, `g_axi_sk`, etc.) don't conflict with any blocks Steven added
- The hierarchy path (`dut.vortex.g_clusters[...]`) must match whatever DUT instantiation name Steven has confirmed

**I1 remaining gap (not Samuel's lane):**
SimX is not yet invoked with multi-core params at runtime. When you run `make sim ... --clusters 2 --cores 2`, the UVM side now correctly probes all 4 cores, but SimX still runs with the default 1-core config. This depends on Steven's D-simx task (I3).

**I2 (Samuel's next task — still open):**
The generate loops make multi-core probing correct, but the elaboration asserts for `NUM_CLUSTERS`, `NUM_CORES`, `NUM_WARPS`, `NUM_THREADS` are not yet added. Only `AXI_TID_W` (C1) has an assert. I2 must add `initial begin $fatal` blocks for the count parameters to catch mismatches loudly.
