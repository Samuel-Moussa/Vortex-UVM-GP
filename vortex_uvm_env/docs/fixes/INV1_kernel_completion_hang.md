---
issue: INV-1 — kernel `busy` never idles (completion blocked)
status: ROOT-CAUSED (corrected) — fix not yet implemented
date: 2026-06-28
author: Samuel Moussa
evidence: live sim logs results/20260628/run_062121 (vecadd) + per-kernel runs; vecadd.dump; vx_start.S
---

# INV-1 — Kernels never complete (`busy` never idles)

This document walks the full path: the symptom, the **first hypothesis that turned
out wrong**, how the evidence corrected it, the real root cause, and the planned
solution (A then B). It is deliberately honest about the wrong turn so nobody
re-treads it.

---

## 1. Symptom

Every compute kernel from `tests/kernel/*` ends via **TIMEOUT**, never via ebreak
or the sustained `busy=0` fallback:

- `Total Cycles` always equals `TIMEOUT-1`.
- **Doubling the timeout doubles the cycle count** — the program never reaches a
  terminal state; it runs as long as you let it.
- `assert_busy_eventually_idles` fires.

Only `hello` (and pure riscv-dv streams) complete. This blocks the real **T4**
negative-injection test, because the injected error needs a *completing* program
to be meaningful.

---

## 2. First hypothesis (WRONG) — missing DCR kernel arguments

The UVM launch log showed:

```
[DCR_DRV] Applying bootstrap DCRs during reset: PC=0x80000000 argv=0x0
[SimX-DPI] DCR Write: addr=0x1, value=0x80000000   ← STARTUP_ADDR0 (PC low)
[SimX-DPI] DCR Write: addr=0x2, value=0x0          ← STARTUP_ADDR1 (PC high)
Kernel launch cfg: startup=0x80000000 result=0x0 size=0
```

