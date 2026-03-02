////////////////////////////////////////////////////////////////////////////////
// File: host_driver.sv
// Description: Host Agent Driver with Clocking Block Support
//
// This driver orchestrates high-level operations by coordinating with multiple
// interfaces using proper clocking blocks:
//   - vortex_mem_if.master_cb     → Load programs, read results
//   - vortex_dcr_if.master_cb     → Configure device, launch kernels
//   - vortex_status_if.monitor_cb → Monitor completion status
//
// Key Features:
//   ✓ Clean timing via clocking blocks
//   ✓ Multi-interface coordination
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


class host_driver extends uvm_driver #(host_transaction);
    `uvm_component_utils(host_driver)
    
    //==========================================================================
    // Virtual Interfaces (with proper modports)
    //==========================================================================
    virtual vortex_mem_if.master_driver    mem_vif;      // Memory operations
    virtual vortex_dcr_if.master_driver    dcr_vif;      // DCR configuration
    virtual vortex_status_if.monitor       status_vif;   // Status monitoring
    
    //==========================================================================
    // Configuration Object
    //==========================================================================
    vortex_config cfg;
    
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
        
        // Initialize statistics
        num_programs_loaded = 0;
        num_dcr_writes = 0;
        num_kernels_launched = 0;
        num_completions = 0;
        num_timeouts = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get memory interface from config DB
        if (!uvm_config_db#(virtual vortex_mem_if)::get(this, "", "mem_vif", mem_vif)) begin
            `uvm_fatal("HOST_DRV", "Failed to get mem_vif from config DB")
        end
        
        // Get DCR interface from config DB
        if (!uvm_config_db#(virtual vortex_dcr_if)::get(this, "", "dcr_vif", dcr_vif)) begin
            `uvm_fatal("HOST_DRV", "Failed to get dcr_vif from config DB")
        end
        
        // Get status interface from config DB
        if (!uvm_config_db#(virtual vortex_status_if)::get(this, "", "status_vif", status_vif)) begin
            `uvm_fatal("HOST_DRV", "Failed to get status_vif from config DB")
        end
        
        // Get configuration object
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("HOST_DRV", "No vortex_config found - creating default")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();  // ← FIXED: Initialize from RTL
        end
    endfunction
    
    //==========================================================================
    // Reset Phase
    // Initialize interface signals to idle state
    //==========================================================================
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        
        phase.raise_objection(this);
        
        // Initialize memory interface signals
        @(mem_vif.master_cb);
        mem_vif.master_cb.req_valid[0] <= 1'b0;
        mem_vif.master_cb.req_rw[0] <= 1'b0;
        mem_vif.master_cb.req_addr[0] <= '0;
        mem_vif.master_cb.req_data[0] <= '0;
        mem_vif.master_cb.req_byteen[0] <= '0;
        mem_vif.master_cb.req_tag[0] <= '0;
        mem_vif.master_cb.rsp_ready[0] <= 1'b1;
        
        // Initialize DCR interface signals
        @(dcr_vif.master_cb);
        dcr_vif.master_cb.wr_valid <= 1'b0;
        dcr_vif.master_cb.wr_addr <= '0;
        dcr_vif.master_cb.wr_data <= '0;
        
        `uvm_info("HOST_DRV", "Host driver reset complete", UVM_MEDIUM)
        
        phase.drop_objection(this);
    endtask
    
    //==========================================================================
    // Run Phase
    // Main driver loop: get transactions and execute them
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        host_transaction trans;
        
        forever begin
            // Get next transaction from sequencer
            seq_item_port.get_next_item(trans);
            
            `uvm_info("HOST_DRV", $sformatf("Executing transaction:\n%s",
                trans.convert2string()), UVM_MEDIUM)
            
            // Execute the transaction
            execute_transaction(trans);
            
            // Broadcast completed transaction
            ap.write(trans);
            
            // Notify sequencer we're done
            seq_item_port.item_done();
        end
    endtask
    
    //==========================================================================
    // Transaction Execution Dispatcher
    //==========================================================================
    virtual task execute_transaction(host_transaction trans);
        trans.start_time = $time;
        
        case (trans.op_type)
            host_transaction::HOST_RESET:
                do_reset();
            
            host_transaction::HOST_LOAD_PROGRAM:
                load_program(trans);
            
            host_transaction::HOST_CONFIGURE_DCR:
                configure_dcr(trans);
            
            host_transaction::HOST_LAUNCH_KERNEL:
                launch_kernel(trans);
            
            host_transaction::HOST_WAIT_DONE:
                wait_completion(trans);
            
            host_transaction::HOST_READ_RESULT:
                read_result(trans);
            
            default:
                `uvm_error("HOST_DRV", $sformatf("Unknown operation: %s",
                    trans.op_type.name()))
        endcase
        
        trans.end_time = $time;
    endtask
    
    //==========================================================================
    // Operation: Reset Device
    //==========================================================================
    virtual task do_reset();
        `uvm_info("HOST_DRV", "Applying reset...", UVM_MEDIUM)
        
        // Wait for reset to be asserted
        wait(status_vif.reset_n == 1'b0);
        
        // Wait reset duration
        repeat(10) @(status_vif.monitor_cb);
        
        // Wait for reset to be deasserted
        wait(status_vif.reset_n == 1'b1);
        
        // Allow settling time
        repeat(5) @(status_vif.monitor_cb);
        
        `uvm_info("HOST_DRV", "Reset complete", UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Operation: Load Program (Using Memory Clocking Block)
    //==========================================================================
    virtual task load_program(host_transaction trans);
        bit [31:0] addr;
        bit [31:0] data_word;
        
        `uvm_info("HOST_DRV", $sformatf("Loading program to 0x%016h (%0d bytes)",
            trans.load_address, trans.program_size), UVM_MEDIUM)
        
        addr = trans.load_address[31:0];  // Use lower 32 bits for address
        
        // Write program data word by word
        for (int i = 0; i < trans.program_size; i += 4) begin
            // Pack 4 bytes into word (little-endian)
            data_word = 32'h0;
            for (int j = 0; j < 4 && (i+j) < trans.program_size; j++) begin
                data_word |= (trans.program_data[i+j] << (j*8));
            end
            
            // Write word using memory clocking block
            write_memory_word(addr, data_word, 4'hF);
            addr += 4;
        end
        
        num_programs_loaded++;
        
        `uvm_info("HOST_DRV", "Program loaded successfully", UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Operation: Configure DCR (Using DCR Clocking Block)
    //==========================================================================
    virtual task configure_dcr(host_transaction trans);
        `uvm_info("HOST_DRV", $sformatf("Writing DCR[0x%08h] = 0x%08h",
            trans.dcr_address, trans.dcr_data), UVM_MEDIUM)
        
        // Use DCR clocking block for single-cycle write
        @(dcr_vif.master_cb);
        dcr_vif.master_cb.wr_valid <= 1'b1;
        dcr_vif.master_cb.wr_addr  <= trans.dcr_address;
        dcr_vif.master_cb.wr_data  <= trans.dcr_data;
        
        @(dcr_vif.master_cb);
        dcr_vif.master_cb.wr_valid <= 1'b0;
        
        // Allow time for DCR to propagate
        repeat(2) @(dcr_vif.master_cb);
        
        num_dcr_writes++;
    endtask
    
    //==========================================================================
    // Operation: Launch Kernel
    // Configures startup address and optional arguments via DCR
    //==========================================================================
    virtual task launch_kernel(host_transaction trans);
        host_transaction dcr_trans;
        
        `uvm_info("HOST_DRV", "Launching kernel...", UVM_MEDIUM)
        
        // Configure startup address (lower 32 bits)
        dcr_trans = host_transaction::type_id::create("dcr_trans");
        dcr_trans.op_type = host_transaction::HOST_CONFIGURE_DCR;
        dcr_trans.dcr_address = VX_DCR_BASE_STARTUP_ADDR0;
        dcr_trans.dcr_data = trans.startup_address[31:0];
        configure_dcr(dcr_trans);
        
        // Configure startup address (upper 32 bits)
        dcr_trans.dcr_address = VX_DCR_BASE_STARTUP_ADDR1;
        dcr_trans.dcr_data = trans.startup_address[63:32];
        configure_dcr(dcr_trans);
        
        // Configure argument pointer if provided (optional)
        if (trans.argv_ptr != 0) begin
            dcr_trans.dcr_address = VX_DCR_BASE_STARTUP_ARG0;
            dcr_trans.dcr_data = trans.argv_ptr[31:0];
            configure_dcr(dcr_trans);
            
            dcr_trans.dcr_address = VX_DCR_BASE_STARTUP_ARG1;
            dcr_trans.dcr_data = trans.argv_ptr[63:32];
            configure_dcr(dcr_trans);
        end
        
        num_kernels_launched++;
        
        `uvm_info("HOST_DRV", $sformatf("Kernel launched at 0x%016h",
            trans.startup_address), UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Operation: Wait for Completion (Using Status Clocking Block)
    //==========================================================================
    virtual task wait_completion(host_transaction trans);
        int cycles_waited = 0;
        bit completed = 0;
        
        `uvm_info("HOST_DRV", $sformatf("Waiting for completion (timeout: %0d cycles)",
            trans.timeout_cycles), UVM_MEDIUM)
        
        // Wait for completion or timeout
        fork
            begin
                while (!completed && cycles_waited < trans.timeout_cycles) begin
                    @(status_vif.monitor_cb);
                    cycles_waited++;
                    
                    // Check for completion (busy goes low OR ebreak detected)
                    if (!status_vif.monitor_cb.busy || 
                        status_vif.monitor_cb.ebreak_detected) begin
                        completed = 1;
                        trans.completion_flag = 1;
                        num_completions++;
                        
                        `uvm_info("HOST_DRV", $sformatf("Kernel completed in %0d cycles",
                            cycles_waited), UVM_LOW)
                        break;
                    end
                end
                
                if (!completed) begin
                    `uvm_error("HOST_DRV", $sformatf(
                        "Timeout waiting for completion after %0d cycles!",
                        trans.timeout_cycles))
                    trans.completion_flag = 0;
                    num_timeouts++;
                end
            end
        join
    endtask
    
    //==========================================================================
    // Operation: Read Result (Using Memory Clocking Block)
    //==========================================================================
    virtual task read_result(host_transaction trans);
        bit [31:0] addr;
        bit [31:0] data_word;
        
        `uvm_info("HOST_DRV", $sformatf("Reading result from 0x%016h (%0d bytes)",
            trans.result_address, trans.result_size), UVM_MEDIUM)
        
        // Allocate result buffer
        trans.result_data = new[trans.result_size];
        
        addr = trans.result_address[31:0];  // Use lower 32 bits
        
        // Read result data word by word
        for (int i = 0; i < trans.result_size; i += 4) begin
            read_memory_word(addr, data_word);
            
            // Unpack word into bytes (little-endian)
            for (int j = 0; j < 4 && (i+j) < trans.result_size; j++) begin
                trans.result_data[i+j] = (data_word >> (j*8)) & 8'hFF;
            end
            
            addr += 4;
        end
        
        `uvm_info("HOST_DRV", "Result read successfully", UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Helper: Write Memory Word (Using Memory Clocking Block)
    //==========================================================================
    virtual task write_memory_word(
        input bit [31:0] addr,
        input bit [31:0] data,
        input bit [3:0]  byteen = 4'hF
    );
        // Drive request using memory master clocking block
        @(mem_vif.master_cb);
        mem_vif.master_cb.req_valid[0]  <= 1'b1;
        mem_vif.master_cb.req_rw[0]     <= 1'b1;  // Write
        mem_vif.master_cb.req_addr[0]   <= addr;
        mem_vif.master_cb.req_data[0]   <= data;
        mem_vif.master_cb.req_byteen[0] <= byteen;
        mem_vif.master_cb.req_tag[0]    <= 0;
        
        // Wait for handshake
        do begin
            @(mem_vif.master_cb);
        end while (!mem_vif.master_cb.req_ready[0]);
        
        mem_vif.master_cb.req_valid[0] <= 1'b0;
        
        // Wait for response
        mem_vif.master_cb.rsp_ready[0] <= 1'b1;
        do begin
            @(mem_vif.master_cb);
        end while (!mem_vif.master_cb.rsp_valid[0]);
    endtask
    
    //==========================================================================
    // Helper: Read Memory Word (Using Memory Clocking Block)
    //==========================================================================
    virtual task read_memory_word(
        input  bit [31:0] addr,
        output bit [31:0] data
    );
        // Drive request using memory master clocking block
        @(mem_vif.master_cb);
        mem_vif.master_cb.req_valid[0]  <= 1'b1;
        mem_vif.master_cb.req_rw[0]     <= 1'b0;  // Read
        mem_vif.master_cb.req_addr[0]   <= addr;
        mem_vif.master_cb.req_byteen[0] <= 4'hF;
        mem_vif.master_cb.req_tag[0]    <= 0;
        
        // Wait for handshake
        do begin
            @(mem_vif.master_cb);
        end while (!mem_vif.master_cb.req_ready[0]);
        
        mem_vif.master_cb.req_valid[0] <= 1'b0;
        
        // Wait for response
        mem_vif.master_cb.rsp_ready[0] <= 1'b1;
        do begin
            @(mem_vif.master_cb);
        end while (!mem_vif.master_cb.rsp_valid[0]);
        
        // Capture data using clocking block
        data = mem_vif.master_cb.rsp_data[0];
    endtask
    
    //==========================================================================
    // Report Phase
    // Print comprehensive statistics
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
