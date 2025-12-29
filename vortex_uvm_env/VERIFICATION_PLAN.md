# Vortex GPGPU Verification Plan

## 1. Introduction

This document outlines the verification strategy for the Vortex GPGPU. The goal is to create a comprehensive UVM-based verification environment to ensure the functional correctness of the RTL design.

## 2. Verification Scope

### In Scope:
- Functional correctness of core GPU features:
  - Warp scheduling and control
  - Memory model (L1/L2/L3 caches, local memory)
  - Execution units (ALU, FPU, LSU, SFU)
  - Interrupts and exceptions
- Interface correctness:
  - AXI4 and custom memory interfaces
  - DCR (Device Configuration Register) interface
  - Host-to-device communication (kernel launch)
- Integration with `simx` as a reference model.

### Out of Scope:
- Physical layer verification (FPGA-specific I/O)
- Performance verification (timing, power)
- Formal verification

## 3. UVM Environment Architecture

The UVM environment will consist of the following key components:
- **Agents**: For each interface (AXI, custom memory, DCR, host).
- **Scoreboard**: To compare RTL results against the `simx` reference model.
- **Sequences**: A library of directed and constrained-random tests.
- **Coverage**: Functional coverage collectors.
- **Testbench**: Top-level module with DUT, interfaces, and UVM test harness.

## 4. Testcase Plan

| Test Name                      | Description                                                                 | Priority |
| ------------------------------ | --------------------------------------------------------------------------- | -------- |
| `smoke_test`                   | Basic reset and DCR write/read test.                                        | High     |
| `functional_memory_test`       | Verifies memory read/write operations through the memory interface.         | High     |
| `axi_memory_test`              | Verifies memory read/write operations through the AXI4 interface.           | High     |
| `kernel_launch_test`           | Tests the ability to launch a simple kernel (e.g., `vecadd`).               | High     |
| `warp_scheduling_test`         | Verifies correct warp scheduling and context switching.                     | Medium   |
| `barrier_sync_test`            | Tests barrier synchronization among threads.                                | Medium   |
| `random_instruction_stress_test` | Executes a constrained-random stream of instructions to stress the pipeline. | Medium   |
| `cache_coherence_test`         | Verifies coherence between L1, L2, and L3 caches.                           | Low      |

## 5. Coverage Goals

### Functional Coverage:
- **Instruction Coverage**: Cover all instruction opcodes and formats.
- **Warp Scheduling**: Cover all warp states and scheduling scenarios.
- **Memory Scenarios**: Cover various memory access patterns (aligned, unaligned, contention).
- **Exceptions/Interrupts**: Cover all exception and interrupt types.

### Structural Coverage:
- **Toggle Coverage**: Aim for >90% toggle coverage on all major modules.
- **Line Coverage**: Aim for >95% line coverage.

## 6. Acceptance Criteria

- All high-priority testcases pass.
- Functional coverage goals are met.
- A smoke test can be run successfully with both Verilator and a commercial simulator.
- The scoreboard successfully compares RTL results with the `simx` reference model for a simple kernel.
