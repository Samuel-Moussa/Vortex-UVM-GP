# Handover: integrate riscvISACOV as a second functional-coverage bank

**For:** Claude Code, working in the Vortex UVM repo
**From:** the deck/analysis session, 2 Sep 2026
**Owner:** Samuel
**Status:** not started. Deck work is finished and must not be disturbed.

---

## 0. Ground rules

1. **Work on a new branch.** `feat/riscvisacov-coverage`. Do not touch `main`/the defence branch.
2. **Do not modify the three existing coverage banks** (`1CL/1C/4W/4T`, `2CL/2C/4W/4T`, `L2/L3`)
   or anything that feeds them. The defence quotes 99.8 / 98.1 / 96.9 etc. from those merges.
   riscvISACOV goes in as a **fourth, separate bank** with its own `.ucdb`, never merged into
   the existing three (different instance sets — the deck explicitly argues merging across
   different geometries is wrong, and the same argument applies here).
3. **The defence deck is frozen.** If this work produces a result worth showing, it becomes a
   *new* appendix slide — it does not edit existing numbers. Slide 108 (`APPENDIX E ·
   PORTABILITY`) already states the portability claim and can absorb a measured result.
4. **Verify, do not assume.** Several things below are marked UNKNOWN. Read the files. If a
   claim in this brief contradicts what you find in the repo, the repo wins — say so.

---

## 1. Goal

Instantiate the Apache-2.0 riscvISACOV coverage model against the existing RVVI-TRACE
retirement stream, sample RV32I (then M, then F), and produce a measured coverage bank.

**Acceptance criteria**

- [ ] riscvISACOV compiles in QuestaSim 2021.2 inside this environment
- [ ] `sample()` is called at retirement with real data from the existing probe path
- [ ] a `.ucdb` is produced with non-zero, plausible RV32I coverage
- [ ] a non-vacuity check: deliberately suppress the sample call → coverage drops to zero;
      restore → it returns. (Same discipline as the four existing injection guards.)
- [ ] the three existing banks are byte-identical to their pre-change results
- [ ] a short written finding: what fraction of RV32I coverpoints the current 50-program bank
      reaches, and which covertypes are structurally unreachable on a SIMT DUT

---

## 2. What riscvISACOV is — verified facts

Source: `https://github.com/riscv-verification/riscvISACOV`

- **Default branch is `X-2025.12`, not `main`.** `main` is a stale Nov-2022 draft containing
  only a README. Clone and check out `X-2025.12`.
- Driven by Imperas with requirements from the **OpenHW Group ARVM-FunctionalCoverage** project.
- Licence: source headers carry `SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0` and
  `Copyright (c) 2005-2024 Imperas Software Ltd.` The README states: *"The source files provided
  in this GitHub repository are all under the Apache 2.0 open source license."*
- **Critical caveat, verbatim from `source/coverage/README.md`:** *"only an example of the source
  is provided in the GitHub repository"* — the public repo is a **sample**, not the full suite.
  The 181-extension / 57,948-coverpoint total in `documentation/README.md` describes Imperas'
  product, not what you can clone. **First job is to find out exactly which extensions have
  real `.svh` source in the public tree.** Do not report a number you have not compiled.

**Structure**

- `documentation/` — one `<EXT>_coverage.md` per extension, listing every covergroup and
  coverpoint. Useful as a spec even where source is absent.
- `source/RISCV_coverage.svh` — the user-facing entry point.
- `source/default_config/RISCV_coverage_config.svh` — compile-time `` `define `` selection.
- `source/coverage/` — the per-extension implementation.
- `dvplans/` — CSV DV plans. Note: `dvplans/RISCV_cover_levels_info.csv` is referenced by name
  in `dvplans/README.md` but 404s at every path tried. Check whether it exists on the branch.

**The integration surface** (verbatim from `source/RISCV_coverage.svh`):

```systemverilog
`include "default_config/RISCV_coverage_config.svh"
`include "default_config/RISCV_csr_config.svh"
`include "coverage/RISCV_coverage_pkg.svh"
import RISCV_coverage_pkg::*;

class coverage #(ILEN=32, XLEN=32, FLEN=32, VLEN=256, NHART=1, RETIRE=1)
    extends RISCV_coverage #(ILEN, XLEN, FLEN, VLEN, NHART, RETIRE);
    function new(virtual rvviTrace #(ILEN, XLEN, FLEN, VLEN, NHART, RETIRE) rvvi);
        super.new(rvvi);
    endfunction
    function void sample(bit trap, int hart, int issue, string disass);
        save_rvvi_data(trap, hart, issue, disass);
        sample_extensions(hart, issue);
        super.sample_idv();
        if (csrs_written(hart, issue)) sample_csrs(hart, issue);
    endfunction
endclass
```

