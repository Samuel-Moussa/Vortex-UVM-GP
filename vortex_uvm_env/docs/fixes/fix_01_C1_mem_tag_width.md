---
issue: C1 + ISS-01
commit: 4c36bd82
date: 2026-06-26
author: Samuel Moussa
verified-against-commit: yes (code blocks below copied from the actual diff)
---

# C1 — VX_MEM_TAG_WIDTH from RTL + ISS-01 Hex Load Address Overflow

## Problem

### C1 — Hardcoded and wrong tag width
`vortex_uvm_env/uvm_env/vortex_config.sv` hardcoded the memory tag width and
the comments claimed it was `8` (the old `L3_MEM_TAG_WIDTH`), while the actual
parameter value had been bumped to `50` with a "will be parameterized later"
note. Two problems:
1. The value `50` was a magic number with no link to the RTL.
2. If the RTL's real `VX_gpu_pkg::VX_MEM_TAG_WIDTH` changed, the UVM bench would
   silently keep using the stale literal — no assertion would catch it.

### ISS-01 — Hex load address overflow
`vortex_uvm_env/scripts/prepare.sh` ran `objcopy --change-addresses=$STARTUP_ADDR`
on an ELF **already linked at 0x80000000**. That produced `@80000000` section
markers in the Verilog hex. `mem_model` then adds its `baseaddr=0x80000000` on
top → `0x80000000 + 0x80000000 = 0x100000000` → 33-bit overflow → empty RAM →
X-propagation in the DUT.

---

## Files Edited (code copied verbatim from commit 4c36bd82)

### `vortex_uvm_env/uvm_env/vortex_config.sv`

The actual parameter change:
```sv
// BEFORE:
parameter VX_MEM_TAG_WIDTH    = 50;   //will be paramterized later to L3_MEM_TAG_WIDTH (VX_define.vh)

// AFTER:
parameter VX_MEM_TAG_WIDTH    = VX_gpu_pkg::VX_MEM_TAG_WIDTH; // derived from RTL — never hardcode
```

The dependent AXI param comment fixed:
```sv
// BEFORE:
parameter AXI_ID_WIDTH   = VX_MEM_TAG_WIDTH;    // 8
// AFTER:
parameter AXI_ID_WIDTH   = VX_MEM_TAG_WIDTH;    // = VX_gpu_pkg::VX_MEM_TAG_WIDTH (NOT 8)
```

The header comment block (lines ~37–55) changed from claiming a fixed `8 bits`
to documenting the derived chain (`L3_MEM_TAG_WIDTH → L2 → L1 arb →
DCACHE/ICACHE NC`, "Example: 1CL/1C/4W/4T debug build → 50").

The two overwrite-guard `uvm_fatal` messages were upgraded from a static
"(8)" string to a `$sformatf` that prints the real derived value:
```sv
// BEFORE:
`uvm_fatal("VORTEX_CFG", "mem_tag_width overwritten! Must equal VX_MEM_TAG_WIDTH (8)")
// AFTER:
`uvm_fatal("VORTEX_CFG", $sformatf("mem_tag_width overwritten! Must equal VX_MEM_TAG_WIDTH=%0d (derived from VX_gpu_pkg)", VX_MEM_TAG_WIDTH))
```
(Same transformation applied to the `AXI_ID_WIDTH overwritten!` fatal.)

### `vortex_uvm_env/tb/vortex_tb_top.sv` — elaboration assert (added)

```sv
//==========================================================================
// C1 — ELABORATION ASSERT: UVM VX_MEM_TAG_WIDTH == RTL VX_MEM_TAG_WIDTH
// Both are derived from VX_gpu_pkg::VX_MEM_TAG_WIDTH. The first check
// catches any future regression where someone re-hardcodes the UVM param.
// The $bits check is the structural proof: DUT port width == UVM param.
//==========================================================================
initial begin : u_c1_tag_width_assert
    assert (vortex_config_pkg::VX_MEM_TAG_WIDTH == VX_gpu_pkg::VX_MEM_TAG_WIDTH)
        else $fatal(1, "[C1-ASSERT] VX_MEM_TAG_WIDTH: UVM_pkg=%0d RTL_pkg=%0d -- check vortex_config.sv",
                    vortex_config_pkg::VX_MEM_TAG_WIDTH, VX_gpu_pkg::VX_MEM_TAG_WIDTH);
`ifdef USE_AXI_WRAPPER
    assert ($bits(axi_awid[0]) == vortex_config_pkg::VX_MEM_TAG_WIDTH)
        else $fatal(1, "[C1-ASSERT] DUT AXI awid width=%0d bits but UVM VX_MEM_TAG_WIDTH=%0d",
                    $bits(axi_awid[0]), vortex_config_pkg::VX_MEM_TAG_WIDTH);
`endif
end
```
Note: `AXI_TID_W` (the localparam at `vortex_tb_top.sv:181`,
`= vortex_config_pkg::VX_MEM_TAG_WIDTH`) is what sizes the AXI ID signals; the
assert proves it equals the DUT's real port width via `$bits(axi_awid[0])`.

### `vortex_uvm_env/scripts/prepare.sh` — ISS-01 (real fix)

The fix was NOT a printf format change. It removed the buggy
`--change-addresses` and instead remaps the hex section markers down by the
link base, plus strips CRLF:

```bash
# BEFORE (buggy): objcopy shifted an already-0x80000000-linked ELF up again
                --change-addresses=$STARTUP_ADDR \
# ...then an error-out check that just told the user what to do manually.

# AFTER: no --change-addresses; ELF is already at 0x80000000.
#   Strip CRLF, then remap @80XXXXXX → @00XXXXXX so mem_model's baseaddr
#   lands it correctly instead of overflowing to 0x100000000.
tr -d '\r' < "$PROGRAM_HEX" > "${PROGRAM_HEX}.tmp" && mv "${PROGRAM_HEX}.tmp" "$PROGRAM_HEX"
if [[ "$(head -1 "$PROGRAM_HEX")" == "@80000000" ]]; then
    sed -i 's/^@80/@00/' "$PROGRAM_HEX"
    print_info "Remapped @80XXXXXX → @00XXXXXX for all sections (ELF linked at 0x80000000)"
fi
```

---

## Acceptance Check
- Elaboration prints the `[C1-ASSERT]` checks passing (no `$fatal`); reported
  `AXI_TID_W` = the true derived value (50 in the debug build)
- `kernel_launch_test` with `hello` → PASS, Errors: 0, AXI_TID_W=50
- Hex no longer starts with `@80000000` after remap → RAM populated, no X-prop

---

## Teammate Conflicts / Handover

**No conflicts.** Both files are in Samuel's infrastructure lane.

**Ahmad — note for I2 (now done, see fix_13):**
The C1 assert covers tag width only. The topology-count asserts (NUM_CLUSTERS
etc.) were added separately in I2 (`u_i2_topology_asserts`). The C1 block is the
template both follow.

**Steven — note:**
`prepare.sh` hex handling is Samuel's lane. If D-simx changes how the ELF is
linked or loaded, re-check the `@80→@00` remap assumption — it depends on the
ELF being linked at exactly 0x80000000 and `mem_model` adding that baseaddr.
