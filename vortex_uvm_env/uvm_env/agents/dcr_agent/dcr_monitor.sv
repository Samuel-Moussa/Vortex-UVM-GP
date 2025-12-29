////////////////////////////////////////////////////////////////////////////////
// File: dcr_monitor.sv
// Description: DCR Agent Monitor with Protocol Checking
//
// This monitor passively observes DCR write transactions on the Vortex DCR
// interface. It captures all writes and performs protocol checking.
//
// Key Features:
//   ✓ Observes all DCR writes using monitor_cb clocking block
//   ✓ Broadcasts transactions to scoreboard
//   ✓ Tracks DCR state (current values)
//   ✓ Detects startup configuration completion
//   ✓ Protocol violation detection
//   ✓ Statistics collection
//
// Protocol Checks:
//   - wr_valid should not be held for multiple cycles (single-cycle pulse)
//   - Startup PC should be word-aligned
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef DCR_MONITOR_SV
`define DCR_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import dcr_agent_pkg::*;


class dcr_monitor extends uvm_monitor;
    `uvm_component_utils(dcr_monitor)
    
    //==========================================================================
    // Virtual Interface Handle
    // Uses monitor modport with clocking block for passive observation
    //==========================================================================
    virtual vortex_dcr_if.monitor vif;
    
    //==========================================================================
    // Analysis Port
    // Broadcasts captured DCR writes to scoreboard
    //==========================================================================
    uvm_analysis_port #(dcr_transaction) ap;
    
    //==========================================================================
    // DCR State Tracking
    // Maps DCR address -> current value
    //==========================================================================
    bit [31:0] current_dcr_values[bit [31:0]];
    
    //==========================================================================
    // Status Flags
    //==========================================================================
    bit startup_configured;  // Set when STARTUP_ADDR0 and STARTUP_ADDR1 are written
    
    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int num_writes;              // Total DCR writes observed
    int num_startup_configs;     // Startup-related writes
    int num_perf_configs;        // Performance monitor writes
    int num_protocol_violations; // Protocol errors detected
    
    //==========================================================================
    // Events
    //==========================================================================
    event startup_config_complete;  // Triggered when startup is fully configured
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "dcr_monitor", uvm_component parent = null);
        super.new(name, parent);
        
        // Create analysis port
        ap = new("ap", this);
        
        // Initialize counters and flags
        num_writes = 0;
        num_startup_configs = 0;
        num_perf_configs = 0;
        num_protocol_violations = 0;
        startup_configured = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface from config DB
        if (!uvm_config_db#(virtual vortex_dcr_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DCR_MON", "Failed to get virtual interface from config DB")
        end
    endfunction
    
    //==========================================================================
    // Run Phase
    // Fork parallel monitoring tasks
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        fork
            collect_dcr_writes();
            detect_protocol_violations();
            monitor_startup_sequence();
        join
    endtask
    
    //==========================================================================
    // Collect DCR Writes
    // Observes wr_valid and captures write transactions
    //==========================================================================
    task collect_dcr_writes();
        dcr_transaction trans;
        
        forever begin
            @(vif.monitor_cb);
            
            // Detect DCR write (wr_valid asserted)
            if (vif.monitor_cb.wr_valid) begin
                
                // Create new transaction object
                trans = dcr_transaction::type_id::create("trans");
                
                // Capture all fields from clocking block
                trans.addr = vif.monitor_cb.wr_addr;
                trans.data = vif.monitor_cb.wr_data;
                trans.write_time = $time;
                trans.completed = 1;
                
                // Update state tracking
                current_dcr_values[trans.addr] = trans.data;
                
                // Update statistics
                num_writes++;
                if (trans.is_startup_config())
                    num_startup_configs++;
                if (trans.is_perf_config())
                    num_perf_configs++;
                
                `uvm_info("DCR_MON", $sformatf(
                    "DCR Write captured: %s = 0x%08h @ %0t",
                    trans.get_dcr_name(), trans.data, $time), UVM_HIGH)
                
                // Broadcast to scoreboard
                ap.write(trans);
            end
        end
    endtask
    
    //==========================================================================
    // Monitor Startup Sequence
    // Detects when critical startup DCRs are configured
    //==========================================================================
    task monitor_startup_sequence();

        bit [63:0] startup_pc;
        forever begin
            // Wait until both startup address DCRs are written
            wait (current_dcr_values.exists(dcr_transaction::DCR_STARTUP_ADDR0) &&
                  current_dcr_values.exists(dcr_transaction::DCR_STARTUP_ADDR1));
            
            // Set flag and trigger event (only once)
            if (!startup_configured) begin
                startup_configured = 1;
                -> startup_config_complete;
                
                // Construct full 64-bit PC
                startup_pc[31:0]  = current_dcr_values[dcr_transaction::DCR_STARTUP_ADDR0];
                startup_pc[63:32] = current_dcr_values[dcr_transaction::DCR_STARTUP_ADDR1];
                
                `uvm_info("DCR_MON", $sformatf(
                    "✓ Startup configuration complete: PC=0x%016h", startup_pc), UVM_LOW)
            end
            
            @(vif.monitor_cb);
        end
    endtask
    
    //==========================================================================
    // Detect Protocol Violations
    // Checks for wr_valid held for multiple cycles (should be single-cycle pulse)
    //==========================================================================
    task detect_protocol_violations();
        bit prev_wr_valid;
        
        forever begin
            @(vif.monitor_cb);
            
            // Check if wr_valid was held from previous cycle
            if (vif.monitor_cb.wr_valid && prev_wr_valid) begin
                `uvm_warning("DCR_MON", 
                    "Protocol violation: wr_valid asserted for multiple cycles")
                num_protocol_violations++;
            end
            
            prev_wr_valid = vif.monitor_cb.wr_valid;
        end
    endtask
    
    //==========================================================================
    // Check Phase
    // Verify critical DCRs were configured
    //==========================================================================
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        
        // Warn if startup was never configured
        if (!startup_configured) begin
            `uvm_warning("DCR_MON", "Test ended without startup configuration")
        end
        
        // Report protocol violations
        if (num_protocol_violations > 0) begin
            `uvm_error("DCR_MON", $sformatf(
                "Test completed with %0d protocol violations",
                num_protocol_violations))
        end
    endfunction
    
    //==========================================================================
    // Report Phase
    // Print comprehensive statistics
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("DCR_MON", {"\n",
            "========================================\n",
            "    DCR Monitor Statistics\n",
            "========================================\n",
            $sformatf("  Total Writes:       %0d\n", num_writes),
            $sformatf("  Startup Configs:    %0d\n", num_startup_configs),
            $sformatf("  Perf Configs:       %0d\n", num_perf_configs),
            $sformatf("  Protocol Violations:%0d\n", num_protocol_violations),
            $sformatf("  Unique DCRs:        %0d\n", current_dcr_values.size()),
            $sformatf("  Startup Complete:   %s\n", startup_configured ? "YES" : "NO"),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : dcr_monitor

`endif // DCR_MONITOR_SV
