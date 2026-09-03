# Vortex GPGPU — Verification Plan (feature-based)

**Version:** 1.0 · **Date:** 2026-08-25
**DUT:** Vortex RISC-V GPGPU @ `7a52ee53` · **Environment:** `sim/uvmsim` @ `3bffd164`
**Reference model:** SimX (C++) over DPI-C · **Simulator:** QuestaSim 2021.2

> This supersedes the founding one-page `VERIFICATION_PLAN.md` as the working plan. The founding
> document's scope (8 named tests, 4 coverage targets, toggle >90% / line >95%) is preserved as the
> **minimum** sign-off bar in §5 — this plan adds the feature decomposition, per-feature scenarios,
> the coverage→test traceability the founding doc lacks, and an explicit waiver register.

---

## 1. Configuration under verification

| Parameter | Default | Swept? |
|---|---|---|
| `NUM_CLUSTERS` / `NUM_CORES` / `NUM_WARPS` / `NUM_THREADS` | 1 / 1 / 4 / 4 | Yes — regression selects one topology per run; multi-core covered by `multicore_isa` |
| ISA | RV32IMF + D + Zicond (`EXT_M/F/D/ZICOND_ENABLE` on by default) | No — RV64 path exists but is unexercised |
| Memory interface | AXI4 (`USE_AXI_WRAPPER`) | Yes — custom `mem` path is an alternate compile |
| Caches | icache + dcache on; L2/L3 configurable | Partially |
| `LMEM_ENABLE` | on | — |
| `EXT_TCU_ENABLE` | off | Enabled for `tcu_test` / `tcu_mt` only |

**Elaboration guard:** the testbench `$fatal`s at time 0 if any runtime topology plusarg disagrees
with the compiled RTL macros (`tb/vortex_tb_top.sv:826-937`). No run can silently use a mismatched
configuration.

---

## 2. Checking mechanisms (referenced by ID throughout)

| ID | Mechanism | Where |
|---|---|---|
| **C-END** | End-state equivalence vs SimX — memory (result window, byte-valid mask, poison gate, tolerance gate) + console | `vortex_scoreboard.svh` |
| **C-REV** | Reverse pass: result-scope dwords SimX wrote and the DUT did not → `DROPPED STORE` | `vortex_scoreboard.svh:791-823` |
| **C-LOCK** | Per-instruction lockstep vs SimX — PC, rd, per-lane data, per-(core,warp) program-order alignment | `lockstep_scoreboard.svh` |
| **C-SVA** | Concurrent assertions — 40 properties across AXI / mem / DCR / status / system | `tb/*_if.sv` |
| **C-SENT** | In-kernel self-check sentinel (`0x900DCAFE`) read back by the test | e.g. `warp_scheduling_test.svh:104-134` |
| **C-RAL** | DCR register model — explicit prediction, backdoor observation, per-instance completeness check | `ral/vortex_dcr_ral_pkg.sv` |
| **C-NEG** | Negative tests proving C-END and C-REV are capable of failing | `negative_result_test`, `negative_dropped_store_test` |

**Rule:** a feature is **DONE** only when it is checked by C-END/C-REV/C-LOCK/C-SVA/C-RAL.
A feature checked only by C-SENT is **IMPLEMENTED-UNVERIFIED** — the DUT graded its own homework.

---

## 3. Feature decomposition and traceability

Status: **DONE** · **PART** (partially covered) · **OPEN** (no coverage or no check) · **WAIVED** (with reason)

### 3.1 Warp scheduling and control flow

