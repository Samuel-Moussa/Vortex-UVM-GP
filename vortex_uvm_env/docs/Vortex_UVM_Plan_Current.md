# Vortex UVM — Verification Plan (Current Progress)
### Canonical plan, grounded in a file-by-file audit of branch `Sudky_scoreboard_and_coverage_collector`. Boundary: founding `VERIFICATION_PLAN.md`. Microarchitecture white-box = Future Work. Supersedes earlier drafts.

**Synced-to:** `a3ce838` (2026-06-30)  *(history was rewritten 2026-06-28 to drop co-author trailers — all SHAs below are post-rewrite)*

### Sync changelog
| Date | SHA | Summary |
|------|-----|---------|
| 2026-06-30 | `a3ce838` | **Co-sim restored for ALL test types + coverage gap attack (Samuel).** **`55661d7` co-sim fix:** `simx_run()` refactor never reset the SimX platform (`ProcessorImpl::step()` reset is commented out; `step(0)` was a no-op) → cores ticked un-reset → `Emulator::decode` abort at cycle 0 → SIGABRT killed vsim → every kernel/regression failed. Fixes: (1) `SimPlatform::instance().reset()` before the step loop; (2) `g_startup_addr` only inferred from program-region writes (DATA staging ≥0x9000_0000 no longer clobbers it → exit-code bootstrap not built on the kernel_arg struct); (3) SIGABRT/SIGSEGV guard around the run loop → sentinel −3 → scoreboard UNVERIFIABLE (SimX can never crash vsim again; also covers loop/no_fence); (4) scoreboard `compare_all_written` uses declared result window if staged (regression) else falls back to `[RAM_BASE,DATA_LIMIT)` (kernel/riscv-dv); (5) no-window+EBREAK+SimX-ran → liveness PASS (declared-window-but-0-compared still FAILs); (6) Makefile `PROGRAM_KIND`→`tests/regression/<kind>/kernel.elf`. **Verified DUT-vs-SimX: regression basic 8/8, kernel vecadd_lite 84/84, riscv-dv arith 15/15.** **`bc96979`:** FP-tolerant compare for `fpu*` kernels (≤2 ULP / denormal-flush per f32 lane; NaN/Inf exact; integer & riscv-dv stay bit-exact) → fixes fpu_test; skip load-time `.got`/relocation entries (DUT=0 where SimX holds a program-region pointer) → fixes barrier_lite; BOTH never excuse an injected fault (negative test preserved); real core[0] fetch PC into `status_if.pc` (was hardcoded 0) → `cp_pc_region` 0%→66%; run_suite clears stale Questa `_lock` (dead-owner) before each riscv-dv regen. **`a3ce838`:** wired fetch/memory pipeline stalls into `status_if` (icache/dcache req-stall probes → cp_fetch_stall/cp_memory_stall 50%→100%; status_if+monitor+transaction all updated, EBREAK path too). **Full suite (29 runs) merged: functional 48.95%, total 72.77%.** All fixes config-valid (core[0]-scoped like busy/pc; value/path-based for FP/GOT). |
| 2026-06-30 | `1a32f4d` | **Honest co-sim scoreboard + MSCRATCH kernel-launch harness (Ahmad `7e947a8`) + riscv-dv repairs (Samuel) + coverage 47.20%/73.93%.** **Scoreboard now reports PASS / FAIL / UNVERIFIABLE honestly** instead of silently false-passing: new `regression_test.sv` emulates the host kernel-launch ABI (stages `kernel_arg_t` + I/O buffers into `mem_model`, points `cfg.startup_arg`→MSCRATCH at `ARGS_ADDR=0x9000_0000`, drives the SAME image into SimX, result-window compare). **`basic` verified end-to-end DUT-vs-SimX (8/8 result words, deterministic);** diverge/sgemm/dogfood correctly classified UNVERIFIABLE under run-to-completion co-sim (root cause deferred → Future Work). Touches `vortex_scoreboard.sv`, `simx_dpi.cpp`, `simulate.sh`, `vortex_config.sv`, `regression_test.sv`, `vortex_test_pkg.sv`. **Coverage** functional **47.20%** (was 41.54%), total **73.93%** (`22caf45`, fresh 16-run merge) → handover to Ahmad for the 47.20%→100% push (`60b6256`). **Samuel riscv-dv:** `run_suite.sh` full-suite-at-any-config + auto-merge (`1c302c9`); self-checking arithmetic via GPR-dump + `vx_tmc 0` exit (`f59efa9`); epilogue injection preserves sub-programs (`600395d`); gawk `\b` bug that deleted the assembly tail fixed (`2c8d008`). ⚠️ **`results/run_suite_logs/rv_riscv_arithmetic_basic_test.log` shows a fresh linker error** (`undefined reference to kernel_stack_end / mtvec_handler / test_done`) — that log predates the gawk/epilogue fixes; riscv-dv arith = IMPLEMENTED, needs a clean re-run to re-confirm PASS. **Gate-0 sign-off still blocked on SB-DIR (Ahmad's dropped-store fail-case).** |
| 2026-06-29 | `148ff78` | **Multi-config UNBLOCKED + config-aware coverage + evidence-based AXI ignores (Samuel).** **Configurability/I3 DONE:** (1) `axi_if` default `ID_WIDTH` now derives from `VX_MEM_TAG_WIDTH` (`cf1a827`) — fixes vsim-8451 virtual-interface bind so ANY config elaborates; (2) `prepare.sh` rebuilds SimX **core objects** per-config with `CONFIGS=$ARCH_FLAGS` (`1ce1e9f`) — SimX bounded its issue loop with compile-time `PER_ISSUE_WARPS` while sizing `ibuffers_` at runtime, so default-NUM_WARPS objects crashed (`vector::_M_range_check` in `Core::issue`) at warps/threads<4; now multi-config VERIFIES (2C/4W/4T→140 cmp PASS, 4C/2W→PASS, 2CL/2C/4W/4T→252 cmp PASS). NOT a Ramulator/SimX-core bug. **D-matrix run:** 4C/2W/1T, 8C/8W/2T, 2CL/2C/4W/4T → `cp_num_cores/warps/threads` all reach 100% across the matrix. **Cross-config UCDB merge is INVALID** (vcover-6821 width-dependent toggles + per-core instance inflation 2247→8260, drops BY-INSTANCE %) → SIGN reports **per-config**, not blended. **Config-aware coverage (`55ac424`):** `cp_num_cores/warps/threads` carry `ignore_bins ... with (item != CFG_*)` keyed off compile-time `\`NUM_*` → each build counts ONLY its reachable bins, auto-adapts to any config (crosses too) → those coverpoints + `cross_cores_warps`/`cross_launch_config` = 100%. **Evidence-based AXI ignores (`148ff78`):** investigated `VX_axi_adapter.sv`+`axi_driver.sv` — `cp_size` (adapter hardcodes awsize=CLOG2(DATA_SIZE)→native only) 12.5→100%, `cp_burst`/`cp_len` (FIXED/single) 100%, `cp_bresp`/`cp_rresp0` (TB slave always OKAY, no error-injection test, AXI errors not SimX-verifiable) 25→100%, `cross_type_burst_size` 12.5→100%. **`cp_id_route`/`cross_type_route` NOT waived** (real verification): genuinely reachable routing tag bits, ~22% — empirical shows even-≥4 values structurally absent (config bypass-tag encoding, NUM_DCACHES=0) → **option A: decode bypass-tag layout to prove/ignore the structural evens (deferred).** New kernels `spawn_tmc_sweep` (tmc_cg 60→100, wspawn reachable 100%), `barrier_lite` (barrier_cg→max-reachable; surfaced scoreboard GOT/cache-writeback false-mismatch → Ahmad). Ahmad's AXI_ID "only low 6 matter" confirmed correct (44-bit UUID + 6 routing; already binned that way). Full-suite re-run at 1C/4W/4T (all kernels+directed+18 riscv-dv profiles) in progress to remeasure combined. |
| 2026-06-29 | `7ea95d2` | **INV-1 SOLVED + T4 PROVEN + coverage push.** INV-1 root cause was **`vx_printf` IO volume**, NOT a wspawn/tmc hang (retracted) — native simx completes vecadd (~4.2M cyc); printf-light kernels complete. New `tests/kernel/{vecadd_lite,diverge_lite,fpu_test,fpu_mt}`. **T4 proven:** `negative_result_test PROGRAM_NAME=vecadd_lite` → checker catches injected fault. **Coverage:** functional bins **9.7%→41.54%** (AXI `ignore_bins` fix_18, TCU covergroup guard, FP + divergent kernels); fpu_cg 0→75%, warp divergence 34→81%, reconverge 15→80%; statements 94.14%, total 72.05%. Combined report: `cov/combined_report_2026-06-29/`. riscv-dv saturated. FP-compare divergence (1-ULP/denormal) → Ahmad/Steven. **Gate-0: all Samuel items + negative test done; only SB-DIR (Ahmad) remains.** |
| 2026-06-28 | (coverage) | **Coverage baseline measured** (`COVERAGE_STATUS_2026-06-28.md`). 12-UCDB merge: total 70.11%, statements 93.43%, branches 86.32%, toggles 69.88%, **functional bins 12.17%**. Functional is capped by `axi_transaction_cg` (1699 mostly-unreachable cross bins) → **Ahmad `ignore_bins` is the unlock**. Full kernel sweep: hello/fibonacci PASS, 6 spawn-kernels TIMEOUT (INV-1). riscv-dv sweep: jump_stress PASS; loop/no_fence **SimX SIGABRT (real SimX bug → Steven)**; privileged profiles inapplicable. Warp-state/divergence coverage gated on INV-1. |
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

## 🎯 COVERAGE GAP MAP — RESUME HERE (2026-06-30, post `a3ce838`)
Functional **48.95%** (280/572 bins), total 72.77% — dominated by the `vortex_coverage_collector` interface CGs (341 bins, 28.7%). Done this session: `cp_pc_region` 0→66% (PC wired), `cp_fetch_stall`/`cp_memory_stall` 50→100% (stalls wired). Remaining, prioritized:

**1. `cp_id_route` (23%) + `cross_type_route` (16%) — ~157 bins, BIGGEST.** Route = `current_axi.id[ROUTE_W-1:0]`, ROUTE_W=6 (AXI_ID_W 50 − UUID 44). **Decoded empirically (DBG_ROUTE probe, vecadd_lite) + RTL (`VX_axi_adapter.sv`):**
  - **Reads** (`arid=tbuf_waddr`): route = `CLOG2(TAG_BUFFER_SIZE=16)`=4-bit tbuf index → **∈[0,15]** (structural).
  - **Writes** (`awid=mem_req_tag`): route always **ODD** (bit0=1) — seen 1,3,5,7,9,11,13,17,19,21,25,29.
  - **bit5 (route≥32) NEVER set** across the full 29-run suite → route content ≤5 bits → **structurally unreachable**.
  - **Hit set:** 0,1,2,3,5,7,9,11,13,15,17,19,21,25,29 (15/64).
  - **STRUCTURAL (waivable, config-aware, with trip-wire):** route≥32 (bit5); even≥16 (16,18,20,22,24,26,28,30 — reads≤15 exclude, writes odd exclude).
  - **STIMULUS (reachable, NOT waivable):** even tbuf slots 4,6,8,10,12,14 (need more outstanding reads); odd writes 23,27,31 (more write-tag variety). → needs an **AXI outstanding-request stress test**.
  - **(a) DONE (commit pending this session):** config-aware `ignore_bins` on `cp_id_route` (route≥32 + even≥16) and `cross_type_route` (READ×[17:31], WRITE×even) → `cp_id_route` 64→24 bins (≈62.5% after suite merge, was 23.4%), `cross_type_route` 128→32 bins. Validated: vecadd_lite compiles+PASS, denominator shrank, hits preserved.
  - **(b) TODO next session:** write the AXI outstanding-request stress test to fill the 9 reachable-but-unhit values (tbuf slots 4,6,8,10,12,14 + odd writes 23,27,31) → cp_id_route/cross_type_route → ~100%.

**2. status_performance stalls execute/decode/issue (50%), `cross_stall_types`/`cross_ipc_stalls`** — need RTL taps for the 3 remaining stall types (only icache→fetch, dcache→memory probed). Ahmad status-agent + RTL.
**3. `cp_pc_region` text_high (≥0x80010000)** — needs a kernel with larger text.
**4. host_operation_cg** `cp_op_type`/`cp_completion`/`cross_op_completion` (8%) — stimulus (more op types) or waive timeout bin.
**5. dcr_config_cg** `cp_startup_align`/`cp_data_magnitude`/`cross_addr_data` — directed DCR variation.
**6. `cp_active_warps` 16%, `cross_sfu_threads`/`cross_join`/`cross_dvg_depth`** — divergence/warp-count stimulus.

*Re-merge the full suite after waivers/stimulus land to remeasure. cp_id_route waiver alone shrinks the denominator most.*

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
- **`negative_result_test`** — ✅ PROVEN 2026-06-29 on `vecadd_lite` (completing program): checker catches injected fault, verdicts not vacuous.
- **`functional_memory_test`**, **`warp_scheduling_test`**, **`barrier_sync_test`** — committed; SimX-routed end-state pass not yet logged.

**OPEN — Gate-0 sign-off (no remaining Samuel code item):**
- **SB-DIR** `compare_all_written()` one-directional only — can't detect dropped stores. *(Ahmad's lane; handover `docs/fixes/HANDOVER_Ahmad_scoreboard_dropped_stores.md`.)*
- **Full negative test** — ✅ DONE: `negative_result_test PROGRAM_NAME=vecadd_lite` catches the injected fault (INV-1 solved → completing program available).

