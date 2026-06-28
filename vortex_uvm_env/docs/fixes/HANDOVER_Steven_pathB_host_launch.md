---
handover: Path B host-driven launch + half-built host sequences → Steven
from: Samuel Moussa
date: 2026-06-28
status: SCAFFOLDING EXISTS — needs the launch protocol + SimX mirroring
unites: this (Bucket b host sequences) + your INV-1 handover (hostless completion)
related: HANDOVER_Steven_INV1_wspawn_tmc.md, INV1_kernel_completion_hang.md, plan item PathB-launch
---

# Handover — Steven (united): make real kernels run end-to-end

This is a **united** handover. You already hold **INV-1** (hostless kernels hang
in `wspawn`/`vx_tmc`). This adds the second half of the same theme — **Path B:
host-driven kernel launch** for the `tests/regression/*` suite — and points you at
the **half-built host sequences** (dead-sequence audit Bucket b) that are its
scaffolding. Both threads are "get a real Vortex program to run and finish through
the bench + SimX." Keeping them together avoids two people touching the same launch
path.

---

## Two related threads, one goal

| Thread | What it is | Status |
|---|---|---|
| **INV-1** (your handover) | hostless `tests/kernel/*` kernels run but never complete (`wspawn`'d warps parked at `vx_tmc zero`) | root-caused → needs waveform/SimX divergence |
| **Path B** (this handover) | host-driven `tests/regression/*` (sgemm/sort/…) can't even launch — no host runtime in the bench | scaffolding exists, launch protocol unbuilt |

INV-1 is "completion of programs we *can* launch"; Path B is "launching the
programs we *can't* yet." Together they're the full "real kernels run" story.

---

## Why the regression suite needs Path B (recap)
`tests/regression/*` are **host-driven**: a host `main.cpp` (x86) does
`vx_mem_alloc` / `vx_copy_to_dev` / `vx_upload_kernel_file` /
`vx_upload_bytes(&kernel_arg)` / `vx_start(...)`. The UVM bench replaces that host
and only does "load one image + set startup PC", so the suite can't run. To enable
it the bench must replicate the launch as UVM sequences **and mirror it in SimX**
so the end-state comparison stays apples-to-apples. (Full reasoning:
`INV1_kernel_completion_hang.md` §7.)

The canonical launch is small and known
([runtime/rtlsim/vortex.cpp:194-197](../../../Vortex/runtime/rtlsim/vortex.cpp#L194)):
```cpp
dcr_write(STARTUP_ADDR0, krnl_addr & 0xffffffff);  // where kernel binary was uploaded
dcr_write(STARTUP_ADDR1, krnl_addr >> 32);
dcr_write(STARTUP_ARG0,  args_addr & 0xffffffff);  // where kernel_arg_t was uploaded
dcr_write(STARTUP_ARG1,  args_addr >> 32);
```
HW then propagates `STARTUP_ARG` → each warp's `CSR_MSCRATCH`, which the kernel reads.

---

## Bucket (b): the half-built host sequences (your scaffolding)
From the dead-sequence audit, these `host_*` sequences are **defined but never
started** — they are exactly the Path-B launch steps, already stubbed:

| Sequence (`uvm_env/agents/host_agent/host_sequences.sv`) | Intended role | State |
|---|---|---|
| `host_load_program_sequence` | load kernel binary at `load_address` (def 0x80000000) | params present, not wired |
| `host_configure_dcr_sequence` | drive a DCR (addr,data) via host_transaction | params present, not wired |
| `host_read_result_sequence` | read back a result window (`result_address`=0x80100000, `result_size`) | params present, not wired |
| `host_complete_test_sequence` | orchestrate load → launch → wait → read-result | params present, not wired |

(`host_launch_kernel_sequence` + `host_wait_done_sequence` ARE used today by
`kernel_launch_vseq`/`random_instr_stress_vseq` — so the host_agent itself is live;
these four are the unbuilt remainder.) These map 1:1 onto Path B:

```
host_load_program_sequence   → vx_upload_kernel_file  (load kernel binary)
(build kernel_arg_t)         → vx_upload_bytes        (backdoor-write args)
host_configure_dcr_sequence  → vx_start               (STARTUP_ADDR/ARG via DCR)
host_wait_done_sequence      → wait for completion
host_read_result_sequence    → read C back for the scoreboard compare
host_complete_test_sequence  → the whole orchestration
```

---

## What Path B needs built (the work)
1. **Bump-allocate** device addresses for inputs/output/kernel/args (mirror the
   runtime's allocator).
2. **Backdoor-write** inputs + kernel binary + the packed `kernel_arg_t` via
   `mem_model.write_block` (per-test `kernel_arg_t`, e.g. sgemm
   `{grid_dim[2], size, A_addr, B_addr, C_addr}`).
3. **Program the real `STARTUP_ARG`** — today `dcr_driver` hardcodes argv=0
   ([dcr_driver.sv:120-121](../../uvm_env/agents/dcr_agent/dcr_driver.sv#L120));
   set `cfg.startup_arg_addr` and drive it. (Samuel can wrap the DCR block as
   **RAL** so this reads cleanly.)
4. **Mirror the same memory setup into SimX RAM** via the DPI write path so the
   golden model matches — **this is your lane** and the crux of why Path B is on
   your handover. Without SimX mirroring, the end-state compare is meaningless.
5. Read result window back (`host_read_result_sequence`) → scoreboard compares.

Flesh out the four `host_*` sequences above rather than writing new ones — the
parameter surfaces (`load_address`, `result_address/size`, `dcr_address/data`) are
already there.

---

## Suggested order
- **Pilot one kernel end-to-end** (vecadd-regression is simplest; sgemm next).
- Get DUT to launch + complete + match SimX for that one, then template per-test.
- Coordinate the DUT-side launch sequences with Samuel (RAL/DCR owner); you own
  the **SimX-side mirroring** and the regression integration.

> [!NOTE]
> Division of labor: Samuel builds the DUT-side launch (DCR RAL + backdoor writes
> + `kernel_arg_t` packing); **you** ensure SimX is driven through the identical
> setup so the scoreboard comparison holds, and integrate the `tests/regression`
> apps. Path B is jointly owned; this handover gives you the SimX/regression half.

---

## Pointers
- Plan item: `PathB-launch` (Tier 3, PARKED) in `Vortex_UVM_Plan_Current.md`
- Host sequences: `uvm_env/agents/host_agent/host_sequences.sv`
- DCR driver (argv hardcoded 0): `uvm_env/agents/dcr_agent/dcr_driver.sv:120`
- mem backdoor: `tb/mem_model.sv` (`write_block`, `load_hex_file`)
- Canonical launch: `Vortex/runtime/rtlsim/vortex.cpp:194`, `simx/vortex.cpp:321`
- Regression example: `Vortex/tests/regression/sgemm/{main.cpp,kernel.cpp,common.h}`
- Companion: your INV-1 handover `HANDOVER_Steven_INV1_wspawn_tmc.md`
