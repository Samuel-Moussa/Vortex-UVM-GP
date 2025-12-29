////////////////////////////////////////////////////////////////////////////////
// File: mem_sequencer.sv
// Description: Memory Agent Sequencer
//
// Standard UVM sequencer parameterized with mem_transaction.
// Manages the flow of memory transactions from sequences to the driver.
//
// No additional functionality required - the base class provides:
//   - Transaction arbitration
//   - Sequence execution management
//   - TLM ports for driver connection
//
// Usage:
//   Sequences are started on this sequencer:
//     my_seq.start(env.mem_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef MEM_SEQUENCER_SV
`define MEM_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import mem_agent_pkg::*;

class mem_sequencer extends uvm_sequencer #(mem_transaction);
    `uvm_component_utils(mem_sequencer)
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mem_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
endclass : mem_sequencer

`endif // MEM_SEQUENCER_SV
