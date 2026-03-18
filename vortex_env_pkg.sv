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

  // Note: vortex_virtual_sequencer.sv is `included by vortex_env.sv
  // Include scoreboard and coverage BEFORE env so env can reference them

  // SimX DPI-C imports — must be inside the package for QuestaSim 2021
  // To add: insert one line here + call site in vortex_scoreboard.sv
  // To remove: delete the line + all call sites, recompile UVM env only
  import "DPI-C" function int  simx_init    (int cores, int warps, int threads);
  import "DPI-C" function void simx_cleanup ();
  import "DPI-C" function void simx_write_mem (longint unsigned addr,
                                               int              size,
                                               input byte unsigned data[]);
  import "DPI-C" function void simx_read_mem  (longint unsigned addr,
                                               int              size,
                                               inout byte unsigned data[]);
  import "DPI-C" function int  simx_load_bin  (string filepath,
                                               longint unsigned load_addr);
  import "DPI-C" function int  simx_load_hex  (string filepath);
  import "DPI-C" function void simx_dcr_write (int addr, int value);
  import "DPI-C" function int  simx_run       ();
  import "DPI-C" function int  simx_step      (int cycles);
  import "DPI-C" function int  simx_is_done   ();
  import "DPI-C" function int  simx_get_exitcode ();
  import "DPI-C" function void simx_init_exit_code_register ();


  // Analysis imp macro declarations — must appear before scoreboard/coverage
  `uvm_analysis_imp_decl(_mem)
  `uvm_analysis_imp_decl(_axi)
  `uvm_analysis_imp_decl(_dcr)
  `uvm_analysis_imp_decl(_host)
  `uvm_analysis_imp_decl(_status)

  `include "vortex_virtual_sequencer.sv"
  `include "vortex_scoreboard.sv"
  `include "vortex_coverage_collector.sv"
  `include "vortex_env.sv"

endpackage : vortex_env_pkg

`endif // VORTEX_ENV_PKG_SV
