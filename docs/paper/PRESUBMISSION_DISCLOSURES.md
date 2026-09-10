# Pre-Submission Disclosures Register

**Purpose.** Single source of truth for every honesty constraint that the
arXiv preprint and the ISQED'27 submission must respect. Every paper claim
is checked against this register before compilation. Written 2026-09-09 as
part of the pre-submission work plan (P0-2, P0-3, P0-4).

**Sources.** PAPER_BASE_EVALUATION.md (audited evidence base),
VERIFICATION_PLAN_v2.md, RTL_OBSERVATIONS.md (OBS-001..OBS-061),
INDUSTRIAL_ROADMAP_2026-09-07.md, OBS-046 (seed farm), and the FuzzGPU
paper (Gao et al., USENIX Security 2026, verified from the published PDF).

---

## 1. Run-count wording (FW-1b) — MANDATORY

- **Never** say "50 programs" (or "51 programs"). Say **"50 simulation
  runs"** / "51 staged runs".
- Current honest counts:
  - 2026-08-16 banks: **50 runs, 0 FAILED** at 1CL and 2CL — 50 runs =
    49 distinct programs, one of which runs twice under two bus modes.
  - Relay-fix bank 2026-08-18: **51 staged runs, 0 FAILED** (cache_tier
    newly also run at 1CL; two variables changed vs the 50-run bank).
  - FW-1b history: `riscv_pmp_test` and `riscv_non_compressed_instr_test`
    produced byte-identical programs (.S md5 `16be14c6…`); the duplicate
    was dropped at commit `eb8a630`; the 45→44 re-run proved **zero
    coverage bins moved** (a distinct program cannot have zero footprint).
- Remaining guard gap: the md5-distinctness assertion is NOT yet wired
    into `run_suite.sh` (roadmap item P0.0). Do not claim the suite is
    mechanically duplicate-free; say "duplicates were removed and the
    removal verified by re-run".

## 2. OBS-061 (FLEN=64 / D-extension) — SCOPED 2026-09-10 (static inspection)

Status change: the coverage-impact question is RESOLVED by code
inspection (no simulation needed). Papers now carry the scoped
statement (was: "under investigation").

Evidence (all file:line in this checkout):
- The RTL default is D-enabled (`hw/rtl/VX_config.vh:45-46`:
  EXT_D_ENABLE unless EXT_D_DISABLE) and FLEN=64 (`:69-76`) — the
  OBS-061 elaboration fact stands, unintentional-by-documentation as
  an RTL fact.
- The coverage model's ONLY D-specific bin — float↔double conversion
  (INST_FPU_F2F) — is config-aware-excluded at RV32:
  `sim/uvmsim/tb/vx_instr_probe.sv:496`
  (`ignore_bins rv32_no_f2f = {INST_FPU_F2F} with (PROBE_XLEN == 32)`),
  mirroring the RV64-only LSU LD/SD waiver. No other probe references
  D-dependent bins (grep: only comments at :188-190, :464, :491-495).
- No stimulus can emit a D operation: kernels build rv32imaf
  (soft-double libcalls; comment at :491-493), riscv-dv targets rv32im,
  and SimX models F only (OBS-061). The ISACOV layer compiles no D plan
  (RV32I/F/M/Zicsr/Zifencei; W-12).
- Therefore: NO functional bin is diluted. The elaborated-but-unexecuted
  D logic sits only in code-coverage (statement/branch/toggle)
  denominators, making the reported totals CONSERVATIVE (understated
  relative to an F-only build), never inflated.

Paper wording rule (updated): use the scoped statement above; the
MISA/D=1 elaboration fact is still disclosed as an RTL documentation
issue. Do not revert to "under investigation".

## 3. Coverage-bank labels — PROVENANCE RULES

- All 2CL and 2CL+L2/L3 banks predate the reset-relay fix (R10) and are
  **taken on the X-window design**. Decision of record (2026-08-19):
  they were NOT re-run on the fixed design. Any cross-configuration
  branch-coverage comparison is therefore invalid; state this whenever
  both are shown.
- The 1CL relay-fix bank: branch 94.53% vs pre-fix 95.09% — the delta is
  **indicative only** (relay fix AND cache_tier-at-1CL changed together).
