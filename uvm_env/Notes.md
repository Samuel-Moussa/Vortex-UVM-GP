# Vortex GPGPU Architecture Research Notes

## Overview
Vortex is a full-stack open-source RISC-V GPGPU supporting RV32IMAF and RV64IMAFD ISAs with OpenCL 1.2 support.

## Key Interfaces Identified

### 1. Memory Interface (Custom Protocol)
**Location**: `hw/rtl/Vortex.sv`
- **Request Channel**:
  - `mem_req_valid`, `mem_req_ready` (handshake)
  - `mem_req_rw` (read/write)
  - `mem_req_byteen[VX_MEM_BYTEEN_WIDTH-1:0]` (byte enable)
  - `mem_req_addr[VX_MEM_ADDR_WIDTH-1:0]` (address)
  - `mem_req_data[VX_MEM_DATA_WIDTH-1:0]` (write data)
  - `mem_req_tag[VX_MEM_TAG_WIDTH-1:0]` (transaction tag)
- **Response Channel**:
  - `mem_rsp_valid`, `mem_rsp_ready` (handshake)
  - `mem_rsp_data[VX_MEM_DATA_WIDTH-1:0]` (read data)
  - `mem_rsp_tag[VX_MEM_TAG_WIDTH-1:0]` (transaction tag)

### 2. AXI4 Memory Interface
**Location**: `hw/rtl/Vortex_axi.sv`
- Full AXI4 interface with 5 channels:
  - Write Address (AW): awvalid, awready, awaddr, awid, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion
  - Write Data (W): wvalid, wready, wdata, wstrb, wlast
  - Write Response (B): bvalid, bready, bid, bresp
  - Read Address (AR): arvalid, arready, araddr, arid, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion
  - Read Data (R): rvalid, rready, rdata, rlast, rid, rresp
- Adapter: `VX_axi_adapter` converts custom memory protocol to AXI4

### 3. DCR (Device Configuration Register) Interface
**Location**: `hw/rtl/Vortex.sv`
- Write-only configuration interface:
  - `dcr_wr_valid` (write enable)
  - `dcr_wr_addr[VX_DCR_ADDR_WIDTH-1:0]` (register address)
  - `dcr_wr_data[VX_DCR_DATA_WIDTH-1:0]` (write data)
- Used for runtime configuration of GPU parameters

### 4. Status/Control Interface
- `busy` signal (output) - indicates GPU is processing

### 5. Internal Memory Bus Interface
**Location**: `hw/rtl/interfaces/VX_mem_bus_if.sv` (likely)
- SystemVerilog interface used internally between cache levels
- Connects L2, L3 caches and clusters

## Architecture Hierarchy

```
Vortex (Top)
├── L3 Cache (VX_cache_wrap)
├── Clusters (VX_cluster) [NUM_CLUSTERS]
│   ├── L2 Cache
│   ├── Sockets (VX_socket) [NUM_SOCKETS]
│   │   └── Cores (VX_core) [CORES_PER_SOCKET]
│   │       ├── Fetch Stage (VX_fetch)
│   │       ├── Decode Stage (VX_decode)
│   │       ├── Issue Stage (VX_issue)
│   │       ├── Execute Stage (VX_execute)
│   │       │   ├── ALU Units (VX_alu_unit)
│   │       │   ├── FPU Units (VX_fpu_unit)
│   │       │   ├── LSU Units (VX_lsu_unit)
│   │       │   ├── SFU Units (VX_sfu_unit)
│   │       │   └── Optional: VPU, TCU
│   │       └── Commit Stage (VX_commit)
│   │       ├── ICache (Instruction Cache)
│   │       └── DCache (Data Cache)
```

## Pipeline Stages
1. **Schedule**: Warp scheduling, thread mask convergence (TMC), barriers
2. **Fetch**: Instruction fetch from ICache
3. **Decode**: Instruction decode
4. **Issue**: Dependency checking, operand collection
5. **Execute**: Execution on functional units (ALU/FPU/LSU/SFU)
6. **Commit**: Writeback to register file

## Configuration Parameters (from DeepWiki)
- `NUM_CLUSTERS`: Number of clusters (default: 1)
- `NUM_CORES`: Cores per cluster (default: 1)
- `NUM_WARPS`: Warps per core (default: 4)
- `NUM_THREADS`: Threads per warp (default: 4)
- `ISSUE_WIDTH`: Pipeline issue width
- `SIMD_WIDTH`: SIMD execution width
- Cache sizes: ICACHE, DCACHE, L2, L3 (configurable)

## Simulation Models
- **simx**: C++ behavioral simulator (reference model)
- **rtlsim**: RTL simulation with Verilator
- **FPGA**: Physical deployment on Xilinx/Altera FPGAs

## Key RTL Modules to Interface
1. `Vortex.sv` - Top-level module with custom memory interface
2. `Vortex_axi.sv` - AXI4 wrapper
3. `VX_cluster.sv` - Cluster-level module
4. `VX_socket.sv` - Socket-level module
5. `VX_core.sv` - Core-level module
6. `VX_cache_wrap.sv` - Cache wrapper
7. AFU wrappers: `vortex_afu.sv` (XRT), `vortex_afu.sv` (OPAE)

## Software Stack
- Runtime: `runtime/` directory
- Driver: `driver/` directory (host-device protocol)
- Tests: `tests/` directory (OpenCL kernels, regression tests)

## Next Steps for UVM Environment
1. Create agents for each interface type
2. Map simx as reference model
3. Identify test scenarios from `tests/` directory
4. Design scoreboard for transaction-level comparison
