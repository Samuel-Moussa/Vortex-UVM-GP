////////////////////////////////////////////////////////////////////////////////
// File: simx_pkg.sv
// Description: SystemVerilog Package for SimX DPI-C Integration
//
// Provides:
//   - DPI-C function imports
//   - UVM golden model component
//   - Utility functions for memory operations
//
// Author: Vortex UVM Team
// Date: December 2025
////////////////////////////////////////////////////////////////////////////////

`ifndef SIMX_PKG_SV
`define SIMX_PKG_SV

package simx_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import vortex_config_pkg::*;

    //==========================================================================
    // DPI-C Function Imports
    //==========================================================================
    
    // Initialization and cleanup
    import "DPI-C" context function int simx_init(
        input int num_cores,
        input int num_warps,
        input int num_threads
    );

    import "DPI-C" context function void simx_cleanup();

    // Program loading
    import "DPI-C" context function int simx_load_program(
        input string filename,
        input longint load_addr
    );

    // Memory operations
    import "DPI-C" context function void simx_write_mem(
        input longint addr,
        input int size,
        input byte data[]
    );

    import "DPI-C" context function void simx_read_mem(
        input longint addr,
        input int size,
        inout byte data[]
    );

    // DCR operations
    import "DPI-C" context function int simx_dcr_write(
        input int addr,
        input int data
    );

    import "DPI-C" context function int simx_dcr_read(
        input int addr
    );

    // Execution control
    import "DPI-C" context function int simx_run(
        input int max_cycles
    );

    import "DPI-C" context function int simx_step();

    import "DPI-C" context function int simx_is_busy();

    // Performance monitoring
    import "DPI-C" context function void simx_get_perf_counters(
        output longint cycles,
        output longint instructions
    );

    // Debug
    import "DPI-C" context function void simx_dump_state();

    //==========================================================================
    // UVM Golden Model Component
    //==========================================================================
    
    class simx_golden_model extends uvm_component;
        `uvm_component_utils(simx_golden_model)

        // Configuration
        vortex_config cfg;
        
        // Analysis port to send expected results
        uvm_analysis_port #(uvm_sequence_item) ap;

        // State tracking
        bit initialized;
        bit execution_complete;
        longint cycle_count;
        longint instr_count;

        //----------------------------------------------------------------------
        // Constructor
        //----------------------------------------------------------------------
        function new(string name = "simx_golden_model", uvm_component parent = null);
            super.new(name, parent);
            ap = new("ap", this);
            initialized = 1'b0;
            execution_complete = 1'b0;
        endfunction

        //----------------------------------------------------------------------
        // Build Phase
        //----------------------------------------------------------------------
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            
            if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
                `uvm_fatal("SIMX_MODEL", "Failed to get vortex_config")
            end
        endfunction

        //----------------------------------------------------------------------
        // Run Phase
        //----------------------------------------------------------------------
        task run_phase(uvm_phase phase);
            if (!cfg.simx_enable) begin
                `uvm_info("SIMX_MODEL", "SimX disabled in configuration", UVM_MEDIUM)
                return;
            end

            // Initialize SimX
            initialize_simx();

            // Load program if specified
            if (cfg.program_path != "") begin
                load_program();
            end

            // Run execution
            run_execution();

            // Extract results
            extract_results();

        endtask : run_phase

        //----------------------------------------------------------------------
        // Initialize SimX
        //----------------------------------------------------------------------
        task initialize_simx();
            int status;

            `uvm_info("SIMX_MODEL", $sformatf("Initializing SimX: %0dC %0dW %0dT",
                      cfg.num_cores, cfg.num_warps, cfg.num_threads), UVM_MEDIUM)

            status = simx_init(cfg.num_cores, cfg.num_warps, cfg.num_threads);

            if (status != 0) begin
                `uvm_fatal("SIMX_MODEL", "SimX initialization failed!")
            end

            initialized = 1'b1;
            `uvm_info("SIMX_MODEL", "SimX initialized successfully", UVM_MEDIUM)
        endtask : initialize_simx

        //----------------------------------------------------------------------
        // Load Program
        //----------------------------------------------------------------------
        task load_program();
            int status;

            `uvm_info("SIMX_MODEL", $sformatf("Loading program: %s", cfg.program_path), UVM_MEDIUM)

            status = simx_load_program(cfg.program_path, cfg.program_load_addr);

            if (status != 0) begin
                `uvm_error("SIMX_MODEL", "Failed to load program")
            end else begin
                `uvm_info("SIMX_MODEL", "Program loaded successfully", UVM_MEDIUM)
            end
        endtask : load_program

        //----------------------------------------------------------------------
        // Run Execution
        //----------------------------------------------------------------------
        task run_execution();
            int status;
            int timeout_cycles;

            timeout_cycles = cfg.simx_timeout_cycles;
            `uvm_info("SIMX_MODEL", "Starting SimX execution", UVM_MEDIUM)

            status = simx_run(timeout_cycles);

            if (status == 1) begin
                execution_complete = 1'b1;
                `uvm_info("SIMX_MODEL", "Execution completed", UVM_MEDIUM)
            end else if (status == 0) begin
                `uvm_warning("SIMX_MODEL", "Execution timeout - still running")
            end else begin
                `uvm_error("SIMX_MODEL", "Execution error")
            end

            // Get performance counters
            simx_get_perf_counters(cycle_count, instr_count);
            `uvm_info("SIMX_MODEL", $sformatf("Cycles: %0d, Instructions: %0d",
                      cycle_count, instr_count), UVM_MEDIUM)
        endtask : run_execution

        //----------------------------------------------------------------------
        // Extract Results
        //----------------------------------------------------------------------
        task extract_results();
            byte result_data[];

            if (!execution_complete) begin
                return;
            end

            `uvm_info("SIMX_MODEL", "Extracting results from SimX memory", UVM_MEDIUM)

            result_data = new[cfg.result_size_bytes];
            simx_read_mem(cfg.result_base_addr, cfg.result_size_bytes, result_data);

            // Send to scoreboard via analysis port
            // (Create appropriate transaction type based on your needs)
            `uvm_info("SIMX_MODEL", $sformatf("Read %0d bytes from result area",
                      cfg.result_size_bytes), UVM_HIGH)
        endtask : extract_results

        //----------------------------------------------------------------------
        // Report Phase
        //----------------------------------------------------------------------
        function void report_phase(uvm_phase phase);
            super.report_phase(phase);

            if (initialized) begin
                `uvm_info("SIMX_MODEL", {"\n",
                    "========================================\n",
                    " SimX Golden Model Report\n",
                    "========================================\n",
                    $sformatf(" Execution: %s\n", execution_complete ? "Complete" : "Incomplete"),
                    $sformatf(" Cycles: %0d\n", cycle_count),
                    $sformatf(" Instructions: %0d\n", instr_count),
                    $sformatf(" IPC: %0.2f\n", cycle_count > 0 ? real'(instr_count)/real'(cycle_count) : 0.0),
                    "========================================\n"
                }, UVM_MEDIUM)
            end
        endfunction : report_phase

        //----------------------------------------------------------------------
        // Final Phase
        //----------------------------------------------------------------------
        function void final_phase(uvm_phase phase);
            super.final_phase(phase);
            
            if (initialized) begin
                `uvm_info("SIMX_MODEL", "Cleaning up SimX resources", UVM_MEDIUM)
                simx_cleanup();
                initialized = 1'b0;
            end
        endfunction : final_phase

    endclass : simx_golden_model

endpackage : simx_pkg

`endif // SIMX_PKG_SV
