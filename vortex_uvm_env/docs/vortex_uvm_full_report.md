# Vortex GPGPU UVM Verification Environment
## Full Technical Record for Scientific Publication (Updated)

**Project:** Universal Verification Methodology (UVM) Environment for the Vortex GPGPU  
**Architecture:** RISC-V 32-bit (RV32IMAF + GPGPU extensions)  
**Simulators:** Mentor Questa (QuestaSim-64 v2021.2.1), Verilator (open-source)  
**Interface Mode:** AXI4 Memory Interface (Vortex_axi wrapper)  
**Environment Location:** ~/Vortex_UVM_GP/vortex_uvm_env/  

---

## 1. Project Background and Motivation

Vortex is an open-source, highly configurable GPGPU based on the RISC-V ISA, developed at
Georgia Tech. It supports multiple cores, warps per core, and threads per warp, making it
well suited for research-grade GPU microarchitecture studies. Unlike commercial GPU
simulators, Vortex exposes its full RTL, enabling functional verification using UVM.

This project builds a complete UVM-based verification environment for Vortex RTL. It
targets the AXI4-wrapped variant and integrates the simx C behavioral simulator as a
golden reference model through DPI-C and a UVM scoreboard.

Uniqueness:
- No prior UVM environment exists for Vortex in the public domain.
- Integrates a C reference model (simx) into UVM via DPI-C.
- Supports AXI4 and custom memory interfaces, multi-core configurations, and
  multi-simulator flows (Questa + Verilator).
- Fully parametric configuration from plusargs.

---

## 2. UVM Environment Architecture

### 2.1 Top-Level Hierarchy

The testbench top (vortex_tb_top.sv) instantiates:
- DUT: Vortex_axi RTL module
- Memory model: SV memory responding to AXI
- Interface bundles: vortex_axi_if, vortex_dcr_if, vortex_status_if
- UVM harness: run_test() launches the base test

Hierarchy:
```
vortex_tb_top.sv (DUT + interfaces + run_test)
  └── vortex_base_test.sv (creates vortex_config, sets uvm_config_db)
        └── vortex_env.sv (builds and connects all agents)
              ├── axi_agent.sv        (Active: driver + monitor + sequencer)
              ├── dcr_agent.sv        (Active: driver + monitor + sequencer)
              ├── host_agent.sv       (Active: driver + monitor + sequencer)
              ├── status_agent.sv     (Passive: monitor only)
              └── vortex_virtual_sequencer.sv (coordinates agents)
```

### 2.2 Configuration System

vortex_config.sv is the single source of truth. It is:
- Created in vortex_base_test.build_phase()
- Populated from plusargs via apply_plusargs()
- Broadcast via uvm_config_db::set()
- Retrieved by agents via uvm_config_db::get()

Key configurable parameters:
| Parameter        | Plusarg          | Default |
|------------------|------------------|---------|
| NUM_CORES        | +NUM_CORES=N     | 1       |
| NUM_WARPS        | +NUM_WARPS=N     | 4       |
| NUM_THREADS      | +NUM_THREADS=N   | 4       |
| VX_MEM_TAG_WIDTH | +MEM_TAG_WIDTH=N | derived |
| AXI_ID_WIDTH     | derived          | derived |
| CLK_PERIOD_NS    | +CLK_PERIOD=N    | 10      |
| KERNEL_HEX       | +KERNEL_HEX=file | vecadd  |

### 2.3 The Five Agents

| Agent        | Interface File     | Mode    | Protocol          |
|-------------|---------------------|---------|-------------------|
| axi_agent   | vortex_axi_if.sv    | Active  | AXI4 (5 channels) |
| dcr_agent   | vortex_dcr_if.sv    | Active  | Write-only DCR    |
| host_agent  | vortex_host_if.sv   | Active  | DCR-based control |
| status_agent| vortex_status_if.sv | Passive | Monitor only      |
| mem_agent   | vortex_mem_if.sv    | Active  | Custom valid-ready|

Each agent follows standard UVM structure:
Transaction -> Sequencer -> Driver -> DUT
                         -> Monitor -> Scoreboard

