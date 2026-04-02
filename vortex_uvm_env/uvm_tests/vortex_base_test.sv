// ////////////////////////////////////////////////////////////////////////////////
// // File: tests/vortex_base_test.sv
// // Description: Base Test Class for Vortex GPGPU Verification
// //
// // Clean, simple base test that all Vortex tests extend from.
// // Provides essential functionality without over-complication.
// //
// // Author: Vortex UVM Team
// // Date: December 2025
// ////////////////////////////////////////////////////////////////////////////////

// `ifndef VORTEX_BASE_TEST_SV
// `define VORTEX_BASE_TEST_SV

// import uvm_pkg::*;
// `include "uvm_macros.svh"

// // Import required packages
// import vortex_config_pkg::*;
// import vortex_env_pkg::*;



// class vortex_base_test extends uvm_test;
//     `uvm_component_utils(vortex_base_test)
    
//     //==========================================================================
//     // Components
//     //==========================================================================
//     vortex_env    env;
//     vortex_config cfg;
    
//     //==========================================================================
//     // Virtual Interface
//     //==========================================================================
//     virtual vortex_if vif;
    
//     //==========================================================================
//     // Test Configuration
//     //==========================================================================
//     int unsigned timeout_cycles;
//     bit test_passed;
    
//     //==========================================================================
//     // Constructor
//     //==========================================================================
//     function new(string name = "vortex_base_test", uvm_component parent = null);
//         super.new(name, parent);
//         test_passed = 1'b0;
//     endfunction
    
//     //==========================================================================
//     // Build Phase
//     //==========================================================================
//     virtual function void build_phase(uvm_phase phase);
//         super.build_phase(phase);
        
//         `uvm_info(get_type_name(), "Building test...", UVM_LOW)
        
//         // Create and configure
//         cfg = vortex_config::type_id::create("cfg");
//         cfg.set_defaults_from_vx_config();
//         cfg.apply_plusargs();
        
//         `uvm_info(get_type_name(),
//   $sformatf("DEBUG cfg after plusargs: cores=%0d warps=%0d threads=%0d str=%s",
//             cfg.num_cores, cfg.num_warps, cfg.num_threads, cfg.get_config_string()),
//   UVM_LOW)

        
//         // Allow test customization
//         customize_config();
        
//         // Validate
//         if (!cfg.is_valid()) begin
//             `uvm_fatal(get_type_name(), "Invalid configuration!")
//         end
        
//         // Set in database
//         uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);
        
//         // Get virtual interface
//         if (!uvm_config_db#(virtual vortex_if)::get(this, "", "vif", vif)) begin
//             `uvm_fatal(get_type_name(), "Failed to get virtual interface")
//         end
        
//         // Create environment
//         env = vortex_env::type_id::create("env", this);
        
//         // Set verbosity
//         set_report_verbosity_level_hier(cfg.default_verbosity);
        
//         timeout_cycles = cfg.test_timeout_cycles;
        
//     endfunction
    
//     //==========================================================================
//     // Customize Config (Override in derived tests)
//     //==========================================================================
//     virtual function void customize_config();
//         // Default - override in derived tests
//     endfunction
    
//     //==========================================================================
//     // Connect Phase
//     //==========================================================================
//     virtual function void connect_phase(uvm_phase phase);
//         super.connect_phase(phase);
//     endfunction
    
//     //==========================================================================
//     // End of Elaboration Phase
//     //==========================================================================
//     virtual function void end_of_elaboration_phase(uvm_phase phase);
//         super.end_of_elaboration_phase(phase);
        
//         `uvm_info(get_type_name(), {"\n",
//             "================================================================================\n",
//             $sformatf("  Test:        %s\n", get_type_name()),
//             $sformatf("  Config:      %s\n", cfg.get_config_string()),
//             $sformatf("  Timeout:     %0d cycles\n", timeout_cycles),
//             "================================================================================"
//         }, UVM_LOW)
        