| # | Feature / scenario | RTL | Check | Coverage item | Test | Status |
|---|---|---|---|---|---|---|
| WS-1 | Warp issue, active/stalled warp occupancy | `VX_schedule.sv` | C-END | `sched_state_cg` — active, stalled, wid × occupancy | `warp_scheduling_test` | **DONE** |
| WS-2 | Branch divergence — split, thread-mask partition | `VX_split_join.sv` | C-END, C-LOCK | `divergence_cg` — uniform/divergent, then-occupancy | `warp_scheduling_test`, `diverge_*` kernels | **DONE** |
| WS-3 | Divergence nesting depth | `VX_ipdom_stack.sv` | C-END | `cp_split_depth` (0..stack max) | `diverge_*` | **DONE** |
| WS-4 | Reconvergence — join, then/else path | `VX_split_join.sv` | C-END | `reconverge_cg` — path, occupancy, depth | `diverge_*` | **DONE** |
| WS-5 | Local barrier — arrival, hold, release, participant count | `VX_wctl_unit.sv` | C-END, C-SENT | `barrier_cg` — id, size, event | `barrier_sync_test` | **DONE** |
| WS-6 | **Global (cross-core) barrier** | `VX_gbar_unit.sv` | — | `cp_bar_scope` global bin **waived unreachable** at 1 core | — | **OPEN** — W-3 |
| WS-7 | Thread-mask control (TMC) | `VX_wctl_unit.sv` | C-END | `tmc_cg` — deactivate / one / partial / full | `diverge_*` | **DONE** |
| WS-8 | Warp spawn (WSPAWN) | `VX_wctl_unit.sv` | — | `wspawn_cg` — spawn count | spawn kernels | **PART** — spawn kernels are scored **UNVERIFIABLE** by C-END (stack-resident args not staged to SimX); only C-LOCK can verify them |
| WS-9 | Predication (`pred`) | `VX_wctl_unit.sv` | C-END | `cp_sfu_op` pred bin | directed kernels | **PART** — no predicate-mask coverpoint |

### 3.2 Instruction execution

| # | Feature / scenario | RTL | Check | Coverage item | Test | Status |
|---|---|---|---|---|---|---|
| EX-1 | Integer ALU — add/sub/logic/shift/compare/lui/auipc | `VX_alu_int.sv` | C-END, C-LOCK | `cp_alu_op` (14 bins) | all | **PART** — bins corrupted, see EX-2/EX-3 and **D-1** |
| EX-2 | **Branch / jump — BEQ BNE BLT BGE BLTU BGEU JAL JALR; taken and not-taken** | `VX_alu_unit.sv` | C-END, C-LOCK (PC compared) | **none** | all | **OPEN** — no branch coverpoint; branch traffic mis-binned into arithmetic bins (**D-1**) |
| EX-3 | **M-extension — MUL MULH MULHSU MULHU DIV DIVU REM REMU** | `VX_alu_muldiv.sv` | C-END, C-LOCK | **none** | riscv-dv | **OPEN** — no coverpoint; mul/div traffic mis-binned (**D-1**). Divide-by-zero and signed-overflow corner cases unlisted. |
| EX-4 | Zicond — CZERO.EQZ / CZERO.NEZ | `VX_alu_int.sv` | C-END | `cp_alu_op` czeq/czne | — | **OPEN** — bins exist, never hit |
| EX-5 | FPU op classes — fadd fmul fmadd fnmadd fdiv fsqrt cvt cmp misc | cvfpu | C-END, C-LOCK | `cp_fpu_op` (13 bins) | `fpu_*` kernels | **DONE** |
| EX-6 | **FP rounding modes** (`frm`) | cvfpu | C-END | **none** — `fpu_args_t.frm` is in the sampled payload, not sampled | — | **OPEN** |
| EX-7 | **FP format — single vs double** (`EXT_D_ENABLE` is on) | cvfpu | C-END | **none** — `fpu_args_t.fmt` not sampled | — | **OPEN** |
| EX-8 | **FP special values — NaN, ±Inf, denormal, ±zero; NaN-boxing** | cvfpu | C-LOCK reconciles NaN-boxing | **none** | — | **OPEN** |
| EX-9 | CSR access — CSRRW/S/C | `VX_csr_unit.sv` | C-END | `cp_sfu_op` 3 bins | riscv-dv | **PART** — no CSR-**address** coverpoint (`csr_args_t.addr` unsampled); immediate variants unlisted |
| EX-10 | Performance-counter CSRs | `VX_csr_data.sv` | — | — | — | **WAIVED** — W-1 (model-divergent by construction; excluded from C-LOCK data compare) |
| EX-11 | Tensor core (WMMA) | `VX_tcu_unit` (ifdef) | C-END | `tcu_class_cg` — thread mask only | `tcu_test`, `tcu_mt` | **PART** — no operand-shape / precision coverage (`tcu_args_t` unsampled); covergroup compiled out by default |
| EX-12 | Operand collector, GPR bank conflicts (`NUM_GPR_BANKS=4`) | `VX_opc_unit.sv`, `VX_operands.sv` | C-END | **none** | — | **OPEN** |
| EX-13 | Register hazards — RAW / WAW / WAR | `VX_scoreboard.sv` (RTL) | C-END, C-LOCK | **none** | riscv-dv | **OPEN** |
| EX-14 | Micro-op sequencing / SIMD beat splitting | `VX_uop_sequencer.sv` | C-LOCK (beat aggregation) | **none** | — | **PART** |

