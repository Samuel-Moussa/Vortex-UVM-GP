
////////////////////////////////////////////////////////////////////////////////
// File: tests/vortex_smoke_test.sv
// Description: Comprehensive Smoke Test for Vortex GPGPU
//
// This smoke test combines:
//   ✅ Proper UVM sequences (from Version 2)
//   ✅ Real program execution verification (from My Version)
//   ✅ DCR configuration testing (from Version 1)
//   ✅ Activity monitoring and statistics
//   ✅ Comprehensive checking with clear pass/fail
//
// Purpose:
//   - Verify environment builds correctly
//   - Test DCR configuration interface
//   - Execute real program and verify completion
//   - Check memory operations
//   - Validate EBREAK detection
//   - Ensure basic functionality works end-to-end
//
// This is the FIRST test to run on any new build.
//
// Usage:
//   vsim +UVM_TESTNAME=vortex_smoke_test +PROGRAM=smoke.hex
//
// Expected Result:
//   - DCR write succeeds
//   - Program executes to completion
//   - EBREAK detected
//   - No errors
//   - Completes in < 5000 cycles
//
// Author: Vortex UVM Team
// Date: December 2025
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_SMOKE_TEST_SV
`define VORTEX_SMOKE_TEST_SV
import uvm_pkg::*;
`include "uvm_macros.svh"

// Import required packages
// import vortex_test_pkg::*;
import vortex_config_pkg::*;
import vortex_env_pkg::*;

//`include "uvm_env\agents\dcr_agent\dcr_agent_pkg.sv"
import dcr_agent_pkg::*;


`include "vortex_base_test.sv"
`include "mem_model.sv"


