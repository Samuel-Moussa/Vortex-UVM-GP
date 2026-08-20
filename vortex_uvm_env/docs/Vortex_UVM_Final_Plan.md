# Vortex UVM — Final Verification Plan (Full Founding-Plan Compliance)
### Target: satisfy **every** requirement in `VERIFICATION_PLAN.md` — all 8 tests, all 4 functional-coverage targets, structural targets — **black-box**. Microarchitecture white-box is in **Future Work**, outside this plan.

**Team:** Samuel **[S]** · Ahmad **[A]** · Steven **[St]**
**Branch:** `Sudky_scoreboard_and_coverage_collector` · **RTL pin:** `7a52ee5` · **Tool:** QuestaSim 2021.2_1 / Ubuntu 22.04
**Primary config:** 1CL/1C/4W/4T RV32 AXI · **Matrix:** 1C/1W, 1C/4W, 2C/4W, 2CL/2C/4W

---

## Scoping principle (in-scope features, black-box method)

The founding plan lists execution units (ALU/FPU/LSU/SFU), warp scheduling, caches, and exceptions as **in-scope features**, and requires **functional coverage** of warp states and exception types. None of that obliges white-box per-unit scoreboards or per-instruction commit-log compares. We reach those features the black-box way: **directed tests** that deliberately exercise each unit/scenario, plus **passive coverage probes** that observe and bin what was hit. The checker stays end-state equivalence vs SimX. So — **features in scope: yes; white-box method: no.** Every probe is for coverage/observability only, never a second pass/fail gate.

---

## Ownership model (fixed constraints)
- **[A] Ahmad — Coverage + Scoreboard:** scoreboard (incl. bidirectional fix), every covergroup, the passive coverage probes' sampling, UCDB merge, coverage closure.
- **[S] Samuel — Infrastructure correctness + Full configurability:** all bench-correctness fixes, and making the env fully driven by parameters (cores/clusters/warps/threads) end-to-end: config → compile defines → plusargs → elaboration asserts → config-matrix harness.
- **[St] Steven — everything else:** SimX/DPI, directed + random tests, sequences, AXI SVA, regression. Load-balanced.

Severity: 🔴 BLOCKING · 🟠 HIGH · 🟡 MEDIUM · 🟢 LOW · time in **person-days (pd)**.

---

## Current status vs the complete founding plan (post final-look)

| Founding requirement | Bar | Current state | Gap |
|---|---|---|---|
| smoke_test | High | ✅ passing | — |
| functional_memory_test | High | 🟡 partial | finish result-window compare |
| axi_memory_test | High | ❌ missing | build |
| kernel_launch_test | High | ✅ passing | — |
| warp_scheduling_test | Med | ❌ planned | directed divergence/wspawn/context test |
| barrier_sync_test | Med | ❌ planned | directed barrier kernel |
| **random_instruction_stress_test** | Med | ✅ **implemented, dual-load + end-state compare working** | seed-replay + ISA-intersection hardening only |
| cache_coherence_test | Low | ❌ planned | directed multi-access/eviction |
| Func cov: instruction opcodes | 100% | ❌ none | `instr_class_cg` |
| Func cov: warp states | all | 🟡 active-warp count only (heuristic) | real divergence/split/join/barrier states |
| Func cov: memory patterns | aligned/unaligned/contention | 🟡 alignment exists (`cp_addr_align`) | add contention + cross |
| Func cov: exceptions/interrupts | all types | ❌ none | `exception_cg` + stimulus |
| Structural: line | >95% | ~94% | close on RTL scope (cvfpu out) |
| Structural: toggle | >90% | ~69% | close + documented waivers |
| Scoreboard RTL vs SimX | ≥1 kernel | ✅ but one-directional | SB-DIR bidirectional |
| Full configurability | cores/clusters/warps/threads | 🟡 script plumbing exists; width hardcoded, no asserts | param↔DUT consistency + asserts + matrix |
| Bench trustworthiness | implicit | ❌ C1/C2/C3 broken (NEG ✅ fixed) | Gate 0 |

---

## TIER 0 — TRUST THE BENCH 🔴 (prerequisite; GATE 0)
| # | Item | Owner | pd | Action |
|---|------|-------|----|--------|
| C1 | Tag/ID width hardcoded 50 | **[S]** | 1 | Derive from RTL `VX_MEM_TAG_WIDTH`; fix false `// 8` comments; **elaboration assert** UVM==DUT. |
| SB-DIR | Scoreboard one-directional | **[A]** | 1.5 | Second pass over SimX written region; fail on expected-present/DUT-absent. |
| C3 | Synthesized EBREAK completion | **[S]** | 1 | Decode ebreak (`0x00100073`), drive completion from it; idle → `UVM_WARNING`. |
| C2 | Fabricated instr_count | **[S]** wire + **[A]** count | 0.5+0.5 | Real retired count from commit probe; restore real IPC (fixes `cp_ipc_bucket`/`cp_ebreak` samples too). |
| T4 | `−2 UVM_ERROR` gate hack | **[S]** | 0.5 | Banners → `UVM_INFO`; gate true errors only. |
| NEG | Negative fault-injection | **[A]** | ✅ | Already working — keep as regression guard. |