### 3.3 Memory system

| # | Feature / scenario | RTL | Check | Coverage item | Test | Status |
|---|---|---|---|---|---|---|
| MEM-1 | Load / store — byte, half, word | `VX_lsu_slice.sv` | C-END, C-REV, C-LOCK | `cp_lsu_op` (6 bins) | `functional_memory_test` | **DONE** |
| MEM-2 | **Unaligned access** | `VX_lsu_adapter.sv` | C-END | `cp_addr_align` exists **only in the custom-mem covergroup**, which is not built on the default AXI config | — | **OPEN** — **D-2** |
| MEM-3 | Float load / store (FLW/FSW) | `VX_lsu_slice.sv` | C-END | **none** — `lsu_args_t.is_float` unsampled | `fpu_*` | **OPEN** |
| MEM-4 | **Local memory / shared scratchpad** (`LMEM_ENABLE` on) | `VX_local_mem.sv`, `VX_lmem_switch.sv` | C-END | **none** | `lmem_stress` | **OPEN** — runs, no coverage |
| MEM-5 | LMEM bank conflicts | `VX_local_mem.sv` | — | **none** | — | **OPEN** |
| MEM-6 | Cache hit / miss | `VX_cache_bank.sv` | C-END | `cache_event_cg` — hit, miss, rw, replay | `cache_tier`, `mem_pressure` | **DONE** |
| MEM-7 | Fill / writeback / flush events | `VX_cache_bank.sv`, `VX_cache_flush.sv` | C-END | `cp_event` (writeback/flush bins waived per config) | — | **PART** |
| MEM-8 | MSHR — stall behaviour | `VX_cache_mshr.sv` | C-END | `cp_mshr_stall` — **binary only** | `mshr_flood` | **PART** — no occupancy histogram |
| MEM-9 | Cache set / way / bank distribution, replacement policy | `VX_cache_repl.sv`, `VX_cache_tags.sv` | — | **none** | — | **OPEN** |
| MEM-10 | Cache bypass path | `VX_cache_bypass.sv` | C-END | **none** | — | **OPEN** |
| MEM-11 | L2 / L3 tiers | `VX_cache_cluster.sv` | C-END | config-keyed exclusions when disabled | `cache_tier` | **PART** |
| MEM-12 | Memory arbitration / switching across cores | `VX_mem_arb.sv`, `VX_mem_switch.sv` | C-END | **none** | `multicore_isa` | **OPEN** |
| MEM-13 | Dropped-store detection | — | **C-REV** | — | `negative_dropped_store_test` | **DONE** — but C-REV is gated to the AXI path; the custom-mem path has no equivalent |
| MEM-14 | Atomics (A-extension) | — | — | — | — | **WAIVED** — W-2 (`EXT_A_ENABLE` not set in the verified config) |

