<div align="center">

# Vortex GPGPU — UVM Functional Verification Environment

**A reusable, fully-configurable UVM testbench for the [Vortex](https://github.com/vortexgpgpu/vortex) open-source RISC-V GPGPU,**
**checked by per-instruction lockstep and end-state equivalence against the SimX C++ golden model over DPI-C.**

[![Methodology](https://img.shields.io/badge/Methodology-UVM%201.2-1f6feb?style=flat-square)](https://www.accellera.org/downloads/standards/uvm)
[![SystemVerilog](https://img.shields.io/badge/SystemVerilog-IEEE%201800-e36209?style=flat-square)](https://ieeexplore.ieee.org/document/8299595)
[![ISA](https://img.shields.io/badge/ISA-RISC--V%20RV32IMAF-283272?style=flat-square&logo=riscv&logoColor=white)](https://riscv.org/)
[![Simulator](https://img.shields.io/badge/Simulator-QuestaSim%202021.2-2da44e?style=flat-square)](https://eda.sw.siemens.com/en-US/ic/questa/)
[![Golden Model](https://img.shields.io/badge/Golden%20Model-SimX%20·%20DPI--C-8957e5?style=flat-square)](https://github.com/vortexgpgpu/vortex)
[![Coverage](https://img.shields.io/badge/Covergroup%20Bins-98.1%25-2da44e?style=flat-square)](#-results)
[![Total](https://img.shields.io/badge/Total%20Coverage-94.7%25-2da44e?style=flat-square)](#-results)
[![Lockstep](https://img.shields.io/badge/Checking-Per--Instruction%20Lockstep-8957e5?style=flat-square)](#-architecture)
[![RTL bugs](https://img.shields.io/badge/RTL%20Defects%20Found-4-c9510c?style=flat-square)](#-findings)

[Quick Start](#-quick-start) ·
[Architecture](#-architecture) ·
[Results](#-results) ·
[Tests](#-tests) ·
[Configurability](#-configurability) ·
[Docs](#-documentation-map)

</div>

---

## Overview

This repository hosts a complete **UVM verification environment** for the **Vortex** RISC-V GPGPU — the open-source GPU from Georgia Tech (Prof. Hyesoon Kim's group, *MICRO-54, 2021*, Apache-2.0).

> [!NOTE]
> **Verification method — two independent checking layers, both proven able to fail.**
> The DUT executes a program to completion; the **SimX** C++ functional model executes the *same* program over a DPI-C bridge from the *same* parameters.
> 1. **End-state equivalence** — byte-exact comparison of final memory, *bidirectional*: every word the DUT wrote is checked, **and** every word SimX wrote that the DUT never did (which is how a dropped store is caught).
> 2. **Per-instruction lockstep** — every retirement compared per active SIMT lane (PC, destination register, value), with an exported trace cross-checked offline against **Spike** on the base-ISA subset.
>
> **Both layers carry permanent fault-injection tests that must report an error**, re-run after every change. A checker that has never been observed to fail is indistinguishable from an absent one — see [Findings](#-findings) for what that discipline cost us to skip, and what it caught.
>
> ⚠️ **Reference-model independence has a ceiling.** SimX is maintained with the RTL, so a shared misunderstanding is invisible to every check. Spike closes only the scalar base-ISA axis; **the SIMT axis has no independent reference.**

### What is *this team's* work, vs. what is vendored

| Path | Origin | Role |
| :--- | :--- | :--- |
| [`vortex_uvm_env/`](vortex_uvm_env/) | **This project** | The entire UVM environment — agents, scoreboard, coverage, DPI bridge, scripts |
| [`Vortex/`](Vortex/) | Upstream (Apache-2.0) | The DUT: Vortex RTL + the SimX golden model, pinned @ `7a52ee5` |
| [`core-v-verif/`](https://github.com/openhwgroup/core-v-verif) | Upstream | riscv-dv generator infrastructure for constrained-random programs |

<table>
<tr><td><b>Simulator</b></td><td>QuestaSim 2021.2_1</td>
    <td><b>Primary config</b></td><td>1&nbsp;cluster · 1&nbsp;core · 4&nbsp;warps · 4&nbsp;threads</td></tr>
<tr><td><b>Host OS</b></td><td>Ubuntu 22.04 (WSL2)</td>
    <td><b>ISA</b></td><td>RISC-V RV32IMAF</td></tr>
<tr><td><b>Memory interface</b></td><td>AXI4 (primary) · native cache-line (alt)</td>
    <td><b>Golden model</b></td><td>SimX, linked as <code>simx_model.so</code> (DPI-C)</td></tr>
</table>

---

## 🚀 Quick Start

**Prerequisites:** QuestaSim 2021.2+, a RISC-V GCC/LLVM toolchain (`riscv{32,64}-unknown-elf`), and a C++17 compiler for the SimX model. All commands run from `vortex_uvm_env/`.

```bash
cd vortex_uvm_env

# Full flow: build the SimX DPI library, compile RTL + UVM, simulate.
make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite TIMEOUT=200000

# Re-run without recompiling the RTL (reuses work/).
make sim-only TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite

# Prove the checkers can fail. NOTE: the injection is plusarg-gated — without
# +INJECT_FAULT / +DROP_STORE these tests pass having injected NOTHING.
EXTRA_PLUSARGS="+INJECT_FAULT" make sim TEST=negative_result_test        PROGRAM_NAME=vecadd_lite
EXTRA_PLUSARGS="+DROP_STORE"   make sim TEST=negative_dropped_store_test PROGRAM_NAME=vecadd_lite

# Run the full regression suite (51 runs) and merge coverage.
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
        │           vortex_coverage_collector                               │
        └────────────────────────────────────────────────────────────────────┘
```

The full GPU is instantiated (`clusters → sockets → cores → warps → threads`).
Two build variants share one golden model and one scoreboard, differing only at
the memory boundary: **`Vortex.sv`** (native cache-line bus) and
**`Vortex_axi.sv`** = `Vortex.sv` + `VX_axi_adapter` (AXI4, primary).

### Agents → RTL interfaces

| Agent | Interface | Protocol | Role |
| :--- | :--- | :--- | :--- |
| `axi_agent` | `vortex_axi_if` | AXI4 · 5 channels · 512-bit | **primary** memory (active responder) |
| `mem_agent` | `vortex_mem_if` | native valid-ready | alt memory path |
| `dcr_agent` | `vortex_dcr_if` | write-only | startup PC, perf config |
| `host_agent` | *(no bus)* | orchestrator | drives DCR + status + mem backdoor |
| `status_agent` | `vortex_status_if` | **passive** | observes busy / EBREAK / IPC |

> The host agent owns no physical bus — it sequences a kernel's full lifecycle
> (reset → load → configure → launch → wait → read) through the other interfaces.
> Signal-level mapping: [`docs/INTERFACE_MAPPING.md`](docs/INTERFACE_MAPPING.md).

### Completion & comparison

- **Primary trigger** — the TB decodes the real `ebreak` (`0x00100073`) at the commit stage across **all** cores; the status monitor broadcasts completion immediately.
- On completion the scoreboard runs SimX to the same point and compares the data-region memory and console. Instruction count and IPC are derived from the real `commit_arb_if[*]` retirement handshake — never a heuristic.
- **Verdicts are tiered and honest:** `PASS` (byte-exact), `FAIL`, liveness-only, `VACUOUS` (guarded), and `UNVERIFIABLE` (SimX aborts / spawn-kernel) — the last is *gated*, never faked.

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
> citation ([`gen_coverage_exclude.sh`](vortex_uvm_env/scripts/gen_coverage_exclude.sh)),
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

### Constrained-random: a measured negative result

A **10-seed sweep across 9 riscv-dv profiles** produced **90 additional distinct
programs** (each verified distinct by content hash), **all passing** — and
**zero coverage gain**: every category bit-identical except toggle at +0.06%.

That is a robustness result, not a coverage one. The binding constraint is the
generator's *reach*, not its sample count — it emits user-mode integer code with
M-mode CSR writes stripped, so every seed explores the same region. **The
remaining stimulus gap is diversity, not volume.**

---

## 🔬 Findings

Four real RTL defects, maintained with evidence and disposition in
[`docs/RTL_OBSERVATIONS.md`](docs/RTL_OBSERVATIONS.md) (46 entries, including
retractions and falsified hypotheses).

| # | Finding | Status |
| :--- | :--- | :--- |
| **R10** | `VX_reset_relay` registers reset in a flop **nothing resets** — `reset_o` is **X for one cycle** at every `RESET_RELAY` site, so modules behind a relay take their non-reset branch | **fixed here; still present upstream** |
| **R1** | JALR does not clear the target LSB (RISC-V spec deviation); odd PC propagates into architectural results via `auipc` | present upstream at HEAD |
| **R2** | `STALL_TIMEOUT` uses `1**N ≡ 1`, so the watchdog never scales with cache depth | fixed here; **independently fixed upstream** |
| **R3** | Misaligned access: no trap, silently retargeted/torn; sim-only assertion is the only guard | expected per SW contract |

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

---

## 🧪 Tests

Located in [`vortex_uvm_env/uvm_tests/`](vortex_uvm_env/uvm_tests/) — select with `TEST=<name>`:

| Test | Focus |
| :--- | :--- |
| `vortex_smoke_test` · `vortex_sanity_test` | bring-up / connectivity |
| `kernel_launch_test` | end-to-end kernels (hello, vecadd, conform, …) vs SimX |
| `functional_memory_test` · `axi_memory_test` | memory correctness / AXI4 compliance |
| `warp_scheduling_test` · `barrier_sync_test` | scheduler, divergence, synchronization |
| `random_instruction_stress_test` | constrained-random (riscv-dv) pipeline stress |
| `negative_result_test` | **fault-injection guard — goes RED on injection** |

`PROGRAM_NAME=<kernel>` resolves an ELF under `Vortex/tests/kernel/<name>/`.
`riscv_*` programs are generated and compiled through the riscv-dv pipeline in
[`prepare.sh`](vortex_uvm_env/scripts/prepare.sh); see
[`docs/RISCV_DV_GUIDE.md`](docs/RISCV_DV_GUIDE.md).

---

## ⚙ Configurability

One parameter set drives **all three** consumers, so the hardware, the golden
model, and the testbench can never silently disagree:

| Consumer | Mechanism |
| :--- | :--- |
| RTL (elaboration) | `+define+NUM_CLUSTERS/CORES/WARPS/THREADS`, `USE_AXI_WRAPPER` |
| SimX (recompiled per config) | `-D` arch macros (`CONFIGS=…`) |
| Testbench (runtime) | `+plusargs` read by `vortex_config.sv::apply_plusargs()` |

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
├── vortex_uvm_env/               ◀ THE VERIFICATION ENVIRONMENT (this project's work)
│   ├── tb/                       #   vortex_tb_top.sv, interfaces, binds, elaboration asserts
│   ├── uvm_env/
│   │   ├── agents/               #   5 agents: axi · mem · dcr · host · status
│   │   ├── ref_model/            #   SimX DPI bridge (simx_dpi.cpp, simx_pkg.sv)
│   │   ├── vortex_scoreboard.sv  #   end-state equivalence vs SimX
│   │   └── vortex_coverage_collector.sv
│   ├── uvm_tests/                #   test library (see Tests)
│   ├── scripts/                  #   run.sh → prepare.sh → compile.sh → simulate.sh, run_suite.sh
│   ├── cov/                      #   per-config coverage banks (bank_1CL…, bank_2CL…)
│   └── docs/                     #   plan, coverage model, riscv-dv guide, per-fix writeups
│
├── Vortex/                       # DUT — Vortex RISC-V GPGPU RTL + SimX (upstream, pinned)
├── core-v-verif/                 # riscv-dv generator infrastructure (upstream)
└── docs/                         # coverage reports and investigations
```

---

## 👥 Authorship

Originally scoped as a group project; the verification environment, coverage
model, lockstep flow, RTL investigations and papers in their current form are
the work of **Samuel Moussa**. Earlier contributors are credited in the commit
history for the bring-up phase.

---

## 📚 Documentation Map

| Document | Purpose |
| :--- | :--- |
| **[`docs/RTL_OBSERVATIONS.md`](docs/RTL_OBSERVATIONS.md)** | **the single running register — 46 evidence-cited findings, RTL and testbench, with dispositions** |
| **[`docs/INDUSTRIAL_TRANSFORMATION_PLAN.md`](docs/INDUSTRIAL_TRANSFORMATION_PLAN.md)** | **project source of truth — start at the ▶▶ RESUME HERE block** |
| [`docs/PAPER_BASE_EVALUATION.md`](docs/PAPER_BASE_EVALUATION.md) | audited evidence base for every published claim |
| [`docs/paper/vortex_uvm_paper.tex`](docs/paper/) | full paper — method, lockstep, findings (11 pp) |
| [`docs/paper/vortex_uvm_paper_short.tex`](docs/paper/) | condensed submission version (8 pp) |
| [`docs/paper/vortex_uvm_frontend_paper.tex`](docs/paper/) | front-end-scoped companion paper (5 pp) |
| [`docs/Coverage_Model_Reference.md`](docs/Coverage_Model_Reference.md) | every covergroup and its rationale |
| [`docs/RISCV_DV_GUIDE.md`](docs/RISCV_DV_GUIDE.md) | constrained-random pipeline |
| [`docs/INTERFACE_MAPPING.md`](docs/INTERFACE_MAPPING.md) | RTL interface → UVM agent mapping |
| [`docs/VERIFICATION_PLAN.md`](docs/VERIFICATION_PLAN.md) | strategy, testcases, coverage goals |
| [`docs/fixes/`](docs/fixes/) | per-issue root-cause writeups |

---

## ⚖️ Scope and limits

Stated here rather than discovered later. This is **front-end functional
verification of an RTL model** — not a sign-off flow.

**Not started:** gate-level simulation · static timing · DFT/ATPG · clock- and
reset-domain-crossing analysis · lint · low-power · formal property verification
· X-propagation and randomized reset · bus error injection · architectural
exception/interrupt stimulus.

**Known caveats:**
- **The DUT is upstream `7a52ee5` plus 18 locally modified RTL files.** Two are
  principled (upstream `VX_pending_size` restored; the R10 relay fix); the rest
  are bring-up expedients, frozen by decision. Two TCU files carry 193 and 111
  lines of undocumented change, so **any TCU-specific claim rests on RTL the
  register does not describe**.
- **Coverage banks are per configuration and must never be blended** — instance
  counts and signal widths differ, so a cross-config merge is meaningless.
- The 2CL and L2/L3 banks were taken **before** the R10 fix and are not
  comparable to the primary bank on branch coverage.
- The coverage model is self-authored, not traced to a specification document.

---

## License & Attribution

The Vortex DUT RTL and the SimX model are vendored under their upstream
**Apache-2.0** license — see [`Vortex/LICENSE`](Vortex/LICENSE). The UVM
verification environment in [`vortex_uvm_env/`](vortex_uvm_env/) is authored by
the team above as a graduation project at **Minia University, Faculty of
Engineering (2026)**, sponsored by **Seamless Waves (Insspectrum)**.

<div align="center">
<sub>Built on the Vortex GPGPU · Verified with UVM 1.2 on QuestaSim · SimX golden reference via DPI-C</sub>
</div>
