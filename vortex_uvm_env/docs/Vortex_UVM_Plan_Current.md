# Vortex UVM — Verification Plan (Current Progress)
### Canonical plan, grounded in a file-by-file audit of branch `Sudky_scoreboard_and_coverage_collector`. Boundary: founding `VERIFICATION_PLAN.md`. Microarchitecture white-box = Future Work. Supersedes earlier drafts.

**Synced-to:** `8200cec` (2026-06-28)  *(history was rewritten 2026-06-28 to drop co-author trailers — all SHAs below are post-rewrite)*

### Sync changelog
| Date | SHA | Summary |
|------|-----|---------|
| 2026-06-28 | `8200cec` | **FULL re-sync (post history-rewrite).** **Samuel:** Gate-0 complete — **T4 DONE** (`df6206e`); **I2 DONE** (`b55f392`); **I5 DONE** (`6838b21`); review-pass fixes Issue 2 sustained busy=0 + Issue 3 I2 alias (`8063ddc`); 16 per-issue fix docs, project README, riscv-dv setup guide. **Ahmad:** architectural probe + coverage pipeline overhaul (`e547314`), banner relabelled to "interface subtotal" (`cd52792`), CG2 warp/scheduler-state probe (`988559a`), cp_id re-binned to routing field (`70c9a7e`), clean 8-run merge via unique testname → 2246 instances / 70.16% total (`6ca3d87`), C1 AXI ID widening end-to-end (`8bed180`). **Steven:** AXI SVA inline in `vortex_axi_if.sv` validated — `axi_memory_test` PASS, zero SVA fires (`9881e86`); 4 directed tests + kernels (`1fd6b09`, `63361b7`); microarch instruction trace + SimX changes (`ee9b1c0`, `554080e`). Evidence: `results/20260628/run_014053` & `run_022612` riscv-dv → TEST PASSED, 0 UVM_ERROR/FATAL. |
| 2026-06-26 | `0d5bd080` | FULL sync: file-by-file audit of all Gate-0 and Tier-1 items. C1/C2/C3/T4 confirmed OPEN — no code fix merged yet. NEG and P1 binds IMPLEMENTED-UNVERIFIED (code present, no passing sim log on record). T-axi/T-warp/T-mem/T-barr_sync code committed (`6fe0840`, `841a672`) but SimX-routed verification not confirmed. |
| 2026-06-26 | `4c36bd82` | **[S] C1 DONE:** VX_MEM_TAG_WIDTH derived from VX_gpu_pkg; elaboration assert; ISS-01 hex load overflow fixed in prepare.sh. hello kernel_launch_test → PASS. |
| 2026-06-26 | `7764ba14` | **[S] C3 DONE:** ebreak (0x00100073) decoded at fetch stage drives completion as primary; busy=0 and idle-threshold demoted to fallback warnings. hello → PASS. |
| 2026-06-26 | `22115864` | **[S] C2 DONE:** tb_mem_ops%3 fabrication removed; real commit handshake tap → tb_instr_count. vecadd: 12798 instrs / 100k cycles = IPC 0.128. |
| 2026-06-26 | `4661f7cb` | **[S] riscv-dv pipeline:** prepare.sh corrected path + gcc assemble step; --stress-iter wired through Makefile→run.sh→simulate.sh→plusarg. |
| 2026-06-26 | `2ccef437` | **[S] riscv_arithmetic_basic_test PASS (0 errors):** 6 root causes fixed — SimX CSR guards, RVC (rv32im target), RTL CSR assert (sed strip), ecall→ebreak, UVM stale event, vacuous-run. Documented per-issue in docs/fixes/ (fix_06–fix_12). |
| 2026-06-26 | `11f71359` | **[S] I1 DONE (probe side):** generate loops replace cluster[0] hardcodes for tb_commit_fires_all and tb_ebreak_fetch_all. Correct for any NUM_CLUSTERS/NUM_CORES/ISSUE_WIDTH. hello + riscv-dv stress PASS. |

**Team:** Samuel **[S]** (infra correctness + full configurability) · Ahmad **[A]** (coverage + scoreboard) · Steven **[St]** (tests, sequences, SVA, SimX/DPI)
**RTL pin:** `7a52ee5` · **Tool:** QuestaSim 2021.2_1 / Ubuntu 22.04 · **Primary config:** 1CL/1C/4W/4T RV32 AXI · **Matrix:** 1C/1W, 1C/4W, 2C/4W, 2CL/2C/4W
**Draft files removed** (`vortex_config2.sv`, `vortex_status_if_fixed.sv`, etc.) — treated as non-existent.

