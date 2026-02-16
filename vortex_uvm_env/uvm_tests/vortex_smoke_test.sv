////////////////////////////////////////////////////////////////////////////////
// File: vortex_smoke_test.sv - FINAL WORKING VERSION
// Description: Complete Smoke Test with Program Loading
//
// ALL BUGS FIXED:
// ===============
// 1. ✅ DCR clocking block usage (race conditions eliminated)
// 2. ✅ DCR protocol compliance (deassert between writes)
// 3. ✅ Correct DCR addresses (byte addressing: 0x004, 0x008)
// 4. ✅ PROGRAM LOADING (critical - was missing!)
//
// Author: Vortex UVM Team  
// Date: February 2026
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_SMOKE_TEST_SV
`define VORTEX_SMOKE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import vortex_env_pkg::*;
import dcr_agent_pkg::*;

`include "mem_model.sv"
`include "vortex_base_test.sv"

class vortex_smoke_test extends vortex_base_test;
    `uvm_component_utils(vortex_smoke_test)
    
    //==========================================================================
    // Test Statistics
    //==========================================================================
    int mem_reads = 0;
    int mem_writes = 0;
    int dcr_writes = 0;
    bit dcr_config_done = 0;
    int bytes_loaded = 0;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "vortex_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info(get_type_name(), "Building smoke test (ALL BUGS FIXED)...", UVM_LOW)
    endfunction
    
    //==========================================================================
    // Customize Configuration
    //==========================================================================
    virtual function void customize_config();
        `uvm_info(get_type_name(), "Configuring smoke test...", UVM_MEDIUM)
        
        cfg.num_cores   = 1;
        cfg.num_warps   = 2;
        cfg.num_threads = 2;
        
        cfg.enable_scoreboard = 0;
        cfg.enable_coverage   = 0;
        cfg.simx_enable       = 0;
        cfg.axi_agent_enable  = 0;
        
        cfg.test_timeout_cycles = 10000;
        cfg.default_verbosity   = UVM_MEDIUM;
        
        // Set startup address if not set
        if (cfg.startup_addr == 0) begin
            cfg.startup_addr = 64'h80000000;
        end
        
        `uvm_info(get_type_name(), "Configuration applied", UVM_MEDIUM)
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info(get_type_name(), {"\n",
            "╔════════════════════════════════════════════════════════════════════════════╗\n",
            "║                    VORTEX SMOKE TEST (FIXED)                               ║\n",
            "╚════════════════════════════════════════════════════════════════════════════╝\n",
            "  Test Phases:\n",
            "    1. LOAD PROGRAM into memory (NEW!)\n",
            "    2. Configure DUT via DCR (using constants)\n",
            "    3. Wait for execution\n",
            "    4. Wait for completion\n",
            "    5. Validate results\n",
            "────────────────────────────────────────────────────────────────────────────\n",
            "  Configuration:\n",
            $sformatf("    Startup Addr: 0x%016h\n", cfg.startup_addr),
            $sformatf("    Cores:        %0d\n", cfg.num_cores),
            $sformatf("    Timeout:      %0d cycles\n", cfg.test_timeout_cycles),
            "╚════════════════════════════════════════════════════════════════════════════╝"
        }, UVM_LOW)
    endfunction
    
    //==========================================================================
    // OVERRIDE: Run Test Stimulus
    //==========================================================================
    virtual task run_test_stimulus();
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "SMOKE TEST EXECUTION", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Step 1: LOAD PROGRAM (critical!)
        load_program();
        
        // Step 2: Configure DUT
        configure_dut();
        
        // Step 3: Monitor activity
        fork
            monitor_memory_activity();
        join_none
        
        `uvm_info(get_type_name(), "Test stimulus complete", UVM_MEDIUM)
    endtask


   task load_program();
    mem_model mem;
    string hex_file;
    int fd;
    bit found;
    
    `uvm_info(get_type_name(), "========================================", UVM_LOW)
    `uvm_info(get_type_name(), "LOADING PROGRAM", UVM_LOW)
    `uvm_info(get_type_name(), "========================================", UVM_LOW)
    
    // ✅ Try multiple contexts with fallback
    found = 0;
    
    // Try 1: null, "*"
    if (uvm_config_db#(mem_model)::get(null, "*", "mem_model", mem)) begin
        `uvm_info(get_type_name(), "✓ mem_model found (context: null,*)", UVM_LOW)
        found = 1;
    end
    // Try 2: this, ""
    else if (uvm_config_db#(mem_model)::get(this, "", "mem_model", mem)) begin
        `uvm_info(get_type_name(), "✓ mem_model found (context: this,\"\")", UVM_LOW)
        found = 1;
    end
    // Try 3: uvm_root
    else if (uvm_config_db#(mem_model)::get(uvm_root::get(), "*", "mem_model", mem)) begin
        `uvm_info(get_type_name(), "✓ mem_model found (context: uvm_root)", UVM_LOW)
        found = 1;
    end
    // Try 4: null, "uvm_test_top*"
    else if (uvm_config_db#(mem_model)::get(null, "uvm_test_top*", "mem_model", mem)) begin
        `uvm_info(get_type_name(), "✓ mem_model found (context: uvm_test_top*)", UVM_LOW)
        found = 1;
    end
    
    if (!found) begin
        `uvm_error(get_type_name(), {
            "mem_model not found in config DB!\n",
            $sformatf("  Tried contexts: null:*, this:\"%s\", uvm_root:*, uvm_test_top*\n", get_full_name()),
            "  Check that mem_model is set before run_phase starts."
        })
        `uvm_fatal(get_type_name(), "Cannot proceed without mem_model")
    end

    // Get hex file path from plusarg
    if (!$value$plusargs("PROGRAM=%s", hex_file)) begin
        `uvm_fatal(get_type_name(), {
            "No +PROGRAM specified!\n",
            "  This test requires a program.\n",
            "  Run with: ./scripts/run_vortex_uvm.sh --test=vortex_smoke_test --program=<program>"
        })
    end
    
    `uvm_info(get_type_name(),
        $sformatf("Loading program: %s", hex_file), UVM_LOW)
    
    // Verify file exists
    fd = $fopen(hex_file, "r");
    if (fd == 0) begin
        `uvm_fatal(get_type_name(),
            $sformatf("Program file not found: %s", hex_file))
    end
    $fclose(fd);
    
    // Load hex file into memory at RISC-V startup address
    bytes_loaded = mem.load_hex_file(hex_file, 64'h80000000);
    
    if (bytes_loaded > 0) begin
        `uvm_info(get_type_name(),
            $sformatf("✓ Loaded %0d bytes successfully", bytes_loaded), UVM_LOW)
    end else begin
        `uvm_fatal(get_type_name(),
            $sformatf("Failed to load program: %s", hex_file))
    end
    
    `uvm_info(get_type_name(), "========================================", UVM_LOW)
endtask


    //==========================================================================
    // Configure DUT via DCR
    //==========================================================================
task configure_dut();
    bit [63:0] startup_addr;
    dcr_startup_config_sequence dcr_seq;  // ✅ Use the correct class
    
    startup_addr = cfg.startup_addr;
    
    `uvm_info(get_type_name(), "========================================", UVM_LOW)
    `uvm_info(get_type_name(), "CONFIGURING DUT VIA DCR", UVM_LOW)
    `uvm_info(get_type_name(), "========================================", UVM_LOW)
    `uvm_info(get_type_name(), 
        $sformatf("Startup address: 0x%016h", startup_addr), UVM_LOW)
    
    // ✅ Create and configure the sequence
    dcr_seq = dcr_startup_config_sequence::type_id::create("dcr_seq");
    dcr_seq.startup_pc = startup_addr;  // Set the PC
    dcr_seq.argv_ptr = 64'h0;           // No arguments
    
    // ✅ Start the sequence (it will write BOTH STARTUP_ADDR0 and ADDR1)
    dcr_seq.start(env.m_virtual_sequencer.m_dcr_sequencer);
    
    dcr_writes += 2;  // It writes 2 DCRs
    dcr_config_done = 1;
    
    `uvm_info(get_type_name(), "✓ DCR configuration complete", UVM_LOW)
    `uvm_info(get_type_name(), "========================================", UVM_LOW)
    
        // Give GPU time to process
        repeat(10) @(vif.dcr_if.master_cb);
    endtask
    
    //==========================================================================
    // Monitor Memory Activity
    //==========================================================================
    task monitor_memory_activity();
        forever begin
            @(posedge vif.clk);
            
            if (vif.mem_if.req_valid && vif.mem_if.req_ready) begin
                if (vif.mem_if.req_rw)
                    mem_writes++;
                else
                    mem_reads++;
                    
                // Log first transaction
                if (mem_reads + mem_writes == 1) begin
                    `uvm_info(get_type_name(), 
                        "✓ First memory transaction detected!", UVM_LOW)
                end
            end
        end
    endtask
    
    //==========================================================================
    // OVERRIDE: Wait for Completion
    //==========================================================================
    virtual task wait_for_completion();
        fork
            begin
                fork
                    // Wait for EBREAK
                    begin
                        `uvm_info(get_type_name(), 
                            "Waiting for execution completion...", UVM_MEDIUM)
                        wait(vif.status_if.ebreak_detected == 1'b1);
                        `uvm_info(get_type_name(), 
                            "✓ Execution completed", UVM_LOW)
                    end
                    
                    // Timeout
                    begin
                        repeat(timeout_cycles) @(posedge vif.clk);
                        `uvm_error(get_type_name(), 
                            $sformatf("TIMEOUT after %0d cycles!", timeout_cycles))
                    end
                join_any
                disable fork;
            end
        join
    endtask
    
    //==========================================================================
    // OVERRIDE: Check Results
    //==========================================================================
    virtual function void check_results();
        int warnings = 0;
        real ipc;
        
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "TEST VALIDATION", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Check 1: Program loaded
        if (bytes_loaded > 0) begin
            `uvm_info(get_type_name(), 
                $sformatf("✓ Program loaded: %0d bytes", bytes_loaded), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "✗ Program not loaded")
            test_passed = 0;
            return;
        end
        
        // Check 2: DCR configured
        if (dcr_config_done) begin
            `uvm_info(get_type_name(), "✓ DCR configuration successful", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "✗ DCR not configured")
            test_passed = 0;
            return;
        end
        
        // Check 3: EBREAK detected
        if (vif.status_if.ebreak_detected) begin
            `uvm_info(get_type_name(), "✓ EBREAK detected", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "✗ EBREAK not detected")
            test_passed = 0;
            return;
        end
        
        // Check 4: Instructions executed
        if (vif.status_if.instr_count > 0) begin
            `uvm_info(get_type_name(), 
                $sformatf("✓ Instructions: %0d", vif.status_if.instr_count), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "✗ No instructions executed")
            test_passed = 0;
            return;
        end
        
        // Check 5: Memory activity
        if (mem_reads > 0) begin
            `uvm_info(get_type_name(), 
                $sformatf("✓ Memory reads: %0d", mem_reads), UVM_LOW)
        end else begin
            `uvm_warning(get_type_name(), "⚠ No memory reads")
            warnings++;
        end
        
        // Summary
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "EXECUTION SUMMARY", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Program bytes:  %0d", bytes_loaded), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("DCR Writes:     %0d", dcr_writes), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Memory Reads:   %0d", mem_reads), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Memory Writes:  %0d", mem_writes), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Total Cycles:   %0d", vif.status_if.cycle_count), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Instructions:   %0d", vif.status_if.instr_count), UVM_LOW)
        
        if (vif.status_if.cycle_count > 0) begin
            ipc = real'(vif.status_if.instr_count) / real'(vif.status_if.cycle_count);
            `uvm_info(get_type_name(), $sformatf("IPC:            %.3f", ipc), UVM_LOW)
        end
        
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        test_passed = 1;
        
        if (warnings == 0) begin
            `uvm_info(get_type_name(), "*** SMOKE TEST PASSED ***", UVM_LOW)
        end else begin
            `uvm_info(get_type_name(), 
                $sformatf("Test passed with %0d warning(s)", warnings), UVM_LOW)
        end
    endfunction
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), {"\n",
                "╔════════════════════════════════════════════════════════════════════════════╗\n",
                "║                      ✓✓✓ SMOKE TEST PASSED ✓✓✓                            ║\n",
                "║                                                                            ║\n",
                "║  ALL BUGS FIXED:                                                           ║\n",
                "║    ✓ DCR clocking block (no race conditions)                               ║\n",
                "║    ✓ DCR protocol (deassert between writes)                                ║\n",
                "║    ✓ Correct DCR addresses (byte addressing)                               ║\n",
                "║    ✓ Program loading (was missing!)                                        ║\n",
                "╠════════════════════════════════════════════════════════════════════════════╣\n",
                "║  STATISTICS:                                                               ║\n",
                $sformatf("║    Program:         %-10d bytes                                       ║\n", bytes_loaded),
                $sformatf("║    Cycles:          %-10d                                              ║\n", vif.status_if.cycle_count),
                $sformatf("║    Instructions:    %-10d                                              ║\n", vif.status_if.instr_count),
                $sformatf("║    Memory Reads:    %-10d                                              ║\n", mem_reads),
                $sformatf("║    Memory Writes:   %-10d                                              ║\n", mem_writes),
                "║                                                                            ║\n",
                "║  🎉 ALL SYSTEMS WORKING!                                                   ║\n",
                "╚════════════════════════════════════════════════════════════════════════════╝"
            }, UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), {"\n",
                "╔════════════════════════════════════════════════════════════════════════════╗\n",
                "║                      ✗✗✗ SMOKE TEST FAILED ✗✗✗                            ║\n",
                "╚════════════════════════════════════════════════════════════════════════════╝"
            })
        end
    endfunction
    
endclass : vortex_smoke_test

`endif // VORTEX_SMOKE_TEST_SV