### 3.4 Bus, configuration and system

| # | Feature / scenario | RTL | Check | Coverage item | Test | Status |
|---|---|---|---|---|---|---|
| BUS-1 | AXI4 channel handshake and stability, all 5 channels | `VX_axi_adapter.sv` | **C-SVA** (30 properties) | 16 SVA covers + `axi_transaction_cg` | `axi_memory_test` | **DONE** |
| BUS-2 | AXI burst legality, 4 KB boundary, ID stability, reset behaviour | " | C-SVA groups A/D/E | " | " | **DONE** |
| BUS-3 | AXI outstanding-transaction discipline | " | C-SVA group C (scoreboards) | **no depth coverpoint** — counters feed assertions only | " | **PART** |
| BUS-4 | AXI backpressure — throttle and flood | " | C-END, C-SVA | — | suite `+AXI_THROTTLE` / `+AXI_FLOOD` variants | **DONE** |
| BUS-5 | AXI error responses (SLVERR / DECERR) | " | — | `ignore_bins` | — | **WAIVED** — W-4 (no error-injection sequence; TB slave never errors) |
| BUS-6 | Custom memory interface (valid/ready) | `Vortex.sv` | C-END, C-SVA (4 properties, **port 0 only**) | `mem_operation_cg` | `functional_memory_test` (mem build) | **PART** |
| BUS-7 | DCR configuration writes — startup address, argv, MPM class | `VX_dcr_data.sv` | **C-RAL** + C-SVA | `dcr_config_cg`, `dcr_write_cg` | all | **DONE** |
| BUS-8 | Kernel launch / completion handshake | host path | C-END | `host_operation_cg` | `kernel_launch_test`, `host_coverage_test` | **DONE** |
| BUS-9 | Busy / idle / EBREAK termination | `Vortex.sv` | C-END, C-SVA | `status_performance_cg`, `system_cg` | all | **DONE** |
| BUS-10 | Pipeline stall profile and IPC | probes | — | `cp_*_stall`, `cp_ipc_bucket` | all | **DONE** (observability, not a check) |

### 3.5 Multi-core / multi-cluster

| # | Feature / scenario | Check | Coverage item | Test | Status |
|---|---|---|---|---|---|
| MC-1 | Multi-core execution of the same kernel | C-END | config-provenance coverpoints only | `multicore_isa` | **PART** |
| MC-2 | **Cross-core functional interaction** (shared memory, arbitration, barrier) | C-END | **none** — `cp_num_cores` is provenance, not behaviour | — | **OPEN** |
| MC-3 | Multi-cluster topology | C-END | — | 2-cluster lockstep sweep | **PART** |
| MC-4 | Per-core DCR probe completeness | **C-RAL** (`expected_instances = NUM_CLUSTERS*NUM_CORES`) | — | all | **DONE** |

### 3.6 Exceptions and error behaviour

| # | Feature / scenario | Check | Coverage item | Test | Status |
|---|---|---|---|---|---|
| EXC-1 | EBREAK termination | C-END | `cp_ebreak` (binary) | all | **DONE** |
| EXC-2 | **Trap cause classification** — illegal instruction, misaligned fetch/load/store | — | **none** | — | **OPEN** — founding-plan target, no coverpoint exists |
| EXC-3 | Machine-mode traps, `mret`, debug mode | — | — | riscv-dv profiles excluded | **WAIVED** — W-5 (architecturally inapplicable to Vortex; exclusion list is documented in `run_suite.sh:297-349`) |

---

## 4. Defects found in the verification environment itself

