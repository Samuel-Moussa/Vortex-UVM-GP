////////////////////////////////////////////////////////////////////////////////
// File: dcr_agent_pkg.sv
// Description: DCR Agent Package for Vortex GPU Configuration Interface
//
// This package bundles all DCR agent components into a single importable
// unit. It provides:
//   - DCR transaction class
//   - Driver, Monitor, Sequencer, Agent classes
//   - Complete sequence library
//   - DCR address definitions
//
// Usage in test environment:
//   import dcr_agent_pkg::*;
//
// Dependencies:
//   - uvm_pkg (UVM library)
//   - vortex_config_pkg (Vortex configuration)
//   - vortex_dcr_if (DCR interface definition)
//
// Compilation Order:
//   1. Compile vortex_config_pkg.sv
//   2. Compile vortex_dcr_if.sv
//   3. Compile dcr_agent_pkg.sv
//   4. Use in test environment
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef DCR_AGENT_PKG_SV
`define DCR_AGENT_PKG_SV

package dcr_agent_pkg;
    
    //==========================================================================
    // Import Required Packages
    //==========================================================================
    
    // UVM base library - provides all UVM classes and macros
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Vortex configuration package - provides vortex_config class and DCR parameters
    import vortex_config_pkg::*;
    
    //==========================================================================
    // Include Agent Component Files
    // Order matters: transaction first, then components using it
    //==========================================================================
    
    // Transaction class (sequence item)
    `include "dcr_transaction.sv"
    
    // Driver (active component)
    `include "dcr_driver.sv"
    
    // Monitor (passive observer)
    `include "dcr_monitor.sv"
    
    // Sequencer (transaction arbiter)
    `include "dcr_sequencer.sv"
    
    // Sequences (stimulus generators)
    `include "dcr_sequences.sv"
    
    // Agent container (top-level)
    `include "dcr_agent.sv"
    
endpackage : dcr_agent_pkg

`endif // DCR_AGENT_PKG_SV
