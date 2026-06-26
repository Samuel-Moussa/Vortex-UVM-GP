////////////////////////////////////////////////////////////////////////////////
// File: tests/vortex_test_pkg.sv
// Description: Test package for Vortex UVM tests
//
// Change from original (file:18):
//   Added two lines only:
//     `include "random_instr_stress_vseq.sv"         (after kernel_launch_vseq)
//     `include "random_instruction_stress_test.sv"    (after kernel_launch_test)
//
// Subsequent additions (T-fmem / T-axi):
//   Removed `include "functional_memory_test.sv" from its original position
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

    //==========================================================================
    // Sequence base classes (must come before any test that uses them)
    //==========================================================================
    `include "vortex_base_sequence.sv"
    `include "vortex_virtual_sequence.sv"

    //==========================================================================
    // Virtual sequences (must come before tests that instantiate them)
    //==========================================================================
    `include "vortex_functional_mem_vseq.sv"
    `include "kernel_launch_vseq.sv"
    `include "random_instr_stress_vseq.sv"          // ← NEW

    //==========================================================================
    // Include Test Files
    //==========================================================================
    `include "vortex_base_test.sv"
    `include "vortex_sanity_test.sv"
    `include "vortex_smoke_test.sv"
    `include "kernel_launch_test.sv"
    `include "negative_result_test.sv"
    `include "random_instruction_stress_test.sv"    // ← NEW
    `include "warp_scheduling_test.sv"
    `include "barrier_sync_test.sv"
    `include "functional_memory_test.sv"            // ← NEW (extends kernel_launch_test; must follow it)
    `include "axi_memory_test.sv"                   // ← NEW (extends kernel_launch_test; AXI path only)
    // `include "sgemm_test.sv"       // To be added later
    // `include "riscv_dv_test.sv"    // To be added later

endpackage : vortex_test_pkg

`endif // VORTEX_TEST_PKG_SV