| ID | Defect | Impact | Fix |
|---|---|---|---|
| **D-1** | `cp_alu_op` samples `op_type` without its class selector `op_args.alu.xtype`. The ALU unit carries ARITH, BRANCH and MULDIV in one reused `op_type` namespace (`VX_decode.sv:182-183`, `VX_gpu_pkg.sv:502`). `BEQ` and `MUL` both score as `add`; `JAL` scores as `srl`. No `default` bin, so nothing shows as uncovered. | Branch and M-extension have no coverage, **and** the arithmetic bins are falsely inflated. | Add `xtype` to `sample()`; split into `cp_alu_arith` / `cp_alu_branch` / `cp_alu_muldiv` with `iff` guards and `bins other[] = default`. ~40 lines. |
| **D-2** | `cp_addr_align` lives in `mem_operation_cg`, constructed only when `USE_AXI_WRAPPER=0` (`vortex_coverage_collector.svh:734`). The default configuration is AXI. | Unaligned-access coverage never samples on the configuration actually regressed. | Add an alignment coverpoint to `axi_transaction_cg`, or move it to the LSU probe where it is interface-independent. |
| **D-3** | `vortex_sanity_test` overrides `wait_for_completion()` to return immediately and sets `test_passed = 1` unconditionally. | Cannot fail. Must never be counted in a pass tally. | Keep as an elaboration smoke check; exclude from result counts and label it as such. |
| **D-4** | `random_instruction_stress_test` has no non-vacuity gate, unlike `kernel_launch_test`. | A random program with no memory or console output could pass having compared nothing. | Copy the gate from `kernel_launch_test.svh:237-263`. ~10 lines. |
| **D-5** | `axi_driver` and `mem_driver` never call `seq_item_port.get_next_item()`. Their sequence libraries (7 AXI sequences, `vortex_axi_mem_vseq`) have no consumer and would deadlock if wired in. | Dead code and a latent hang. | Delete them, or implement a sequence-driven mode. |
| **D-6** | `ref_model/Makefile:83` appends `-DXLEN_32` unconditionally after the `ifeq ($(XLEN),64)` block; `simx_init()` validates cores/warps/threads but not XLEN. | An RV64 build compiles with both macros defined and the mismatch is not detected at init. | Delete line 83; add an XLEN check to `simx_init()`. |
| **D-7** | `scripts/gen_coverage_exclude.sh:42-43` hardcodes developer-absolute paths. | Exclusion generation silently misbehaves on any other checkout. | Derive from `VORTEX_HOME` / script directory. |
| **D-8** | `lockstep_pkg.sv:59-63` declares a `+LOCKSTEP_INJECT` negative-test hook that `lockstep_scoreboard.svh` never references. | C-LOCK has no proven non-vacuity, unlike C-END and C-REV. | Close the loop or drop the claim. |

---

## 5. Sign-off criteria

**Inherited from the founding plan (minimum bar):**

| Founding target | Current status |
|---|---|
| Instruction opcodes — 100% | **FAIL** — EX-2, EX-3 open; D-1 corrupts EX-1 |
| Warp scheduling states — all covered | **PASS** — WS-1…WS-5, WS-7, WS-8 |
| Memory access patterns — aligned / unaligned / contention | **FAIL** — MEM-2 dead on the default config (D-2); no contention coverpoint |
| Exception / interrupt types — all covered | **FAIL** — EXC-2 open |
| Toggle > 90% / line > 95% | **Not measured in-repo** — merged UCDB lives outside the tree |

**Added by this plan:**

1. Every **DONE** feature is checked by a mechanism other than C-SENT.
2. Every **WAIVED** item appears in §6 with a cited reason.
3. C-END and C-REV are proven non-vacuous by C-NEG on every regression; C-LOCK likewise once D-8 is closed.
4. C-LOCK runs in the standard regression, not only in a manual sweep.
5. No run reaches PASS with `num_comparisons == 0` (VACUOUS RUN gate active).
6. The UCDB merge passes the hits-invariant gate — no exclusion moved the numerator.
7. UNVERIFIABLE runs are counted and budgeted, not merely reported.

---

## 6. Waiver register

