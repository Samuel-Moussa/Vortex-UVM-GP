# Vortex GPGPU UVM — Whole-Project PPT Handover

**Date:** 2026-09-06 · **Author:** Samuel Moussa · **Status:** all technical work frozen for the defence

This is the single source for building the defence presentation. Every number here was
re-measured from the actual UCDBs and source files on 2026-09-06, not copied from earlier
drafts. Where an earlier document disagrees with this one, **this one is correct** — the
supersessions are called out explicitly.

**Read the "Claim discipline" section (§10) before writing any slide sentence.** Several
figures in this project are easy to overstate, and the whole credibility of the work rests
on stating them precisely.

---

## 1. What the project is, in one paragraph

A complete UVM verification environment for **Vortex**, an open-source RISC-V **GPGPU**.
The environment is black-box at the architectural level (end-state and per-instruction
equivalence against reference models) and white-box at the observability level (nine passive
RTL probes feeding a SIMT-aware functional coverage model). It publishes the industry-standard
**RVVI-TRACE** interface, extended for SIMT, which is what allows a **third-party ISA coverage
VIP (Imperas/OpenHW riscvISACOV)** to attach to a GPU without modification — the central
technical contribution.

**Primary configuration:** 1 cluster / 1 core / 4 warps / 4 threads, RV32IMF + Zicond, AXI
memory interface. **Scale configuration:** 2 clusters / 2 cores / 4 warps / 4 threads.
**Toolchain:** QuestaSim 2021.2_1, Ubuntu 22.04.

---

## 2. The contribution — why this is not "just a UVM testbench"

Three open standards exist for RISC-V processor verification, and **all three assume a scalar
core**: one hart, executing one instruction, for one thread.

| standard | what it is | the scalar assumption |
|---|---|---|
| **RVVI-TRACE** | the retirement-trace interface | one record per hart: one PC, one destination register, one value |
| **riscvISACOV** | Imperas/OpenHW functional-coverage VIP, covergroups generated from the ratified ISA | one instruction, one set of operands |
| **ImperasDV** | the commercial reference-model/verdict flow | one architectural context |

A **warp is N architectural contexts executing one instruction under a thread mask.** One
record per hart cannot carry that.

**What this project did:** extended RVVI-TRACE at its documented assumption boundary — adding
warp ID, thread mask and per-lane data — and then attached the unmodified third-party coverage
VIP to the extended interface. **The VIP was never forked.** Five ISA extensions were
generated from Imperas' own DV plans and 80 of its covergroups run against a GPU.

That is the claim: **the open RISC-V verification standards were extended to a SIMT machine,
and a third-party ISA coverage VIP was made to work against a GPU without modifying it.**

---

## 3. Architecture — the checking stack

Two independent reference models, each with a distinct and non-overlapping role:

| model | role | scope | why it cannot be replaced by the other |
|---|---|---|---|
| **SimX** (via DPI-C) | the working golden model | **full SIMT** — warps, masks, divergence, all custom ops | it is the only model that can execute a Vortex kernel at all |
| **Spike** | independence audit | **scalar, base-ISA, warp 0 / lane 0 only** | it is architecturally incapable of SIMT; it exists to prove SimX is not marking its own homework |

The Spike audit is a genuine independence result and must be scoped precisely: on the same
linked ELF, **Spike, SimX and the DUT all retire exactly 11,076 architectural writebacks and
agree on every PC, destination register and value — 0 mismatches**, all 11,076 value-compared.
Non-vacuity was proven by injecting a fault at record 5000, which was named exactly and exited
non-zero. **Spike stops at the first Vortex custom op; SIMT has no independent reference and
will not get one from Spike.**

### The checkers, each with its non-vacuity proof

A checker that has never fired is not evidence of anything. Every checker in this environment
has a proof that it *can* fire:

