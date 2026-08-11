////////////////////////////////////////////////////////////////////////////////
// File: axi_sequencer.sv
// Description: AXI4 UVM Sequencer
//
// The sequencer is a simple parameterized UVM sequencer that manages
// the flow of AXI transactions from sequences to the driver.
//
// It uses the standard UVM sequencer base class with no additional
// functionality required. All intelligence is in sequences and driver.
//
// Usage:
//   Sequences are run on this sequencer via:
//     sequence.start(env.axi_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_SEQUENCER_SV
`define AXI_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import axi_agent_pkg::*;

class axi_sequencer extends uvm_sequencer #(axi_transaction);
    `uvm_component_utils(axi_sequencer)
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
endclass : axi_sequencer

`endif // AXI_SEQUENCER_SV