| ID | Waived | Reason | Evidence |
|---|---|---|---|
| **W-1** | Performance-counter CSR values excluded from lockstep data compare | Model-divergent by construction; cycle counts cannot match a functional model | `lockstep_scoreboard.svh:612-613` |
| **W-2** | Atomics (A-extension) | `EXT_A_ENABLE` not set in the verified configuration | `hw/rtl/VX_config.vh:867` |
| **W-3** | Global (cross-core) barrier | Structurally unreachable at 1 cluster / 1 core | `vx_sched_probe.sv` `cp_bar_scope` ignore_bins |
| **W-4** | AXI SLVERR / DECERR responses | The testbench slave never errors; no error-injection sequence exists | `vortex_coverage_collector.svh` bresp/rresp ignore_bins |
| **W-5** | Privileged-CSR, debug-mode and illegal-trap riscv-dv profiles | Architecturally inapplicable to Vortex | `scripts/run_suite.sh:297-349` |
| **W-6** | AXI INCR/WRAP bursts, non-native sizes, multi-beat lengths | The Vortex AXI adapter issues single-beat FIXED native-size transfers only | ignore_bins cited against `VX_axi_adapter.sv:263-264, 298-299` |
| **W-7** | Third-party IP (cvfpu, Berkeley HardFloat inside the TCU) | Not the DUT under verification | `gen_coverage_exclude.sh` category EOTH |
| **W-8** | icache write-data toggle and flush FSM | icache is read-only in this configuration; flush path proven unenterable | `gen_coverage_exclude.sh:190-198, 270-294` |
| **W-9** | Spawn-runtime kernels under C-END | Stack-resident spawn arguments are not staged to SimX; end-state equivalence is undefined. Verifiable only under C-LOCK. | `vortex_scoreboard.svh:90-106` |

---

## 7. Closure roadmap

| Priority | Item | Features closed | Effort |
|---|---|---|---|
| P0 | Fix D-1 (class-qualified ALU coverage) | EX-1, EX-2, EX-3 partially | ~0.5 d |
| P0 | Fix D-2 (alignment on the AXI path) | MEM-2 | ~0.5 d |
| P0 | Fold C-LOCK into the standard regression | Raises every C-LOCK-checked row from claim to evidence | ~0.5 d |
| P1 | Sample the remaining `op_args` fields — `fpu.frm`, `fpu.fmt`, `lsu.is_float/offset`, `csr.addr`, `tcu.*` | EX-6, EX-7, EX-9, EX-11, MEM-3 | ~1 d |
| P1 | Add branch-direction and M-op coverpoints; add trap-cause coverage | EX-2, EX-3, EXC-2 | ~1 d |
| P1 | Fix D-4, D-6, D-7; resolve D-5; close D-8 | Environment integrity | ~1 d |
| P2 | LMEM coverage — access pattern and bank conflict | MEM-4, MEM-5 | ~1 d |
| P2 | MSHR occupancy histogram; cache set/way/bank distribution | MEM-8, MEM-9 | ~1 d |
| P2 | FP special-value coverage (NaN / Inf / denormal / zero) | EX-8 | ~1 d |
| P3 | Cross-core functional coverage; operand-collector bank conflicts; register-hazard coverage | MC-2, EX-12, EX-13 | ~2 d |

---

## 8. Open questions

- Merged UCDB code / functional / assertion percentages — not in the repo; must be pulled from the
  coverage bank with `vcover report -summary`.
- ISS-12 (status monitor poll may miss EBREAK) and ISS-13 (host monitor completion count) are marked
  open in the March bring-up report. ISS-13 is inferably fixed — `kernel_launch_test` hard-gates on
  the completion count and passes — but neither monitor has been re-read. **Verify before claiming.**
- Whether `negative_result_test` asserts on `fault_detected` specifically, or relies on the resulting
  error count. The former is the stronger claim.
- Reconciliation with the outer repo's `Vortex_UVM_Plan_Current.md` and the `CLAUDE.md` ownership
  lanes ([S] / [A] / [St]) — pending access to that repo.
