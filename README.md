# UVM Verification Environment for the Vortex RISC-V Processor

This repository contains an industrial-grade UVM (Universal Verification Methodology) environment for the functional verification of the Vortex RISC-V processor. The environment is built upon the OpenHW Group's [core-v-verif](https://github.com/openhwgroup/core-v-verif) framework and is configured to use Questasim as the primary simulator.

The primary goal of this project is to create a robust, reusable, and scalable testbench to thoroughly verify the Vortex processor's compliance with the RISC-V ISA specification, including its `RV32IMAF` and `RV64IMAFD` variants.

## Key Features

  * **UVM-Based:** Leverages the full power of the Universal Verification Methodology for a structured, scalable, and reusable testbench architecture.
  * **Step-and-Compare Verification:** Employs a lock-step comparison methodology, running test programs on both the Vortex RTL (DUT) and a golden reference model (Spike ISS) to detect any architectural state mismatches in real-time.
  * **Constrained-Random Stimulus:** Utilizes `corev-dv`, an extension of Google's powerful `riscv-dv` instruction stream generator, to create complex and random test programs that target corner-case scenarios.
  * **Submodule Integration:** The `core-v-verif` framework and the Vortex RTL are integrated as Git submodules, ensuring a clean separation between the verification environment and the design source code.

## Directory Structure

The repository is organized to separate the core design, the verification framework, and the project-specific verification IP.
Vortex_UVM_GP/
├── core-v-verif/
│   ├── cv32e40p/
│   │   ├── tb/
│   │   │   └── uvmt/
│   │   │       ├── uvmt_cv32e40p.flist
│   │   │       ├── uvmt_cv32e40p_tb.sv
│   │   │       ├── uvmt_cv32e40p_dut_wrap.sv
│   │   │       ├── uvmt_cv32e40p_iss_wrap.sv
│   │   │       └── uvmt_cv32e40p_step_compare.sv
│   │   ├── sim/
│   │   │   └── uvmt/
│   │   │       └── vsim_results/
│   │   └── tests/
│   │       └── programs/
│   │           └── custom/hello-world/hello-world.elf
│   └── mk/
├── core-v-verif.bak/
├── docs/
├── env/
├── results/
├── tools/
└── Vortex/

````

## Prerequisites

To use this environment, the following tools must be installed and configured on an **Ubuntu 22.04 LTS** system:

