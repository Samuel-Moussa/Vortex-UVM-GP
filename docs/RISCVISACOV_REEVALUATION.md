# riscvISACOV — plan reevaluation after Step 4

**Supersedes parts of `RISCVISACOV_STEP3_REPORT.md`** (Finding A in that document is now
obsolete — see §4 below; I found the answer by digging further and it reverses the
conclusion in our favour).

**Status: Step 4 COMPLETE and PROVEN.** riscvISACOV RV32I compiles and samples in
QuestaSim 2021.2 with zero errors, driven by a standalone testbench with nothing from
Vortex attached.

---

## 1. Why only RV32I — definitive answer

**It is Imperas' business model, not a branch problem or a mistake.**

`third_party/riscvISACOV/source/coverage/README.md`, verbatim:

> *"NOTE that only an example of the source is provided in the GitHub repository - please
> contact Imperas for full access."*

Verified across **every branch on the remote**, not just the one we cloned:

| branch | files in `source/coverage/` | extensions with source |
|---|---|---|
| `X-2025.12` (default, ours) | 13 | **RV32I only** |
| `X-2025.06` | 12 | **RV32I only** |
| `20240904.0` | 14 | **RV32I only** (+ `RV32I_illegal_coverage.svh`, later dropped) |
| `main` | 0 | none — stale 2022 draft, README only |

Meanwhile `documentation/` carries **143** `<EXT>_coverage.md` spec files and `dvplans/`
carries **143** CSV DV plans. So the repository is a **catalogue plus one free sample**:
you can read exactly what RV32M/RV32F coverage *would* contain, but the implementation is
the paid product.

Confirmed the sample is genuine and complete, not a crippled stub: `RV32I_coverage.svh` is
170 KB containing **39 covergroups**, matching the published "RV32I 39 instr / 39 cg"
figure exactly, and containing zero M/F mnemonics.

Also worth knowing: `ChangeLog.md` carries a **different and contradictory** licence header
to `LICENSE.md` — *"THIS SOFTWARE CONTAINS CONFIDENTIAL INFORMATION AND TRADE SECRETS OF
IMPERAS SOFTWARE LTD. USE, DISCLOSURE, OR REPRODUCTION IS PROHIBITED…"*. `LICENSE.md` says
Apache-2.0. Add this to the licence question already flagged for Samuel.

**Consequence for the plan:** the handover's Step 8 (`COVER_RV32M` → run `div_edge`) and
the RV32F ambition are **not executable**. `RISCV_coverage_base.svh:56-57` includes
`coverage/RV32M_coverage.svh` unconditionally when `COVER_RV32M` is defined, and that file
does not exist on any branch — it is a hard compile error, not a silent no-op.

**Does that kill the idea? No — and here is the honest value calculation:**

- RV32I is the *base* ISA. In these workloads (vecadd, FFT, riscv-dv, the 50-program bank)
  it is the large majority of dynamic instructions — every load, store, branch, jump, and
  integer ALU op.
- The **independence argument survives completely.** "Our own covergroups say 99.79%; an
  independent third-party ISA model, written by Imperas to OpenHW requirements, says X% on
  the same runs" is a genuinely strong external-validation claim, and it is the entire
  point of doing this.
- What is lost: M (`div_edge` exists specifically for divide corner cases) and F
  (`fpu_test`/`fpu_mt`). Those stay covered only by our own model.

**Recommended framing:** *"RV32I — the only extension with public source"* — stated plainly.
Do not imply broader ISA coverage.

---

## 2. Step 4 result: it compiles, elaborates, and samples correctly

```
vlog -sv +incdir+<shadow> +incdir+third_party/riscvISACOV/source \
     +define+COVER_BASE_RV32I +define+COVER_RV32I +define+COVER_LEVEL_BASIC \
     isacov_smoke_tb.sv
→ Errors: 0, Warnings: 0
```

Two blockers were found and both are solved:

