# Vortex GPGPU UVM Verification Environment - File Tree

```
vortex_uvm_env/
├── README.md                           # Main documentation and quick start guide
├── VERIFICATION_PLAN.md                # Detailed verification plan
├── FILE_TREE.md                        # This file - directory structure
│
├── uvm_env/                            # Main UVM environment package
│   ├── vortex_pkg.sv                   # Top-level UVM package
│   ├── vortex_env.sv                   # Top-level UVM environment
│   ├── vortex_config.sv                # Configuration object
│   ├── vortex_scoreboard.sv            # Main scoreboard with simx integration
│   ├── vortex_coverage.sv              # Functional coverage collector
│   │
│   ├── agents/                         # UVM agents for each interface
│   │   ├── mem_agent/                  # Memory interface agent (custom protocol)
│   │   │   ├── mem_agent_pkg.sv        # Memory agent package
│   │   │   ├── mem_agent.sv            # Memory agent
│   │   │   ├── mem_driver.sv           # Memory driver
│   │   │   ├── mem_monitor.sv          # Memory monitor
│   │   │   ├── mem_sequencer.sv        # Memory sequencer
│   │   │   ├── mem_transaction.sv      # Memory transaction class
│   │   │   └── mem_sequences.sv        # Memory sequence library
│   │   │
│   │   ├── axi_agent/                  # AXI4 interface agent
│   │   │   ├── axi_agent_pkg.sv        # AXI agent package
│   │   │   ├── axi_agent.sv            # AXI agent
│   │   │   ├── axi_driver.sv           # AXI driver
│   │   │   ├── axi_monitor.sv          # AXI monitor
│   │   │   ├── axi_sequencer.sv        # AXI sequencer
│   │   │   ├── axi_transaction.sv      # AXI transaction class
│   │   │   └── axi_sequences.sv        # AXI sequence library
│   │   │
│   │   ├── dcr_agent/                  # DCR (Device Config Register) agent
│   │   │   ├── dcr_agent_pkg.sv        # DCR agent package
│   │   │   ├── dcr_agent.sv            # DCR agent
│   │   │   ├── dcr_driver.sv           # DCR driver
│   │   │   ├── dcr_monitor.sv          # DCR monitor
│   │   │   ├── dcr_sequencer.sv        # DCR sequencer
│   │   │   ├── dcr_transaction.sv      # DCR transaction class
│   │   │   └── dcr_sequences.sv        # DCR sequence library
│   │   │
│   │   ├── host_agent/                 # Host/Driver interface agent
│   │   │   ├── host_agent_pkg.sv       # Host agent package
│   │   │   ├── host_agent.sv           # Host agent
│   │   │   ├── host_driver.sv          # Host driver (kernel launch, etc.)
│   │   │   ├── host_monitor.sv         # Host monitor
│   │   │   ├── host_sequencer.sv       # Host sequencer
│   │   │   ├── host_transaction.sv     # Host transaction class
│   │   │   └── host_sequences.sv       # Host sequence library
│   │   │
│   │   └── status_agent/               # Status/control signal agent
│   │       ├── status_agent_pkg.sv     # Status agent package
│   │       ├── status_agent.sv         # Status agent
│   │       ├── status_monitor.sv       # Status monitor (busy signal, etc.)
│   │       └── status_transaction.sv   # Status transaction class
│   │
│   ├── sequences/                      # Virtual sequences and sequence library
│   │   ├── vortex_base_sequence.sv     # Base virtual sequence
│   │   ├── vortex_reset_sequence.sv    # Reset sequence
│   │   ├── vortex_kernel_sequence.sv   # Kernel launch sequence
│   │   ├── vortex_memory_sequence.sv   # Memory operation sequences
│   │   ├── vortex_barrier_sequence.sv  # Barrier/sync sequences
│   │   └── vortex_random_sequence.sv   # Randomized stress sequences
│   │
│   └── ref_model/                      # Reference model integration
│       ├── simx_wrapper.sv             # SystemVerilog wrapper for simx
│       ├── simx_dpi.c                  # DPI-C interface to simx
│       ├── simx_predictor.sv           # UVM predictor using simx
│       └── simx_comparator.sv          # Transaction comparator
│
├── uvm_tests/                          # UVM test library
│   ├── vortex_test_pkg.sv              # Test package
│   ├── vortex_base_test.sv             # Base test class
│   ├── smoke_test.sv                   # Basic smoke test
│   ├── functional_memory_test.sv       # Memory read/write test
│   ├── warp_scheduling_test.sv         # Warp scheduling test
│   ├── stress_random_instr_test.sv     # Random instruction stress test
│   ├── cache_coherence_test.sv         # Cache coherence test
│   ├── barrier_sync_test.sv            # Barrier synchronization test
│   └── regression_test_list.f          # Regression test list
│
├── tb/                                 # Testbench top-level files
│   ├── vortex_tb_top.sv                # Testbench top module
│   ├── vortex_if.sv                    # Interface bundle
│   ├── vortex_dut_wrapper.sv           # DUT wrapper
│   └── vortex_assertions.sv            # SVA assertions
│
├── sim/                                # Simulation scripts and makefiles
│   ├── verilator/                      # Verilator simulation
│   │   ├── Makefile                    # Verilator makefile
│   │   ├── compile.sh                  # Compile script
│   │   ├── run.sh                      # Run script
│   │   ├── sim_main.cpp                # Verilator C++ main
│   │   └── verilator_config.vlt        # Verilator configuration
│   │
│   ├── vcs/                            # Synopsys VCS simulation
│   │   ├── Makefile                    # VCS makefile
│   │   ├── compile.sh                  # Compile script
│   │   ├── run.sh                      # Run script
│   │   └── vcs.f                       # VCS file list
│   │
│   ├── questa/                         # Mentor Questa simulation
│   │   ├── Makefile                    # Questa makefile
│   │   ├── compile.sh                  # Compile script
│   │   ├── run.sh                      # Run script
│   │   └── questa.f                    # Questa file list
│   │
│   └── common/                         # Common simulation files
│       ├── rtl_files.f                 # RTL file list
│       ├── uvm_files.f                 # UVM file list
│       └── defines.vh                  # Common defines
│
├── examples/                           # Example tests and usage
│   ├── smoke_test_example/             # Smoke test example
│   │   ├── run_verilator.sh            # Run with Verilator
│   │   ├── run_vcs.sh                  # Run with VCS
│   │   └── expected_output.log         # Expected output
│   │
│   └── kernel_test_example/            # Kernel execution example
│       ├── vecadd_test.sv              # Vector add test
│       ├── run_test.sh                 # Run script
│       └── kernel.bin                  # Compiled kernel binary
│
├── docs/                               # Additional documentation
│   ├── architecture.md                 # UVM environment architecture
│   ├── extending_env.md                # How to extend the environment
│   ├── adding_tests.md                 # How to add new tests
│   ├── coverage_guide.md               # Coverage collection guide
│   └── debugging.md                    # Debugging guide
│
└── scripts/                            # Utility scripts
    ├── gen_filelist.sh                 # Generate file lists
    ├── run_regression.sh               # Run regression suite
    └── analyze_coverage.sh             # Coverage analysis script
```