### 2.4 Virtual Sequencer and Sequences

vortex_virtual_sequencer.sv lives in vortex_env.sv and holds handles to agent sequencers:
- m_axi_sequencer
- m_dcr_sequencer
- m_host_sequencer

Tests access env.vseqr and run virtual sequences such as kernel_launch_vseq.sv, which:
1. DCR agent writes kernel parameters (address, warps, threads)
2. Host agent asserts start register
3. AXI agent responds to DUT memory requests
4. Status agent monitors busy for completion

### 2.5 Reference Model Integration

simx is integrated via DPI-C:
- simx_dpi.c: C wrapper exposing simx functions
- simx_wrapper.sv: SystemVerilog DPI imports
- vortex_scoreboard.sv: compares RTL transactions vs simx golden output

Reference model dataflow (per transaction class):
1) Monitor samples RTL transaction (AXI, DCR, status).
2) Transaction forwarded to scoreboard via analysis port.
3) Scoreboard drives equivalent stimulus into simx via DPI.
4) Scoreboard compares RTL outputs vs simx outputs.
5) Mismatches reported as UVM_ERROR with address and beat context.

### 2.6 Microarchitecture Context (From Vortex Docs)

The RTL under verification implements a SIMT execution model with warp-based scheduling
and a 6-stage pipeline (Schedule, Fetch, Decode, Issue, Execute, Commit). Each thread
has its own register file (32 int + 32 FP), while warps share a PC and thread mask. The
issue stage includes an ibuffer, scoreboard, and operands collector, and the execute
stage includes ALU, FPU, LSU, SFU, and TCU units. This context shapes the verification focus
on warp scheduling, divergence handling, and memory hazards.

### 2.7 Cache Subsystem Context (From Vortex Docs)

The cache subsystem is multi-bank, non-blocking, and write-through with per-bank MSHR.
Key components include request dispatch and response merge crossbars, memory request
multiplexing, and memory response demultiplexing. Deadlock risks exist when the MSHR or
memory queues are full, which informs the verification focus on stall coverage and
stress patterns that exercise MSHR pressure and response ordering.

### 2.8 Verification Dataflow and Control

Runtime parameters are passed via plusargs and consumed by apply_plusargs() in
vortex_config.sv. Compile-time configuration (cache sizes, MSHR depths, AXI wrapper enable)
is provided via +define+ in compile scripts. This separation avoids mismatches between
compile-time RTL structure and runtime UVM configuration.

The AXI testbench acts as a slave device. For writes, it accepts AW/W from the DUT and
returns B responses; for reads, it accepts AR and returns R beats. This role inversion
drives the UVM agent design and the mem_model-backed response behavior.

---

## 3. Interfaces and Protocol Mapping

### 3.1 AXI4 Memory Interface (vortex_axi_if.sv)
- Wraps Vortex_axi.sv
- Five channels: AW, W, B, AR, R
- DUT is AXI master; TB memory model is AXI slave
- ID_WIDTH parametric (derived from mem tag width)
- Write path: AW + W handshake followed by B response
- Read path: AR handshake followed by R beats with rvalid/rlast
- Backpressure modeled via ready/valid on all channels

### 3.2 DCR Interface (vortex_dcr_if.sv)
- Write-only: dcr_wr_valid, dcr_wr_addr, dcr_wr_data
- Driver asserts dcr_wr_valid for one cycle with address and data
- SVA assertions for protocol checks

### 3.3 Status Interface (vortex_status_if.sv)
- Passive: busy only from DUT
- TB generates cycle_count, instr_count, ebreak_detected
- Monitor samples every cycle

---

## 4. Verification Plan

### 4.1 In-Scope
- Functional correctness: ALU, FPU (IEEE 754), LSU, SFU, TCU
- Explicit verification and bring-up of FPU and TCU paths in the UVM environment
- Warp scheduling and context switching
- Memory hierarchy: L1/L2/L3 caches, local memory
- Cache coherence
- Interrupts and exceptions
- AXI4 and custom memory interface correctness
- DCR configuration correctness
- Host-to-device kernel launch