**DONE this session (Samuel, 2026-06-29 — see top changelog `148ff78`):**
- **I3 SimX param-match ✅** (`cf1a827` AXI ID_WIDTH derive + `1ce1e9f` per-config SimX object rebuild) — multi-config now elaborates AND verifies (2C/4W/4T, 2CL/2C/4W/4T, 4C/2W).
- **D-matrix runs ✅ (partial)** — 3 configs run+verified; config bins → 100% across matrix; cross-config-merge-invalidity established (report per-config).
- **Config-aware coverage ✅** (`55ac424`) — `cp_num_*` auto-adapt per config to 100%. **Evidence-based AXI ignores ✅** (`148ff78`) — size/burst/len/resp → 100% from RTL evidence.
- **Directed kernels ✅** — `spawn_tmc_sweep` (tmc/wspawn), `barrier_lite` (barrier_cg).

**OPEN — Samuel's remaining work:**
- **cp_id_route tag-decode (option A, deferred)** — decode the bypass-tag layout (`NUM_DCACHES=0` path) to PROVE which routing values are structural (even-≥4 absent empirically) → ignore those, fill the rest by stimulus. Until then `cp_id_route`/`cross_type_route` are the AXI residual (~22%). Do NOT waive without proof.
- **SIGN — per-config merged report** — the matrix can't blend into one UCDB (vcover-6821); aggregate **per-config** pass rate + functional/code + matrix status.
- **I6 — XLEN 32/64 configurability** — build flow hardcodes RV32 (`prepare.sh` `--target=rv32im`/`-mabi=ilp32`); wire an `--xlen` knob (`+define XLEN_64` + rv64 march/mabi + SimX xlen). *(configurability lane.)*
- **T-exc** exception/interrupt stimulus (drive `exception_cg`); **T-cache** `cache_coherence_test`.
- **PathB-launch (PARKED)** — host-driven launch for `tests/regression/*`: bump-alloc device addrs → backdoor-write inputs+binary+`kernel_arg_t` → set `cfg.startup_arg_addr` → real `STARTUP_ARG0/1` → mirror into SimX RAM; DCR as **RAL**. Pilot one kernel first. *Revisit after coverage.*
- **P1-bind** ✅ DONE (`1ae658f`).

