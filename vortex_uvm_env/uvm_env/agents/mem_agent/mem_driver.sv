////////////////////////////////////////////////////////////////////////////////
// File: mem_driver.sv
// Description: Memory Agent Driver with Clocking Block Support
//
// This driver actively drives memory transactions onto the Vortex custom
// memory interface. It uses clocking blocks for race-free operation.
//
// Protocol:
//   1. Drive req_valid HIGH with address, data, tag
//   2. Wait for req_ready HIGH (handshake)
//   3. Deassert req_valid
//   4. Wait for rsp_valid HIGH with matching tag
//   5. Capture response data
//
// Key Features:
//   ✓ Uses master_cb clocking block for clean timing
//   ✓ Tag-based request/response matching
//   ✓ Timeout protection (configurable)
//   ✓ Latency tracking
//   ✓ Statistics collection
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef MEM_DRIVER_SV
`define MEM_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import mem_agent_pkg::*;

class mem_driver extends uvm_driver #(mem_transaction);
    `uvm_component_utils(mem_driver)
    
    //==========================================================================
    // Virtual Interface Handle
    // Uses master_driver modport with clocking block
    //==========================================================================
    virtual vortex_mem_if.master_driver vif;
    
    //==========================================================================
    // Configuration Object
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int num_reads;              // Total read transactions
    int num_writes;             // Total write transactions
    longint total_read_latency; // Sum of all read latencies
    longint total_write_latency; // Sum of all write latencies
    
    //==========================================================================
    // Cycle Counter for Latency Calculation
    //==========================================================================
    longint cycle_count;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mem_driver", uvm_component parent = null);
        super.new(name, parent);
        num_reads = 0;
        num_writes = 0;
        total_read_latency = 0;
        total_write_latency = 0;
        cycle_count = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface from config DB
        if (!uvm_config_db#(virtual vortex_mem_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MEM_DRV", "Failed to get virtual interface from config DB")
        end
        
        // Get configuration object
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("MEM_DRV", "No vortex_config found - using defaults")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
    endfunction
    
    //==========================================================================
    // Run Phase
    // Main driver loop and background cycle counter
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        mem_transaction trans;
        
        // Initialize interface signals using clocking block
        @(vif.master_cb);
        vif.master_cb.req_valid[0] <= 1'b0;
        vif.master_cb.rsp_ready[0] <= 1'b1;  // Always ready to accept responses
        
        // Fork background cycle counter
        fork
            forever begin
                @(vif.master_cb);
                cycle_count++;
            end
        join_none
        
        // Main driver loop
        forever begin
            // Get next transaction from sequencer
            seq_item_port.get_next_item(trans);
            
            `uvm_info("MEM_DRV", $sformatf("Driving transaction:\n%s", 
                trans.convert2string()), UVM_HIGH)
            
            // Drive the transaction
            drive_transaction(trans);
            
            // Notify sequencer we're done
            seq_item_port.item_done();
        end
    endtask
    
    //==========================================================================
    // Drive Complete Transaction
    // Handles both request and response phases
    //==========================================================================
    virtual task drive_transaction(mem_transaction trans);
        longint start_cycle, end_cycle;
        
        // Capture starting time and cycle
        trans.req_time = $time;
        start_cycle = cycle_count;
        
        // Drive request phase
        drive_request(trans);
        
        // Wait for response phase
        wait_response(trans);
        
        // Capture ending time and calculate latency
        trans.rsp_time = $time;
        end_cycle = cycle_count;
        trans.latency_cycles = int'(end_cycle - start_cycle);
        trans.completed = 1;
        
        // Update statistics
        if (trans.is_read()) begin
            num_reads++;
            total_read_latency += trans.latency_cycles;
        end else begin
            num_writes++;
            total_write_latency += trans.latency_cycles;
        end
        
        `uvm_info("MEM_DRV", $sformatf("Transaction completed: latency=%0d cycles", 
            trans.latency_cycles), UVM_HIGH)
    endtask
    
    //==========================================================================
    // Drive Request Phase
    // Drives req_valid and waits for req_ready handshake
    //==========================================================================
    virtual task drive_request(mem_transaction trans);
        int timeout_count = 0;
        
        // Drive request signals using clocking block
        @(vif.master_cb);
        vif.master_cb.req_valid[0] <= 1'b1;
        vif.master_cb.req_rw[0]    <= trans.rw;
        vif.master_cb.req_addr[0]  <= trans.addr;
        vif.master_cb.req_data[0]  <= trans.data;
        vif.master_cb.req_byteen[0] <= trans.byteen;
        vif.master_cb.req_tag[0]   <= trans.tag;
        
        // Wait for handshake (req_ready HIGH)
        fork
            begin
                do begin
                    @(vif.master_cb);
                    timeout_count++;
                end while (!vif.master_cb.req_ready[0]);
            end
            
            begin
                // Timeout watchdog
                repeat(cfg.timeout_cycles) @(vif.master_cb);
                `uvm_fatal("MEM_DRV", $sformatf(
                    "Request timeout after %0d cycles (addr=0x%h)", 
                    timeout_count, trans.addr))
            end
        join_any
        disable fork;
        
        // Deassert req_valid after handshake
        vif.master_cb.req_valid[0] <= 1'b0;
        
        `uvm_info("MEM_DRV", $sformatf("%s request accepted after %0d cycles", 
            trans.is_read() ? "READ" : "WRITE", timeout_count), UVM_HIGH)
    endtask
    
    //==========================================================================
    // Wait for Response Phase
    // Waits for rsp_valid and captures response data
    //==========================================================================
    virtual task wait_response(mem_transaction trans);
        int timeout_count = 0;
        
        // Ensure rsp_ready is HIGH
        vif.master_cb.rsp_ready[0] <= 1'b1;
        
        // Wait for response (rsp_valid HIGH)
        fork
            begin
                do begin
                    @(vif.master_cb);
                    timeout_count++;
                end while (!vif.master_cb.rsp_valid[0]);
            end
            
            begin
                // Timeout watchdog
                repeat(cfg.timeout_cycles) @(vif.master_cb);
                `uvm_fatal("MEM_DRV", $sformatf(
                    "Response timeout after %0d cycles (tag=%0d)", 
                    timeout_count, trans.tag))
            end
        join_any
        disable fork;
        
        // Capture response data using clocking block
        trans.rsp_data = vif.master_cb.rsp_data[0];
        trans.rsp_tag  = vif.master_cb.rsp_tag[0];
        
        // Verify tag matches
        if (trans.rsp_tag != trans.tag) begin
            `uvm_error("MEM_DRV", $sformatf(
                "Tag mismatch! Expected: %0d, Got: %0d", 
                trans.tag, trans.rsp_tag))
            trans.error = 1;
        end
        
        `uvm_info("MEM_DRV", $sformatf("%s response received after %0d cycles", 
            trans.is_read() ? "READ" : "WRITE", timeout_count), UVM_HIGH)
    endtask
    
    //==========================================================================
    // Report Phase
    // Print statistics summary at end of simulation
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        real avg_read_latency, avg_write_latency;
        
        super.report_phase(phase);
        
        // Calculate average latencies
        if (num_reads > 0)
            avg_read_latency = real'(total_read_latency) / real'(num_reads);
        else
            avg_read_latency = 0.0;
        
        if (num_writes > 0)
            avg_write_latency = real'(total_write_latency) / real'(num_writes);
        else
            avg_write_latency = 0.0;
        
        // Print summary
        `uvm_info("MEM_DRV", {"\n",
            "========================================\n",
            "    Memory Driver Statistics\n",
            "========================================\n",
            $sformatf("  Total Reads:        %0d\n", num_reads),
            $sformatf("  Avg Read Latency:   %.2f cycles\n", avg_read_latency),
            $sformatf("  Total Writes:       %0d\n", num_writes),
            $sformatf("  Avg Write Latency:  %.2f cycles\n", avg_write_latency),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : mem_driver

`endif // MEM_DRIVER_SV
