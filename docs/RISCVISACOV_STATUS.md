# riscvISACOV integration — consolidated status

**Branch `feat/riscvisacov-coverage`. Everything below is MEASURED; every number
names the run or command it came from.** Deep detail lives in
`RISCVISACOV_STEP3_REPORT.md` (inventory + licence), `RISCVISACOV_REEVALUATION.md`
(why RV32I only, the `disass` finding, mode A/B) and `RISCVISACOV_GENERATOR.md`
(the generator and tiers 1-2). This file is the single index.

---

## 1. What this is, in one paragraph

riscvISACOV is an independent third-party RISC-V ISA functional-coverage model
(Imperas, Apache-2.0). We drive it from real Vortex retirements so that our own
covergroups are cross-checked by something we did not write. It is a **fourth,
separate coverage bank** — the three existing banks (1CL 94.72%, 2CL 94.55%,
L2/L3 93.18%) are untouched and must stay that way.

## 2. Current state

| extension | source | covergroups | status |
|---|---|---|---|
| **RV32I** | Imperas (the only one they publish) | 39 | ✅ running |
| **RV32M** | **generated** from Imperas' dvplan | 8 | ✅ running |
| **RV32Zicsr** | **generated** | 6 | ✅ running |
| **RV32F** | **generated** (26 instruction cgs; 3 `csr` cgs excluded) | 26 | ✅ running |
| Zicond, SFU, VOTE/SHFL, TCU | — | — | ❌ no third-party model exists, ever |

**Measured coverage, one kernel each, 1CL/1C/4W/4T, mode A:**

| bank | kernel | result |
|---|---|---|
| RV32I | `vecadd_lite` | 25/39 non-zero, `fence_cg` 100% |
| RV32M | `div_edge` | 5/8 non-zero, `remu_cg` 63.39% |
| RV32Zicsr | `csr_probe` | **6/6 non-zero**, `csrrci_cg` 60.62% |
| RV32F | `fpu_test` | **21/26 non-zero**, mean 26.43%, `flw_cg` 58.59% |

Every run: `TEST PASSED`, 0 UVM errors, **0 PC-lookup misses, 0 fetched-word
mismatches**.

## 3. How it works

```
kernel.elf --objdump--> PC-keyed disassembly map --.
                                                    +--> riscvISACOV covergroups
VX_commit retirement --> vortex_rvvi_shim --> rvviTrace
VX_fetch  instr word --> vx_instr_word_probe --> cross-check the map
```

**riscvISACOV keys on DISASSEMBLY TEXT, not the instruction word**
(`RISCV_coverage_base.svh:1381` does `$sscanf(disass,"%s %s %s")` and returns the
second token; `RISCV_instruction_base.svh:119` parses register numbers out of the
same string). Proven empirically: the identical retirement scored **0.00%** with
`disass="addi x5,x0,10"` and **2.55%** with `"00a00293 addi x5,x0,10"`.

That is why no new decode probe was needed — every kernel already ships a
`.dump`, and `objdump -d -M numeric,no-aliases` produces exactly the required
form. Both flags are load-bearing: `numeric` because the model tests
`ops[i].key[0]=="x"`, `no-aliases` because pseudo-instructions match no
covergroup. Vortex custom ops render as `.4byte 0x...` and correctly match
nothing.

`vx_instr_word_probe` exists to answer one question: **is the disassembly we are
scoring the binary that actually ran?** It compares the fetched word against the
map's word at each PC. This project has already been burned by a stale ELF
surviving a source change (`fft_par16`, 2026-09-01).

## 4. Files

| file | role |
|---|---|
| `isacov/isacov_pkg.sv` | PC→disassembly map, loader, word cross-check, end-of-run report |
| `isacov/vx_instr_word_probe.sv` | passive probe bound into every `VX_fetch` |
| `isacov/vortex_rvvi_shim.sv` | bound into every `VX_commit`; drives `rvviTrace`, calls `cov.sample()` |
| `isacov/idv_stubs.sv` | 61-line `idvPkg`/`idvApiPkg` stubs |
| `isacov/isacov_dpi.c` | our implementation of `rvviRefCsrIndex` |
| `isacov/shadow/` | stub for `RISCV_coverage_vectors.svh` (shipped-but-missing) |
| `isacov/ext/coverage/` | GENERATED RV32M / RV32Zicsr / RV32F |
| `isacov/gen/gen_ext_coverage.py` | the dvplan→SystemVerilog generator |
| `isacov/gen/inst_names.txt`, `inst_formats.txt` | data the CSV does not contain |
| `isacov/gen_disass_map.sh` | objdump → map |
| `tests/kernel/csr_probe/` | new kernel: all six Zicsr forms |
| `tb/vortex_tb_top.sv` | the two binds, under `` `ifdef ISACOV `` |

**Run it:**
```
ISACOV=1 ISACOV_EXTS="RV32I RV32M RV32Zicsr RV32F" \
  EXTRA_PLUSARGS="+ISACOV +ISACOV_MODE=A +ISACOV_MAP=<map>" \
  make sim TEST=kernel_launch_test PROGRAM_NAME=<prog> ...
