# COVERAGE RUN CHECKLIST & MATRIX — 2026-09-09

Execution plan for producing ONE current-build coverage picture spanning all stimulus
sources, with L1 (ISA) and L2 (SIMT/µarch) reported as separate families in a single
database. Follow top-down. Do not skip a GATE.

Primary config for everything below: **1CL / 1C / 4W / 4T, L2=0, L3=0, AXI**.

---

## 0. STANDING HAZARDS (re-read before each phase)

| # | Hazard | Guard |
|---|---|---|
| H1 | `merge_coverage.sh` / `run_suite*.sh` default `RESULTS_ROOT` to `Vortex/sim/uvmsim/results` (WRONG) when invoked as `bash scripts/...` instead of via `make` | **Always** `export VORTEX_UVM_RESULTS_DIR=/home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/results` first |
| H2 | A stale `latest` symlink at the wrong root can stage an unrelated old run | Never rely on `latest`; always collect by explicit run-dir list |
| H3 | Merging UCDBs from **different testbench builds** silently dilutes (19-cg frozen bank vs 23-cg current build) | Every UCDB in a bank must come from ONE compile. Verify covergroup COUNT before/after merge |
| H4 | Merging UCDBs across **configs** (1CL vs 2CL) is invalid | One bank per config, always |
| H5 | Only one process may hold the Questa `work/` library | Never compile while a sim runs |
| H6 | A script run from the wrong directory breaks `BASH_SOURCE`-based self-location, failing every `make` with no clear error | Run scripts only from `Vortex/sim/uvmsim/scripts/` |
| H7 | `make` with no explicit target in kernel dirs only regenerates `kernel.cl` | Always pass `all TARGET=...` |

---

## 1. PHASE A — finish the in-flight L2 run

Background job: `run_suite_resume.sh` (started 2026-09-09 ~19:16).

- [ ] **A1** Wait for completion. Poll: `pgrep -c vsimk` → 0, and `run_suite_resume2.log` reaches `=== DONE`.
- [ ] **A2** Ignore the script's own SUITE VERDICT and its final merge — both are corrupted by **H1**. The simulations are valid; only the staging bookkeeping is broken.

**GATE A** — do not proceed until: job exited, and `results/20260909/` contains a run dir per kernel.

### Progress tracker (32 confirmed PASS as of 20:42)

| Group | Items | Status |
|---|---|---|
| Core kernels (hello…csr_probe) | 31 | ✅ all PASS |
| `cache_tier` (L2/L3 phases) | 1 | ⏳ in flight |
| `isa_probe`, `unit_storm`, `storm_big` | 3 | pending |
| Directed (`axi_memory_test`, `functional_memory_test`, `warp_scheduling_test`, `barrier_sync_test`, `host_coverage_test`) | 5 | pending |
| Regression (`basic`, `diverge`, `sgemm`, `dogfood`) | 4 | pending |
| riscv-dv profiles | 9 | pending |
| **Suite total** | **53** | |
| `simtgen` (already complete, separate batch) | 57 | ✅ done earlier |

---

## 2. PHASE B — harvest and bank the L2 result

- [ ] **B1** Export the results root (H1):
  ```bash
  export VORTEX_UVM_RESULTS_DIR=/home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/results
  ```
- [ ] **B2** Enumerate every `results/20260909/run_*` dir that has `reports/coverage.ucdb`
      AND a PASS verdict. Build the explicit list (suite runs + the 57 simtgen runs).
      Reject any run dir dated before 2026-09-09 (H3 — different build).
- [ ] **B3** Fresh-collect into staging (clears any stale entry):
  ```bash
  cd Vortex/sim/uvmsim
  bash scripts/merge_coverage.sh --collect <run_dir> [<run_dir> ...]
  ```
- [ ] **B4** Merge with config-aware exclusions:
  ```bash
  export COV_NCL=1 COV_NC=1 COV_NW=4 COV_NT=4 COV_L2=0 COV_L3=0
  bash scripts/merge_coverage.sh
  ```
