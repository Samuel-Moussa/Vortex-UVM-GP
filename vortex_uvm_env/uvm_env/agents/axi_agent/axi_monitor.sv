////////////////////////////////////////////////////////////////////////////////
// File: axi_monitor.sv
// Description: AXI4 Protocol Monitor with Burst Reconstruction
//
// This monitor passively observes all 5 AXI4 channels and reconstructs
// complete transactions. It handles:
//   - Independent observation of AW, W, B, AR, R channels
//   - FIFO-based W channel matching (AXI4 has no WID signal)
//   - Out-of-order transaction support via ID tracking
//   - Protocol violation detection (WLAST/RLAST, ordering)
//   - Burst reconstruction from individual beats
//   - Timeout detection for hung transactions
//
// Operation Flow:
//   Write Path: AW → FIFO → W beats matched in order → B response
//   Read Path:  AR → Pending reads by ID → R beats by RID → Complete
//
// Key Features:
//   ✓ Completely passive (no DUT influence)
//   ✓ Clocking blocks for race-free sampling
//   ✓ Reset and X-state safety guards
//   ✓ Comprehensive protocol checking
//   ✓ Cycle-accurate timing
//   ✓ Separate analysis ports for writes and reads
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import axi_agent_pkg::*;

class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    
    //==========================================================================
    // Virtual Interface Handle
    // Uses monitor modport with clocking block for passive observation
    //==========================================================================
    virtual vortex_axi_if.monitor vif;
    
    //==========================================================================
    // Analysis Ports
    // Separate ports allow independent scoreboard connections
    //==========================================================================
    uvm_analysis_port #(axi_transaction) ap_write;  // Completed write transactions
    uvm_analysis_port #(axi_transaction) ap_read;   // Completed read transactions
    
    //==========================================================================
    // Configuration Object
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Write Channel Matching Structures
    // AXI4 removed WID, so we must match W beats to AW in FIFO order
    //==========================================================================
    axi_transaction aw_fifo[$];           // Queue of AW transactions (in order)
    axi_transaction pending_b_resp[int];  // ID -> write waiting for B response
    
    //==========================================================================
    // Read Channel Tracking
    // R channel has RID, so we can match directly by ID
    //==========================================================================
    axi_transaction pending_r_resp[int];  // ID -> read waiting for R data
    
    //==========================================================================
    // Beat Counters for Burst Reconstruction
    //==========================================================================
    int write_beat_count[int];  // ID -> current W beat captured
    int read_beat_count[int];   // ID -> current R beat captured
    
    //==========================================================================
    // Cycle Counter for Timing
    //==========================================================================
    longint cycle_count;
    
    //==========================================================================
    // Statistics
    //==========================================================================
    int num_write_addr;          // AW handshakes observed
    int num_write_data;          // W beat handshakes observed
    int num_write_resp;          // B handshakes observed
    int num_read_addr;           // AR handshakes observed
    int num_read_data;           // R beat handshakes observed
    int num_protocol_violations; // Protocol errors detected
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_monitor", uvm_component parent = null);
        super.new(name, parent);
        
        // Create analysis ports
        ap_write = new("ap_write", this);
        ap_read = new("ap_read", this);
        
        // Initialize statistics
        num_write_addr = 0;
        num_write_data = 0;
        num_write_resp = 0;
        num_read_addr = 0;
        num_read_data = 0;
        num_protocol_violations = 0;
        cycle_count = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface
        if (!uvm_config_db#(virtual vortex_axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_MON", "Failed to get virtual interface from config DB")
        end
        
        // Get configuration
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("AXI_MON", "No vortex_config found - using defaults")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
    endfunction
    
    //==========================================================================
    // Run Phase
    // Fork all channel collectors and timeout watchdog
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        // Start cycle counter
        fork
            forever begin
                @(vif.monitor_cb);
                if (vif.reset_n) cycle_count++;
            end
        join_none
        
        // Fork all channel observers
        fork
            collect_write_addresses();  // AW channel
            collect_write_data();        // W channel
            collect_write_responses();   // B channel
            collect_read_addresses();    // AR channel
            collect_read_data();         // R channel
            detect_timeouts();           // Watchdog
        join
    endtask
    
    //==========================================================================
    // Write Address Channel Collector (AW)
    // Captures AW transactions and adds them to FIFO for W matching
    //==========================================================================
    virtual task collect_write_addresses();
        axi_transaction trans;
        
        forever begin
            @(vif.monitor_cb);
            
            // Guard against reset and X-states
            if (!vif.reset_n) continue;
            if ($isunknown(vif.monitor_cb.awvalid)) continue;
            if ($isunknown(vif.monitor_cb.awready)) continue;
            
            // Detect AW handshake
            if (vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
                // Create new transaction object
                trans = axi_transaction::type_id::create("wr_trans");
                trans.cfg = cfg;
                
                // Capture all AW channel fields
                trans.trans_type = axi_transaction::AXI_WRITE;
                trans.id = vif.monitor_cb.awid;
                trans.addr = vif.monitor_cb.awaddr;
                trans.len = vif.monitor_cb.awlen;
                trans.size = vif.monitor_cb.awsize;
                trans.burst = axi_transaction::axi_burst_type_e'(vif.monitor_cb.awburst);
                trans.addr_cycle = cycle_count;
                
                // Allocate arrays for data capture
                trans.wdata = new[trans.len + 1];
                trans.wstrb = new[trans.len + 1];
                trans.data_cycle = new[trans.len + 1];
                
                // Add to FIFO for W channel matching
                // This maintains AW ordering for W beat association
                aw_fifo.push_back(trans);
                
                // Initialize beat counter
                write_beat_count[trans.id] = 0;
                
                num_write_addr++;
                
                `uvm_info("AXI_MON", $sformatf(
                    "AW captured: ID=%0d, addr=0x%h, len=%0d beats, cycle=%0d",
                    trans.id, trans.addr, trans.len+1, cycle_count), UVM_HIGH)
            end
        end
    endtask
    
    //==========================================================================
    // Write Data Channel Collector (W)
    // Matches W beats to AW transactions in FIFO order
    // This is the critical fix for W channel matching without WID
    //==========================================================================
    virtual task collect_write_data();
        axi_transaction trans;
        int beat;
        
        forever begin
            @(vif.monitor_cb);
            
            // Guard against reset and X-states
            if (!vif.reset_n) continue;
            if ($isunknown(vif.monitor_cb.wvalid)) continue;
            if ($isunknown(vif.monitor_cb.wready)) continue;
            
            // Detect W handshake
            if (vif.monitor_cb.wvalid && vif.monitor_cb.wready) begin
                
                // PROTOCOL CHECK: W before AW is illegal
                if (aw_fifo.size() == 0) begin
                    `uvm_error("AXI_PROTOCOL", $sformatf(
                        "W data beat without matching AW address (cycle %0d)", 
                        cycle_count))
                    num_protocol_violations++;
                    continue;
                end
                
                // Match to FIRST transaction in FIFO
                // This implements AXI4 requirement: W beats must follow AW order
                trans = aw_fifo[0];
                beat = write_beat_count[trans.id];
                
                // PROTOCOL CHECK: Too many W beats
                if (beat > trans.len) begin
                    `uvm_error("AXI_PROTOCOL", $sformatf(
                        "Extra W beat for ID=%0d (expected %0d beats, got beat %0d)",
                        trans.id, trans.len+1, beat+1))
                    num_protocol_violations++;
                    continue;
                end
                
                // Capture W beat data
                trans.wdata[beat] = vif.monitor_cb.wdata;
                trans.wstrb[beat] = vif.monitor_cb.wstrb;
                trans.data_cycle[beat] = cycle_count;
                
                // Increment beat counter
                write_beat_count[trans.id]++;
                num_write_data++;
                
                `uvm_info("AXI_MON", $sformatf(
                    "W beat %0d/%0d: ID=%0d, data=0x%h, last=%0b",
                    beat+1, trans.len+1, trans.id, trans.wdata[beat], 
                    vif.monitor_cb.wlast), UVM_DEBUG)
                
                // PROTOCOL CHECK: WLAST validation
                if (vif.monitor_cb.wlast) begin
                    // Check WLAST asserted at correct beat
                    if (beat != trans.len) begin
                        `uvm_error("AXI_PROTOCOL", $sformatf(
                            "WLAST asserted at beat %0d, expected at beat %0d (ID=%0d)",
                            beat, trans.len, trans.id))
                        num_protocol_violations++;
                    end
                    
                    // Remove from AW FIFO and move to B pending queue
                    aw_fifo.pop_front();
                    pending_b_resp[trans.id] = trans;
                    
                end else begin
                    // Check WLAST was not missed
                    if (beat == trans.len) begin
                        `uvm_error("AXI_PROTOCOL", $sformatf(
                            "WLAST not asserted at final beat %0d (ID=%0d)",
                            beat, trans.id))
                        num_protocol_violations++;
                    end
                end
            end
        end
    endtask
    
    //==========================================================================
    // Write Response Channel Collector (B)
    // Matches B responses to transactions by BID
    //==========================================================================
    virtual task collect_write_responses();
        int id;
        axi_transaction trans;
        
        forever begin
            @(vif.monitor_cb);
            
            // Guard against reset and X-states
            if (!vif.reset_n) continue;
            if ($isunknown(vif.monitor_cb.bvalid)) continue;
            if ($isunknown(vif.monitor_cb.bready)) continue;
            
            // Detect B handshake
            if (vif.monitor_cb.bvalid && vif.monitor_cb.bready) begin
                id = vif.monitor_cb.bid;
                
                // Find matching transaction
                if (pending_b_resp.exists(id)) begin
                    trans = pending_b_resp[id];
                    
                    // Capture response
                    trans.bresp = axi_transaction::axi_resp_e'(vif.monitor_cb.bresp);
                    trans.resp_cycle = cycle_count;
                    trans.latency_cycles = int'(trans.resp_cycle - trans.addr_cycle);
                    trans.completed = 1;
                    
                    // Check for error responses
                    if (trans.bresp != axi_transaction::AXI_OKAY) begin
                        trans.error = 1;
                        `uvm_warning("AXI_MON", $sformatf(
                            "Write error response: ID=%0d, resp=%s",
                            id, trans.bresp.name()))
                    end
                    
                    num_write_resp++;
                    
                    // Clean up tracking structures
                    pending_b_resp.delete(id);
                    write_beat_count.delete(id);
                    
                    `uvm_info("AXI_MON", $sformatf(
                        "Write complete: ID=%0d, resp=%s, latency=%0d cycles",
                        id, trans.bresp.name(), trans.latency_cycles), UVM_HIGH)
                    
                    // Send to scoreboard via analysis port
                    ap_write.write(trans);
                    
                end else begin
                    // PROTOCOL VIOLATION: Response for unknown ID
                    `uvm_error("AXI_PROTOCOL", $sformatf(
                        "B response for unknown/completed ID=%0d (cycle %0d)",
                        id, cycle_count))
                    num_protocol_violations++;
                end
            end
        end
    endtask
    
    //==========================================================================
    // Read Address Channel Collector (AR)
    // Captures AR transactions and stores by ID for R matching
    //==========================================================================
    virtual task collect_read_addresses();
        axi_transaction trans;
        
        forever begin
            @(vif.monitor_cb);
            
            // Guard against reset and X-states
            if (!vif.reset_n) continue;
            if ($isunknown(vif.monitor_cb.arvalid)) continue;
            if ($isunknown(vif.monitor_cb.arready)) continue;
            
            // Detect AR handshake
            if (vif.monitor_cb.arvalid && vif.monitor_cb.arready) begin
                // Create new transaction
                trans = axi_transaction::type_id::create("rd_trans");
                trans.cfg = cfg;
                
                // Capture all AR channel fields
                trans.trans_type = axi_transaction::AXI_READ;
                trans.id = vif.monitor_cb.arid;
                trans.addr = vif.monitor_cb.araddr;
                trans.len = vif.monitor_cb.arlen;
                trans.size = vif.monitor_cb.arsize;
                trans.burst = axi_transaction::axi_burst_type_e'(vif.monitor_cb.arburst);
                trans.addr_cycle = cycle_count;
                
                // Allocate arrays for response capture
                trans.rdata = new[trans.len + 1];
                trans.rresp = new[trans.len + 1];
                trans.data_cycle = new[trans.len + 1];
                
                // Store by ID (R channel has RID for direct matching)
                pending_r_resp[trans.id] = trans;
                read_beat_count[trans.id] = 0;
                
                num_read_addr++;
                
                `uvm_info("AXI_MON", $sformatf(
                    "AR captured: ID=%0d, addr=0x%h, len=%0d beats, cycle=%0d",
                    trans.id, trans.addr, trans.len+1, cycle_count), UVM_HIGH)
            end
        end
    endtask
    
    //==========================================================================
    // Read Data Channel Collector (R)
    // Matches R beats to transactions by RID and accumulates burst
    //==========================================================================
    virtual task collect_read_data();
        int id;
        axi_transaction trans;
        int beat;
        
        forever begin
            @(vif.monitor_cb);
            
            // Guard against reset and X-states
            if (!vif.reset_n) continue;
            if ($isunknown(vif.monitor_cb.rvalid)) continue;
            if ($isunknown(vif.monitor_cb.rready)) continue;
            
            // Detect R handshake
            if (vif.monitor_cb.rvalid && vif.monitor_cb.rready) begin
                id = vif.monitor_cb.rid;
                
                // Find matching transaction
                if (pending_r_resp.exists(id)) begin
                    trans = pending_r_resp[id];
                    beat = read_beat_count[id];
                    
                    // PROTOCOL CHECK: Too many R beats
                    if (beat > trans.len) begin
                        `uvm_error("AXI_PROTOCOL", $sformatf(
                            "Extra R beat for ID=%0d (expected %0d beats, got beat %0d)",
                            id, trans.len+1, beat+1))
                        num_protocol_violations++;
                        continue;
                    end
                    
                    // Capture R beat data and response
                    trans.rdata[beat] = vif.monitor_cb.rdata;
                    trans.rresp[beat] = axi_transaction::axi_resp_e'(vif.monitor_cb.rresp);
                    trans.data_cycle[beat] = cycle_count;
                    
                    // Increment beat counter
                    read_beat_count[id]++;
                    num_read_data++;
                    
                    `uvm_info("AXI_MON", $sformatf(
                        "R beat %0d/%0d: ID=%0d, data=0x%h, last=%0b",
                        beat+1, trans.len+1, id, trans.rdata[beat], 
                        vif.monitor_cb.rlast), UVM_DEBUG)
                    
                    // PROTOCOL CHECK: RLAST validation
                    if (vif.monitor_cb.rlast) begin
                        // Check RLAST asserted at correct beat
                        if (beat != trans.len) begin
                            `uvm_error("AXI_PROTOCOL", $sformatf(
                                "RLAST asserted at beat %0d, expected at beat %0d (ID=%0d)",
                                beat, trans.len, id))
                            num_protocol_violations++;
                        end
                        
                        // Transaction complete
                        trans.resp_cycle = cycle_count;
                        trans.latency_cycles = int'(trans.resp_cycle - trans.addr_cycle);
                        trans.completed = 1;
                        
                        // Check for errors
                        if (!trans.is_response_ok()) begin
                            trans.error = 1;
                            `uvm_warning("AXI_MON", $sformatf(
                                "Read error response(s): ID=%0d", id))
                        end
                        
                        // Clean up
                        pending_r_resp.delete(id);
                        read_beat_count.delete(id);
                        
                        `uvm_info("AXI_MON", $sformatf(
                            "Read complete: ID=%0d, latency=%0d cycles",
                            id, trans.latency_cycles), UVM_HIGH)
                        
                        // Send to scoreboard
                        ap_read.write(trans);
                        
                    end else begin
                        // Check RLAST was not missed
                        if (beat == trans.len) begin
                            `uvm_error("AXI_PROTOCOL", $sformatf(
                                "RLAST not asserted at final beat %0d (ID=%0d)",
                                beat, id))
                            num_protocol_violations++;
                        end
                    end
                    
                end else begin
                    // PROTOCOL VIOLATION: Response for unknown ID
                    `uvm_error("AXI_PROTOCOL", $sformatf(
                        "R data for unknown/completed ID=%0d (cycle %0d)",
                        id, cycle_count))
                    num_protocol_violations++;
                end
            end
        end
    endtask
    
    //==========================================================================
    // Timeout Watchdog
    // Periodically checks for hung transactions
    //==========================================================================
    virtual task detect_timeouts();
        forever begin
            // Check every 100 cycles
            repeat(100) @(vif.monitor_cb);
            
            if (!vif.reset_n) continue;
            
            // Check for hung writes waiting for W data
            foreach (aw_fifo[i]) begin
                if ((cycle_count - aw_fifo[i].addr_cycle) > cfg.timeout_cycles) begin
                    `uvm_error("AXI_TIMEOUT", $sformatf(
                        "Write data timeout: ID=%0d, addr=0x%h, waiting %0d cycles for W beats",
                        aw_fifo[i].id, aw_fifo[i].addr, 
                        cycle_count - aw_fifo[i].addr_cycle))
                end
            end
            
            // Check for hung writes waiting for B response
            foreach (pending_b_resp[id]) begin
                if ((cycle_count - pending_b_resp[id].addr_cycle) > cfg.timeout_cycles) begin
                    `uvm_error("AXI_TIMEOUT", $sformatf(
                        "Write response timeout: ID=%0d, addr=0x%h, waiting %0d cycles for B response",
                        id, pending_b_resp[id].addr, 
                        cycle_count - pending_b_resp[id].addr_cycle))
                end
            end
            
            // Check for hung reads waiting for R response
            foreach (pending_r_resp[id]) begin
                if ((cycle_count - pending_r_resp[id].addr_cycle) > cfg.timeout_cycles) begin
                    `uvm_error("AXI_TIMEOUT", $sformatf(
                        "Read response timeout: ID=%0d, addr=0x%h, waiting %0d cycles for R data",
                        id, pending_r_resp[id].addr, 
                        cycle_count - pending_r_resp[id].addr_cycle))
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
        if (aw_fifo.size() > 0) begin
            `uvm_warning("AXI_MON", $sformatf(
                "%0d write addresses waiting for W data at end of test",
                aw_fifo.size()))
        end
        
        if (pending_b_resp.size() > 0) begin
            `uvm_warning("AXI_MON", $sformatf(
                "%0d write transactions waiting for B response at end of test",
                pending_b_resp.size()))
        end
        
        if (pending_r_resp.size() > 0) begin
            `uvm_warning("AXI_MON", $sformatf(
                "%0d read transactions waiting for R data at end of test",
                pending_r_resp.size()))
        end
        
        // Report protocol violations
        if (num_protocol_violations > 0) begin
            `uvm_error("AXI_MON", $sformatf(
                "Test completed with %0d AXI protocol violations",
                num_protocol_violations))
        end
    endfunction
    
    //==========================================================================
    // Report Phase
    // Print statistics summary
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("AXI_MON", {"\n",
            "========================================\n",
            "    AXI Monitor Statistics\n",
            "========================================\n",
            $sformatf("  Write Addresses:     %0d\n", num_write_addr),
            $sformatf("  Write Data Beats:    %0d\n", num_write_data),
            $sformatf("  Write Responses:     %0d\n", num_write_resp),
            $sformatf("  Read Addresses:      %0d\n", num_read_addr),
            $sformatf("  Read Data Beats:     %0d\n", num_read_data),
            $sformatf("  Protocol Violations: %0d\n", num_protocol_violations),
            $sformatf("  Pending AW (no W):   %0d\n", aw_fifo.size()),
            $sformatf("  Pending B:           %0d\n", pending_b_resp.size()),
            $sformatf("  Pending R:           %0d\n", pending_r_resp.size()),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : axi_monitor

`endif // AXI_MONITOR_SV
