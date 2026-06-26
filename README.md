# Vortex GPGPU — UVM Verification Environment

A UVM verification environment for the [Vortex](https://github.com/vortexgpgpu/vortex)
open-source RISC-V GPGPU, built to the mentor's specification (5-agent layout,
interface mapping, SimX golden reference, functional + structural coverage). The
DUT RTL lives in `Vortex/`; the verification environment lives in
`vortex_uvm_env/`.

> **Method:** black-box end-state equivalence. The DUT runs a program to
> completion; the **SimX** software model runs the same program via DPI; the
> scoreboard compares the final architectural memory state. SimX is the golden
> reference.

---

## Quick start

```bash
cd vortex_uvm_env

# Full flow (compile RTL + UVM, build SimX DPI, simulate):
make sim TEST=kernel_launch_test PROGRAM_NAME=hello TIMEOUT=500000

# Re-run without recompiling the RTL:
make sim-only TEST=kernel_launch_test PROGRAM_NAME=hello

# GUI (Questa):
make gui TEST=kernel_launch_test PROGRAM_NAME=hello

# Coverage merge across runs:
make cov-merge          # merge staged UCDBs
make help               # all flags
```

A run drops results in `vortex_uvm_env/results/<date>/run_<time>_<test>/`
(`logs/simulation.log`, `reports/SUMMARY.txt`, `reports/coverage.ucdb`,
optional `waves/`). `results/latest` symlinks the most recent.

### Toolchain / environment
| Item | Value |
|------|-------|
| Simulator | QuestaSim 2021.2_1 |
| OS | Ubuntu 22.04 |
| Primary config | **1 cluster / 1 core / 4 warps / 4 threads**, RV32, **AXI** memory interface |
| Golden model | SimX (C++), linked as `simx_model.so` via DPI-C |
| RTL pin | `Vortex/` @ `7a52ee5` |

Config is parameterized — override per run:
`make sim ... CLUSTERS=2 CORES=2 WARPS=4 THREADS=4 INTERFACE=axi`.
Topology plusargs are checked against the compiled RTL at elaboration (see
**I2 asserts**), so a stale `sim-only` with mismatched params aborts loudly
instead of producing garbage.

---

## Repository layout

```
Vortex_UVM_GP/
├── Vortex/                       # DUT — Vortex RISC-V GPGPU RTL + SimX model (pinned)
│   ├── hw/rtl/                   #   SystemVerilog RTL (Vortex.sv, Vortex_axi.sv, ...)
│   └── sim/simx/                 #   SimX C++ behavioral model (golden reference)
├── vortex_uvm_env/               # UVM verification environment  ← work happens here
│   ├── tb/                       #   vortex_tb_top.sv, vortex_if.sv (interfaces + binds)
│   ├── uvm_env/                  #   env, config, scoreboard, coverage, virtual sequencer
│   │   ├── agents/               #     5 agents: mem, axi, dcr, host, status
│   │   ├── sequences/            #     virtual sequences (kernel launch, mem, stress)
│   │   └── ref_model/            #     SimX DPI bridge (simx_dpi.cpp, simx_pkg.sv, .so)
│   ├── uvm_tests/                #   test library (see Tests below)
│   ├── scripts/                  #   run.sh → prepare.sh → compile.sh → simulate.sh
│   ├── flists/                   #   RTL + UVM file lists
│   ├── cov/ results/ trace/      #   coverage staging, run outputs, traces
│   └── docs/                     #   mentor guidance + plan + per-fix writeups (docs/fixes/)
├── CLAUDE.md                     # Samuel's working context + live task checklist
└── README.md                     # this file
```

The full intended file tree and rationale are in
[vortex_uvm_env/docs/FILE_TREE.md](vortex_uvm_env/docs/FILE_TREE.md).

---

## Architecture

```
        +------------------- vortex_tb_top -------------------+
        |                                                     |
  DCR / host  ──▶ [dcr_agent] [host_agent]                    |
        |            │                                         |
        |            ▼                                         |
  program ──▶  Vortex DUT (RTL)  ──▶ AXI / mem bus ──▶ mem_model
        |            │  ▲                                      |
        |   [status_agent] [axi_agent / mem_agent]  (monitors) |
        |            │                                         |
        |            ▼  analysis ports                         |
        |        vortex_scoreboard ──── DPI ───▶ SimX (golden) |
        |            │                                         |
        |        vortex_coverage_collector                     |
        +-----------------------------------------------------+
```

### The 5 agents → RTL interfaces
Mapping detail (signals, widths, line refs) in
[vortex_uvm_env/docs/INTERFACE_MAPPING.md](vortex_uvm_env/docs/INTERFACE_MAPPING.md).

