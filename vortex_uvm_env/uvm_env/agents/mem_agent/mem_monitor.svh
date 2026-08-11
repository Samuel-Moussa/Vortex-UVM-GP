////////////////////////////////////////////////////////////////////////////////
// File: mem_monitor.sv
// Description: Memory Agent Monitor with Clocking Block Support
//
// This monitor passively observes memory transactions on the Vortex custom
// memory interface. It reconstructs complete transactions by matching
// requests and responses via tags.
//
// Operation:
//   1. Observe req_valid && req_ready → Capture request with tag
//   2. Store in outstanding_trans[tag]
//   3. Observe rsp_valid && rsp_ready → Find request by rsp_tag
//   4. Complete transaction and broadcast to scoreboard
//
// Key Features:
//   ✓ Uses monitor_cb clocking block (passive observation)
//   ✓ Tag-based request/response matching
//   ✓ Handles out-of-order responses
//   ✓ Protocol violation detection
//   ✓ Statistics collection
//
// **For Final State Comparison**:
//   The monitor broadcasts all completed transactions to the scoreboard.
//   For Option A (EBREAK final state), the scoreboard will:
//   - Accumulate write transactions into RTL memory model
//   - Wait for EBREAK signal
//   - Compare final RTL memory state against simx
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef MEM_MONITOR_SV
`define MEM_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import mem_agent_pkg::*;

class mem_monitor extends uvm_monitor;
    `uvm_component_utils(mem_monitor)
    
    //==========================================================================
    // Virtual Interface Handle
    // Uses monitor modport with clocking block for passive observation
    //==========================================================================
    virtual vortex_mem_if.monitor vif;
    
    //==========================================================================
    // Analysis Port
    // Broadcasts completed transactions to scoreboard
    //==========================================================================
    uvm_analysis_port #(mem_transaction) ap;
    
    //==========================================================================
    // Configuration Object
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Outstanding Transactions Tracking
    // Maps tag -> incomplete transaction
    // Allows out-of-order response handling
    //==========================================================================
    mem_transaction outstanding_trans[int];
    
    //==========================================================================
    // Cycle Counter for Accurate Latency Measurement
    //==========================================================================
    longint cycle_count;
    
    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int num_requests;           // Total requests observed
    int num_responses;          // Total responses observed
    int num_reads;              // Read transactions
    int num_writes;             // Write transactions
    int num_mismatched_tags;    // Tag errors detected
    longint total_latency;
    int     max_latency;
    int     min_latency;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mem_monitor", uvm_component parent = null);
        super.new(name, parent);
        
        // Create analysis port
        ap = new("ap", this);
        
        // Initialize statistics
        num_requests = 0;
        num_responses = 0;
        num_reads = 0;
        num_writes = 0;
        num_mismatched_tags = 0;
        cycle_count = 0;
        total_latency = 0;
        max_latency = 0;
        min_latency = -1;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface from config DB
        if (!uvm_config_db#(virtual vortex_mem_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MEM_MON", "Failed to get virtual interface from config DB")
        end
        
        // Get configuration object
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("MEM_MON", "No vortex_config found - using defaults")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
    endfunction
    
    //==========================================================================
    // Run Phase
    // Fork request collector, response collector, and cycle counter
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        fork
            // Background cycle counter for accurate latency
            forever begin
                @(vif.monitor_cb);
                if (vif.reset_n) cycle_count++;
            end
            
            // Collect requests and responses in parallel
            collect_requests();
            collect_responses();
        join
    endtask
    
    //==========================================================================
    // Collect Memory Requests
    //==========================================================================
    virtual task collect_requests();
        mem_transaction trans;
        
        forever begin
            @(vif.monitor_cb);
            
            // Guard against reset and X-states BEFORE doing anything
            if (!vif.reset_n) continue;
            if ($isunknown(vif.monitor_cb.req_valid[0])) continue;
            if ($isunknown(vif.monitor_cb.req_ready[0])) continue;
            
            // Detect request handshake
            if (vif.monitor_cb.req_valid[0] && vif.monitor_cb.req_ready[0]) begin
                
                // Create new transaction object ONLY when a valid handshake occurs
                trans = mem_transaction::type_id::create("trans");
                
                trans.rw     = vif.monitor_cb.req_rw[0];
                trans.addr   = vif.monitor_cb.req_addr[0];
                trans.data   = vif.monitor_cb.req_data[0];
                trans.byteen = vif.monitor_cb.req_byteen[0];
                trans.tag    = vif.monitor_cb.req_tag[0];
                
                // Record timing information (Use cycle_count for precise latency!)
                trans.req_time = $time;
                // NOTE: Add 'longint req_cycle;' to mem_transaction.sv if you haven't already!
                // trans.req_cycle = cycle_count; 
                
                // Update statistics
                num_requests++;
                if (trans.is_read()) num_reads++;
                else                 num_writes++;

                if (trans.is_read()) begin
                    // Reads need response matching for latency + data — park
                    // the request and wait for collect_responses() to complete it.
                    if (outstanding_trans.exists(trans.tag)) begin
                        `uvm_warning("MEM_MON", $sformatf(
                            "Overwriting outstanding transaction with tag=%0d", trans.tag))
                    end
                    outstanding_trans[trans.tag] = trans;
                end else begin
                    // Custom-mem writes are fire-and-forget — mem_driver commits
                    // to mem_model on the request handshake and generates no
                    // response. Forward to the scoreboard immediately, marked
                    // completed. Do NOT park in outstanding_trans (no response
                    // will ever match, and the tag namespace gets reused for
                    // subsequent writes, producing spurious overwrite warnings).
                    trans.completed = 1;
                    trans.rsp_time  = trans.req_time;
                    ap.write(trans);
                end

                `uvm_info("MEM_MON", $sformatf(
                    "Request captured: %s addr=0x%h, tag=%0d, cycle=%0d",
                    trans.is_read() ? "READ" : "WRITE", trans.addr, trans.tag, cycle_count), UVM_HIGH)
            end
        end
    endtask
    
    //==========================================================================
    // Collect Memory Responses
    //==========================================================================
    virtual task collect_responses();
        mem_transaction trans;
        int tag;
        
        forever begin
            @(vif.monitor_cb);
            
            if (!vif.reset_n) continue;
            if ($isunknown(vif.monitor_cb.rsp_valid[0])) continue;
            if ($isunknown(vif.monitor_cb.rsp_ready[0])) continue;
            
            if (vif.monitor_cb.rsp_valid[0] && vif.monitor_cb.rsp_ready[0]) begin
                tag = vif.monitor_cb.rsp_tag[0];
                
                if (outstanding_trans.exists(tag)) begin
                    trans = outstanding_trans[tag];
                    
                    trans.rsp_data = vif.monitor_cb.rsp_data[0];
                    trans.rsp_tag  = vif.monitor_cb.rsp_tag[0];
                    trans.rsp_time = $time;
                    
                    // CYCLE ACCURATE LATENCY (Requires trans.req_cycle to be captured above)
                    // trans.latency_cycles = int'(cycle_count - trans.req_cycle);
                    // Fallback using time if you don't want to modify mem_transaction.sv:
                    trans.latency_cycles = int'((trans.rsp_time - trans.req_time) / (1000.0 / cfg.CLK_FREQ_MHZ));
                    
                    trans.completed = 1;
                    
                    // Accumulate latency stats for Report Phase
                    total_latency += trans.latency_cycles;
                    if (min_latency == -1 || trans.latency_cycles < min_latency) min_latency = trans.latency_cycles;
                    if (trans.latency_cycles > max_latency) max_latency = trans.latency_cycles;

                    if (trans.rsp_tag != trans.tag) begin
                        `uvm_error("MEM_MON", $sformatf("Tag mismatch! Req=%0d, Rsp=%0d", trans.tag, trans.rsp_tag))
                        trans.error = 1;
                        num_mismatched_tags++;
                    end
                    
                    outstanding_trans.delete(tag);
                    num_responses++;
                    
                    ap.write(trans);
                    
                end else begin
                    `uvm_error("MEM_MON", $sformatf("Response for unknown tag: %0d (cycle=%0d)", tag, cycle_count))
                end
            end
        end
    endtask
    
    //==========================================================================
    // Check Phase
    // Verify all transactions completed at end of test
    //==========================================================================
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        
        // Check for incomplete transactions
        if (outstanding_trans.size() > 0) begin
            `uvm_warning("MEM_MON", $sformatf(
                "%0d transactions still outstanding at end of test",
                outstanding_trans.size()))
            
            // List all outstanding transactions
            foreach (outstanding_trans[tag]) begin
                `uvm_info("MEM_MON", $sformatf(
                    "Outstanding: tag=%0d, %s addr=0x%h, age=%0d cycles",
                    tag, 
                    outstanding_trans[tag].is_read() ? "READ" : "WRITE",
                    outstanding_trans[tag].addr,
                    cycle_count - (outstanding_trans[tag].req_time / 10)),
                    UVM_LOW)
            end
        end
        
        // Warn about tag mismatches
        if (num_mismatched_tags > 0) begin
            `uvm_error("MEM_MON", $sformatf(
                "Test completed with %0d tag mismatches",
                num_mismatched_tags))
        end
    endfunction
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        real avg_lat = 0.0;
        super.report_phase(phase);
        
        if (num_responses > 0) begin
            avg_lat = real'(total_latency) / real'(num_responses);
        end
        
        `uvm_info("MEM_MON", {"\n",
            "========================================\n",
            "    Memory Monitor Statistics\n",
            "========================================\n",
            $sformatf("  Total Requests:     %0d\n", num_requests),
            $sformatf("  Total Responses:    %0d\n", num_responses),
            $sformatf("  Read Transactions:  %0d\n", num_reads),
            $sformatf("  Write Transactions: %0d\n", num_writes),
            "----------------------------------------\n",
            $sformatf("  Avg Latency:        %.2f cycles\n", avg_lat),
            $sformatf("  Min Latency:        %0d cycles\n",  min_latency == -1 ? 0 : min_latency),
            $sformatf("  Max Latency:        %0d cycles\n",  max_latency),
            "----------------------------------------\n",
            $sformatf("  Tag Mismatches:     %0d\n", num_mismatched_tags),
            $sformatf("  Outstanding:        %0d\n", outstanding_trans.size()),
            $sformatf("  Total Cycles:       %0d\n", cycle_count),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : mem_monitor

`endif // MEM_MONITOR_SV
