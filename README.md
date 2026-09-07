<div align="center">

# A Standard, Reusable, Fully-Configurable UVM Framework for RISC-V–Based GPUs

**Built on the [Vortex](https://github.com/vortexgpgpu/vortex) open-source RISC-V GPGPU as its reference DUT —**
**checked by per-instruction lockstep and end-state equivalence against the SimX C++ golden model over DPI-C,**
**and extended with an original SIMT-aware stimulus and coverage layer this project designed and adopted on top of the standard RISC-V verification stack.**

[![Methodology](https://img.shields.io/badge/Methodology-UVM%201.2-1f6feb?style=flat-square)](https://www.accellera.org/downloads/standards/uvm)
[![SystemVerilog](https://img.shields.io/badge/SystemVerilog-IEEE%201800-e36209?style=flat-square)](https://ieeexplore.ieee.org/document/8299595)
[![ISA](https://img.shields.io/badge/ISA-RISC--V%20RV32IMAF-283272?style=flat-square&logo=riscv&logoColor=white)](https://riscv.org/)
[![Simulator](https://img.shields.io/badge/Simulator-QuestaSim%202021.2-2da44e?style=flat-square)](https://eda.sw.siemens.com/en-US/ic/questa/)
[![Golden Model](https://img.shields.io/badge/Golden%20Model-SimX%20·%20DPI--C-8957e5?style=flat-square)](https://github.com/vortexgpgpu/vortex)
[![Config](https://img.shields.io/badge/Config-Clusters·Cores·Warps·Threads-2da44e?style=flat-square)](#-configurability)
[![SIMT Generator](https://img.shields.io/badge/simtgen-SIMT--aware%20random%20stimulus-8957e5?style=flat-square)](#-simtgen--closing-the-simt-stimulus-gap)
[![Coverage](https://img.shields.io/badge/Covergroup%20Bins-98.1%25-2da44e?style=flat-square)](#-results)
[![Total](https://img.shields.io/badge/Total%20Coverage-94.7%25-2da44e?style=flat-square)](#-results)
[![RTL/TB findings](https://img.shields.io/badge/Findings%20Logged-60%2B-c9510c?style=flat-square)](#-findings)

[Why this exists](#-why-this-exists--the-gap) ·
[Quick Start](#-quick-start) ·
[Architecture](#-architecture) ·
[simtgen](#-simtgen--closing-the-simt-stimulus-gap) ·
[Results](#-results) ·
[Configurability](#-configurability) ·
[Docs](#-documentation-map)

</div>

---

## 🎯 Why this exists — the gap

The RISC-V verification ecosystem is mature and industry-standard, and this project is built **on top of it, not instead of it**. We directly adopt:

| Standard component | Adopted as |
| :--- | :--- |
| **Accellera UVM 1.2** (IEEE 1800.2) | the base class library our agent/driver/monitor/scoreboard architecture is written to — **not** OpenHW Group's own testbench/environment, which is CPU-scoped and not reused here |
| **RVVI** (RISC-V Verification Interface) | the reference concept for instruction-retirement lockstep against a golden model — realized here via SimX co-simulation, since RVVI itself has no notion of a warp or a thread mask to lock against |
| **Google riscv-dv**, via OpenHW Group's `core-v-verif` packaging | the constrained-random **base-ISA** stimulus generator our SIMT kernels ride on top of — the *only* piece taken from `core-v-verif`; its UVM environment is not used |
| **Spike** | an *independent* golden reference for base-ISA cross-checking, layered underneath SimX |
| **riscv-isacov**-style functional coverage | the model this project's covergroups extend |

> **Our UVM environment is original, not a derivative of OpenHW Group's.** Every
> agent, the scoreboard, the coverage collector, the DPI bridge, and the SIMT
> probes in [`Vortex/sim/uvmsim/`](Vortex/sim/uvmsim/) were designed and written
> for this project's warp/mask/divergence semantics from scratch. `core-v-verif`
> is vendored for exactly one thing — the riscv-dv constrained-random generator
> plumbing — never for its (CPU-scoped, single-hart) UVM testbench architecture.

**The gap:** every one of those tools models a **single scalar hart executing one instruction stream**. None has a semantic concept of a *warp*, a *dynamic per-thread execution mask*, a *divergence/reconvergence (IPDOM) stack*, *memory coalescing*, or *scratchpad bank contention* — the exact dimensions that make a GPU a GPU. Run unmodified against Vortex, that scalar stack measurably leaves the GPU-specific coverage bins at **0% hits** (divergence depth, bank conflicts, coalescing classification) — not because those hazards can't happen, but because nothing upstream knew to look for them.

**What this project adds is the missing SIMT extension layer**, not a replacement: a warp/mask/divergence-aware coverage model, an original SIMT-aware random-kernel generator (`simtgen`), and a lockstep architecture that plugs a cycle-approximate golden model into the same checking philosophy RVVI already established for scalar cores — all driven from **one fully-configurable parameter set** (`CLUSTERS × CORES × WARPS × THREADS`) so the same environment retargets to any Vortex-derived SIMT core topology without touching testbench source.

---

## Overview

This repository hosts a complete **UVM verification environment** for the **Vortex** RISC-V GPGPU — the open-source GPU from Georgia Tech (Prof. Hyesoon Kim's group, *MICRO-54, 2021*, Apache-2.0) — engineered to generalize as a **reusable framework for any RISC-V–based SIMT GPU**, not a one-off testbench for one core.

> [!NOTE]
> **Verification method — two independent checking layers, both proven able to fail.**
> The DUT executes a program to completion; the **SimX** C++ functional model executes the *same* program over a DPI-C bridge from the *same* parameters.
> 1. **End-state equivalence** — byte-exact comparison of final memory, *bidirectional*: every word the DUT wrote is checked, **and** every word SimX wrote that the DUT never did (which is how a dropped store is caught).
> 2. **Per-instruction lockstep** — every retirement compared per active SIMT lane (PC, destination register, value), with an exported trace cross-checked offline against **Spike** on the base-ISA subset.
>
> **Both layers carry permanent fault-injection tests that must report an error**, re-run after every change. A checker that has never been observed to fail is indistinguishable from an absent one — see [Findings](#-findings) for what that discipline cost us to skip, and what it caught.
>
> ⚠️ **Reference-model independence has a ceiling.** SimX is maintained with the RTL, so a shared misunderstanding is invisible to every check. Spike closes only the scalar base-ISA axis; **the SIMT axis has no independent reference.**

### What is *this project's* work, vs. what is vendored or adopted

| Path | Origin | Role |
| :--- | :--- | :--- |
| [`Vortex/sim/uvmsim/`](Vortex/sim/uvmsim/) | **This project** | The UVM environment source — agents, scoreboard, coverage collector, DPI bridge, scripts (packaged as a Vortex simulator backend, alongside `sim/simx` etc.) |
| [`Vortex/sim/uvmsim/scripts/simtgen/`](Vortex/sim/uvmsim/scripts/simtgen/) | **This project — original** | `simtgen`: a from-scratch SIMT-aware random C-kernel generator (see [below](#-simtgen--closing-the-simt-stimulus-gap)) |
| [`vortex_uvm_env/`](vortex_uvm_env/) | **This project** | Coverage banks (`cov/`), run results (`results/`), and project-level docs — not simulator source |
| [`Vortex/`](Vortex/) | Upstream (Apache-2.0) | The DUT: Vortex RTL + the SimX golden model, pinned baseline `7a52ee5` + this project's RTL/TB fixes |
| [`core-v-verif/`](https://github.com/openhwgroup/core-v-verif) | Upstream (OpenHW Group) | riscv-dv generator infrastructure for constrained-random base-ISA programs |
| Spike (`riscv-isa-sim`) | Upstream | independent scalar golden-reference cross-check |

<table>
<tr><td><b>Simulator</b></td><td>QuestaSim 2021.2_1</td>
    <td><b>Primary config</b></td><td>1&nbsp;cluster · 1&nbsp;core · 4&nbsp;warps · 4&nbsp;threads</td></tr>
<tr><td><b>Host OS</b></td><td>Ubuntu 22.04 (WSL2)</td>
    <td><b>ISA</b></td><td>RISC-V RV32IMAF (D-extension elaborated but unused — see finding OBS-061)</td></tr>
<tr><td><b>Memory interface</b></td><td>AXI4 (primary) · native cache-line (alt)</td>
    <td><b>Golden model</b></td><td>SimX, linked as <code>simx_model.so</code> (DPI-C)</td></tr>
<tr><td><b>Alternate stimulus paths</b></td><td>native Vortex kernels · riscv-dv · <code>simtgen</code> · POCL (OpenCL-C)</td>
    <td><b>Config knobs</b></td><td><code>CLUSTERS · CORES · WARPS · THREADS · L2 · L3</code></td></tr>
</table>

---

## 🚀 Quick Start

**Prerequisites:** QuestaSim 2021.2+, a RISC-V GCC/LLVM toolchain (`riscv{32,64}-unknown-elf`), and a C++17 compiler for the SimX model. All commands run from `Vortex/sim/uvmsim/`.

```bash
cd Vortex/sim/uvmsim

# Full flow: build the SimX DPI library, compile RTL + UVM, simulate.
make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite TIMEOUT=200000

# Re-run without recompiling the RTL (reuses work/).
make sim-only TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite

# Prove the checkers can fail. NOTE: the injection is plusarg-gated — without
# +INJECT_FAULT / +DROP_STORE these tests pass having injected NOTHING.
EXTRA_PLUSARGS="+INJECT_FAULT" make sim TEST=negative_result_test        PROGRAM_NAME=vecadd_lite
EXTRA_PLUSARGS="+DROP_STORE"   make sim TEST=negative_dropped_store_test PROGRAM_NAME=vecadd_lite

# Generate a SIMT-aware random kernel and run it through the same flow
# (no test/scoreboard changes needed — simtgen only emits stimulus).
python3 scripts/simtgen/simtgen.py --seed 42 --axis divergence \
        --out ../../tests/kernel/simtgen_demo
make sim TEST=kernel_launch_test PROGRAM_NAME=simtgen_demo TIMEOUT=100000

# Run the full regression suite and merge coverage.
bash scripts/run_suite.sh

# Report merged coverage without re-running anything.
vcover report -summary cov/bank_1CL_1C_4W_4T_relayfix_20260818/merged.ucdb

make help    # all targets and flags
```

Each run writes to `results/<date>/run_<time>_<test>/` with a full transcript, a
pass/fail `SUMMARY.txt`, and a per-run `coverage.ucdb`.

---

## 🏗 Architecture

```
        ┌────────────────────────── vortex_tb_top ──────────────────────────┐
        │                                                                    │
  host ─▶│ host_agent ─┬─▶ dcr_agent ──▶ DCR  ─┐                             │
        │  (orchestr.) └─▶ status_agent ◀─ status│                          │
        │                                        ▼                          │
   ELF ─▶│           Vortex DUT (RTL)  ──▶ AXI4 / mem bus ──▶ mem_model      │
        │                 │      ▲              ▲                            │
        │        axi_agent / mem_agent (active responders + monitors)       │
        │                 │                                                  │
        │                 ▼  analysis ports                                 │
        │           vortex_scoreboard ─────── DPI-C ─────▶ SimX (golden)     │
        │                 │                                                  │
        │           vortex_coverage_collector  ◀── warp/mask/divergence/     │
        │                                           coalesce/bank covergroups│
        └────────────────────────────────────────────────────────────────────┘
                                    ▲
                    stimulus:  native kernels · riscv-dv · simtgen · POCL
```

The full GPU is instantiated (`clusters → sockets → cores → warps → threads`).
Two build variants share one golden model and one scoreboard, differing only at
the memory boundary: **`Vortex.sv`** (native cache-line bus) and
**`Vortex_axi.sv`** = `Vortex.sv` + `VX_axi_adapter` (AXI4, primary).

### Agents → RTL interfaces

| Agent | Interface | Protocol | Role |
| :--- | :--- | :--- | :--- |
| `axi_agent` | `vortex_axi_if` | AXI4 · 5 channels · 512-bit | **primary** memory (active responder), fault-injectable (`+AXI_INJECT_ERR`) |
| `mem_agent` | `vortex_mem_if` | native valid-ready | alt memory path |
| `dcr_agent` | `vortex_dcr_if` | write-only | startup PC, perf config |
| `host_agent` | *(no bus)* | orchestrator | drives DCR + status + mem backdoor |
| `status_agent` | `vortex_status_if` | **passive** | observes busy / EBREAK / IPC |

> The host agent owns no physical bus — it sequences a kernel's full lifecycle
> (reset → load → configure → launch → wait → read) through the other interfaces.
> Signal-level mapping: [`docs/INTERFACE_MAPPING.md`](docs/INTERFACE_MAPPING.md).

### The SIMT coverage layer (this project's extension over riscv-isacov)

Passive `bind`-based probes expose microarchitectural state riscv-isacov has no vocabulary for, each feeding a dedicated covergroup:

| Probe | Samples | Covergroup |
| :--- | :--- | :--- |
| `vx_sched_probe.sv` | IPDOM divergence-stack depth (`warp_ctl_if.dvstack_ptr`) | `warp_divergence_cg.cp_split_depth` |
| `vx_lmem_probe.sv` | per-lane scratchpad bank request/conflict | `lmem_bank_cg.cp_bank_conflict` |
| `vx_commit_probe.sv` | per-lane commit/mask state, memory coalescing kind | `coalesce_cg.cp_coalesce_kind` |
| `vx_cache_probe.sv` | L1/L2/L3 hit/miss, per instance | `cache_event_cg` |
| `vx_dcr_probe.sv` | per-core DCR RAL read-back | `dcr_cg` |

### Completion & comparison

- **Primary trigger** — the TB decodes the real `ebreak` (`0x00100073`) at the commit stage across **all** cores; the status monitor broadcasts completion immediately.
- On completion the scoreboard runs SimX to the same point and compares the data-region memory and console. Instruction count and IPC are derived from the real `commit_arb_if[*]` retirement handshake — never a heuristic.
- **Verdicts are tiered and honest:** `PASS` (byte-exact), `FAIL`, liveness-only, `VACUOUS` (guarded), and `UNVERIFIABLE` (SimX aborts / spawn-kernel) — the last is *gated*, never faked.

---

## 🎲 `simtgen` — closing the SIMT stimulus gap

`riscv-dv` and Spike generate/execute **scalar** programs; neither has a concept of a warp, a thread mask, or a reconvergence stack, so neither can *intentionally* provoke a divergent branch, a bank-contending memory pattern, or a coalescable-vs-scattered access. **`simtgen`** ([`Vortex/sim/uvmsim/scripts/simtgen/`](Vortex/sim/uvmsim/scripts/simtgen/)) is an original, from-scratch generator built to close exactly that gap.

**Design principle:** randomize only at the *program* layer. The existing SimX lockstep + end-state compare do all correctness checking, unchanged — `simtgen`'s only job is to produce *interesting* programs; it needs no self-checking logic of its own.

**Why not reuse an existing SIMT fuzzer?** FuzzGPU (USENIX Security 2026) was evaluated and its generator was found inseparable from its own checking stack — it calls into a live, vendored ISA-emulator instance per generated instruction, coupled to a CMake build that also pulls in Verilator/ramulator/softfloat, with no generator-only target. Full negative-result writeup, with file:line evidence: [`docs/GENERATOR_SCOPING_DECISION.md`](docs/GENERATOR_SCOPING_DECISION.md). Only the *published axis taxonomy* (divergence / memory-access-pattern / barrier-sync) was reused as a category label; every data structure, weight, and generation algorithm in `simtgen` is original.

**Six hard constraints enforced in every generated program:**

| # | Constraint | Why |
| :--- | :--- | :--- |
| 1 | Race-free by construction | Vortex is weakly coherent (flush-only) — each thread/warp writes only its own memory slice |
| 2 | Divergent control flow is real C `if`/`else`, never hand-asm | matches how real kernels diverge (OBS-056) |
| 3 | Grid is device-derived (`vx_num_cores()*vx_num_warps()*vx_num_threads()`) | never hardcoded — same program retargets to any config (OBS-028) |
| 4 | No self-check | SimX is the reference; duplicating it in the kernel would be redundant and error-prone |
| 5 | Bounded live values (≤ 8–16) | measured register-spill / spawn-join deadlock risk above that |
| 6 | Seeded, deterministic — one `random.Random(seed)` instance threaded through everything | reproducibility, verified by generating the same seed twice and diffing |

**Two axes implemented today** (`barrier` and `vote_shfl` axes are declared placeholders, not yet built):

- **`divergence`** — nested-`if` trees up to the RTL-derived IPDOM stack depth (`DV_STACK_SIZE = NUM_THREADS-1`, `VX_gpu_pkg.sv:53`). Had to defeat **LLVM folding a pure-arithmetic divergent body into a lookup table** (confirmed by reading the compiled disassembly) — fixed with a `volatile` accumulator that forces real memory ordering, restoring genuine nested `vx_split_n`/`vx_join` structure.
- **`memory`** — coalescable / partial / scattered access-pattern modes, plus a mode that deliberately synthesizes **bank-hostile strides** (`idx = base + tid*nt`) to provoke scratchpad bank contention on purpose rather than hoping for it.

**Result — bins the unmodified industry stack left at 0% are now closed:**

| Covergroup bin | Before `simtgen` | After |
| :--- | :---: | :---: |
| `warp_divergence_cg.cp_split_depth` (4 depths) | 3/4 (d[3] never hit, 0/50 seeds) | **4/4 (100%)** |
| `lmem_bank_cg.cp_bank_conflict` | 0/3 (structurally never sampled — see OBS-060) | **3/3 (100%)** |
| `coalesce_cg.cp_coalesce_kind` | partial | **3/3 (100%)** |

> These closures are verified in isolated merge directories (`vortex_uvm_env/cov/simtgen_*_20260907/`) and are **not yet folded into the frozen defence banks below** — that requires a full-suite re-run, tracked as a deliberate next step, not silently assumed.

`simtgen` is complemented by a **second independent stimulus/compiler path**: **POCL** compiles real OpenCL-C kernels through a Vortex-targeted `llvm-vortex` toolchain onto the same DUT (validated end-to-end this project: `saxpy`, PASSED, IPC 0.997) — proving the environment isn't exercised through only one code-generation path.

---

## 📊 Results

Reported **per configuration — never blended** (cross-config UCDB merges are invalid due to per-instance width and count changes).

### Banked configurations

Five banks; each is one consistent compile, verified by re-reading the banked copy.

| Configuration | Runs | Total | Covergroup bins | Conditions | Toggle |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **1CL / 1C / 4W / 4T** (primary, reset-fixed) | **51 / 51** | **94.72%** | 370/377 = 98.1% | 90.4% | 83.3% |
| 2CL / 2C / 4W / 4T | 50 / 50 | 94.55% | 989/1032 = 95.8% | 88.8% | 80.5% |
| 2CL + **L2 + L3** enabled | 51 / 51 | 93.18% | 1042/1092 = 95.4% | 79.3% | 83.5% |
| 1CL + **seed farm** (141 UCDBs) | — | 94.72% | 98.1% | 90.4% | 83.4% |

**0 failures at every configuration.** Statements 98.1% · branches 94.5% · assertions 96.9% · SVA directives 100%.

> **Coverage-exclusion integrity is enforced, not asserted.** Every waiver is
> generated per-configuration from elaborated RTL parameters with a `file:line`
> citation ([`gen_coverage_exclude.sh`](Vortex/sim/uvmsim/scripts/gen_coverage_exclude.sh)),
> and the merge applies a **blocking hits-invariant gate**: if a structural
> exclusion changes any *covered* bin count, the merge fails. It caught two
> waivers that had been silently deleting real coverage.

> **Toggle ceiling — root-caused, and the attribution was corrected.** The plateau
> was long ascribed to write-through data caching. Measured per subtree, the
> dominant contributor is the **read-only instruction cache**, elaborated with its
> write port disabled: **22,730 missing bins — 26% of the entire toggle gap from
> one subtree** — while the dcache is 89% covered. Positive control: the icache's
> response-data path toggles on all 512 bits, so the read direction is alive and
> only the write direction is dead.

> **Shared L2/L3 exercised for the first time.** Both levels were always
> pass-through because the suite had no path from its configuration to the
> compile. After plumbing it, all four shared-cache instances are covered on hit
> *and* miss (13k–15k hits each), with a **196,868-word byte-exact** end-state
> compare — 6× the previous largest in the suite. Honest reading: the hierarchy
> was *reached and validated, not thoroughly exercised* (conditions 79.3%).

### Constrained-random: a measured negative result, and why `simtgen` exists

A **10-seed sweep across 9 riscv-dv profiles** produced **90 additional distinct
programs** (each verified distinct by content hash), **all passing** — and
**zero coverage gain**: every category bit-identical except toggle at +0.06%.

That is a robustness result, not a coverage one. The binding constraint is the
generator's *reach*, not its sample count — riscv-dv emits scalar user-mode
integer code with no concept of a warp to diverge or a bank to contend, so
every seed explores the same region. **The stimulus gap was diversity along
the SIMT axis, not volume along the scalar one** — which is exactly what
`simtgen` was engineered to add (see above).

---

## 🔬 Findings

Real RTL and testbench-integrity defects, maintained with evidence and
disposition in [`docs/RTL_OBSERVATIONS.md`](docs/RTL_OBSERVATIONS.md)
(60+ entries, including retractions and falsified hypotheses).

| # | Finding | Status |
| :--- | :--- | :--- |
| **R10** | `VX_reset_relay` registers reset in a flop **nothing resets** — `reset_o` is **X for one cycle** at every `RESET_RELAY` site, so modules behind a relay take their non-reset branch | **fixed here; still present upstream** |
| **R1** | JALR does not clear the target LSB (RISC-V spec deviation); odd PC propagates into architectural results via `auipc` | present upstream at HEAD |
| **R2** | `STALL_TIMEOUT` uses `1**N ≡ 1`, so the watchdog never scales with cache depth | fixed here; **independently fixed upstream** |
| **R3** | Misaligned access: no trap, silently retargeted/torn; sim-only assertion is the only guard | expected per SW contract |
| **OBS-060** | `lmem_bank_cg.cp_bank_conflict` reported a false 0% "gap" — the coverage **probe** was gated on `req_valid && req_ready`, structurally unreachable given the memory crossbar's one-winner-per-bank-per-cycle port structure (a testbench defect, not an RTL one) | **fixed** — reclassified on `req_valid` alone; 169 real conflicts now observed |
| **OBS-061** | The primary "RV32IMF" config elaborates with **FLEN=64 and RISC-V D-extension MISA bit set** — confirmed dynamically via an isolated elaboration probe, not assumed from source alone. Scoping (architectural reachability, coverage-bank dilution, SimX F-only soundness) is an **open** follow-up, not yet resolved | **open, logged** |

> **How R10 was found is the point.** Upstream's counter assertions fired during
> bring-up and were guarded off so the bench could run. That guard hid a genuine
> X window for months. Restoring the assertion and root-causing it exposed the
> defect. **The assertion had been correct all along** — what was suppressed was
> the report, not the problem.
>
> Fixing it **lowered** branch coverage (95.1% → 94.5%): modules behind a relay
> had been executing their normal-operation paths during the unknown-reset cycle,
> and those executions counted as *covered branches*. Part of the previously
> banked coverage came from a state that cannot legitimately arise — something no
> coverage metric can report about itself.
>
> **OBS-060 is the same lesson at the testbench layer**: a 0%-hit bin is not
> self-evidently a stimulus gap. It can be the probe itself failing to see what
> the RTL is actually doing — and the only way to tell the difference is to
> read the RTL structure the probe claims to sample, not just trust the count.

---

## 🧪 Tests

Located in [`Vortex/sim/uvmsim/uvm_tests/`](Vortex/sim/uvmsim/uvm_tests/) — select with `TEST=<name>`:

| Test | Focus |
| :--- | :--- |
| `vortex_smoke_test` · `vortex_sanity_test` | bring-up / connectivity |
| `kernel_launch_test` | end-to-end kernels (native, riscv-dv, `simtgen`, POCL) vs SimX |
| `functional_memory_test` · `axi_memory_test` | memory correctness / AXI4 compliance |
| `warp_scheduling_test` · `barrier_sync_test` | scheduler, divergence, synchronization |
| `random_instruction_stress_test` | constrained-random (riscv-dv) pipeline stress |
| `host_coverage_test` | DCR RAL read-back coverage |
| `negative_result_test` · `negative_dropped_store_test` | **fault-injection guards — must go RED on injection** |

`PROGRAM_NAME=<kernel>` resolves an ELF under `Vortex/tests/kernel/<name>/`.
`riscv_*` programs are generated and compiled through the riscv-dv pipeline in
[`prepare.sh`](Vortex/sim/uvmsim/scripts/prepare.sh); `simtgen_*` programs are
generated by [`scripts/simtgen/simtgen.py`](Vortex/sim/uvmsim/scripts/simtgen/simtgen.py).
See [`docs/RISCV_DV_GUIDE.md`](docs/RISCV_DV_GUIDE.md).

---

## ⚙ Configurability

**This is the "fully configurable, reusable" part of the framework.** One
parameter set drives **all three** consumers, so the hardware, the golden
model, and the testbench can never silently disagree — the same environment
retargets to a different SIMT core topology (or, in principle, a different
Vortex-derived GPU) without touching testbench source:

| Consumer | Mechanism |
| :--- | :--- |
| RTL (elaboration) | `+define+NUM_CLUSTERS/CORES/WARPS/THREADS`, `USE_AXI_WRAPPER`, `L2`, `L3` |
| SimX (recompiled per config) | `-D` arch macros (`CONFIGS=…`) — rebuilt automatically per config, never assumed |
| Testbench (runtime) | `+plusargs` read by `vortex_config.sv::apply_plusargs()` |
| Coverage exclusions | regenerated per configuration from the *elaborated* RTL parameters, never hand-maintained |
| Stimulus (`simtgen`) | grid size is **device-derived at runtime** (`vx_num_cores()*vx_num_warps()*vx_num_threads()`), never hardcoded to one config |

```bash
make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite \
         CLUSTERS=2 CORES=2 WARPS=4 THREADS=4 TIMEOUT=200000
```

> [!IMPORTANT]
> **Elaboration asserts** check the UVM topology and tag widths against the
> compiled DUT. A stale `sim-only` run with mismatched parameters **aborts loudly**
> at time 0 instead of silently producing garbage.

---

## 📁 Repository Layout

```
Vortex_UVM_GP/
├── Vortex/                       # DUT — Vortex RISC-V GPGPU RTL + SimX (upstream, pinned; a real git submodule)
│   └── sim/uvmsim/               ◀ THE VERIFICATION ENVIRONMENT SOURCE (this project's work,
│       ├── tb/                   #   packaged as a Vortex simulator backend, alongside sim/simx etc.)
│       │                         #   vortex_tb_top.sv, interfaces, binds, elaboration asserts,
│       │                         #   SIMT probes (vx_sched_probe, vx_lmem_probe, vx_commit_probe, …)
│       ├── uvm_env/
│       │   ├── agents/           #   5 agents: axi · mem · dcr · host · status
│       │   ├── ref_model/        #   SimX DPI bridge (simx_dpi.cpp, simx_pkg.sv)
│       │   ├── vortex_scoreboard.svh          #   end-state equivalence vs SimX
│       │   └── vortex_coverage_collector.svh  #   SIMT covergroups (divergence/coalesce/bank/…)
│       ├── uvm_tests/            #   test library (see Tests)
│       ├── scripts/              #   run.sh → prepare.sh → compile.sh → simulate.sh, run_suite.sh
│       │   └── simtgen/          #   ◀ original SIMT-aware random C-kernel generator
│       └── docs/                 #   testbench-specific writeups
│
├── vortex_uvm_env/                # coverage banks, run results, project-level docs (not sim source)
│   ├── cov/                       #   per-config coverage banks (bank_1CL…, bank_2CL…, simtgen_*)
│   ├── results/                   #   run logs/waveforms/reports
│   └── docs/                      #   plan, coverage model, riscv-dv guide, per-fix writeups
│
├── core-v-verif/                 # riscv-dv generator infrastructure (upstream, OpenHW Group)
└── docs/                         # coverage reports, findings register, investigations
```

---

## 👥 Authorship

Originally scoped as a group project; the verification environment, coverage
model, lockstep flow, RTL investigations, `simtgen`, and papers in their
current form are the work of **Samuel Moussa**. Earlier contributors are
credited in the commit history for the bring-up phase.

---

## 📚 Documentation Map

| Document | Purpose |
| :--- | :--- |
| **[`docs/RTL_OBSERVATIONS.md`](docs/RTL_OBSERVATIONS.md)** | **the single running register — 60+ evidence-cited findings, RTL and testbench, with dispositions** |
| **[`docs/INDUSTRIAL_TRANSFORMATION_PLAN.md`](docs/INDUSTRIAL_TRANSFORMATION_PLAN.md)** | **project source of truth — start at the ▶▶ RESUME HERE block** |
| [`docs/GENERATOR_SCOPING_DECISION.md`](docs/GENERATOR_SCOPING_DECISION.md) | why FuzzGPU's generator was evaluated and not reused; what `simtgen` took instead |
| [`docs/INDUSTRIAL_ROADMAP_2026-09-07.md`](docs/INDUSTRIAL_ROADMAP_2026-09-07.md) | costed forward roadmap, with claims individually checked against source |
| [`docs/PAPER_BASE_EVALUATION.md`](docs/PAPER_BASE_EVALUATION.md) | audited evidence base for every published claim |
| [`docs/paper/vortex_uvm_paper.tex`](docs/paper/) | full paper — method, lockstep, findings (11 pp) |
| [`docs/paper/vortex_uvm_paper_short.tex`](docs/paper/) | condensed submission version (8 pp) |
| [`docs/paper/vortex_uvm_frontend_paper.tex`](docs/paper/) | front-end-scoped companion paper (5 pp) |
| [`docs/Coverage_Model_Reference.md`](docs/Coverage_Model_Reference.md) | every covergroup and its rationale |
| [`docs/RISCV_DV_GUIDE.md`](docs/RISCV_DV_GUIDE.md) | constrained-random pipeline |
| [`docs/INTERFACE_MAPPING.md`](docs/INTERFACE_MAPPING.md) | RTL interface → UVM agent mapping |
| [`docs/VERIFICATION_PLAN_v2.md`](docs/VERIFICATION_PLAN_v2.md) | strategy, testcases, coverage goals — current |
| [`docs/fixes/`](docs/fixes/) | per-issue root-cause writeups |

---

## ⚖️ Scope and limits

Stated here rather than discovered later. This is **front-end functional
verification of an RTL model** — not a sign-off flow, and not yet a
formally-published standard, though it is engineered to generalize as one.

**Not started:** gate-level simulation · static timing · DFT/ATPG · clock- and
reset-domain-crossing analysis · lint · low-power · formal property verification
· X-propagation and randomized reset.

**Known caveats:**
- **The DUT is upstream `7a52ee5` plus locally modified RTL/TB files.** Some
  are principled (upstream `VX_pending_size` restored; the R10 relay fix;
  the OBS-060 probe reclassification), the rest are bring-up expedients,
  frozen by decision. Two TCU files carry undocumented change, so **any
  TCU-specific claim rests on RTL the register does not fully describe**.
- **Coverage banks are per configuration and must never be blended** — instance
  counts and signal widths differ, so a cross-config merge is meaningless.
- `simtgen`'s coverage closures (divergence depth, bank conflict, coalescing)
  are verified in **isolated merges**, not yet folded into the frozen defence
  banks reported above — a full-suite re-run is the tracked next step.
- The 2CL and L2/L3 banks were taken **before** the R10 fix and are not
  comparable to the primary bank on branch coverage.
- **OBS-061 (FLEN=64/D-extension elaborated at the primary config) is an open
  scoping item** — do not assume the frozen coverage totals above account for
  it until it is resolved.
- `simtgen`'s `barrier` and `vote_shfl` axes are declared but not yet
  implemented.
- The coverage model is self-authored, not traced to a specification document.

---

## License & Attribution

The Vortex DUT RTL and the SimX model are vendored under their upstream
**Apache-2.0** license — see [`Vortex/LICENSE`](Vortex/LICENSE). The UVM
verification environment in [`Vortex/sim/uvmsim/`](Vortex/sim/uvmsim/), including
`simtgen`, is authored by the team above as a graduation project at
**Minia University, Faculty of Engineering (2026)**, sponsored by
**Seamless Waves (Insspectrum)**.

<div align="center">
<sub>Built on the Vortex GPGPU · Verified with UVM 1.2 on QuestaSim · SimX golden reference via DPI-C · SIMT stimulus by simtgen</sub>
</div>