| ID | mechanism | non-vacuity proof |
|---|---|---|
| **C-END** | end-state memory equivalence vs SimX, byte-exact | `negative_result_test` — fires at `0x800075d8` |
| **C-REV** | reverse pass: detects **dropped stores** the forward pass structurally cannot see | `negative_dropped_store_test` — fires at `0x800075d8` |
| **C-LOCK** | per-instruction lockstep vs SimX | `+LOCKSTEP_INJECT` → exactly 1 `field_mismatch` |
| **C-SVA** | 40 concurrent assertions (AXI / mem / DCR / status) | assertion-fire evidence captured |
| **C-RAL** | DCR register model + backdoor probe (the DCR bus is **write-only**, so a frontdoor read is impossible) | `+DCR_RAL_INJECT` |
| **C-ISA** | third-party ISA coverage (riscvISACOV) | 0 map misses / 0 word mismatches on every run |
| **C-ASSERT-GATE** | RTL runtime assertions counted into the verdict | `misalign_neg` — must report FAILED |

**Gate 0** (bench trustworthiness) is closed, and the two negative tests are the standing
regression guard: they must stay RED on injection after every change.

---

## 4. The ten taps — observability without touching the RTL

**Nine passive probes plus one RVVI shim, all attached with `bind`. Zero RTL modifications.
One bind statement each — the same testbench elaborates for 1 core or 8 cores with no edits.**

| tap | attach point | what it observes |
|---|---|---|
| `vx_commit_probe` | `VX_commit` | every core's retire arbiter — the RVVI retirement stream |
| `vx_instr_probe` | `VX_dispatch` | per-unit instruction classes, thread masks, warp IDs |
| `vx_instr_word_probe` | `VX_fetch` | raw instruction words (feeds riscvISACOV) |
| `vx_sched_probe` | `VX_schedule` | divergence depth, split/join, barriers, warp state |
| `vx_hazard_probe` | `VX_scoreboard` | **register hazards (RAW/WAW)** — added 2026-09-04 |
| `vx_lsu_probe` | `VX_lsu_slice` | true per-lane load writeback values |
| `vx_cache_probe` | `VX_cache_bank` | hit/miss, MSHR stall, per bank |
| `vx_coalescer_probe` | `VX_mem_coalescer` | memory coalescing behaviour |
| `vx_dcr_probe` | `VX_dcr_data` | DCR register read-back (peek-only, never poke) |
| `vortex_rvvi_shim` | `VX_commit` | publishes extended RVVI-TRACE; the riscvISACOV attach point |

Because probes bind to *module types* rather than enumerated paths, they scale to any topology
by construction — no path lists to maintain.

---

## 5. The three coverage layers

The central methodological finding: **our coverage model and a third-party ISA model share no
bin at all.** That is not redundancy to eliminate; it is a layering to make explicit.

| layer | question it answers | owner | blind to |
|---|---|---|---|
| **L1 — ISA** | was the *instruction space* exercised? mnemonic, operand sign, immediate | **riscvISACOV** (third party, independent) | **everything SIMT** |
| **L2 — microarchitecture / SIMT** | was the *machine* exercised? warps, masks, divergence, coalescing, banks, hazards, caches | **ours** | operand values, per-mnemonic identity |
| **L3 — system / protocol** | was the *interface* legal and stressed? | **ours** (SVA + collector) | — |

That L1 and L2 are disjoint was **proven, not assumed**: riscvISACOV sampled as
lane-as-hart (4,581 samples) and as lane-0-only (1,677 samples) covers the **identical bin
set** — it is structurally blind to the thread mask.

**Rule: never merge L1 and L2 UCDBs and never quote a blended number.** Different denominators
over different axes.

---

## 6. Coverage results — the frozen defence banks

**L2/L3 (our model + code coverage), the quotable banks:**

| | **1CL/1C/4W/4T** | **2CL/2C/4W/4T** |
|---|---|---|
| **Total (filtered)** | **94.72%** | **94.55%** |
| Statements | 98.10% | 98.32% |
| Branches | 94.53% | 95.71% |
| Conditions | 90.41% | 88.77% |
| Toggles | 83.40% | 80.47% |
| Assertions | 96.85% | 98.87% |
| Covergroups | **99.79%** | **99.75%** |

50 programs, 0 FAILED at both configurations.

*(A later pair of banks including the new hazard probe reads 94.66% / 94.50% — very slightly
lower because the new probe legitimately **adds** bins to the denominator. That is honest
movement, not a regression; quote whichever bank you cite consistently.)*

**L1 (riscvISACOV ISA coverage) — the targeted gap-hunt campaign:**

