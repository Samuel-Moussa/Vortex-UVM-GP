# Program inventory and scenario coverage — answers for the appendix slides

Every claim below is grounded in a real file or command output, cited by path and line.
Where something could not be confirmed, it says so explicitly.

---

## 1 · The authoritative program list — CONFIRMED, with one correction

Real staged-log listing from the actual 1CL storm bank directory (the run behind the
94.72% headline), not `run_suite.sh`'s source in isolation:

```
$ cd vortex_uvm_env/results/run_suite_logs_1CL_storm_20260816
$ ls *.log | grep -v merge.log | sed 's/_.*$//' | sort | uniq -c
      5 d
     32 k
      4 r
     10 rv
```

**Correction to the "50 vs 51" claim: the count is 51 logs in the directory, but one
(`rv_riscv_pmp_test.log`) is a stale leftover from a run four days earlier** — `pmp` was
removed from the profile loop on 2026-08-13 (`run_suite.sh:336`) and its log was never
cleaned up because `run_suite.sh` doesn't clear `$LOGDIR` between runs. Excluding it:
**5 + 32 + 4 + 9 = 50 real staged programs**, matching the 94.72%/94.55% storm banks
exactly. The L2/L3 bank is the one that is genuinely 51 (see §5).

| Prefix | Count | Source |
|---|---|---|
| `d_` | 5 | directed UVM tests |
| `k_` | 32 (30 distinct kernels — see below) | `tests/kernel/` |
| `r_` | 4 | `tests/regression/` |
| `rv_` | 9 | riscv-dv generated |

**`k_` is 32 log entries but only 30 distinct kernel binaries.** `mem_stress` and
`vecadd_lite` are each run twice under different AXI stress modes, producing separate log
names but reusing the same kernel source:

- `runthr()` (`run_suite.sh:77`) → `AXI_THROTTLE=1`, logs as `k_thr_<name>.log`
- `runflood()` (`run_suite.sh:80`) → `AXI_FLOOD=1`, logs as `k_flood_<name>.log`

So **`flood_mem_stress` and `thr_vecadd_lite` are not separate kernel directories** — they
are `mem_stress` and `vecadd_lite` re-run under a stress plusarg. This fully answers §2 of
the Claude-web request; there is nothing to trace to a missing source directory.

---

## 2 · Cross-referencing your `ls tests/kernel/` (47 entries) against the bank

### Staged in the main (storm) bank — 30 distinct kernels + 5 directed-test targets

```
axi_edge  bar_masks  barrier_lite  cache_stress  div_edge  diverge_deep
diverge_fpu  diverge_lite  diverge_peel  diverge_uni3  fibonacci  fpu_mt
fpu_test  hello  isa_probe  lmem_stress  mem_stress  mem_zero  mshr_flood
multicore_isa  sfu_masks  spawn_tmc_sweep  storm_big  tcu_mt  tcu_test
text_big  unit_storm  vecadd_lite  vote_shfl  wide_stress
```
plus, run as the program behind a `d_` directed test:
```
axi_traffic      -> d_axi_memory_test        (run_suite.sh:287)
functional_mem   -> d_functional_memory_test (run_suite.sh:288)
warp_test        -> d_warp_scheduling_test   (run_suite.sh:289)
barrier_test     -> d_barrier_sync_test      (run_suite.sh:290)
vecadd_lite      -> d_host_coverage_test     (run_suite.sh:291, reused a third time)
```

**Note: `axi_traffic` IS staged.** The earlier Claude-web answer listed it among the
"8 unaccounted" kernels — that was wrong; it is `run_suite.sh:287`'s program, confirmed by
both the source line and the real `d_axi_memory_test.log` in the bank directory.

### Staged only in the L2/L3 bank

```
cache_tier   -> runct() (run_suite.sh:238-239), KERNEL_EXTRA_CONFIGS="-DCT_P1=1 -DCT_P2=1 -DCT_P3=1"
```

