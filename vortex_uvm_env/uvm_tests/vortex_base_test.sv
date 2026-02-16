////////////////////////////////////////////////////////////////////////////////
// File: tests/vortex_base_test.sv
// Description: Base Test Class for Vortex GPGPU Verification
//
// Clean, simple base test that all Vortex tests extend from.
// Provides essential functionality without over-complication.
//
// Author: Vortex UVM Team
// Date: December 2025
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_BASE_TEST_SV
`define VORTEX_BASE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

// Import required packages
import vortex_config_pkg::*;
import vortex_env_pkg::*;



class vortex_base_test extends uvm_test;
    `uvm_component_utils(vortex_base_test)
    
    //==========================================================================
    // Components
    //==========================================================================
    vortex_env    env;
    vortex_config cfg;
    
    //==========================================================================
    // Virtual Interface
    //==========================================================================
    virtual vortex_if vif;
    
    //==========================================================================
    // Test Configuration
    //==========================================================================
    int unsigned timeout_cycles;
    bit test_passed;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "vortex_base_test", uvm_component parent = null);
        super.new(name, parent);
        test_passed = 1'b0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info(get_type_name(), "Building test...", UVM_LOW)
        
        // Create and configure
        cfg = vortex_config::type_id::create("cfg");
        cfg.set_defaults_from_vx_config();
        cfg.apply_plusargs();
        
        `uvm_info(get_type_name(),
  $sformatf("DEBUG cfg after plusargs: cores=%0d warps=%0d threads=%0d str=%s",
            cfg.num_cores, cfg.num_warps, cfg.num_threads, cfg.get_config_string()),
  UVM_LOW)

        
        // Allow test customization
        customize_config();
        
        // Validate
        if (!cfg.is_valid()) begin
            `uvm_fatal(get_type_name(), "Invalid configuration!")
        end
        
        // Set in database
        uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);
        
        // Get virtual interface
        if (!uvm_config_db#(virtual vortex_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "Failed to get virtual interface")
        end
        
        // Create environment
        env = vortex_env::type_id::create("env", this);
        
        // Set verbosity
        set_report_verbosity_level_hier(cfg.default_verbosity);
        
        timeout_cycles = cfg.test_timeout_cycles;
        
    endfunction
    
    //==========================================================================
    // Customize Config (Override in derived tests)
    //==========================================================================
    virtual function void customize_config();
        // Default - override in derived tests
    endfunction
    
    //==========================================================================
    // Connect Phase
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info(get_type_name(), {"\n",
            "================================================================================\n",
            $sformatf("  Test:        %s\n", get_type_name()),
            $sformatf("  Config:      %s\n", cfg.get_config_string()),
            $sformatf("  Timeout:     %0d cycles\n", timeout_cycles),
            "================================================================================"
        }, UVM_LOW)
        
        // Print topology if debug
        if (cfg.default_verbosity >= UVM_HIGH) begin
            uvm_top.print_topology();
        end
    endfunction
    
    //==========================================================================
    // Run Phase (Override in derived tests)
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        
        phase.raise_objection(this, "Test running");
        
        `uvm_info(get_type_name(), "Starting test execution...", UVM_LOW)
        
        // Wait for reset
        wait_for_reset();
        
        // Run test stimulus (override this)
        run_test_stimulus();
        
        // Wait for completion
        wait_for_completion();
        
        // Check results
        check_results();
        
        `uvm_info(get_type_name(), "Test execution complete", UVM_LOW)
        
        phase.drop_objection(this, "Test complete");
    endtask
    
    //==========================================================================
    // Wait for Reset
    //==========================================================================
    virtual task wait_for_reset();
        `uvm_info(get_type_name(), "Waiting for reset...", UVM_MEDIUM)
        @(posedge vif.reset_n);
        repeat(5) @(posedge vif.clk);
        `uvm_info(get_type_name(), "Reset complete", UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Run Test Stimulus (Override in derived tests)
    //==========================================================================
    virtual task run_test_stimulus();
        `uvm_info(get_type_name(), "No test stimulus (override in derived test)", UVM_MEDIUM)
        repeat(100) @(posedge vif.clk);
    endtask
    
    //==========================================================================
    // Wait for Completion
    //==========================================================================
    virtual task wait_for_completion();
        fork
            begin
                fork
                    // Wait for EBREAK
                    begin
                        wait(vif.status_if.ebreak_detected == 1'b1);
                        `uvm_info(get_type_name(), "EBREAK detected", UVM_LOW)
                    end
                    // Timeout watchdog
                    begin
                        repeat(timeout_cycles) @(posedge vif.clk);
                        `uvm_error(get_type_name(), 
                                  $sformatf("Timeout after %0d cycles!", timeout_cycles))
                    end
                join_any
                disable fork;
            end
        join
    endtask
    
    //==========================================================================
    // Check Results
    //==========================================================================
    virtual function void check_results();
        if (vif.status_if.ebreak_detected) begin
            test_passed = 1'b1;
            `uvm_info(get_type_name(), "✓ Test completed successfully", UVM_LOW)
        end else begin
            test_passed = 1'b0;
            `uvm_error(get_type_name(), "✗ Test did not complete properly")
        end
    endfunction
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        uvm_report_server rs;
        int err_count;
        real ipc;
        
        super.report_phase(phase);
        
        rs = uvm_report_server::get_server();
        err_count = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
        
        // Calculate IPC
        if (vif.status_if.cycle_count > 0) begin
            ipc = real'(vif.status_if.instr_count) / real'(vif.status_if.cycle_count);
        end else begin
            ipc = 0.0;
        end
        
        `uvm_info(get_type_name(), {"\n",
            "================================================================================\n",
            "                              TEST SUMMARY\n",
            "================================================================================\n",
            $sformatf("  Test:         %s\n", get_type_name()),
            $sformatf("  Status:       %s\n", (err_count == 0 && test_passed) ? "PASSED ✓" : "FAILED ✗"),
            $sformatf("  Errors:       %0d\n", err_count),
            $sformatf("  Warnings:     %0d\n", rs.get_severity_count(UVM_WARNING)),
            "--------------------------------------------------------------------------------\n",
            $sformatf("  Cycles:       %0d\n", vif.status_if.cycle_count),
            $sformatf("  Instructions: %0d\n", vif.status_if.instr_count),
            $sformatf("  IPC:          %.3f\n", ipc),
            "================================================================================"
        }, UVM_NONE)
        
        if (err_count == 0 && test_passed) begin
            `uvm_info(get_type_name(), "\n*** TEST PASSED ***\n", UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), "\n*** TEST FAILED ***\n")
        end
    endfunction
    
endclass : vortex_base_test

`endif // VORTEX_BASE_TEST_SV
