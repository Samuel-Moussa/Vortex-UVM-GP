////////////////////////////////////////////////////////////////////////////////
// File: axi_driver.sv
// Description: AXI4 Master Driver with Full Protocol Compliance
//
// This driver implements an AXI4 master that drives transactions from the
// sequencer to the DUT's AXI slave interface. It handles:
//   - 5 independent AXI channels (AW, W, B, AR, R)
//   - Out-of-order transaction support via ID management
//   - Write channel serialization option (W channel has no WID in AXI4)
//   - Backpressure tolerance (READY can toggle)
//   - Timeout protection on all handshakes
//   - Cycle-accurate latency tracking
//
// Operation:
//   1. Allocate ID from pool (blocks if all IDs in use)
//   2. Drive address phase (AW or AR channel)
//   3. Drive data phase (W channel for writes, receive R for reads)
//   4. Collect responses (B for writes, R for reads)
//   5. Release ID back to pool
//
// Key Features:
//   ✓ Clocking blocks prevent race conditions
//   ✓ Configurable ID width from vortex_config
//   ✓ VALID never drops before READY (protocol compliant)
//   ✓ Comprehensive timeout protection
//   ✓ Optional write serialization for W channel matching
//   ✓ Detailed statistics and error reporting
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import axi_agent_pkg::*;