**Enabling extensions** is compile-time, by un-commenting macros in
`source/default_config/RISCV_coverage_config.svh` — e.g. `` `define COVER_RV32I ``,
`` `define COVER_RV32M ``, `` `define COVER_RV32F ``, and level selection
`` `define COVER_LEVEL_BASIC / _EXTENDED / _DV ``. **No plusarg mechanism was documented.**
If you want runtime selection you will have to add it, or build separate objects per level.

**Covertypes** (verbatim from `documentation/RV32I_coverage.md` / `RV32M_coverage.md`):

| Covertype | Level | Meaning |
|---|---|---|
| `ASM_COUNT` | BASIC | number of times instruction executed |
| `INST_ILLEGAL` | BASIC | if not implemented in this config, check the exception is hit |
| `REG_ASSIGN` | BASIC | all legal register assignments |
| `REG_VALUE_SIGN` | BASIC | register value pos / neg / zero |
| `IMM_VALUE` | BASIC | immediate values |
| `REG_COMPARE` | EXTENDED | register assignments using the same register (`cr_*` crosses) |
| `REG_VALUE` | EXTENDED | significant values per register |
| `REG_HAZARD` | EXTENDED | possible register hazards |
| `INSTR_DIVIDE` | EXTENDED | divide-by-zero and over/underflow (RV32M) |
| `REG_VALUE_TOGGLE` | DV | each bit toggling in each register |
| `MEM_ALIGNED` | DV | for load/store, whether memory is aligned |

Naming: one covergroup per mnemonic, `<mnemonic>_cg` (e.g. `addi_cg`); coverpoints `cp_*`,
crosses `cr_*`.

Published per-extension counts (from `documentation/README.md`, **docs not source**):
RV32I 39 instr / 39 cg / 559 cp · RV32M 13 / 8 / 172 · RV32F 30 / 29 / 321.

---

## 3. The unknowns — resolve these first, by reading files

1. **`idvPkg` / `idvApiPkg` dependency.** `source/coverage/RISCV_coverage_pkg.svh` imports
   `idvPkg`, `rvviApiPkg`, `idvApiPkg`. `idv*` are **ImperasDV** packages we do not have.
   Determine: are they needed for compilation, or only by `sample_idv()` / `sample_csrs()`?
   If the dependency is shallow, the fix is a stub package or overriding `sample()` to skip
   `super.sample_idv()`. **This is the single biggest go/no-go risk. Establish it before
   writing any integration code.**
2. **Which extensions actually have source** in `source/coverage/` on `X-2025.12`.
3. **What `rvviTrace` fields the covergroups read.** The interface itself lives in the separate
   `riscv-verification/RVVI` repo — clone that too. We need the exact signal names our shim
   must drive (`valid`, `order`, `insn`, `pc_rdata`, `x_wdata`, `x_wb`, `csr`, `trap`, …).
4. **What `disass` is used for.** `sample()` takes a disassembly string. If any coverpoint keys
   off it we need a disassembler; if it is only for messages, pass `""`.

---

## 4. What our side already provides

From the existing environment (all of this is established and quoted in the defence deck):

- `hw/rtl/.../vx_commit_probe.sv` binds the commit arbiter. Retirement filter at **line 97**:
  `retire_fire && commit_arb_if[i].data.wb`.