//         // Print topology if debug
//         if (cfg.default_verbosity >= UVM_HIGH) begin
//             uvm_top.print_topology();
//         end
//     endfunction
    
//     //==========================================================================
//     // Run Phase (Override in derived tests)
//     //==========================================================================
//     virtual task run_phase(uvm_phase phase);
//         super.run_phase(phase);
        
//         phase.raise_objection(this, "Test running");
        
//         `uvm_info(get_type_name(), "Starting test execution...", UVM_LOW)
        
//         // Wait for reset
//         wait_for_reset();
        
//         // Run test stimulus (override this)
//         run_test_stimulus();
        
//         // Wait for completion
//         wait_for_completion();
        
//         // Check results
//         check_results();
        
//         `uvm_info(get_type_name(), "Test execution complete", UVM_LOW)
        
//         phase.drop_objection(this, "Test complete");
//     endtask
    
//     //==========================================================================
//     // Wait for Reset
//     //==========================================================================
//     virtual task wait_for_reset();
//         `uvm_info(get_type_name(), "Waiting for reset...", UVM_MEDIUM)
//         @(posedge vif.reset_n);
//         repeat(5) @(posedge vif.clk);
//         `uvm_info(get_type_name(), "Reset complete", UVM_MEDIUM)
//     endtask
    
//     //==========================================================================
//     // Run Test Stimulus (Override in derived tests)
//     //==========================================================================
//     virtual task run_test_stimulus();
//         `uvm_info(get_type_name(), "No test stimulus (override in derived test)", UVM_MEDIUM)
//         repeat(100) @(posedge vif.clk);
//     endtask
    
//     //==========================================================================
//     // Wait for Completion
//     //==========================================================================
//     virtual task wait_for_completion();
//         fork
//             begin
//                 fork
//                     // Wait for EBREAK
//                     begin
//                         wait(vif.status_if.ebreak_detected == 1'b1);
//                         `uvm_info(get_type_name(), "EBREAK detected", UVM_LOW)
//                     end
//                     // Timeout watchdog
//                     begin
//                         repeat(timeout_cycles) @(posedge vif.clk);
//                         `uvm_error(get_type_name(), 
//                                   $sformatf("Timeout after %0d cycles!", timeout_cycles))
//                     end
//                 join_any
//                 disable fork;
//             end
//         join
//     endtask
    
//     //==========================================================================
//     // Check Results
//     //==========================================================================
//     virtual function void check_results();
//         if (vif.status_if.ebreak_detected) begin
//             test_passed = 1'b1;
//             `uvm_info(get_type_name(), "✓ Test completed successfully", UVM_LOW)
//         end else begin
//             test_passed = 1'b0;
//             `uvm_error(get_type_name(), "✗ Test did not complete properly")
//         end
//     endfunction
    
//     //==========================================================================
//     // Report Phase
//     //==========================================================================
//     virtual function void report_phase(uvm_phase phase);
//         uvm_report_server rs;
//         int err_count;
//         real ipc;
        
//         super.report_phase(phase);
        
//         rs = uvm_report_server::get_server();
//         err_count = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
        
//         // Calculate IPC
//         if (vif.status_if.cycle_count > 0) begin
//             ipc = real'(vif.status_if.instr_count) / real'(vif.status_if.cycle_count);
//         end else begin
//             ipc = 0.0;
//         end
        
//         `uvm_info(get_type_name(), {"\n",
//             "================================================================================\n",
//             "                              TEST SUMMARY\n",
//             "================================================================================\n",
//             $sformatf("  Test:         %s\n", get_type_name()),
//             $sformatf("  Status:       %s\n", (err_count == 0 && test_passed) ? "PASSED ✓" : "FAILED ✗"),
//             $sformatf("  Errors:       %0d\n", err_count),
//             $sformatf("  Warnings:     %0d\n", rs.get_severity_count(UVM_WARNING)),
//             "--------------------------------------------------------------------------------\n",
//             $sformatf("  Cycles:       %0d\n", vif.status_if.cycle_count),
//             $sformatf("  Instructions: %0d\n", vif.status_if.instr_count),
//             $sformatf("  IPC:          %.3f\n", ipc),
//             "================================================================================"
//         }, UVM_NONE)
        
