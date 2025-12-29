////////////////////////////////////////////////////////////////////////////////
// File: vortex_virtual_sequence.sv
// Description: Base Class for Virtual Sequences
//
// Virtual sequences coordinate transactions across multiple agents using
// the virtual sequencer. This base class provides:
//   - Access to all agent sequencers via p_sequencer
//   - Common configuration access
//   - Helper methods for multi-agent coordination
//
// Usage:
//   class my_virtual_seq extends vortex_virtual_sequence;
//     task body();
//       // Access any sequencer
//       my_mem_seq.start(p_sequencer.mem_sequencer);
//       my_dcr_seq.start(p_sequencer.dcr_sequencer);
//     endtask
//   endclass
//
// Example Multi-Agent Sequence:
//   1. Load program via host_sequencer
//   2. Configure DCRs via dcr_sequencer
//   3. Launch kernel via host_sequencer
//   4. Wait for completion via status monitoring
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_VIRTUAL_SEQUENCE_SV
`define VORTEX_VIRTUAL_SEQUENCE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import vortex_env_pkg::*;

class vortex_virtual_sequence extends uvm_sequence;
    `uvm_object_utils(vortex_virtual_sequence)
    `uvm_declare_p_sequencer(vortex_virtual_sequencer)
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "vortex_virtual_sequence");
        super.new(name);
    endfunction
    
    //==========================================================================
    // Pre-Body
    // Get configuration before sequence execution
    //==========================================================================
    virtual task pre_body();
        super.pre_body();
        
        // Get configuration from sequencer
        if (p_sequencer != null) begin
            cfg = p_sequencer.cfg;
        end
        
        if (cfg == null) begin
            `uvm_warning("VIRT_SEQ", "No configuration found")
        end
    endtask
    
    //==========================================================================
    // Body (to be overridden by derived classes)
    //==========================================================================
    virtual task body();
        `uvm_info("VIRT_SEQ", "Executing base virtual sequence", UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Helper Method: Wait for Execution Complete
    // Waits for status_agent to detect EBREAK
    //==========================================================================
    virtual task wait_for_execution_complete();
        // TODO: Implement via status_agent event or callback
        `uvm_info("VIRT_SEQ", "Waiting for execution to complete...", UVM_MEDIUM)
        
        // Placeholder: In real implementation, wait for status_agent event
        #10us;
        
        `uvm_info("VIRT_SEQ", "Execution complete", UVM_MEDIUM)
    endtask
    
endclass : vortex_virtual_sequence

`endif // VORTEX_VIRTUAL_SEQUENCE_SV
