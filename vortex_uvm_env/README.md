# Vortex UVM Verification Environment

The UVM environment for the Vortex RISC-V GPGPU. For the project overview,
architecture, and results, see the [top-level README](../README.md); this file
is the build-and-extend reference for the environment itself.

## Method

Black-box **end-state equivalence**: the DUT and the **SimX** C++ golden model
run the same program from the same configuration; the scoreboard compares the
final memory, console, and exit state over a DPI-C bridge.

## Prerequisites

- **QuestaSim 2021.2+** (the flow auto-detects `vsim`).
- A **RISC-V toolchain** — `riscv{32,64}-unknown-elf` GCC/LLVM 14.
- A **C++17 compiler** to build the SimX model into `simx_model.so`.
- Host: Ubuntu 22.04 (validated under WSL2).

## Running

All flows go through the `Makefile`, which drives four sourced scripts —
`run.sh → prepare.sh → compile.sh → simulate.sh`:

```bash
# Full flow: build SimX DPI lib, compile RTL + UVM, simulate.
make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite TIMEOUT=200000

# Re-run without recompiling the RTL.
make sim-only TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite

# Waveform debug in the Questa GUI.
make gui TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite

# Full regression suite (48 runs) + coverage merge.
bash scripts/run_suite.sh

make help          # all targets and flags
```

`PROGRAM_NAME=<kernel>` resolves an ELF under `../Vortex/tests/kernel/<name>/`.
`riscv_*` programs are generated and compiled through the riscv-dv pipeline in
`prepare.sh` (see [`docs/RISCV_DV_GUIDE.md`](docs/RISCV_DV_GUIDE.md)).

### Configuration

One parameter set drives the RTL (`+define+`), SimX (`-D` macros, recompiled per
config), and the testbench (runtime `+plusargs`). Elaboration asserts abort at
time 0 if the testbench topology disagrees with the compiled DUT.

```bash
make sim TEST=kernel_launch_test PROGRAM_NAME=vecadd_lite \
         CLUSTERS=2 CORES=2 WARPS=4 THREADS=4 INTERFACE=axi TIMEOUT=200000
```

## Structure

```
vortex_uvm_env/
├── tb/                 vortex_tb_top.sv, interfaces, binds, elaboration asserts
├── uvm_env/
│   ├── agents/         axi · mem · dcr · host · status
│   ├── ref_model/      SimX DPI bridge (simx_dpi.cpp, simx_pkg.sv)
│   ├── vortex_scoreboard.sv          end-state equivalence vs SimX
│   ├── vortex_coverage_collector.sv
│   └── vortex_config.sv              config derived from RTL params
├── uvm_tests/          test library (extend vortex_base_test)
├── scripts/            run.sh, prepare.sh, compile.sh, simulate.sh, run_suite.sh,
│                       gen_coverage_exclude.sh, merge_coverage.sh
├── cov/                per-config coverage banks (bank_1CL…, bank_2CL…)
└── docs/               plan, coverage model, riscv-dv guide, fix writeups
```

## Extending

**Add a test** — create a file in `uvm_tests/` extending `vortex_base_test`,
build/start a sequence in `run_phase`, and register it in the regression list.

**Add a sequence** — create a file under `uvm_env/sequences/` extending
`vortex_base_sequence`, randomize transactions in `body`, and send them to the
target agent's sequencer.

## Documentation

- [`docs/VERIFICATION_PLAN.md`](docs/VERIFICATION_PLAN.md) — strategy, testcases, coverage goals
- [`docs/Coverage_Model_Reference.md`](docs/Coverage_Model_Reference.md) — every covergroup and its rationale
- [`docs/INTERFACE_MAPPING.md`](docs/INTERFACE_MAPPING.md) — RTL interface → UVM agent mapping
- [`docs/RISCV_DV_GUIDE.md`](docs/RISCV_DV_GUIDE.md) — constrained-random pipeline
- [`docs/fixes/`](docs/fixes/) — per-issue root-cause writeups
