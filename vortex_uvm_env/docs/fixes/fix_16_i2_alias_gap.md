---
issue: Issue 3 (Opus review finding)
commit: 19c3d558
date: 2026-06-26
author: Samuel Moussa
verified-against-commit: yes (code copied from the actual edit + sim log)
---

# Issue 3 — I2 Elaboration Assert Missed the Plusarg Aliases

## Problem

The I2 topology assert (`u_i2_topology_asserts`, added in fix_13) reads the four
topology plusargs and compares them against the compiled RTL macros. It only
read the `NUM_*` form:

```sv
// BEFORE:
void'($value$plusargs("NUM_CLUSTERS=%d", chk_clusters));
void'($value$plusargs("NUM_CORES=%d",    chk_cores));
void'($value$plusargs("NUM_WARPS=%d",    chk_warps));
void'($value$plusargs("NUM_THREADS=%d",  chk_threads));
```

But the UVM config object accepts **both** the `NUM_*` form and short aliases
([vortex_config.sv:800-814](../../uvm_env/vortex_config.sv#L800)):

```sv
if ($value$plusargs("NUM_CLUSTERS=%d", tmp) ||
    $value$plusargs("CLUSTERS=%d",     tmp))
    num_clusters = tmp;
// ... same for CORES / WARPS / THREADS
```

So if someone ran with the **alias** form (`+CLUSTERS=2` instead of
`+NUM_CLUSTERS=2`), the config object would pick up `num_clusters=2` while the
I2 assert read its default (the RTL macro value) and **silently passed** — the
exact mismatch I2 exists to catch would slip through.

Not hit today (the `simulate.sh` flow only emits the `NUM_*` form via
`--clusters → +NUM_CLUSTERS`), but the guard was incomplete: a hand-run with the
alias, or a future script that uses the short form, would defeat it.

---

## Fix (code copied verbatim from commit 19c3d558)

### `vortex_uvm_env/tb/vortex_tb_top.sv`

Check the `NUM_*` form first; if absent, fall back to the alias — mirroring the
config object's own `||` logic so both paths reach the same assert:

```sv
// AFTER:
// Issue 3: accept both the NUM_* form and the short aliases the config
// object reads (vortex_config.sv apply_plusargs). Check NUM_* first; if
// absent, fall back to the alias so an alias-form override is also caught.
if (!$value$plusargs("NUM_CLUSTERS=%d", chk_clusters))
    void'($value$plusargs("CLUSTERS=%d", chk_clusters));
if (!$value$plusargs("NUM_CORES=%d", chk_cores))
    void'($value$plusargs("CORES=%d", chk_cores));
if (!$value$plusargs("NUM_WARPS=%d", chk_warps))
    void'($value$plusargs("WARPS=%d", chk_warps));
if (!$value$plusargs("NUM_THREADS=%d", chk_threads))
    void'($value$plusargs("THREADS=%d", chk_threads));
```

The defaults are still pre-set to the RTL macro values (from fix_13), so when
neither form is supplied the assert remains a no-op.

---

## Acceptance Check

- `make sim TEST=kernel_launch_test PROGRAM_NAME=hello` → still prints
  `[I2-ASSERT] Topology OK: 1CL 1C 4W 4T`, PASS, 0 errors (NUM_* path intact).
- `make sim-only TEST=kernel_launch_test PROGRAM_NAME=hello CLUSTERS=2` on
  1-cluster RTL → still aborts:
  `** Fatal: [I2-ASSERT] NUM_CLUSTERS: plusarg=2 but RTL compiled with 1`
  (the `--clusters` flow emits `+NUM_CLUSTERS`, exercising the primary check).
- A direct `+CLUSTERS=2` (alias) on stale RTL would now also be caught — the new
  fallback branch reads it where before it read the default and passed.

---

## Teammate Conflicts / Handover

**No conflicts.** `vortex_tb_top.sv` assert block is Samuel's lane.

**Ahmad / Steven — awareness:**
If either runs with the short alias plusargs (`+CLUSTERS/+CORES/+WARPS/+THREADS`),
the I2 assert now validates them against the compiled RTL just like the `NUM_*`
form. No action needed — this only closes a gap, never adds a new failure for a
correctly-matched config.

Related: [fix_13_I2_elaboration_asserts.md](fix_13_I2_elaboration_asserts.md)
(the original I2 assert this extends).
