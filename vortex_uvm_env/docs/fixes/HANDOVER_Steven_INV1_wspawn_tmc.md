---
handover: INV-1 → Steven (SimX / microarch lane)
from: Samuel Moussa
date: 2026-06-28
status: ROOT-CAUSED to SIMT warp-control; needs waveform + SimX divergence check
related: INV1_kernel_completion_hang.md (full investigation), fix_17 (P1 probe used to diagnose)
---

# Handover — INV-1: hostless kernels hang in `wspawn`/`vx_tmc` (warp lifecycle)

Steven — this is a clean handover so you can start without re-deriving anything.
The infra side is fully investigated; what remains is microarchitectural (warp
scheduler / SIMT control) and a SimX-vs-RTL divergence check, both your lane.

---

## 1. One-paragraph summary

Every **hostless** compute kernel (`tests/kernel/vecadd`, `fibonacci`,
`functional_mem`) runs for thousands of instructions and then **hangs** — `busy`
never de-asserts, so the run only ever ends by TIMEOUT. The spin localizes to
`wspawn`-spawned warps **parked at `PC=0x80000944`, which is `vx_tmc zero`** — the
instruction a spawned warp uses to deactivate itself at the end of
`init_tls_all`. So the spawned warps reach the point where they should switch off
but never retire/go idle. This blocks the real **T4** negative-injection test
(which needs a completing program).

---

## 2. How to reproduce (1 command)

```bash
cd vortex_uvm_env
make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd TIMEOUT=50000
```

Result: `TEST FAILED` via TIMEOUT at `Total Cycles: 49999`. The probe output is in
`results/latest/logs/simulation.log`. fibonacci and functional_mem reproduce the
same way (`PROGRAM_NAME=fibonacci` / `functional_mem`). `hello` and riscv-dv
(`make sim TEST=random_instruction_stress_test PROGRAM=riscv_arithmetic_basic_test`)
PASS — the contrast is the key clue (they don't `wspawn` worker warps the same way).

---

## 3. Evidence (from run_062121, vecadd, TIMEOUT=50000)

### 3.1 The core runs, then spins at a low PC
```
cyc=1000   PC=0x80003958     ← real kernel/main code (high)
cyc=2000   PC=0x80003a70     ← real kernel/main code (high)
...
cyc=47000  PC=0x80000944
cyc=48000  PC=0x80000944
cyc=49000  PC=0x80000944     ← parked here for thousands of cycles
P1-PROBE retired instructions observed = 6608
per_cluster_busy=1 dut_busy=1 ebreak_detect=0  (entire run)
```
So it is **not** failing to start and **not** frozen from cycle 0 — it executes
6608 instructions, then the PC collapses to `0x80000944` and stays.

### 3.2 The spin PC is `vx_tmc zero` (warp self-deactivation)
`tests/kernel/vecadd/vecadd.dump`:
```asm
80000938 <init_tls_all>:
80000938: li     t0, -0x1
8000093c: vx_tmc t0            # activate ALL threads
80000940: jal    0x8000094c <__init_tls>
80000944: vx_tmc zero          # <-- PARKED HERE: deactivate all threads
80000948: ret
```
`init_tls_all` is launched on every warp by `wspawn` at startup
(`kernel/src/vx_start.S`):
```asm
csrr t0, VX_CSR_NUM_WARPS
la   t1, init_tls_all
.insn r RISCV_CUSTOM0, 1, 0, x0, t0, t1   # wspawn ALL warps -> init_tls_all
```
(and again indirectly when `vx_spawn_threads` launches the kernel body).

### 3.3 These kernels are hostless (rules out the DCR-arg theory)
`tests/kernel/vecadd/vecadd.cpp` runs `main()` **on the device**, calls
`vx_malloc` itself, builds `vecadd_args_t` on its own stack, and spawns via
`vx_spawn_threads` → `VX_CSR_MSCRATCH`. It never reads DCR `STARTUP_ARG`. So the
launch only needs the startup PC, which the bench already provides correctly.

---

## 4. Already ruled out — do NOT re-chase these

| Hypothesis | Why it's out |
|---|---|
| `busy` not wired to DUT | It's directly on the DUT port (`vortex_tb_top.sv:314/337`); it reflects real DUT busy. |
| Missing DCR kernel-args | Hostless kernels don't use `STARTUP_ARG` (they use `CSR_MSCRATCH`, self-built args). `result=0x0 size=0` in the log is the scoreboard compare-window, not kernel args. |
| 32/64-bit (XLEN) mismatch | Kernel + env are consistently RV32; XLEN affects datapath widths, not warp/TMC control. |
| Infinite TLS memset (bad size) | `__tbss_size = 0x1c` (28 B), `__tdata_size = 0` — `__init_tls` is trivial. Not a loop-bound bug. |
| Wrong hex load / X-prop | Core executes 6608 real instructions first; early PCs are valid kernel code. |

---

## 5. What I need from you (the two open questions)

### 5.1 Waveform — does the spawned warp ever retire `vx_tmc zero`?
Inspect the warp scheduler around `0x80000938–0948` on the vecadd run:
- Use `vx_sched_probe` (already bound on `VX_schedule`) signals: `active_warps`,
  `stalled_warps`, `barrier_ctrs`, the split/join wires.
- Question: is the `wspawn`'d warp **stuck pre-issue** (never fetched/issued
  `vx_tmc zero`), or does it **issue but never retire/deactivate**? Is it waiting
  on a barrier (`barrier_ctrs`), a join that never fires, or a TMC update that
  doesn't take effect?