1.  **Questasim (2021.2 or later):** An industrial-grade SystemVerilog simulator.
2.  **RISC-V GCC Toolchain:** A pre-built, "multilib" compatible toolchain is required. The official([https://github.com/openhwgroup/cvw](https://github.com/openhwgroup/cvw)) is recommended.
3.  **Spike:** The RISC-V ISA Simulator, used as the golden reference model.
4.  **Python 3:** With the packages specified in `core-v-verif/bin/requirements.txt`.
5.  **Standard Build Utilities:** `git`, `make`, `build-essential`, etc.

## Environment Setup

Follow these steps to configure the simulation environment.

### 1. Clone the Repository

Clone this repository **recursively** to ensure the `core-v-verif` and `Vortex` submodules are also downloaded.

```bash
git clone --recursive <your-repository-url>
cd Vortex_UVM_GP
````

### 2\. Configure Shell Environment Variables

The `core-v-verif` build system relies on environment variables to locate tools. Add the following to your `~/.bashrc` file, ensuring the paths match your local installation.

```bash
# === UVM Verification Environment Setup ===

# 1. Set the target simulator to Questasim
export CV_SIMULATOR="vsim"

# 2. Set the path to the RISC-V toolchain installation directory
export RISCV="$HOME/riscv"
export PATH="$RISCV/bin:$PATH"

# 3. Set the path to the Spike ISS (Instruction Set Simulator) executable
export SPIKE_PATH="$HOME/riscv/bin"

# 4. Set the path to the UVM library included with your Questasim installation
export UVM_HOME="/opt/questa_sim-2021.2_1/questasim/uvm-1.2"

# 5. Set the RISC-V architecture to include the Zicsr extension for modern toolchains
export CV_SW_MARCH="rv32imc_zicsr"

# 6. Set the C Flags to enforce the correct soft-float ABI for all compile steps
export CV_SW_CFLAGS="-O2 -g -static -mabi=ilp32 -march=$CV_SW_MARCH"
```

After editing, apply the changes to your current session:

```bash
source ~/.bashrc
```

## Running a Sanity Test

To validate that the entire toolchain and environment are correctly configured, you can run the baseline `hello-world` smoke test from the `cv32e40p` UVM environment.

1.  Navigate to the simulation directory:
    ```bash
    cd core-v-verif/cv32e40p/sim/uvmt
    ```
2.  Clean any previous builds and run the test:
    ```bash
    make clean
    make test TEST=hello-world
    ```

A successful run will compile the test program, build the entire UVM testbench in Questasim, and finish with a `SIMULATION PASSED` message.

## Project Roadmap

The verification of the Vortex processor will be conducted in two main phases.

### Phase 1: RV32IMAF Verification

The initial phase focuses on bringing up and verifying the 32-bit configuration of the Vortex core.

1.  **Develop the DUT Wrapper:** Create a custom SystemVerilog wrapper in `env/tb/` to instantiate the Vortex core and connect its physical interfaces to the generic UVM interfaces provided by `core-v-verif`.
2.  **Configure the UVM Environment:** Extend the base UVM environment to configure agents, scoreboards, and coverage models for the Vortex architecture.
3.  **Run Compliance Tests:** Execute the standard RISC-V compliance test suite to ensure baseline ISA functionality.
4.  **Enable Constrained-Random Testing:** Use `corev-dv` to generate a high volume of random tests to uncover architectural bugs and achieve high coverage.

### Phase 2: RV64IMAFD Extension

Once the 32-bit environment is stable, it will be extended to support the 64-bit Vortex variant with double-precision floating-point.

1.  **Parameterize the Environment:** Update all data paths, transaction objects, and interfaces to be 64-bit compatible.
2.  **Reconfigure Stimulus Generation:** Update the `corev-dv` configuration to generate `rv64imafd` instruction streams.
3.  **Update Reference Model:** Configure Spike to run as a 64-bit golden model.
4.  **Extend Functional Coverage:** Add coverage points for 64-bit operations and the D-extension instructions.

## Advanced Verification: HW/SW Co-Simulation

In addition to UVM-based verification, this project may also leverage a full Hardware/Software Co-Simulation methodology, as detailed in resources like the([https://www.reds.com.es/blog/zynq-7000-hw-sw-co-simulation-qemu-questasim/](https://www.google.com/search?q=https://www.reds.com.es/blog/zynq-7000-hw-sw-co-simulation-qemu-questasim/)). This approach enables end-to-end system-level testing by running the full software stack on an emulated host while simulating the RTL in a cycle-accurate simulator.

### Methodology: QEMU + QuestaSim

  * **QEMU (Host System Emulation):** The QEMU emulator will be used to model a complete host system, such as a Xilinx Zynq-7000 SoC with its ARM-based Processing System (PS). QEMU runs the entire software stack, including a full Linux OS, the Vortex kernel driver, and user-space applications like OpenCL programs.
  * **QuestaSim (RTL Simulation):** QuestaSim runs the cycle-accurate simulation of the Vortex GPGPU RTL. In the context of a Zynq-based system, this represents the accelerator implemented in the Programmable Logic (PL).
  * **DPI-C Bridge:** A high-performance communication bridge connects QEMU and QuestaSim. This bridge, typically implemented using SystemVerilog DPI-C, allows the software running in QEMU to send commands and data (e.g., MMIO writes, DMA transfers) to the RTL design and receive responses back.

### Benefits for Vortex Verification

This co-simulation flow is invaluable for finding deep system-level integration bugs that are difficult to expose with UVM alone. It allows for the verification of:

  * **Full Software Stack:** End-to-end testing of the entire software chain, from user application to kernel driver.
  * **Driver/Hardware Interaction:** Debugging complex interactions, race conditions, and synchronization issues between the driver and the RTL.
  * **Performance Analysis:** Identifying system-level performance bottlenecks by running realistic, long-duration software workloads.

<!-- end list -->

```
```
