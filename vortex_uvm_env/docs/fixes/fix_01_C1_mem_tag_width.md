---
issue: C1 + ISS-01
commit: 4c36bd82
date: 2026-06-26
author: Samuel Moussa
---

# C1 — VX_MEM_TAG_WIDTH + ISS-01 Hex Load Address Overflow

## Problem

### C1 — Hardcoded and wrong tag width
`vortex_uvm_env/config/vortex_config.sv` had:
```sv
localparam AXI_TID_W = 50;  // 8 — comment lied, value was hardcoded
```
Two problems:
1. The comment claimed 8, the value was 50 — no one knew which was right.
2. If the RTL ever changed `VX_MEM_TAG_WIDTH`, the UVM bench would silently use the wrong width without any assertion failing at elaboration.

### ISS-01 — Hex load address overflow
`vortex_uvm_env/scripts/prepare.sh` passed a raw decimal to `$readmemh` which wrapped on addresses > 2^31, corrupting the hex file load.

---

## Files Edited

### `vortex_uvm_env/config/vortex_config.sv`

Before:
```sv
localparam AXI_TID_W = 50;  // 8
```

After:
```sv
localparam AXI_TID_W = VX_gpu_pkg::VX_MEM_TAG_WIDTH;
```

The value is now derived from the RTL package — if the RTL changes, the bench changes automatically.

### `vortex_uvm_env/tb/vortex_tb_top.sv`

Added elaboration assert at module top (after parameter declarations):
```sv
// [C1-ASSERT] UVM tag width must match RTL tag width
initial begin
    if (AXI_TID_W !== VX_gpu_pkg::VX_MEM_TAG_WIDTH)
        $fatal(1, "[C1-ASSERT] AXI_TID_W=%0d != VX_MEM_TAG_WIDTH=%0d — UVM config mismatch",
               AXI_TID_W, VX_gpu_pkg::VX_MEM_TAG_WIDTH);
    $display("[C1-ASSERT] AXI_TID_W=%0d matches VX_MEM_TAG_WIDTH — OK", AXI_TID_W);
end
```

### `vortex_uvm_env/scripts/prepare.sh`

Before (ISS-01):
```bash
STARTUP_ADDR_HEX=$(printf "%d" "$STARTUP_ADDR")   # wrong — decimal, overflows
```

After:
```bash
STARTUP_ADDR_HEX=$(printf "0x%x" "$STARTUP_ADDR")  # hex, no overflow
```

---

## Acceptance Check
- Elaboration prints `[C1-ASSERT] AXI_TID_W=50 matches VX_MEM_TAG_WIDTH — OK`
- No `[C1-ASSERT]` fatal
- `kernel_launch_test` with `hello.elf` passes: Errors: 0

---

## Teammate Conflicts / Handover

**No conflicts.** This is Samuel's infra lane.

**Ahmad — note for I2 expansion:**
The C1 assert covers tag width only. I2 (open) must add similar assertions for `NUM_CLUSTERS`, `NUM_CORES`, `NUM_WARPS`, `NUM_THREADS`. The pattern to follow is exactly the `initial begin ... $fatal` block added here in `vortex_tb_top.sv`. Ahmad does not need to touch this for his work.

**Steven — note:**
`prepare.sh` is in Samuel's lane. If Steven's D-simx changes how programs are loaded, he should check that `STARTUP_ADDR_HEX` is still passed correctly to his SimX runtime invocation.