---

## Scoping principle
Founding-plan features (ALU/FPU/LSU/SFU, warp scheduling, caches, exceptions) are reached **black-box**: directed tests exercise each unit/scenario; passive coverage probes observe and bin what was hit. The only **checker** is end-state equivalence vs SimX (SimX is run-to-completion; confirmed in `simx_dpi.cpp`). Probes are coverage-only, never a second pass/fail gate. **Features in scope: yes; white-box method: no.**

**Out of scope (founding plan governs):** report §4.4 extras — TCU texture coverage, FPU op-category coverage, dedicated AXI-sequencing covergroup. Report noise items (#22–28) = opportunistic polish, off the critical path.

---

## Progress snapshot (synced `8200cec`, 2026-06-28)

**DONE — Gate-0 (Samuel; evidenced with passing sim logs):**
- **C1 ✅** `vortex_config.sv` derives `VX_MEM_TAG_WIDTH` from `VX_gpu_pkg::VX_MEM_TAG_WIDTH`; elaboration assert UVM pkg == RTL pkg in `vortex_tb_top.sv`. `kernel_launch_test/hello` → PASS, 0 errors. Ahmad later widened the AXI ID end-to-end downstream (`8bed180`). (`5f19a67`)
- **C3 ✅** ebreak `0x00100073` decoded at fetch stage drives completion as primary trigger; `busy=0` and idle-threshold demoted to `** Warning:` fallbacks. Generate loop OR-s across all cores. (`a46a109`, extended `c80e336`)
- **C2 ✅** `tb_mem_ops%3` fabrication removed; generate loop sums commit handshakes across all `NUM_CLUSTERS × NUM_SOCKETS × SOCKET_SIZE × ISSUE_WIDTH` lanes into `tb_commit_count_cyc` (popcount). IPC is real. (`b14efc5`, extended `c80e336`)
- **T4 ✅** `simulate.sh` error gate `REAL_UVM_ERRORS=$UVM_ERRORS` — `-2` subtraction removed; verified intact at HEAD after Ahmad's coverage edit to the same file. (`df6206e`)
- **ISS-01 ✅** `prepare.sh` hex load address overflow fixed (erroneous `+0x80000000` offset removed, CRLF strip, `@80→@00` remap). (`5f19a67`)

**DONE — Tier 1 configurability (Samuel):**
- **I1-probes ✅** `tb_commit_fires_all[TB_NUM_LANES]` and `tb_ebreak_fetch_all[TB_NUM_CORES_T]` driven by `genvar` loops — no more `cluster[0]` hardcodes. Both AXI and non-AXI `ifdef` paths updated. (`c80e336`)
- **I2 ✅** `u_i2_topology_asserts`: NUM_CLUSTERS/CORES/WARPS/THREADS (+ short aliases) read at time=0, compared vs RTL macros, `$fatal` on mismatch; prints `[I2-ASSERT] Topology OK`. (`b55f392`, alias fix `8063ddc`)
- **I5 ✅** dead files (`vortex_config2.sv`, `vortex_status_if_fixed.sv`) removed; stale `// 8` tag-width comments corrected. (`6838b21`)
- **Issue 2 ✅ (review fix)** `busy==0` completion now requires sustained de-assertion (`BUSY_LOW_THRESHOLD`, default 100) — a transient gap no longer ends the test. (`8063ddc`)

**DONE — riscv-dv pipeline (Samuel):**
- **riscv-dv `random_instruction_stress_test` / `riscv_arithmetic_basic_test` ✅** — 0 UVM_ERROR, 0 UVM_FATAL, ebreak completion. Six root causes fixed: SimX M-mode CSR guards, RVC decode crash (rv32im target), RTL CSR assertion (sed strip), ecall→ebreak, UVM stale `wait_trigger()`, vacuous-run false error. Per-issue docs `fix_06–fix_12`; setup guide `docs/RISCV_DV_GUIDE.md`. Re-confirmed at HEAD: `results/20260628/run_014053` & `run_022612` PASS. (`f545e1a`, `5f6ddff`)

**DONE — Coverage (Ahmad):**
- **Architectural probe + pipeline overhaul ✅** (`e547314`); **honest banner** — "TOTAL COVERAGE" relabelled "INTERFACE SUBTOTAL, sanity check only", 90% verdict deferred to merged UCDB (`cd52792`).
- **CG2 warp/scheduler-state probe ✅** via `vx_sched_probe` (`988559a`).
- **cp_id re-bin ✅** to real routing field — drops 256-bin UUID inflation that suppressed merged % (`70c9a7e`).
- **Coverage merge ✅** unique per-run testname → clean 8-run single-config merge: 0 errors, 2246 instances, **70.16% total** (`6ca3d87`).
- **C1 AXI ID widening ✅** end-to-end across `axi_transaction`/`axi_driver`/responder + interfaces (`8bed180`).

**DONE — Tests / SVA / SimX (Steven):**
- **AXI SVA ✅** inline in `vortex_axi_if.sv` (handshake-stability + burst-legality property groups); validated by `axi_memory_test` → PASS, **zero SVA fires** (report: `docs/AXI_SVA_report.md`). (`9881e86`)
- **4 directed tests + kernels ✅** committed: `axi_memory_test`, `functional_memory_test`, `warp_scheduling_test`, `barrier_sync_test` (`1fd6b09`, `63361b7`).
- **SimX microarch trace + DPI changes ✅** instruction-by-instruction trace and SimX edits to verify microarch (`ee9b1c0`, `554080e`).

**DONE — Infrastructure (pre-session):**
- 5-agent UVM env, virtual sequencer, config-DB plusarg flow.
- Scoreboard end-state compare vs SimX (memory + console). `compare_all_written()` + `compare_console()`.
- AXI B-channel write responder (`axi_driver.sv`). Write path live.
- AXI interface SVA (`0d5bd080`): valid-stability, addr-stable, WLAST-on-write, BVALID-after-WLAST, RLAST beat-count.
- SimX DPI bridge (init/load/run/read/write/dcr/console/exit-code).
- Coverage CGs: `mem_operation_cg`, axi/dcr/host/status, `cp_active_warps`.
- `vx_instr_probe` bound on `VX_dispatch`; `vx_sched_probe` bound on `VX_schedule`.

**VERIFIED this window:** `axi_memory_test` now confirmed PASS via Steven's AXI SVA validation (was IMPLEMENTED-UNVERIFIED).

**IMPLEMENTED-UNVERIFIED (code present; no passing SimX-routed sim log on record):**
- **`negative_result_test`** — fault injection + inverted verdict. Code correct; full run blocked by INV-1 (no completing program).
- **`functional_memory_test`**, **`warp_scheduling_test`**, **`barrier_sync_test`** — committed; SimX-routed end-state pass not yet logged.

**OPEN — Gate-0 sign-off (no remaining Samuel code item):**
- **SB-DIR** `compare_all_written()` one-directional only — can't detect dropped stores. *(Ahmad's lane; handover `docs/fixes/HANDOVER_Ahmad_scoreboard_dropped_stores.md`.)*
- **Full negative test** needs a completing program — blocked by **INV-1** (vecadd `busy` never idles).

