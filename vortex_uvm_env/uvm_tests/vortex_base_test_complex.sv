////////////////////////////////////////////////////////////////////////////////
// File: tests/vortex_base_test.sv
// Description: Enhanced base test class for Vortex GPGPU UVM verification
//
// This is a hybrid approach combining:
//   ✅ Professional formatting and reporting (from your version)
//   ✅ Flexible dependency handling (supports with/without env)
//   ✅ Comprehensive helper methods
//   ✅ Full UVM phase usage
//   ✅ Rich statistics and timing
//   ✅ Can work standalone or with full environment
//
// Author: Vortex UVM Team
// Date: December 2025
// Version: 2.0 (Ultimate Hybrid)
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_BASE_TEST_SV
`define VORTEX_BASE_TEST_SV

class vortex_base_test extends uvm_test;
    
    `uvm_component_utils(vortex_base_test)
    
    //==========================================================================
    // Configuration & Environment
    //==========================================================================
    
    // Environment (optional - can work without it for early testing)
    `ifdef USE_VORTEX_ENV
        vortex_env env;
    `endif
    
    // Configuration (optional - has fallback)
    `ifdef USE_VORTEX_CONFIG
        vortex_config cfg;
    `endif
    
    // Memory model (optional - can use TB top's memory or create own)
    `ifdef USE_LOCAL_MEMORY
        mem_model mem;
    `endif
    
    //==========================================================================
    // Virtual Interfaces (Always available)
    //==========================================================================
    
    virtual vortex_if        vif;
    virtual vortex_mem_if    mem_vif;
    virtual vortex_dcr_if    dcr_vif;
    virtual vortex_status_if status_vif;
    virtual vortex_axi_if    axi_vif;
    
    //==========================================================================
    // Test Configuration
    //==========================================================================
    
    // Test control
    int  test_timeout     = 10000;        // Timeout in cycles
    bit  expect_ebreak    = 1'b1;         // Expect EBREAK completion
    int  test_verbosity   = UVM_MEDIUM;   // Default verbosity
    bit  enable_scoreboard = 1'b1;        // Enable checking
    bit  enable_coverage  = 1'b1;         // Enable coverage
    
    // Program loading
    string program_file   = "";
    bit [63:0] load_addr  = 64'h80000000; // Default RISC-V address
    
    // Test result tracking
    bit  test_passed;
    time start_time;
    time end_time;
    
    // Statistics
    int total_cycles;
    int total_instructions;
    real ipc;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    
    function new(string name = "vortex_base_test", uvm_component parent = null);
        super.new(name, parent);
        test_passed = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        `uvm_info(get_type_name(), "Building test...", UVM_LOW)
        
        // Get virtual interfaces from config_db (always required)
        if (!uvm_config_db#(virtual vortex_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "Failed to get vortex_if from config_db!")
        end
        
        if (!uvm_config_db#(virtual vortex_mem_if)::get(this, "", "vif_mem", mem_vif)) begin
            `uvm_fatal(get_type_name(), "Failed to get vortex_mem_if from config_db!")
        end
        
        if (!uvm_config_db#(virtual vortex_dcr_if)::get(this, "", "vif_dcr", dcr_vif)) begin
            `uvm_fatal(get_type_name(), "Failed to get vortex_dcr_if from config_db!")
        end
        
        if (!uvm_config_db#(virtual vortex_status_if)::get(this, "", "vif_status", status_vif)) begin
            `uvm_fatal(get_type_name(), "Failed to get vortex_status_if from config_db!")
        end
        
        // AXI interface is optional
        if (!uvm_config_db#(virtual vortex_axi_if)::get(this, "", "vif_axi", axi_vif)) begin
            `uvm_info(get_type_name(), "AXI interface not available (using custom memory interface)", UVM_LOW)
        end
        
        `uvm_info(get_type_name(), "Virtual interfaces retrieved successfully", UVM_LOW)
        
        // Create configuration (if using config package)
        `ifdef USE_VORTEX_CONFIG
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
            cfg.apply_plusargs();
            configure_test();  // Test-specific config
            uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);
            `uvm_info(get_type_name(), "Configuration created and set", UVM_LOW)
        `else
            // Apply command-line overrides directly
            apply_plusargs();
            configure_test();  // Test-specific config
            `uvm_info(get_type_name(), "Using direct configuration (no config class)", UVM_LOW)
        `endif
        
        // Create local memory model if requested
        `ifdef USE_LOCAL_MEMORY
            mem = new();
            uvm_config_db#(mem_model)::set(this, "*", "mem_model", mem);
            `uvm_info(get_type_name(), "Local memory model created", UVM_LOW)
        `endif
        
        // Create environment if available
        `ifdef USE_VORTEX_ENV
            env = vortex_env::type_id::create("env", this);
            `uvm_info(get_type_name(), "Environment created", UVM_LOW)
        `else
            `uvm_info(get_type_name(), "Running without environment (standalone mode)", UVM_LOW)
        `endif
        
        // Set test verbosity
        set_report_verbosity_level_hier(test_verbosity);
        
    endfunction
    
    //==========================================================================
    // Apply Command-Line Arguments (Fallback when no config class)
    //==========================================================================
    
    virtual function void apply_plusargs();
        void'($value$plusargs("TEST_TIMEOUT=%d", test_timeout));
        void'($value$plusargs("PROGRAM=%s", program_file));
        void'($value$plusargs("HEX=%s", program_file));
        void'($value$plusargs("LOAD_ADDR=%h", load_addr));
        
        if ($test$plusargs("NO_SCOREBOARD")) enable_scoreboard = 0;
        if ($test$plusargs("NO_COVERAGE")) enable_coverage = 0;
        
        `uvm_info(get_type_name(), $sformatf("Plusargs applied: timeout=%0d, program=%s", 
                  test_timeout, program_file), UVM_MEDIUM)
    endfunction
    
    //==========================================================================
    // Connect Phase
    //==========================================================================
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info(get_type_name(), "Connect phase complete", UVM_LOW)
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        // Print beautiful test information banner
        `uvm_info(get_type_name(), {"\n",
            "╔══════════════════════════════════════════════════════════════════════════════╗\n",
            "║                        VORTEX UVM TEST CONFIGURATION                         ║\n",
            "╚══════════════════════════════════════════════════════════════════════════════╝\n",
            $sformatf("  Test Name:          %s\n", get_type_name()),
            $sformatf("  Program:            %s\n", program_file != "" ? program_file : "NONE (using TB memory)"),
            $sformatf("  Load Address:       0x%016h\n", load_addr),
            $sformatf("  Timeout:            %0d cycles\n", test_timeout),
            $sformatf("  Expect EBREAK:      %s\n", expect_ebreak ? "YES" : "NO"),
            "--------------------------------------------------------------------------------\n",
            `ifdef USE_VORTEX_CONFIG
                $sformatf("  Cores:              %0d\n", cfg.num_cores),
                $sformatf("  Warps:              %0d\n", cfg.num_warps),
                $sformatf("  Threads:            %0d\n", cfg.num_threads),
                "--------------------------------------------------------------------------------\n",
            `endif
            $sformatf("  Scoreboard:         %s\n", enable_scoreboard ? "ENABLED" : "DISABLED"),
            $sformatf("  Coverage:           %s\n", enable_coverage ? "ENABLED" : "DISABLED"),
            $sformatf("  Verbosity:          %s\n", get_verbosity_string(test_verbosity)),
            "--------------------------------------------------------------------------------\n",
            `ifdef USE_VORTEX_ENV
                $sformatf("  Environment:        ENABLED\n"),
            `else
                $sformatf("  Environment:        STANDALONE MODE\n"),
            `endif
            `ifdef USE_LOCAL_MEMORY
                $sformatf("  Memory Model:       LOCAL\n"),
            `else
                $sformatf("  Memory Model:       TB TOP\n"),
            `endif
            "╚══════════════════════════════════════════════════════════════════════════════╝"
        }, UVM_LOW)
        
        // Print topology if high verbosity
        if (test_verbosity >= UVM_HIGH) begin
            uvm_top.print_topology();
        end
    endfunction
    
    //==========================================================================
    // Start of Simulation Phase
    //==========================================================================
    
    virtual function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        
        // Load program if specified (and using local memory)
        `ifdef USE_LOCAL_MEMORY
            if (program_file != "") begin
                int bytes_loaded = load_program(program_file, load_addr);
                if (bytes_loaded < 0) begin
                    `uvm_fatal(get_type_name(), "Program loading failed!")
                end
            end
        `endif
    endfunction
    
    //==========================================================================
    // Run Phase
    //==========================================================================
    
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        
        phase.raise_objection(this, "Test running");
        
        start_time = $time;
        
        `uvm_info(get_type_name(), {"\n",
            "╔══════════════════════════════════════════════════════════════════════════════╗\n",
            "║                           TEST EXECUTION STARTED                             ║\n",
            "╚══════════════════════════════════════════════════════════════════════════════╝"
        }, UVM_LOW)
        
        // Wait for reset
        wait_for_reset();
        
        // Set timeout watchdog
        set_timeout(test_timeout);
        
        // Execute test body (implemented by derived classes)
        execute_test();
        
        // Wait for completion
        wait_for_completion();
        
        end_time = $time;
        
        `uvm_info(get_type_name(), {"\n",
            "╔══════════════════════════════════════════════════════════════════════════════╗\n",
            "║                           TEST EXECUTION COMPLETE                            ║\n",
            "╚══════════════════════════════════════════════════════════════════════════════╝"
        }, UVM_LOW)
        
        phase.drop_objection(this, "Test complete");
        
    endtask
    
    //==========================================================================
    // Extract Phase
    //==========================================================================
    
    virtual function void extract_phase(uvm_phase phase);
        super.extract_phase(phase);
        
        // Extract statistics
        total_cycles = status_vif.cycle_count;
        total_instructions = status_vif.instr_count;
        
        if (total_cycles > 0) begin
            ipc = real'(total_instructions) / real'(total_cycles);
        end else begin
            ipc = 0.0;
        end
        
        // Determine test result
        test_passed = (get_report_server().get_severity_count(UVM_FATAL) == 0) &&
                      (get_report_server().get_severity_count(UVM_ERROR) == 0);
        
        // Additional checks
        if (expect_ebreak && !status_vif.ebreak_detected) begin
            test_passed = 0;
            `uvm_error(get_type_name(), "EBREAK was expected but not detected!")
        end
        
        `uvm_info(get_type_name(), "Statistics extracted", UVM_MEDIUM)
    endfunction
    
    //==========================================================================
    // Check Phase
    //==========================================================================
    
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        
        // Perform test-specific checks
        check_results();
    endfunction
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    
    virtual function void report_phase(uvm_phase phase);
        uvm_report_server rs;
        int error_count;
        int warning_count;
        int fatal_count;
        real execution_time_ns;
        real execution_time_us;
        
        super.report_phase(phase);
        
        rs = get_report_server();
        error_count = rs.get_severity_count(UVM_ERROR);
        warning_count = rs.get_severity_count(UVM_WARNING);
        fatal_count = rs.get_severity_count(UVM_FATAL);
        execution_time_ns = (end_time - start_time) / 1.0;
        execution_time_us = execution_time_ns / 1000.0;
        
        `uvm_info(get_type_name(), {"\n",
            "╔══════════════════════════════════════════════════════════════════════════════╗\n",
            "║                              TEST SUMMARY                                    ║\n",
            "╚══════════════════════════════════════════════════════════════════════════════╝\n",
            $sformatf("  Test Name:          %s\n", get_type_name()),
            "--------------------------------------------------------------------------------\n",
            "  EXECUTION METRICS:\n",
            $sformatf("    Simulation Time:  %.2f ns (%.3f μs)\n", execution_time_ns, execution_time_us),
            $sformatf("    Total Cycles:     %0d\n", total_cycles),
            $sformatf("    Instructions:     %0d\n", total_instructions),
            $sformatf("    IPC:              %.3f\n", ipc),
            $sformatf("    EBREAK Detected:  %s\n", status_vif.ebreak_detected ? "YES ✓" : "NO ✗"),
            "--------------------------------------------------------------------------------\n",
            "  UVM REPORT:\n",
            $sformatf("    Fatals:           %0d\n", fatal_count),
            $sformatf("    Errors:           %0d\n", error_count),
            $sformatf("    Warnings:         %0d\n", warning_count),
            "--------------------------------------------------------------------------------\n",
            $sformatf("  FINAL RESULT:       %s\n", 
                      test_passed ? "✓✓✓ PASSED ✓✓✓" : "✗✗✗ FAILED ✗✗✗"),
            "╚══════════════════════════════════════════════════════════════════════════════╝"
        }, UVM_LOW)
        
        // Print memory statistics if available
        `ifdef USE_LOCAL_MEMORY
            if (mem != null) begin
                `uvm_info(get_type_name(), "\n", UVM_LOW)
                mem.print_statistics();
            end
        `endif
        
    endfunction
    
    //==========================================================================
    // Final Phase
    //==========================================================================
    
    virtual function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        
        if (test_passed) begin
            $display("\n");
            $display("╔══════════════════════════════════════════════════════════════════════════════╗");
            $display("║                                                                              ║");
            $display("║                           ✓✓✓ TEST PASSED ✓✓✓                               ║");
            $display("║                                                                              ║");
            $display("╚══════════════════════════════════════════════════════════════════════════════╝");
            $display("\n");
        end else begin
            $display("\n");
            $display("╔══════════════════════════════════════════════════════════════════════════════╗");
            $display("║                                                                              ║");
            $display("║                           ✗✗✗ TEST FAILED ✗✗✗                               ║");
            $display("║                                                                              ║");
            $display("╚══════════════════════════════════════════════════════════════════════════════╝");
            $display("\n");
        end
    endfunction
    
    //==========================================================================
    // Virtual Methods (Override in Derived Tests)
    //==========================================================================
    
    // Configure test-specific settings
    virtual function void configure_test();
        // Default configuration (override in derived tests)
        test_timeout = 10000;
        expect_ebreak = 1'b1;
        test_verbosity = UVM_MEDIUM;
    endfunction
    
    // Execute test body
    virtual task execute_test();
        `uvm_warning(get_type_name(), "execute_test() not implemented - override in derived test")
        #100ns;
    endtask
    
    // Check test results
    virtual function void check_results();
        // Default checking (override for custom checks)
        if (expect_ebreak && !status_vif.ebreak_detected) begin
            `uvm_error(get_type_name(), "Expected EBREAK not detected")
        end
        
        if (total_instructions == 0) begin
            `uvm_warning(get_type_name(), "No instructions executed!")
        end
        
        if (ipc < 0.1 && total_cycles > 100) begin
            `uvm_warning(get_type_name(), $sformatf("Low IPC detected: %.3f", ipc))
        end
    endfunction
    
    //==========================================================================
    // Helper Tasks & Functions
    //==========================================================================
    
    // Wait for reset completion
    virtual task wait_for_reset();
        `uvm_info(get_type_name(), "Waiting for reset completion...", UVM_MEDIUM)
        
        // Wait for reset assertion (if not already asserted)
        if (vif.reset_n == 1'b1) begin
            wait(vif.reset_n == 1'b0);
        end
        
        // Wait for reset deassertion
        wait(vif.reset_n == 1'b1);
        
        // Allow system to stabilize
        repeat(10) @(posedge vif.clk);
        
        `uvm_info(get_type_name(), "Reset complete - system ready", UVM_MEDIUM)
    endtask
    
    // Wait for kernel completion with timeout
    virtual task wait_for_completion();
        int cycles = 0;
        
        `uvm_info(get_type_name(), 
                  $sformatf("Waiting for completion (max %0d cycles)...", test_timeout), 
                  UVM_MEDIUM)
        
        while (!status_vif.ebreak_detected && (status_vif.busy || cycles < 100)) begin
            @(posedge vif.clk);
            cycles++;
            
            if (cycles >= test_timeout) begin
                `uvm_error(get_type_name(), 
                          $sformatf("Completion timeout after %0d cycles!", cycles))
                break;
            end
            
            // Progress reporting every 10k cycles
            if (cycles % 10000 == 0) begin
                `uvm_info(get_type_name(), 
                         $sformatf("Progress: %0d cycles elapsed...", cycles), 
                         UVM_MEDIUM)
            end
        end
        
        if (status_vif.ebreak_detected) begin
            `uvm_info(get_type_name(), 
                     $sformatf("✓ EBREAK detected after %0d cycles", cycles), 
                     UVM_LOW)
        end else if (!status_vif.busy) begin
            `uvm_info(get_type_name(), 
                     $sformatf("System idle after %0d cycles", cycles), 
                     UVM_LOW)
        end
        
        // Allow pipeline to flush
        repeat(20) @(posedge vif.clk);
        
    endtask
    
    // Set timeout watchdog (runs in background)
    virtual task set_timeout(int cycles);
        fork
            begin
                repeat(cycles) @(posedge vif.clk);
                `uvm_fatal(get_type_name(), 
                          $sformatf("⏰ Global test timeout after %0d cycles!", cycles))
            end
        join_none
        
        `uvm_info(get_type_name(), 
                 $sformatf("Timeout watchdog set: %0d cycles", cycles), 
                 UVM_MEDIUM)
    endtask
    
    // Load program into memory (if using local memory model)
    `ifdef USE_LOCAL_MEMORY
    virtual function int load_program(string program_path, bit [63:0] addr = 64'h80000000);
        int bytes_loaded;
        
        `uvm_info(get_type_name(), 
                 $sformatf("Loading program: %s @ 0x%016h", program_path, addr), 
                 UVM_LOW)
        
        bytes_loaded = mem.load_hex_file(program_path, addr);
        
        if (bytes_loaded < 0) begin
            `uvm_error(get_type_name(), 
                      $sformatf("Failed to load program: %s", program_path))
            return -1;
        end
        
        `uvm_info(get_type_name(), 
                 $sformatf("✓ Loaded %0d bytes successfully", bytes_loaded), 
                 UVM_LOW)
        
        return bytes_loaded;
    endfunction
    `endif
    
    // Get verbosity string
    function string get_verbosity_string(int verbosity);
        case (verbosity)
            UVM_NONE:   return "NONE";
            UVM_LOW:    return "LOW";
            UVM_MEDIUM: return "MEDIUM";
            UVM_HIGH:   return "HIGH";
            UVM_FULL:   return "FULL";
            UVM_DEBUG:  return "DEBUG";
            default:    return "UNKNOWN";
        endcase
    endfunction
    
endclass : vortex_base_test

`endif // VORTEX_BASE_TEST_SV