- [ ] **B5** Verify, do not assume:
  ```bash
  vcover report -summary cov/merged.ucdb | grep -iE "Covergroup|Instances|TOTAL"
  ```

**GATE B** — all three must hold, else STOP and investigate:
1. Covergroup count reads **23** (not 19 — 19 means a frozen-bank UCDB leaked in, H3).
2. Total coverage is **≥ 94.72%** (the frozen bank's value). A *lower* number after adding
   samples means dilution, not regression — that is a merge defect.
3. `merge_coverage.sh`'s hits-invariant gate passed (no exclusion changed a COVERED count).

- [ ] **B6** Confirm the three `simtgen` closures landed in a real bank for the first time:
      `cp_split_depth` 4/4 · `cp_bank_conflict` 3/3 · `cp_coalesce_kind` 3/3.
- [ ] **B7** Bank it: copy `merged.ucdb`, `merged_raw.ucdb`, `report/`, `staging/` to
      `vortex_uvm_env/cov/bank_1CL_1C_4W_4T_L2_20260909/` and re-read the COPY to verify.

---

## 3. PHASE C — the ISACOV (L1) result

### C-0 REUSE FIRST — measured 2026-09-09, do not re-derive

Three ISACOV banks already exist and were re-measured today. **They already contain both
families in ONE UCDB** — this is the combined picture, and it predates this plan:

| bank | covergroups | cg bins hit | cg % | total (filtered) |
|---|---|---|---|---|
| `bank_1CL_1C_4W_4T_ISACOV_with_20260904` | 100 | 425 / 6905 | 6.15% | 83.26% |
| `bank_1CL_1C_4W_4T_ISACOV_without_20260904` | 100 | 425 / 6905 | 6.15% | 83.26% |
| **`isacov_gaphunt`** | **101** | **1812 / 6929** | **26.15%** | 67.96% |

**Verified breakdown of the 100:** exactly **80 riscvISACOV covergroups** + 20 project
covergroups (the project count at the 2026-09-04 build; the current build has 23 because
3 covergroups were added after). This confirms the audit brief's "80 active" figure —
it is measured, not assumed.

`isacov_gaphunt` is the best existing L1 result: **57.70%** covergroup coverage vs 19.89%
for the two 09-04 banks.

**Why reuse is valid here:** L1 and L2 are reported with *separate denominators*, so the
L1 family does not have to come from the same build as the L2 family. The riscvISACOV
covergroups are third-party and **unchanged** between the 09-04 build and today — only the
project's own covergroup set grew (20 → 23). H3 forbids merging these two banks into one
metric; it does **not** forbid reporting L1 from one bank and L2 from another.

- [ ] **C-0a** Confirm the riscvISACOV covergroup definitions are byte-identical between
      the 09-04 build and the current tree (`third_party/riscvISACOV` + `isacov/ext`
      unchanged in git). If unchanged → **reuse `isacov_gaphunt` as the L1 result and
      SKIP C1–C5 entirely.**

### C-1 The ONLY case that justifies a new ISACOV run

`isacov_gaphunt` predates `simtgen`, so simtgen's 57 programs have **never** fed the ISA
covergroups. If we want simtgen's ISA-space contribution, run `ISACOV=1` over the **57
simtgen programs only** — not the whole suite. That is the targeted, credit-cheap version.

- [ ] **C-1a** Decide: accept `isacov_gaphunt` as-is (zero sim cost), or spend one
      ISACOV=1 compile + 57 simtgen runs to see whether simtgen moves any ISA bins.

### C-2 Full re-run (fallback only — most expensive, do NOT default to this)

Only after GATE B. Requires a **recompile**, so the work library must be free (H5).

- [ ] **C1** Decide the extension set. Default in
      [compile.sh:183](../Vortex/sim/uvmsim/scripts/compile.sh#L183) is `RV32I RV32M` only.
      For full ISA breadth pass explicitly:
  ```bash
  export ISACOV=1
  export ISACOV_EXTS="RV32I RV32M RV32F RV32Zicsr RV32Zifencei"
  ```
- [ ] **C2** Compile with `ISACOV=1` and confirm the log shows
      `riscvISACOV: enabled (+define+ISACOV)` and `riscvISACOV compiled`.
- [ ] **C3** **Liveness check before the full run** — compile.sh warns the ALL-CAPS
      `COVER_<EXT>` macros can silently miss, yielding a passing run with **zero**
      covergroups. Run one kernel and confirm riscvISACOV covergroups are present and
      non-zero in its UCDB.

**GATE C** — riscvISACOV covergroups appear in the UCDB with non-zero hits. If zero,
the extension defines did not take; fix before burning the suite.

- [ ] **C4** Run the stimulus set with `ISACOV=1`. Scope decision (record which was used):
      - *Full*: all 53 suite items + 57 simtgen = maximum ISA breadth, longest.
      - *Representative*: riscv-dv (9) + simtgen (57) + a native-kernel subset — riscv-dv
        and simtgen are the ISA-breadth drivers; native kernels add little new ISA space.
- [ ] **C5** Harvest exactly as in Phase B (B1–B5), into its own bank
      `bank_1CL_1C_4W_4T_ISACOV_20260909/`.

**GATE C2** — the ISACOV bank contains BOTH families: 23 project covergroups AND the
riscvISACOV covergroups. Record the active riscvISACOV covergroup count as **measured**,
not as the assumed 80.

---

## 4. PHASE D — combined reporting

- [ ] **D1** One UCDB may hold both families. **Database merge = allowed.
      Metric collapse = forbidden.** Never emit a single blended "Total Coverage %".
- [ ] **D2** Report as separate rows with explicit denominators:

| Layer | Owner | Question answered | Covergroups | Result |
|---|---|---|---|---|
| L1 — ISA | riscvISACOV (Imperas, unmodified) | Was the RISC-V instruction space exercised? | measure, don't assume | |
| L2 — SIMT / µarch | this project | Was Vortex SIMT/microarchitectural behaviour exercised? | **23** | |
| L3 — System / protocol | this project | Was the system interface exercised legally and under stress? | included in the 23 (`vortex_if`, `dcr_if`, AXI coverpoints in the collector) | |

- [ ] **D3** State plainly which runs had `+ISACOV` and which did not. The Phase-B bank
      does **not** contain L1 coverage — say so rather than implying absence of coverage.

---

## 5. PHASE E — the audit

- [ ] **E1** Run the coverage audit against the Phase-C bank, with these corrections to
      the audit brief (all verified against the tree 2026-09-09):

| Brief says | Correct |
|---|---|
| 20 project covergroups | **23 in the current build.** 20 was correct for the 2026-09-04 build (confirmed: the ISACOV banks hold exactly 20 + 80). Three were added after: `vx_hazard_probe.sv`, `vx_commit_probe.sv`, `vx_lmem_probe.sv`. Quote 23 for anything built today. |
| 9 passive probes | **10** — the list omits `vx_lmem_probe.sv` |
| `vx_instr_word_probe.sv`, `vortex_rvvi_shim.sv` under `tb/` | They live under `Vortex/sim/uvmsim/isacov/` |
| 80 active riscvISACOV covergroups | ✅ **VERIFIED 2026-09-09** by counting covergroup types in `isacov_gaphunt/merged.ucdb`. Note the *default* build is `RV32I RV32M` only — 80 requires passing the full `ISACOV_EXTS`. |
| 53 feature areas | Unverified from the tree; treat as a claim to check, not an axiom |

- [ ] **E2** Add the two rules the brief is missing: **never merge across builds** (H3) and
      **never blend configs** (H4).
- [ ] **E3** Classify every meaningful unhit bin as exactly one of:
      REACHABLE · UNREACHABLE · WAIVED/N-A · OBSERVABILITY GAP · DESIGN-CONSTRAINED ·
      NEEDS INVESTIGATION. Unhit ≠ failure.
- [ ] **E4** For each actionable gap, state the required hardware condition and whether it
      needs new stimulus, a new probe, or a waiver. Do not change the coverage model to
      raise a percentage.

---

## 6. STIMULUS × COVERAGE-FAMILY MATRIX

| Stimulus source | SIMT-aware? | Feeds L1 (ISA) | Feeds L2 (SIMT) | In Phase B | In Phase C |
|---|---|---|---|---|---|
| Native Vortex kernels (53 suite items) | n/a (real workloads) | narrow — compiler-emitted mix | ✅ primary | ✅ | scope decision C4 |
| Google riscv-dv (9 profiles) | ❌ scalar generator | ✅ primary ISA breadth | weak | ✅ | ✅ |
| `simtgen` (57 programs) | ✅ purpose-built | moderate | ✅ divergence + memory axes | ✅ | ✅ |
| Coverage-gap directed kernels | ✅ by construction | targeted | ✅ closes named bins | ✅ | as needed |

Reminder for the write-up: riscv-dv is **not** a SIMT generator; riscvISACOV is **not**
SIMT-aware; Spike is **not** a SIMT golden model (scalar, offline, warp0/lane0 slice only);
the RVVI shim is an adapter, **not** one of the passive RTL probes.

---

## 6b. CONFIG / TOPOLOGY-AWARENESS AUDIT — done 2026-09-09, result: PASS

Requirement: every covergroup's bin bounds must derive from elaborated parameters, so the
denominator adapts to any NCL/NC/NW/NT instead of being hardcoded to the primary config.

| covergroup owner | config-aware? | mechanism (verified) |
|---|---|---|
| `vx_hazard_probe.sv` | ✅ by construction | `bins w[] = {[0 : PER_ISSUE_WARPS-1]}` from `VX_gpu_pkg` |
| `vx_lmem_probe.sv` | ✅ by construction | `NUM_REQS` / `NUM_BANKS` passed through the `bind` |
| `vx_coalescer_probe.sv` | ✅ by construction | `bins lanes[] = {[1:NUM_REQS]}`, `partial_transfers[] = {[1:DATA_RATIO-1]}`; module is not elaborated at all when no coalescer exists ⇒ no bins to waive |
| `vx_commit_probe.sv` | ✅ by construction | `LS_LANES` derived; `partial[] = {[2:LS_LANES-1]}`, `uniform = {LS_LANES}` |
| `vx_cache_probe.sv` | ✅ by construction | bank exists only when `PASSTHRU==0` (G1, pre-existing) |
| AXI coverpoints in the collector | ✅ config-keyed waivers | `gen_coverage_exclude.sh` (`cp_rw`, `cp_burst`, `cp_len`, `cp_bresp`, `cp_rresp`) |

⇒ The three covergroups added after 2026-09-04 need **no** new entries in
`gen_coverage_exclude.sh`; they scale with topology on their own. Nothing to fix before 2CL.

**riscvISACOV contains NO SIMT covergroups.** Measured: the 80 active groups are
39 RV32I + 8 RV32M + 26 RV32F + 6 Zicsr + 1 Zifencei, and zero of them model warps, lanes,
masks or divergence. So there is nothing SIMT-related to exclude from the ISA family — the
low ISA percentage has a different cause (see §6c). **RV32D is already correctly absent**
from the active set at this RV32 configuration.

## 6c. WHY THE ISA NUMBER READS LOW — measured, not assumed

`isacov_gaphunt` headline is 26.15% covergroup bins. Root cause, measured across the bank:

| coverpoint family | bins covered / total | % |
|---|---|---|
| `*_reg_assign` (which architectural register was used as rd/rs1/rs2) | 4,060 / 23,804 | **17.06%** |
| **every other coverpoint** (opcode reached, operand signs, values, immediates, ISA behaviour) | **2,688 / 3,250** | **82.71%** |

Register-index bins are ~88% of the ISA bin space: each instruction covergroup carries
3 × 32 register bins (e.g. `rv32i_add_cg` = 106 bins, of which 96 are register indices).
A compiled kernel emits a limited ABI register subset per instruction form, so most of
those bins are unreachable **for compiled stimulus** — a property of the compiler and ABI,
not of the DUT.

Evidence the instruction space itself is well exercised: only **2 of 80** covergroups sit
at 0% (`rv32zifencei_fence_i_cg`, `rv32i_nop_cg`), and typical groups read high —
`rv32i_add_cg` 94.19%.

**Reporting rule:** report the ISA family as two numbers with explicit denominators —
*ISA behavioural coverage 82.71%* and *register-allocation coverage 17.06%* — never a
single blended 26.15% that implies the ISA was barely tested. Do **not** waive the
register bins: most are REACHABLE-needs-stimulus (riscv-dv could reach more), not
structurally unreachable. Classifying them as unreachable to raise a percentage is exactly
the gaming this project forbids.

---

## 6d. STANDING RULE — COVERAGE-DRIVEN VERIFICATION LOOP

**This applies to every run in this plan, both configs, until no further bin can honestly
be closed.** After every merge, do not stop at the number — process the gap list:

```
RUN → MEASURE → LIST UNHIT BINS → for each: WHAT HARDWARE CONDITION WOULD HIT IT?
   → classify → act → RE-RUN → RE-MEASURE
```

Classification, one per bin, with evidence:

| class | meaning | action |
|---|---|---|
| **REACHABLE** | ordinary stimulus can produce it | write/extend a directed kernel, or add a simtgen axis |
| **UNREACHABLE (structural)** | the RTL cannot produce it in any run of any program | **exclude**, with an `RTL file:line` citation in the waiver |
| **CONFIG-LIMITED** | impossible at this compile-time config, possible at another | exclude *config-keyed* (via `gen_coverage_exclude.sh`), never globally |
| **OBSERVABILITY GAP** | it happens, the probe cannot see it | fix the probe (that is OBS-060's lesson) |
| **WEIGHT-0 / N-A** | interface not selected in this build | already handled by `weight = 0`; keep the bins in the UCDB |
| **NEEDS INVESTIGATION** | reason not yet established | investigate before classifying — never default to "waive" |

### The exclusion bar (non-negotiable)

Exclude **only** what is architecturally impossible, and only with an RTL citation proving
it. Precedents that meet the bar: icache `cp_rw.wr` (`VX_socket.sv:106` `.WRITE_ENABLE(0)`);
`axi_usage_cp.simultaneous` (AW and AR mutually exclusive by construction in
`VX_axi_adapter.sv`); `b_valid_stable` (`bready` hardwired 1).

Precedents that were **refused**, and stay refused: `cp_mshr_stall.stall` (a genuine
stimulus gap, left honestly uncovered); `cp_route_slot` slots 4–15 (measured bound 3 <
naive 8 — waiving on an unproven bound is the OBS-030 mistake); riscvISACOV `*_reg_assign`
(compiler/ABI-limited, not structurally impossible).

"Hard to hit", "low value", or "would raise the percentage" are **not** grounds for
exclusion. A bin excluded on an unproven bound hides real coverage — that error has already
been made once on this project and must not recur.

## 6e. 1CL GAP LIST — measured 2026-09-09 from the current bank

All 7 uncovered bins in the 1CL bank, classified:

| covergroup | bins | class | disposition |
|---|---|---|---|
| `system_cg` `system_state_cp` / mem-usage — `idle`, `read`, `write` | 3 | **WEIGHT-0 / N-A** | Already correct. These are the *MEM* interface coverpoints; the build selects AXI via `USE_AXI_WRAPPER`, so the unused interface sits idle. [vortex_if.sv:249-253](../Vortex/sim/uvmsim/tb/vortex_if.sv#L249) already sets `weight = 0` — bins kept in the UCDB, removed from the %. **No action.** This is why weighted covergroup coverage reads 99.79% vs 98.14% raw. |
| `axi_transaction_cg` `cp_write_tag` — `tag[4]`…`tag[7]` | 4 | **REACHABLE — needs stimulus** | `ROUTE_W=6` @1CL ⇒ 64 tag values in 8 buckets; buckets 4–7 are tag values 32–63, never produced. Write id is `m_axi_awid = TAG_WIDTH_OUT'(xbar_tag_out)` ([VX_axi_adapter.sv:262](../Vortex/hw/rtl/libs/VX_axi_adapter.sv#L262)) — a pass-through of the mem request tag, no write tag buffer. Needs more concurrent, distinct write sources. |

⇒ **The 1CL primary config has exactly ONE actionable gap: 4 `cp_write_tag` bins.**
Closing them takes raw covergroup bins from 370/377 (98.14%) to 374/377 (99.20%); the
remaining 3 are weight-0 by design and cannot be "closed" at all.

- [x] **G1** **Reuse before writing — done 2026-09-10.** `Vortex/tests/kernel/axi_stress/`
      already exists and was purpose-built for exactly this. Re-ran it in isolation
      (`kernel_launch_test`, 1CL/1C/4W/4T, TIMEOUT=1,500,000 — the original 200,000 was an
      undersized budget, not a real hang; `TB_STATUS` showed `mem=` still climbing linearly
      at cycle 199,000 with no stall, a mostly-serial `.bss`-init cost, not contention).
      Real Questa run, raw evidence:
      [`docs/paper/evidence/G1_axi_stress_cp_write_tag/`](https://github.com/Samuel-Moussa/Vortex-UVM-GP/tree/main/docs/paper/evidence/G1_axi_stress_cp_write_tag).
- [x] **G2** Verify against the target — done, **NEGATIVE RESULT.** `vcover report -details`
      on the passing run's own UCDB (isolated, not suite-merged):
      ```
      Coverpoint cp_write_tag   25.00%   2/8 covered
        bin tag[0]   9084 hits   Covered
        bin tag[1]     37 hits   Covered
        bin tag[2]      0 hits   ZERO
        bin tag[3]      0 hits   ZERO
        bin tag[4]      0 hits   ZERO   <- target
        bin tag[5]      0 hits   ZERO   <- target
        bin tag[6]      0 hits   ZERO   <- target
        bin tag[7]      0 hits   ZERO   <- target
      ```
      `axi_stress` alone does **not** move tag[4..7] — it does not even reach tag[2]/tag[3]
      in isolation (worse than the old-model claim of raw write IDs up to 21, which maps to
      the old, since-withdrawn coverpoint, not this one). The bound is real for THIS
      kernel's achieved concurrency, not proven structural for the RTL.
      **Root-cause hypothesis, not yet proven:** `VX_axi_adapter.sv:262`
      (`m_axi_awid = TAG_WIDTH_OUT'(xbar_tag_out)`) passes through the *same* underlying
      memory-request tag the read path uses — i.e. `cp_write_tag`'s reachable range is
      governed by the same tag-buffer/allocator mechanism already measured (§6e/G-precedent)
      to top out at **~3 simultaneously outstanding** requests for `cp_route_slot`, not by
      total request volume over time. This kernel issues K=4 independent writes per thread
      × 16 threads = 64 total, but warp-serialized issue likely caps true concurrency well
      below that, matching the observed low tag values.
- [ ] **G3** NOT folded into the suite (nothing to fold — G2 was negative). Per the
      project's own exclusion bar (§6d), this is **NOT waived** — "hard to hit" is not
      grounds for exclusion, and the concurrency bound above is a hypothesis, not an RTL
      citation. **Disposition: REACHABLE — needs a genuinely higher-concurrency kernel than
      `axi_stress` achieves** (a new `wtag_spread`-class kernel, or proving the ~3-outstanding
      bound with the same rigor as the accepted `cp_route_slot` precedent). Left honestly
      uncovered; matches the diminishing-returns precedent already accepted for the closely
      related `cp_route_slot` slots 4-15. Not pursued further this pass — future work.

## 7. PHASE F — 2CL (2CL / 2C / 4W / 4T)

Same pipeline, second config. **Never merge 1CL and 2CL** (H4) — separate bank, separate report.

- [ ] **F1** Re-run the suite with `CLUSTERS=2 CORES=2 WARPS=4 THREADS=4`. This forces a
      full RTL + SimX rebuild (`prepare.sh` rebuilds SimX per config) — the work library
      must be free (H5).
- [ ] **F2** Budget guard: 2CL is slower per program. `barrier_sync_test` needs ≥164,602
      cycles and riscv-dv ≥205,982 — both already raised in `run_suite.sh`; confirm before
      launching so a shortfall doesn't masquerade as a divergence.
- [ ] **F3** Expect a **lower raw bin %** than 1CL and do not treat it as a regression:
      per-core probe instances multiply the denominator (1CL 377 bins vs 2CL 1032).
- [ ] **F4** Export `COV_NCL=2 COV_NC=2` for the merge so config-keyed exclusions are
      generated for 2CL — without this the merge silently applies **1CL** waivers.
- [ ] **F5** Bank as `bank_2CL_2C_4W_4T_L2_20260909/`, verify from the copy.
- [ ] **F6** ISACOV at 2CL: the two 09-04 banks (`bank_2CL_2C_4W_4T_ISACOV_{with,without}`)
      already exist — apply the §C-0 reuse test before spending a re-run.

**Known 2CL residuals (documented, do not re-derive):** `cp_route_slot` slots 4–15 +
`cross_port_slot` (measured per-port concurrency is 3), `cp_write_tag` high buckets,
weight-0 `mem_usage_cp`/`system_mem_cross`, `cross_dvg_depth` 2 bins.

---

## 7b. PHASE H — L2/L3 shared-hierarchy bank (third config)

Rationale: every bank so far runs `L2=0 L3=0`, so both shared levels are **PASSTHRU**
([VX_cache_wrap.sv:160](../Vortex/hw/rtl/cache/VX_cache_wrap.sv#L160) builds the storage only
when `PASSTHRU==0`) — and that RTL is currently **waived out of the denominator** by
`gen_coverage_exclude.sh`'s EUR class. A waiver standing in for untested RTL is the weakest
point in the coverage story. Enabling L2/L3 also instantiates **new** `vx_cache_probe`
covergroup instances (config-aware by construction), so this is real new coverage.

⚠ Set expectations honestly: this is **coverage and configurability evidence, not
bug-finding**. L2/L3 was already functionally validated 2026-08-07 (`cache_tier` @2CL with
L2+L3: 57,379 matched pairs; 15-kernel sweep identical to the pre-L2/L3 baseline) — shared
caches change timing, not architectural outcome. Do not claim otherwise.

- [ ] **H1** **Reduced, cache-focused suite only.** L2/L3 affects the memory hierarchy, so
      riscv-dv arithmetic / FPU / TCU kernels add nothing. Run:
      `cache_tier` (all 3 phases), `cache_stress`, `mshr_flood`, `mem_stress`,
      `lmem_stress`, `wide_stress`, `storm_big`. ~45–75 min vs ~4 h for the full suite.
- [ ] **H2** Build with `L2=1 L3=1` (structural — a plusarg cannot create hardware; the I2
      asserts fail loud and name the rebuild command if this is wrong).
- [ ] **H3** Verify the levels are genuinely live via
      `vcover report -recursive | grep l2cache` — **never** by grepping the sim log.
      Reference point from a prior measurement: L2 cluster0 15,268 hits / cluster1 15,323 /
      L3 bank0 13,464 / bank1 14,304.
- [ ] **H4** Export `COV_L2=1 COV_L3=1` for the merge so the EUR passthru waivers are NOT
      generated — leaving them in would waive the very RTL this phase exists to cover.
- [ ] **H5** Bank as its own config (`bank_..._L2L3_20260909/`). Never merge with an
      L2=0/L3=0 bank (H4 in §0).

## 8. OPEN ITEMS AFTER THIS PLAN

- [ ] **T-cache** — `cache_evict` directed kernel (same-cache-set multi-core contention,
      device-derived grid, end-state compare vs SimX). Plan agreed, not yet written.
- [ ] **T-exc** — recommend closing as N/A / architecturally unimplementable
      (see OBS-024: Vortex kernels terminate via `tmc x0` → `busy` deassert, not `ebreak`).
- [ ] **D-matrix** — broader config-point sweep, per-config banks only.
- [ ] **SIGN** — final merged sign-off report.