DCR map ([VX_types.vh:23-26](../../../Vortex/hw/rtl/VX_types.vh#L23)):

| addr | name | written? |
|------|------|----------|
| 0x1 | STARTUP_ADDR0 | ✅ |
| 0x2 | STARTUP_ADDR1 | ✅ |
| 0x3 | STARTUP_ARG0 (arg ptr low) | ❌ |
| 0x4 | STARTUP_ARG1 (arg ptr high) | ❌ |

It *looked* like the testbench launches kernels with a null argument pointer and
never uploads a `kernel_arg_t` struct — so the kernel would read garbage args and
spin. The `result=0x0 size=0` reinforced this.

**Why this was wrong:** `result/size` are the *scoreboard compare-window* config,
not kernel args (a red herring). And the kernel that hangs does not read
`STARTUP_ARG` at all (next section).

---

## 3. The evidence that corrected it

### 3.1 The probe shows the core runs, then spins at a LOW pc

From `results/20260628/run_062121_kernel_launch_test` (vecadd, TIMEOUT=50000):

```
cyc=1000   PC=0x80003958   ← real kernel code (high)
cyc=2000   PC=0x80003a70   ← real kernel code (high)
...
cyc=47000  PC=0x80000944   instr=0x00a282b3 (add)
cyc=48000  PC=0x80000944   instr=0xfc0e88e3 (beq, backward)
cyc=49000  PC=0x80000944   instr=0x00a282b3
P1-PROBE retired instructions observed = 6608
```

So the core **executes 6608 instructions** (it is NOT frozen / NOT failing to
start), runs real kernel code early, then falls back to a **low PC** and spins in
an `add`+backward-`beq` loop with persistent DCACHE stalls.

### 3.2 The spin PC is runtime TLS init, launched via `wspawn`

`vecadd.dump`:

```
80000938 <init_tls_all>:
80000938: li     t0, -0x1
8000093c: vx_tmc t0            # enable all threads
80000940: jal    0x8000094c <__init_tls>
80000944: vx_tmc zero
80000948: ret
```

`__init_tls` ([kernel/src/vx_syscalls.c:56](../../../Vortex/kernel/src/vx_syscalls.c#L56)):

```c
void __init_tls(void) {
  ...
  memcpy(__thread_self, __tdata_start, (size_t)__tdata_size);
  memset(__thread_self + (size_t)__tbss_offset, 0, (size_t)__tbss_size);
}
```

`vx_start.S`:

```asm
csrr t0, VX_CSR_NUM_WARPS
la   t1, init_tls_all
.insn r RISCV_CUSTOM0, 1, 0, x0, t0, t1   # wspawn ALL warps -> init_tls_all
call __init_tls
```

So at startup, **`wspawn` launches `init_tls_all` on every warp**, and each warp
runs the TLS `memcpy`/`memset` loop (the `add`+`beq` we see). The spin lives in
**runtime startup on the spawned warps**, not in kernel computation.

### 3.3 The kernel is HOSTLESS — it never uses DCR args

`tests/kernel/vecadd/vecadd.cpp`:

```cpp
// Host code -> this will actually be run on vortex itself!
int main() {
  // core0, thread0 runs the host part and initializes buffers and kernel args.
  int N = 16;
  int *src0 = (int*)vx_malloc(N*sizeof(int));   // allocates on-device itself
  ...
  vecadd_args_t args; args.src0 = src0; ... args.num_elements = N;
  vx_spawn_threads(1, &total_threads, nullptr, (vx_kernel_func_cb)vecadd_kernel, &args);
}
```

`vx_spawn_threads` passes args via `VX_CSR_MSCRATCH`
([kernel/src/vx_spawn.c:253](../../../Vortex/kernel/src/vx_spawn.c#L253)), **not**
`STARTUP_ARG`. The kernel is self-contained: it only needs the startup PC, which
the bench already provides. **The missing-DCR-arg theory does not apply to this
kernel class.**

---

## 4. Root cause (corrected)

**The `tests/kernel/*` hostless kernels hang in runtime startup — specifically in
the `wspawn`-launched per-warp TLS init (`init_tls_all`/`__init_tls`) — so the
spawned warps never converge/retire and `busy` stays high.** Completion never
fires; only TIMEOUT remains.

This is a SIMT-control / runtime-startup interaction on the RTL DUT, not a
register-programming or kernel-argument gap. It is consistent across vecadd,
fibonacci, and functional_mem (all hit the same `wspawn`/TLS path; all spin at low
PC). It plausibly shares a cause with **INV-2** (DCR-write-timing assert), to be
confirmed.

---

## 5. Solution plan

### Path A — fix the hostless-kernel completion (the real INV-1; do first)
1. **Confirm divergence vs SimX** — does SimX complete this same vecadd while the
   RTL DUT hangs? If SimX finishes and RTL spins, it is a DUT/runtime-config
   interaction (couples with Steven's SimX/microarch lane), not pure infra.
2. **Trace warp activity around `wspawn`** — use `vx_sched_probe` (active/stalled
   warps) + a waveform at `0x80000938–094c` to see whether the spawned warps ever
   retire/converge or are stuck in the TLS `memset` loop. Determine infinite-loop
   vs merely-very-long, and whether `__thread_self`/TLS-size symbols are sane.
3. Fix the identified cause; success criterion: `busy=0` fires, kernel completes,
   and the T4 negative-injection test becomes meaningful.

### Path B — host-driven launch path (where solution 2 + RAL belong; do after A)
For the `tests/regression/*` suite (sgemm, sort, conv3, …), implement the real
Vortex host→device launch:
- mirror the runtime's `kernel_arg_t`, upload the arg struct to device memory,
- program `STARTUP_ARG0/ARG1` (DCR 0x3/0x4),
- model the DCR block as **UVM RAL** (`uvm_reg_block` + `uvm_reg_map` over the
  existing `dcr_agent`) for clean, self-documenting launch programming.
This must be mirrored in SimX so the golden reference matches.

---

## 6. RAL assessment

The DCR interface (12-bit addr, 32-bit data; `STARTUP_ADDR0/1`, `STARTUP_ARG0/1`,
`MPM_*`) is a textbook register block and a good RAL candidate — it would make the
launch sequence clean and frontdoor/backdoor-capable. **There is no RAL in the env
today** (DCR is a plain driver/monitor/sequence agent). RAL pays off in **Path B**;
it does **not** help the `wspawn`/TLS hang in Path A.

---

## 7. Why the regression suite does not (yet) suit this bench

`tests/regression/*` are **host-driven**: they assume a full host runtime that
dynamically uploads the kernel binary and an argument buffer, then programs the DCR
to launch. This bench is **black-box end-state equivalence**: it loads one program
image, sets the startup PC via DCR, runs to completion, and compares final memory
vs SimX — both DUT and SimX driven identically. Running the host-driven suite would
require implementing that entire launch protocol on the DUT side **and** mirroring
it in SimX so the reference matches — a major scope expansion (Path B), not a test
run. The `tests/kernel/*` hostless kernels are the correct fit for the current
model.

---

## 7b. Path A progress (2026-06-28) — narrowed to SIMT warp-control

Three concrete results this session:

1. **SimX divergence test is blocked by tooling, not answered.** Standalone
   `sim/simx/simx` cannot replicate the bench's "map to absolute memory" load:
   on the bench's `@00000000`-remapped hex it fetches `0xbaadf00d` (poison) at
   `PC=0x80000000` and dies — code sits at `0x0`, execution starts at
   `0x80000000`. So "does SimX also hang on vecadd?" remains **unanswered** via
   this route. (The in-bench DPI SimX handles the mapping, but it only runs at
   DUT-completion, which never happens here.) A proper divergence test needs the
   DPI load path or a correctly-based image.

2. **TLS size is sane — not an infinite memset.** From `vecadd.elf`:
   `__tbss_size = 0x1c` (28 B), `__tdata_size = 0`, `__tbss_offset = 0`. So
   `__init_tls` is a trivial 28-byte `memset`. The hang is **not** a bogus TLS
   loop bound.

3. **The spin PC is `vx_tmc zero`** (`0x80000944`) — the instruction a warp uses
   to deactivate itself at the end of `init_tls_all`:
   ```asm
   8000093c: vx_tmc t0       # activate all threads
   80000940: jal __init_tls  # 28-byte memset (trivial)
   80000944: vx_tmc zero     # warps parked HERE — trying to deactivate
   80000948: ret
   ```
   The `wspawn`-spawned warps are **stuck right where they should switch off**.
   This is a **SIMT warp-control / scheduling** behavior (spawned warps not
   retiring/deactivating), i.e. **microarchitectural** — not an infra, load, or
   TLS-size bug.

**Revised conclusion:** INV-1 is most likely a SIMT `wspawn`/`tmc` warp-lifecycle
interaction in the DUT (or a DUT-config/SimX divergence), not something the UVM
infra alone can fix. Next step requires **waveform inspection of the warp
scheduler** (`active_warps`/`stalled_warps` via `vx_sched_probe`, and the TMC
deactivation path) around `0x80000938–0948`, and likely **Steven** (SimX /
microarch lane) to compare against the golden model. This is being handed toward
that investigation rather than forced as an infra patch.

## 7c. Sharpened by full kernel sweep (2026-06-28) — spawning vs non-spawning

Ran all 8 `tests/kernel/*` kernels through the bench (TIMEOUT=80000):

| Result | Kernels | Trait |
|---|---|---|
| ✅ PASS via **ebreak** | `hello`, `fibonacci` | single-threaded — never call `vx_spawn_threads` |
| ✗ TIMEOUT (hang) | `vecadd`, `conform`, `axi_traffic`, `functional_mem`, `warp_test`, `barrier_test` | all call `vx_spawn_threads` (spawn worker warps) |

**Key inference:** every kernel boots through the **same** `wspawn init_tls_all` in
`vx_start.S`. hello/fibonacci complete, so the **boot-time wspawn path is fine**.
The hang is therefore **not** the boot TLS init — it is the **worker warps spawned
later by `vx_spawn_threads`** (which re-enter `init_tls_all` per-warp and park at
`vx_tmc zero`). So INV-1 narrows to: *`vx_spawn_threads`-spawned worker warps fail
to retire/deactivate.* (fibonacci also confirms not all long runs are infinite —
it completes at ~28k cycles; the spawners genuinely hang, not merely slow.)

Steven: focus the waveform on the **second** wspawn (from `vx_spawn_threads`), not
the boot one — the boot one demonstrably works.

## 8. Status

- Root cause: **narrowed** — hostless-kernel hang in `wspawn`-spawned warps parked
  at `vx_tmc zero` (SIMT warp-control), not DCR args, not TLS size.
- Fix: **not implemented** — needs waveform + likely Steven (SimX/microarch).
- Spin-off win already banked: the new **P1 commit probe** (`fix_17`) gives an
  instant "retired N instructions" liveness read that made this diagnosis fast.