**OPEN — Samuel's remaining work:**
- **P1-bind** ✅ DONE (`1ae658f`) — passive `commit_arb_if[*]` probe bound + UUID assert + liveness proof (11498 retires). Ahmad now samples it.
- **PathB-launch (PARKED, not started)** — host-driven kernel launch so `tests/regression/*` (sgemm/sort/conv3/…) become runnable: bump-allocate device addrs → backdoor-write inputs + kernel binary + `kernel_arg_t` (mem_model `write_block`) → set `cfg.startup_arg_addr` so dcr_driver writes real `STARTUP_ARG0/1` (today hardcoded 0, dcr_driver.sv:120-121) → mirror the same setup into SimX RAM. **RAL** (`uvm_reg_block` over DCR) belongs here. Pilot one kernel end-to-end first. *Deferred by Samuel's decision 2026-06-28 — revisit after INV-1/coverage.*
- **I6 — XLEN 32/64 configurability (NEW, open)** — RTL (`XLEN_32/64`) + UVM widths (`vortex_config.sv:68-73`) already support both, but the build flow hardcodes RV32 (`prepare.sh:304,408` → `--target=rv32im`, `-mabi=ilp32`) and there is no `--xlen` run-knob. Wire XLEN end-to-end (run flag → `+define XLEN_64` + rv64 march/mabi + SimX xlen) to make the env truly 32/64-switchable. *(Samuel — configurability lane.)*
- I3: SimX param-match at runtime (depends on Steven's D-simx).
- `cache_coherence_test`, `T-exc`.
- D-matrix config matrix; SIGN merged report.

**Dead-sequence audit (2026-06-28):** only 6 of 23 agent sequence classes are started. Dispositions:
- **(a) mem_\* (6)** — dormant by config (mem_agent passive in AXI mode); kept, header note added. ✅
- **(b) host load/read/configure/complete (4)** — Path-B scaffolding → **handed to Steven** (`HANDOVER_Steven_pathB_host_launch.md`).
- **(c) AXI single/write-read/burst-write/random/stress + dcr_random** — unused-but-useful stimulus → **handed to Ahmad** for coverage (`HANDOVER_Ahmad_unused_axi_dcr_sequences.md`).
- **redundant** `dcr_minimal_startup_sequence` — deleted (I5 hygiene). ✅

**OPEN — investigations (un-boxed):**
- **INV-1** — ROOT-CAUSED (SIMT warp-control: `wspawn`'d warps parked at `vx_tmc zero`; not 32/64, not DCR args, not TLS size). Handed to Steven for waveform/microarch. Blocks the real T4 negative test. See `docs/fixes/INV1_kernel_completion_hang.md`.
- **INV-2** `assert_dcr_write_timing` fires at startup (3915/3975 ns), inflating RTL error count.

---

## Status vs founding plan
| Founding requirement | Bar | Current | Gap |
|---|---|---|---|
| smoke / sanity / kernel_launch | High pass | ✅ | — |
| functional_memory_test | High pass | ✅ impl (`1fd6b09`) | verify SimX-routed & close |
| **axi_memory_test** | High pass | ✅ **PASSING** (`1fd6b09`+`9881e86`) | AXI SVA validated, zero fires (Steven). |
| warp_scheduling_test | Med | ✅ impl (`1fd6b09`+`63361b7`) | verify & close |
| barrier_sync_test | Med | ✅ impl (`1fd6b09`+`63361b7`) | verify & close |
| random_instruction_stress_test | Med | ✅ **PASSING** `5f6ddff` | 0 UVM_ERROR; re-confirmed at HEAD (run_014053/run_022612) |
| cache_coherence_test | Low | ❌ | directed test |
| Func cov: instruction opcodes | 100% | 🟡 defined, not closed | per-class CGs (alu/lsu/sfu/noop) live in `vx_instr_probe.sv`; needs wider riscv-dv ISA stimulus to fill `op_type` bins |
| Func cov: warp states | all | 🟡 defined, not closed | `sched_state/divergence/reconverge/barrier/tmc/wspawn` CGs live in `vx_sched_probe.sv` (`988559a`); needs divergent + barrier stimulus |
| Func cov: memory patterns | aligned/unaligned/contention | 🟡 alignment ✅ | add contention |
| Func cov: exceptions | all types | ❌ | `exception_cg` + stimulus |
| Structural line / toggle | >95% / >90% | ~94% / ~69% | close + waivers |
| Scoreboard RTL vs SimX | ≥1 kernel | 🟡 one-directional | SB-DIR bidirectional |
| Full configurability | cores/clusters/warps/threads | 🟡 ~90% | probe loops ✅ + I2 count asserts ✅; I3 SimX-runtime open |
| Bench trustworthiness | implicit | ✅ C1/C2/C3/T4 ✅ | Gate 0 — all four Samuel items DONE; SB-DIR (Ahmad) + INV-1 remain |

---

## TIER 0 — TRUST THE BENCH 🔴 (GATE 0; nothing downstream counts first)
| # | Item | Owner | Status | Notes |
|---|------|-------|--------|-------|
| C1 | Tag/ID width derived from RTL | **[S]** | ✅ DONE `5f19a67` | `VX_MEM_TAG_WIDTH = VX_gpu_pkg::VX_MEM_TAG_WIDTH`; elaboration assert in tb_top; hello PASS. AXI ID widened end-to-end by Ahmad (`8bed180`). |
| C3 | Real EBREAK decode drives completion | **[S]** | ✅ DONE `a46a109`+`c80e336` | fetch decode primary; busy=0 fallback (now sustained, `8063ddc`); generate loop covers all cores. |
| C2 | Real instruction count | **[S]** | ✅ DONE `b14efc5`+`c80e336` | Commit handshake popcount across all lanes; IPC real. |
| T4 | Remove `-2` error subtraction | **[S]** | ✅ DONE `df6206e` | `REAL_UVM_ERRORS=$UVM_ERRORS`; intact at HEAD after Ahmad's same-file edit. |
| SB-DIR | Scoreboard bidirectional | **[A]** | 🔴 OPEN | `compare_all_written()` DUT-only. Ahmad's lane (handover written). |
| NEG | Negative injection | **[A]** | ✅ impl | Regression guard. Full run blocked by INV-1 (no completing program). |

> **🚦 GATE 0:** NEG RED on injection · dropped store fails · no hardcoded subtraction ✅ · width assert matches DUT ✅ · instr count real ✅.
> **Samuel's Gate-0: ALL FOUR DONE (C1/C2/C3/T4).** Remaining: SB-DIR (Ahmad) + INV-1 (completing program for the negative test).

---

## TIER 1 — CONFIGURABILITY, HIGH TESTS, CORE COVERAGE 🟠

### Configurability — **[S]**
| # | Item | pd | Status | Action |
|---|------|----|--------|--------|
| I1 | Param→RTL probe consistency | 2 | ✅ DONE `c80e336` (probe side) | Generate loops cover all clusters×sockets×cores×lanes for commit count and ebreak detection. SimX runtime param-match still depends on Steven's D-simx. |
| I2 | True width/count asserts | 1 | ✅ DONE `b55f392`+`8063ddc` | `u_i2_topology_asserts`: NUM_* + alias plusargs vs RTL macros at time=0, `$fatal` on mismatch. C1 tag-width assert also done. |
| I3 | SimX param-match | 0.5 | 🔴 OPEN | config → SimX cores/clusters/warps/threads (with **[St]** D-simx). |
| I5 | Stale comments + dead files | 0.5 | ✅ DONE `6838b21` | dead files removed; `// 8` comments corrected to derived width. |
| I6 | XLEN 32/64 configurability | 1.5 | 🔴 OPEN (NEW) | RTL + UVM widths already 64-ready (`vortex_config.sv:68-73`); build flow hardcodes RV32 (`prepare.sh:304,408`) and no `--xlen` knob. Wire run-flag → `+define XLEN_64` + rv64 march/mabi + SimX xlen. |

### High tests — **[St]** (implemented; verify & close)
| # | Item | pd | Action |
|---|------|----|--------|
| T-axi | `axi_memory_test` + `axi_traffic.cpp` | 0.5 | ✅ **PASSING** (`1fd6b09`+`63361b7`); AXI SVA validated zero fires (`9881e86`, `docs/AXI_SVA_report.md`). Close. |
| T-fmem | `functional_memory_test` + `functional_mem.cpp` | 0.5 | Implemented (`1fd6b09`). Verify SimX-routed golden check passes; delete `.sv.old`; close. |

### Core coverage — **[A]** (P1 bind by **[S]**)
| # | Item | pd | Action |
|---|------|----|--------|
| P1 | Passive commit probe | 1+1 | ✅ **bind side DONE (Samuel, 2026-06-28)** — `tb/vx_commit_probe.sv` bound `bind VX_commit … u_commit_probe`; passive read-only over `[\`ISSUE_WIDTH]`, exposes uuid/wid/sid/tmask/PC/wb/rd/data/sop/eop, `assert($bits(uuid)>1)`. riscv-dv PASS, 0 err, assert silent. **Ahmad: hang covergroups (count + warp activity) off this probe.** |
| CG1 | `instr_class_cg` | 2 | Opcode class — **off the dispatch probe** (`vx_instr_probe.sv`/`VX_dispatch`), since `commit_t` has no `op_type`. Hook riscv-dv stream. Target 100% opcode/format. |
| CG-mem | contention coverpoint | 0.5 | Add contention + cross to `mem_operation_cg` (alignment already covered). |
| COV-pipe | UCDB merge + honest banner | 1.5 | 🟡 PROGRESS — banner relabelled "interface subtotal" (`cd52792`); clean 8-run single-config merge works (unique testname `6ca3d87`): 2246 instances / **70.16% total**; cp_id re-binned (`70c9a7e`). Remaining: `-du` exclusions, HTML+cvg, extend `report_phase` for new CGs. |

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
| PathB-launch | Host-driven kernel launch (enables `tests/regression/*`) | **[S]** | 3+ | **PARKED 2026-06-28.** Mirror runtime `vx_start`: bump-alloc device addrs → backdoor-write inputs + kernel binary + `kernel_arg_t` (mem_model `write_block`) → set `cfg.startup_arg_addr` → dcr_driver writes real `STARTUP_ARG0/1` (today 0) → mirror into SimX RAM. Model DCR as **RAL** (`uvm_reg_block`). Pilot one kernel end-to-end (vecadd-reg or sgemm), then template. Design captured in chat; revisit after INV-1/coverage. |
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