- Toggle numbers: pre-fix 1CL bank = **82.83%**; relay-fix 51-run bank =
  **83.34%**; seed-farm 141-UCDB bank = **83.40%** (OBS-046). Cite the
  one that matches the bank being described; never mix within a table row.
- The seed-farm result is a **robustness** result, never coverage progress:
  10 seeds × 9 profiles = 90 additional distinct programs (content-hash
  verified), 90/90 PASS, every coverage category bit-identical except
  toggle +0.06%.
- simtgen closures (cp_split_depth 3/4→4/4; cp_bank_conflict and
  cp_coalesce_kind →3/3) were verified in **isolated merges**
  (`cov/simtgen_*_20260907`), NOT folded into the frozen banks. State
  this explicitly wherever the closures are quoted.
- The banked UCDB files are **not present in this repository checkout**
  (tool-machine-local artifacts); the evidence chain is the committed
  documentation (bank names, dates, vcover report transcripts, OBS
  register). An artifact release must re-home or regenerate them.

## 4. G-1 aliasing disclosure

The frozen 1CL bank reports `cp_alu_op` = 100% (14/14), but the
instruction-class encodings alias (OBS-049: e.g. `INST_ALU_CZNE` ≡
`INST_BR_EBREAK` ≡ `4'b1011`), so per-mnemonic ALU identity in that bank
is unsound. The denominator was re-scoped 14→44 bins (commit `256e71e88`)
after the banks were frozen. Papers must either omit per-mnemonic ALU
claims from frozen-bank numbers or disclose the aliasing; use post-fix
measurements (cp_xtype 3/4, cp_alu_op 11/14, cp_branch_op 6/10,
cp_muldiv_op 3/8, cp_vote_shfl_op 0/8 at the time of measurement) when a
per-mnemonic picture is needed.

## 5. Covergroup naming (README table corrections)

Verified against source:
- `divergence_cg` (type name; `option.name = "warp_divergence_cg"`) in
  `vx_sched_probe.sv:145` — cite as `divergence_cg`.
- `lmem_bank_cg` in `vx_lmem_probe.sv:56`; `coalesce_cg` in
  `vx_coalescer_probe.sv:166` (NOT in the commit probe); `cache_event_cg`
  in `vx_cache_probe.sv:117`; `beat_cg` in `vx_commit_probe.sv:89`;
  `hazard_cg` in `vx_hazard_probe.sv:58`.
- **`dcr_cg` does not exist** (vx_dcr_probe builds no covergroup).
  Do not cite it anywhere.

## 6. Lockstep evidence caveat

The configuration-matrix tallies (1,035 / 1,801 / 3,333 / 855 / 1,423
matched writebacks) are recorded in committed planning documents and the
OBS register; the raw per-run simulation logs were session scratch and
were **not retained**. Cite the tallies as documented results, and do not
imply re-derivable logs.

## 7. FuzzGPU positioning — FACTS (verified from the USENIX '26 PDF)

