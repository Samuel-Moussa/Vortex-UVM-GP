////////////////////////////////////////////////////////////////////////////////
// File: tests/vortex_test_pkg.sv
// Description: Test package for Vortex UVM tests
//
// Change from original (file:18):
//   Added two lines only:
//     `include "random_instr_stress_vseq.svh"         (after kernel_launch_vseq)
//     `include "random_instruction_stress_test.svh"    (after kernel_launch_test)
//
// Subsequent additions (T-fmem / T-axi):
//   Removed `include "functional_memory_test.svh" from its original position
//   (which was before kernel_launch_test — wrong order since the new class
//   extends kernel_launch_test). Added both new tests at the end of the test
//   include block, after barrier_sync_test.sv.
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
    import mem_model_pkg::*;
    import simx_pkg::*;

    //==========================================================================
    // Sequence base classes (must come before any test that uses them)
    //==========================================================================
    `include "vortex_base_sequence.svh"
    `include "vortex_virtual_sequence.svh"

    //==========================================================================
    // Virtual sequences (must come before tests that instantiate them)
    //==========================================================================
    `include "vortex_functional_mem_vseq.svh"
    `include "kernel_launch_vseq.svh"
    `include "random_instr_stress_vseq.svh"          // ← NEW
    `include "host_coverage_vseq.svh"                // ← NEW (coverage push)

    //==========================================================================
    // Include Test Files
    //==========================================================================
    `include "vortex_base_test.svh"
    `include "vortex_sanity_test.svh"
    `include "vortex_smoke_test.svh"
    `include "kernel_launch_test.svh"
    `include "host_coverage_test.svh"                // ← NEW (extends kernel_launch_test)
    `include "negative_result_test.svh"
    `include "negative_dropped_store_test.svh"        // ← SB-DIR bidirectional (dropped-store) proof
    `include "random_instruction_stress_test.svh"    // ← NEW
    `include "warp_scheduling_test.svh"
    `include "barrier_sync_test.svh"
    `include "functional_memory_test.svh"            // ← NEW (extends kernel_launch_test; must follow it)
    `include "axi_memory_test.svh"                   // ← NEW (extends kernel_launch_test; AXI path only)
    `include "regression_test.svh"       

endpackage : vortex_test_pkg

`endif // VORTEX_TEST_PKG_SV