### 4.2 Out-of-Scope
- Physical FPGA I/O
- Performance/timing/power verification
- Formal verification

### 4.3 Test Suite
| Test Name                     | Priority | Status      |
|------------------------------|----------|-------------|
| vortex_sanity_test           | High     | PASSING     |
| vortex_smoke_test            | High     | PASSING     |
| functional_memory_test       | High     | In progress |
| axi_memory_test              | High     | In progress |
| kernel_launch_test (vecadd)  | High     | PASSING     |
| warp_scheduling_test         | Medium   | Planned     |
| barrier_sync_test            | Medium   | Planned     |
| random_instruction_stress    | Medium   | Planned     |
| cache_coherence_test         | Low      | Planned     |

### 4.4 Coverage Goals
Functional:
- Instruction opcodes and formats
- Warp states and scheduling scenarios
- Memory access patterns: aligned, unaligned, contention
- Exception/interrupt types
- TCU texture operations
- FPU operation categories (add, mul, fma, div/sqrt)
- AXI channel sequencing (AW/W/B, AR/R) and response ordering
- DCR programming sequences (startup addr, kernel launch, config writes)

Structural:
- Toggle coverage >90%
- Line coverage >95%

### 4.5 Simulation and Debug Workflows (From Vortex Docs)

The Vortex project uses a unified driver script (blackbox.sh) for simx, rtlsim, and fpga
flows, with configuration through command-line flags. Debug workflows include:
- SimX debug traces (run.log) with adjustable verbosity.
- RTL waveform generation and optional full tracing using TRACING_ALL.
- CSV trace generation from SimX and RTL logs for instruction-level correlation.
These workflows were leveraged to validate UVM behavior and cross-check RTL vs simx.

### 4.6 Functional Coverage Strategy (Execution Units)

Functional coverage is driven by a two-layer strategy:
1) Directed tests target specific execution units (ALU, FPU, LSU, SFU, TCU) with
  deterministic stimulus to hit unit-specific coverage bins.
2) Constrained-random stress sequences expand coverage across operand ranges,
  warp states, and memory patterns while still logging unit hits.

Mapping of unit coverage to tests:
- ALU: arithmetic/logic ops in sanity and smoke tests plus directed ALU sequences.
- FPU: IEEE754 ops (add, mul, fma, div/sqrt) in functional kernels and FPU-directed tests.
- LSU: load/store bursts in memory tests and kernel execution memory traffic.
- SFU: control-flow, CSR, and warp-control operations used in kernel launch flows.
- TCU: texture/warp-control operations via kernel-level tests and TCU-focused sequences.

Coverage is considered valid only when the scoreboard confirms correct results against
the simx reference model, tying coverage bins to functional correctness.

### 4.7 Questa Coverage Report Generation

Goal: generate a UCDB coverage report alongside the results/ run directory, covering
the full RTL (including Vortex_axi.sv signals) and UVM. This is handled by the
run scripts so the coverage artifacts always land in the same results folder as logs,
waves, and config.

Typical flow (implemented inside the run scripts):

1) Compile RTL and UVM with coverage:
  - vlog -cover bcesft +acc -f vortex_rtl.flist
  - vlog -cover bcesft +acc -f uvm_env.flist
2) Optimize with coverage:
  - vopt -coverage vortex_tb_top -o vortex_tb_top_opt
3) Run with coverage enabled and set UCDB output:
  - vsim -coverage -c vortex_tb_top_opt -do "coverage save -onexit <run_dir>/reports/coverage.ucdb; run -all; quit -f"
4) Generate reports in the run directory:
  - vcover report -details -html <run_dir>/reports/coverage.ucdb

The coverage report is stored under results/<date>/run_<time>_<test>/reports so it
travels with the logs, waveforms, and config for that run. This ensures that coverage
includes RTL signals such as those in Vortex_axi.sv as long as the RTL file list is
compiled with -cover enabled.

---

## 5. Simulation Results (Representative)

### 5.1 vecadd Kernel Execution
```
Total Cycles: 3817036
Total Instructions: 89904
Average IPC: 0.024
Peak IPC: 0.080
```

