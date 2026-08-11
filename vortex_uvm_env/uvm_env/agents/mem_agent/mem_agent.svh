////////////////////////////////////////////////////////////////////////////////
// File: mem_agent.sv
// Description: Memory Agent Container for Vortex Custom Memory Interface
//
// The agent encapsulates all memory verification components into a reusable
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
//   - ap: Broadcasts completed memory transactions
//   This connects to scoreboard for Option A comparison (final state)
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef MEM_AGENT_SV
`define MEM_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import mem_agent_pkg::*;

class mem_agent extends uvm_agent;
    `uvm_component_utils(mem_agent)
    
    //==========================================================================
    // Sub-Components
    //==========================================================================
    mem_driver    m_driver;     // Drives transactions to DUT (active mode only)
    mem_monitor   m_monitor;    // Observes all memory traffic (always present)
    mem_sequencer m_sequencer;  // Generates transactions (active mode only)
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Analysis Port (Forwarded from Monitor)
    // External components (scoreboard) connect here
    //==========================================================================
    uvm_analysis_port #(mem_transaction) ap;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mem_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    // Create sub-components based on agent mode
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        
        // Get virtual interface from config DB
        virtual vortex_mem_if vif;

        super.build_phase(phase);
        
        // Get configuration from config DB
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("MEM_AGENT", "No vortex_config found - creating default", UVM_MEDIUM)
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
        

        if (uvm_config_db#(virtual vortex_mem_if)::get(this, "", "vif_mem", vif)) begin
            // Propagate interface to sub-components
            uvm_config_db#(virtual vortex_mem_if)::set(this, "m_driver", "vif", vif);
            uvm_config_db#(virtual vortex_mem_if)::set(this, "m_monitor", "vif", vif);
        end else begin
            `uvm_warning("MEM_AGENT", "No virtual interface found in config DB")
        end
        
        // Propagate configuration to sub-components
        uvm_config_db#(vortex_config)::set(this, "m_driver", "cfg", cfg);
        uvm_config_db#(vortex_config)::set(this, "m_monitor", "cfg", cfg);
        
        // Monitor is always created (needed for observation in both modes)
        m_monitor = mem_monitor::type_id::create("m_monitor", this);
        
        // Driver and sequencer only created in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            m_driver = mem_driver::type_id::create("m_driver", this);
            m_sequencer = mem_sequencer::type_id::create("m_sequencer", this);
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
        if (get_is_active() == UVM_ACTIVE) begin
            // Standard UVM TLM connection
            // Driver pulls transactions from sequencer via this port/export pair
            m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
        end
        
        // Forward monitor's analysis port to agent's analysis port
        // This allows external components to connect to agent instead of monitor
        m_monitor.ap.connect(ap);
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    // Print configuration summary for debugging
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("MEM_AGENT", $sformatf(
            "Memory agent configured: %s mode",
            get_is_active() == UVM_ACTIVE ? "ACTIVE" : "PASSIVE"),
            UVM_MEDIUM)
    endfunction
    
endclass : mem_agent

`endif // MEM_AGENT_SV
