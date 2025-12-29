////////////////////////////////////////////////////////////////////////////////
// File: dcr_agent.sv
// Description: DCR Agent Container for Vortex GPU Configuration Interface
//
// The agent encapsulates all DCR verification components into a reusable
// module. It instantiates and connects:
//   - Driver (active mode only)
//   - Monitor (always present)
//   - Sequencer (active mode only)
//
// The agent can operate in two modes:
//   - ACTIVE:  Has driver and sequencer, can generate stimulus
//   - PASSIVE: Monitor only, observes existing traffic
//
// Configuration:
//   - Virtual interface propagated to driver and monitor
//   - Config object propagated to all sub-components
//   - Active/passive mode set via uvm_config_db
//
// Analysis Port:
//   - ap: Broadcasts DCR write transactions
//   This connects to scoreboard for verification
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef DCR_AGENT_SV
`define DCR_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import dcr_agent_pkg::*;


class dcr_agent extends uvm_agent;
    `uvm_component_utils(dcr_agent)
    
    //==========================================================================
    // Sub-Components
    //==========================================================================
    dcr_driver    m_driver;     // Drives DCR writes to DUT (active mode only)
    dcr_monitor   m_monitor;    // Observes all DCR traffic (always present)
    dcr_sequencer m_sequencer;  // Generates transactions (active mode only)
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Analysis Port (Forwarded from Monitor)
    // External components (scoreboard) connect here
    //==========================================================================
    uvm_analysis_port #(dcr_transaction) ap;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "dcr_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    // Create sub-components based on agent mode
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);

        virtual vortex_dcr_if vif;

        super.build_phase(phase);
        
        // Get configuration from config DB
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("DCR_AGENT", "No vortex_config found - creating default", UVM_MEDIUM)
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
        
        // Get virtual interface from config DB and propagate to sub-components
        if (uvm_config_db#(virtual vortex_dcr_if)::get(this, "", "vif_dcr", vif)) begin
            // Propagate interface to driver and monitor
            uvm_config_db#(virtual vortex_dcr_if)::set(this, "m_driver", "vif", vif);
            uvm_config_db#(virtual vortex_dcr_if)::set(this, "m_monitor", "vif", vif);
        end else begin
            `uvm_warning("DCR_AGENT", "No virtual interface found in config DB")
        end
        
        // Propagate configuration to sub-components
        uvm_config_db#(vortex_config)::set(this, "m_driver", "cfg", cfg);
        uvm_config_db#(vortex_config)::set(this, "m_monitor", "cfg", cfg);
        
        // Monitor is always created (needed for observation in both modes)
        m_monitor = dcr_monitor::type_id::create("m_monitor", this);
        
        // Driver and sequencer only created in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            // Additional check: only create if config allows DCR agent activity
            if (cfg.dcr_agent_is_active) begin
                m_driver = dcr_driver::type_id::create("m_driver", this);
                m_sequencer = dcr_sequencer::type_id::create("m_sequencer", this);
            end else begin
                `uvm_info("DCR_AGENT", "DCR agent set to passive per config", UVM_MEDIUM)
            end
        end
        
        // Create analysis port for external connections
        ap = new("ap", this);
    endfunction
    
    //==========================================================================
    // Connect Phase
    // Wire up internal connections between sub-components
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // In active mode: connect driver to sequencer
        if (get_is_active() == UVM_ACTIVE && m_driver != null) begin
            // Standard UVM TLM connection
            m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
        end
        
        // Forward monitor's analysis port to agent's analysis port
        m_monitor.ap.connect(ap);
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    // Print configuration summary for debugging
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        string mode_str;

        super.end_of_elaboration_phase(phase);
        
        if (get_is_active() == UVM_ACTIVE && m_driver != null)
            mode_str = "ACTIVE";
        else
            mode_str = "PASSIVE";
        
        `uvm_info("DCR_AGENT", $sformatf("DCR agent configured: %s mode", mode_str), UVM_MEDIUM)
    endfunction
    
endclass : dcr_agent

`endif // DCR_AGENT_SV