//         if (err_count == 0 && test_passed) begin
//             `uvm_info(get_type_name(), "\n*** TEST PASSED ***\n", UVM_NONE)
//         end else begin
//             `uvm_error(get_type_name(), "\n*** TEST FAILED ***\n")
//         end
//     endfunction
    
// endclass : vortex_base_test

// `endif // VORTEX_BASE_TEST_SV

//////////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////
    // File: tests/vortex_base_test.sv
    // Description: Base Test Class for Vortex GPGPU Verification
    //
    // MOD-1 additions (promoted from vortex_smoke_test):
    //   + load_program()            — loads hex via mem_model from config_db
    //   + monitor_memory_activity() — AXI/MEM beat + data counter
    //   + completion_cycle          — cycle at which EBREAK fired
    //   run_phase: load_program() before wait_for_reset()
    //
    // NOTE: No `include directives — vortex_test_pkg.sv owns all includes.
    //       mem_model type is available because vortex_test_pkg.sv includes
    //       mem_model.sv before this file.  Do NOT add import mem_model_pkg::*;
    //       here — it causes a multiply-defined typedef (E-B).
    //
    // Author: Vortex UVM Team  /  MOD-1 March 2026
    ////////////////////////////////////////////////////////////////////////////////

    `ifndef VORTEX_BASE_TEST_SV
    `define VORTEX_BASE_TEST_SV

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import mem_model_pkg::*;
    import vortex_config_pkg::*;
    import vortex_env_pkg::*;
    import vortex_test_pkg::*;

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
        bit          test_passed;

        //==========================================================================
        // MOD-1: Shared counters — ONE copy in base, visible to ALL derived tests
        //
        //  mem_reads       — AR handshakes (AXI) or read reqs (MEM): one per burst
        //  mem_writes      — AW handshakes (AXI) or write reqs (MEM): one per burst
        //  mem_read_beats  — R-channel beats: actual 64-bit data beats returned
        //  mem_write_beats — W-channel beats: actual 64-bit data beats sent
        //  bytes_loaded    — bytes written into mem_model by load_program()
        //  completion_cycle— value of cycle_count when EBREAK fired
        //==========================================================================
        int mem_reads        = 0;
        int mem_writes       = 0;
        int mem_read_beats   = 0;
        int mem_write_beats  = 0;
        int bytes_loaded     = 0;
        int completion_cycle = 0;

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

            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
            cfg.apply_plusargs();

            `uvm_info(get_type_name(),
                $sformatf("DEBUG cfg: cores=%0d warps=%0d threads=%0d str=%s",
                    cfg.num_cores, cfg.num_warps, cfg.num_threads,
                    cfg.get_config_string()), UVM_LOW)

            customize_config();

            if (!cfg.is_valid())
                `uvm_fatal(get_type_name(), "Invalid configuration!")

            uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);

            if (!uvm_config_db#(virtual vortex_if)::get(this, "", "vif", vif))
                `uvm_fatal(get_type_name(), "Failed to get virtual interface")

            env = vortex_env::type_id::create("env", this);
            set_report_verbosity_level_hier(cfg.default_verbosity);
            timeout_cycles = cfg.test_timeout_cycles;  // set AFTER customize_config
        endfunction

        //==========================================================================
        // Customize Config (override in derived tests)
        //==========================================================================
        virtual function void customize_config();
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

            `uvm_info(get_type_name(), {"
    ",
                "================================================================================
    ",
                $sformatf("  Test:      %s
    ",    get_type_name()),
                $sformatf("  Config:    %s
    ",    cfg.get_config_string()),
                $sformatf("  Interface: %s
    ",    cfg.axi_agent_enable ? "AXI4" : "Custom MEM"),
                $sformatf("  Timeout:   %0d cycles
    ", timeout_cycles),
                "================================================================================"
            }, UVM_LOW)

            if (cfg.default_verbosity >= UVM_HIGH)
                uvm_top.print_topology();
        endfunction

        //==========================================================================
        // Run Phase
        //==========================================================================
        virtual task run_phase(uvm_phase phase);
            super.run_phase(phase);
            phase.raise_objection(this, "Test running");
            `uvm_info(get_type_name(), "Starting test execution...", UVM_LOW)

            load_program();                              // STEP 1: before reset
            wait_for_reset();                            // STEP 2: wait reset_n
            fork monitor_memory_activity(); join_none    // STEP 3: background
            run_test_stimulus();                         // STEP 4: test-specific
            wait_for_completion();                       // STEP 5: wait EBREAK
            check_results();                             // STEP 6: validate

            `uvm_info(get_type_name(), "Test execution complete", UVM_LOW)
            phase.drop_objection(this, "Test complete");
        endtask

        //==========================================================================
        // Wait for Reset (edge-triggered — override for level-safe in derived tests)
        //==========================================================================
        virtual task wait_for_reset();
            `uvm_info(get_type_name(), "Waiting for reset...", UVM_MEDIUM)
            @(posedge vif.reset_n);
            repeat(5) @(posedge vif.clk);
            `uvm_info(get_type_name(), "Reset complete", UVM_MEDIUM)
        endtask

        //==========================================================================
        // Run Test Stimulus (override in derived tests)
        //==========================================================================
        virtual task run_test_stimulus();
            `uvm_info(get_type_name(), "No stimulus -- override in derived test", UVM_MEDIUM)
            repeat(100) @(posedge vif.clk);
        endtask

        //==========================================================================
        // Wait for Completion (captures completion_cycle)
        //==========================================================================
        virtual task wait_for_completion();
            fork begin
                fork
                    begin
                        wait(vif.status_if.ebreak_detected == 1'b1);
                        completion_cycle = int'(vif.status_if.cycle_count);
                        `uvm_info(get_type_name(),
                            $sformatf("EBREAK detected at cycle %0d", completion_cycle), UVM_LOW)
                    end
                    begin
                        repeat(timeout_cycles) @(posedge vif.clk);
                        `uvm_error(get_type_name(),
                            $sformatf("Timeout after %0d cycles!", timeout_cycles))
                    end
                join_any
                disable fork;
            end join
        endtask

        //==========================================================================
        // load_program() — MOD-1: promoted from vortex_smoke_test
        //==========================================================================
        // virtual task load_program();
        //     mem_model mem;
        //     string    hex_file;
        //     int       fd;
        //     bit       found;

        //     #2ns;
        //     `uvm_info(get_type_name(), "LOADING PROGRAM", UVM_LOW)

        //     found = 0;
        //     if      (uvm_config_db#(mem_model)::get(null,            "*",             "mem_model", mem)) found = 1;
        //     else if (uvm_config_db#(mem_model)::get(this,            "",              "mem_model", mem)) found = 1;
        //     else if (uvm_config_db#(mem_model)::get(uvm_root::get(), "*",             "mem_model", mem)) found = 1;
        //     else if (uvm_config_db#(mem_model)::get(null,            "uvm_test_top*", "mem_model", mem)) found = 1;

        //     if (!found)
        //         `uvm_fatal(get_type_name(),
        //             "mem_model not in config_db -- TB_TOP must set it before run_phase")

        //     if (!$value$plusargs("PROGRAM=%s", hex_file))
        //         `uvm_fatal(get_type_name(), "No +PROGRAM= -- run with +PROGRAM=path/to/file.hex")

        //     fd = $fopen(hex_file, "r");
        //     if (fd == 0)
        //         `uvm_fatal(get_type_name(), $sformatf("File not found: %s", hex_file))
        //     $fclose(fd);

        //     begin
        //         bit [63:0] load_addr = cfg.startup_addr;
        //         bytes_loaded = mem.load_hex_file(hex_file, load_addr);
        //         `uvm_info(get_type_name(),
        //             $sformatf("Loading %s at 0x%016h", hex_file, load_addr), UVM_LOW)
        //     end

        //     if (bytes_loaded == 0)
        //         `uvm_fatal(get_type_name(), $sformatf("0 bytes loaded: %s", hex_file))

        //     `uvm_info(get_type_name(),
        //         $sformatf("Loaded %0d bytes", bytes_loaded), UVM_LOW)
        // endtask
        //==========================================================================
        // load_program() — MOD-1: promoted from vortex_smoke_test
        //==========================================================================
        virtual task load_program();
            mem_model mem;
            string    hex_file;
            int       fd;
            int       tries;

            `uvm_info(get_type_name(), "LOADING PROGRAM", UVM_LOW)

            // Poll until TBTOP's initial block has registered mem_model
            // (replaces blind #2ns which races against TB_TOP's initial block)
            tries = 0;
            mem   = null;
            while (mem == null && tries < 200) begin
                void'(uvm_config_db#(mem_model)::get(null, "*", "mem_model", mem));
                if (mem == null) begin
                    #10ns;
                    tries++;
                end
            end

            if (mem == null)
                `uvm_fatal(get_type_name(),
                    "mem_model not in config_db after 2us -- TB_TOP must call set() before run_test()")

            `uvm_info(get_type_name(),
                $sformatf("mem_model found after %0d poll(s)", tries), UVM_LOW)

            if (!$value$plusargs("PROGRAM=%s", hex_file))
                `uvm_fatal(get_type_name(), "No +PROGRAM= -- run with +PROGRAM=path/to/file.hex")

            fd = $fopen(hex_file, "r");
            if (fd == 0)
                `uvm_fatal(get_type_name(), $sformatf("File not found: %s", hex_file))
            $fclose(fd);

            begin
                bit [63:0] load_addr = cfg.startup_addr;
                bytes_loaded = mem.load_hex_file(hex_file, load_addr);
                `uvm_info(get_type_name(),
                    $sformatf("Loading %s at 0x%016h", hex_file, load_addr), UVM_LOW)
            end

            if (bytes_loaded == 0)
                `uvm_fatal(get_type_name(), $sformatf("0 bytes loaded: %s", hex_file))

            `uvm_info(get_type_name(),
                $sformatf("Loaded %0d bytes", bytes_loaded), UVM_LOW)
        endtask
        //==========================================================================
        // monitor_memory_activity() — MOD-1: promoted from vortex_smoke_test
        //==========================================================================
        virtual task monitor_memory_activity();
            forever begin
                @(posedge vif.clk);
                if (cfg.axi_agent_enable) begin
                    if (vif.axi_if.arvalid && vif.axi_if.arready) begin
                        mem_reads++;
                        if (mem_reads + mem_writes == 1)
                            `uvm_info(get_type_name(), "First AXI AR transaction", UVM_LOW)
                    end
                    if (vif.axi_if.rvalid  && vif.axi_if.rready)  mem_read_beats++;
                    if (vif.axi_if.awvalid && vif.axi_if.awready) begin
                        mem_writes++;
                        if (mem_reads + mem_writes == 1)
                            `uvm_info(get_type_name(), "First AXI AW transaction", UVM_LOW)
                    end
                    if (vif.axi_if.wvalid  && vif.axi_if.wready)  mem_write_beats++;
                end else begin
                    if (vif.mem_if.req_valid[0] && vif.mem_if.req_ready[0]) begin
                        if (vif.mem_if.req_rw[0]) begin
                            mem_writes++; mem_write_beats++;
                        end else begin
                            mem_reads++;  mem_read_beats++;
                        end
                        if (mem_reads + mem_writes == 1)
                            `uvm_info(get_type_name(), "First MEM transaction", UVM_LOW)
                    end
                end
            end
        endtask

        //==========================================================================
        // Check Results
        //==========================================================================
        virtual function void check_results();
            if (vif.status_if.ebreak_detected) begin
                test_passed = 1'b1;
                `uvm_info(get_type_name(), "Test completed successfully", UVM_LOW)
            end else begin
                test_passed = 1'b0;
                `uvm_error(get_type_name(), "Test did not complete properly")
            end
        endfunction

        //==========================================================================
        // Report Phase
        //==========================================================================
        virtual function void report_phase(uvm_phase phase);
            uvm_report_server rs;
            int  err_count;
            real ipc, cpi;
            int  read_bytes, write_bytes;

            super.report_phase(phase);
            rs          = uvm_report_server::get_server();
            err_count   = rs.get_severity_count(UVM_ERROR) +
                        rs.get_severity_count(UVM_FATAL);
            ipc         = (vif.status_if.cycle_count > 0) ?
                        real'(vif.status_if.instr_count) /
                        real'(vif.status_if.cycle_count) : 0.0;
            cpi         = (ipc > 0.0) ? 1.0 / ipc : 0.0;
            read_bytes  = mem_read_beats  * 8;
            write_bytes = mem_write_beats * 8;

            `uvm_info(get_type_name(), {"
    ",
                "================================================================================
    ",
                "                              TEST SUMMARY
    ",
                "================================================================================
    ",
                $sformatf("  Test           : %s
    ",   get_type_name()),
                $sformatf("  Status         : %s
    ",   (err_count==0 && test_passed) ? "PASSED" : "FAILED"),
                $sformatf("  Interface      : %s
    ",   cfg.axi_agent_enable ? "AXI4" : "Custom MEM"),
                $sformatf("  Hardware       : %0d core(s) x %0d warp(s) x %0d thread(s)
    ",
                                            cfg.num_cores, cfg.num_warps, cfg.num_threads),
                $sformatf("  Startup addr   : 0x%016h
    ", cfg.startup_addr),
                "--------------------------------------------------------------------------------
    ",
                $sformatf("  Errors         : %0d
    ",  err_count),
                $sformatf("  Warnings       : %0d
    ",  rs.get_severity_count(UVM_WARNING)),
                "--------------------------------------------------------------------------------
    ",
                $sformatf("  Program bytes  : %0d
    ",  bytes_loaded),
                $sformatf("  Cycles (total) : %0d
    ",  vif.status_if.cycle_count),
                $sformatf("  EBREAK cycle   : %0d
    ",  completion_cycle),
                $sformatf("  Instructions   : %0d
    ",  vif.status_if.instr_count),
                $sformatf("  IPC            : %.4f
    ", ipc),
                $sformatf("  CPI            : %.4f
    ", cpi),
                "--------------------------------------------------------------------------------
    ",
                $sformatf("  Mem bursts  RD : %0d
    ",  mem_reads),
                $sformatf("  Mem bursts  WR : %0d
    ",  mem_writes),
                $sformatf("  Data beats  RD : %0d  (%0d bytes)
    ", mem_read_beats,  read_bytes),
                $sformatf("  Data beats  WR : %0d  (%0d bytes)
    ", mem_write_beats, write_bytes),
                "================================================================================"
            }, UVM_NONE)

            if (err_count == 0 && test_passed)
                `uvm_info(get_type_name(),  "
    *** TEST PASSED ***
    ", UVM_NONE)
            else
                `uvm_error(get_type_name(), "
    *** TEST FAILED ***
    ")
        endfunction

    endclass : vortex_base_test

    `endif // VORTEX_BASE_TEST_SV