# Vortex UVM — Verification Plan (Current Progress)
### Canonical plan, grounded in a file-by-file audit of branch `Sudky_scoreboard_and_coverage_collector`. Boundary: founding `VERIFICATION_PLAN.md`. Microarchitecture white-box = Future Work. Supersedes earlier drafts.

**Synced-to:** `11f71359` (2026-06-26)

### Sync changelog
| Date | SHA | Summary |
|------|-----|---------|
| 2026-06-26 | `0d5bd080` | FULL sync: file-by-file audit of all Gate-0 and Tier-1 items. C1/C2/C3/T4 confirmed OPEN — no code fix merged yet. NEG and P1 binds IMPLEMENTED-UNVERIFIED (code present, no passing sim log on record). T-axi/T-warp/T-mem/T-barr_sync code committed (`6fe0840`, `841a672`) but SimX-routed verification not confirmed. |
| 2026-06-26 | `4c36bd82` | **[S] C1 DONE:** VX_MEM_TAG_WIDTH derived from VX_gpu_pkg; elaboration assert; ISS-01 hex load overflow fixed in prepare.sh. hello kernel_launch_test → PASS. |
| 2026-06-26 | `7764ba14` | **[S] C3 DONE:** ebreak (0x00100073) decoded at fetch stage drives completion as primary; busy=0 and idle-threshold demoted to fallback warnings. hello → PASS. |
| 2026-06-26 | `22115864` | **[S] C2 DONE:** tb_mem_ops%3 fabrication removed; real commit handshake tap → tb_instr_count. vecadd: 12798 instrs / 100k cycles = IPC 0.128. |
| 2026-06-26 | `4661f7cb` | **[S] riscv-dv pipeline:** prepare.sh corrected path + gcc assemble step; --stress-iter wired through Makefile→run.sh→simulate.sh→plusarg. |
| 2026-06-26 | `2ccef437` | **[S] riscv_arithmetic_basic_test PASS (0 errors):** 6 root causes fixed — SimX CSR guards, RVC (rv32im target), RTL CSR assert (sed strip), ecall→ebreak, UVM stale event, vacuous-run. Documented in docs/session_fixes_2026-06-26.md. |
| 2026-06-26 | `11f71359` | **[S] I1 DONE (probe side):** generate loops replace cluster[0] hardcodes for tb_commit_fires_all and tb_ebreak_fetch_all. Correct for any NUM_CLUSTERS/NUM_CORES/ISSUE_WIDTH. hello + riscv-dv stress PASS. |

**Team:** Samuel **[S]** (infra correctness + full configurability) · Ahmad **[A]** (coverage + scoreboard) · Steven **[St]** (tests, sequences, SVA, SimX/DPI)
**RTL pin:** `7a52ee5` · **Tool:** QuestaSim 2021.2_1 / Ubuntu 22.04 · **Primary config:** 1CL/1C/4W/4T RV32 AXI · **Matrix:** 1C/1W, 1C/4W, 2C/4W, 2CL/2C/4W
**Draft files removed** (`vortex_config2.sv`, `vortex_status_if_fixed.sv`, etc.) — treated as non-existent.

---

## Scoping principle
Founding-plan features (ALU/FPU/LSU/SFU, warp scheduling, caches, exceptions) are reached **black-box**: directed tests exercise each unit/scenario; passive coverage probes observe and bin what was hit. The only **checker** is end-state equivalence vs SimX (SimX is run-to-completion; confirmed in `simx_dpi.cpp`). Probes are coverage-only, never a second pass/fail gate. **Features in scope: yes; white-box method: no.**