**Dead-sequence audit (2026-06-28):** only 6 of 23 agent sequence classes are started. Dispositions:
- **(a) mem_\* (6)** — dormant by config (mem_agent passive in AXI mode); kept, header note added. ✅
- **(b) host load/read/configure/complete (4)** — Path-B scaffolding → **handed to Steven** (`HANDOVER_Steven_pathB_host_launch.md`).
- **(c) AXI single/write-read/burst-write/random/stress + dcr_random** — unused-but-useful stimulus → **handed to Ahmad** for coverage (`HANDOVER_Ahmad_unused_axi_dcr_sequences.md`).
- **redundant** `dcr_minimal_startup_sequence` — deleted (I5 hygiene). ✅

**OPEN — investigations (un-boxed):**
- **INV-1** — **SOLVED 2026-06-29.** Root cause = **`vx_printf` console-IO volume** (NOT a wspawn/tmc hang — that hypothesis retracted). Native simx completes vecadd (~4.2M cyc); bench retires climb with cycles (progressing). Fix: printf-light kernels — **`vecadd_lite`** (multi-warp, no printf) PASSES 9915 cyc, DUT==SimX. Unblocks T4. `vx_spawn`/multi-warp work fine. See `docs/fixes/INV1_kernel_completion_hang.md` (top correction).
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
| Structural line / toggle | >95% / >90% | stmt 93.43% / toggle 69.88% (12-test merge) | close + waivers (see `COVERAGE_STATUS_2026-06-29.md`) |
| **Functional (covergroup bins)** | 100% | **per-config, on reachable** — config/AXI coverpoints now config-aware & evidence-ignored → `cp_num_cores/warps/threads`, crosses, `cp_size`, `cp_burst/len`, `cp_bresp/rresp0`, `cross_type_burst_size` all **100%**; new combined % being remeasured (was 41.54%). | residual: `cp_id_route`/`cross_type_route` (option A tag-decode), instr_class breadth, Zicond czeq/czne (needs `zicond` build) |
| Scoreboard RTL vs SimX | ≥1 kernel | 🟡 one-directional + **GOT/cache-writeback false-mismatch found** (barrier_lite) | SB-DIR bidirectional + preload shadow / ignore read-only `.got` words → Ahmad |
| Full configurability | cores/clusters/warps/threads | ✅ **~100%** | probe loops ✅ + I2 asserts ✅ + I3 SimX param-match ✅ (multi-config verifies); only XLEN 32/64 (I6) open |
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
| NEG | Negative injection | **[A]** | ✅ PROVEN 2026-06-29 | Catches injected fault on vecadd_lite (INV-1 solved). Regression guard live. |