## Directory Descriptions

### `uvm_env/`
Contains all UVM environment components including agents, sequences, scoreboard, and coverage collectors.

### `uvm_env/agents/`
Five main agents for different interfaces:
- **mem_agent**: Custom memory protocol (used by Vortex.sv)
- **axi_agent**: AXI4 interface (used by Vortex_axi.sv)
- **dcr_agent**: Device configuration register interface
- **host_agent**: Host/driver protocol for kernel launch and control
- **status_agent**: Monitors status signals (busy, interrupts, etc.)

### `uvm_env/ref_model/`
Integration with simx reference model via DPI-C for golden reference comparison.

### `uvm_tests/`
Test library with directed and random tests covering:
- Smoke tests
- Functional tests (memory, ALU, FPU, warp scheduling)
- Stress tests (random instructions, cache thrashing)
- Corner case tests (barriers, exceptions, interrupts)

### `tb/`
Testbench infrastructure including:
- Top-level testbench module
- Interface definitions
- DUT wrapper
- SystemVerilog Assertions (SVA)

### `sim/`
Simulation scripts for multiple simulators:
- **Verilator**: Open-source cycle-accurate simulator
- **VCS**: Synopsys commercial simulator
- **Questa**: Mentor/Siemens commercial simulator

### `examples/`
Working examples demonstrating how to run tests and validate setup.

### `docs/`
Comprehensive documentation for users and developers.

## Key Features

1. **Modular Design**: Each agent can be enabled/disabled per test
2. **Multi-Simulator Support**: Verilator (open-source) and VCS/Questa (commercial)
3. **Reference Model Integration**: simx integration via DPI-C
4. **Comprehensive Coverage**: Functional and structural coverage
5. **Scalable**: Supports different core/warp/thread configurations
6. **Protocol Adapters**: Support for both custom and AXI4 memory interfaces
7. **Reusable**: Can be adapted for both RTL and simx verification
