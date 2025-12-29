////////////////////////////////////////////////////////////////////////////////
// File: dcr_sequencer.sv
// Description: DCR Agent Sequencer
//
// Standard UVM sequencer parameterized with dcr_transaction.
// Manages the flow of DCR write transactions from sequences to the driver.
//
// No additional functionality required - the base class provides:
//   - Transaction arbitration
//   - Sequence execution management
//   - TLM ports for driver connection
//
// Usage:
//   Sequences are started on this sequencer:
//     my_seq.start(env.dcr_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef DCR_SEQUENCER_SV
`define DCR_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import dcr_agent_pkg::*;

class dcr_sequencer extends uvm_sequencer #(dcr_transaction);
    `uvm_component_utils(dcr_sequencer)
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "dcr_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("DCR_SQCR", "No config found, using defaults", UVM_MEDIUM)
        end
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info("DCR_SQCR", "DCR sequencer ready", UVM_MEDIUM)
    endfunction
    
endclass : dcr_sequencer

`endif // DCR_SEQUENCER_SV