| Agent | RTL interface | Protocol | Role |
|-------|---------------|----------|------|
| `mem_agent` | custom memory (`Vortex.sv`) | valid-ready | active/passive mem |
| `axi_agent` | AXI4 (`Vortex_axi.sv`) | AXI4, 5 channels | **primary** mem interface |
| `dcr_agent` | device config regs | write-only | startup PC, perf config |
| `host_agent` | kernel launch (via DCR) | DCR-based | start execution |
| `status_agent` | status/busy | passive | observe busy, completion |

### Completion + reference comparison
- The TB decodes the real **ebreak** (`0x00100073`) at the fetch stage across all
  cores as the **primary** completion trigger; sustained `busy==0` and an idle
  watchdog are fallbacks.
- On completion the scoreboard runs SimX to the same point and compares the
  data-region memory. Instruction count and IPC come from the real
  `commit_arb_if[*]` retirement handshake (not a heuristic).

---

## Tests

`vortex_uvm_env/uvm_tests/` (run with `TEST=<name>`):

| Test | Focus |
|------|-------|
| `vortex_smoke_test`, `vortex_sanity_test` | bring-up / connectivity |
| `kernel_launch_test` | end-to-end kernel (hello, vecadd) vs SimX |
| `functional_memory_test`, `axi_memory_test` | memory correctness / AXI compliance |
| `warp_scheduling_test`, `barrier_sync_test` | scheduler / sync primitives |
| `random_instruction_stress_test` | constrained-random (riscv-dv) pipeline stress |
| `negative_result_test` | fault-injection guard — must go RED on injection |

`PROGRAM_NAME=<kernel>` resolves a kernel ELF under
`Vortex/tests/kernel/<name>/`. `riscv_*` programs are generated and compiled
through the riscv-dv pipeline in `prepare.sh`.

---

## Team lanes

This is a group project to one shared plan. Each owner stays in their lane and
flags shared-file changes.

| Owner | Lane |
|-------|------|
| **Samuel** | infrastructure correctness + full configurability (TB, config, scripts, elaboration asserts) |
| **Ahmad** | functional/code coverage + scoreboard |
| **Steven** | directed/random tests, AXI SVA, SimX/DPI |

Cross-lane edits and handovers are documented per-issue in
[vortex_uvm_env/docs/fixes/](vortex_uvm_env/docs/fixes/) — start at its
[README](vortex_uvm_env/docs/fixes/README.md). Notable: a CRITICAL scoreboard
handover ([dropped-stores](vortex_uvm_env/docs/fixes/HANDOVER_Ahmad_scoreboard_dropped_stores.md))
and the engineering [evaluation](vortex_uvm_env/docs/fixes/EVALUATION_2026-06-26.md).

---

## Status (2026-06-26)

**Bench-trust (Gate 0) — Samuel's items complete:**
- ✅ Tag/ID width derived from RTL with an elaboration `$bits` assert (C1)
- ✅ Real retired instruction count + IPC from the commit handshake (C2/I1)
- ✅ ebreak-decode completion, multi-core (C3/I1)
- ✅ Honest UVM_ERROR gate, no subtraction (T4)
- ✅ Topology elaboration asserts incl. plusarg aliases (I2)
- ✅ riscv-dv `random_instruction_stress_test` passing end-to-end

**Open before Gate-0 sign-off:**
- ⛔ Scoreboard cannot yet detect *dropped* stores (DUT-write-driven comparison) — Ahmad's lane, handover written
- ⛔ INV-1: vecadd `busy` never idles (completion path blocked for that kernel)

The authoritative, continuously-updated checklist is in
[CLAUDE.md](CLAUDE.md); the rolling plan is
[vortex_uvm_env/docs/Vortex_UVM_Plan_Current.md](vortex_uvm_env/docs/Vortex_UVM_Plan_Current.md).

---

## Documentation map

| Doc | What |
|-----|------|
| [docs/README.md](vortex_uvm_env/docs/README.md) | environment overview (original spec) |
| [docs/FILE_TREE.md](vortex_uvm_env/docs/FILE_TREE.md) | intended directory structure |
| [docs/INTERFACE_MAPPING.md](vortex_uvm_env/docs/INTERFACE_MAPPING.md) | RTL interface → UVM agent mapping |
| [docs/DELIVERABLES_SUMMARY.md](vortex_uvm_env/docs/DELIVERABLES_SUMMARY.md) | deliverables checklist |
| [docs/Vortex_UVM_Plan_Current.md](vortex_uvm_env/docs/Vortex_UVM_Plan_Current.md) | rolling task plan |
| [docs/fixes/](vortex_uvm_env/docs/fixes/) | per-issue fix writeups + review artifacts |
| [docs/AXI_SVA_report.md](vortex_uvm_env/docs/AXI_SVA_report.md) | AXI assertions report |
| [docs/GLIBCXX_*](vortex_uvm_env/docs/) | DPI/Questa libstdc++ toolchain notes |