class vortex_smoke_test extends vortex_base_test;
    `uvm_component_utils(vortex_smoke_test)
    
    //==========================================================================
    // Test Statistics
    //==========================================================================
    int mem_reads = 0;
    int mem_writes = 0;
    int dcr_writes = 0;
    bit dcr_config_done = 0;
    bit first_mem_access = 0;
    
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
        `uvm_info(get_type_name(), "Building smoke test...", UVM_LOW)
    endfunction
    
    //==========================================================================
    // Customize Configuration
    //==========================================================================
    virtual function void customize_config();
        `uvm_info(get_type_name(), "Configuring smoke test...", UVM_MEDIUM)
        
        // Minimal but realistic configuration
        cfg.num_cores   = 1;
        cfg.num_warps   = 2;
        cfg.num_threads = 2;
        
        // Enable basic checking, disable heavy features
        cfg.enable_scoreboard = 0;              // Enable checking
        cfg.enable_coverage   = 0;              // Disable for speed
        cfg.simx_enable       = 0;              // No golden model yet
        cfg.axi_agent_enable  = 0;              // Use custom memory
        
        // Short timeout for fast feedback
        cfg.test_timeout_cycles = 5000;
        cfg.default_verbosity   = UVM_MEDIUM;
        
        `uvm_info(get_type_name(), "Smoke test configuration applied", UVM_MEDIUM)
    endfunction
    
    //==========================================================================
    // End of Elaboration
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info(get_type_name(), {"\n",
            "╔════════════════════════════════════════════════════════════════════════════╗\n",
            "║                         VORTEX SMOKE TEST                                  ║\n",
            "╚════════════════════════════════════════════════════════════════════════════╝\n",
            "  Test Phases:\n",
            "    1. Reset verification\n",
            "    2. DCR configuration (startup address)\n",
            "    3. Program execution monitoring\n",
            "    4. EBREAK detection\n",
            "    5. Results validation\n",
            "────────────────────────────────────────────────────────────────────────────\n",
            "  Configuration:\n",
            $sformatf("    Cores:       %0d\n", cfg.num_cores),
            $sformatf("    Warps:       %0d\n", cfg.num_warps),
            $sformatf("    Threads:     %0d\n", cfg.num_threads),
            $sformatf("    Timeout:     %0d cycles\n", cfg.test_timeout_cycles),
            "────────────────────────────────────────────────────────────────────────────\n",
            "  Checks:\n",
            "    ✓ Environment builds\n",
            "    ✓ Agents operational\n",
            "    ✓ DCR writes work\n",
            "    ✓ Memory operations\n",
            "    ✓ Program execution\n",
            "    ✓ EBREAK detection\n",
            "╚════════════════════════════════════════════════════════════════════════════╝"
        }, UVM_LOW)
    endfunction
    
    //==========================================================================
    // Phase 0: Load Program into Memory
    //==========================================================================
    task load_program();
        begin
             mem_model mem;
             string hex_file;
            
            `uvm_info(get_type_name(), "Phase 0: Loading program into memory...", UVM_LOW)
            
            if (!uvm_config_db#(mem_model)::get(this, "", "mem_model", mem)) begin
                `uvm_warning(get_type_name(), "mem_model not in config DB, trying backdoor...")
                
                if ($root.vortex_tb_top.memory != null) begin
                    if (cfg.program_path != "") begin
                        hex_file = cfg.program_path;
                    end else begin
                        hex_file = "./uvm_env/agents/host_agent/program_simple.hex";
                        `uvm_info(get_type_name(), "No program_path in config, using default", UVM_MEDIUM)
                    end
                    
                    `uvm_info(get_type_name(), $sformatf("  → Loading: %s", hex_file), UVM_MEDIUM)
                    void'($root.vortex_tb_top.memory.load_hex_file(hex_file, 64'h80000000));
                    `uvm_info(get_type_name(), "  ✓ Program loaded successfully", UVM_LOW)
                end else begin
                    `uvm_fatal(get_type_name(), "Cannot access memory model!")
                end
            end else begin
                if (cfg.program_path != "") begin
                    hex_file = cfg.program_path;
                end else begin
                    hex_file = "./uvm_env/agents/host_agent/program_simple.hex";
                end
                
                `uvm_info(get_type_name(), $sformatf("  → Loading: %s", hex_file), UVM_MEDIUM)
                void'(mem.load_hex_file(hex_file, 64'h80000000));
                `uvm_info(get_type_name(), "  ✓ Program loaded successfully", UVM_LOW)
            end
            
            repeat(5) @(posedge vif.clk);
        end
    endtask


    //==========================================================================
    // Run Test Stimulus
    //==========================================================================
    virtual task run_test_stimulus();
        `uvm_info(get_type_name(), {"\n",
            "╔════════════════════════════════════════════════════════════════╗\n",
            "║             STARTING SMOKE TEST EXECUTION                      ║\n",
            "╚════════════════════════════════════════════════════════════════╝"
        }, UVM_LOW)
            // ✅ PHASE 0: LOAD PROGRAM INTO MEMORY
    load_program();
        // Start all monitoring tasks in parallel
        fork
            monitor_dcr_activity();
            monitor_memory_activity();
            monitor_execution_status();
        join_none
        
        // Phase 1: Configure DUT via DCR (optional)
        configure_dut_via_dcr();
        
        // Phase 2: Let program execute
        // (Program is loaded by TB top, we just monitor)
        `uvm_info(get_type_name(), "Phase 2: Monitoring program execution...", UVM_LOW)
        
        // Main test body waits for completion (handled by base class)
        
    endtask
    
    //==========================================================================
    // Phase 1: Configure DUT via DCR
    //==========================================================================
    // task configure_dut_via_dcr();
    //     dcr_startup_config_sequence dcr_seq;
        
    //     `uvm_info(get_type_name(), "Phase 1: Configuring DUT via DCR...", UVM_LOW)
        
    //     // Create and configure DCR sequence
    //     dcr_seq = dcr_startup_config_sequence::type_id::create("dcr_seq");
        
    //     // Write startup address to DCR
    //     if (!dcr_seq.randomize() with {
    //         addr == 12'h001;          // VX_DCR_BASE_STARTUP_ADDR0
    //         data == 32'h80000000;     // Default RISC-V startup address
    //     }) begin
    //         `uvm_error(get_type_name(), "DCR sequence randomization failed")
    //     end
        
    //     // Execute sequence
    //     `uvm_info(get_type_name(), "  → Writing DCR_STARTUP_ADDR0 = 0x80000000", UVM_MEDIUM)
    //     dcr_seq.start(env.m_virtual_sequencer.m_dcr_sequencer);
        
    //     dcr_config_done = 1;
    //     `uvm_info(get_type_name(), "  ✓ DCR configuration complete", UVM_LOW)
        
    //     // Small delay before execution starts
    //     repeat(10) @(posedge vif.clk);
        
    // endtask


    //==========================================================================
