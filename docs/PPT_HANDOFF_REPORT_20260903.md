# Vortex UVM verification — handoff for PPT drafting

**Purpose of this document:** paste into a fresh Claude.ai (web) conversation to help
draft presentation slides on the coverage-model work completed this session. This is
a headline-level summary — it deliberately excludes bin percentages and pass/fail
ratios, since the post-change suite run has not yet been banked. Every count below
(covergroups, features, ISA extensions) is a structural fact, verified from source,
not a coverage percentage.

**Repo:** Vortex UVM-GP (RISC-V GPGPU verification, QuestaSim UVM testbench).
**Branch:** `feat/riscvisacov-coverage`. **Config:** 1CL/1C/4W/4T RV32 AXI, primary.
The three original defence-deck coverage banks are frozen and were not touched this
session — a verified backup exists.

---

## 1. Headline: a two-layer coverage model, not one

**Layer L1 — architectural, third-party, independent.** Integrated Imperas'
open-source `riscvISACOV` (Apache-2.0), which scores retired instructions against
RISC-V's own ISA semantics via an RVVI-TRACE feed — independent of anything our own
testbench assumes. Backed by:
- A custom shim reconstructing the RVVI trace record from our commit probe, per SIMT
  lane.
- A code generator that reads Imperas' own coverage specifications and emits the
  SystemVerilog covergroups, **validated by regenerating an existing Imperas
  extension byte-for-byte against their own published source** before being trusted
  on extensions with no reference to check against.

**Layer L2 — microarchitectural, ours, Vortex-specific.** Passive `bind`-based
probes on the DUT's scheduler, dispatch, commit, DCR, LSU, cache, and (new this
session) memory-coalescing units.

**Rule enforced throughout: L1 and L2 results are never merged.** They score
different things over different denominators.

---

## 2. Headline: ISA extensions and covergroups now active

| Layer | Coverage source | ISA extensions covered |
|---|---|---|
| L1 | Imperas riscvISACOV (third-party, independent) | RV32I, RV32M, RV32Zicsr, RV32F, RV32Zifencei — **5 extensions** |
| L1 (built, held for a future config) | generated, not yet enabled | RV32D — held because double-precision float is not present in the current hardware configuration, not because it wasn't tested |
| L2 | Vortex-specific microarchitectural probes | SIMT scheduling, divergence/reconvergence, warp control (barrier/TMC/spawn), the ALU/branch/multiply/VOTE-SHFL instruction classes, FPU/TCU/SFU units, DCR, memory coalescing, cache events, AXI, system status |

**Covergroup counts:**

| | covergroups | coverpoints | crosses |
|---|---:|---:|---:|
| L1 (active) | **80** | — | — |
| L1 (built, not yet enabled) | 32 | — | — |
| L2 (ours) | **20** | **87** | **22** |
| **Active total** | **100** | | |

This session raised active covergroups from 78 to **100**, and staged an additional
32-covergroup bank for a future configuration.

---

## 3. Headline: two verification gaps closed this session

### Closed — ALU/branch/multiply/VOTE-SHFL instruction-class coverage
**Finding:** the RTL's ALU execution unit reuses the same internal encoding field for
four different instruction categories (plain ALU ops, branches, multiplies, and
Vortex's own warp-collective VOTE/SHFL ops), distinguished only by a second field the
coverage model wasn't reading. The practical effect: the coverage model could not
reliably tell an add from a branch from a multiply, and a reported "fully covered"
result on one coverpoint was not actually attributable to the instruction it claimed
to measure.

**Closed:** the probe now reads the correct discriminating field and reports each
instruction category as its own, independently trustworthy coverpoint. **VOTE and
SHFL — Vortex's own SIMT primitives, present in no public RISC-V specification and
therefore invisible to any third-party model — now have dedicated coverage for the
first time.**

### Closed — GPU memory-coalescing coverage (previously zero)
**Finding:** the unit that decides whether a warp's parallel memory accesses collapse
into a single cache-line request or fragment into several — arguably the defining
behaviour of a GPU memory system — had no coverage probe at all.

**Closed:** built a new passive coverage probe plus a directed test kernel exercising
the full range of access patterns (fully coalesced, partially coalesced, fully
scattered), covering both loads and stores. **The GPU's core memory-access behaviour
now has dedicated functional coverage for the first time.**

### Also found: a latent RTL observation (filed, not a live defect)
While building the RV32Zifencei coverage bank, found that the instruction-cache fence
operation is not distinguished from a plain data fence in the decoder — an
architectural detail with no functional impact today, documented as an open RTL
observation rather than presented as a bug.

---

## 4. Headline: what's still running

The extended coverage model is being re-run against the existing 1CL and (next) 2CL
regression suites. **No coverage percentage from this run should be quoted yet** —
it is in progress and will be reported separately once banked. This document is
scoped to what was structurally built and closed, independent of that pending
number.

---

## 5. One-paragraph summary, if the deck needs a single slide

*"Extended verification from a single Vortex-specific coverage model to a two-layer
model: an independent, third-party RISC-V ISA coverage tool (5 ISA extensions, 80
active covergroups, validated byte-for-byte against the vendor's own source) combined
with an expanded microarchitectural model (20 covergroups, 87 coverpoints) covering
Vortex's SIMT-specific behaviour — 100 active covergroups in total. In the process,
closed two verification gaps: a coverage-integrity defect where four distinct
instruction classes were aliasing onto one measurement, and the project's largest
structural blind spot — zero visibility into GPU memory-address coalescing — closed
with a new dedicated probe and directed test."*