| stage | bins | coverage |
|---|---|---|
| raw, everything included | 1,444/6,469 | 22.32% |
| + structurally unreachable excluded | 1,444/6,467 | 22.33% *(hit count unchanged — gated and proven)* |
| **+ register-index bins excluded — the quotable figure** | **429/516** | **83.14%** (89.28% weighted) |

**78 of 80 covergroups carry real coverage.** The campaign drove this from a standing start:
`vecadd_lite` baseline (546 bins) → directed kernels → a new purpose-built kernel
`isacov_fill` → 1,444 bins.

---

## 7. Why the L1 number is quoted with register-index bins excluded

**This must be stated on the slide, not hidden.** `*_reg_assign` coverpoints ask *which*
architectural register was used as rd/rs1/rs2. They are **92% of the raw denominator**
(5,951 of 6,469 bins).

They are excluded as a **stated scope decision, not as an unreachability claim**:

1. Vortex's register file is a **banked RAM with uniform indexing** — `x5` versus `x6` is
   structurally symmetric; there is no per-index logic that could break.
2. **Which register the compiler allocates is a property of the compiler, not the DUT.**
   Reaching `x28` requires manufacturing register pressure, which verifies nothing about the
   hardware.
3. Leaving them in makes the aggregate a measurement of the compiler's register allocator
   rather than of the design.

This is standard practice in CPU DV — OpenHW take the same position. It is implemented as a
**separate, differently-labelled exclusion class** (`EOTH`) from genuine structural
unreachability (`EUR`) precisely so the distinction cannot be blurred, and the two are never
merged into one number.

**The structural class is machine-gated:** an `EUR` exclusion asserts the bins *cannot* be
hit, so removing them must change the denominator only. `apply_isacov_exclude.sh` **fails the
run** if a structural exclusion moves the hit count. It passed: 1,444 hits before and after.

---

## 8. Findings — what the verification actually caught

**29 logged RTL observations** (`docs/RTL_OBSERVATIONS.md`, OBS-001 … OBS-056). The
defence-relevant ones:

**Real RTL defects:**
- **OBS-014** — hardware `fsqrt.s` is **1 ULP off IEEE-754**.
- **OBS-012** — an ISA specification deviation in `jalr`/misalignment handling.
- Stall and response-timeout guards that never scaled with configuration.

**Structural findings — an uncovered bin that is a result, not an excuse:**
- **OBS-055 / WAR hazards.** The new hazard probe shows RAW and WAW but never WAR. Reading
  `VX_scoreboard.sv` proves why: the in-use register bitmap is set **only on a producer's own
  `rd`**, never on a source read, and per-warp issue is strictly in-order — so a later write
  can never chase an earlier read. **WAR is unreachable by construction, not merely
  unobserved.** Recorded with the reason attached rather than left open or quietly waived.
- **OBS-050 / `fence.i`.** `VX_decode.sv:291` never inspects `funct3`, so `fence.i` decodes
  identically to a data `fence` and `INST_FENCE_I` is a dead localparam. The zero bin was
  deliberately left visible before being excluded with the citation.

**Methodology findings — traps that would have produced false confidence:**
- **OBS-029 — the most important one.** The DUT and SimX execute the **same binary**, so a
  fault in the *stimulus* is common-mode and cancels: the compare passes, lockstep passes,
  coverage fills. **A green run with zero mismatches is compatible with the kernel having
  verified nothing.** Only what *differs* between the two sides is validated.
- **OBS-028** — kernels were being compiled for a fixed 1/1/4/4 regardless of the requested
  configuration, so a "multi-core aware" stress kernel had been running single-core all along.
- **OBS-056** — a hand-written inline-asm branch with per-lane-differing operands bypasses the
  compiler's SIMT split/join codegen and causes real divergence with no reconvergence markers.
  Caught by lockstep as a cascade of orphaned retirements.

---

## 9. Verification scope

**53 distinct feature areas** decomposed in `docs/VERIFICATION_PLAN_v2.md`, GPU-first:
11 SIMT · 4 issue/scoreboard · 10 execution units · 14 memory · 8 bus/protocol · 3 multi-core ·
2 termination · 1 exception (waived).