class axi_driver extends uvm_driver #(axi_transaction);
    `uvm_component_utils(axi_driver)
    
    //==========================================================================
    // Virtual Interface Handle
    // Uses master_driver modport with clocking block for race-free operation
    //==========================================================================
    virtual vortex_axi_if.master_driver vif;
    
    //==========================================================================
    // Configuration Object
    // Provides AXI_ID_WIDTH, timeout_cycles, and other parameters
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // ID Pool Management
    // Tracks which transaction IDs are currently in use
    // AXI4 allows multiple outstanding transactions per ID is unique
    //==========================================================================
    bit id_pool[];              // Dynamic array: 0=free, 1=in use
    int num_ids_available;      // Count of free IDs
    int max_ids;                // Total IDs = 2^AXI_ID_WIDTH
    
    //==========================================================================
    // Write Serialization Control
    // Option A solution for W channel matching (no WID in AXI4)
    // When enabled: Only one write transaction active at a time
    // When disabled: Multiple writes can be in-flight (need monitor FIFO matching)
    //==========================================================================
    semaphore write_sema;       // Binary semaphore (0 or 1 permits)
    bit enforce_write_order;    // Enable/disable serialization
    
    //==========================================================================
    // Outstanding Transaction Tracking
    // Maps ID -> transaction for response matching
    //==========================================================================
    axi_transaction outstanding_writes[int];  // ID -> incomplete write
    axi_transaction outstanding_reads[int];   // ID -> incomplete read
    
    //==========================================================================
    // Beat Counters for Multi-Beat Bursts
    // Explicit counters prevent data==0 logic errors
    //==========================================================================
    int read_beat_count[int];   // ID -> current R beat being received
    int write_beat_count[int];  // ID -> current W beat being sent
    
    //==========================================================================
    // Cycle Counter for Accurate Latency Measurement
    // Increments every clock edge - avoids timescale dependencies
    //==========================================================================
    longint cycle_count;
    
    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int num_writes;             // Total write transactions completed
    int num_reads;              // Total read transactions completed
    longint total_write_latency; // Sum of all write latencies
    longint total_read_latency;  // Sum of all read latencies
    
    //==========================================================================
    // Synchronization Events
    //==========================================================================
    event reset_done;           // Triggered when reset completes
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_driver", uvm_component parent = null);
        super.new(name, parent);
        
        // Initialize statistics
        num_writes = 0;
        num_reads = 0;
        total_write_latency = 0;
        total_read_latency = 0;
        cycle_count = 0;
        
        // Enable write serialization by default (safe W channel matching)
        enforce_write_order = 1;
    endfunction
    
    //==========================================================================
    // Build Phase
    // Retrieve interface and config, allocate ID pool
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface from config DB
        // This should be set by the testbench top module
        if (!uvm_config_db#(virtual vortex_axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_DRV", "Failed to get virtual interface from config DB")
        end
        
        // Get configuration object
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("AXI_DRV", "No vortex_config found - using defaults")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
        
        // Calculate maximum IDs based on configured width
        // Example: AXI_ID_WIDTH=4 -> max_ids=16
        max_ids = (1 << cfg.AXI_ID_WIDTH);
        
        // Allocate ID pool array
        id_pool = new[max_ids];
        num_ids_available = max_ids;
        
        // Create write serialization semaphore
        write_sema = new(1); // Starts with 1 permit (available)
        
        `uvm_info("AXI_DRV", $sformatf(
            "Driver configured: ID_WIDTH=%0d (%0d IDs available), Write serialization=%s",
            cfg.AXI_ID_WIDTH, max_ids, enforce_write_order ? "ON" : "OFF"), UVM_MEDIUM)
    endfunction
    
    //==========================================================================
    // Reset Phase
    // Wait for reset deassertion and initialize all state
    //==========================================================================
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        phase.raise_objection(this);
        
        `uvm_info("AXI_DRV", "Waiting for reset deassertion...", UVM_MEDIUM)
        
        // Wait for reset to assert
        wait(vif.reset_n == 1'b0);
        
        // Wait for reset to deassert
        wait(vif.reset_n == 1'b1);
        
        // Wait additional cycles for DUT stabilization
        repeat(5) @(vif.master_cb);
        
        // Initialize ID pool - all IDs are free
        foreach (id_pool[i]) id_pool[i] = 0;
        num_ids_available = max_ids;
        
        // Reset cycle counter
        cycle_count = 0;
        
        // Signal that reset is complete
        -> reset_done;
        `uvm_info("AXI_DRV", "Reset complete - driver ready", UVM_MEDIUM)
        
        phase.drop_objection(this);
    endtask
    
    //==========================================================================
    // Run Phase
    // Main driver loop: get transactions and drive them to DUT
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        axi_transaction trans;
        
        // Wait for reset sequence to complete
        @(reset_done);
        
        // Initialize all output signals using clocking block
        @(vif.master_cb);
        vif.master_cb.awvalid <= 1'b0;
        vif.master_cb.wvalid  <= 1'b0;
        vif.master_cb.bready  <= 1'b1;  // Always ready for write responses
        vif.master_cb.arvalid <= 1'b0;
        vif.master_cb.rready  <= 1'b1;  // Always ready for read data
        
        // Start background tasks
        fork
            // Cycle counter - increments every clock
            forever begin
                @(vif.master_cb);
                cycle_count++;
            end
            
            // Response collectors run continuously
            collect_write_responses();
            collect_read_responses();
        join_none
        
        // Main driver loop - process transactions from sequencer
        forever begin
            // Get next transaction from sequencer
            seq_item_port.get_next_item(trans);
            
            `uvm_info("AXI_DRV", $sformatf("Received transaction:\n%s", 
                trans.convert2string()), UVM_HIGH)
            
            // Allocate an ID for this transaction
            // Blocks if all IDs are in use
            allocate_id(trans);
            
            // Pass config handle to transaction for constraint evaluation
            trans.cfg = cfg;
            
            // Drive transaction based on type
            if (trans.trans_type == axi_transaction::AXI_WRITE) begin
                drive_write_transaction(trans);
            end else begin
                drive_read_transaction(trans);
            end
            
            // Notify sequencer that we're done with this item
            seq_item_port.item_done();
        end
    endtask
    
    //==========================================================================
    // ID Pool Management Functions
    //==========================================================================
    
    // Allocate an ID from the pool
    // Blocks with timeout if no IDs are available
    virtual task allocate_id(axi_transaction trans);
        int timeout_counter = 0;
        
        // Wait for an ID to become available
        while (num_ids_available == 0) begin
            `uvm_info("AXI_DRV", "All IDs in use - waiting...", UVM_HIGH)
            @(vif.master_cb);
            
            timeout_counter++;
            if (timeout_counter >= cfg.timeout_cycles) begin
                `uvm_fatal("AXI_DRV", $sformatf(
                    "ID allocation timeout after %0d cycles - all %0d IDs busy",
                    timeout_counter, max_ids))
            end
        end
        
        // Find the first free ID
        for (int i = 0; i < max_ids; i++) begin
            if (!id_pool[i]) begin
                // Mark ID as in use
                id_pool[i] = 1;
                trans.id = i;
                num_ids_available--;
                
                `uvm_info("AXI_DRV", $sformatf(
                    "Allocated ID=%0d (%0d IDs remaining)", 
                    i, num_ids_available), UVM_HIGH)
                return;
            end
        end
    endtask
    
    // Release an ID back to the pool
    virtual function void release_id(int id);
        // Sanity check
        if (id >= max_ids) begin
            `uvm_error("AXI_DRV", $sformatf("Invalid ID=%0d (max=%0d)", id, max_ids))
            return;
        end
        
        if (id_pool[id]) begin
            // Mark ID as free
            id_pool[id] = 0;
            num_ids_available++;
            
            `uvm_info("AXI_DRV", $sformatf(
                "Released ID=%0d (%0d IDs available)", 
                id, num_ids_available), UVM_HIGH)
        end else begin
            `uvm_warning("AXI_DRV", $sformatf(
                "Attempted to release already-free ID=%0d", id))
        end
    endfunction
    
    //==========================================================================
    // Write Transaction Driver
    // Drives AW and W channels in parallel, then waits for B response
    //==========================================================================
    virtual task drive_write_transaction(axi_transaction trans);
        // Capture starting cycle
        trans.addr_cycle = cycle_count;
        
        // Store in outstanding writes map
        outstanding_writes[trans.id] = trans;
        write_beat_count[trans.id] = 0;
        
        // Optionally enforce write serialization (safe W channel matching)
        if (enforce_write_order) begin
            write_sema.get(); // Block if another write is active
        end
        
        // Drive AW and W channels in parallel with watchdog protection
        fork
            begin
                // Drive both channels
                fork
                    drive_write_address(trans);
                    drive_write_data(trans);
                join
            end
            
            begin
                // Watchdog timer - kills transaction if it hangs
                repeat(cfg.timeout_cycles) @(vif.master_cb);
                
                if (!trans.completed) begin
                    `uvm_fatal("AXI_DRV", $sformatf(
                        "Write transaction ID=%0d timed out after %0d cycles",
                        trans.id, cfg.timeout_cycles))
                end
            end
        join_any
        disable fork; // Kill watchdog if transaction completed
        
        num_writes++;
        `uvm_info("AXI_DRV", $sformatf(
            "Write transaction ID=%0d address and data phases complete", 
            trans.id), UVM_HIGH)
    endtask
    
    //==========================================================================
    // Write Address Channel (AW) Driver
    // Drives address phase - AWVALID stays high until AWREADY
    //==========================================================================
    virtual task drive_write_address(axi_transaction trans);
        int timeout_counter = 0;
        
        // Wait for clock edge
        @(vif.master_cb);
        
        // Drive all AW channel signals
        vif.master_cb.awvalid <= 1'b1;
        //vif.master_cb.awid    <= trans.id[cfg.AXI_ID_WIDTH-1:0];
        vif.master_cb.awid <= $bits(vif.master_cb.awid)'(trans.id);
        vif.master_cb.awaddr  <= trans.addr;
        vif.master_cb.awlen   <= trans.len;
        vif.master_cb.awsize  <= trans.size;
        vif.master_cb.awburst <= trans.burst;
        
        // CRITICAL: AWVALID must remain high until AWREADY
        // This loop implements proper AXI4 handshake protocol
        fork
            begin
                do begin
                    @(vif.master_cb);
                    timeout_counter++;
                end while (!vif.master_cb.awready);
            end
            
            begin
                repeat(cfg.timeout_cycles) @(vif.master_cb);
                `uvm_fatal("AXI_DRV", $sformatf(
                    "AW handshake timeout after %0d cycles for ID=%0d, addr=0x%h",
                    timeout_counter, trans.id, trans.addr))
            end
        join_any
        disable fork;
        
        // Deassert AWVALID after handshake completes
        vif.master_cb.awvalid <= 1'b0;
        
        `uvm_info("AXI_DRV", $sformatf(
            "AW handshake complete: ID=%0d, addr=0x%h, len=%0d, cycles=%0d",
            trans.id, trans.addr, trans.get_num_beats(), timeout_counter), UVM_HIGH)
    endtask
    
    //==========================================================================
    // Write Data Channel (W) Driver
    // Drives data beats - WVALID stays high until WREADY for each beat
    //==========================================================================
    virtual task drive_write_data(axi_transaction trans);
        int timeout_counter;
        
        // Drive each data beat
        for (int i = 0; i <= trans.len; i++) begin
            // Capture cycle number for this beat
            trans.data_cycle[i] = cycle_count;
            
            timeout_counter = 0;
            
            // Wait for clock edge
            @(vif.master_cb);
            
            // Drive all W channel signals
            vif.master_cb.wvalid <= 1'b1;
            vif.master_cb.wdata  <= trans.wdata[i];
            vif.master_cb.wstrb  <= trans.wstrb[i];
            vif.master_cb.wlast  <= (i == trans.len); // Last beat indicator
            
            // CRITICAL: WVALID must remain high until WREADY
            fork
                begin
                    do begin
                        @(vif.master_cb);
                        timeout_counter++;
                    end while (!vif.master_cb.wready);
                end
                
                begin
                    repeat(cfg.timeout_cycles) @(vif.master_cb);
                    `uvm_fatal("AXI_DRV", $sformatf(
                        "W handshake timeout after %0d cycles for beat %0d/%0d, ID=%0d",
                        timeout_counter, i+1, trans.get_num_beats(), trans.id))
                end
            join_any
            disable fork;
            
            // Deassert WVALID after handshake completes
            vif.master_cb.wvalid <= 1'b0;
            
            `uvm_info("AXI_DRV", $sformatf(
                "W beat %0d/%0d complete: ID=%0d, data=0x%h, last=%0b, cycles=%0d",
                i+1, trans.get_num_beats(), trans.id, trans.wdata[i], 
                (i == trans.len), timeout_counter), UVM_DEBUG)
        end
    endtask
    
    //==========================================================================
    // Read Transaction Driver
    // Drives AR channel, then responses are collected in background task
    //==========================================================================
    virtual task drive_read_transaction(axi_transaction trans);
        int timeout_counter = 0;
        
        // Capture starting cycle
        trans.addr_cycle = cycle_count;
        
        // Store in outstanding reads map
        outstanding_reads[trans.id] = trans;
        
        // Initialize beat counter for response collection
        read_beat_count[trans.id] = 0;
        
        // Wait for clock edge
        @(vif.master_cb);
        
        // Drive all AR channel signals
        vif.master_cb.arvalid <= 1'b1;
        //vif.master_cb.arid    <= trans.id[cfg.AXI_ID_WIDTH-1:0];
        vif.master_cb.arid <= $bits(vif.master_cb.arid)'(trans.id);
        vif.master_cb.araddr  <= trans.addr;
        vif.master_cb.arlen   <= trans.len;
        vif.master_cb.arsize  <= trans.size;
        vif.master_cb.arburst <= trans.burst;
        
        // CRITICAL: ARVALID must remain high until ARREADY
        fork
            begin
                do begin
                    @(vif.master_cb);
                    timeout_counter++;
                end while (!vif.master_cb.arready);
            end
            
            begin
                repeat(cfg.timeout_cycles) @(vif.master_cb);
                `uvm_fatal("AXI_DRV", $sformatf(
                    "AR handshake timeout after %0d cycles for ID=%0d, addr=0x%h",
                    timeout_counter, trans.id, trans.addr))
            end
        join_any
        disable fork;
        
        // Deassert ARVALID after handshake completes
        vif.master_cb.arvalid <= 1'b0;
        
        num_reads++;
        `uvm_info("AXI_DRV", $sformatf(
            "AR handshake complete: ID=%0d, addr=0x%h, len=%0d, cycles=%0d",
            trans.id, trans.addr, trans.get_num_beats(), timeout_counter), UVM_HIGH)
    endtask
    
    //==========================================================================
    // Write Response Collector (B Channel)
    // Runs continuously in background, matches BID to transaction
    //==========================================================================
    virtual task collect_write_responses();
        int id;
        axi_transaction trans;
        
        forever begin
            @(vif.master_cb);
            
            // Detect B channel handshake
            if (vif.master_cb.bvalid && vif.master_cb.bready) begin
                id = vif.master_cb.bid;
                
                // Find matching transaction
                if (outstanding_writes.exists(id)) begin
                    trans = outstanding_writes[id];
                    
                    // Capture response
                    trans.bresp = axi_transaction::axi_resp_e'(vif.master_cb.bresp);
                    
                    // Calculate cycle-accurate latency
                    trans.resp_cycle = cycle_count;
                    trans.latency_cycles = int'(trans.resp_cycle - trans.addr_cycle);
                    
                    // Mark as completed
                    trans.completed = 1;
                    
                    // Check for errors
                    if (trans.bresp != axi_transaction::AXI_OKAY) begin
                        trans.error = 1;
                        `uvm_error("AXI_DRV", $sformatf(
                            "Write error response: ID=%0d, resp=%s",
                            id, trans.bresp.name()))
                    end
                    
                    // Update statistics
                    total_write_latency += trans.latency_cycles;
                    
                    // Clean up tracking structures
                    outstanding_writes.delete(id);
                    write_beat_count.delete(id);
                    
                    // Release ID back to pool
                    release_id(id);
                    
                    // Release write serialization semaphore
                    if (enforce_write_order) begin
                        write_sema.put();
                    end
                    
                    `uvm_info("AXI_DRV", $sformatf(
                        "Write complete: ID=%0d, latency=%0d cycles, resp=%s",
                        id, trans.latency_cycles, trans.bresp.name()), UVM_HIGH)
                    
                end else begin
                    `uvm_error("AXI_DRV", $sformatf(
                        "B response for unknown/completed ID: %0d", id))
                end
            end
        end
    endtask
    
    //==========================================================================
    // Read Response Collector (R Channel)
    // Runs continuously in background, accumulates multi-beat responses
    //==========================================================================
    virtual task collect_read_responses();
        int id;
        axi_transaction trans;
        int beat;
        
        forever begin
            @(vif.master_cb);
            
            // Detect R channel handshake
            if (vif.master_cb.rvalid && vif.master_cb.rready) begin
                id = vif.master_cb.rid;
                
                // Find matching transaction
                if (outstanding_reads.exists(id)) begin
                    trans = outstanding_reads[id];
                    
                    // Get current beat number using explicit counter
                    beat = read_beat_count[id];
                    
                    // Capture data and response for this beat
                    trans.rdata[beat] = vif.master_cb.rdata;
                    trans.rresp[beat] = axi_transaction::axi_resp_e'(vif.master_cb.rresp);
                    
                    // Increment beat counter AFTER capturing data
                    read_beat_count[id]++;
                    
                    `uvm_info("AXI_DRV", $sformatf(
                        "R beat %0d/%0d received: ID=%0d, data=0x%h",
                        beat+1, trans.get_num_beats(), id, trans.rdata[beat]), UVM_DEBUG)
                    
                    // Check if this is the last beat
                    if (vif.master_cb.rlast) begin
                        // Calculate cycle-accurate latency
                        trans.resp_cycle = cycle_count;
                        trans.latency_cycles = int'(trans.resp_cycle - trans.addr_cycle);
                        
                        // Mark as completed
                        trans.completed = 1;
                        
                        // Check for errors across all beats
                        if (!trans.is_response_ok()) begin
                            trans.error = 1;
                            `uvm_error("AXI_DRV", $sformatf(
                                "Read error response(s): ID=%0d", id))
                        end
                        
                        // Update statistics
                        total_read_latency += trans.latency_cycles;
                        
                        // Clean up tracking structures
                        outstanding_reads.delete(id);
                        read_beat_count.delete(id);
                        
                        // Release ID back to pool
                        release_id(id);
                        
                        `uvm_info("AXI_DRV", $sformatf(
                            "Read complete: ID=%0d, latency=%0d cycles",
                            id, trans.latency_cycles), UVM_HIGH)
                    end
                    
                end else begin
                    `uvm_error("AXI_DRV", $sformatf(
                        "R data for unknown/completed ID: %0d", id))
                end
            end
        end
    endtask
    
    //==========================================================================
    // Report Phase
    // Print statistics at end of simulation
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        real avg_write_latency, avg_read_latency;
        
        super.report_phase(phase);
        
        // Calculate averages
        if (num_writes > 0)
            avg_write_latency = real'(total_write_latency) / real'(num_writes);
        else
            avg_write_latency = 0.0;
        
        if (num_reads > 0)
            avg_read_latency = real'(total_read_latency) / real'(num_reads);
        else
            avg_read_latency = 0.0;
        
        // Print summary
        `uvm_info("AXI_DRV", {"\n",
            "========================================\n",
            "    AXI Driver Statistics\n",
            "========================================\n",
            $sformatf("  Total Writes:       %0d\n", num_writes),
            $sformatf("  Avg Write Latency:  %.2f cycles\n", avg_write_latency),
            $sformatf("  Total Reads:        %0d\n", num_reads),
            $sformatf("  Avg Read Latency:   %.2f cycles\n", avg_read_latency),
            $sformatf("  Outstanding Writes: %0d\n", outstanding_writes.size()),
            $sformatf("  Outstanding Reads:  %0d\n", outstanding_reads.size()),
            $sformatf("  Available IDs:      %0d / %0d\n", num_ids_available, max_ids),
            "========================================"
        }, UVM_LOW)
        
        // Warn about leaks
        if (outstanding_writes.size() > 0) begin
            `uvm_warning("AXI_DRV", $sformatf(
                "%0d write transactions did not complete", 
                outstanding_writes.size()))
        end
        
        if (outstanding_reads.size() > 0) begin
            `uvm_warning("AXI_DRV", $sformatf(
                "%0d read transactions did not complete", 
                outstanding_reads.size()))
        end
    endfunction
    
endclass : axi_driver

`endif // AXI_DRIVER_SV
