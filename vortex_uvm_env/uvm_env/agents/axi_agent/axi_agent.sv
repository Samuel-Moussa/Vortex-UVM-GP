////////////////////////////////////////////////////////////////////////////////
// File: axi_agent.sv
// Description: AXI4 UVM Agent Container
//
// The agent encapsulates the AXI4 verification components into a reusable
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
// Analysis Ports:
//   - ap_write: Broadcasts completed write transactions
//   - ap_read:  Broadcasts completed read transactions
//   These connect to scoreboards, coverage collectors, etc.
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_AGENT_SV
`define AXI_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import axi_agent_pkg::*;

class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)
    
    //==========================================================================
    // Sub-Components
    //==========================================================================
    axi_driver    m_driver;     // Drives transactions to DUT (active mode only)
    axi_monitor   m_monitor;    // Observes all AXI channels (always present)
    axi_sequencer m_sequencer;  // Generates transactions (active mode only)
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Analysis Ports (Forwarded from Monitor)
    // These allow external components to observe completed transactions
    //==========================================================================
    uvm_analysis_port #(axi_transaction) ap_write;
    uvm_analysis_port #(axi_transaction) ap_read;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    // Create sub-components based on agent mode (active/passive)
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);

        virtual vortex_axi_if vif;
        
        super.build_phase(phase);
        
        // Get configuration from config DB
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("AXI_AGENT", "No vortex_config found - creating default", UVM_MEDIUM)
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
        
        // Get virtual interface from config DB
        if (uvm_config_db#(virtual vortex_axi_if)::get(this, "", "vif_axi", vif)) begin
            // Propagate interface to sub-components
            uvm_config_db#(virtual vortex_axi_if)::set(this, "m_driver", "vif", vif);
            uvm_config_db#(virtual vortex_axi_if)::set(this, "m_monitor", "vif", vif);
        end else begin
            `uvm_warning("AXI_AGENT", "No virtual interface found in config DB")
        end
        
        // Propagate configuration to sub-components
        uvm_config_db#(vortex_config)::set(this, "m_driver", "cfg", cfg);
        uvm_config_db#(vortex_config)::set(this, "m_monitor", "cfg", cfg);
        
        // Monitor is always created (needed for observation in both modes)
        m_monitor = axi_monitor::type_id::create("m_monitor", this);
        
        // Driver and sequencer only created in active mode
        if (get_is_active() == UVM_ACTIVE) begin
            m_driver = axi_driver::type_id::create("m_driver", this);
            m_sequencer = axi_sequencer::type_id::create("m_sequencer", this);
        end
        
        // Create analysis ports for external connections
        ap_write = new("ap_write", this);
        ap_read = new("ap_read", this);
    endfunction
    
    //==========================================================================
    // Connect Phase
    // Wire up internal connections between sub-components
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // In active mode: connect driver to sequencer
        if (get_is_active() == UVM_ACTIVE) begin
            // This is the standard UVM TLM connection
            // Driver pulls transactions from sequencer via this port/export pair
            m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
        end
        
        // Forward monitor's analysis ports to agent's analysis ports
        // This allows external components to connect to agent instead of monitor
        m_monitor.ap_write.connect(ap_write);
        m_monitor.ap_read.connect(ap_read);
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    // Print configuration summary for debugging
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("AXI_AGENT", $sformatf(
            "AXI Agent configured: %s mode, ID_WIDTH=%0d",
            get_is_active() == UVM_ACTIVE ? "ACTIVE" : "PASSIVE",
            cfg.AXI_ID_WIDTH), UVM_MEDIUM)
    endfunction
    
endclass : axi_agent

`endif // AXI_AGENT_SV