- A **separate LSU writeback probe** exists because `commit_arb_if[i].data` is **stale for loads**
  — the LSU writes the register file on its asynchronous response path. The two probes are
  **merged** before publication.
- `rvvi_monitor` publishes one merged record per retirement on a `uvm_analysis_port`, carrying
  `uuid · wid · PC · rd · wb · tmask · per-lane data`.
- Current lockstep numbers on the reference run: **11,634 retirements, 9,287 compared,
  data compared on 8,040** (1,185 loads skipped, 62 volatile CSRs excluded).
- Config under verification: **RV32 I M F + D + Zicond**, AXI4, icache + dcache.

**Implication:** the coverage sample point is already built. This is a shim, not a new probe.

---

## 5. The design decision you must make explicitly

riscvISACOV assumes **one hart executes one instruction for one thread**. A Vortex warp retires
**one instruction for N lanes**, each lane having its own register file. Three options — pick one,
write down why, and say what it costs:

| Option | Mapping | Cost |
|---|---|---|
| **A — lane-as-hart** | `NHART = NUM_THREADS`; each active lane drives one hart slot per retirement | Truest to the ISA model; per-lane register values get real coverage. Inactive lanes under `tmask` must be suppressed, not sampled as zero — **getting this wrong silently inflates coverage** |
| **B — lane 0 only** | `NHART = 1`, sample lane 0 | Trivial to build, honest, and understates coverage. Good first milestone |
| **C — RETIRE-slot** | `RETIRE = NUM_THREADS`, one issue slot per lane | Closest to riscvISACOV's own multi-issue handling; check whether the covergroups actually iterate `issue` |

**Recommendation: build B first** to prove the toolchain end-to-end, then move to A. Do not start
at A — if it does not compile you will not know whether the problem is the mapping or the package.

**The `tmask` trap:** a masked lane still receives the instruction and still spends the cycle, but
does not write back. It must not be sampled. This is the same boundary the environment already
handles in the lockstep comparator — reuse that logic, do not re-derive it.

---

## 6. Coverage-bank hygiene

- New bank path, e.g. `cov/bank_isacov_1CL_1C_4W_4T/`. **Never** `vcover merge` it with the
  existing three.
- The existing `gen_coverage_exclude.sh` exclusion generator must not be pointed at it without
  review — its exclusions are written against our own covergroup names.
- Re-run the existing regression and diff the three existing `.ucdb` summaries before and after.
  If any digit moves, stop and find out why.

---

## 7. Licence obligations if this ships

Apache-2.0 §4: preserve the `Copyright (c) 2005-2024 Imperas Software Ltd.` notice in every file
retained or derived, state the changes made, no trademark grant. Keep riscvISACOV in its own
directory with its licence intact rather than copying fragments into our files. The `WITH SHL-2.0`
rider's full text was not locatable — **find it before redistributing anything**, and if the thesis
will be published, flag it to Samuel.

Anything beyond the public sample is **proprietary Imperas product** and is not covered by the
open-source grant.

---

## 8. Suggested order of work

1. Clone `riscvISACOV` (`X-2025.12`) and `RVVI` into a `third_party/` directory on the branch.
2. Inventory what source actually exists. Report it.
3. Resolve the `idvPkg` / `idvApiPkg` question. **Go / no-go gate.**
4. Compile riscvISACOV standalone in QuestaSim with `` `define COVER_RV32I `` + `COVER_LEVEL_BASIC`
   and nothing else wired up. Get it to elaborate before connecting anything.
5. Write the shim: an `rvviTrace` interface instance driven from the existing merged record,
   Option B (lane 0).
6. Run one directed kernel. Confirm non-zero coverage and run the suppress/restore non-vacuity check.
7. Move to Option A (lane-as-hart), with `tmask` suppression.
8. Add `COVER_RV32M` + `COVER_LEVEL_EXTENDED` to pick up `INSTR_DIVIDE`; run `div_edge` against it.
9. Run the full 50-program bank, produce the `.ucdb`, write the finding.

**Stop and report at step 3 and step 6** rather than pushing through — both are points where the
answer may be "this needs ImperasDV", and that is a perfectly good result to report.
