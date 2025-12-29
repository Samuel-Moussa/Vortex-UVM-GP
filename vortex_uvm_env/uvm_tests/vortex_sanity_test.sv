////////////////////////////////////////////////////////////////////////////////
// File: vortex_sanity_test.sv
// Description: Ultra-Simple Sanity Test
//
// Purpose: Verify that:
//   1. Testbench compiles
//   2. Environment builds
//   3. Reset works
//   4. Simulation runs without crash
//
// This is the FIRST test to run on a brand new testbench.
//
// Usage: vsim +UVM_TESTNAME=vortex_sanity_test
//
// Expected: Should pass in ~100 cycles, no program needed
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_SANITY_TEST_SV
`define VORTEX_SANITY_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

// Import required packages
// import vortex_test_pkg::*;
import vortex_config_pkg::*;
import vortex_env_pkg::*;

`include "vortex_base_test.sv"


class vortex_sanity_test extends vortex_base_test;
    `uvm_component_utils(vortex_sanity_test)

    function new(string name = "vortex_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Customize Configuration - Minimal
    //==========================================================================
    virtual function void customize_config();
        cfg.test_timeout_cycles = 500;        // Very short
        cfg.enable_scoreboard = 0;            // Disabled
        cfg.enable_coverage = 0;              // Disabled
        cfg.default_verbosity = UVM_LOW;      // Quiet
        
        `uvm_info(get_type_name(), "Sanity test: minimal config", UVM_LOW)
    endfunction
    
    //==========================================================================
    // Run Test - Just wait a bit
    //==========================================================================
    virtual task run_test_stimulus();
        `uvm_info(get_type_name(), "╔═══════════════════════════════════╗", UVM_LOW)
        `uvm_info(get_type_name(), "║    SANITY TEST - Just Survive     ║", UVM_LOW)
        `uvm_info(get_type_name(), "╚═══════════════════════════════════╝", UVM_LOW)
        
        // Just wait 100 cycles - that's it!
        repeat(100) @(posedge vif.clk);
        
        `uvm_info(get_type_name(), "✓ Survived 100 cycles without crashing", UVM_LOW)
    endtask
    
    //==========================================================================
    // Override completion wait - Don't wait for EBREAK
    //==========================================================================
    virtual task wait_for_completion();
        // Don't wait for EBREAK - just return immediately
        `uvm_info(get_type_name(), "Skipping EBREAK check (sanity test)", UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Override result check - Always pass if we got here
    //==========================================================================
    virtual function void check_results();
        test_passed = 1'b1;
        `uvm_info(get_type_name(), "✓ Sanity test PASSED - testbench is alive!", UVM_LOW)
    endfunction
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), {"\n",
                "╔═══════════════════════════════════════════════════╗\n",
                "║                                                   ║\n",
                "║        ✓✓✓ SANITY TEST PASSED ✓✓✓                ║\n",
                "║                                                   ║\n",
                "║  Testbench Infrastructure Working:                ║\n",
                "║    ✓ Compiles without errors                      ║\n",
                "║    ✓ Environment builds                           ║\n",
                "║    ✓ Reset sequence works                         ║\n",
                "║    ✓ Clock is running                             ║\n",
                "║    ✓ UVM phases execute                           ║\n",
                "║    ✓ Simulation doesn't crash                     ║\n",
                "║                                                   ║\n",
                "║  Ready for: Smoke Test                            ║\n",
                "║                                                   ║\n",
                "╚═══════════════════════════════════════════════════╝"
            }, UVM_NONE)
        end
    endfunction
    
endclass : vortex_sanity_test

`endif