What FuzzGPU is: first RTL GPU fuzzer; SIMT-aware program generation
(divergence stack, barrier planner, interleaved warp generation, taint
propagation); trace-driven differential testing against an ISA-level ISS
oracle with per-warp state over DPI; memory-consistency validator;
**Verilator 5.034**; evaluated on Vortex64 @ commit `2189194` and
OpenGPGPU (Ventus) @ `7e97907`; 20 new bugs (14 OpenGPGPU, 3 Vortex
X1–X3 → PRs #356/#358/#359, 3 ISS incl. S2 "jalr ignores LSB clearing"
→ PR #339, CWE-682); 10 CVEs (CVE-2025-70007..70016); **structural
coverage only** (line 94%, toggle ~80%, expression ~80% on Vortex).

What FuzzGPU explicitly does NOT have (positioning axes, all verifiable
in their text): no UVM (sole mention is their related-work note that
Ventus's GVM is "UVM-like" and "neither fuzzes GPUs nor validates memory
consistency models"); no functional-coverage model / covergroups /
closure; no checker or mutation qualification (they concede their
memory validator's soundness is "practical rather than absolute"); no
sign-off or regression discipline (bounded 20-core-hour campaigns).

Honest claims for our papers:
- "First UVM-based verification environment for an open-source RISC-V
  GPGPU" — supported (no public UVM env for Vortex exists; GVM is
  Ventus-only, acknowledged by FuzzGPU as non-fuzzing, and concurrent).
- "First published SIMT functional-coverage model (IPDOM divergence
  depth, scratchpad bank conflicts, coalescing classes) for RTL GPU
  verification" — supported by our literature sweep.
- NOT claimable: "first per-instruction/per-warp lockstep flow for a
  SIMT GPU" (FuzzGPU's difftest is instruction-granular per-warp).
  Instead: our alignment-rule formalization, UVM packaging, and
  after-the-fact checking vs their execute-in-the-loop generation.
- R1 (JALR LSB) was independently corroborated by FuzzGPU's S2 (PR
  #339). Their S1 (SRA) was NOT reproduced at our pin — do not cite S1.
- Their bugs were filed at commit `2189194`, ours at pin `7a52ee5`;
  do not compare bug counts head-to-head without stating both pins.

## 8. Re-run runbook (P0-2) — simtgen fold-in procedure

Cannot be executed on this machine (no QuestaSim). Procedure of record
for the tool machine:

1. `cd Vortex/sim/uvmsim && source prepare.sh` (expects `~/riscv` and
   QuestaSim 2021.2_1 on PATH; uses the standalone riscv-dv clone).
2. Re-run the full 1CL suite with simtgen's divergence and memory axes
   enabled (`+SIMTGEN_AXES=divergence,memory`), seeds as banked.
3. `vcover merge` into a NEW bank directory
   `cov/bank_1CL_1C_4W_4T_simtgen_<date>/` — never overwrite the frozen
   banks; the merge gate (hits-invariant waiver check) must pass.
4. `vcover report -summary` on the merged UCDB; expect: cp_split_depth
   4/4, lmem_bank_cg conflict bin hit, coalesce_cg 3/3 folded in.
5. Only then update headline totals. Until this run completes, the
   papers quote the frozen totals + isolated-merge closures separately
   (per Section 3).
6. Repeat for 2CL and L2/L3 **on the relay-fixed design** if
   cross-configuration comparability is ever claimed (per Section 3,
   currently out of scope).

## 9. Claim inventory quick-reference (paper-safe numbers)

| Claim | Value | Provenance |
|---|---|---|
| 1CL total (relay-fix bank) | 94.72%, 51/51, 0 FAILED | bank_1CL_1C_4W_4T_relayfix_20260818 |
| 2CL total (pre-fix) | 94.55%, 50/50 | bank_2CL_2C_4W_4T (2026-08-16) |
| L2/L3 total (pre-fix) | 93.18%, 51/51 | bank_2CL_2C_4W_4T_L2L3_20260818 |
| CG bins 1CL / 2CL | 370/377=98.1% / 989/1032=95.8% | 2026-08-16 banks |
| 1CL categories (pre-fix) | stmt 98.10 / branch 95.09 / cond 90.41 / toggle 82.83 / assert 96.85 / directive 100 | 2026-08-16 bank |
| Branch post-fix | 94.53% (indicative) | relay-fix bank; two-variable caveat |
| Pass-2 feed | residual 0 over 5,432/5,432 retirements | SimX_2CL investigation; commits 2dd48ea.. |
| Interrupt boundary | 116→7, keying-independent | OBS-010; 2614ee0 |
| Spike 3-way audit | 11,076 = 11,076 = 11,076, 0 mismatches; injection-detected | A6 audit; 8e1a3b2 |
| AXI error injection | 166/166 firings, no error path | OBS-057 |
| L2/L3 first exercise | 4 instances hit+miss (13,464–15,323 hits); 196,868-word compare | 2026-08-18/19 blocks |
| ISA coverage (L1) | 429/516 = 83.14% (89.28% weighted); 78/80 covergroups real | gap-hunt frozen 2026-09-06 (OBS-056) |
| Seed farm | 90 programs, 0 failures, toggle +0.06% only | OBS-046 |
| simtgen closures | split_depth 3/4→4/4; bank-conflict 0/3→3/3; coalescing →3/3 (isolated merges) | cov/simtgen_probefix_20260907 |
| Findings register | OBS-001..OBS-061; R1–R10 paper-facing | RTL_OBSERVATIONS.md |
| Modified RTL files | 18 files vs upstream 7a52ee5 (provenance statement) | OBS-040 |
| ISACOV rule | quote 83.14% (weighted 89.28%); never the bare raw 22.32% | W-13 |