**Deliberately out of scope, with reasons:**
- **RV32D** — 32 covergroups generated but not enabled: `EXT_D_ENABLE` is gated by
  `` `ifdef XLEN_64 `` in Vortex's own configuration, and the build stamp confirms `-DXLEN_32`.
  D is **structurally absent at this configuration**, not an untested capability. (Note the
  distinction: RV32D with FLEN=64 is architecturally legal in the ISA — this is *Vortex's*
  implementation choice, not an ISA requirement.)
- **Atomics (A)** — `EXT_A_ENABLE` unset at the primary configuration.
- **CSR frontdoor** — no host-side CSR bus exists in the RTL; architectural CSRs are already
  covered by end-state plus lockstep, which is stronger.

---

## 10. Claim discipline — read before writing any slide

**Defensible, and provable from artifacts in the repo:**
- "Per-instruction lockstep against a golden model, with **proven-non-vacuous** checkers."
- "94.7% total coverage with 99.8% covergroup coverage on the primary configuration, and a
  second configuration re-run to confirm it scales."
- "Real RTL defects found: an IEEE-754 deviation in hardware `fsqrt.s`, and an ISA
  specification deviation."
- "A third-party ISA coverage VIP attached to a GPU without forking it."
- "83.1% ISA-behaviour coverage across 78 live covergroups, register-index bins excluded by a
  stated scope decision."

**NOT defensible — do not write these:**
- ❌ "The design is verified." (No environment establishes that.)
- ❌ "We stressed the design." (Unquantified.)
- ❌ A single blended L1+L2 coverage number.
- ❌ The bare 22.3% *or* the bare 83.1% without saying which bins are in the denominator.
- ❌ Any Imperas aggregate total quoted as a single precise figure — **their own repository is
  internally inconsistent** (the README header, the per-extension table in that same file, and
  the DV plans give three different totals). Say "five extensions, 80 covergroups, generated
  from Imperas' DV plans" and cite what we generated.

**On "first published":** the defensible framing is narrow and evidence-backed — an open-source
UVM environment for a RISC-V-based GPGPU that extends RVVI to SIMT and integrates a third-party
ISA coverage VIP. Avoid unqualified "first ever" claims; prior theoretical work exists.

---

## 11. Suggested slide flow

1. **The problem** — GPUs are verified with ad-hoc flows; RISC-V has open verification
   standards but they are all scalar.
2. **The gap** — a warp is N architectural contexts; one record per hart cannot carry it.
3. **The contribution** — extend RVVI at its assumption boundary; attach the VIP unmodified.
4. **Architecture** — the environment, two golden models with distinct roles.
5. **Observability** — ten binds, zero RTL edits, scales by construction.
6. **Checking** — seven mechanisms, each with its non-vacuity proof; Gate 0.
7. **Coverage** — three layers, proven disjoint; the two configuration banks.
8. **L1 ISA coverage** — the campaign, and the honest denominator discussion.
9. **Findings** — the two real RTL defects; WAR as a structural result; OBS-029 as the
   methodology lesson.
10. **Scope and limits** — what was not verified and why.
11. **Conclusion** — the contribution restated, with the claim discipline intact.

**The strongest single slide is #9**, and within it OBS-029: *a green run can be compatible
with having verified nothing.* Demonstrating that you found and closed that trap is a better
argument for verification maturity than any coverage percentage.

---

## 12. Source-of-truth files

| file | contains |
|---|---|
| `docs/VERIFICATION_PLAN_v2.md` | the 53 feature areas, three-layer model, waivers |
| `docs/RTL_OBSERVATIONS.md` | all 29 observations, OBS-001 … OBS-056 |
| `docs/RISCVISACOV_STATUS.md` | L1 integration detail, coverpoint taxonomy |
| `Vortex/sim/uvmsim/scripts/isacov_exclude.do` | the two exclusion classes, with citations |
| `Vortex/sim/uvmsim/docs/*_EXPLAINED.md` | RVVI / RAL / AXI / probes / SVA deep dives |
| `vortex_uvm_env/cov/bank_*_DEFENCE_FROZEN_*` | the quotable coverage banks |
| `vortex_uvm_env/cov/isacov_gaphunt/` | the L1 gap-hunt bank + both exclusion stages |
