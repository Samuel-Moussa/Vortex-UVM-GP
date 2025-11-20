# Vortex GPGPU UVM Verification Environment

## Introduction

This directory contains a complete UVM (Universal Verification Methodology) verification environment for the Vortex GPGPU. It is designed to be a reusable, modular, and scalable solution for verifying the functional correctness of the Vortex RTL design.

## Features

- **Modular UVM Agents**: Separate agents for each interface (custom memory, AXI4, DCR, host).
- **Reference Model Integration**: Scoreboard with DPI-C integration for the `simx` C++ behavioral model.
- **Comprehensive Test Suite**: Includes smoke tests, functional tests, and stress tests.
- **Multi-Simulator Support**: Scripts for Verilator (open-source) and commercial simulators (VCS/Questa).
- **Functional Coverage**: Built-in coverage collectors for key GPU features.

## Directory Structure

Please refer to the `FILE_TREE.md` document for a detailed breakdown of the directory structure.

## Getting Started

### Prerequisites

- A SystemVerilog simulator that supports UVM (e.g., Verilator, Synopsys VCS, Mentor Questa).
- The Vortex GPGPU source code.
- A C++ compiler for building the `simx` reference model and DPI-C wrapper.

### Configuration

1.  **Set up the Vortex source**: Ensure the `VORTEX_HOME` environment variable points to the root of the Vortex repository.
2.  **Configure paths**: Update the simulation scripts in the `sim/` directory to point to your simulator installation and the Vortex source code.

### Running a Smoke Test with Verilator

1.  **Navigate to the Verilator simulation directory**:

    ```bash
    cd sim/verilator
    ```

2.  **Compile the testbench**:

    ```bash
    ./compile.sh
    ```

3.  **Run the simulation**:

    ```bash
    ./run.sh
    ```

    This will run the `smoke_test` and generate a waveform file (`simx.vcd`) for debugging.

## Extending the Environment

### Adding a New Test

1.  Create a new test file in the `uvm_tests/` directory, extending from `vortex_base_test`.
2.  In the `run_phase` of your new test, create and start a sequence.
3.  Add your new test to the regression test list (`uvm_tests/regression_test_list.f`).

### Adding a New Sequence

1.  Create a new sequence file in the `uvm_env/sequences/` directory, extending from `vortex_base_sequence`.
2.  In the `body` of your sequence, create and randomize transactions, and send them to the appropriate agent's sequencer.

## Verification Plan

For a detailed overview of the verification strategy, testcases, and coverage goals, please refer to the `VERIFICATION_PLAN.md` document.
