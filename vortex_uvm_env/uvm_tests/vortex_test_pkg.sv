////////////////////////////////////////////////////////////////////////////////
// File: tests/vortex_test_pkg.sv
// Description: Test package for Vortex UVM tests
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_TEST_PKG_SV
`define VORTEX_TEST_PKG_SV

package vortex_test_pkg;
    
    //==========================================================================
    // Import Required Packages
    //==========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    import vortex_config_pkg::*;
    import vortex_env_pkg::*;
    import mem_agent_pkg::*;
    import axi_agent_pkg::*;
    import dcr_agent_pkg::*;
    import host_agent_pkg::*;
    import status_agent_pkg::*;

    `include "mem_model.sv"  // For testbench reference, not part of the env

    //==========================================================================
    // Sequence base classes (must come before any test that uses them)
    //==========================================================================
    `include "vortex_base_sequence.sv"
    `include "vortex_virtual_sequence.sv"

    //==========================================================================
    // Virtual sequences (must come before tests that instantiate them)
    //==========================================================================
    `include "vortex_functional_mem_vseq.sv"

    //==========================================================================
    // Include Test Files
    //==========================================================================
    `include "vortex_base_test.sv"
    `include "vortex_sanity_test.sv"
    `include "vortex_smoke_test.sv"
    `include "functional_memory_test.sv"
    // `include "vecadd_test.sv"      // To be added later
    // `include "sgemm_test.sv"       // To be added later
    // `include "riscv_dv_test.sv"    // To be added later
    
endpackage : vortex_test_pkg

`endif // VORTEX_TEST_PKG_SV