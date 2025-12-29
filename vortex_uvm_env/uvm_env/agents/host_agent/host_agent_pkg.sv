////////////////////////////////////////////////////////////////////////////////
// File: host_agent_pkg.sv
// Description: Host Agent Package for High-Level Kernel Operations
//
// This package bundles all host agent components into a single importable
// unit. The host agent orchestrates multiple low-level agents to perform
// complex operations like program loading and kernel execution.
//
// Usage in test environment:
//   import host_agent_pkg::*;
//
// Dependencies:
//   - uvm_pkg (UVM library)
//   - vortex_config_pkg (Vortex configuration)
//   - vortex_mem_if (Memory interface)
//   - vortex_dcr_if (DCR interface)
//   - vortex_status_if (Status interface)
//
// Compilation Order:
//   1. Compile vortex_config_pkg.sv
//   2. Compile interface files (vortex_mem_if, vortex_dcr_if, vortex_status_if)
//   3. Compile host_agent_pkg.sv
//   4. Use in test environment
//
// Key Features:
//   - Multi-interface coordination
//   - High-level operation abstraction
//   - Clocking block support for clean timing
//   - Complete sequence library
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_AGENT_PKG_SV
`define HOST_AGENT_PKG_SV

package host_agent_pkg;
    
    //==========================================================================
    // Import Required Packages
    //==========================================================================
    
    // UVM base library - provides all UVM classes and macros
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Vortex configuration package - provides vortex_config class
    import vortex_config_pkg::*;
    
    //==========================================================================
    // Include Agent Component Files
    // Order matters: transaction first, then components using it
    //==========================================================================
    
    // Transaction class (host operation descriptor)
    `include "host_transaction.sv"
    
    // Sequencer (transaction arbiter)
    `include "host_sequencer.sv"
    
    // Driver (transaction executor using clocking blocks)
    `include "host_driver.sv"
    
    // Monitor (passive observer using clocking blocks)
    `include "host_monitor.sv"
    
    // Agent container (top-level orchestrator)
    `include "host_agent.sv"
    
    // Sequence library (reusable test sequences)
    `include "host_sequences.sv"
    
endpackage : host_agent_pkg

`endif // HOST_AGENT_PKG_SV
