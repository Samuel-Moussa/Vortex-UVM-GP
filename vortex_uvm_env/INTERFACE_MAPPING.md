# Vortex GPGPU Interface Mapping

This document provides a concrete mapping of the five specific RTL interfaces identified in the Vortex GPGPU to UVM agents and describes how they should be transacted.

## 1. Custom Memory Interface

### RTL Location
`hw/rtl/Vortex.sv`

### Signals
**Request Channel:**
- `mem_req_valid` (output): Request valid signal
- `mem_req_ready` (input): Request ready signal
- `mem_req_rw` (output): Read/Write control (1 = write, 0 = read)
- `mem_req_byteen[VX_MEM_BYTEEN_WIDTH-1:0]` (output): Byte enable
- `mem_req_addr[VX_MEM_ADDR_WIDTH-1:0]` (output): Memory address
- `mem_req_data[VX_MEM_DATA_WIDTH-1:0]` (output): Write data
- `mem_req_tag[VX_MEM_TAG_WIDTH-1:0]` (output): Transaction tag

**Response Channel:**
- `mem_rsp_valid` (input): Response valid signal
- `mem_rsp_ready` (output): Response ready signal
- `mem_rsp_data[VX_MEM_DATA_WIDTH-1:0]` (input): Read data
- `mem_rsp_tag[VX_MEM_TAG_WIDTH-1:0]` (input): Transaction tag

### UVM Agent
`mem_agent` (located in `uvm_env/agents/mem_agent/`)

### Transaction Protocol
This is a custom valid-ready handshake protocol. The driver should:
1. Assert `mem_req_valid` with the transaction data.
2. Wait for `mem_req_ready` to be asserted.
3. For read transactions, wait for `mem_rsp_valid` and capture `mem_rsp_data`.
4. Assert `mem_rsp_ready` to acknowledge the response.

### Code Path
`hw/rtl/Vortex.sv` lines 23-36

---

## 2. AXI4 Memory Interface

### RTL Location
`hw/rtl/Vortex_axi.sv`

### Signals
This module wraps the Vortex core with a full AXI4 interface, including five channels:

**Write Address (AW):**
- `m_axi_awvalid`, `m_axi_awready`, `m_axi_awaddr`, `m_axi_awid`, `m_axi_awlen`, `m_axi_awsize`, `m_axi_awburst`, etc.

**Write Data (W):**
- `m_axi_wvalid`, `m_axi_wready`, `m_axi_wdata`, `m_axi_wstrb`, `m_axi_wlast`

**Write Response (B):**
- `m_axi_bvalid`, `m_axi_bready`, `m_axi_bid`, `m_axi_bresp`

**Read Address (AR):**
- `m_axi_arvalid`, `m_axi_arready`, `m_axi_araddr`, `m_axi_arid`, `m_axi_arlen`, `m_axi_arsize`, `m_axi_arburst`, etc.

**Read Data (R):**
- `m_axi_rvalid`, `m_axi_rready`, `m_axi_rdata`, `m_axi_rlast`, `m_axi_rid`, `m_axi_rresp`

### UVM Agent
`axi_agent` (located in `uvm_env/agents/axi_agent/`)

### Transaction Protocol
This is a standard AXI4 protocol. The driver should:
1. For writes: Drive the AW channel, then the W channel, then wait for the B channel.
2. For reads: Drive the AR channel, then wait for the R channel.

### Code Path
`hw/rtl/Vortex_axi.sv` lines 28-75

---

## 3. DCR (Device Configuration Register) Interface

### RTL Location
`hw/rtl/Vortex.sv`

### Signals
- `dcr_wr_valid` (input): Write enable
- `dcr_wr_addr[VX_DCR_ADDR_WIDTH-1:0]` (input): Register address
- `dcr_wr_data[VX_DCR_DATA_WIDTH-1:0]` (input): Write data

### UVM Agent
`dcr_agent` (located in `uvm_env/agents/dcr_agent/`)

### Transaction Protocol
This is a simple write-only interface. The driver should:
1. Assert `dcr_wr_valid` with the address and data.
2. Hold for one clock cycle.
3. Deassert `dcr_wr_valid`.

### Code Path
`hw/rtl/Vortex.sv` lines 38-41

---

## 4. Host/Driver Interface (Kernel Launch)

### RTL Location
This is not a direct RTL interface, but rather a high-level abstraction implemented via DCR writes.

### Signals
The host driver uses the DCR interface to configure the GPU and launch kernels. Typical DCR addresses include:
- Kernel address register
- Number of warps register
- Number of threads register
- Start/stop control register

### UVM Agent
`host_agent` (located in `uvm_env/agents/host_agent/`)

### Transaction Protocol
The driver should:
1. Write the kernel configuration to DCR registers.
2. Write to the start register to begin execution.
3. Monitor the `busy` signal to detect completion.

### Code Path
The exact DCR addresses are defined in `hw/rtl/VX_define.vh` and `runtime/` directory.

---

## 5. Status/Control Interface

### RTL Location
`hw/rtl/Vortex.sv`

### Signals
- `busy` (output): Indicates the GPU is processing

### UVM Agent
`status_agent` (located in `uvm_env/agents/status_agent/`)

### Transaction Protocol
This is a passive agent (monitor-only). The monitor should:
1. Sample the `busy` signal on every clock cycle.
2. Report status changes to the scoreboard.

### Code Path
`hw/rtl/Vortex.sv` line 44
