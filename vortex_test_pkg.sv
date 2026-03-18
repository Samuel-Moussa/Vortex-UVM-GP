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
    `include "mem_model.sv"

    
    //==========================================================================
    // Include Test Files
    //==========================================================================
    
    `include "vortex_base_test.sv"
    `include "vortex_sanity_test.sv"
    `include "vortex_smoke_test.sv"
    // `include "vecadd_test.sv"      // To be added later
    // `include "sgemm_test.sv"       // To be added later
    // `include "riscv_dv_test.sv"    // To be added later
    
endpackage : vortex_test_pkg

`endif // VORTEX_TEST_PKG_SV