```
`+ISACOV_MODE=A` = lane-as-hart (default), `B` = lane 0 only.

## 5. The generator, and why it is trustworthy

Imperas publishes DV plans for **all 143** extensions and source for **one**.
`gen_ext_coverage.py` reconstructs the source from the plans, with one template
per coverage TYPE. Correctness is **proven, not asserted**:

```
$ python3 gen/gen_ext_coverage.py --ext RV32I --verify
VERIFY RV32I: BYTE-IDENTICAL to Imperas source (39 covergroups, 559 coverpoint rows);
              _init.svh also identical
```

It regenerates Imperas' 4,162-line `RV32I_coverage.svh` byte for byte. **This
check is re-run after every generator change and has caught real regressions.**

**62 of 142 dvplans need no new template** (2,094 covergroups) — but only
Zicsr mattered for Vortex. Measured across all 47 kernel ELFs: **0** atomics,
**0** `fence.i`, **0** compressed, **0** bit-manip. Quoting "62 extensions
available" would oversell it.

### Templates that are OURS, not reconstructed — state this wherever quoted

| template | validated by the RV32I diff? |
|---|---|
| ASM_COUNT, REG_ASSIGN, REG_COMPARE, REG_VALUE, REG_VALUE_SIGN, REG_VALUE_TOGGLE, REG_HAZARD, IMM_VALUE, MEM_ALIGNED | ✅ yes |
| **INSTR_DIVIDE** (RV32M) | ❌ no published source exists |
| **REG_FPVALUE, FP_RM, FP_FFLAG** (RV32F) | ❌ no published source exists |

The RV32F bins in particular are **our reading of IEEE-754 binary32**, not
Imperas'. RV32M/Zicsr rest almost entirely on validated templates; **RV32F does
not, and is the weakest claim in this work.**

## 6. Deliberate exclusions, each with a reason

* **RV32F's 3 CSR covergroups** (`csr_fcsr_cg`, `csr_fflags_cg`, `csr_frm_cg`) —
  different covergroup shape, sampled from `sample_csrs()`, and their
  `CSR_COMPARE` coverpoints need `idvRefCoverPointNext`, an **ImperasDV runtime
  API** we stub to `""`. Structurally unavailable.
* **`cp_frm`, `cr_rm_frm`, `cp_exception_flags`** — these read `rvvi.csr[]`,
  which the shim ties to zero. Emitting them would be **worse than omitting
  them**: an undriven coverpoint reliably hits its zero bin and reads as
  *covered*. That is the OBS-029/OBS-030 failure class. Recovering them means
  binding a probe on `VX_csr_data.fcsr` (`VX_csr_data.sv:81`, per-warp) and
  correlating by the uuid's core id — identified, not done.
* **`cp_rm` IS emitted and works**: it comes from the disassembly, and an omitted
  rm operand yields `dyn`, which is exactly what the RISC-V encoding means.
* **`cp_imm_value.neg` (Zicsr)** — the CSR immediate is a 5-bit *unsigned* field.
  Structurally unreachable; left honestly uncovered.

## 7. Findings this work produced

**OBS-049 — `op_type` is overloaded across ALU sub-types.** `EX_ALU` carries four
disjoint opcode namespaces in one field, keyed by `xtype`
(`VX_gpu_pkg.sv:205-209`), and our `cp_alu_op` does not qualify on it, so
`vote.all`, `mul` and `beq` all increment the **`add`** bin. **VOTE/SHFL have no
coverage of their own anywhere.** No reported number is invalidated (every
colliding code has a real arithmetic producer), but per-instruction counts are
not attributable. OPEN — see `RTL_OBSERVATIONS.md`.

**FP writebacks were silently dropped by our shim.** `commit_t.rd` is a *unified*
register number, `(reg_type << 5) | idx` (`VX_gpu_pkg.sv:910`). `32'b1 << rd`
sets no bit past 31 and `x_wdata[rd]` is an out-of-range write SystemVerilog
discards. Fixed; proven by new counters — `fpu_test` reports **`fp_wb=36`**,
previously structurally 0. Without this fix RV32F would have read 0% and looked
like a stimulus gap.

