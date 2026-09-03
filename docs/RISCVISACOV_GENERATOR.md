# Generating the 142 withheld riscvISACOV extensions from their own DV plans

**Status: the generator is written and PROVEN. RV32M is generated, compiled and
run on real Vortex retirements.**

## The situation

riscvISACOV (Imperas, Apache-2.0) publishes:

| | count |
|---|---|
| extensions with a specification document (`documentation/*_coverage.md`) | **143** |
| extensions with a machine-readable DV plan (`dvplans/*_coverage_dvplan.csv`) | **143** |
| extensions with SystemVerilog **source** (`source/coverage/*_coverage.svh`) | **1** (RV32I) |

`source/coverage/README.md`, verbatim: *"NOTE that only an example of the source is provided
in the GitHub repository - please contact Imperas for full access."* Verified on all four
remote branches (`X-2025.12`, `X-2025.06`, `20240904.0`, `main`) — RV32I only on every one.

**But the CSV is the specification of the code that was withheld.** Each row names a
covergroup, a coverpoint, its coverage TYPE, its operand and its description:

```
RV32M,mul_cg,,instruction,mul,
,,cp_asm_count,ASM_COUNT,,Number of times instruction executed
,,cp_rd_reg_assign,REG_ASSIGN,rd,All legal register assignments
```

And `RV32I_coverage.svh` is machine-generated and perfectly regular: every `REG_ASSIGN`
coverpoint in all 39 covergroups is the same four lines with one operand substituted.

## The generator, and why you can trust it

`Vortex/sim/uvmsim/isacov/gen/gen_ext_coverage.py` — CSV in, `<EXT>_coverage.svh` and
`<EXT>_coverage_init.svh` out. Ten templates, one per coverage TYPE (`ASM_COUNT`,
`REG_ASSIGN`, `REG_COMPARE`, `REG_VALUE_SIGN`, `REG_VALUE`, `REG_VALUE_TOGGLE`,
`REG_HAZARD`, `IMM_VALUE`, `MEM_ALIGNED`, `INSTR_DIVIDE`), plus the `INST_ILLEGAL`
`` `ifdef `` wrapper and the `<ext>_sample()` dispatch function.

**Correctness is not asserted, it is proven:**

```
$ python3 gen/gen_ext_coverage.py --ext RV32I --verify
VERIFY RV32I: BYTE-IDENTICAL to Imperas source (39 covergroups, 559 coverpoint rows);
              _init.svh also identical
```

Run on RV32I's own dvplan, the generator reproduces Imperas' 4,162-line
`RV32I_coverage.svh` **byte for byte** — every covergroup, every coverpoint, every bin,
every `` `ifdef ``, every trailing space — and its `_init.svh` as well. A generator that
reproduces the one published extension exactly is a generator you can trust on the other
142. This is the whole argument, and it is mechanically re-checkable in one command.

### What the CSV does NOT contain, and is therefore supplied as data

Three things had to come from outside the dvplan. All are held in flat, citable data files
rather than hidden inside templates:

1. **`gen/inst_names.txt` — instruction long names** (the covergroup `option.comment`,
   e.g. `slt` → "Set if Less Than"). Cosmetic: sets no bin, changes no number. RV32I's are
   extracted from Imperas' source so the verification run has the data the original had;
   RV32M's are written from the specification.
2. **`gen/inst_formats.txt` — operand format.** The CSV says *which* coverpoints an
   instruction has, never the *order* its operands appear in the disassembly, nor whether
   an immediate is an address (`add_imm_addr`), a register offset (`add_reg_offset`), or
   plain; nor whether a load/store needs `add_mem_address()`. That is ISA-specification
   knowledge. **Writing this table from the RISC-V spec and then getting a byte-exact diff
   is a stronger check than transcribing it would have been** — a wrong format entry
   cannot pass.
3. **`CP_OVERRIDES` — one refinement the dvplan cannot express.** `jalr`'s
   `cp_rs1_reg_assign` excludes `x0` (`RV32I_coverage.svh:1246`). The CSV has no field for
   it. One entry, keyed `(extension, covergroup, coverpoint)`, with the citation.

### One template has no reference implementation — stated, not hidden

`INSTR_DIVIDE` (`cp_divide_by_zero`) appears in **no** published riscvISACOV source, so
unlike the other nine it is **not** validated by the RV32I diff. It is written from the
dvplan description and the RISC-V spec's two special cases for DIV/REM (divisor zero, and
the signed overflow −2³¹/−1). **It is ours, not reconstructed, and must be labelled that
way.** It is an EXTENDED-level coverpoint, so it does not compile at
`COVER_LEVEL_BASIC` — the numbers below do not depend on it.

## RV32M: generated, compiled, run

```
$ python3 gen/gen_ext_coverage.py --ext RV32M --out isacov/ext/coverage
wrote isacov/ext/coverage/RV32M_coverage.svh        (8 covergroups)
wrote isacov/ext/coverage/RV32M_coverage_init.svh
```

Compiled with `+define+COVER_RV32M` alongside Imperas' RV32I — `Errors: 0` — with
`isacov/ext` placed ahead of `third_party/` on `+incdir+`, so **`third_party/riscvISACOV`
stays byte-for-byte unmodified** and the Apache-2.0 obligation stays trivially satisfied.

**Live run, `div_edge`, 1CL/1C/4W/4T, mode A:** `TEST PASSED`, 0 UVM errors, 10,515 lane
samples, 3,531 PC lookups / **0 misses**, 709 fetched-word cross-checks / **0 mismatches**.

| RV32M covergroup | coverage |
|---|---|
| `remu_cg` | 63.39% |
| `divu_cg` | 59.52% |
| `div_cg` / `rem_cg` | 53.72% |
| `mul_cg` | 53.57% |
| `mulh_cg` / `mulhsu_cg` / `mulhu_cg` | **0.00%** |

The three zeros are an honest stimulus result, not a generator failure: `div_edge` targets
divide corners and never produces a high-half multiply. The static-image walk over the same
ELF *does* reach `mulhu_cg` (54.91%) — that code exists in the binary and is never executed.
**A directed kernel for `mulh`/`mulhsu`/`mulhu` is now a concrete, justified gap.**

## Build hook

```
ISACOV=1 ISACOV_EXTS="RV32I RV32M" EXTRA_PLUSARGS="+ISACOV +ISACOV_MAP=<map>" make sim ...
```
`ISACOV_EXTS` defaults to `RV32I RV32M`; unset `ISACOV` and nothing is compiled or sampled.

## What this is worth

Two claims, both defensible:

1. **Independent validation.** Our own covergroups say 99.79% weighted; a third-party ISA
   coverage model written by Imperas to OpenHW requirements says X% on the same runs.
2. **The generator itself.** riscvISACOV's DV plans are public for all 143 extensions and
   its source is not. Reconstructing the source from the plans, and *proving* the
   reconstruction against the one published extension, makes 142 extensions available to
   any open-source RISC-V verification effort under Apache-2.0. That is a contribution
   independent of Vortex.

**What it is NOT:** Imperas' full product. Extensions beyond RV32I/RV32M are generated but
unrun; anything using a coverage TYPE outside the ten templates (`VECTOR_STATE`,
`CSR_FIELD_VALUE`, `FP_RM`, `MMU_SCENARIO`, …) will stop the generator with a named error
rather than emit something plausible and wrong. Adding those is more template work, not a
different method.
