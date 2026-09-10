# riscvISACOV integration — Step 1-3 report (stop point per the handover brief)

**Branch:** `feat/riscvisacov-coverage` (created from `main`, nothing else touched)
**Status:** Steps 1-3 done. Step 3's go/no-go gate is a **GO**. Two findings reshape
step 5's scope — read before writing the shim.

---

## Step 1 — cloned

```
$ git clone --branch X-2025.12 --depth 1 https://github.com/riscv-verification/riscvISACOV.git
$ git clone --branch X-2025.12 --depth 1 https://github.com/riscv-verification/RVVI.git
```
Both landed under `third_party/` on this branch. `X-2025.12` exists on both remotes exactly
as the brief stated (`git ls-remote` confirmed both before cloning).

---

## Step 2 — inventory: only RV32I has real source. This changes the achievable scope.

```
$ ls third_party/riscvISACOV/documentation/*_coverage.md | wc -l
143
$ ls third_party/riscvISACOV/source/coverage/
RISCV_config_checks.svh    RISCV_coverage_hazards.svh   RISCV_trace_data.svh
RISCV_coverage_base.svh    RISCV_coverage_pkg.svh       RV32I_coverage.svh
RISCV_coverage_common.svh  RISCV_coverage_rvvi.svh      RV32I_coverage_init.svh
RISCV_coverage_csr.svh     RISCV_instruction_base.svh
```

**143 extensions are documented (spec `.md` files). Exactly one — RV32I — has an
implementation file (`RV32I_coverage.svh`, 170 KB) in this public checkout.** No
`RV32M_coverage.svh`, no `RV32F_coverage.svh`, no `RV32D`/`RV32C`/anything else.

Confirmed this isn't a naming mismatch — the include gate is unconditional and would fail
to find the file:
```
$ grep -n 'ifdef COVER_RV32M' source/coverage/RISCV_coverage_base.svh
    `ifdef COVER_RV32M
        `include "coverage/RV32M_coverage.svh"     <-- this file does not exist
```

