////////////////////////////////////////////////////////////////////////////////
// File: vortex_virtual_sequencer.sv
// Description: Virtual Sequencer for Multi-Agent Coordination
//
// The virtual sequencer provides a centralized access point to all agent
// sequencers, enabling complex multi-agent sequences that coordinate
// transactions across multiple interfaces.
//
// Agent Sequencer References:
//   - mem_sequencer   (Custom memory interface)
//   - axi_sequencer   (AXI4 interface) ✓ ACTIVE
//   - dcr_sequencer   (Device Configuration Registers)
//   - host_sequencer  (High-level host operations)
//
// Usage in Virtual Sequences:
//   class my_virtual_seq extends vortex_virtual_sequence;
//     task body();
//       // Access any sequencer
//       my_mem_seq.start(p_sequencer.mem_sequencer);
//       my_dcr_seq.start(p_sequencer.dcr_sequencer);
//     endtask
//   endclass
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_VIRTUAL_SEQUENCER_SV
`define VORTEX_VIRTUAL_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;

// Import agent packages to get sequencer types
import mem_agent_pkg::*;
import axi_agent_pkg::*;
import dcr_agent_pkg::*;
import host_agent_pkg::*;

class vortex_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(vortex_virtual_sequencer)
    
    //==========================================================================
    // Agent Sequencer Handles
    // These provide access to individual agent sequencers
    //==========================================================================
    mem_sequencer  m_mem_sequencer;   // Custom memory interface
    axi_sequencer  m_axi_sequencer;   // AXI4 interface (ACTIVE)
    dcr_sequencer  m_dcr_sequencer;   // DCR configuration
    host_sequencer m_host_sequencer;  // Host operations
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "vortex_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get configuration
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("VIRT_SQCR", "No vortex_config found", UVM_MEDIUM)
        end
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    // Verify all sequencer handles are connected
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        
        `uvm_info("VIRT_SQCR", {"\n",
            "========================================\n",
            "  Virtual Sequencer Configuration\n",
            "========================================\n",
            $sformatf("  mem_sequencer:  %s\n", m_mem_sequencer != null ? "✓" : "✗"),
            $sformatf("  axi_sequencer:  %s\n", m_axi_sequencer != null ? "✓" : "✗"),
            $sformatf("  dcr_sequencer:  %s\n", m_dcr_sequencer != null ? "✓" : "✗"),
            $sformatf("  host_sequencer: %s\n", m_host_sequencer != null ? "✓" : "✗"),
            "========================================"
        }, UVM_MEDIUM)
        
        // Warn about missing sequencers
        if (m_mem_sequencer == null)
            `uvm_warning("VIRT_SQCR", "mem_sequencer not connected")
        if (m_axi_sequencer == null && cfg.axi_agent_enable)
            `uvm_warning("VIRT_SQCR", "axi_sequencer not connected but AXI agent is enabled")
        if (m_dcr_sequencer == null)
            `uvm_warning("VIRT_SQCR", "dcr_sequencer not connected")
        if (m_host_sequencer == null)
            `uvm_warning("VIRT_SQCR", "host_sequencer not connected")
    endfunction
    
endclass : vortex_virtual_sequencer

`endif // VORTEX_VIRTUAL_SEQUENCER_SV