> **🚦 GATE 0:** negative RED · dropped store fails · no hardcoded subtraction · width assert matches DUT · instr count real.

---

## TIER 1 — INFRASTRUCTURE, HIGH TESTS, CORE COVERAGE 🟠

### Configurability — **[S]**
| # | Item | pd | Action |
|---|------|----|--------|
| I1 | Param→DUT→SimX consistency | 2.5 | Make config's cores/clusters/warps/threads reliably drive RTL elaboration **and** SimX; script plumbing already exists. |
| I2 | Elaboration asserts | 1 | UVM params == DUT params (widths, counts) fail loud. |
| I3 | SimX param-match | 0.5 | Coordinate config → SimX build/runtime with **[St]**. |
| I5 | Hygiene | 0.5 | Dead files; stale scoreboard header. |

### High-priority tests — **[St]**
| # | Item | pd | Action |
|---|------|----|--------|
| T-axi | `axi_memory_test` | 1.5 | AXI4 R/W + result-window compare. Last missing High test. |
| T-fmem | finish `functional_memory_test` | 1 | Deterministic window compare on custom-mem path. |

### Core coverage — **[A]** (P1 bind assisted by **[S]**)
| # | Item | pd | Action |
|---|------|----|--------|
| P1 | Passive commit/decode probe | 2 ([S] does bind, [A] samples) | `bind` passive monitor on `commit_arb_if[*]` (observability only). Feeds instr count + instr/exception coverage. Assert `$bits(uuid)>1`. |
| CG1 | `instr_class_cg` | 2 | Opcode class ALU/FPU/LSU/CSR/branch/SIMT-special × active-warp-count. Target 100% opcode/format. Hook riscv-dv stream here. |
| CG-mem | contention coverpoint | 0.5 | Add contention + cross to existing `mem_operation_cg` (alignment already covered). |
| COV-pipe | UCDB merge + report update | 1.5 | Per-test save, `-du` exclusions (`-reason EOTH`), merge, HTML+cvg+summary; extend `report_phase` for new CGs. |

> **🚦 GATE 1:** all High tests pass through trusted checker · instr+mem coverage populating · merged report builds · primary config runs from parameters.

---

## TIER 2 — MEDIUM/LOW TESTS + REMAINING COVERAGE 🟡

### Tests — **[St]** (+[S] for cache/exc)
| # | Item | Owner | pd | Action |
|---|------|-------|----|--------|
| T-warp | `warp_scheduling_test` | **[St]** | 2 | Directed divergence / wspawn / context-switch; observe via status+probe, check end-state. |
| T-barr | `barrier_sync_test` | **[St]** | 1.5 | Directed barrier kernel; hold→release. |
| T-rand+ | riscv-dv hardening | **[St]** | 1 | Record seed for replay; constrain ISA to Vortex∩SimX (verify rv32imc vs F/C support); log divergences. |
| T-cache | `cache_coherence_test` | **[S]** | 2 | Directed multi-core/multi-access + eviction; end-state + cache coverage. |
| T-exc | Exception/interrupt stimulus | **[S]** | 1.5 | ebreak / misaligned / illegal-instr → drives `exception_cg`. |
| SVA-axi | AXI4 protocol SVA | **[St]** | 2 | Handshake stability, burst legality, response codes, 5 channels. |

### Remaining coverage — **[A]**
| # | Item | pd | Action |
|---|------|----|--------|
| CG2 | warp-**state** coverage | 2.5 | split/join depth, reconvergence, barrier hold/release via passive scheduler probe. Closes "all warp states" (active-warp count alone is insufficient). |
| CG3 | `exception_cg` | 1.5 | trap/exception type + EBREAK, fed by T-exc. Closes "all exception types." |

> **🚦 GATE 2:** all 8 founding tests pass · all 4 functional-coverage targets populated.

---

## TIER 3 — SCALE, CLOSE, SIGN-OFF 🟠
| # | Item | Owner | pd | Action |
|---|------|-------|----|--------|
| D-simx | SimX `NUM_CLUSTERS` runtime + exit-code | **[St]** | 2 | Dynamic cluster sizing / per-config `.so`; confirm exit semantics. Enables matrix. |
| D-matrix | Config matrix run | **[S]** | 1.5 | Run suite across 1C/1W … 2CL/2C/4W via param harness. |
| A1 | Software regression breadth | **[St]** (+[A] windows) | 2 | ≥3 kernels + RISC-V conformance subset, result windows. |
| COV-close | Coverage closure loop | **[A]** | 2 | Holes → bias riscv-dv / add directed → re-run → re-merge to func 100% / line>95% / toggle>90% (waivers). |
| TOG | Toggle/line push | **[A]** | 1 | Close cheap toggles; document waivers for third-party blocks. |
| SIGN | Seeded regression → one report | **[S]** | 1 | Pass rate, merged func+code vs goal, matrix status. |
| PATCH | `vortex_dpi.patch` + divergence log | **[St]** | 1 | Capture SimX/RTL edits on `7a52ee5`; apply-check. |