Observed run configuration (kernel_launch_test):
- Interface: AXI
- Cores/Warps/Threads: 1/4/4
- Startup address: 0x80000000
- Timeout: 10,000,000 cycles

### 5.2 Sanity Test
```
Result: TEST PASSED
Instructions: 0 (bring-up test, no kernel loaded)
```

### 5.3 RTL Compilation Stats
```
Errors: 0
Warnings: 135 (mostly -svinputport=relaxed port-kind warnings)
```

Simulation warnings observed in the run logs include:
- dpi_trace not found at runtime in simx_model.so
- $fseek called as a function (PLI warning)
- DCR write during kernel execution (assertion warning)
- Scoreboard result-window filtering (AXI reads skipped)

---

## 6. Issues, Problems, and Resolutions (Full List)

### RTL/DPI Compilation Issues (Vortex/FIX_SOURCE_BUGS)
1) DPI scope violation in VX_tcu_pkg.sv
- dpi_trace not visible in package scope
- Fix: move DPI import inside package

2) Missing import in VX_fpu_pkg.sv
- Fix: include VX_gpu_pkg.sv

3) Syntax error in VX_tcu_top.sv
- Fix: correct interface instantiation name

4) Missing imports in VX_tcu_uops.sv
- Fix: include VX_tcu_pkg.sv and VX_gpu_pkg.sv

5) Incorrect parameter scope in VX_tcu_pkg.sv
- Fix: localparam -> parameter for TCU_RA/RB/RC

6) Missing HardFloat specialization file
- Fix: copy HardFloat_specialize.vi into expected directory

### UVM Bringup and Script Issues (SMOKE_TEST_BRINGALIVE_REPORT)
7) HEX base address overflow
- @80000000 treated as offset, baseaddr added again
- Fix: enforce @00000000 and use startup_addr for base

8) X-propagation from empty RAM
- Root cause: wrong hex offset
- Fix: resolved by HEX base fix

9) AXI B-channel response missing
- TB AXI slave did not assert BVALID
- Workaround: avoid stores until B-channel responder added

10) STARTUP_ADDR plusarg parse failure
- %h parsing fails with 0x prefix
- Fix: strip 0x before passing to sim

11) NUM_CLUSTERS missing from COMPILE_OPTS
- Fix: add +define+NUM_CLUSTERS

12) COMPILE_OPTS missing from UVM vlog
- Fix: add COMPILE_OPTS to UVM compile stage

13) Missing runtime plusargs
- Fix: add +NUM_CLUSTERS, +STARTUP_ADDR, +USE_AXI_WRAPPER

14) DPI library not linked
- Fix: add -sv_lib to vsim

15) Logs and waves overwritten per run
- Fix: timestamped run directory under results

16) Inline comment broke bash line continuation
- Fix: move comments above command lines

17) No @80000000 guard in hex validation
- Fix: reject @80000000 in hex precheck

18) Status monitor polling misses completion (open)
- Fix plan: edge-trigger on busy

19) Host monitor completion not seen for DCR-only launch (open)
- Fix plan: map busy deassert to completion when host iface unused

20) Virtual sequencer handles unconnected (expected)
- Only relevant for future vseq usage

### GLIBCXX and DPI Load Issues
21) GLIBCXX_3.4.29 mismatch with Questa GCC 7
- Fix: static link simx_model + LD_PRELOAD system libstdc++

### Runtime and Simulation Warnings (results/latest)
22) dpi_trace not found at runtime (warning)
- Warning persists in sim log even with DPI scope fix

23) $fseek called as function (warning)
- host_transaction::load_program_from_file uses $fseek in expression

24) DCR write during kernel execution (warning)
- Interface assertion fires during kernel launch flow

25) Scoreboard result window filter warnings
- AXI reads outside result window skipped; high volume noise

26) Busy stuck high threshold warning
- status_if asserts busy must fall within 10k cycles
- long kernels can trigger warning

27) UVM-aware debug package missing
- questa_uvm_pkg not compiled; debug features disabled

28) Large compile warning volume from -svinputport=relaxed
- Many ports defaulted to var instead of wire
- Noise can mask real issues

