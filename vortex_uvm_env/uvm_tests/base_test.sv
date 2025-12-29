////////////////////////////////////////////////////////////////////////////////
// File: vortex_base_test.sv
// Description: Base Test Class for Vortex GPGPU Verification
//
// All Vortex tests extend from this base class. Provides common functionality:
//   - Environment instantiation and configuration
//   - Default test phases
//   - Timeout handling
//   - Result checking
//
// Derived tests override build_phase() to customize configuration and
// run_phase() to execute specific test sequences.
//
// Author: Vortex UVM Team
// Date: December 2025
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_BASE_TEST_SV
`define VORTEX_BASE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

import vortex_config_pkg::*;

class vortex_base_test extends uvm_test;
  `uvm_component_utils(vortex_base_test)

  //==========================================================================
  // Environment and Configuration
  //==========================================================================
  vortex_env env;
  vortex_config cfg;

  //==========================================================================
  // Virtual Interfaces
  //==========================================================================
  virtual vortex_if vif;

  //==========================================================================
  // Test Control
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

    // Create and configure
    cfg = vortex_config::type_id::create("cfg");
    cfg.set_defaults_from_vx_config();
    cfg.apply_plusargs();

    // Allow tests to customize configuration
    customize_config();

    // Validate configuration
    if (!cfg.is_valid()) begin
      `uvm_fatal("BASE_TEST", "Invalid configuration!")
    end

    // Set configuration in database
    uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);

    // Get virtual interface
    if (!uvm_config_db#(virtual vortex_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("BASE_TEST", "Failed to get virtual interface")
    end

    // Create environment
    env = vortex_env::type_id::create("env", this);

    // Set verbosity
    if (cfg.default_verbosity != UVM_NONE) begin
      set_report_verbosity_level_hier(cfg.default_verbosity);
    end

    timeout_cycles = cfg.test_timeout_cycles;

    `uvm_info("BASE_TEST", $sformatf("Test: %s", get_type_name()), UVM_LOW)
    `uvm_info("BASE_TEST", $sformatf("Timeout: %0d cycles", timeout_cycles), UVM_MEDIUM)

  endfunction : build_phase

  //==========================================================================
  // Customize Configuration (override in derived tests)
  //==========================================================================
  virtual function void customize_config();
    // Default implementation - derived tests override this
    `uvm_info("BASE_TEST", "Using default configuration", UVM_MEDIUM)
  endfunction : customize_config

  //==========================================================================
  // Connect Phase
  //==========================================================================
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
  endfunction : connect_phase

  //==========================================================================
  // End of Elaboration Phase
  //==========================================================================
  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    
    `uvm_info("BASE_TEST", {"\n",
      "========================================\n",
      $sformatf(" Test: %s\n", get_type_name()),
      "========================================\n",
      $sformatf(" Config: %s\n", cfg.get_config_string()),
      $sformatf(" Timeout: %0d cycles\n", timeout_cycles),
      "========================================\n"
    }, UVM_LOW)

    // Print topology if debug enabled
    if (cfg.default_verbosity >= UVM_HIGH) begin
      uvm_top.print_topology();
    end

  endfunction : end_of_elaboration_phase

  //==========================================================================
  // Run Phase (override in derived tests)
  //==========================================================================
  virtual task run_phase(uvm_phase phase);
    `uvm_info("BASE_TEST", "Starting run phase", UVM_MEDIUM)
    
    phase.raise_objection(this, "Test running");

    // Wait for reset
    wait_for_reset();

    // Execute test-specific stimulus (override in derived tests)
    run_test_stimulus();

    // Wait for completion
    wait_for_completion();

    // Check results
    check_test_results();

    phase.drop_objection(this, "Test complete");

  endtask : run_phase

  //==========================================================================
  // Wait for Reset Deassertion
  //==========================================================================
  virtual task wait_for_reset();
    `uvm_info("BASE_TEST", "Waiting for reset deassertion", UVM_MEDIUM)
    @(posedge vif.resetn);
    repeat(5) @(posedge vif.clk);
    `uvm_info("BASE_TEST", "Reset complete - system ready", UVM_MEDIUM)
  endtask : wait_for_reset

  //==========================================================================
  // Run Test Stimulus (override in derived tests)
  //==========================================================================
  virtual task run_test_stimulus();
    `uvm_info("BASE_TEST", "Base test stimulus (override in derived test)", UVM_MEDIUM)
    repeat(100) @(posedge vif.clk);
  endtask : run_test_stimulus

  //==========================================================================
  // Wait for Test Completion
  //==========================================================================
  virtual task wait_for_completion();
    fork
      begin
        // Wait for EBREAK or timeout
        fork
          begin
            // Wait for EBREAK signal
            wait(vif.status_if.ebreak_detected == 1'b1);
            `uvm_info("BASE_TEST", "EBREAK detected - execution complete", UVM_LOW)
          end
          begin
            // Timeout watchdog
            repeat(timeout_cycles) @(posedge vif.clk);
            `uvm_error("BASE_TEST", $sformatf("Test timeout after %0d cycles!", timeout_cycles))
          end
        join_any
        disable fork;
      end
    join
  endtask : wait_for_completion

  //==========================================================================
  // Check Test Results
  //==========================================================================
  virtual function void check_test_results();
    if (vif.status_if.ebreak_detected) begin
      test_passed = 1'b1;
      `uvm_info("BASE_TEST", "Test completed successfully", UVM_LOW)
    end else begin
      test_passed = 1'b0;
      `uvm_error("BASE_TEST", "Test did not complete properly")
    end
  endfunction : check_test_results

  //==========================================================================
  // Report Phase
  //==========================================================================
  virtual function void report_phase(uvm_phase phase);
    uvm_report_server rs;
    int err_count;

    super.report_phase(phase);

    rs = uvm_report_server::get_server();
    err_count = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);

    `uvm_info("BASE_TEST", {"\n",
      "========================================\n",
      " Test Summary\n",
      "========================================\n",
      $sformatf(" Test Name: %s\n", get_type_name()),
      $sformatf(" Status: %s\n", (err_count == 0 && test_passed) ? "PASSED" : "FAILED"),
      $sformatf(" Errors: %0d\n", err_count),
      $sformatf(" Warnings: %0d\n", rs.get_severity_count(UVM_WARNING)),
      $sformatf(" Cycles: %0d\n", vif.status_if.cycle_count),
      $sformatf(" Instructions: %0d\n", vif.status_if.instr_count),
      "========================================\n"
    }, UVM_NONE)

    if (err_count == 0 && test_passed) begin
      `uvm_info("BASE_TEST", "*** TEST PASSED ***", UVM_NONE)
    end else begin
      `uvm_error("BASE_TEST", "*** TEST FAILED ***")
    end

  endfunction : report_phase

endclass : vortex_base_test

`endif // VORTEX_BASE_TEST_SV
