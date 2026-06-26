---
issue: I2
commit: 37cfce55
date: 2026-06-26
author: Samuel Moussa
---

# I2 — Elaboration Asserts: Topology Parameters (NUM_CLUSTERS/CORES/WARPS/THREADS)

## Background

C1 (commit 4c36bd82) added the first elaboration assert: `AXI_TID_W` (UVM config) must equal `VX_MEM_TAG_WIDTH` (RTL package). That covers the signal-width side.

I2 covers the topology side: if you compile the RTL with `NUM_CLUSTERS=1` but then run the simulator with `+NUM_CLUSTERS=2`, every probe, every generate loop, and every UVM component is misconfigured — but simulation would proceed silently and produce garbage results. I2 makes this a hard failure at time=0.

---

## The Risky Scenario I2 Guards Against

The normal flow (`make sim CLUSTERS=2`) is safe — `compile.sh` sets `+define+NUM_CLUSTERS=2` and `simulate.sh` sets `+NUM_CLUSTERS=2` from the same shell variable, so they always match.

The dangerous flow is:
```bash
make sim  CLUSTERS=1  # compiles RTL with `NUM_CLUSTERS=1
# ... someone changes the run command ...
make sim-only CLUSTERS=2  # skips recompile, passes +NUM_CLUSTERS=2 to stale RTL
```
Without I2, this runs silently. The TB's generate loops (I1) iterate once (TB_NUM_CLUSTERS=1 from the macro), the UVM config thinks it has 2 clusters, and results are meaningless.

---

## Files Edited

### `vortex_uvm_env/tb/vortex_tb_top.sv` — added `u_i2_topology_asserts` initial block

Inserted after the C1 assert block (line 706), before the TIMEOUT WATCHDOG section:

```sv
//==========================================================================
// I2 — ELABORATION ASSERTS: UVM plusarg topology == RTL compile-time params
// These fire at time=0 before any UVM phase runs. If +NUM_CLUSTERS=2 but
// the RTL was compiled with `NUM_CLUSTERS=1, the bench is meaningless.
// Pattern: read the plusarg (default = RTL value so single-config runs
// always pass); fatal if the override disagrees with the compiled DUT.
//==========================================================================
initial begin : u_i2_topology_asserts
    int unsigned chk_clusters, chk_cores, chk_warps, chk_threads;

    // Default to the RTL compile-time values so the assert is a no-op
    // when the plusarg is not supplied (single-config baseline run).
    chk_clusters = TB_NUM_CLUSTERS;
    chk_cores    = `NUM_CORES;
    chk_warps    = `NUM_WARPS;
    chk_threads  = `NUM_THREADS;

    void'($value$plusargs("NUM_CLUSTERS=%d", chk_clusters));
    void'($value$plusargs("NUM_CORES=%d",    chk_cores));
    void'($value$plusargs("NUM_WARPS=%d",    chk_warps));
    void'($value$plusargs("NUM_THREADS=%d",  chk_threads));

    assert (chk_clusters == TB_NUM_CLUSTERS)
        else $fatal(1,
            "[I2-ASSERT] NUM_CLUSTERS: plusarg=%0d but RTL compiled with %0d -- recompile with correct `NUM_CLUSTERS",
            chk_clusters, TB_NUM_CLUSTERS);

    assert (chk_cores == `NUM_CORES)
        else $fatal(1,
            "[I2-ASSERT] NUM_CORES: plusarg=%0d but RTL compiled with %0d -- recompile with correct `NUM_CORES",
            chk_cores, `NUM_CORES);

    assert (chk_warps == `NUM_WARPS)
        else $fatal(1,
            "[I2-ASSERT] NUM_WARPS: plusarg=%0d but RTL compiled with %0d -- recompile with correct `NUM_WARPS",
            chk_warps, `NUM_WARPS);

    assert (chk_threads == `NUM_THREADS)
        else $fatal(1,
            "[I2-ASSERT] NUM_THREADS: plusarg=%0d but RTL compiled with %0d -- recompile with correct `NUM_THREADS",
            chk_threads, `NUM_THREADS);

    $display("[I2-ASSERT] Topology OK: %0dCL %0dC %0dW %0dT (RTL == UVM plusargs)",
             TB_NUM_CLUSTERS, `NUM_CORES, `NUM_WARPS, `NUM_THREADS);
end
```

**Why defaulting to the RTL value is correct:**
When a plusarg is not supplied (normal baseline run), `$value$plusargs` returns 0 and does not write to `chk_*`. The defaults are set to the RTL macro values before the plusarg call, so unset plusargs always match — the assert is a no-op. No change in behavior for any existing run that doesn't explicitly pass `+NUM_CLUSTERS`.

---

## Acceptance Check

**Positive path (clean 1CL/1C/4W/4T run):**
```
# [I2-ASSERT] Topology OK: 1CL 1C 4W 4T (RTL == UVM plusargs)
```
Confirmed: `make sim TEST=kernel_launch_test PROGRAM_NAME=hello TIMEOUT=500000` — PASSED, 0 UVM_ERROR.

**Negative path (stale compile):**
```bash
# Simulate with CLUSTERS=2 on RTL compiled with CLUSTERS=1:
make sim-only TEST=kernel_launch_test PROGRAM_NAME=hello CLUSTERS=2
```
Output:
```
# ** Fatal: [I2-ASSERT] NUM_CLUSTERS: plusarg=2 but RTL compiled with 1 -- recompile with correct `NUM_CLUSTERS
```
Confirmed: simulation aborts at time=0 with a clear message.

---

## Teammate Conflicts / Handover

**No conflicts.** `vortex_tb_top.sv` infrastructure is Samuel's lane. The added `initial begin` block is self-contained and does not touch any signal, interface, or generate block used by Ahmad or Steven.

**Ahmad — awareness only:**
The I2 assert fires before any UVM phase runs (time=0). If Ahmad ever runs a test with a misconfigured CLUSTERS/CORES setting on a stale RTL compile, he will see `[I2-ASSERT]` instead of the usual UVM output. The fix is always: recompile the RTL with the correct parameter (`make sim` instead of `make sim-only`).

**Steven — awareness for D-matrix:**
When Steven runs the D-matrix across configurations (1C/1W, 1C/4W, 2C/4W, 2CL/2C/4W), each config requires a full recompile. If Steven automates the matrix with `sim-only` for speed, I2 will catch any case where the recompile was skipped. This is intentional protective behavior — the assert should be left in place.

---

## What's Still Open (Not I2)

I2 does not cover:
- `SOCKET_SIZE` and `ISSUE_WIDTH` — these are RTL-internal (`VX_gpu_pkg` package members), not user-facing plusargs. They cannot be overridden at runtime; the values in the TB generate loops (`TB_SOCK_SIZE`, `TB_ISSUE_W`) are always correct by construction.
- SimX topology mismatch — if SimX is run with different core count than the DUT, results diverge silently. This is I3 (depends on Steven's D-simx).