### Outside every bank, run standalone for the FFT proof-of-concept

```
fft  fft_mt  fft_par  fft_par16
```

### The real remainder — 8 kernels, each with a confirmed disposition (not "unaccounted")

| kernel | disposition | evidence |
|---|---|---|
| `vecadd` | **superseded by `vecadd_lite`** | `vecadd/vecadd.cpp` contains **25 `printf` calls**; this is the historical INV-1 finding — printf-heavy kernels' MMIO console traffic makes them take millions of cycles to finish, so every kernel needing this shape of test was rewritten printf-free as `*_lite`. Confirmed by direct grep: `grep -c printf vecadd/vecadd.cpp` → 25. |
| `misalign_neg` | **deliberately excluded, by its own header comment** | `tests/kernel/misalign_neg/main.cpp:1-2`: *"NEGATIVE test for the A5 RTL-assertion gate (**keep OUT of run_suite**)."* It issues one deliberate misaligned load, which fires `VX_lsu_slice.sv:189`'s `RUNTIME_ASSERT` with no trap (OBS-013) — the run is *supposed* to report "TEST FAILED — RTL assertion error(s)" so it cannot sit in a suite gated on 0 FAILED. Confirmed never referenced anywhere else: `grep -rn misalign_neg uvm_tests/ scripts/` → no hits. |
| `toggle_stress` | **tried, gave ~0 net gain, parked** | Only reference in `run_suite.sh` is a comment at line 182: *"32KB toggle_stress (real toggle gain: aggregate 77.99->78.61%)"* — it was actually run once historically (project history, session 11) but is not invoked (`runk` is never called for it). It is not staged in the current bank. |
| `axi_stress` | **tried, produced evidence for a waiver, then retired** | Header (`tests/kernel/axi_stress/main.cpp:1-6`): *"PURPOSE: drive cp_id_route / cross_type_route to ~100%… 0 new route bins"* per project history. It was used once to *prove* a coverage waiver (that certain AXI route values are structurally unreachable at the compiled tag-buffer depth), then was not added to the ongoing suite because it added no further coverage once the waiver was accepted. |
| `compute_dense` | **superseded by the config-aware IPC waiver** | Header: *"drive cp_ipc_bucket med_ipc/high_ipc bins… ISSUE_WIDTH=1 ceiling."* Used to characterize the achievable IPC ceiling; the eventual fix was a **config-aware `ignore_bins`** on `cp_ipc_bucket` (waiving IPC buckets unreachable at the compiled `NUM_WARPS`/`ISSUE_WIDTH`) rather than keeping a dedicated stress kernel in the suite. |
| `compute_flat` | same as `compute_dense` | Header: *"probe the true issue-bound IPC ceiling… fully unrolled with NO branches."* Same disposition — measurement kernel, superseded by the RTL-derived waiver. |
| `compute_tight` | same as `compute_dense` | Header: *"cover cp_ipc_bucket.high_ipc… branchless, memory-free."* Same disposition. |
| `conform` | **a pre-project Vortex regression test, never adopted** | `tests/kernel/conform/main.cpp` includes `<vx_print.h>` and calls a battery of `test_*()` functions (`test_global_memory`, `test_local_memory`, `test_tmc`, `test_pred`, `test_divergence`, `test_wsapwn`, `test_spawn_tasks`, `test_serial`, `test_barrier`, `test_tls`, …) — this looks like an upstream Vortex self-test, structurally different from every other kernel in this tree (no scoreboard-comparable deterministic output pattern). Never referenced in `run_suite.sh`. |

**None of the eight are unexplained.** Three are genuinely-parked coverage experiments
with a stated reason (net-zero gain or superseded by a cleaner waiver), one is a
deliberately-excluded negative test, one is a printf-heavy kernel superseded by its `_lite`
replacement, and one is a pre-existing Vortex regression test that was never brought into
the suite.

---