> **🚦 GATE 0:** NEG RED on injection · dropped store fails · no hardcoded subtraction ✅ · width assert matches DUT ✅ · instr count real ✅.
> **Samuel's Gate-0: ALL DONE (C1/C2/C3/T4 + negative test proven on vecadd_lite).** Only remaining Gate-0 blocker: SB-DIR (Ahmad).

---

## TIER 1 — CONFIGURABILITY, HIGH TESTS, CORE COVERAGE 🟠

### Configurability — **[S]**
| # | Item | pd | Status | Action |
|---|------|----|--------|--------|
| I1 | Param→RTL probe consistency | 2 | ✅ DONE `c80e336` (probe side) | Generate loops cover all clusters×sockets×cores×lanes for commit count and ebreak detection. SimX runtime param-match still depends on Steven's D-simx. |
| I2 | True width/count asserts | 1 | ✅ DONE `b55f392`+`8063ddc` | `u_i2_topology_asserts`: NUM_* + alias plusargs vs RTL macros at time=0, `$fatal` on mismatch. C1 tag-width assert also done. |
| I3 | SimX param-match | 0.5 | ✅ DONE `cf1a827`+`1ce1e9f` (2026-06-29) | config → RTL (`+define`) + SimX (`-DNUM_*`, **core objects rebuilt per-config**) + runtime plusargs, all matched (I2 asserts confirm). Multi-config VERIFIES: 2C/4W/4T 140 cmp, 2CL/2C/4W/4T 252 cmp, 4C/2W PASS. Fixed AXI ID_WIDTH virtual-iface bind + SimX `Core::issue` over-index at warps/threads<4. |
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
| CG2 | warp-**state** coverage | 2.5 | split/join depth, reconvergence, barrier hold/release via passive scheduler probe. Closes "all warp states." Samuel's `spawn_tmc_sweep`/`barrier_lite` already drove tmc/wspawn/barrier→100%-reachable. |
| CG3 | `exception_cg` | 1.5 | trap/exception type + EBREAK, fed by T-exc. Closes "all exception types." |
| SB-GOT | scoreboard read-only `.got` false-mismatch | 0.5 | **NEW (found by Samuel via barrier_lite):** DUT cache writeback zero-clobbers a read-only GOT word the program never stores; `shadow_memory` has no image preload → false MEM MISMATCH. Fix: preload shadow from program image, or ignore writeback of never-stored read-only `.got`/`.rodata` words (like existing stack/poison gates). See `COVERAGE_STATUS_2026-06-29.md` §4c. |
| AXI-route | `cp_id_route` structural-ignore confirm | 0.5 | Samuel ignored size/burst/len/resp (evidence-based) + sign-off needed on the config-aware `ignore_bins` (`55ac424`/`148ff78`). Remaining: confirm/decode the bypass-tag so the even-≥4 `cp_id_route` values can be ignored (option A) — needs AXI/tag judgment. |

