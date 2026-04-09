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
import mem_agent_pkg::*;
import axi_agent_pkg::*;
import dcr_agent_pkg::*;
import host_agent_pkg::*;
import status_agent_pkg::*;

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
    //
    // Blocks until the DUT signals EBREAK (kernel execution finished).
    //
    // Mechanism:
    //   vortex_scoreboard.write_status() calls cfg.ebreak_event.trigger()
    //   the moment it observes ebreak_detected == 1 from the status_agent
    //   monitor.  This task waits on that event, so it unblocks at exactly
    //   the simulation time the EBREAK is seen — no polling, no fixed delay.
    //
    // Timeout:
    //   A parallel watchdog converts cfg.test_timeout_cycles to nanoseconds
    //   (assuming 10 ns/cycle = 100 MHz default) and fires uvm_error if the
    //   DUT never signals EBREAK.  This keeps the test from hanging forever
    //   while still reporting a clean failure.
    //==========================================================================
    virtual task wait_for_execution_complete();
        int unsigned timeout_ns;

        if (cfg == null) begin
            `uvm_fatal("VIRT_SEQ", "wait_for_execution_complete() called but cfg is null — did pre_body() run and find a config?")
        end

        if (cfg.ebreak_event == null) begin
            `uvm_fatal("VIRT_SEQ",
                "cfg.ebreak_event is null — was vortex_config created correctly?")
        end

        // 10 ns per cycle at 100 MHz; adjust if your CLK_PERIOD_NS differs
        timeout_ns = cfg.test_timeout_cycles * 10;

        `uvm_info("VIRT_SEQ",
            $sformatf("Waiting for EBREAK (timeout = %0d cycles / %0d ns)...",
                      cfg.test_timeout_cycles, timeout_ns),
            UVM_MEDIUM)

        fork
            // Branch 1 — wait for the ebreak event from the scoreboard
            begin
                cfg.ebreak_event.wait_trigger();
                `uvm_info("VIRT_SEQ",
                    "EBREAK event received — DUT execution complete", UVM_MEDIUM)
            end

            // Branch 2 — timeout watchdog
            begin
                #(timeout_ns * 1ns);
                `uvm_error("VIRT_SEQ", $sformatf("wait_for_execution_complete() timed out after %0d cycles (%0d ns) — DUT never signalled EBREAK", cfg.test_timeout_cycles, timeout_ns))
            end
        join_any
        disable fork;
    endtask
    
endclass : vortex_virtual_sequence

`endif // VORTEX_VIRTUAL_SEQUENCE_SV