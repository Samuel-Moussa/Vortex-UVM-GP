<div align="center">

# Vortex GPGPU — UVM Verification Environment

**A reusable, configurable UVM testbench for the Vortex open-source RISC-V GPGPU,**
**verified by end-state equivalence against the SimX golden model.**

[![Methodology](https://img.shields.io/badge/Methodology-UVM%201.2-1f6feb?style=flat-square)](https://www.accellera.org/downloads/standards/uvm)
[![SystemVerilog](https://img.shields.io/badge/SystemVerilog-IEEE%201800-e36209?style=flat-square)](https://ieeexplore.ieee.org/document/8299595)
[![ISA](https://img.shields.io/badge/ISA-RISC--V%20RV32IM-283272?style=flat-square&logo=riscv&logoColor=white)](https://riscv.org/)
[![Simulator](https://img.shields.io/badge/Simulator-QuestaSim%202021.2-2da44e?style=flat-square)](https://eda.sw.siemens.com/en-US/ic/questa/)
[![OS](https://img.shields.io/badge/OS-Ubuntu%2022.04-E95420?style=flat-square&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Golden Model](https://img.shields.io/badge/Golden%20Model-SimX%20·%20DPI--C-8957e5?style=flat-square)](https://github.com/vortexgpgpu/vortex)
[![Gate 0](https://img.shields.io/badge/Gate--0-in%20progress-d4a72c?style=flat-square)](CLAUDE.md)

[Quick Start](#-quick-start) ·
[Architecture](#-architecture) ·
[Tests](#-tests) ·
[Status](#-status) ·
[Docs](#-documentation-map)

</div>

---

## Overview

This repository hosts a complete **UVM verification environment** for the
[Vortex](https://github.com/vortexgpgpu/vortex) RISC-V GPGPU. The design-under-test
(DUT) RTL is vendored in [`Vortex/`](Vortex/); the verification environment lives
in [`vortex_uvm_env/`](vortex_uvm_env/).

> [!NOTE]
> **Verification method — black-box, end-state equivalence.**
> The DUT executes a program to completion. The **SimX** C++ model executes the
> same program through a DPI-C bridge. The scoreboard compares the final
> architectural memory state. **SimX is the golden reference.**

<table>
<tr><td><b>Simulator</b></td><td>QuestaSim 2021.2_1</td>
    <td><b>Primary config</b></td><td>1&nbsp;cluster · 1&nbsp;core · 4&nbsp;warps · 4&nbsp;threads</td></tr>
<tr><td><b>Host OS</b></td><td>Ubuntu 22.04</td>
    <td><b>ISA / data width</b></td><td>RISC-V RV32IM</td></tr>
<tr><td><b>Memory interface</b></td><td>AXI4 (primary) · custom valid-ready</td>
    <td><b>Golden model</b></td><td>SimX, linked as <code>simx_model.so</code></td></tr>
<tr><td><b>DUT RTL pin</b></td><td colspan="3"><code>Vortex/</code> @ <code>7a52ee5</code></td></tr>
</table>

---

## Table of Contents

- [Quick Start](#-quick-start)
- [Repository Layout](#-repository-layout)
- [Architecture](#-architecture)
- [Tests](#-tests)
- [Configurability](#-configurability)
- [Team & Ownership](#-team--ownership)
- [Status](#-status)
- [Documentation Map](#-documentation-map)

---

## 🚀 Quick Start

```bash
cd vortex_uvm_env

# Full flow: compile RTL + UVM, build the SimX DPI library, simulate.
make sim TEST=kernel_launch_test PROGRAM_NAME=hello TIMEOUT=500000

# Re-run without recompiling the RTL.
make sim-only TEST=kernel_launch_test PROGRAM_NAME=hello

# Interactive waveform debug (Questa GUI).
make gui TEST=kernel_launch_test PROGRAM_NAME=hello

# Merge per-run coverage into a single UCDB.
make cov-merge

# All targets and flags.
make help
```

Each run writes to `vortex_uvm_env/results/<date>/run_<time>_<test>/`:

```
results/latest/
├── logs/simulation.log        # full transcript
├── reports/SUMMARY.txt        # pass/fail, config, statistics
├── reports/coverage.ucdb      # per-run coverage database
└── waves/                     # optional VCD
```

---

## 📂 Repository Layout

```
Vortex_UVM_GP/
├── Vortex/                       # DUT — Vortex RISC-V GPGPU (pinned @ 7a52ee5)
│   ├── hw/rtl/                   #   SystemVerilog RTL (Vortex.sv, Vortex_axi.sv, …)
│   └── sim/simx/                 #   SimX C++ behavioral model (golden reference)
│
├── vortex_uvm_env/               # ◀ UVM verification environment (all work here)
│   ├── tb/                       #   vortex_tb_top.sv · vortex_if.sv (interfaces, binds, asserts)
│   ├── uvm_env/
│   │   ├── agents/               #   5 agents: mem · axi · dcr · host · status
│   │   ├── sequences/            #   virtual sequences (kernel launch, mem, stress)
│   │   ├── ref_model/            #   SimX DPI bridge (simx_dpi.cpp, simx_pkg.sv, .so)
│   │   ├── vortex_env.sv         #   environment
│   │   ├── vortex_config.sv      #   configuration object (derived from RTL params)
│   │   ├── vortex_scoreboard.sv  #   end-state comparison vs SimX
│   │   └── vortex_coverage_collector.sv
│   ├── uvm_tests/                #   test library (see Tests)
│   ├── scripts/                  #   run.sh → prepare.sh → compile.sh → simulate.sh
│   ├── flists/  cov/  results/   #   file lists · coverage staging · run outputs
│   └── docs/                     #   guidance, plan, per-fix writeups (docs/fixes/)
│
├── CLAUDE.md                     # working context + authoritative live checklist
└── README.md                     # this file
```

> Full directory rationale: [`vortex_uvm_env/docs/FILE_TREE.md`](vortex_uvm_env/docs/FILE_TREE.md)

---

## 🏗 Architecture

```
        ┌────────────────────── vortex_tb_top ──────────────────────┐
        │                                                           │
  DCR / host ──▶ │ dcr_agent │ host_agent │                         │
        │                       │                                   │
   program ──▶   Vortex DUT (RTL) ──▶ AXI / mem bus ──▶ mem_model   │
        │                  │   ▲                                    │
        │      │ status_agent │ │ axi_agent / mem_agent │ (monitors)│
        │                  │                                        │
        │                  ▼  analysis ports                        │
        │            vortex_scoreboard ───── DPI ─────▶ SimX (gold) │
        │                  │                                        │
        │            vortex_coverage_collector                      │
        └───────────────────────────────────────────────────────────┘
```

### Agents → RTL interfaces

| Agent | RTL interface | Protocol | Role |
| :--- | :--- | :--- | :--- |
| `axi_agent` | AXI4 (`Vortex_axi.sv`) | AXI4 · 5 channels | **primary** memory |
| `mem_agent` | custom memory (`Vortex.sv`) | valid-ready | alt memory path |
| `dcr_agent` | device config regs | write-only | startup PC, perf config |
| `host_agent` | kernel launch (via DCR) | DCR-based | start execution |
| `status_agent` | status / busy | passive | observe completion |

> Signal-level mapping (widths, line refs): [`docs/INTERFACE_MAPPING.md`](vortex_uvm_env/docs/INTERFACE_MAPPING.md)

### Completion & comparison

- **Primary trigger** — the TB decodes the real `ebreak` (`0x00100073`) at the
  fetch stage across **all** cores.
- **Fallbacks** — sustained `busy == 0`, then an idle watchdog (both warn).
- On completion the scoreboard runs SimX to the same point and compares the
  data-region memory. Instruction count and IPC are derived from the real
  `commit_arb_if[*]` retirement handshake — not a heuristic.

---

## 🧪 Tests

Located in [`vortex_uvm_env/uvm_tests/`](vortex_uvm_env/uvm_tests/) — select with `TEST=<name>`:

| Test | Focus |
| :--- | :--- |
| `vortex_smoke_test` · `vortex_sanity_test` | bring-up / connectivity |
| `kernel_launch_test` | end-to-end kernel (hello, vecadd) vs SimX |
| `functional_memory_test` · `axi_memory_test` | memory correctness / AXI compliance |
| `warp_scheduling_test` · `barrier_sync_test` | scheduler / synchronization |
| `random_instruction_stress_test` | constrained-random (riscv-dv) pipeline stress |
| `negative_result_test` | fault-injection guard — **must go RED on injection** |

`PROGRAM_NAME=<kernel>` resolves an ELF under `Vortex/tests/kernel/<name>/`.
`riscv_*` programs are generated and compiled through the riscv-dv pipeline in
[`prepare.sh`](vortex_uvm_env/scripts/prepare.sh).

---

## ⚙ Configurability

The environment is parameterized and validated against the compiled RTL at
elaboration. Override any knob per run:

```bash
make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd \
         INTERFACE=axi CLUSTERS=1 CORES=1 WARPS=4 THREADS=4 TIMEOUT=1000000
```

> [!IMPORTANT]
> **Elaboration asserts** check the UVM topology and tag widths against the
> compiled DUT (`NUM_CLUSTERS/CORES/WARPS/THREADS`, `VX_MEM_TAG_WIDTH`). A stale
> `sim-only` run with mismatched parameters **aborts loudly** at time 0 instead
> of silently producing garbage.

---

## 👥 Team & Ownership

A group project to one shared plan; each owner stays in lane and flags
shared-file changes.

| Owner | Lane |
| :--- | :--- |
| **Samuel** | infrastructure correctness + full configurability (TB, config, scripts, asserts) · constrained-random (riscv-dv) testing |
| **Ahmad** | functional & code coverage + scoreboard |
| **Steven** | directed tests, AXI SVA, SimX / DPI |

Cross-lane edits and handovers are documented per issue in
[`docs/fixes/`](vortex_uvm_env/docs/fixes/) — including a CRITICAL scoreboard
[handover](vortex_uvm_env/docs/fixes/HANDOVER_Ahmad_scoreboard_dropped_stores.md)
and the engineering
[evaluation](vortex_uvm_env/docs/fixes/EVALUATION_2026-06-26.md).

---

## 📊 Status

A snapshot of the environment's current capabilities. Detailed per-task tracking
lives in the [rolling plan](vortex_uvm_env/docs/Vortex_UVM_Plan_Current.md).

**Operational**

| ✔ | Capability |
| :---: | :--- |
| ✅ | End-to-end kernel execution compared against the SimX golden model |
| ✅ | Constrained-random instruction stress testing (riscv-dv pipeline) |
| ✅ | 5-agent UVM architecture over AXI4 and custom memory interfaces |
| ✅ | Functional + code coverage collection with cross-run merge |
| ✅ | Full parameterization with elaboration-time validation against the DUT |
| ✅ | Trustworthy results: real retirement counts, honest error gating, decoded completion |

**In progress**

| 🔄 | Item |
| :---: | :--- |
| 🔄 | Scoreboard detection of *dropped* stores (currently DUT-write-driven) |
| 🔄 | Completion path for long-running kernels (e.g. vecadd) |
| 🔄 | Multi-config matrix run and merged sign-off report |

---

## 📚 Documentation Map

| Document | Purpose |
| :--- | :--- |
| [`docs/README.md`](vortex_uvm_env/docs/README.md) | environment overview (original spec) |
| [`docs/FILE_TREE.md`](vortex_uvm_env/docs/FILE_TREE.md) | intended directory structure |
| [`docs/INTERFACE_MAPPING.md`](vortex_uvm_env/docs/INTERFACE_MAPPING.md) | RTL interface → UVM agent mapping |
| [`docs/DELIVERABLES_SUMMARY.md`](vortex_uvm_env/docs/DELIVERABLES_SUMMARY.md) | deliverables checklist |
| [`docs/Vortex_UVM_Plan_Current.md`](vortex_uvm_env/docs/Vortex_UVM_Plan_Current.md) | rolling task plan |
| [`docs/fixes/`](vortex_uvm_env/docs/fixes/) | per-issue fix writeups + review artifacts |
| [`docs/AXI_SVA_report.md`](vortex_uvm_env/docs/AXI_SVA_report.md) | AXI assertions report |
| [`docs/GLIBCXX_*`](vortex_uvm_env/docs/) | DPI / Questa libstdc++ toolchain notes |

---

## License & Attribution

The Vortex DUT RTL and SimX model are vendored under their upstream license —
see [`Vortex/LICENSE`](Vortex/LICENSE). The UVM verification environment in
[`vortex_uvm_env/`](vortex_uvm_env/) is coursework authored by the team above.

<div align="center">
<sub>Built on the Vortex GPGPU · Verified with UVM 1.2 on QuestaSim · SimX golden reference via DPI-C</sub>
</div>