> **🚦 GATE 2:** all 8 founding tests pass · all 4 functional-coverage targets populated.

---

## TIER 3 — SCALE, CLOSE, SIGN-OFF 🟠
| # | Item | Owner | pd | Action |
|---|------|-------|----|--------|
| PathB-launch | Host-driven kernel launch (enables `tests/regression/*`) | **[S]** | 3+ | **PARKED 2026-06-28.** Mirror runtime `vx_start`: bump-alloc device addrs → backdoor-write inputs + kernel binary + `kernel_arg_t` (mem_model `write_block`) → set `cfg.startup_arg_addr` → dcr_driver writes real `STARTUP_ARG0/1` (today 0) → mirror into SimX RAM. Model DCR as **RAL** (`uvm_reg_block`). Pilot one kernel end-to-end (vecadd-reg or sgemm), then template. Design captured in chat; revisit after INV-1/coverage. |
| D-simx | SimX cluster runtime + exit-code | **[St]** | 2 | ✅ **largely DONE via Samuel's per-config SimX object rebuild** (`1ce1e9f`): per-config `.so` with matching `NUM_CLUSTERS/CORES/WARPS/THREADS`; 2CL/2C/4W/4T verifies (252 cmp). Steven residual: SimX `loop`/`no_fence` SIGABRT + exit-code polish. |
| D-matrix | Config matrix run | **[S]** | 1.5 | 🟡 **IN PROGRESS** — 4C/2W/1T, 8C/8W/2T, 2CL/2C/4W/4T run + verified; `cp_num_cores/warps/threads`→100% across matrix. **Cross-config merge INVALID** (vcover-6821 + instance inflation) → report **per-config**, not one blended UCDB. Remaining: formalize per-config matrix table in SIGN. |
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