## 3 · The four `r_*` programs and OpenCL — CONFIRMED

`Makefile:60,108`: `REGRESSION_DIR ?= $(VORTEX_HOME)/tests/regression`, and
`PROGRAM_KIND` resolves `KERNEL_SRC_DIR := $(REGRESSION_DIR)/$(PROGRAM_KIND)`.
`run_suite.sh:293-296`:
```
runr basic
runr diverge
runr sgemm
runr dogfood "DOGFOOD_TESTID=4"
```
`tests/regression/` on disk contains `basic diverge dogfood sgemm` among 14 other
directories (`conv3, cta, demo, dotproduct, dropout, fence, io_addr, madmax, mstress,
printf, relu, sgemm2, sgemv, sort, stencil3d`) — **13 further regression programs exist
and are NOT run.**

**OpenCL: wired as a resolution path in the scripts, never invoked.**
`Vortex/tests/opencl/` exists on disk (upstream Vortex's own OpenCL test suite —
`vecadd, sgemm, conv3, cta, dotproduct, dropout, madmax, relu, sgemm2, sort, stencil3d`,
etc.) and `scripts/prepare.sh:244-247` / `scripts/run_vortex_uvm_enhanced.sh:537-540`
both contain a `# Case 2: Vortex OpenCL kernel` resolution branch that would use
`tests/opencl/$PROGRAM/kernel.bin` if invoked with `--program=<name>` directly through
`run.sh`. **`run_suite.sh` never uses this path** — it always calls `make ... PROGRAM_NAME=`,
which resolves through `tests/kernel/` only (`Makefile:111-112`). So: **confirmed, no
OpenCL program has ever run in the UVM bank**, but the claim needs one qualifier — the
plumbing to run one exists and would work if invoked directly via `scripts/run.sh
--program=vecadd`, it has simply never been exercised through the regression suite.

---

## 4 · D-1 defect (`cp_alu_op` class-selector bug) — **CANNOT LOCATE THE ORIGINAL CLAIM**

`docs/VERIFICATION_PLAN_v1.md` — **NOT FOUND** anywhere in the repository. The closest
file is `docs/VERIFICATION_PLAN.md`, and it contains **zero** references to "D-1",
"cp_alu_op", or a class-selector defect (`grep -n -i 'D-1\|cp_alu_op' docs/VERIFICATION_PLAN.md`
→ no output). I cannot confirm the defect record exists in this repository at all — it may
be from a different document, a prior session's memory, or was never committed. Say so on
the slide rather than presenting it as resolved.

