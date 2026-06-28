---
handover: kernel execution (run + launch) → Steven
from: Samuel Moussa
date: 2026-06-28
status: INV-1 root-caused (needs waveform/SimX); Path B scaffolding exists (needs build + SimX mirroring)
related: INV1_kernel_completion_hang.md, plan item PathB-launch, fix_17 (P1 probe)
---

# Handover — Steven: make real kernels run end-to-end

One handover, two related threads. Both are "get a real Vortex program to run and
finish through the bench + SimX," which is why they're merged here so one person
owns the whole launch/execution path.

| Thread | What it is | Status |
|---|---|---|
| **A — INV-1** | hostless `tests/kernel/*` kernels run but never complete (`wspawn`'d warps parked at `vx_tmc zero`) | root-caused → needs waveform + SimX divergence check |
| **B — Path B** | host-driven `tests/regression/*` (sgemm/sort/…) can't even launch — no host runtime in the bench | scaffolding exists (half-built `host_*` seqs) → needs launch protocol + SimX mirroring |

Thread A is "completion of programs we *can* launch"; Thread B is "launching the
programs we *can't* yet." Together = the full "real kernels run" story.

---

# THREAD A — INV-1: kernels hang in `wspawn`/`vx_tmc` (warp lifecycle)

## A.1 Summary
Every **hostless** compute kernel (`vecadd`, `fibonacci`, `functional_mem`) runs
thousands of instructions then **hangs** — `busy` never de-asserts, so the run
only ends by TIMEOUT. The spin localizes to `wspawn`-spawned warps **parked at
`PC=0x80000944` = `vx_tmc zero`** — the instruction a spawned warp uses to
deactivate itself at the end of `init_tls_all`. So spawned warps reach the point
where they should switch off but never retire/go idle. Blocks the real **T4**
negative-injection test (needs a completing program).

## A.2 Reproduce (1 command)
```bash
cd vortex_uvm_env
make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd TIMEOUT=50000
```
→ `TEST FAILED` via TIMEOUT at `Total Cycles: 49999`. fibonacci/functional_mem
reproduce identically. `hello` and riscv-dv PASS — that contrast is the key clue
(they don't `wspawn` worker warps the same way).

## A.3 Evidence (run_062121, vecadd)
```
cyc=1000   PC=0x80003958     ← real kernel/main code (high)
cyc=47000  PC=0x80000944
cyc=49000  PC=0x80000944     ← parked here thousands of cycles
P1-PROBE retired instructions observed = 6608
per_cluster_busy=1 dut_busy=1 ebreak_detect=0   (entire run)
```
Disasm (`tests/kernel/vecadd/vecadd.dump`):
```asm
80000938 <init_tls_all>:
8000093c: vx_tmc t0            # activate ALL threads
80000940: jal    __init_tls    # 28-byte memset (trivial)
80000944: vx_tmc zero          # <-- PARKED HERE: deactivate all threads
80000948: ret
```
`init_tls_all` is launched on every warp by `wspawn` (`kernel/src/vx_start.S`).
These kernels are **hostless**: `main()` runs on-device, builds its own args, and
spawns via `vx_spawn_threads`→`VX_CSR_MSCRATCH`; they never read DCR `STARTUP_ARG`.

## A.4 Already ruled out — do NOT re-chase
| Hypothesis | Why it's out |
|---|---|
| `busy` not wired | Direct on DUT port (`vortex_tb_top.sv:314/337`) |
| Missing DCR kernel-args | Hostless kernels use `CSR_MSCRATCH`, not `STARTUP_ARG`; `result=0/size=0` is the scoreboard window |
| 32/64 (XLEN) | Kernel + env consistently RV32; XLEN ≠ warp/TMC control |
| Infinite TLS memset | `__tbss_size=0x1c` (28 B), `__tdata_size=0` — trivial |
| Wrong hex / X-prop | 6608 real instructions execute first; early PCs valid |

## A.5 What I need from you
1. **Waveform** around `0x80000938–0948`: is the `wspawn`'d warp **stuck pre-issue**
   or does it **issue `vx_tmc zero` but never retire/deactivate**? Use
   `vx_sched_probe` (`active_warps`, `stalled_warps`, `barrier_ctrs`, split/join);
   the **P1 commit probe** (`vx_commit_probe`, fix_17) gives a per-run retire count.
2. **SimX divergence:** does SimX complete this same vecadd while RTL hangs?
   **Standalone `sim/simx/simx` does NOT work** for this — it can't replicate the
   bench's "map to absolute memory" load (fetches `0xbaadf00d` at `0x80000000`).
   Use the **DPI SimX path** or a correctly-based image. SimX completes + RTL hangs
   → DUT/config issue; both hang → shared kernel/runtime issue.

## A.5b Sharpened by full kernel sweep (2026-06-28)
All 8 `tests/kernel/*` run through the bench: **`hello` + `fibonacci` PASS via
ebreak** (single-threaded, never call `vx_spawn_threads`); **vecadd, conform,
axi_traffic, functional_mem, warp_test, barrier_test all TIMEOUT** (all call
`vx_spawn_threads`). Since every kernel boots through the **same** `wspawn
init_tls_all` and the single-threaded ones finish, **the boot wspawn works** — the
hang is the **worker warps spawned by `vx_spawn_threads`** (second wspawn), which
re-enter `init_tls_all` and park at `vx_tmc zero`. **Focus the waveform on the
`vx_spawn_threads` wspawn, not the boot one.** (fibonacci completes at ~28k cycles
→ spawners genuinely hang, not merely slow.)

## A.6 Leading hypothesis
SIMT warp-lifecycle: `wspawn`'d warps reach `vx_tmc zero` but the
thread-mask-clear / warp-deactivation doesn't retire them, so `per_cluster_busy`
stays asserted. Check TMC=0 handling for a `wspawn`'d warp, join/reconvergence of
the spawned set, or a barrier never satisfied (1CL/1C/4W/4T, `NUM_BARRIERS=2`).

## A.7 Success criterion
`busy` de-asserts and a hostless kernel completes (MMIO exit / sustained-`busy=0`)
without TIMEOUT → immediately unblocks the real T4 negative test.

---

# THREAD B — Path B: host-driven launch for the regression suite

## B.1 Why the regression suite needs this
`tests/regression/*` are **host-driven**: a host `main.cpp` (x86) does
`vx_mem_alloc` / `vx_copy_to_dev` / `vx_upload_kernel_file` /
`vx_upload_bytes(&kernel_arg)` / `vx_start(...)`. The UVM bench replaces that host
and only "loads one image + sets startup PC", so the suite can't run. Enabling it
means replicating the launch as UVM sequences **and mirroring it in SimX** so the
end-state compare stays apples-to-apples.

Canonical launch ([runtime/rtlsim/vortex.cpp:194-197](../../../Vortex/runtime/rtlsim/vortex.cpp#L194)):
```cpp
dcr_write(STARTUP_ADDR0, krnl_addr & 0xffffffff);  // where kernel binary uploaded
dcr_write(STARTUP_ADDR1, krnl_addr >> 32);
dcr_write(STARTUP_ARG0,  args_addr & 0xffffffff);  // where kernel_arg_t uploaded
dcr_write(STARTUP_ARG1,  args_addr >> 32);
```
HW propagates `STARTUP_ARG` → each warp's `CSR_MSCRATCH`, which the kernel reads.

## B.2 The scaffolding already exists (dead-sequence audit, Bucket b)
These `host_*` sequences are defined but never started — exactly the Path-B steps,
stubbed (`uvm_env/agents/host_agent/host_sequences.sv`):

| Sequence | Intended role | Maps to |
|---|---|---|
| `host_load_program_sequence` | load kernel binary at `load_address` | `vx_upload_kernel_file` |
| `host_configure_dcr_sequence` | drive DCR (addr,data) | `vx_start` (STARTUP_ADDR/ARG) |
| `host_read_result_sequence` | read result window (`result_address`/`size`) | read C for compare |
| `host_complete_test_sequence` | orchestrate load→launch→wait→read | whole flow |

(`host_launch_kernel_sequence` + `host_wait_done_sequence` are already live in
`kernel_launch_vseq`/`random_instr_stress_vseq` — flesh out the four above rather
than writing new ones; their param surfaces already exist.)

## B.3 What to build
1. **Bump-allocate** device addresses for inputs/output/kernel/args.
2. **Backdoor-write** inputs + kernel binary + packed `kernel_arg_t` via
   `mem_model.write_block` (per-test struct, e.g. sgemm
   `{grid_dim[2], size, A_addr, B_addr, C_addr}`).
3. **Program real `STARTUP_ARG`** — today `dcr_driver` hardcodes argv=0
   ([dcr_driver.sv:120-121](../../uvm_env/agents/dcr_agent/dcr_driver.sv#L120));
   set `cfg.startup_arg_addr`. (Samuel can wrap DCR as **RAL** for clean access.)
4. **Mirror the same setup into SimX RAM** via the DPI write path so the golden
   model matches — **your lane**, and the crux of why this is on your handover.
5. **Read result** (`host_read_result_sequence`) → scoreboard compares.

## B.4 Division of labor
- **Samuel:** DUT-side launch (DCR RAL + backdoor writes + `kernel_arg_t` packing).
- **Steven (you):** SimX-side mirroring (identical setup so the compare holds) +
  `tests/regression` integration.
- **Order:** pilot one kernel end-to-end (vecadd-regression simplest, sgemm next),
  prove DUT launches+completes+matches SimX, then template per-test.

---

# Shared pointers
- Full INV-1 investigation: `INV1_kernel_completion_hang.md`
- P1 probe (diagnostic aid): `fix_17_P1_commit_probe_bind.md`, `tb/vx_commit_probe.sv`
- Startup/TLS: `Vortex/kernel/src/vx_start.S`, `Vortex/kernel/src/vx_syscalls.c`
- Host sequences: `uvm_env/agents/host_agent/host_sequences.sv`
- DCR driver (argv hardcoded 0): `uvm_env/agents/dcr_agent/dcr_driver.sv:120`
- mem backdoor: `tb/mem_model.sv` (`write_block`, `load_hex_file`)
- Canonical launch: `Vortex/runtime/rtlsim/vortex.cpp:194`, `simx/vortex.cpp:321`
- Regression example: `Vortex/tests/regression/sgemm/{main.cpp,kernel.cpp,common.h}`
- Plan item: `PathB-launch` (Tier 3, PARKED) in `Vortex_UVM_Plan_Current.md`
- Probe trace + launch log: `results/20260628/run_062121_kernel_launch_test/logs/simulation.log`
