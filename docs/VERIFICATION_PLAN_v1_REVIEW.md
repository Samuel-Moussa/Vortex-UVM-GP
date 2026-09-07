# Review of `VERIFICATION_PLAN_v1.md` — verdict and corrections

**Reviewed 2026-09-03 against the tree at `feat/riscvisacov-coverage`.** Every claim below was
checked against the actual files, not against the plan's own prose.

## Verdict: adopt it, after four corrections

It is the best-structured verification document this project has. Three things it does that our
existing docs do not:

1. **Feature → check-mechanism → coverage item → test → status**, in one table, per feature. Our
   docs track coverage numbers and observations; they never enumerate the DUT's features and ask
   which are actually checked.
2. **The C-SENT rule** — *"a feature checked only by an in-kernel self-check is
   IMPLEMENTED-UNVERIFIED: the DUT graded its own homework."* That is the single sharpest sentence
   in any of our documents and it is exactly right. It is the same failure class as OBS-029.
3. **A real waiver register** with citations, separate from the coverage-exclusion script.

It also **independently found OBS-049** (as D-1), by a completely different route — reading the
coverage model against the decoder, where we found it by auditing what riscvISACOV could not score.
Two independent derivations of the same defect is strong evidence it is real.

---

## 1. D-8 is WRONG — and it is the one that matters

> *"`lockstep_pkg.sv:59-63` declares a `+LOCKSTEP_INJECT` negative-test hook that
> `lockstep_scoreboard.svh` never references. C-LOCK has no proven non-vacuity."*

**False.** The hook is wired — not in the scoreboard, but in the probe that feeds it:

```
tb/vx_commit_probe.sv:60   initial if ($test$plusargs("LOCKSTEP_INJECT")) lockstep_pkg::inject_en = 1'b1;
tb/vx_commit_probe.sv:116      if (lockstep_pkg::inject_en && !lockstep_pkg::inject_done) begin
tb/vx_commit_probe.sv:117          rec.data[0] = rec.data[0] ^ 64'h1;
tb/vx_commit_probe.sv:118          lockstep_pkg::inject_done = 1'b1;
```

It corrupts the first captured lane at the source, which then flows into the compare. The plan
searched only `lockstep_scoreboard.svh` and concluded the hook was dangling.

**And it has been run:** during the defence-evidence work, `+LOCKSTEP_INJECT` produced exactly
**one** `field_mismatch data` from exactly one injection — the textbook non-vacuity result.

**Consequences:** §5 criterion 3 ("C-LOCK likewise once D-8 is closed") is already satisfied, and
the P1 line "close D-8" should be struck. **C-LOCK's non-vacuity is proven today.**

## 2. EX-4 is stale — Zicond IS covered

> *"EX-4 Zicond — bins exist, never hit. **OPEN**"*

**False.** From the banked 1CL coverage (`cov/bank_1CL_1C_4W_4T/merged_raw.ucdb`):

```
bin czeq    16   Covered
bin czne    20   Covered
```

`multicore_isa` emits them via inline `.insn` (the compiler cannot: kernels build at
`-march=rv32imaf`, no Zicond in the arch string). EX-4 is **DONE**, not OPEN.

## 3. The configuration table is wrong about the TCU

> *"`EXT_TCU_ENABLE` — off. Enabled for `tcu_test` / `tcu_mt` only."*

**False.** `scripts/compile.sh:51` promotes it to a **global** compile define on every build:

```
COMPILE_OPTS="$COMPILE_OPTS +define+EXT_TCU_ENABLE=1"
```

This was deliberate (`0984bdf`): without it the passive TCU probe is `ifdef`-ed out and
`instr_class_cg_tcu` is never built. So the TCU is present and probed in **every** run. The plan's
EX-11 note "covergroup compiled out by default" follows from the same mistake and is also wrong.

## 4. §5's last row is answerable, not unmeasurable

> *"Toggle > 90% / line > 95% — Not measured in-repo — merged UCDB lives outside the tree."*

True of the **submodule**, misleading overall. The banks are in the outer repo and the numbers are
known and banked: **1CL 94.72% · 2CL 94.55% · L2/L3 93.18%** total, with per-category breakdowns in
`docs/COVERAGE_MAX_20260816.md`. The founding toggle target is met at neither config
(82.16% / 79.47%) and the reason is root-caused and waived (OBS-033/034, the icache
`.WRITE_ENABLE(0)` subtree). The row should state that, not "not measured".

---

## What I verified as TRUE

| ID | verdict | evidence |
|---|---|---|
| **D-1** | ✅ correct, = **OBS-049** | `cp_alu_op` samples `op_type` with no `xtype` guard. Their extra detail is right too: `INST_BR_JAL = 4'b1000 = INST_ALU_SRL`, so `JAL` scores as `srl`; and there is no `default` bin, so nothing reads as uncovered. |
| **D-2** | ✅ correct | `vortex_coverage_collector.svh:727-734` — `mem_operation_cg` is constructed only when `!use_axi`, and AXI is the default. |
| **D-3** | ✅ correct, and the worst one for a defence | `vortex_sanity_test.svh` overrides `wait_for_completion()` to return immediately and `check_results()` to `test_passed = 1'b1` unconditionally. **This test cannot fail and must never appear in a pass tally.** |
| **D-4** | ✅ correct | `kernel_launch_test.svh` has the vacuity gate; `random_instruction_stress_test.svh` has none. |
| **D-5** | ✅ correct | `get_next_item` appears **0** times in both `axi_driver.svh` and `mem_driver.svh`. |
| **D-6** | ✅ correct | `ref_model/Makefile:74-83` appends `-DXLEN_32` after the if/else. |
| **D-7** | ✅ correct, and now worse | `gen_coverage_exclude.sh:42-43` hardcodes absolute paths, and one of them points at a directory deleted in the `sim/uvmsim` move. |

## What is now partly overtaken by later work

* **EX-3 (M-extension, "no coverpoint")** — still true of *our* model, but a generated **RV32Zicsr /
  RV32M** riscvISACOV bank now scores `mul/mulh/mulhsu/mulhu/div/divu/rem/remu` per mnemonic
  (5/8 covergroups non-zero on `div_edge`). `INSTR_DIVIDE` (divide-by-zero, signed overflow) exists
  as a template but is EXTENDED-level and not compiled at BASIC.
* **EX-9 (CSR)** — RV32Zicsr covers all six mnemonics (6/6 non-zero, `csr_probe`). The **CSR-address**
  coverpoint the plan asks for is still missing from both models.
* **EX-2 (branch)** — still fully open. Neither model covers branch direction; riscvISACOV covers the
  branch *mnemonics* but taken/not-taken is not in its BASIC set.
* **P1 "sample the remaining `op_args` fields"** — independently reached the same conclusion from the
  other direction (`RISCVISACOV_STATUS.md` §6c): `dispatch_t` already carries `rd`, `rs1_data`,
  `rs2_data`, `rs3_data` at the probe we already bind, so this is a small edit, **not** a new probe.
  That materially lowers the cost estimate for the whole P1 row.

## Recommended merge into our tracking

* Adopt the feature table and the C-SENT rule wholesale.
* Strike D-8; correct EX-4, the TCU config row, and §5's last row.
* Fold **D-1 ≡ OBS-049** into one entry so it is not tracked twice.
* Raise **D-3** in priority. A test that cannot fail, counted in a pass tally, is the single most
  damaging thing in this list if an examiner finds it first.
* P0 "fold C-LOCK into the standard regression" is the highest-value item in the roadmap and should
  stay P0 — it converts every C-LOCK row from a claim into standing evidence.
