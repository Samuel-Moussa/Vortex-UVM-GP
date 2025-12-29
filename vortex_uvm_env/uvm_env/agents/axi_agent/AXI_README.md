# Vortex AXI4 UVM Agent

## Overview

Complete UVM agent for verifying AXI4 master interfaces in the Vortex GPGPU. Provides transaction-level modeling, protocol checking, and comprehensive stimulus generation.

---

## Files Included

| File                 | Description                                      | Lines |
|----------------------|--------------------------------------------------|-------|
| `axi_transaction.sv` | Transaction class with AXI4 protocol constraints | ~600  |
| `axi_driver.sv`      | Active driver with ID pool management            | ~800  |
| `axi_monitor.sv`     | Passive monitor with FIFO-based W matching       | ~700  |
| `axi_sequencer.sv`   | Standard UVM sequencer                           | ~30   |
| `axi_sequences.sv`   | Sequence library (8+ reusable sequences)         | ~400  |
| `axi_agent.sv`       | Agent container                                  | ~150  |
| `axi_agent_pkg.sv`   | Package wrapper                                  | ~350  |

**Total:** ~3000 lines of production-quality SystemVerilog

---

## Key Features

### ✅ Full AXI4 Protocol Support
- 5 independent channels (AW, W, B, AR, R)
- Burst transactions (1-256 beats)
- Out-of-order completion via ID tracking
- 4KB boundary enforcement
- Clocking blocks for race-free operation

### ✅ Advanced W Channel Matching
- **FIFO-based solution** for W channel (AXI4 removed WID)
- Maintains AW ordering as required by spec
- No data loss or mismatched beats

### ✅ Comprehensive Constraints
- Address alignment validation
- Burst length limits
- Protocol-compliant randomization
- Configurable from vortex_config

### ✅ Robust Error Handling
- Timeout protection on all handshakes
- Protocol violation detection
- X-state guards
- Reset handling

### ✅ Performance Instrumentation
- Cycle-accurate latency tracking
- Transaction statistics
- Average throughput calculation

---


## Available Sequences

### Basic Operations
- **axi_single_write_seq**: Single write to address
- **axi_single_read_seq**: Single read from address
- **axi_write_read_seq**: Write then read (RAW test)

### Burst Operations
- **axi_burst_write_seq**: Multi-beat write burst
- **axi_burst_read_seq**: Multi-beat read burst

### Advanced Patterns
- **axi_random_seq**: Mixed random reads/writes
- **axi_stress_seq**: High-throughput stress test


---

## Protocol Checking

The monitor automatically detects:
- ❌ W beats without matching AW
- ❌ Wrong number of beats in burst
- ❌ WLAST/RLAST assertion errors
- ❌ Responses for unknown IDs
- ❌ Hung transactions (timeout)

Violations reported as `UVM_ERROR` with cycle number and details.

---

## Statistics Output

End-of-test report shows:
========================================
AXI Agent Statistics
Total Writes: 125
Avg Write Latency: 12.3 cycles
Total Reads: 87
Avg Read Latency: 15.7 cycles
Protocol Violations: 0


---

## Limitations & Future Enhancements

### Current Limitations
- Write serialization reduces throughput (default safe mode)
- No support for narrow transfers (WSTRB partial)
- No exclusive access (AxLOCK) checking

### Planned Enhancements
- Coverage collector component
- Assertion-based formal checks
- Performance analyzer component
- Atomic operation sequences

---


### Common Issues
1. **"W data beat without matching AW"** → Check driver is driving AW before W
2. **"ID allocation timeout"** → All IDs busy, increase `AXI_ID_WIDTH` or reduce transaction rate
3. **"WLAST not asserted"** → Check transaction `len` field matches actual beats

---


**Status:** ✅ Production Ready  
**Last Updated:** December 2025  
**Maintainer:** Vortex UVM Team