**(a) `idvPkg` / `idvApiPkg`** — the ImperasDV packages, the handover's "single biggest
go/no-go risk". **Resolved.** Across the entire source tree only **two** idv symbols are
ever referenced: `idvMsgFatal` (7 sites, all inside `` `ifdef `` branches that only compile
on a contradictory base-ISA selection) and `idvRefCoverPointNext` (2 sites, both inside
`sample_csrs()`). Both are stubbed faithfully in
`Vortex/sim/uvmsim/isacov/idv_stubs.sv` — 61 lines, ours, no Imperas code. **No ImperasDV
licence or tool is required.**

**(b) `RISCV_coverage_vectors.svh`** — included **unconditionally** at
`RISCV_coverage_base.svh:41` and **not shipped** in the sample (it is RVV vector support).
Resolved with a shadow include directory placed ahead of `third_party/` on the `+incdir+`
path, so `third_party/riscvISACOV` stays **byte-for-byte unmodified** — which also keeps
the Apache-2.0 obligation trivially satisfied.

### The model is real: 39 covergroups, 216 coverpoints, 2,918 bins

Elaborated and confirmed in a UCDB. And it samples correctly — 4 hand-assembled RV32I
retirements produced **exactly** the three covergroups they should:

```
RV32I::addi_cg    39.93%     (sampled twice)
RV32I::add_cg     29.91%
RV32I::sub_cg     29.91%
   ...all 36 other covergroups: 0.00%
```

**This doubles as the non-vacuity proof the handover asks for in Step 6**, and it happened
by accident in the most convincing way possible — see §3.

---

## 3. The finding that changes the design: `disass` is the primary input, not `insn`

The handover listed this as UNKNOWN #4 — *"if it is only for messages, pass `""`"*.

**The answer is the opposite: pass `""` and coverage is permanently 0%.**

`RISCV_coverage_base.svh:1381`:
```systemverilog
function string get_inst_name(bit trap, int hart, int issue, string disass);
    string insbin, ins_str, ops;
    int num = $sscanf (disass, "%s %s %s", insbin, ins_str, ops);
    return ins_str;                        // <-- the SECOND token
endfunction
```
and `RV32I_coverage.svh:3798` dispatches on it:
```systemverilog
case (traceDataQ[hart][issue][0].inst_name)
```

**Operands come from the same string.** `RISCV_instruction_base.svh:119-125`:
```systemverilog
if (this.ops[i].key[0] == "x") begin
    int idx = get_gpr_num(this.ops[i].key);      // register number PARSED FROM TEXT
```

So both instruction identity *and* register numbers are obtained by **parsing the
disassembly text**. The `insn` word is stored into `rvviData` but is not what drives
covergroup selection.

**I proved this empirically rather than by reading alone.** The first smoke run passed
`disass = "addi x5,x0,10"`, so `$sscanf` read the mnemonic as the second token —
`"x5,x0,10"` — which matched no case:

| run | disass format | coverage | bins hit |
|---|---|---|---|
| 1 | `"addi x5,x0,10"` | **0.00%** | 0 |
| 2 | `"00a00293 addi x5,x0,10"` | **2.55%** | 21 |

Identical RTL-side data, identical everything else. That is a textbook non-vacuity
demonstration and it is already in hand.

**Required format:** `"<hex> <mnemonic> <operands>"`, numeric register names (`x5`, not
`t0`), no pseudo-instructions.

---

## 4. This makes the integration EASIER than the handover assumed — no new probe

My Step-3 report concluded we needed a new fetch-stage probe to capture the raw `insn`
word (it is in `fetch_t`, `VX_gpu_pkg.sv:567`, but is dropped before `commit_t`). **That
conclusion is now obsolete.** Since identity and operands both come from `disass`, and
`disass` can be keyed by **PC** — which the existing retirement record already carries —
no new RTL probe is needed at all.

**Every kernel already ships a disassembly file.** `fft_par16/fft_par16.dump`, produced by
the normal build:
```
80000000: f3 22 10 fc  	csrr	t0, nw
80000004: 17 03 00 00  	auipc	t1, 0x0
```
Default flags emit ABI names (`t0`) and pseudo-ops (`csrr`), which the model's
`key[0] == "x"` test would reject. But with the right flags — **verified working**:
```
$ objdump -d -M numeric,no-aliases fft_par16.elf
80000000:  fc1022f3    csrrs  x5,0xfc1,x0
80000004:  00000317    auipc  x6,0x0
80000008:  73c30313    addi   x6,x6,1852
8000000c:  0062900b    .4byte 0x62900b          <- Vortex custom op, correctly unmatched
```
Numeric registers, real mnemonics, and Vortex's custom instructions degrade gracefully to
`.4byte` which matches no RV32I covergroup — exactly right.

**So the shim is: build a static `PC → "hex mnemonic ops"` map from the objdump at sim
start, look it up at each retirement.** Vortex kernels are not self-modifying, so a static
map is exact. This is cheaper, needs no DPI, no SimX disassembler call, and no RTL change.

**Net: the handover's "this is a shim, not a new probe" claim is TRUE after all — but for
a completely different reason than it gave.** Not because `insn` is available (it isn't at
the commit stage), but because the model wants text keyed by PC, and we already generate
that text as a build artifact.

---

## 5. Revised plan

| # | step | status |
|---|---|---|
| 1 | Clone both repos to `third_party/` | ✅ done |
| 2 | Inventory | ✅ done — RV32I only, all branches |
| 3 | `idvPkg` go/no-go | ✅ **GO** — 61-line stub, no ImperasDV |
| 4 | Standalone compile + elaborate | ✅ done — 39 cg / 2,918 bins, samples correctly |
| 5 | **objdump → PC-keyed disassembly map loader** | next |
| 6 | Shim: existing retirement record → `rvviTrace` wires, Option B (lane 0) | next |
| 7 | Run one kernel, confirm non-zero + non-vacuity | — |
| 8 | Option A (lane-as-hart) with `tmask` suppression | — |
| ~~9~~ | ~~RV32M / RV32F~~ | ❌ **impossible** — no public source |
| 9' | Full 50-program bank → 4th UCDB → written finding | — |

**Fields the shim must drive**, read from the consuming code
(`RISCV_coverage_rvvi.svh:67-138`), not guessed from the interface declaration:
`valid, order, insn, trap, halt, intr, mode, ixl, pc_rdata, pc_wdata, x_wb, x_wdata[],
f_wb, f_wdata[], v_wb, v_wdata[], csr_wb, csr[], lrsc_cancel`.
For RV32I/BASIC only `valid, order, pc_rdata, x_wb, x_wdata, trap` carry information;
`mode=2'b11` (Vortex is M-mode only), `ixl=2'b01` (XLEN=32), the rest tie to zero. All are
`wire`, so they must be **driven** by a module, not assigned from a class — the smoke
testbench already demonstrates the exact pattern.

---

## 6. Assessment of the Arabic explainer

**It is genuinely good** — accurate on architecture, well-sequenced, and the pedagogy is
strong. The bank-separation rationale, the Option A/B/C trade-off, the reasoning for
starting at lane 0 (so a failure is attributable), and the closing two-layer split (ISA
coverage from riscvISACOV vs. SIMT coverage from our own model) are all correct and are
the right framing for the appendix.

**Three corrections before any of it reaches a slide:**

1. **§6 and §18 repeat "the sample point is already built — this is a shim, not a new
   probe."** The conclusion is right but the stated reason is wrong: `commit_t` does not
   carry the instruction word (`VX_gpu_pkg.sv:651-663`). It works because the model wants
   *disassembly text keyed by PC*, which we get from objdump. If the deck states the
   original reason, an examiner reading `commit_t` can falsify it in thirty seconds.

2. **§14/§16/§24 promise MUL/DIV/RV32M coverage.** Not available — no public source. §24's
   Step 8 ("أضف RV32M ... خصوصًا divide-by-zero") cannot be executed.

3. **§22's numbers are illustrative, not measured** — `559 / 487 / 87.1%` is invented for
   explanation. Legitimate in a teaching document; **must not** appear as a result. The
   only real measured numbers so far are 39 covergroups / 216 coverpoints / 2,918 bins,
   and the 2.55% smoke figure from four synthetic instructions.

**One thing it gets exactly right and should be kept:** §20's non-vacuity framing, and the
closing statement that adapting a CPU-oriented ISA coverage model onto a SIMT retirement
architecture is itself the contribution. That is the real finding here, and §12's `tmask`
analysis (an inactive lane must not be sampled, or coverage inflates silently) is precisely
the technical core of it.

---

## 7. Steps 5-7 DONE — end-to-end on real Vortex silicon-model retirements

**Measured 2026-09-03. One `vecadd_lite` run, 1CL/1C/4W/4T, `+ISACOV`.**

```
[ISACOV] loaded 6216 disassembly entries from vecadd_lite_map.txt
[ISACOV]   retirements samp : 1677
[ISACOV]   PC lookups hit   : 1677
[ISACOV]   PC lookups MISS  : 0
[ISACOV]   fetch PCs seen   : 807
[ISACOV]   word cross-checks: 807
[ISACOV]   word MISMATCHES  : 0
*** TEST PASSED ***   Total Cycles: 9915   Instructions: 1881   UVM_ERROR : 0
```

**No regression:** 9,915 cycles and 1,881 instructions — byte-identical to the documented
baseline. The binds are plusarg-gated, so a run without `+ISACOV` is unchanged.

### What was built

| file | role |
|---|---|
| `isacov/isacov_pkg.sv` | PC→disassembly map, loader, fetched-word cross-check, end-of-run report |
| `isacov/vx_instr_word_probe.sv` | **new passive probe**, bound into every `VX_fetch` |
| `isacov/vortex_rvvi_shim.sv` | bound into every `VX_commit`; drives `rvviTrace`, calls `cov.sample()` |
| `isacov/isacov_binds.sv` | the two binds, inside `vortex_isacov_top` |
| `isacov/gen_disass_map.sh` | objdump → map |
| `flists/isacov.flist` | opt-in compile unit |
| `scripts/compile.sh`, `scripts/simulate.sh` | `ISACOV=1` hooks (no-op when unset) |

### The new probe, and why it earns its place

`vx_instr_word_probe` reads `fetch_if.data.instr` at the fetch handshake
(`VX_fetch.sv:131`) and hands `{PC, word}` to `isacov_pkg`, which compares it against the
word objdump recorded at that PC. **807 cross-checks, 0 mismatches** — that is the run's
own proof that the disassembly scoring coverage came from the binary that actually
executed. Without it, a stale ELF would fabricate ISA coverage silently, and this project
has already been burned by exactly that failure mode (`fft_par16`, 2026-09-01, the
`.kernel_config.stamp` gap). The probe is strictly passive and never gates a verdict.

### Two measurable things learned

**(a) A file-scope `bind` is silently dropped.** The first integration run passed cleanly
and produced *zero* `[ISACOV]` output — the binds sat in a `$unit` nothing instantiated, so
Questa never elaborated them. Fixed by putting them inside `vortex_isacov_top` and passing
it to `vsim` as a second top. **A green run proved nothing here** — the same trap as
OBS-029, in a new place.

**(b) Static image ≠ dynamic execution, and they fail in opposite directions.** The same
model, fed the whole `fft_par16` static text once per instruction, versus fed real
`vecadd_lite` retirements:

| | static walk (1,127 instrs, once each) | dynamic run (1,677 retirements) |
|---|---|---|
| covergroups at 0% | 9 of 39 | **14 of 39** |
| `add_cg` | 66.51% | **74.55%** |
| `addi_cg` | 76.38% | **86.45%** |
| `sw_cg` | 78.33% | **80.62%** |

Dynamic reaches *fewer mnemonics* (cold code never executes) but scores *higher on the ones
it does reach* (real operand and register diversity accumulates over repeated execution).
Neither is a substitute for the other, and only the dynamic figure is a verification result.

### Status against the revised plan

| # | step | status |
|---|---|---|
| 5 | objdump → PC-keyed map loader | ✅ done, 0 lookup misses on 1,677 retirements |
| 6 | shim: retirement → `rvviTrace`, Option B (lane 0) | ✅ done |
| 7 | one kernel, non-zero + non-vacuity | ✅ done — 25 of 39 covergroups non-zero, `fence_cg` 100% |
| 8 | Option A (lane-as-hart) with `tmask` suppression | next |
| 9' | full 50-program bank → 4th UCDB → written finding | after 8 |

---

## 8. Step 8 DONE — Option A (lane-as-hart) and Option B (lane 0), and what A buys

**Measured 2026-09-03, `vecadd_lite`, 1CL/1C/4W/4T, one build, mode chosen at runtime
by `+ISACOV_MODE=<A|B>` so the two are directly comparable.**

| | mode B (lane 0) | mode A (lane as hart) |
|---|---|---|
| lane-samples | 1,677 | **4,581** (2.73x) |
| PC lookups / misses | 1,881 / **0** | 1,881 / **0** |
| fetched-word cross-checks / mismatches | 807 / **0** | 807 / **0** |
| RV32I covergroups non-zero | 25 / 39 | 25 / 39 |
| RV32I unweighted mean | **37.07%** | **37.07%** |
| covered BINS | identical | identical |

`NHART = `NUM_THREADS`, `hart = sid*`SIMD_WIDTH + lane`, every commit beat sampled (not
just `sop`), and only `tmask[l] == 1` lanes ever sampled.

### The finding: 2.73x more samples buys ZERO additional bins

Not one bin differs between A and B. Only the hit COUNTS move (`add_cg`'s `cp_rd_sign.neg`
goes 32 -> 119, `cp_rs1_sign.neg` 36 -> 132).

**This is not a defect and not a stimulus gap — it is what an ISA coverage model IS.** At
`COVER_LEVEL_BASIC` every coverpoint is a function of (mnemonic, register NUMBERS, value
sign). Across the lanes of a warp the mnemonic and all three register numbers are
identical by construction — that is what SIMT means — so the only lane-varying quantity is
the sign of a value, and sign saturates almost immediately.

**So this measurement quantifies the limit of the third-party model on a GPU:**
riscvISACOV is structurally blind to SIMT width. It can tell us the RV32I instruction
space was exercised; it can say nothing about thread divergence, mask shapes, warp
occupancy, barriers or reconvergence. Those are exactly what our own collector covers
(`cp_active_threads`, `cross_dvg_depth`, `cross_sfu_threads`, `sched_state_cg`), and this
is the hard evidence that the two models are complementary rather than redundant.

**Report BOTH numbers.** Quoting only A would imply SIMT credit the model cannot give.

### A real defect the A/B comparison exposed in our own shim

The first A/B run came back byte-identical, which was suspicious enough to look at *why*.
The shim was driving `x_wdata` as "the value written this cycle" — clearing the array and
setting only the `rd` slot.

**RVVI defines `x_wdata` as a full 32-register SNAPSHOT**, and riscvISACOV depends on it:
`RISCV_instruction_base.svh:444` reads `current.rs1_val = prev.x_wdata[rs1]` — source
operand values come from the PREVIOUS retirement's snapshot. With the shortcut, a source
operand read as 0 unless it happened to be the immediately preceding instruction's `rd`.

Fixed: each hart now carries its own persistent architectural register file, updated on
every writeback (per-hart is correct for SIMT — each thread has its own registers).

**Honest result of the fix at BASIC level: no bin changed.** Dependency chains in real
code meant `rs1 == previous rd` often enough that both sign bins were already reached. The
fix still matters — it is required for any EXTENDED-level `REG_VALUE` / `REG_HAZARD`
analysis, where feeding fabricated operand values would produce confidently wrong coverage
— but it must not be claimed as a coverage gain.

### Single top, as required

The binds now live inside `vortex_tb_top` under `` `ifdef ISACOV `` (added at the end of
its existing bind block), so `vortex_tb_top` remains the ONE elaboration top and the
second-top workaround is gone. Confirmed live from the run log:
`vortex_tb_top.dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.commit.u_rvvi_shim
mode=A NHART=4 LANES=4 sampled=4581`.

### Vortex-specific ISA — confirmed covered by OUR collector, not left to a third party

No third-party model covers Vortex's custom instructions, and none ever will. Checked the
RTL's complete custom opcode set against `tb/vx_instr_probe.sv`:

| RTL opcode set | count | covered in our collector |
|---|---|---|
| `INST_SFU_{TMC,WSPAWN,SPLIT,JOIN,BAR,PRED,CSRRW,CSRRS,CSRRC}` (`VX_gpu_pkg.sv:377-385`) | 9 | ✅ `cp_sfu_op`, all 9 bins (`vx_instr_probe.sv:174-183`) |
| `INST_ALU_{CZEQ,CZNE}` — Zicond (`VX_gpu_pkg.sv:197-198`) | 2 | ✅ `vx_instr_probe.sv:121-122` |
| `INST_TCU_WMMA` (`VX_gpu_pkg.sv:445`) | 1 | ✅ `instr_class_cg_tcu` (single op, no decode needed) |

**12 of 12 accounted for, nothing delegated to riscvISACOV.** These render as `.4byte` in
objdump, so they map to no RV32I covergroup and are correctly scored as nothing by the
third-party model — the division of labour is enforced by construction, not by convention.