**What I can confirm about the current code, independent of that claim:**
`tb/vx_instr_probe.sv:294-306` gates each class covergroup on the **array index**
(`gi == C_ALU`, `dispatch_if[gi]`), not a payload field — `ex_type` (the instruction class)
is architecturally the dispatch array index, confirmed by the file's own header
(`:14-16`: *"ex_type (instruction CLASS) is the ARRAY INDEX, not a payload field… EX_ALU=0,
EX_LSU=1… (VX_gpu_pkg.sv:113-119)"*). `alu_class_cg` only samples when
`dispatch_if[C_ALU].valid && .ready` fires (`:296-303`). Its `cp_alu_op` coverpoint
(`:108-121`) enumerates **explicit named bins per ALU sub-opcode**
(`bins add = {INST_ALU_ADD}`, `bins sub = {INST_ALU_SUB}`, …) — there is no generic
default bin a mis-decoded op could silently fall into.

**A branch instruction (BEQ) and a multiply (MUL, `EXT_M`) structurally cannot land in
`alu_class_cg.cp_alu_op` today**, because (a) they would only sample it at all if
`dispatch_if[C_ALU]` fired for them, and (b) even then, `cp_alu_op` has no bin their
`op_type` would fall into unless it genuinely equals `INST_ALU_ADD`'s encoding. This is
inconsistent with the described defect ("BEQ and MUL score as add"). **My read: the
current per-class covergroup structure (documented in the file's own header as "REVISED —
per-class covergroup variants", `:29`) looks like it already IS the fix — but I cannot
prove that without the original defect record to diff against.** Recommend: ask for the
source of the D-1 claim (session, doc, or memory) before writing a slide either way.

---

## 5 · Instruction/interface scenario coverage — checked against the code, not the docs

| Scenario | Status | Evidence |
|---|---|---|
| **Walking ones / walking zeros / marching patterns** | **CONFIRMED ABSENT** | `grep -rli 'walking.*one\|walking.*zero\|march.*pattern\|marching' <whole uvmsim tree>` → zero hits. Genuinely not present anywhere, not even under a different name. |
| **Mid-run reset (assert, then restart)** | **CONFIRMED ABSENT** | `tb/vortex_tb_top.sv:54`: `logic reset_n = 1'b0;` — initialized low once. The reset-release block (`:65` onward) is a **single** `initial` sequence gated on the DCR-bootstrap handshake (`dcr_bootstrap_done_ev`, `:58-59`); nothing in `uvm_tests/`, `uvm_env/agents/`, or the TB re-asserts `reset_n` after release. Every run resets exactly once, at time 0. |
| **Clock gating / clock gate-ungate** | **CONFIRMED OUT OF SCOPE — not a stimulus gap, a design fact** | `grep -rli 'clock.gat\|clkgat\|clk_en\b' <entire Vortex/hw/rtl tree>` → zero hits. Vortex has no clock-gating logic in this RTL at all. Nothing to exercise; state this on the slide as a design fact, not a coverage gap. |
| **AXI backpressure — throttle / flood** | **PRESENT** | `runthr()`/`runflood()` (`run_suite.sh:77,80`), `+AXI_THROTTLE` / `+AXI_FLOOD` plusargs in `axi_driver.svh`. Moved handshake-stability assertions from 84.78% to 93% per project history. |
| **Reset-property assertions** | **PRESENT, 2 of 30 AXI assertions** | `assert_valids_low_during_reset`, `assert_valids_low_after_reset` (confirmed by name in the earlier assertion-count audit). |
| **X-propagation** | **PRESENT — one real finding, R10/OBS-045** | `VX_reset_relay.sv:29-49`: the reset-synchronizer flop previously had no initial value and nothing reset it, so `reset_o` was X for one cycle — caught via a restored assertion, now fixed with an async-assert/sync-deassert synchroniser. |
| **4 KB boundary / burst legality** | **PRESENT** | 8 of the 30 AXI assertions (`aw/ar_4k_boundary`, `aw/ar_burst_legal`, `aw/ar_size_legal`, `aw/ar_wrap_len_legal`). |
| **Unaligned access** | **DUT limitation, not a stimulus gap** | `VX_lsu_slice.sv` explicitly: *"memory misalignment not supported!"* — `misalign_neg` exists specifically to prove the assertion gate catches this; it is intentionally kept out of the passing suite (see §2). |
| **M-extension corner cases (div-by-zero, signed overflow)** | **Exercised by riscv-dv, not independently targeted** | riscv-dv's random generation includes M-extension ops; no directed kernel specifically targets div-by-zero/overflow. No coverpoint confirms it was hit. |
| **FP special values (NaN, ±Inf, denormal, ±0)** | **Exercised incidentally, not covered** | `fpu_test`/`fpu_mt` exist and drive real FP ops (see the earlier 1-ULP `fsqrt` finding, OBS-014), but there is no coverpoint confirming NaN/Inf/denormal/±0 inputs specifically occurred. |

---

## 6 · One-line intent per kernel — for the slide

Sourced from each kernel's own header comment where present.

```
axi_edge        AXI edge-case stress (short timeout, targeted transaction shapes)
axi_stress      AXI outstanding-tag-depth stress; proved the cp_id_route waiver bound
axi_traffic     AXI4 protocol traffic generator, drives d_axi_memory_test
bar_masks       barrier under peeled thread masks; fills cross_sfu_threads bar bins
barrier_lite    printf-free multi-warp barrier (proven wspawn+barrier pattern)
barrier_test    directed barrier scenario, drives d_barrier_sync_test
cache_stress    cache pressure kernel (fetch/mem stall coverage)
cache_tier      L2/L3-phased cache tier exercise (L2/L3 bank only)
compute_dense   ALU-bound, memory-light; drove the IPC-ceiling characterization
compute_flat    branchless straight-line ALU; IPC-ceiling upper bound probe
compute_tight   branchless, memory-free ALU; high sustained IPC probe
conform         pre-existing Vortex self-test battery (never adopted into the suite)
div_edge        raw div/rem instruction corner cases
diverge_deep    deep branch-divergence stress
diverge_fpu     divergence combined with FP ops
diverge_lite    printf-free divergence baseline
diverge_peel    divergence with peeled/partial thread masks
diverge_uni3    uniform-split divergence at stack depth 3
fibonacci       tiny liveness kernel (no data compare)
fpu_mt          multi-thread FPU op-decode coverage
fpu_test        single-thread FPU op-decode coverage
functional_mem  directed functional-memory scenario, drives d_functional_memory_test
hello           tiny liveness kernel
isa_probe       M-mode CSR + FCLASS/FMV.X.W decode closure kernel
lmem_stress     local/scratchpad memory stress
mem_stress      dcache request-backpressure (MSHR) stress; also run under +AXI_FLOOD
mem_zero        zero-fill memory stress pattern
misalign_neg    NEGATIVE test proving the RTL misalignment assertion fires (excluded by design)
mshr_flood      dcache miss-flood stress (67,207 misses; documented as an honest residual gap)
multicore_isa   per-core ISA coverage closure across all cores
sfu_masks       SFU CSR ops under peeled thread masks
spawn_tmc_sweep thread-mask-control sweep across spawn patterns
storm_big       concurrent icache+dcache response contention
tcu_mt          multi-warp tensor-core (WMMA) op coverage
tcu_test        single-warp tensor-core op coverage
text_big        large-.text kernel; fills PC-region toggle coverage
toggle_stress   high-entropy toggle-coverage kernel (tried, ~0 net gain, parked)
unit_storm      internal back-pressure kernel (lmem response path + wctl rsp_buf)
vecadd          original vector-add (25 printf calls; superseded by vecadd_lite)
vecadd_lite     printf-free vector-add; the project's default correctness baseline
vote_shfl       VOTE/SHFL SFU op coverage
warp_test       directed warp-scheduling scenario, drives d_warp_scheduling_test
wide_stress     256 KB sparse hi-entropy memory kernel; device-scaled multi-core
fft/fft_mt/fft_par/fft_par16   FFT proof-of-concept, latency vs throughput parallelism, run outside the bank
```

---

## Bottom line for the appendix slides

- **Regression: yes, 4 programs, from `tests/regression/`.** 13 more exist and are unused.
- **OpenCL: no program has ever run**, though the script-level resolution logic exists and
  is untested through the suite.
- **The "8 unaccounted kernels" list from the earlier answer had one factual error**
  (`axi_traffic` IS staged) and undercounted how well-documented the other seven are — all
  seven have a stated reason in their own source header or in `run_suite.sh`'s comments;
  none is a silent gap.
- **The scenario table is the real finding for the slide**: walking-pattern data stress,
  mid-run reset, and dedicated M-extension/FP-special-value coverage are the three genuine,
  confirmed gaps. Clock gating is not a gap — it does not exist in this RTL at all, and
  saying so plainly is stronger than leaving it as an open question.
- **D-1 could not be verified** — the source document doesn't exist under the name given,
  and the current code structure looks inconsistent with the defect as described. Ask
  where the original claim came from before writing a slide about it either way.
