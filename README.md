<div align="center">

# Vortex GPGPU — UVM Functional Verification Environment

**A reusable, fully-configurable UVM testbench for the [Vortex](https://github.com/vortexgpgpu/vortex) open-source RISC-V GPGPU,**
**verified by black-box end-state equivalence against the SimX C++ golden model over DPI-C.**

[![Methodology](https://img.shields.io/badge/Methodology-UVM%201.2-1f6feb?style=flat-square)](https://www.accellera.org/downloads/standards/uvm)
[![SystemVerilog](https://img.shields.io/badge/SystemVerilog-IEEE%201800-e36209?style=flat-square)](https://ieeexplore.ieee.org/document/8299595)
[![ISA](https://img.shields.io/badge/ISA-RISC--V%20RV32IMAF-283272?style=flat-square&logo=riscv&logoColor=white)](https://riscv.org/)
[![Simulator](https://img.shields.io/badge/Simulator-QuestaSim%202021.2-2da44e?style=flat-square)](https://eda.sw.siemens.com/en-US/ic/questa/)
[![Golden Model](https://img.shields.io/badge/Golden%20Model-SimX%20·%20DPI--C-8957e5?style=flat-square)](https://github.com/vortexgpgpu/vortex)
[![Coverage](https://img.shields.io/badge/Functional%20Coverage-100%25-2da44e?style=flat-square)](#-results)
[![Total](https://img.shields.io/badge/Total%20Coverage-91%25-2da44e?style=flat-square)](#-results)

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
> **Verification method — black-box, end-state equivalence.**
> The DUT executes a program to completion. The **SimX** C++ functional model executes the *same* program through a DPI-C bridge, configured from the *same* parameters. The scoreboard compares the final architectural state — memory, console, and exit. **SimX is the golden reference.** No white-box, per-unit checking is assumed (that is scoped as future work).

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

# Prove the checker can fail — fault injection must produce SIMULATION FAILED.
make sim TEST=negative_result_test PROGRAM_NAME=vecadd_lite

# Run the full regression suite (48 runs) and merge coverage.
bash scripts/run_suite.sh

# Report merged coverage without re-running anything.
vcover report -summary cov/bank_1CL_1C_4W_4T/merged.ucdb

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

### Primary — 1 Cluster / 1 Core / 4 Warps / 4 Threads

| Metric | Value | | Metric | Value |
| :--- | :---: | :-- | :--- | :---: |
| **Functional coverage** | **100%** | | Toggle | 78.65% ¹ |
| Line | 97.05% | | Assertions | 93.79% |
| Branch | 91.16% | | Directives (SVA) | 100% |
| Condition | 76.35% | | **Total** | **91.00%** |

**48 runs · 0 failures · 29 byte-exact verified against SimX**; the remainder are liveness-verified or gated `UNVERIFIABLE` (not faked).

> ¹ **Toggle ~79% is a structural ceiling, not a stimulus gap.** The caches are
> write-through (`VX_cache_tags.sv`, `WRITEBACK=0`), so full-line write-data nets
> are never driven. This is root-caused and reported at its true value — every
> coverage exclusion is a per-configuration structural waiver cited to a specific
> line of RTL, generated by [`scripts/gen_coverage_exclude.sh`](vortex_uvm_env/scripts/gen_coverage_exclude.sh).

### Scale — 2 Clusters / 2 Cores / 4 Warps / 4 Threads

Total coverage **85.16%** (functional 92.48%, line 96.19%), demonstrating the
environment scales across topologies from a single parameter source.

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

## 👥 Team

A group project delivered to one shared verification plan.

| Owner | Lane |
| :--- | :--- |
| **Samuel Mousa** | verification infrastructure · full configurability (parameter harness, elaboration asserts, scripts) · constrained-random (riscv-dv) |
| **Ahmad Mahmoud** | functional & code coverage · scoreboard |
| **Abanoub Nabil** | Vortex architecture |
| **Steven Ibrahim** | golden model (SimX / DPI-C) · directed tests · AXI SVA . Regression Tests . Building Configrable master Makefile |
| **Ahmad Fawzy** | UVM agents |

---

## 📚 Documentation Map

| Document | Purpose |
| :--- | :--- |
| [`vortex_uvm_env/README.md`](vortex_uvm_env/README.md) | environment build & structure detail |
| [`docs/Coverage_Report_2026-07-10.md`](docs/Coverage_Report_2026-07-10.md) | full coverage report (both configs) |
| [`docs/Coverage_Model_Reference.md`](docs/Coverage_Model_Reference.md) | every covergroup and its rationale |
| [`docs/RISCV_DV_GUIDE.md`](docs/RISCV_DV_GUIDE.md) | constrained-random pipeline |
| [`docs/INTERFACE_MAPPING.md`](docs/INTERFACE_MAPPING.md) | RTL interface → UVM agent mapping |
| [`docs/VERIFICATION_PLAN.md`](docs/VERIFICATION_PLAN.md) | verification strategy, testcases, coverage goals |
| [`docs/fixes/`](docs/fixes/) | per-issue root-cause writeups |

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
