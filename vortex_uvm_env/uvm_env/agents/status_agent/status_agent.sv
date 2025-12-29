////////////////////////////////////////////////////////////////////////////////
// File: status_agent.sv
// Description: Status Agent Container for Vortex Execution Monitoring
//
// The status agent is a PASSIVE-ONLY agent (no driver or sequencer) that
// monitors the GPU's execution status. It provides:
//   - Real-time execution state tracking
//   - Program completion detection (EBREAK)
//   - Performance statistics
//   - Helper tasks for test synchronization
//
// Key Features:
//   - Always passive (read-only monitoring)
//   - Provides wait_execution_start() and wait_execution_complete() tasks
//   - Critical for Option A: signals scoreboard when to compare memory
//
// Usage in Test:
//   // Wait for program to complete
//   env.status_agent.wait_execution_complete();
//   // Now safe to compare RTL vs simx memory
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef STATUS_AGENT_SV
`define STATUS_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import status_agent_pkg::*;

class status_agent extends uvm_agent;
    `uvm_component_utils(status_agent)
    
    //==========================================================================
    // Sub-Components
    // Status agent only has monitor (no driver/sequencer - always passive)
    //==========================================================================
    status_monitor m_monitor;
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Analysis Port (Forwarded from Monitor)
    // External components (scoreboard, coverage) connect here
    //==========================================================================
    uvm_analysis_port #(status_transaction) ap;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "status_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    // Create monitor and configure sampling
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);

        // Get virtual interface from config DB and propagate to monitor
        virtual vortex_status_if vif;
        
        super.build_phase(phase);
        
        // Get configuration from config DB
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("STATUS_AGENT", "No vortex_config found - creating default", UVM_MEDIUM)
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
        

        if (uvm_config_db#(virtual vortex_status_if)::get(this, "", "vif_status", vif)) begin
            // Propagate interface to monitor
            uvm_config_db#(virtual vortex_status_if)::set(this, "m_monitor", "vif", vif);
        end else begin
            `uvm_warning("STATUS_AGENT", "No virtual interface found in config DB")
        end
        
        // Propagate configuration to monitor
        uvm_config_db#(vortex_config)::set(this, "m_monitor", "cfg", cfg);
        
        
        // Create monitor (only component in status agent)
        m_monitor = status_monitor::type_id::create("m_monitor", this);
        
        // Create analysis port for external connections
        ap = new("ap", this);
    endfunction
    
    //==========================================================================
    // Connect Phase
    // Forward monitor's analysis port to agent's analysis port
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Forward monitor's analysis port
        m_monitor.ap.connect(ap);
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    // Print configuration summary
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("STATUS_AGENT", "Status agent configured: PASSIVE (monitor-only)", UVM_MEDIUM)
        
        if (cfg.status_sample_interval > 1) begin
            `uvm_info("STATUS_AGENT", $sformatf(
                "Status sampling every %0d cycles", 
                cfg.status_sample_interval), UVM_MEDIUM)
        end
    endfunction
    
    //==========================================================================
    // Helper Tasks - Forwarded from Monitor
    // These allow tests to synchronize with execution events
    //==========================================================================
    
    // Wait for execution to start (busy goes HIGH)
    task wait_execution_start();
        m_monitor.wait_execution_start();
    endtask
    
    // Wait for execution to complete (EBREAK detected)
    // CRITICAL for Option A: Scoreboard calls this before comparing memory
    task wait_execution_complete();
        m_monitor.wait_execution_complete();
    endtask
    
endclass : status_agent

`endif // STATUS_AGENT_SV
