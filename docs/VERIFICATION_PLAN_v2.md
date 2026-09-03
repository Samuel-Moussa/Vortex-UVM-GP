# Vortex GPGPU — Enhanced Verification Plan v2

**Date:** 2026-09-03 · **DUT:** Vortex RISC-V GPGPU · **Env:** `Vortex/sim/uvmsim`
**Supersedes** `VERIFICATION_PLAN_v1.md` (corrections in §5) and the founding
`VERIFICATION_PLAN.md` (re-scoped targets in §5.3).

**Target: verifying the features that make Vortex a GPU**, not re-verifying RISC-V.

---

## 1. The organising principle: three coverage layers, with owners

The central lesson of the riscvISACOV work is that our model and a third-party ISA
model do not overlap **at all** — they share no bin. That is not redundancy to
resolve; it is a layering to make explicit.

| layer | question | owner | blind to |
|---|---|---|---|
| **L1 — ISA** | was the *instruction space* exercised? mnemonic, register index, operand sign, immediate | **riscvISACOV** (third party, independent) | **everything SIMT** — proven: lane-as-hart (4,581 samples) and lane-0-only (1,677) cover the *identical* bin set |
| **L2 — microarchitecture / SIMT** | was the *machine* exercised? warps, masks, divergence, coalescing, banks, hazards, caches | **ours** (`vx_*probe.sv` + collector) | operand values, register indices, per-mnemonic identity |
| **L3 — system / protocol** | was the *interface* legal and stressed? | **ours** (SVA + `vortex_coverage_collector`) | — |

