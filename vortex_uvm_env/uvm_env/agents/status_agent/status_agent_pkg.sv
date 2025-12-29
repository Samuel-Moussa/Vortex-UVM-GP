////////////////////////////////////////////////////////////////////////////////
// File: status_agent_pkg.sv
// Description: Status Agent Package for Vortex Execution Monitoring
//
// This package bundles all status agent components into a single importable
// unit. It provides:
//   - Status transaction class
//   - Monitor class
//   - Agent container class
//   - Execution state tracking
//
// Usage in test environment:
//   import status_agent_pkg::*;
//
// Dependencies:
//   - uvm_pkg (UVM library)
//   - vortex_config_pkg (Vortex configuration)
//   - vortex_status_if (Status interface definition)
//
// Compilation Order:
//   1. Compile vortex_config_pkg.sv
//   2. Compile vortex_status_if.sv
//   3. Compile status_agent_pkg.sv
//   4. Use in test environment
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef STATUS_AGENT_PKG_SV
`define STATUS_AGENT_PKG_SV

package status_agent_pkg;
    
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
    
    // Transaction class (status snapshot)
    `include "status_transaction.sv"
    
    // Monitor (passive observer)
    `include "status_monitor.sv"
    
    // Agent container (top-level)
    `include "status_agent.sv"
    
endpackage : status_agent_pkg

`endif // STATUS_AGENT_PKG_SV