**Practical consequence: the handover's step 8 ("Add `COVER_RV32M` … run `div_edge`
against it") is not executable against this public clone.** RV32F is the same story. This
is exactly the risk the brief itself flagged (*"the public repo is a sample, not the full
suite … do not report a number you have not compiled"*) — now quantified: **1 of 143
extensions is buildable from the public source tree. RV32I only.**

`dvplans/RISCV_cover_levels_info.csv`, referenced by name in `dvplans/README.md`: confirmed
**does not exist** in this checkout, exactly as the brief suspected.

**Recommendation: scope this work to RV32I only**, and say so plainly in the eventual
finding — "riscvISACOV bank: RV32I, the only extension with public source" is a completely
defensible sentence for the appendix; claiming broader ISA coverage would not be.

---

## Step 3 — the `idvPkg`/`idvApiPkg` go/no-go gate: **GO, the dependency is shallow**

`source/coverage/RISCV_coverage_pkg.svh:25-28`:
```systemverilog
import idvPkg::*;
import rvviApiPkg::*;
import idvApiPkg::*;
```
These are the **only three external package imports in the entire toolchain** — confirmed
by grepping every `.svh` file for `import`. `rvviApiPkg` is real and provided by RVVI
(`RVVI/source/host/rvvi/rvviApiPkg.sv`), and confirmed it has **no** `idv*` dependency of
its own — it's clean.

`idvPkg`/`idvApiPkg` are never defined anywhere in either cloned repo — confirmed. This is
the ImperasDV product dependency the brief flagged as the biggest risk.

**But actual usage of `idv*` symbols across the whole source tree is exactly two
functions, seven and two call sites respectively:**

| symbol | call sites | what it does |
|---|---|---|
| `idvMsgFatal(string)` | 7, all in `RISCV_config_checks.svh` | fires only inside `` `ifdef `` branches that detect **conflicting base-ISA macros** (e.g. both `COVER_BASE_RV32I` and `COVER_BASE_RV32E` defined). For a valid single-base config these branches aren't even compiled in. |
| `idvRefCoverPointNext(string)` | 2, both in `RISCV_coverage_base.svh`'s `sample_csrs()` | pulls the next CSR-compare record from what would be ImperasDV's reference-model queue, in a `do…while` loop keyed on the returned string being non-empty. |

**Both are trivially stubbable:**
- `idvMsgFatal` → a one-line function that calls `$fatal`. Only exists to fire on a
  misconfiguration we won't create.
- `idvRefCoverPointNext` → return `""` unconditionally. That makes `sample_csrs()`'s loop
  execute zero iterations — which is exactly correct for us, since we have no ImperasDV
  reference model to compare CSR values against, and CSR coverage is not in scope for the
  RV32I-BASIC milestone anyway (`sample_csrs()` is only called from `sample()` when
  `csrs_written()` is true — we can also simply not call it).

**Plan: a ~15-line stub file, two packages (`idvPkg`, `idvApiPkg`), satisfying the import
and the two symbols.** No ImperasDV license, tool, or product is needed. This is the
opposite of the brief's fear — worth stating plainly since "needs ImperasDV" would have
ended the whole effort.

---

## Two findings that reshape Step 5 (the shim) — read before writing it

### Finding A: `insn` — the raw instruction word — is NOT in our existing merged commit record, but it exists one stage upstream

The brief's framing (*"the sample point is already built… this is a shim, not a new
probe"*) is not quite right, and it matters because riscvISACOV's covergroups decode the
raw instruction themselves — they don't take a pre-classified opcode.

Checked both structs the existing probes read:
```systemverilog
// VX_gpu_pkg.sv:635-649 — dispatch_t (feeds vx_instr_probe.sv)
logic [INST_ALU_BITS-1:0] op_type;   // an ALREADY-DECODED Vortex-internal enum, e.g. INST_ALU_ADD

// VX_gpu_pkg.sv:651-663 — commit_t (feeds vx_commit_probe.sv, our merged record's source)
// no instruction-word field at all
```
Neither carries `insn[31:0]`. **But the raw word exists earlier in the pipeline and is
simply not forwarded:**
```
core/VX_fetch.sv:131: assign fetch_if.data.instr = icache_bus_if.rsp_data.data;
```

**Two ways to close this, in order of soundness:**
1. **Bind a small new probe near fetch/decode** that tags `fetch_if.data.instr` with
   `uuid` and forwards it to retirement, correlated with the existing commit-time merged
   record by `uuid`. This is real, scoped, additive work — a new probe, not a rewrite of
   the existing one — but it is genuinely new, not "just a shim."
2. **Reverse-map `op_type` back to a synthetic RV32I encoding.** Possible in principle
   (RV32I is ~40 mnemonics, `op_type` values are enumerable), but lossy and fragile —
   `op_type` doesn't carry register-field bit positions cleanly, and building a second
   decoder whose only job is to re-derive what the first decoder already knew is exactly
   the kind of duplicate-source-of-truth bug class this project's own methodology (rule 7,
   OBS-029) warns against. **Not recommended.**

**Recommendation: option 1**, and it should be sized into Step 5's estimate — a compact
`vx_instr_word_probe.sv` bound at `VX_fetch`, publishing `{uuid, PC, instr}` on its own
analysis port, merged with the existing RVVI record by `uuid` before driving the
`rvviTrace` interface. This is the same pattern already used for the LSU writeback probe
merge described in the handover's §4 — not a new pattern, just a new instance of it.

### Finding B: the `rvviTrace` interface is `wire`-typed and must be driven, not written

`RVVI/source/host/rvvi/rvviTrace.sv:59-95` — every signal (`valid`, `order`, `insn`, `pc_rdata`,
`x_wdata`, `x_wb`, `csr`, …) is declared `wire`, sized `[NHART-1:0][RETIRE-1:0]`. A `wire`
cannot be assigned from inside a `class` method the way a `bit`/`reg` could — the shim needs
a small **driver module** (or a bound interface with continuous `assign`s fed from
registered state a class updates) sitting between our merged UVM record and the interface
instance. This is normal RVVI-TRACE integration, not a Vortex-specific problem, but it's
worth sizing into Step 5 rather than discovering it mid-shim.

**`x_wdata`/`x_wb` semantics, confirmed from the struct comments** — these are **full
32-register snapshots**, not "the value written this cycle": `x_wdata[r]` holds register
`r`'s current value, `x_wb[r]` flags whether `r` changed *this* retirement. Maps cleanly
onto what we already have: on a `wb` retirement, set `x_wb[rd]=1`, `x_wdata[rd]=data`, and
`x_wb[i]=0` for every other `i` (Vortex retires one register write per instruction, so this
is a single-bit-set operation, not a real snapshot to maintain).

---

## Licensing — one item flagged for Samuel, not resolved here

`LICENSE.md` (repo root) states plainly: *"The files provided in the public GitHub
repositories are all under the Apache 2.0 open source license."* Confirmed present, and
that sentence is unambiguous.

**But every source file's header carries `SPDX-License-Identifier: Apache-2.0 WITH
SHL-2.0`, and no file in either cloned repo contains the SHL-2.0 rider text.** I could not
locate a standard SPDX identifier matching `SHL-2.0` in anything available to me locally —
the Solderpad Hardware License identifiers I'm aware of are `SHL-0.51` and `SHL-2.1`, not
`SHL-2.0`. **I am not confident this is a real, resolvable SPDX tag, and I don't have a way
to verify the SPDX registry from here.** Per the brief: flagging to Samuel rather than
guessing. Practical read for now: `LICENSE.md`'s plain-English statement is unambiguous
Apache-2.0, and that's what governs use; the file-header tag is worth a five-minute check
against the SPDX registry before anything from this repo is quoted in a publishable thesis.

---

## What did NOT happen

Nothing compiled yet — that's step 4, next. No RTL, probe, scoreboard, or existing test was
touched. The three existing coverage banks were not opened, merged, or regenerated. Nothing
outside `third_party/` and this doc changed.

## Recommended next action

Step 4: write the ~15-line `idv` stub package, then attempt to compile
`RISCV_coverage_pkg.svh` standalone in QuestaSim with `` `define COVER_RV32I `` +
`` `define COVER_LEVEL_BASIC `` and nothing else wired up — the brief's own next step,
now unblocked. Say go and I'll continue; this report is the step-3 stop point as instructed.