**Out of scope (founding plan governs):** report §4.4 extras — TCU texture coverage, FPU op-category coverage, dedicated AXI-sequencing covergroup. Report noise items (#22–28) = opportunistic polish, off the critical path.

---

## Progress snapshot (synced `11f71359`, 2026-06-26)

**DONE — Gate-0 (evidenced with passing sim logs):**
- **C1 ✅** `vortex_config.sv` derives `VX_MEM_TAG_WIDTH` from `VX_gpu_pkg::VX_MEM_TAG_WIDTH`; elaboration assert UVM pkg == RTL pkg in `vortex_tb_top.sv`. `kernel_launch_test/hello` → PASS, 0 errors. (`4c36bd82`)
- **C3 ✅** ebreak `0x00100073` decoded at fetch stage drives completion as primary trigger; `busy=0` and idle-threshold demoted to `** Warning:` fallbacks. Generate loop now OR-s across all cores (`11f71359`). (`7764ba14`, extended `11f71359`)
- **C2 ✅** `tb_mem_ops%3` fabrication removed; generate loop sums commit handshakes across all `NUM_CLUSTERS × NUM_SOCKETS × SOCKET_SIZE × ISSUE_WIDTH` lanes into `tb_commit_count_cyc` (popcount). IPC is real. (`22115864`, extended `11f71359`)
- **ISS-01 ✅** `prepare.sh` hex load address overflow fixed (erroneous `+0x80000000` offset removed, CRLF strip, `@80→@00` remap). (`4c36bd82`)

**DONE — Tier 1 (probe side of I1):**
- **I1-probes ✅** `tb_commit_fires_all[TB_NUM_LANES]` and `tb_ebreak_fetch_all[TB_NUM_CORES_T]` driven by `genvar` loops — no more `cluster[0]` hardcodes. Both AXI and non-AXI `ifdef` paths updated. Behaviorally identical for primary config (loop iterates once). (`11f71359`)

**DONE — riscv-dv pipeline (new this session):**
- **riscv-dv `random_instruction_stress_test` / `riscv_arithmetic_basic_test` ✅** — 0 UVM_ERROR, 0 UVM_FATAL, EBREAK at 88387 cycles. Six root causes fixed: SimX M-mode CSR guards, RVC decode crash (rv32im target), RTL CSR assertion (sed strip), ecall→ebreak, UVM stale `wait_trigger()`, vacuous-run false error. Documented in `docs/session_fixes_2026-06-26.md`. (`4661f7cb`, `2ccef437`)

**DONE — Infrastructure (pre-session):**
- 5-agent UVM env, virtual sequencer, config-DB plusarg flow.
- Scoreboard end-state compare vs SimX (memory + console). `compare_all_written()` + `compare_console()`.
- AXI B-channel write responder (`axi_driver.sv`). Write path live.
- AXI interface SVA (`0d5bd080`): valid-stability, addr-stable, WLAST-on-write, BVALID-after-WLAST, RLAST beat-count.
- SimX DPI bridge (init/load/run/read/write/dcr/console/exit-code).
- Coverage CGs: `mem_operation_cg`, axi/dcr/host/status, `cp_active_warps`.
- `vx_instr_probe` bound on `VX_dispatch`; `vx_sched_probe` bound on `VX_schedule`.

**IMPLEMENTED-UNVERIFIED (code present; no passing sim log on record):**
- **`negative_result_test`** — fault injection + inverted verdict. Code correct; no sim log.
- **`axi_memory_test`** + kernel `axi_traffic.cpp`. Sentinel `0x900DCAFE` present; SimX-routed path unconfirmed.
- **`functional_memory_test`**, **`warp_scheduling_test`**, **`barrier_sync_test`** — same caveat.

**OPEN — Gate-0 blockers (T4 is the only remaining Samuel item):**
- **T4** `simulate.sh:123` `-2` subtraction still present. Must remove.
- **SB-DIR** `compare_all_written()` one-directional only. *(Ahmad's lane.)*

**OPEN — other work:**
- I2: elaboration asserts for NUM_CLUSTERS/NUM_CORES/NUM_WARPS/NUM_THREADS (C1 tag-width assert done; counts not yet).
- I3: SimX param-match at runtime (depends on Steven's D-simx).
- I5: dead files (`vortex_config2.sv`, `vortex_status_if_fixed.sv`) still in tree.
- P1-bind: passive `commit_arb_if[*]` bind + UUID assert (for Ahmad's coverage).
- `cache_coherence_test`, `T-exc`.
- Config matrix D-matrix, structural coverage closure.

---

## Status vs founding plan
| Founding requirement | Bar | Current | Gap |
|---|---|---|---|
| smoke / sanity / kernel_launch | High pass | ✅ | — |
| functional_memory_test | High pass | ✅ impl (841a672) | verify SimX-routed & close |
| **axi_memory_test** | High pass | ✅ impl (841a672+6fe0840) | verify SimX-routed & close |
| warp_scheduling_test | Med | ✅ impl (841a672+6fe0840) | verify & close |
| barrier_sync_test | Med | ✅ impl (841a672+6fe0840) | verify & close |
| random_instruction_stress_test | Med | ✅ **PASSING** `2ccef437` | 0 UVM_ERROR; riscv_arithmetic_basic_test verified |
| cache_coherence_test | Low | ❌ | directed test |
| Func cov: instruction opcodes | 100% | ❌ | `instr_class_cg` (dispatch probe) |
| Func cov: warp states | all | 🟡 count only | divergence/barrier states |
| Func cov: memory patterns | aligned/unaligned/contention | 🟡 alignment ✅ | add contention |
| Func cov: exceptions | all types | ❌ | `exception_cg` + stimulus |
| Structural line / toggle | >95% / >90% | ~94% / ~69% | close + waivers |
| Scoreboard RTL vs SimX | ≥1 kernel | 🟡 one-directional | SB-DIR bidirectional |
| Full configurability | cores/clusters/warps/threads | 🟡 ~85% | probe loops done; I2 counts + I3 SimX still open |
| Bench trustworthiness | implicit | 🟡 C1/C2/C3 ✅ · T4 open | Gate 0 — T4 is last Samuel item |

---

## TIER 0 — TRUST THE BENCH 🔴 (GATE 0; nothing downstream counts first)
| # | Item | Owner | Status | Notes |
|---|------|-------|--------|-------|
| C1 | Tag/ID width derived from RTL | **[S]** | ✅ DONE `4c36bd82` | `VX_MEM_TAG_WIDTH = VX_gpu_pkg::VX_MEM_TAG_WIDTH`; elaboration assert in tb_top; hello PASS. |
| C3 | Real EBREAK decode drives completion | **[S]** | ✅ DONE `7764ba14`+`11f71359` | fetch decode primary; busy=0 fallback; generate loop covers all cores. |
| C2 | Real instruction count | **[S]** | ✅ DONE `22115864`+`11f71359` | Commit handshake popcount across all lanes; IPC real. |
| T4 | Remove `-2` error subtraction | **[S]** | 🔴 OPEN | `simulate.sh:123` `-2` still present. **Next item.** |
| SB-DIR | Scoreboard bidirectional | **[A]** | 🔴 OPEN | `compare_all_written()` DUT-only. Ahmad's lane. |
| NEG | Negative injection | **[A]** | ✅ impl | Keep as regression guard after every Gate-0 edit. |

> **🚦 GATE 0:** NEG RED on injection · dropped store fails · no hardcoded subtraction · width assert matches DUT · instr count real.
> **Samuel's Gate-0 remaining:** T4 only.

---

## TIER 1 — CONFIGURABILITY, HIGH TESTS, CORE COVERAGE 🟠

### Configurability — **[S]**
| # | Item | pd | Status | Action |
|---|------|----|--------|--------|
| I1 | Param→RTL probe consistency | 2 | ✅ DONE `11f71359` (probe side) | Generate loops cover all clusters×sockets×cores×lanes for commit count and ebreak detection. SimX runtime param-match still depends on Steven's D-simx. |
| I2 | True width/count asserts | 1 | 🟡 PARTIAL | C1 tag-width assert done. NUM_CLUSTERS/NUM_CORES/NUM_WARPS/NUM_THREADS elaboration asserts still open. |
| I3 | SimX param-match | 0.5 | 🔴 OPEN | config → SimX cores/clusters/warps/threads (with **[St]** D-simx). |
| I5 | Stale comments + dead files | 0.5 | 🔴 OPEN | `vortex_config2.sv`, `vortex_status_if_fixed.sv` still in tree. Fix stale comments. |

### High tests — **[St]** (implemented; verify & close)
| # | Item | pd | Action |
|---|------|----|--------|
| T-axi | `axi_memory_test` + `axi_traffic.cpp` | 0.5 | Implemented (841a672/6fe0840). **Verify it compares DUT-vs-SimX on the result window (not sentinel-only); confirm it passes; close.** |
| T-fmem | `functional_memory_test` + `functional_mem.cpp` | 0.5 | Implemented. Verify SimX-routed golden check passes; delete `.sv.old`; close. |

### Core coverage — **[A]** (P1 bind by **[S]**)
| # | Item | pd | Action |
|---|------|----|--------|
| P1 | Passive commit probe | 1+1 | `bind` on `commit_arb_if[ISSUE_WIDTH]` (post-arb retire; fields uuid/wid/sid/tmask/PC/wb/rd/data/sop/eop). `assert($bits(uuid)>1)`. Feeds count + warp activity. |
| CG1 | `instr_class_cg` | 2 | Opcode class — **off the dispatch probe** (`vx_instr_probe.sv`/`VX_dispatch`), since `commit_t` has no `op_type`. Hook riscv-dv stream. Target 100% opcode/format. |
| CG-mem | contention coverpoint | 0.5 | Add contention + cross to `mem_operation_cg` (alignment already covered). |
| COV-pipe | UCDB merge + honest banner | 1.5 | Per-test save, `-du` exclusions (`-reason EOTH`), merge, HTML+cvg; relabel the interface-only in-sim aggregate; extend `report_phase` for new CGs. |

> **🚦 GATE 1:** all High tests pass through trusted checker · instr+mem coverage populating · merged report builds · primary config runs from parameters.

---

## TIER 2 — MEDIUM/LOW TESTS + REMAINING COVERAGE 🟡

### Tests — **[St]** (+[S] for cache/exc)
| # | Item | Owner | pd | Action |
|---|------|-------|----|--------|
| T-warp | `warp_scheduling_test` + `warp_test.cpp` | **[St]** | 0.5 | Implemented (841a672/6fe0840). Verify SimX-routed end-state check; close. |
| T-barr | `barrier_sync_test` + `barrier_test.cpp` | **[St]** | 0.5 | Implemented. Verify hold→release end-state vs SimX; close. |
| T-rand+ | riscv-dv hardening | **[St]** | 1 | Record seed for replay; constrain ISA to Vortex∩SimX (verify rv32imc vs F/C). |
| T-cache | `cache_coherence_test` | **[S]** | 2 | Directed multi-access + eviction; end-state + cache coverage. |
| T-exc | Exception/interrupt stimulus | **[S]** | 1.5 | ebreak/misaligned/illegal → drives `exception_cg`. |
| SVA-axi | AXI SVA completeness | **[St]** | 1 | Interface SVA partly present; add burst-legality + response-code coverage gaps only. |

### Remaining coverage — **[A]**
| # | Item | pd | Action |
|---|------|----|--------|
| CG2 | warp-**state** coverage | 2.5 | split/join depth, reconvergence, barrier hold/release via passive scheduler probe. Closes "all warp states." |
| CG3 | `exception_cg` | 1.5 | trap/exception type + EBREAK, fed by T-exc. Closes "all exception types." |

> **🚦 GATE 2:** all 8 founding tests pass · all 4 functional-coverage targets populated.

---

## TIER 3 — SCALE, CLOSE, SIGN-OFF 🟠
| # | Item | Owner | pd | Action |
|---|------|-------|----|--------|
| D-simx | SimX cluster runtime + exit-code | **[St]** | 2 | Dynamic `NUM_CLUSTERS` / per-config `.so`. Gates matrix. |
| D-matrix | Config matrix run | **[S]** | 1.5 | 1C/1W … 2CL/2C/4W via param harness. |
| A1 | Software regression breadth | **[St]** (+[A] windows) | 2 | ≥3 kernels + RISC-V conformance subset, result windows. |
| COV-close | Coverage closure loop | **[A]** | 2 | Holes → bias riscv-dv / add directed → re-run → re-merge to func 100% / line>95% / toggle>90% (waivers). |
| TOG | Toggle/line push | **[A]** | 1 | Close cheap toggles; document third-party waivers. |
| SIGN | Seeded regression → one report | **[S]** | 1 | Pass rate, merged func+code vs goal, matrix status. |
| PATCH | `vortex_dpi.patch` + divergence log | **[St]** | 1 | Capture SimX/RTL edits on `7a52ee5`; apply-check. |

> **🚦 GATE 3 — SIGN-OFF:** all High+Med+Low tests pass · functional coverage goals met · line>95% & toggle>90% (waivers documented) · bidirectional SimX equivalence · matrix green · one merged report.

---

## Summary by PERSON
### [S] Samuel — Infra + Config · ≈ 14.5 pd
C1, C3, C2-wire, T4 · I1, I2, I3, I5 · HOST-DCR verify · P1 bind · T-cache, T-exc · D-matrix · SIGN
Critical thread: I1 gates the matrix + multi-warp/core tests.

### [A] Ahmad — Coverage + Scoreboard · ≈ 15.25 pd
SB-DIR, NEG, C2-count · P1 sample, CG1, CG-mem, COV-pipe · CG2 warp-state, CG3 exception · COV-close, TOG, A1 windows
Critical thread: coverage closure trails the tests — build CGs early, close last. (Heaviest load — inherent.)

### [St] Steven — Tests + SVA + DPI · ≈ 9 pd
T-axi/T-fmem/T-warp/T-barr **verify-and-close** (implemented) · T-rand+, SVA-axi · D-simx, A1, PATCH
Critical thread: D-simx gates the matrix. **Four directed tests + kernels already done** (commits 841a672/6fe0840) — remaining is verification routing + the SimX/regression infra. Large slack — absorb slip / assist COV-close.

> **Total ≈ 38 pd ÷ 3 ≈ ~2 weeks** (down from ~42: four directed tests + their kernels implemented). One week covers Tier 0 + most of Tier 1.

---

## Summary by SEVERITY (time)
| Severity | Items | pd | Calendar (3 ‖) |
|---|---|---|---|
| 🔴 Tier 0 | C1, SB-DIR, C3, C2, T4 (NEG ✅) | ~5 | ~2 days |
| 🟠 Tier 1 | I1–I5, T-axi, T-fmem, P1, CG1, CG-mem, COV-pipe | ~12 | end Week 1 |
| 🟡 Tier 2 | warp/barr/cache/exc + T-rand+ + SVA-axi, CG2, CG3 | ~13 | Week 2 |
| 🟠 Tier 3 | D-simx, D-matrix, A1, COV-close, TOG, SIGN, PATCH | ~10.5 | Week 3 |

**Total ≈ 38 pd ÷ 3 ≈ ~2 weeks** (four directed tests + kernels implemented in commits 841a672/6fe0840; B-channel done; AXI SVA partial; I1 70% present; drafts removed). One week covers Tier 0 + most of Tier 1.

---

## Phased timeline
- **Week 1 — Tier 0→1:** Gate 0 (Day 2). I-items + asserts. axi_memory built, functional_memory closed. Commit probe + instr-class + mem-contention coverage. Primary config from params. → **Gate 1.**
- **Week 2 — Tier 2:** warp/barrier/cache/exception tests + riscv-dv hardening + AXI SVA completeness. warp-state + exception covergroups. SimX cluster runtime. → **Gate 2.**
- **Week 3 — Tier 3:** matrix, regression breadth, coverage closure, structural close, seeded merged sign-off report, dpi patch. → **Gate 3.**

---

# FUTURE WORK — Microarchitecture white-box (outside this plan)
Not required by founding plan; after Gate 3.
1. **M1 commit-log co-sim** — SimX producer built, but **SimX is run-to-completion only** (`simx_dpi.cpp`); per-instruction lockstep needs a *stepping* backend first (added scope). Then: confirm `UUID_WIDTH>1` → full retire record → uuid-keyed cosim scoreboard → SIMD-beat aggregation → bring-up. **~2–2.5 weeks** (incl. stepping backend).
2. **M3 `VX_*_if` SVA** — near-free, ‖. **~3–5 days.**
3. **M2 per-unit white-box scoreboards** — ALU ~3–4d; **FPU IEEE-754 corners ~1.5–2 weeks**; LSU ~1 week. **~3–4 weeks.**
4. **M4 cache/coherence + hazard coverage** — **~1–1.5 weeks.**

**Minimal depth (M1+M3): ~3 weeks. Full M1–M4: ~6–9 weeks.**
