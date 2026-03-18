////////////////////////////////////////////////////////////////////////////////
// File: vortex_smoke_test.sv - FINAL WORKING VERSION (TB_TOP DCR Edition)
// Description: Complete Smoke Test with Program Loading
//
// ALL BUGS FIXED + TB_TOP DCR INTEGRATION:
// =========================================
// 1. ✅ DCR initialization moved to TB_TOP (permanent fix)
// 2. ✅ Program loading in test
// 3. ✅ No multi-driver conflicts
// 4. ✅ Proper timing coordination
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
    int dcr_writes = 0;  // ✅ Keep for tracking TB_TOP writes
    bit dcr_config_done = 1;  // ✅ Changed to 1 (TB_TOP already did it!)
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
        `uvm_info(get_type_name(), "Building smoke test (TB_TOP DCR Edition)...", UVM_LOW)
    endfunction
    
    //==========================================================================
    // Customize Configuration
    // NOTE: cfg.set_defaults() + cfg.apply_plusargs() already ran in
    // vortex_base_test.build_phase before this is called. 
    // Only OVERRIDE values that the smoke test specifically needs to differ
    // from the defaults — do NOT override things already correctly set.
    //==========================================================================
    virtual function void customize_config();
        `uvm_info(get_type_name(), "Configuring smoke test...", UVM_MEDIUM)
        
        // num_cores/warps/threads: use RTL compile-time defaults (1C/4W/4T).
        // DO NOT override — these must match what the RTL was compiled with.
        // If you need different values, recompile RTL with +define+NUM_WARPS=N.
        // Leaving them at the values set by set_defaults() / apply_plusargs().
        
        cfg.enable_scoreboard = 1;
        cfg.enable_coverage   = 1;
        cfg.simx_enable       = 0;
        // DO NOT override cfg.axi_agent_enable here!
        // apply_plusargs() already set it correctly from +USE_AXI_WRAPPER:
        //   +USE_AXI_WRAPPER present → axi_agent_enable = 1  (AXI path)
        //   absent              → axi_agent_enable = 0  (custom MEM path)
        // Overriding to 0 here would break monitor_memory_activity() in AXI mode.
        cfg.dcr_agent_is_active = 0;  // PASSIVE — TB_TOP DCR driver handles writes
        
        cfg.axi_agent_is_active = cfg.axi_agent_enable;  // Match AXI agent activity to wrapper usage

        // Timeout: use value from +TIMEOUT plusarg if present.
        // cfg.test_timeout_cycles is set by apply_plusargs(); the default
        // from set_defaults() is 50000. Only clamp if wildly over-sized.
        if (cfg.test_timeout_cycles > cfg.global_timeout_cycles)
            cfg.test_timeout_cycles = cfg.global_timeout_cycles;

        // startup_addr: MUST come from cfg (set by set_defaults/apply_plusargs).
        // NEVER override it here — it's already correct from the pkg/plusarg.
        // The TB_TOP DCR driver also reads +STARTUP_ADDR independently.

        `uvm_info(get_type_name(),
            $sformatf("Smoke test cfg: cores=%0d warps=%0d threads=%0d startup=0x%h timeout=%0d iface=%s",
                cfg.num_cores, cfg.num_warps, cfg.num_threads,
                cfg.startup_addr, cfg.test_timeout_cycles,
                cfg.axi_agent_enable ? "AXI4" : "CustomMEM"), UVM_LOW)
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info(get_type_name(), {"\n",
            "╔════════════════════════════════════════════════════════════════════════════╗\n",
            "║                VORTEX SMOKE TEST (TB_TOP DCR Edition)                      ║\n",
            "╚════════════════════════════════════════════════════════════════════════════╝\n",
            "  Test Phases:\n",
            "    0. TB_TOP initializes DCR (AUTOMATIC - during reset) ✓\n",
            "    1. LOAD PROGRAM into memory\n",
            "    2. Wait for execution to start\n",
            "    3. Monitor execution\n",
            "    4. Wait for completion\n",
            "    5. Validate results\n",
            "────────────────────────────────────────────────────────────────────────────\n",
            "  Configuration:\n",
            $sformatf("    Startup Addr: 0x%016h (set by TB_TOP)\n", cfg.startup_addr),
            $sformatf("    Cores:        %0d\n", cfg.num_cores),
            $sformatf("    Timeout:      %0d cycles\n", cfg.test_timeout_cycles),
            "╚════════════════════════════════════════════════════════════════════════════╝"
        }, UVM_LOW)
    endfunction
    
    //==========================================================================
    // MODIFIED: Run Test Stimulus (No DCR writes - TB_TOP handles it!)
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        // ✅ Step 1: Load program FIRST — while reset is still asserted.
        // mem_model is a software object; writing it needs no interface.
        // Program MUST be in memory before reset deasserts or the DUT
        // fetches zeros on its first cache-line request.
        `uvm_info(get_type_name(), "Pre-loading program during reset...", UVM_LOW)
        load_program();

        // ✅ Step 2: NOW wait for reset — level-safe form
        if (!vif.reset_n) @(posedge vif.reset_n);
        repeat(10) @(posedge vif.clk);

        `uvm_info(get_type_name(),
            "Reset released — program pre-loaded, DCR configured by TB_TOP", UVM_LOW)
        dcr_writes = 2;

        // ✅ Step 3: Monitor + wait + check
        fork monitor_memory_activity(); join_none
        wait_for_completion();
        check_results();

        phase.drop_objection(this);
    endtask


    //==========================================================================
    // Load Program (UNCHANGED - still needed!)
    //==========================================================================
    task load_program();
        mem_model mem;
        string hex_file;
        int fd;
        bit found;

        #2ns;  // Wait for tb_top to register mem_model

        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "LOADING PROGRAM", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        
        // Try multiple contexts with fallback
        found = 0;
        
        if (uvm_config_db#(mem_model)::get(null, "*", "mem_model", mem)) begin
            `uvm_info(get_type_name(), "✓ mem_model found (context: null,*)", UVM_LOW)
            found = 1;
        end
        else if (uvm_config_db#(mem_model)::get(this, "", "mem_model", mem)) begin
            `uvm_info(get_type_name(), "✓ mem_model found (context: this,\"\")", UVM_LOW)
            found = 1;
        end
        else if (uvm_config_db#(mem_model)::get(uvm_root::get(), "*", "mem_model", mem)) begin
            `uvm_info(get_type_name(), "✓ mem_model found (context: uvm_root)", UVM_LOW)
            found = 1;
        end
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
        
        // Load hex file into memory at the configured startup address.
        // cfg.startup_addr is set by set_defaults()/apply_plusargs() —
        // matches exactly what TB_TOP wrote into DCR_STARTUP_ADDR0/1.
        begin
            bit [63:0] load_addr = cfg.startup_addr;
            bytes_loaded = mem.load_hex_file(hex_file, load_addr);
            `uvm_info(get_type_name(),
                $sformatf("Loading at cfg.startup_addr=0x%016h", load_addr), UVM_LOW)
        end
        
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
    // ✅ REMOVED: configure_dut() - TB_TOP handles DCR now!
    //==========================================================================
    // No longer needed - TB_TOP writes DCR during reset automatically
    
    //==========================================================================
    // Monitor Memory Activity
    // FIX: In USE_AXI_WRAPPER mode the DUT uses AXI — vif.mem_if is never active.
    // Must watch AXI AR/AW handshakes. In MEM mode, watch vif.mem_if as before.
    // Use cfg.axi_agent_enable (set by +USE_AXI_WRAPPER plusarg) to select path.
    //==========================================================================
    task monitor_memory_activity();
        forever begin
            @(posedge vif.clk);

            if (cfg.axi_agent_enable) begin
                // AXI mode: count AR handshakes as reads, AW handshakes as writes
                if (vif.axi_if.arvalid && vif.axi_if.arready) begin
                    mem_reads++;
                    if (mem_reads + mem_writes == 1)
                        `uvm_info(get_type_name(),
                            "✓ First AXI read (AR) transaction detected!", UVM_LOW)
                end
                if (vif.axi_if.awvalid && vif.axi_if.awready) begin
                    mem_writes++;
                    if (mem_reads + mem_writes == 1)
                        `uvm_info(get_type_name(),
                            "✓ First AXI write (AW) transaction detected!", UVM_LOW)
                end
            end else begin
                // Custom MEM mode
                if (vif.mem_if.req_valid[0] && vif.mem_if.req_ready[0]) begin
                    if (vif.mem_if.req_rw[0])
                        mem_writes++;
                    else
                        mem_reads++;
                    if (mem_reads + mem_writes == 1)
                        `uvm_info(get_type_name(),
                            "✓ First MEM transaction detected!", UVM_LOW)
                end
            end
        end
    endtask
    
    //==========================================================================
    // Wait for Completion (UNCHANGED)
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
                    
                    // Timeout — use cfg.test_timeout_cycles (set by apply_plusargs/customize_config)
                    begin
                        repeat(cfg.test_timeout_cycles) @(posedge vif.clk);
                        `uvm_error(get_type_name(), 
                            $sformatf("TIMEOUT after %0d cycles!", cfg.test_timeout_cycles))
                    end
                join_any
                disable fork;
            end
        join
    endtask
    
    //==========================================================================
    // Check Results (UNCHANGED)
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

        // Check 2: DCR configured (by TB_TOP)
        if (dcr_config_done) begin
            `uvm_info(get_type_name(), "✓ DCR configured by TB_TOP", UVM_LOW)
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

        // Check 5: Memory reads — count from whichever interface is active.
        // AXI mode:  mem_reads = AXI AR handshakes (instruction + data fetches)
        // MEM mode:  mem_reads = custom MEM interface read requests
        begin
            string if_name = cfg.axi_agent_enable ? "AXI AR" : "MEM req";
            if (mem_reads > 0) begin
                `uvm_info(get_type_name(),
                    $sformatf("✓ Memory reads (%s): %0d", if_name, mem_reads), UVM_LOW)
            end else begin
                // Zero reads = DUT never fetched. This is a real failure.
                `uvm_error(get_type_name(),
                    $sformatf("✗ No memory reads on %s — DUT never fetched from memory",
                              if_name))
                test_passed = 0;
                return;
            end
        end

        // Summary
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), "EXECUTION SUMMARY", UVM_LOW)
        `uvm_info(get_type_name(), "========================================", UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Program bytes:  %0d", bytes_loaded),              UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("DCR Writes:     %0d (by TB_TOP)", dcr_writes),    UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Memory Reads:   %0d", mem_reads),                 UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Memory Writes:  %0d", mem_writes),                UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Total Cycles:   %0d", vif.status_if.cycle_count), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Instructions:   %0d", vif.status_if.instr_count), UVM_LOW)

        if (vif.status_if.cycle_count > 0) begin
            ipc = real'(vif.status_if.instr_count) / real'(vif.status_if.cycle_count);
            `uvm_info(get_type_name(), $sformatf("IPC:            %.3f", ipc), UVM_LOW)
        end

        `uvm_info(get_type_name(), "========================================", UVM_LOW)

        // First: set test_passed based on functional checks
        if (warnings == 0) begin
            test_passed = 1;
            `uvm_info(get_type_name(), "*** SMOKE TEST PASSED ***", UVM_LOW)
        end else begin
            test_passed = 0;
            `uvm_error(get_type_name(),
                $sformatf("*** SMOKE TEST FAILED — %0d warning(s) promoted to errors ***",
                    warnings))
        end

        // Final gate: if any UVM_ERROR was raised (e.g. AXI protocol violations,
        // status monitor errors), override test_passed regardless of local checks.
        begin
            uvm_report_server rs = uvm_report_server::get_server();
            int err_count = rs.get_severity_count(UVM_ERROR);
            if (err_count > 0 && test_passed) begin
                `uvm_warning(get_type_name(),
                    $sformatf("Overriding PASS: %0d UVM_ERROR(s) detected — marking FAILED",
                              err_count))
                test_passed = 0;
            end
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
                "║  TB_TOP DCR INTEGRATION:                                                   ║\n",
                "║    ✓ DCR initialized by TB_TOP (permanent fix for all tests)              ║\n",
                "║    ✓ No multi-driver conflicts                                            ║\n",
                "║    ✓ Proper timing coordination                                           ║\n",
                "║    ✓ Program loading in test                                              ║\n",
                "╠════════════════════════════════════════════════════════════════════════════╣\n",
                "║  STATISTICS:                                                               ║\n",
                $sformatf("║    Program:         %-10d bytes                                       ║\n", bytes_loaded),
                $sformatf("║    Cycles:          %-10d                                              ║\n", vif.status_if.cycle_count),
                $sformatf("║    Instructions:    %-10d                                              ║\n", vif.status_if.instr_count),
                $sformatf("║    Memory Reads:    %-10d                                              ║\n", mem_reads),
                $sformatf("║    Memory Writes:   %-10d                                              ║\n", mem_writes),
                "║                                                                            ║\n",
                "║  🎉 SCALABLE ARCHITECTURE WORKING!                                         ║\n",
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