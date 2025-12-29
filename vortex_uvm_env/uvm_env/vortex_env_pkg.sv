////////////////////////////////////////////////////////////////////////////////
// File: vortex_env_pkg.sv
// Description: Vortex UVM Environment Package
//
// This package bundles the complete Vortex UVM environment including:
//   - Virtual Sequencer
//   - Coverage Collector
//   - Scoreboard (placeholder)
//   - Top-level Environment
//
// The package imports all agent packages and provides a single import
// point for test classes.
//
// Usage in tests:
//   import vortex_env_pkg::*;
//
// Dependencies:
//   - uvm_pkg (UVM library)
//   - vortex_config_pkg (Configuration)
//   - All agent packages (mem, axi, dcr, host, status)
//
// Compilation Order:
//   1. Compile vortex_config_pkg.sv
//   2. Compile all agent packages
//   3. Compile vortex_env_pkg.sv
//   4. Compile test packages
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////



// ////////////////////////////////////////////////////////////////////////////////
// // File: vortex_env_pkg.sv
// // Description: Vortex UVM Environment Package
// //
// // Author: Vortex UVM Team
// ////////////////////////////////////////////////////////////////////////////////

// `ifndef VORTEX_ENV_PKG_SV
// `define VORTEX_ENV_PKG_SV

// package vortex_env_pkg;
    
//     //==========================================================================
//     // Import Required Packages
//     //==========================================================================
    
//     import uvm_pkg::*;
//     `include "uvm_macros.svh"
    
//     // Vortex configuration
//     import vortex_config_pkg::*;
    
//     // All agent packages
//     import mem_agent_pkg::*;
//     import axi_agent_pkg::*;
//     import dcr_agent_pkg::*;
//     import host_agent_pkg::*;
//     import status_agent_pkg::*;
    
//     //==========================================================================
//     // Include Environment Component Files
//     //==========================================================================
    
//     // Virtual Sequencer (multi-agent coordination)
//     `include "vortex_virtual_sequencer.sv"
    
//     // Coverage Collector (functional coverage)
//     `include "vortex_coverage_collector.sv"
    
//     // Scoreboard (placeholder - will be completed after DPI-C wrapper)
//     // `include "vortex_scoreboard.sv"
    
//     // Top-level Environment
//     `include "vortex_env.sv"
    
// endpackage : vortex_env_pkg

// `endif // VORTEX_ENV_PKG_SV



////////////////////////////////////////////////////////////////////////////////
// File: vortex_env_pkg.sv
// Description: Top-level UVM Environment Package
//
// Imports all agent packages and environment components.
// Minimal version without scoreboard/coverage for initial testing.
//
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_ENV_PKG_SV
`define VORTEX_ENV_PKG_SV

package vortex_env_pkg;
  
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  
  // Import configuration
  import vortex_config_pkg::*;
  
  // Import all agent packages
  import mem_agent_pkg::*;
  import axi_agent_pkg::*;
  import dcr_agent_pkg::*;
  import host_agent_pkg::*;
  import status_agent_pkg::*;
  
  // Include environment components
  `include "vortex_virtual_sequencer.sv"
  `include "vortex_env.sv"
  
  // TODO: Add when ready
  // `include "vortex_scoreboard.sv"
  // `include "vortex_coverage.sv"

endpackage : vortex_env_pkg

`endif // VORTEX_ENV_PKG_SV




// `ifndef VORTEX_ENV_PKG_SV
// `define VORTEX_ENV_PKG_SV

// package vortex_env_pkg;
    
//     //==========================================================================
//     // Import Required Packages
//     //==========================================================================
    
//     // UVM base library
//     import uvm_pkg::*;
//     `include "uvm_macros.svh"
    
//     // Vortex configuration
//     import vortex_config_pkg::*;
    
//     // All agent packages
//     import mem_agent_pkg::*;
//     import axi_agent_pkg::*;
//     import dcr_agent_pkg::*;
//     import host_agent_pkg::*;
//     import status_agent_pkg::*;
    
//     //==========================================================================
//     // Include Environment Component Files
//     //==========================================================================
    
//     // Virtual Sequencer (multi-agent coordination)
//     `include "vortex_virtual_sequencer.sv"
    
//     // Coverage Collector (functional coverage)
//     `include "vortex_coverage_collector.sv"
    
//     // Scoreboard (placeholder - will be completed after DPI-C wrapper)
//     // `include "vortex_scoreboard.sv"
    
//     // Top-level Environment
//     `include "vortex_env.sv"
    
// endpackage : vortex_env_pkg

// `endif // VORTEX_ENV_PKG_SV