- The new **P1 commit probe** (`vx_commit_probe`, `fix_17`) gives a per-run
  "retired N instructions" read and per-lane `retire_fire` — handy to see if the
  stuck warp ever commits.

### 5.2 SimX divergence — does SimX complete the same vecadd?
This is the decisive split (DUT bug vs shared), and it needs your SimX/DPI path:
- **Standalone `sim/simx/simx` does NOT work for this test** — it can't replicate
  the bench's "map to absolute memory" load. On the bench's `@00000000`-remapped
  hex it fetches `0xbaadf00d` at `PC=0x80000000` (code at `0x0`, PC at
  `0x80000000`) and dies. So that route is a dead end.
- Use the **DPI SimX path** (same `simx_model.so` the scoreboard uses) or a
  correctly-based image so SimX executes from `0x80000000`. If **SimX completes
  vecadd while the RTL hangs → it's a DUT/config issue** at the `wspawn`/`tmc`
  warp-lifecycle. If **SimX also hangs → shared kernel/runtime issue**.

---

## 6. Leading hypothesis (mine, for you to confirm/refute)

A SIMT warp-lifecycle interaction: warps spawned via `wspawn` (for per-warp TLS
init) reach `vx_tmc zero` but the thread-mask-clear / warp-deactivation doesn't
retire them, so the core's `per_cluster_busy` stays asserted forever. Candidate
sub-causes to check in the scheduler: TMC=0 handling for a `wspawn`'d warp,
join/reconvergence of the spawned set, or a barrier the spawned warps never
satisfy in this config (1CL/1C/4W/4T, `NUM_BARRIERS=2`).

---

## 7. Success criterion

`busy` de-asserts and a hostless kernel completes (vecadd reaches its MMIO exit /
the sustained-`busy=0` fallback fires) without TIMEOUT. That immediately unblocks
the real **T4** negative-injection test (inject a fault on a *completing* run and
confirm it FAILS).

---

## 8. Pointers

- Full investigation + corrected reasoning: `INV1_kernel_completion_hang.md`
- P1 probe (diagnostic aid): `fix_17_P1_commit_probe_bind.md`,
  `tb/vx_commit_probe.sv`
- Startup/TLS: `Vortex/kernel/src/vx_start.S`,
  `Vortex/kernel/src/vx_syscalls.c` (`__init_tls`)
- Kernel source: `Vortex/tests/kernel/vecadd/vecadd.cpp` (+ `.dump`)
- Probe trace + launch log: `vortex_uvm_env/results/20260628/run_062121_kernel_launch_test/logs/simulation.log`