**L1 is now real:** RV32I (Imperas) + RV32M / RV32Zicsr / RV32F (generated from
Imperas' own DV plans, generator proven by regenerating RV32I byte-for-byte). See
`RISCVISACOV_STATUS.md`.

**Rule:** never merge L1 and L2 UCDBs, and never quote a blended number. They have
different denominators over different axes.

**Rule (inherited from v1, kept verbatim):** a feature checked only by an in-kernel
self-check (C-SENT) is **IMPLEMENTED-UNVERIFIED** — the DUT graded its own homework.

---

## 2. Checking mechanisms

| ID | Mechanism | Non-vacuity proof |
|---|---|---|
| **C-END** | End-state equivalence vs SimX (byte-exact, poison/tolerance gated) | `negative_result_test` — fires at `0x800075d8` |
| **C-REV** | Reverse pass → dropped-store detection | `negative_dropped_store_test` — fires at `0x800075d8` |
| **C-LOCK** | Per-instruction lockstep vs SimX | **`+LOCKSTEP_INJECT` — PROVEN: 1 injection → exactly 1 `field_mismatch data`** (v1's D-8 said this was unwired; it is wired at `tb/vx_commit_probe.sv:60,116-118`) |
| **C-SVA** | 40 concurrent assertions (AXI / mem / DCR / status) | assertion-fire evidence captured |
| **C-RAL** | DCR register model + backdoor probe | `+DCR_RAL_INJECT` |
| **C-ISA** | **NEW — third-party ISA coverage (riscvISACOV)** | disassembly-format experiment: 0.00% → 2.55% on identical data; plus 0 map misses / 0 word mismatches per run |
| **C-ASSERT-GATE** | RTL runtime assertions counted into the verdict | `misalign_neg` — must report FAILED |

---

## 3. Feature decomposition — Vortex first

Status: **DONE** · **PART** · **OPEN** · **WAIVED**

### 3.1 SIMT control — the defining features

| # | Feature | RTL | Check | Coverage | Status |
|---|---|---|---|---|---|
| SIMT-1 | Warp scheduling, active/stalled occupancy | `VX_schedule.sv` | C-END | `sched_state_cg` | DONE |
| SIMT-2 | Divergence: split, mask partition | `VX_split_join.sv` | C-END, C-LOCK | `divergence_cg` | DONE |
| SIMT-3 | Nesting depth (IPDOM stack) | `VX_ipdom_stack.sv` | C-END | `cp_split_depth` | DONE |
| SIMT-4 | Reconvergence: join, then/else | `VX_split_join.sv` | C-END | `reconverge_cg` | DONE |
| SIMT-5 | Local barrier | `VX_wctl_unit.sv` | C-END, C-SENT | `barrier_cg` | DONE |
| SIMT-6 | TMC | `VX_wctl_unit.sv` | C-END | `tmc_cg` | DONE |
| SIMT-7 | WSPAWN | `VX_wctl_unit.sv` | C-LOCK only | `wspawn_cg` | PART — **W-9**: spawn args are stack-resident, not staged to SimX, so C-END is undefined |
| SIMT-8 | Predication | `VX_wctl_unit.sv` | C-END | `cp_sfu_op.pred` | PART — no predicate-**mask** coverpoint |
| SIMT-9 | **VOTE / SHFL** (8 ops: all/any/uni/bal, up/down/bfly/idx) | `VX_decode.sv:507-517` | C-END | **NONE — and they mis-bin into `cp_alu_op`** | **OPEN — G-1 (OBS-049)** |
| SIMT-10 | **SIMD beat splitting / uop sequencing** | `VX_uop_sequencer.sv` | C-LOCK (aggregates beats) | **none** | **OPEN — G-7** |
| SIMT-11 | Global (cross-core) barrier | `VX_gbar_unit.sv` | — | waived at 1 core | OPEN at ≥2 cores — **W-3** |

### 3.2 Issue, operands, hazards

| # | Feature | RTL | Coverage | Status |
|---|---|---|---|---|
| ISS-1 | Instruction buffer occupancy / per-warp arbitration | `VX_ibuffer.sv` | none | **OPEN — G-8** |
| ISS-2 | **Register hazards (RAW/WAW/WAR)** | `VX_scoreboard.sv` | none in L2; **L1 has `REG_HAZARD` but only at EXTENDED level** | **OPEN — G-4** |
| ISS-3 | **Operand collector / GPR bank conflicts** (`NUM_GPR_BANKS`) | `VX_opc_unit.sv`, `VX_operands.sv` | none | **OPEN — G-5** |
| ISS-4 | Gather unit / PE switching | `VX_gather_unit.sv`, `VX_pe_switch.sv` | none | OPEN |

### 3.3 Execute

| # | Feature | Check | L1 (riscvISACOV) | L2 (ours) | Status |
|---|---|---|---|---|---|
| EX-1 | Integer ALU | C-END, C-LOCK | ✅ per mnemonic (39) | `cp_alu_op` 14 bins, **contaminated** | PART — **G-1** |
| EX-2 | **Branch / jump, taken vs not-taken** | C-LOCK (PC) | mnemonics ✅, direction ✗ | **none** | **OPEN — G-2** |
| EX-3 | M-extension | C-END, C-LOCK | ✅ **RV32M bank, 8 cgs** | none | PART — L1 closes identity; **divide-by-zero / signed-overflow still open (G-3)** |
| EX-4 | Zicond CZEQ/CZNE | C-END | ✗ (no dvplan exists, ever) | `cp_alu_op` czeq=16 czne=20 **hit** | **DONE** (v1 said OPEN — stale) |
| EX-5 | FPU op classes | C-END, C-LOCK | ✅ RV32F 26 cgs | `cp_fpu_op` 13 bins | DONE |
| EX-6 | FP rounding mode | C-END | `cp_rm` (EXTENDED) | **none** — `fpu_args_t.frm` unsampled | OPEN — G-6 |
| EX-7 | FP special values (NaN/Inf/denormal/±0) | C-LOCK | `REG_FPVALUE` (EXTENDED, **our template, unvalidated**) | none | OPEN — G-6 |
| EX-8 | CSR access | C-END | ✅ **RV32Zicsr 6/6 cgs** | `cp_sfu_op` 3 bins | PART — CSR **address** uncovered in both |
| EX-9 | Tensor core WMMA | C-END | ✗ never | `tcu_class_cg` mask only | PART — operand shape/precision uncovered |
| EX-10 | Perf-counter CSRs | — | — | — | WAIVED — W-1 |

### 3.4 GPU memory — where the biggest gap is

| # | Feature | RTL | Coverage | Status |
|---|---|---|---|---|
| **MEM-1** | **Memory coalescing** — per-warp address divergence collapsed into cache lines | **`VX_mem_coalescer.sv`**, instantiated `VX_mem_unit.sv:160`, exports a `misses` counter | **NONE** | **OPEN — G-0, the highest-value gap in this plan** |
| MEM-2 | Load/store byte/half/word | `VX_lsu_slice.sv` | `cp_lsu_op` | DONE |
| MEM-3 | Float load/store | `VX_lsu_slice.sv` | L1 `flw_cg`/`fsw_cg` ✅; L2 `lsu_args_t.is_float` unsampled | PART |
| MEM-4 | **Unaligned access** | `VX_lsu_slice.sv:189` | — | **WAIVED — W-10.** Not a gap: Vortex **does not support** misaligned data access. The RTL asserts, there is no trap, the access is silently torn (OBS-013). Guarded by the `misalign_neg` negative test, which MUST report FAILED. v1 listed this as OPEN and the founding plan graded it FAIL; both are mis-specified. |
| MEM-5 | Local memory / scratchpad | `VX_local_mem.sv` | none (code coverage only, 73.19% toggle) | OPEN — G-9 |
| MEM-6 | LMEM bank conflicts | `VX_local_mem.sv` | none | OPEN — G-9 |
| MEM-7 | Cache hit/miss | `VX_cache_bank.sv` | `cache_event_cg` | DONE |
| MEM-8 | MSHR | `VX_cache_mshr.sv` | `cp_mshr_stall` binary | PART — no occupancy histogram |
| MEM-9 | Set/way/bank distribution, replacement | `VX_cache_repl.sv` | none | OPEN |
| MEM-10 | Bypass path | `VX_cache_bypass.sv` | none | OPEN |
| MEM-11 | L2/L3 | `VX_cache_cluster.sv` | config-keyed | PART — own bank exists (93.18%) |
| MEM-12 | Cross-core arbitration | `VX_mem_arb.sv` | none | OPEN — G-10 |
| MEM-13 | Dropped store | — | **C-REV** | DONE (AXI path only) |
| MEM-14 | Atomics | — | — | WAIVED — W-2 |

### 3.5 Bus, system, multi-core, termination

| # | Feature | Check | Status |
|---|---|---|---|
| BUS-1..4 | AXI handshake, legality, outstanding, backpressure | C-SVA (30 props) + `axi_transaction_cg` | DONE (outstanding **depth** uncovered) |
| BUS-5 | AXI error responses | — | WAIVED — W-4 |
| BUS-6 | Custom mem interface | C-END, C-SVA (port 0 only) | PART |
| BUS-7 | DCR config | **C-RAL** | DONE |
| BUS-8 | Launch/completion handshake | C-END | DONE |
| MC-1 | Multi-core same kernel | C-END | PART |
| MC-2 | Cross-core functional interaction | C-END | OPEN — G-10 |
| MC-3 | Multi-cluster | C-END | PART (2CL bank 94.55%) |
| **TERM-1** | **Termination: `tmc x0` → `busy` deassert** (NOT ebreak — OBS-024) | C-END, C-SVA | DONE |
| **TERM-2** | **RTL runtime-assertion error gate** | **C-ASSERT-GATE** | DONE — `misalign_neg` |
| ~~EXC-2~~ | ~~Trap cause classification~~ | — | **WAIVED — W-11. Vortex has NO trap architecture**: no trap logic in `VX_decode.sv` or `VX_csr_data.sv`; `mcause` exists only as a number in `VX_types.vh:59`. You cannot cover trap causes on a machine that does not take traps. v1 listed OPEN; founding plan graded FAIL. Re-scoped to TERM-1/TERM-2. |

---

## 4. Gap-closure backlog (ranked by verification value, not by effort)

| ID | Gap | Why it matters | Proposed coverpoints | Cost |
|---|---|---|---|---|
| **G-0** | **Memory coalescing** | The defining GPU memory behaviour. A warp's 4 lanes may hit 1 line (fully coalesced), N lines (fully divergent), or anything between — that ratio is the whole point of a GPU memory system, and **we measure none of it.** The RTL even exports `misses` for us. | bind a probe on `VX_mem_coalescer`: `cp_coalesce_ratio` (1 / 2 / … / NUM_REQS lines per request), `cp_access_pattern` (uniform / unit-stride / strided / scattered), `cross` with `tmask` occupancy | ~1 d |
| **G-1** | ALU class contamination (**OBS-049 ≡ v1 D-1**) | `vote.all`, `mul`, `beq` all score as `add`; `JAL` scores as `srl`; **VOTE/SHFL have no coverage anywhere**; no `default` bin so nothing reads uncovered | pass `op_args.alu.xtype`; split into `cp_alu_arith` / `cp_alu_branch` / `cp_alu_muldiv` / `cp_vote_shfl`, each `iff` its xtype, each with `bins other[] = default` | 0.5 d |
| **G-2** | Branch direction | taken/not-taken is invisible to both layers | `cp_br_taken` cross `cp_alu_branch` | 0.5 d (with G-1) |
| **G-3** | Divide corner cases | divide-by-zero and −2³¹/−1 are the classic DIV bugs | either enable L1 `COVER_LEVEL_EXTENDED` (`INSTR_DIVIDE`) or add `cp_div_special` in L2 | 0.5 d |
| **G-4** | Register hazards | `VX_scoreboard.sv` is real hazard logic with no functional coverage | `cp_hazard_type` (RAW/WAW/WAR/none) from the RTL scoreboard's stall reason | 1 d |
| **G-5** | GPR bank conflicts | `NUM_GPR_BANKS` collector is a real arbiter that can starve | `cp_bank_conflict_degree`, cross with warp | 1 d |
| **G-6** | Operand values, incl. FP specials | **L2 has ZERO operand-value coverage, and `dispatch_t` already carries `rs1_data`/`rs2_data`/`rs3_data`/`rd` at a probe we already bind** — a small edit, not a new probe | `cp_rs1_sign`, `cp_rs2_sign`, `cp_fp_class` (NaN/Inf/denorm/±0), `cp_imm_sign` | 0.5 d |
| **G-7** | uop / SIMD beat splitting | `sop`/`eop` beat sequences are already in `commit_t` and unsampled | `cp_beats_per_instr`, cross with `tmask` | 0.5 d |
| **G-8** | Ibuffer occupancy | per-warp fetch buffering / starvation | `cp_ibuf_occupancy` per warp | 0.5 d |
| **G-9** | LMEM + bank conflicts | scratchpad is a GPU-defining feature; `lmem_stress` runs but scores nothing functional | `cp_lmem_bank_conflict`, `cp_lmem_pattern` | 1 d |
| **G-10** | Cross-core interaction | `cp_num_cores` is provenance, not behaviour | `cp_core_concurrency`, `cp_mem_arb_winner` | 1 d |

**Do G-0 and G-1 first.** G-0 is the largest genuinely-Vortex hole in the model;
G-1 is a defect that currently makes three feature rows unmeasurable and inflates
a fourth.

---

## 5. Corrections carried into this plan

### 5.1 To `VERIFICATION_PLAN_v1.md`
* **D-8 is FALSE** — `+LOCKSTEP_INJECT` is wired at `tb/vx_commit_probe.sv:60,116-118` and has been run (1 injection → 1 mismatch). C-LOCK's non-vacuity is proven. Strike it from P1.
* **EX-4 stale** — Zicond bins are hit (czeq 16 / czne 20 in the 1CL bank).
* **TCU config row wrong** — `compile.sh:51` promotes `+define+EXT_TCU_ENABLE=1` globally; the TCU is on in **every** build.
* **"Toggle/line not measured in-repo"** — the banks are in the outer repo: **1CL 94.72% · 2CL 94.55% · L2/L3 93.18%**.
* **D-1 ≡ OBS-049** — one defect, track once (G-1).
* v1's D-2..D-7 are **confirmed correct**; **D-3 (`vortex_sanity_test` cannot fail) should be top priority** — a test that cannot fail, counted in a pass tally, is the most damaging item on that list.

### 5.2 To the founding plan's sign-off bar
Two of its four failing rows are **mis-specified targets, not verification failures**:
* *"Memory access patterns — aligned / unaligned"* → unaligned is **unsupported** (W-10).
* *"Exception / interrupt types — all covered"* → **no trap architecture** (W-11).

Restate both as: *"unsupported behaviours are guarded by negative tests that must
fail"* — which is a stronger, and true, claim.

---

## 6. Waiver register (additions to v1's W-1..W-9)

| ID | Waived | Reason | Evidence |
|---|---|---|---|
| **W-10** | Unaligned data access | Not implemented: RTL asserts, no trap, access silently torn | `VX_lsu_slice.sv:189`, OBS-013, `misalign_neg` |
| **W-11** | Trap-cause / interrupt coverage | No trap architecture exists | no trap logic in `VX_decode.sv` / `VX_csr_data.sv`; `mcause` is a bare number at `VX_types.vh:59` |
| **W-12** | L1 ISA coverage of Vortex custom ops (SFU, VOTE/SHFL, TCU, Zicond) | No third-party model covers them and none can — Zicond has no dvplan in riscvISACOV at all | `RISCVISACOV_STATUS.md` §2 |
| **W-13** | L1 `*_reg_assign` (92% of the L1 denominator) | Register *allocation* is a compiler property, not a DUT property; Vortex's GPR file is a uniformly-indexed banked RAM with no per-index logic | `RISCVISACOV_STATUS.md` §6c — quote the 42.6% figure that excludes it, never the bare 10.3% |

---

## 7. Sign-off criteria

1. Every **DONE** row is checked by something other than C-SENT.
2. Every **WAIVED** row cites RTL, not convenience.
3. C-END, C-REV and **C-LOCK** are all proven non-vacuous in the standard regression.
4. C-LOCK runs in the standard regression, not a manual sweep. *(highest-value open item)*
5. No run reaches PASS with `num_comparisons == 0`.
6. `vortex_sanity_test` is excluded from every pass tally and labelled un-failable.
7. The UCDB merge passes the hits-invariant gate.
8. **L1 and L2 are reported as two numbers, never blended**, with W-13 applied to L1.
9. G-0 and G-1 closed before any claim that the GPU memory path or the ALU is covered.
