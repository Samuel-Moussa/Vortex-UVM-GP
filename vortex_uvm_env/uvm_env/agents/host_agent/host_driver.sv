////////////////////////////////////////////////////////////////////////////////
// File: host_driver.sv
// Description: Host Agent Driver (Pure Orchestrator)
//
// This driver orchestrates high-level operations by coordinating with:
//   - vortex_dcr_if.master_cb     → Configure device, launch kernels
//   - vortex_status_if.monitor_cb → Monitor completion status
//   - mem_model                   → Load programs, read results (Direct access)
//
// Key Features:
//   ✓ Clean timing via clocking blocks for hardware pins
//   ✓ Direct C-style memory access (no multi-driver conflict on memory bus!)
//   ✓ Complex operation decomposition
//   ✓ Timeout protection
//   ✓ Statistics collection
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_DRIVER_SV
`define HOST_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import host_agent_pkg::*;
import mem_model_pkg::*;


class host_driver extends uvm_driver #(host_transaction);
    `uvm_component_utils(host_driver)
    
    //==========================================================================
    // Virtual Interfaces & Memory Model
    //==========================================================================
    virtual vortex_dcr_if.master_driver    dcr_vif;      // DCR configuration
    virtual vortex_status_if.monitor       status_vif;   // Status monitoring
    
    vortex_config cfg;
    mem_model     memory;  // Direct access to shared memory model
    
    //==========================================================================
    // Analysis Port (for transaction broadcasting)
    //==========================================================================
    uvm_analysis_port #(host_transaction) ap;
    
    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int num_programs_loaded;
    int num_dcr_writes;
    int num_kernels_launched;
    int num_completions;
    int num_timeouts;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "host_driver", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
        
        num_programs_loaded  = 0;
        num_dcr_writes       = 0;
        num_kernels_launched = 0;
        num_completions      = 0;
        num_timeouts         = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual vortex_dcr_if)::get(this, "", "dcr_vif", dcr_vif)) begin
            `uvm_fatal("HOST_DRV", "Failed to get dcr_vif from config DB")
        end
        
        if (!uvm_config_db#(virtual vortex_status_if)::get(this, "", "status_vif", status_vif)) begin
            `uvm_fatal("HOST_DRV", "Failed to get status_vif from config DB")
        end
        
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("HOST_DRV", "No vortex_config found - creating default")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end

        if (!uvm_config_db#(mem_model)::get(this, "", "mem_model", memory)) begin
            `uvm_fatal("HOST_DRV", "Failed to get mem_model from config DB! Host needs memory access.")
        end
    endfunction
    
    //==========================================================================
    // Reset Phase
    //==========================================================================
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        phase.raise_objection(this);
        
        // Initialize DCR interface signals
        @(dcr_vif.master_cb);
        dcr_vif.master_cb.wr_valid <= 1'b0;
        dcr_vif.master_cb.wr_addr  <= '0;
        dcr_vif.master_cb.wr_data  <= '0;
        
        `uvm_info("HOST_DRV", "Host driver reset complete", UVM_MEDIUM)
        phase.drop_objection(this);
    endtask
    
    //==========================================================================
    // Run Phase
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        host_transaction trans;
        
        forever begin
            seq_item_port.get_next_item(trans);
            
            `uvm_info("HOST_DRV", $sformatf("Executing transaction:\n%s",
                trans.convert2string()), UVM_MEDIUM)
            
            execute_transaction(trans);
            ap.write(trans);
            seq_item_port.item_done();
        end
    endtask
    
    //==========================================================================
    // Transaction Execution Dispatcher
    //==========================================================================
    virtual task execute_transaction(host_transaction trans);
        trans.start_time = $time;
        
        case (trans.op_type)
            host_transaction::HOST_RESET:         do_reset();
            host_transaction::HOST_LOAD_PROGRAM:  load_program(trans);
            host_transaction::HOST_CONFIGURE_DCR: configure_dcr(trans);
            host_transaction::HOST_LAUNCH_KERNEL: launch_kernel(trans);
            host_transaction::HOST_WAIT_DONE:     wait_completion(trans);
            host_transaction::HOST_READ_RESULT:   read_result(trans);
            default: `uvm_error("HOST_DRV", $sformatf("Unknown operation: %s", trans.op_type.name()))
        endcase
        
        trans.end_time = $time;
    endtask
    
    //==========================================================================
    // Operations
    //==========================================================================
    virtual task do_reset();
        `uvm_info("HOST_DRV", "Applying reset...", UVM_MEDIUM)
        wait(status_vif.reset_n == 1'b0);
        repeat(10) @(status_vif.monitor_cb);
        wait(status_vif.reset_n == 1'b1);
        repeat(5) @(status_vif.monitor_cb);
        `uvm_info("HOST_DRV", "Reset complete", UVM_MEDIUM)
    endtask
    
    virtual task load_program(host_transaction trans);
        `uvm_info("HOST_DRV", $sformatf("Loading program to byte 0x%016h, size=%0d bytes",
            trans.load_address, trans.program_size), UVM_MEDIUM)
        
        // Write program data byte by byte directly into the shared memory model
        for (int i = 0; i < trans.program_size; i++) begin
            memory.write_byte(trans.load_address + i, trans.program_data[i]);
        end
        
        num_programs_loaded++;
        `uvm_info("HOST_DRV", "Program loaded successfully into mem_model", UVM_MEDIUM)
    endtask
    
    virtual task configure_dcr(host_transaction trans);
        `uvm_info("HOST_DRV", $sformatf("Writing DCR[0x%08h] = 0x%08h", trans.dcr_address, trans.dcr_data), UVM_MEDIUM)

        // Stage address/data while wr_valid is low to satisfy DCR stability assertions.
        @(dcr_vif.master_cb);
        dcr_vif.master_cb.wr_addr  <= trans.dcr_address;
        dcr_vif.master_cb.wr_data  <= trans.dcr_data;
        dcr_vif.master_cb.wr_valid <= 1'b0;

        // Single-cycle write pulse.
        @(dcr_vif.master_cb);
        dcr_vif.master_cb.wr_valid <= 1'b1;
        
        @(dcr_vif.master_cb);
        dcr_vif.master_cb.wr_valid <= 1'b0;

        // Allow one idle cycle before the next configuration write.
        @(dcr_vif.master_cb);
        
        repeat(2) @(dcr_vif.master_cb);
        num_dcr_writes++;
    endtask
    
    virtual task launch_kernel(host_transaction trans);
        host_transaction dcr_trans;
        `uvm_info("HOST_DRV", "Launching kernel...", UVM_MEDIUM)
        
        dcr_trans = host_transaction::type_id::create("dcr_trans");
        dcr_trans.op_type = host_transaction::HOST_CONFIGURE_DCR;
        
        dcr_trans.dcr_address = VX_DCR_BASE_STARTUP_ADDR0;
        dcr_trans.dcr_data = trans.startup_address[31:0];
        configure_dcr(dcr_trans);
        
        dcr_trans.dcr_address = VX_DCR_BASE_STARTUP_ADDR1;
        dcr_trans.dcr_data = trans.startup_address[63:32];
        configure_dcr(dcr_trans);
        
        if (trans.argv_ptr != 0) begin
            dcr_trans.dcr_address = VX_DCR_BASE_STARTUP_ARG0;
            dcr_trans.dcr_data = trans.argv_ptr[31:0];
            configure_dcr(dcr_trans);
            
            dcr_trans.dcr_address = VX_DCR_BASE_STARTUP_ARG1;
            dcr_trans.dcr_data = trans.argv_ptr[63:32];
            configure_dcr(dcr_trans);
        end
        num_kernels_launched++;
        `uvm_info("HOST_DRV", $sformatf("Kernel launched at 0x%016h", trans.startup_address), UVM_MEDIUM)
    endtask
    
    virtual task wait_completion(host_transaction trans);
        int cycles_waited = 0;
        bit completed = 0;
        `uvm_info("HOST_DRV", $sformatf("Waiting for completion (timeout: %0d cycles)", trans.timeout_cycles), UVM_MEDIUM)
        
        fork
            begin
                while (!completed && cycles_waited < trans.timeout_cycles) begin
                    @(status_vif.monitor_cb);
                    cycles_waited++;
                    
                    if (!status_vif.monitor_cb.busy || status_vif.monitor_cb.ebreak_detected) begin
                        completed = 1;
                        trans.completion_flag = 1;
                        num_completions++;
                        `uvm_info("HOST_DRV", $sformatf("Kernel completed in %0d cycles", cycles_waited), UVM_LOW)
                        break;
                    end
                end
                
                if (!completed) begin
                    `uvm_error("HOST_DRV", $sformatf("Timeout waiting for completion after %0d cycles!", trans.timeout_cycles))
                    trans.completion_flag = 0;
                    num_timeouts++;
                end
            end
        join
    endtask
    
    virtual task read_result(host_transaction trans);
        `uvm_info("HOST_DRV", $sformatf("Reading result from 0x%016h (%0d bytes)", trans.result_address, trans.result_size), UVM_MEDIUM)
        
        trans.result_data = new[trans.result_size];
        for (int i = 0; i < trans.result_size; i++) begin
            trans.result_data[i] = memory.read_byte(trans.result_address + i);
        end
        
        `uvm_info("HOST_DRV", "Result read successfully directly from mem_model", UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("HOST_DRV", {"\n",
            "========================================\n",
            "    Host Driver Statistics\n",
            "========================================\n",
            $sformatf("  Programs Loaded:   %0d\n", num_programs_loaded),
            $sformatf("  DCR Writes:        %0d\n", num_dcr_writes),
            $sformatf("  Kernels Launched:  %0d\n", num_kernels_launched),
            $sformatf("  Completions:       %0d\n", num_completions),
            $sformatf("  Timeouts:          %0d\n", num_timeouts),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : host_driver

`endif // HOST_DRIVER_SV