29) AXI ID width still reported as 50 in logs
- Indicates width override path still active in that run

### DPI Bridge and simx Integration Issues (simx_dpi README)
30) Missing compiler and DPI headers on WSL
- Missing g++ toolchain and svdpi.h during initial build
- Fix: install build-essential and add Questa include path in Makefile

31) SimX RAM range too small (SIGABRT)
- SimX memory initialized to 16MB, but runtime writes used 0x80000000
- Fix: initialize SimX RAM to 4GB to cover full address space

32) Incomplete C++ type errors (ifstream)
- Missing standard headers for file access in simx_dpi.cpp
- Fix: include <fstream>, later replaced by direct SV-to-memory transfer

### Functional Behavior Observations
33) vecadd long runtime not a hang
- Large .bss zeroing + heavy printf + thread launch overhead
- Root cause documented; not a functional failure

---

## 7. Architecture Lessons and Contributions

1) UVM/RTL boundary must be clean: tb_top only instantiates DUT, IFs, clock/reset, run_test.
2) AXI role inversion is critical: DUT is AXI master, TB is slave.
3) DPI-C scoreboard enables golden reference checking using existing C models.
4) Full parametric control via plusargs enables large config sweeps.
5) Multi-simulator portability validated (Questa + Verilator).

---

## 8. Final Directory Structure (Implemented)

```
vortex_uvm_env/
├── DELIVERABLES_SUMMARY.md
├── FILE_TREE.md
├── INTERFACE_MAPPING.md
├── README.md
├── VERIFICATION_PLAN.md
├── Vortex_UVM.cr.mti
├── results/
├── flists/
├── uvm_env/
├── uvm_tests/
├── tb/
├── sim/
└── scripts/
```

---

## 9. Advanced Verification Techniques Used

| Technique               | Status   | Where Applied                  |
|------------------------|----------|--------------------------------|
| UVM Agents (x5)        | Done     | All interfaces                 |
| Virtual Sequencer      | Done     | vortex_env + vseq              |
| DPI-C Reference Model  | Done     | simx_dpi + scoreboard           |
| Clocking Blocks        | Done     | vortex_axi_if                   |
| Constrained Random     | Partial  | DCR and memory sequences        |
| Functional Coverage    | Partial  | vortex_coverage.sv              |
| UVM Config DB          | Done     | Full plusarg-driven config      |
| SVA Assertions         | Partial  | DCR and AXI protocols           |
| RAL (Register Model)   | Planned  | DCR access                      |
| Reactive Sequences     | Planned  | Stress testing                  |
| Factory Override       | Planned  | Low priority                    |

---

## 10. Key Observations for the Paper

1) Verification of open-source GPGPU RTL remains a gap in literature.
2) AXI4 master/slave inversion is a non-trivial verification challenge.
3) DPI-C scoreboard using simx enables instruction-level golden checking.
4) Full plusarg parametricity enables configuration space exploration.
5) The 0x80000000 startup address and hex offset policy is a critical pitfall.

---

## 11. Evidence and Run Artifacts Used

- results/latest/logs/compile_rtl.log
- results/latest/logs/compile_uvm.log
- results/latest/logs/simulation.log
- results/latest/reports/SUMMARY.txt
- results/latest/reports/config.txt
- Vortex/FIX_SOURCE_BUGS
- vortex_uvm_env/uvm_tests/SMOKE_TEST_BRINGALIVE_REPORT.md
- vortex_uvm_env/VECADD_HANG_ROOT_CAUSE_REPORT.md
- GLIBCXX_FIX_SUMMARY.md
- Vortex/docs/microarchitecture.md
- Vortex/docs/cache_subsystem.md
- Vortex/docs/simulation.md
- Vortex/docs/debugging.md
- Vortex/verification/dpi/simx_dpi-main/README.md

---

## 12. Open Items and Future Work

- Implement AXI B-channel responses in axi_driver (stores).
- Make status completion edge-triggered to avoid false warnings.
- Map DCR-only launch completion in host monitor.
- Reduce scoreboard noise by refining result window filtering.
- Remove lingering hardcoded values (clock period, memory size).