> **🚦 GATE 3 — SIGN-OFF:** all High + Medium + Low tests pass · functional coverage goals met (100% opcode, all warp states, mem patterns, all exception types) · line>95% & toggle>90% on RTL scope (waivers documented) · bidirectional SimX equivalence · matrix green · one merged report.

---

## Summary by PERSON

### [S] Samuel — Infrastructure + Configurability  ·  ≈ 14.5 pd
C1, C3, C2-wire, T4 · I1 param-consistency, I2 asserts, I3 SimX-match, I5 hygiene · P1 bind · T-cache, T-exc · D-matrix · SIGN
Critical thread: **I1 param-consistency gates the config matrix and multi-warp/multi-core tests.**

### [A] Ahmad — Coverage + Scoreboard  ·  ≈ 15.25 pd
SB-DIR, C2-count · P1 sampling, CG1 instr_class, CG-mem contention, COV-pipe · CG2 warp-state, CG3 exception · COV-close, TOG, A1 windows
Critical thread: **coverage closure trails the tests existing — build covergroups early, close last.** Heaviest load (coverage is inherently the largest bucket).

### [St] Steven — Tests + Sequences + SVA + DPI  ·  ≈ 14 pd
T-axi, T-fmem · T-warp, T-barr, T-rand+ hardening, SVA-axi · D-simx, A1, PATCH
Critical thread: **D-simx cluster runtime gates the config matrix.** riscv-dv already implemented — only hardening left.

---

## Summary by SEVERITY (time)
| Severity | Items | pd | Calendar (3 ‖) |
|---|---|---|---|
| 🔴 Tier 0 | C1, SB-DIR, C3, C2, T4 (NEG done) | ~5 | ~2 days |
| 🟠 Tier 1 | I1–I5, T-axi, T-fmem, P1, CG1, CG-mem, COV-pipe | ~13.5 | end Week 1 |
| 🟡 Tier 2 | warp/barr/cache/exc tests, T-rand+, SVA-axi, CG2, CG3 | ~14 | Week 2 |
| 🟠 Tier 3 | D-simx, D-matrix, A1, COV-close, TOG, SIGN, PATCH | ~10.5 | Week 3 |

**Total ≈ 43 pd ÷ 3 ≈ ~2.5–3 weeks.** One week covers Tier 0 + most of Tier 1 only.

---

## Phased timeline
- **Week 1 — Tier 0 → Tier 1:** Gate 0 (Day 2). Param-consistency + asserts. axi_memory + functional_memory done. Commit probe + instr_class + mem-contention coverage live. Primary config runs from parameters. → **Gate 1.**
- **Week 2 — Tier 2:** warp / barrier / cache / exception tests + riscv-dv hardening. warp-state + exception covergroups. AXI SVA. SimX cluster runtime. → **Gate 2.**
- **Week 3 — Tier 3:** config matrix, regression breadth, coverage closure, structural close, seeded merged sign-off report, dpi patch. → **Gate 3.**

---

# FUTURE WORK — Microarchitecture white-box depth (outside this plan)
Not required by the founding plan; pursue only after Gate 3.

1. **M1 — commit-log co-sim (per-instruction equivalence).** SimX producer already built. Steps: confirm `UUID_WIDTH>1` (fallback per-warp FIFO, +3d) → promote commit probe to full retire record → uuid-keyed cosim scoreboard (`matched/dut_orphan/simx_orphan/field_mismatch[by_field]`) → SIMD-beat aggregation → bring-up green. **~1.5–2 weeks.**
2. **M3 — `VX_*_if` protocol SVA** (valid-stable-until-ready, no mid-handshake change, no X on qualified-valid, one-hot). Near-free, ‖. **~3–5 days.**
3. **M2 — per-unit white-box scoreboards.** ALU ~3–4d; **FPU IEEE-754 corners (NaN/Inf/denormal/rounding/flags) ~1.5–2 weeks**; LSU ~1 week. **~3–4 weeks.**
4. **M4 — cache/coherence + hazard coverage** (hit/miss/eviction, outstanding depth, interlock/forwarding/structural hazards). **~1–1.5 weeks.**

**Sequencing:** M1 first (per-instruction observability) with M3 ‖; then M2/M4. **Minimal depth (M1+M3): ~3 weeks. Full M1–M4: ~6–9 weeks.**
