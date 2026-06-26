////////////////////////////////////////////////////////////////////////////////
// File: vortex_env_pkg.sv
// Description: Top-level Vortex UVM Environment Package
//
// Bundles the complete environment into a single importable unit.
// Compile order within the package:
//   1. Shared analysis imp declarations
//   2. Virtual sequencer
//   3. Scoreboard  (DPI-C imports at CU scope, class inside)
//   4. Coverage collector
//   5. Top-level environment
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_ENV_PKG_SV
`define VORTEX_ENV_PKG_SV

package vortex_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import vortex_config_pkg::*;
    import mem_agent_pkg::*;
    import axi_agent_pkg::*;
    import dcr_agent_pkg::*;
    import host_agent_pkg::*;
    import status_agent_pkg::*;
    import mem_model_pkg::*;
    import simx_pkg::*;
    import VX_gpu_pkg::*;

    // Declare analysis imp macros ONCE for the entire environment
    `uvm_analysis_imp_decl(_mem)
    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_dcr)
    `uvm_analysis_imp_decl(_host)
    `uvm_analysis_imp_decl(_status)

    // INCLUDE the components so they are compiled inside this package
    `include "vortex_virtual_sequencer.sv"
    `include "vortex_scoreboard.sv"
    `include "vortex_coverage_collector.sv"
    `include "vortex_env.sv"

endpackage : vortex_env_pkg

`endif // VORTEX_ENV_PKG_SV