**SIMT lane diversity buys no ISA-coverage bins.** Mode A (4,581 lane samples)
and mode B (1,677) cover the **identical bin set** on `vecadd_lite`; only hit
counts move. At `COVER_LEVEL_BASIC` every coverpoint is a function of (mnemonic,
register *numbers*, value sign) and all of those are identical across a warp's
lanes by construction. **This quantifies the limit of any ISA coverage model on a
GPU** and is the strongest argument that the third-party model and our own SIMT
model are complementary, not redundant. Report both numbers.

**Static image ≠ dynamic execution, in both directions.** On `fft_par16`: the
static walk reaches *more mnemonics* (cold code) but scores *lower per
covergroup* than a dynamic run (less operand diversity). Only the dynamic figure
is a verification result. Used deliberately as a diagnostic: `div_edge`'s
`mulhu_cg` is 54.91% statically and **0% dynamically**, which proves the three
zero RV32M covergroups are a stimulus gap, not a generator failure.

## 8. Four silent failures hit — none announced itself

Recording these because each produced a **passing run that measured nothing**:

1. **File-scope `bind` is dropped.** It lands in a `$unit` nothing instantiates;
   Questa never elaborates it. First integration run passed with *zero* `[ISACOV]`
   output. Fixed by putting the binds inside `vortex_tb_top`, which also keeps it
   the single elaboration top.
2. **`+define+COVER_RV32Zicsr` was ignored** — the gating macros are ALL-CAPS
   (`COVER_RV32ZICSR`) while the include filenames stay mixed-case. Compile
   succeeded, run passed, no covergroups existed. `compile.sh` now uppercases;
   the log's `// RV32ZICSR - Enabled` is the check.
3. **The dvplan parser mis-attributed non-instruction covergroups.** Only
   `instruction` headers were recognised, so RV32F's three `csr_*_cg` coverpoints
   were grafted onto whichever instruction covergroup came last (`fsw_cg`) —
   17 CSR coverpoints on a store. Fixed; skipped covergroups are now printed.
4. **`get_gpr_reg` on an FP register halts the run** with
   `get_gpr_reg(f8) not found gpr`. Not silent, but the *cause* was: a template
   edit that appeared to apply had not. Caught because RV32F read 0.00%.

Plus one non-silent trap worth recording: **a C++ DPI will not load into
QuestaSim 2021.2** (`GLIBCXX_3.4.29 not found` — it ships gcc-7.4's libstdc++).
`isacov_dpi.c` is deliberately plain C with no libstdc++ dependency.

## 9. The ImperasDV question

| | licence |
|---|---|
| riscvOVPsim **model source** | Apache-2.0, genuinely open |
| riscvOVPsim **simulator binary** | OVP Fixed Platform Kits — free, no modification/redistribution, expires |
| **ImperasDV** (the DV product) | commercial; Imperas acquired by Synopsys, 2023 |

RVVI declares **66** `import "DPI-C"` functions, all supplied by ImperasDV.
QuestaSim does not complain at elaboration — it aborts on first call, and crt0
issues a `csrrs` before `main()`. **Exactly one is on our path**:
`rvviRefCsrIndex`, called from `add_csr()` (`RISCV_instruction_base.svh:490`).

It is a **pure name-to-number decoder**, so we implemented it
(`isacov/isacov_dpi.c`): standard names by table, `mhpmcounterN` parsed, hex
literals converted (how every Vortex GPU CSR is spelled), unrecognised returns
**-1** rather than a plausible wrong number. It makes no architectural decision
and cannot affect a verdict. **Implementing `rvviRefCsr*Value*` would be a
different matter and we have not.**

Obtaining the free riscvOVPsim would **not** unlock the `CSR_COMPARE`
coverpoints — those need the ImperasDV *runtime*, not the ISS. And we would not
want it: we already have a golden reference in per-instruction lockstep (SimX).

## 10. Regression status — the bank is untouched

* default build (no `ISACOV=1`): **9,915 cycles, 0 errors**
* `ISACOV=1` build without `+ISACOV`: **9,915 cycles, 0 errors, zero `[ISACOV]` output**
* `negative_result_test` and `negative_dropped_store_test`: **both still fire at `0x800075d8`**
* the three existing coverage banks: **not regenerated, not merged, not opened**

## 11. Not done, and why

* **`csr_probe` is NOT in `run_suite.sh`.** Adding it changes bank composition,
  and the banks are frozen for the defence deck. Samuel's call.
* **The 50-program riscvISACOV bank** (the fourth UCDB) is not built — it is
  ~50 runs and needs costing first.
* **`cp_frm` / `cp_exception_flags`** need an `fcsr` probe (§6).
* **OBS-049's fix** (split `cp_alu_op` by `xtype`, creating VOTE/SHFL coverage)
  changes `instr_class_cg_alu`'s denominator, so it needs its own bank.
* **RV64 / vector / bit-manip / atomics** — not executed by Vortex; skipped
  deliberately, measured not assumed.