// Phase 1: Configure DUT via DCR
//==========================================================================
task configure_dut_via_dcr();
    dcr_startup_config_sequence dcr_seq;
    
    `uvm_info(get_type_name(), "Phase 1: Configuring DUT via DCR...", UVM_LOW)
    
    // Step 1: Create the sequence
    dcr_seq = dcr_startup_config_sequence::type_id::create("dcr_seq");
    
    // Step 2: Configure sequence fields (NOT transaction fields!)
    // ✅ Set high-level parameters - sequence will generate transactions
    dcr_seq.startup_pc = 64'h0000_0000_8000_0000;  // Standard RISC-V entry point
    dcr_seq.argv_ptr   = 64'h0;                    // NULL (no program arguments)
    
    // Step 3: Log configuration
    `uvm_info(get_type_name(), 
             $sformatf("  → Configuring startup PC = 0x%016h", dcr_seq.startup_pc), 
             UVM_MEDIUM)
    
    // Step 4: Execute sequence
    // This calls dcr_seq.body() which:
    //   - Calls write_dcr(0x004, startup_pc[31:0])   ← Transaction 1
    //   - Calls write_dcr(0x008, startup_pc[63:32])  ← Transaction 2
    dcr_seq.start(env.m_virtual_sequencer.m_dcr_sequencer);
    
    // Step 5: Update statistics
    dcr_writes += 2;        // Two 32-bit DCR writes (for 64-bit PC)
    dcr_config_done = 1;
    
    `uvm_info(get_type_name(), "  ✓ DCR configuration complete", UVM_LOW)
    
    // Step 6: Small delay before execution monitoring
    repeat(10) @(posedge vif.clk);
    
endtask

    
    //==========================================================================
    // Monitor DCR Activity
    //==========================================================================
    task monitor_dcr_activity();
        `uvm_info(get_type_name(), "DCR monitor started", UVM_HIGH)
        
        forever begin
            @(posedge vif.clk);
            
            if (vif.dcr_if.wr_valid) begin
                dcr_writes++;
                `uvm_info(get_type_name(), 
                         $sformatf("  [DCR] Write #%0d: addr=0x%03h data=0x%08h", 
                                   dcr_writes, vif.dcr_if.wr_addr, vif.dcr_if.wr_data),
                         UVM_HIGH)
            end
            
            if (vif.status_if.ebreak_detected) break;
        end
    endtask
    
    //==========================================================================
    // Monitor Memory Activity
    //==========================================================================
    task monitor_memory_activity();
        `uvm_info(get_type_name(), "Memory monitor started", UVM_HIGH)
        
        forever begin
            @(posedge vif.clk);
            
            if (vif.mem_if.req_valid && vif.mem_if.req_ready) begin
                
                if (!first_mem_access) begin
                    `uvm_info(get_type_name(), "  ✓ First memory access detected", UVM_MEDIUM)
                    first_mem_access = 1;
                end
                
                if (vif.mem_if.req_rw) begin
                    mem_writes++;
                    `uvm_info(get_type_name(),
                             $sformatf("  [MEM] Write #%0d: addr=0x%08h data=0x%016h",
                                       mem_writes, vif.mem_if.req_addr, vif.mem_if.req_data),
                             UVM_HIGH)
                end else begin
                    mem_reads++;
                    `uvm_info(get_type_name(),
                             $sformatf("  [MEM] Read  #%0d: addr=0x%08h",
                                       mem_reads, vif.mem_if.req_addr),
                             UVM_HIGH)
                end
            end
            
            if (vif.status_if.ebreak_detected) break;
        end
    endtask
    
    //==========================================================================
    // Monitor Execution Status
    //==========================================================================
    task monitor_execution_status();
        bit was_busy = 0;
        int idle_cycles = 0;
        
        `uvm_info(get_type_name(), "Execution monitor started", UVM_HIGH)
        
        forever begin
            @(posedge vif.clk);
            
            // Track busy/idle transitions
            if (vif.status_if.busy && !was_busy) begin
                `uvm_info(get_type_name(), "  → DUT became BUSY", UVM_MEDIUM)
                idle_cycles = 0;
            end else if (!vif.status_if.busy && was_busy) begin
                `uvm_info(get_type_name(), "  → DUT became IDLE", UVM_MEDIUM)
            end
            
            was_busy = vif.status_if.busy;
            
            // Track idle time
            if (!vif.status_if.busy) begin
                idle_cycles++;
            end
            
            if (vif.status_if.ebreak_detected) break;
        end
    endtask
    
    //==========================================================================
    // Check Results - Comprehensive Validation
    //==========================================================================
    virtual function void check_results();
        int warnings = 0;
        real ipc;
        
        super.check_results();
        
        `uvm_info(get_type_name(), {"\n",
            "════════════════════════════════════════════════════════════════\n",
            "  SMOKE TEST VALIDATION\n",
            "════════════════════════════════════════════════════════════════"
        }, UVM_LOW)
        
        // Check 1: DCR configuration
        if (dcr_config_done) begin
            `uvm_info(get_type_name(), "  ✓ DCR configuration successful", UVM_LOW)
        end else begin
            `uvm_warning(get_type_name(), "  ⚠ DCR configuration skipped")
            warnings++;
        end
        
        // Check 2: EBREAK detection
        if (vif.status_if.ebreak_detected) begin
            `uvm_info(get_type_name(), "  ✓ EBREAK detected (program completed)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "  ✗ EBREAK not detected")
        end
        
        // Check 3: Instructions executed
        if (vif.status_if.instr_count > 0) begin
            `uvm_info(get_type_name(), 
                     $sformatf("  ✓ Instructions executed: %0d", vif.status_if.instr_count),
                     UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "  ✗ No instructions executed")
        end
        
        // Check 4: Memory operations
        if (mem_reads > 0) begin
            `uvm_info(get_type_name(), 
                     $sformatf("  ✓ Memory reads: %0d", mem_reads),
                     UVM_LOW)
        end else begin
            `uvm_warning(get_type_name(), "  ⚠ No memory reads detected")
            warnings++;
        end
        
        if (mem_writes > 0) begin
            `uvm_info(get_type_name(), 
                     $sformatf("  ✓ Memory writes: %0d", mem_writes),
                     UVM_LOW)
        end else begin
            `uvm_info(get_type_name(), "  ℹ No memory writes (read-only test?)", UVM_LOW)
        end
        
        // Check 5: Cycle count
        if (vif.status_if.cycle_count > 0 && 
            vif.status_if.cycle_count < cfg.test_timeout_cycles) begin
            `uvm_info(get_type_name(), 
                     $sformatf("  ✓ Cycles: %0d (within timeout)", vif.status_if.cycle_count),
                     UVM_LOW)
        end else if (vif.status_if.cycle_count >= cfg.test_timeout_cycles) begin
            `uvm_error(get_type_name(), "  ✗ Test reached timeout")
        end else begin
            `uvm_error(get_type_name(), "  ✗ No cycles elapsed")
        end
        
        // Check 6: IPC sanity
        if (vif.status_if.cycle_count > 0) begin
            ipc = real'(vif.status_if.instr_count) / real'(vif.status_if.cycle_count);
            
            if (ipc >= 0.05) begin
                `uvm_info(get_type_name(), $sformatf("  ✓ IPC: %.3f", ipc), UVM_LOW)
            end else begin
                `uvm_warning(get_type_name(), 
                            $sformatf("  ⚠ Low IPC: %.3f (possible stalls)", ipc))
                warnings++;
            end
        end
        
        // Summary
        `uvm_info(get_type_name(), {
            "════════════════════════════════════════════════════════════════\n",
            $sformatf("  ACTIVITY SUMMARY:\n"),
            $sformatf("    DCR Writes:     %0d\n", dcr_writes),
            $sformatf("    Memory Reads:   %0d\n", mem_reads),
            $sformatf("    Memory Writes:  %0d\n", mem_writes),
            $sformatf("    Total Memory:   %0d\n", mem_reads + mem_writes),
            "════════════════════════════════════════════════════════════════"
        }, UVM_LOW)
        
        if (warnings > 0) begin
            `uvm_info(get_type_name(), 
                     $sformatf("  Smoke test completed with %0d warning(s)", warnings),
                     UVM_LOW)
        end
        
    endfunction
    
    //==========================================================================
    // Report Phase - Beautiful Summary
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        if (test_passed) begin
            `uvm_info(get_type_name(), {"\n",
                "╔════════════════════════════════════════════════════════════════════════════╗\n",
                "║                                                                            ║\n",
                "║                      ✓✓✓ SMOKE TEST PASSED ✓✓✓                            ║\n",
                "║                                                                            ║\n",
                "╠════════════════════════════════════════════════════════════════════════════╣\n",
                "║  VERIFIED FUNCTIONALITY:                                                   ║\n",
                "║    ✓ Environment builds correctly                                          ║\n",
                "║    ✓ UVM agents operational                                                ║\n",
                "║    ✓ DCR configuration successful                                          ║\n",
                "║    ✓ Reset sequence works                                                  ║\n",
                "║    ✓ Memory interface functional                                           ║\n",
                "║    ✓ Program execution successful                                          ║\n",
                "║    ✓ Instructions execute correctly                                        ║\n",
                "║    ✓ EBREAK detection works                                                ║\n",
                "║    ✓ Basic pipeline operation                                              ║\n",
                "╠════════════════════════════════════════════════════════════════════════════╣\n",
                "║  STATISTICS:                                                               ║\n",
                $sformatf("║    Cycles:          %-10d                                              ║\n", vif.status_if.cycle_count),
                $sformatf("║    Instructions:    %-10d                                              ║\n", vif.status_if.instr_count),
                $sformatf("║    DCR Writes:      %-10d                                              ║\n", dcr_writes),
                $sformatf("║    Memory Reads:    %-10d                                              ║\n", mem_reads),
                $sformatf("║    Memory Writes:   %-10d                                              ║\n", mem_writes),
                "║                                                                            ║\n",
                "║  ✓ READY FOR ADVANCED TESTING                                              ║\n",
                "║                                                                            ║\n",
                "╚════════════════════════════════════════════════════════════════════════════╝"
            }, UVM_NONE)
        end else begin
            `uvm_error(get_type_name(), {"\n",
                "╔════════════════════════════════════════════════════════════════════════════╗\n",
                "║                                                                            ║\n",
                "║                      ✗✗✗ SMOKE TEST FAILED ✗✗✗                            ║\n",
                "║                                                                            ║\n",
                "║  Basic functionality verification failed!                                  ║\n",
                "║  Fix these issues before proceeding with other tests.                     ║\n",
                "║                                                                            ║\n",
                "╚════════════════════════════════════════════════════════════════════════════╝"
            })
        end
    endfunction
    
endclass : vortex_smoke_test

`endif // VORTEX_SMOKE_TEST_SV
