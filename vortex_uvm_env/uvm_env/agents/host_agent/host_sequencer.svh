////////////////////////////////////////////////////////////////////////////////
// File: host_sequencer.sv
// Description: Host Agent Sequencer
//
// Standard UVM sequencer parameterized with host_transaction.
// Manages the flow of host-level transactions from sequences to the driver.
//
// The host sequencer coordinates high-level operations like:
//   - Program loading
//   - Kernel launching
//   - Result reading
//
// No additional functionality required - the base class provides:
//   - Transaction arbitration
//   - Sequence execution management
//   - TLM ports for driver connection
//
// Usage:
//   Sequences are started on this sequencer:
//     my_seq.start(env.host_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_SEQUENCER_SV
`define HOST_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import host_agent_pkg::*;


class host_sequencer extends uvm_sequencer #(host_transaction);
    `uvm_component_utils(host_sequencer)
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "host_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get configuration object
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("HOST_SQCR", "No config found, using defaults", UVM_MEDIUM)
        end
    endfunction
    
    //==========================================================================
    // End of Elaboration Phase
    //==========================================================================
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info("HOST_SQCR", "Host sequencer ready", UVM_MEDIUM)
    endfunction
    
endclass : host_sequencer

`endif // HOST_SEQUENCER_SV
