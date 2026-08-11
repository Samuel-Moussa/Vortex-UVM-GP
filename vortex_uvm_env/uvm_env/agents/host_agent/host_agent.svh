////////////////////////////////////////////////////////////////////////////////
// File: host_agent.sv
// Description: Host Agent with Full Clocking Block Integration
//
// The host agent is the "conductor" of the verification environment, 
// orchestrating multiple interfaces to perform high-level operations:
//   - Memory operations (via vortex_mem_if.master_driver)
//   - DCR configuration (via vortex_dcr_if.master_driver)
//   - Status monitoring (via vortex_status_if.monitor)
//
// Agent Configuration:
//   - Can be ACTIVE (with driver/sequencer) or PASSIVE (monitor only)
//   - Controlled via cfg.host_agent_is_active
//
// Key Features:
//   ✓ Multi-interface coordination
//   ✓ High-level operation abstraction
//   ✓ Execution lifecycle management
//   ✓ Flexible active/passive modes
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_AGENT_SV
`define HOST_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import host_agent_pkg::*;


class host_agent extends uvm_agent;
    `uvm_component_utils(host_agent)
    
    //==========================================================================
    // Sub-Components
    //==========================================================================
    host_driver    m_driver;
    host_monitor   m_monitor;
    host_sequencer m_sequencer;
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Analysis Port (Forwarded from Monitor/Driver)
    // External components (scoreboard, coverage) connect here
    //==========================================================================
    uvm_analysis_port #(host_transaction) ap;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "host_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);

        // Get virtual interfaces and propagate to sub-components
        virtual vortex_mem_if    mem_vif;
        virtual vortex_dcr_if    dcr_vif;
        virtual vortex_status_if status_vif;        
        super.build_phase(phase);
        
        // Get configuration from config DB
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("HOST_AGENT", "No vortex_config found - creating default", UVM_MEDIUM)
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();  // ← FIXED: Initialize from RTL
        end
        
        // Propagate configuration to sub-components
        uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);
        

        
        if (uvm_config_db#(virtual vortex_mem_if)::get(this, "", "vif_mem", mem_vif)) begin
            uvm_config_db#(virtual vortex_mem_if)::set(this, "m_driver", "mem_vif", mem_vif);
        end
        
        if (uvm_config_db#(virtual vortex_dcr_if)::get(this, "", "vif_dcr", dcr_vif)) begin
            uvm_config_db#(virtual vortex_dcr_if)::set(this, "m_driver", "dcr_vif", dcr_vif);
            uvm_config_db#(virtual vortex_dcr_if)::set(this, "m_monitor", "dcr_vif", dcr_vif);
        end

        if (uvm_config_db#(virtual vortex_status_if)::get(this, "", "vif_status", status_vif)) begin
            uvm_config_db#(virtual vortex_status_if)::set(this, "m_driver", "status_vif", status_vif);
            uvm_config_db#(virtual vortex_status_if)::set(this, "m_monitor", "status_vif", status_vif);
        end
        
        // Create monitor (always present)
        m_monitor = host_monitor::type_id::create("m_monitor", this);
        
        // Create driver and sequencer if active
        if (get_is_active() == UVM_ACTIVE) begin
            if (cfg.host_agent_is_active) begin
                m_driver = host_driver::type_id::create("m_driver", this);
                m_sequencer = host_sequencer::type_id::create("m_sequencer", this);
            end else begin
                `uvm_info("HOST_AGENT", 
                    "Config set to passive, no driver/sequencer created", UVM_MEDIUM)
            end
        end
        
        // Create analysis port
        ap = new("ap", this);
    endfunction
    
    //==========================================================================
    // Connect Phase
    //==========================================================================
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect driver to sequencer if active
        if (get_is_active() == UVM_ACTIVE && m_driver != null && m_sequencer != null) begin
            m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
            
            // Connect driver analysis port to agent analysis port
            m_driver.ap.connect(ap);
        end
        
        // Connect monitor analysis port to agent analysis port
        m_monitor.ap.connect(ap);
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("HOST_AGENT", {"\n",
            "========================================\n",
            "    Host Agent Configuration\n",
            "========================================\n",
            $sformatf("  Mode:          %s\n", 
                get_is_active() == UVM_ACTIVE ? "ACTIVE" : "PASSIVE"),
            $sformatf("  Driver:        %s\n", m_driver != null ? "✓" : "✗"),
            $sformatf("  Sequencer:     %s\n", m_sequencer != null ? "✓" : "✗"),
            $sformatf("  Monitor:       %s\n", m_monitor != null ? "✓" : "✗"),
            "========================================\n",
            "  Interfaces Used:\n",
            "    - vortex_mem_if.master_driver\n",
            "    - vortex_dcr_if.master_driver\n",
            "    - vortex_status_if.monitor\n",
            "========================================"
        }, UVM_MEDIUM)
    endfunction
    
endclass : host_agent

`endif // HOST_AGENT_SV
