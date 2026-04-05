////////////////////////////////////////////////////////////////////////////////
// File: vortex_base_sequence.sv
// Description: Base sequence class for all single-agent Vortex sequences.
//
// This is the base for sequences that run on a SINGLE agent sequencer —
// i.e. sequences started with seq.start(some_sequencer).
//
// For multi-agent coordination across several sequencers, extend
// vortex_virtual_sequence instead, which uses p_sequencer to reach all
// agent sequencers through the virtual sequencer.
//
// ============================================================================
// HOW UVM SEQUENCES GET THEIR SEQUENCER
// ============================================================================
// When a sequence is started with seq.start(sqr), UVM binds the sequencer
// handle internally. The sequence accesses it via:
//   - m_sequencer  — the sequencer this sequence is running on
//   - p_sequencer  — typed handle (only if uvm_declare_p_sequencer used)
//
// start_item(trans) and finish_item(trans) use m_sequencer automatically.
// There is NO need to fetch sequencer handles from uvm_config_db.
//
// FIX (March 2026):
//   The original body() called:
//     uvm_config_db#(mem_sequencer)::get(null, get_full_name(), ...)
//   for all four sequencer types. This was wrong because:
//     1. 'null' context + sequence get_full_name() never matches the
//        component hierarchy paths used when vortex_env registers sequencers.
//     2. Non-virtual sequences only run on ONE sequencer — they should not
//        hold handles to other agents' sequencers.
//     3. All four handles silently remained null, causing start_item() in
//        any derived class to crash at runtime with a null pointer dereference.
//
//   Fix: body() is now an empty virtual task. The broken config_db lookups
//   are removed entirely. Derived classes override body() and use
//   start_item()/finish_item() — sequencer binding happens automatically
//   via seq.start(sequencer).
//
//   Config is now fetched correctly in pre_body() using m_sequencer as
//   the context — m_sequencer is the component that owns the config entry.
//
// ============================================================================
// USAGE
// ============================================================================
//   class my_mem_seq extends vortex_base_sequence;
//     `uvm_object_utils(my_mem_seq)
//     function new(string name = "my_mem_seq");
//       super.new(name);
//     endfunction
//     virtual task body();
//       mem_transaction tr = mem_transaction::type_id::create("tr");
//       start_item(tr);   // uses m_sequencer set by seq.start(mem_sqr)
//       assert(tr.randomize());
//       finish_item(tr);
//     endtask
//   endclass
//
//   // Starting it on the mem agent sequencer:
//   my_mem_seq seq = my_mem_seq::type_id::create("seq");
//   seq.start(env.m_mem_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_BASE_SEQUENCE_SV
`define VORTEX_BASE_SEQUENCE_SV

class vortex_base_sequence extends uvm_sequence;

    `uvm_object_utils(vortex_base_sequence)

    //==========================================================================
    // Configuration handle
    // Populated in pre_body() from the sequencer's config_db entry so that
    // derived sequences can read test parameters without a separate lookup.
    //==========================================================================
    vortex_config cfg;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "vortex_base_sequence");
        super.new(name);
    endfunction

    //==========================================================================
    // Pre-Body
    // Retrieves vortex_config from the sequencer this sequence runs on.
    // The correct context for config_db::get() inside a sequence is the
    // sequencer itself (m_sequencer), not null + get_full_name().
    //==========================================================================
    virtual task pre_body();
        super.pre_body();
        // m_sequencer is set by UVM before pre_body() runs.
        // It is the only correct context for config_db::get() in a sequence
        // because vortex_env registers cfg on sequencer components, not on null.
        if (m_sequencer != null) begin
            if (!uvm_config_db#(vortex_config)::get(m_sequencer, "", "cfg", cfg))
                `uvm_warning("BASE_SEQ",
                    "vortex_config not found on sequencer — cfg will be null")
        end else begin
            `uvm_warning("BASE_SEQ",
                "m_sequencer is null in pre_body() — was sequence started with seq.start(sqr)?")
        end
    endtask

    //==========================================================================
    // Body — override in derived classes.
    // Use start_item()/finish_item() directly; m_sequencer is already bound
    // by the time body() runs.  Do NOT add config_db sequencer lookups here.
    //==========================================================================
    virtual task body();
        // Intentionally empty — derived sequences override this.
        `uvm_info("BASE_SEQ", "vortex_base_sequence body() called directly — derive a class and override body()", UVM_MEDIUM)
    endtask

endclass : vortex_base_sequence

`endif // VORTEX_BASE_SEQUENCE_SV