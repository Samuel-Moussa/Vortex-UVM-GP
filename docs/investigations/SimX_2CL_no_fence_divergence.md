# Investigation: 2CL `no_fence` / `full_interrupt` failures — SimX multi-cluster ordering

**Date:** 2026-07-10 · **Config:** 2CL/2C/4W/4T · **Status:** ROOT-CAUSED (not a DUT bug); disposition = UNVERIFIABLE class
**Program:** `riscv_no_fence_test_0` (riscv-dv random), also `riscv_full_interrupt_test`

## Symptom
At 2CL/2C, `riscv_no_fence_test` fails the scoreboard with **one** memory mismatch:
```
MEM MISMATCH addr=0x80013dd8  DUT=0x28af8c40  SimX=0x2fff8c40
```
Deterministic and reproducible (identical every run). `full_interrupt` fails similarly (single-bit
mismatch). Both **pass at 1CL**. All 10 fence-respecting riscv-dv tests pass at 2CL.

## Method
Replayed the exact failing hex (`PROGRAM=<hex>` → prepare.sh uses it directly; no regen) at both
configs; instrumented the TB `mem_model.write_byte` (DUT-side store log) and SimX
`Emulator::dcache_write` + the LSU STORE path in `execute.cpp` (SimX-side store log with core id +
register file dump). All instrumentation has been reverted.

## Evidence chain (hypotheses tested — several DISPROVEN)
| Hypothesis | Verdict | Evidence |
|---|---|---|
| UB / wild jump into uninitialized memory | ❌ | `0x80013dd8` is in defined `.region_0` (loaded data section) |
| It "worked at 1CL" = same test | ❌ | 1CL and 2CL ran **different** regenerated programs (MD5 differ); *and* the 2CL-failing hex **passes at 1CL** |
| Cross-core race (value varies) | ❌ | all 4 DUT cores write the **same** `0x28af8c40`; two 2CL replays identical |
| SimX crash / robustness | ❌ | native-SimX abort was a *flawed* experiment — it aborts on the **passing** 1CL program too (native harness mismatch, not the UVM/DPI behavior) |
| SimX register init = `std::rand()` (release/NDEBUG) | ❌ | changed to zero-init, **verified `emulator.o` rebuilt**, divergence persists |
| SimX doesn't share memory across clusters | ❌ | `processor.cpp` passes one `g_ram` to every core/cluster |
| Per-core CSR (hart/core id) | ❌ | program reads **only** `mscratch` (0x340, ×1782) + `MIP` (0x344, ×1) — no id CSR |

## What is PROVEN
- The divergence is **per-cluster**: SimX cluster-0 cores (0,1) compute `0x28af8c40` — **matching the DUT exactly**; SimX cluster-1 cores (2,3) compute `0x2fff8c40`. Final memory = last writer (a cluster-1 core) → mismatch.
- Isolated to a **single propagating value** in 3 registers at the store (`sw s10, -0x281(tp)` @ `0x80000780`): `s10 = s2 << 4`, and only `x18 (s2)`, `x15 (a5)`, `x26 (s10)` differ between clusters — all carry `0x…28af8c4…` (cluster0) vs `0x…2fff8c4…` (cluster1).
- The **DUT is self-consistent** (all cores agree) **and corroborated by SimX's own cluster 0**.

## Conclusion
With registers zero-init, memory shared, and no per-core CSR, the **only** remaining per-core input is
the **order in which unsynchronized cross-core shared-memory writes become visible**. This is the
**`no_fence`** test (fences removed → no ordering guarantees). SimX's deterministic core-interleaving
resolves that ordering differently for its second cluster than the timing-accurate DUT does.

**This is a memory-ordering / fenceless-semantics reference-faithfulness difference, NOT a Vortex DUT
bug.** Signature confirms it: only the two ordering/timing-unsafe tests (`no_fence`, `full_interrupt`)
fail at multi-cluster; every fence-respecting test passes. A real multi-cluster coherence bug would
corrupt the fenced tests too.

## Honest boundary (not fully pinpointed)
The exact upstream instruction where SimX cluster-1 first diverges was **not** isolated — `s2`/`a5` are
set well before the store, and pinpointing the first divergence needs a per-instruction **lockstep
DUT-vs-SimX register trace** (scoreboard `vortex_scoreboard.sv:83` marks lockstep as Future Work).
Stopped after ~10 rebuilds; the practical conclusion holds without it.

## Disposition (recommended)
Classify `no_fence` / `full_interrupt` at **multi-cluster** as **UNVERIFIABLE** (matches the documented
"SimX diverges on some random sequences" class in `run_suite.sh`) — now backed by this evidence, not a
guess. All deterministic kernels/directed/regression + 10/12 riscv-dv remain a hard pass at 2CL.

## Follow-up candidates (optional, not blocking)
- Build a lockstep retire-trace comparator (DUT commit-probe PCs+regs vs SimX step trace) to pinpoint
  first-divergence generally — closes the "Future Work" gap and settles any similar case in minutes.
- SimX co-sim faithfulness: zero-init registers in release builds too (did NOT fix this issue, but is
  correct for co-simulation against a zero-init DUT — a separate, low-risk hardening; Steven's lane).
