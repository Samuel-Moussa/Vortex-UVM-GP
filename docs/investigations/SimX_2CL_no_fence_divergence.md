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

## First divergence — PINPOINTED via lockstep (2026-07-15, Phase A1(d))
The per-instruction lockstep comparator (`lockstep_scoreboard.sv`, `+LOCKSTEP`) was run on **this exact
pinned hex** (`results/20260710/run_125857_.../programs/riscv_no_fence_test_0.hex`, replayed with regen
OFF) at 2CL/2C/4W/4T. It **reproduced the end-state mismatch** (`0x80013dd8 DUT=0x28af8c40
SimX=0x2fff8c40`) and pinpointed the first diverging retirement:

```
first divergence:  cid=2 & cid=3 (cluster 1)  seq=278  PC=0x800004f4  uuid=…144
    800004f4:  02d9b433   mulhu s0,s3,a3      DUT s0=0x3d75a09d  vs  SimX s0=0x3d009f79
```

- **cid=0 and cid=1 (cluster 0) show ZERO divergences** — byte-exact vs SimX for all retirements.
  Only cluster-1 cores diverge. This confirms the "per-cluster" finding at instruction granularity.
- Tallies: compared 5432, matched 5314, **field_mismatch data = 118** (59 per cluster-1 core), PC/rd
  mismatch = 0, **0 orphans** (both models completed, same instruction counts), 936 loads data-skipped.
- `mulhu` is a pure deterministic ALU op ⇒ its **inputs (`s3`/`a3`) already differed** on cluster-1.
  The block around it uses `a3` as the base for interleaved shared loads AND stores
  (`sw s10,-14(a3)` @0x800004f0; `lb/lw/lbu … (a3)`). The diverging input therefore originates in
  **shared-memory read ordering**, not computation — corroborated by the fact that a real compute/RTL
  bug would corrupt *both* clusters identically, whereas here cluster-0 is exact.
- **True root is one instruction upstream** (a shared-memory load feeding `s3`/`a3`): lockstep skips
  load *data* at the commit-arb probe (OBS-002), so the `mulhu` is the first *observable* writeback
  carrying the already-diverged value. Naming the exact load needs an LSU-writeback / regfile-write
  probe (OBS-002 follow-up) — but the class (fenceless shared-load ordering) is now proven, not inferred.

**Verdict unchanged and now instruction-level: fenceless memory-ordering reference-faithfulness
difference, NOT a Vortex DUT bug** (see RTL_OBSERVATIONS OBS-007 for the companion *abort* case on a
regenerated no_fence program). Disposition stays UNVERIFIABLE at multi-cluster.

## Honest boundary (superseded above)
~~The exact upstream instruction where SimX cluster-1 first diverges was **not** isolated~~ — now
pinpointed to the `mulhu` @0x800004f4 consuming a shared-load-derived input; only the exact upstream
load remains unnamed (needs an LSU-data probe, OBS-002).

## DECISIVE root cause (2026-07-15, OBS-002 load-compare + ELF-init check)
With per-instruction load-data now visible (OBS-002, `97c4e30`), the first divergence on
cluster-1 is a **LOAD**, upstream of the `mulhu`:
```
cid=2,3  seq=231  PC=0x80000414  lw s3,0(s1)   s1=0x80020618   DUT=0x7aea0e77  SimX=0x7a000e77
```
`s1` is a **fixed absolute** address (`auipc s1,0x20; addi s1,s1,560` @0x800003e8 → 0x80020618,
identical on every core), in **`.region_1` (PROGBITS = initialized data)**. The **ELF init bytes
at 0x80020618 are `77 0e ea 7a` = 0x7aea0e77 — exactly the DUT value**. So:
- **DUT reads the pristine ELF value** (nothing overwrote byte 0x80020619 before the read).
- **SimX reads 0x7a000e77** — byte 0x80020619 zeroed (0xea→0x00) — and only on **cluster-1**
  (SimX cluster-0 reads it correctly). Same shared `g_ram` address, two values across clusters
  ⇒ a store zeroed that byte **between** SimX's cluster-0 and cluster-1 core-stepping, whereas the
  DUT's cycle-accurate timing does both reads first.
- The program reads **no `mhartid`** and uses **fixed absolute** region addresses ⇒ it is a
  **single-hart** riscv-dv program. Running it on 4 shared-memory cores makes all 4 write the same
  `.region_0`/`.region_1`/`.user_stack` with no fences ⇒ genuine cross-core write-ordering races.

**Verdict (proven): the divergence is a single-hart random test executed in a multi-hart
shared-memory config; its result is architecturally undefined (RVWMO, no fences). SimX's fixed
core-stepping order and the DUT's cycle-accurate timing are BOTH valid executions.** Not a DUT bug;
not a fixable SimX staging bug. Evidence: `scratchpad/obs002_nofence_2CL.log`, ELF `.region_1`@0x80020618.

## REAL fixes (make it verifiable, not suppressed) — decision pending
1. **True lockstep cosim (RVVI-standard, industrial):** drive SimX from the DUT's memory-operation
   order — on a shared-region load, SimX consumes the DUT's loaded value (RVVI load bus) instead of
   its own `g_ram`. Races resolve identically by construction ⇒ these tests become verifiable. Aligns
   with Phase-A RVVI migration. Cost: SimX becomes a step-driven follower for loads (can't independently
   verify a shared-region load's data — inherent to racy regions).
2. **Config-scope single-hart random tests to single-core (methodologically correct, low effort):**
   riscv-dv `no_fence`/`full_interrupt` are single-hart; run them at 1C (deterministic, they PASS) and
   get multi-core coverage from multi-hart-AWARE directed kernels instead of replicating a single-hart
   binary across N shared-memory cores. This is the honest methodology fix.
3. **Per-hart disjoint data regions:** regenerate riscv-dv with per-hart `.region_*`/stack offsets so
   the 4 cores don't stomp each other. More work; riscv-dv/linker-specific.

## Disposition (recommended)
Classify `no_fence` / `full_interrupt` at **multi-cluster** as **UNVERIFIABLE** (matches the documented
"SimX diverges on some random sequences" class in `run_suite.sh`) — now backed by this evidence, not a
guess. All deterministic kernels/directed/regression + 10/12 riscv-dv remain a hard pass at 2CL.

## Follow-up candidates (optional, not blocking)
- Build a lockstep retire-trace comparator (DUT commit-probe PCs+regs vs SimX step trace) to pinpoint
  first-divergence generally — closes the "Future Work" gap and settles any similar case in minutes.
- SimX co-sim faithfulness: zero-init registers in release builds too (did NOT fix this issue, but is
  correct for co-simulation against a zero-init DUT — a separate, low-risk hardening; Steven's lane).
