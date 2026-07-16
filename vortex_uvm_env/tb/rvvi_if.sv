////////////////////////////////////////////////////////////////////////////////
// File: rvvi_if.sv
// Description: Phase-A / A1(c) RVVI hand-off interface + registry.
//
//   Replaces the global lockstep_pkg package queues (D2a) with a proper
//   interface → UVM-monitor → analysis-port data path (D2b, core-v-verif
//   uvma_rvvi style):
//
//     probe (module domain, bound per VX_commit / VX_lsu_slice)
//       └─ instantiates ONE rvvi_if, push()es dut_retire_s records into it,
//          and registers the instance in rvvi_registry_pkg at time 0
//     rvvi_monitor (class domain)
//       └─ discovers every registered vif after #1, drains each queue on
//          @(posedge vif.clk) + a final extract_phase sweep, publishes
//          rvvi_txn on its uvm_analysis_port
//     lockstep_scoreboard
//       └─ subscribes via uvm_analysis_imp, routes by rec.kind
//
//   TRANSACTION-LEVEL by design (records, not RVVI-TRACE pins): the record
//   struct carries widened scalars + a dynamic data[] (lockstep_pkg), so the
//   interface needs NO parameters — one `virtual rvvi_if` type is valid for
//   ANY NUM_CLUSTERS/NUM_CORES/NUM_WARPS/NUM_THREADS/SIMD_WIDTH/ISSUE_WIDTH.
//   A signal-level RVVI-TRACE upgrade (the ENH-1 step-follower era) would add
//   a `clocking mon_cb @(posedge clk); default input #1step;` here and have
//   the monitor sample pins through it; with record hand-off there is no
//   cross-domain signal sampling, so no clocking block is required.
//
//   The internal queue is PERSISTENT: if the monitor's drain thread loses the
//   scheduling race on a given edge (or is killed at end of run_phase), the
//   records simply wait for the next edge / the extract_phase sweep. Nothing
//   is ever dropped. Pattern proven on Questa 2021.2 (bound-module interface
//   instance, package virtual-if registry, class-domain drain via vif).
//
// Author: Vortex UVM (Samuel) — Phase A1(c)
////////////////////////////////////////////////////////////////////////////////

`ifndef RVVI_IF_SV
`define RVVI_IF_SV

interface rvvi_if (input wire clk);
    import lockstep_pkg::*;

    // Probe-filled record queue (one entry per captured commit/load beat).
    dut_retire_s q[$];

    // Probe side: push one captured record (kind set by the probe).
    function automatic void push(dut_retire_s r);
        q.push_back(r);
    endfunction

    // Monitor side: drain accessors.
    function automatic int size();
        return q.size();
    endfunction

    function automatic dut_retire_s pop();
        return q.pop_front();
    endfunction

endinterface : rvvi_if

// Registry of every rvvi_if instance in the design. Probes self-register at
// time 0 (initial block); the monitor snapshots the list after #1, when all
// time-0 registrations are guaranteed complete. Setup-time-only state (a list
// of interface handles) — the DATA path is the interfaces + analysis port,
// not this package. Compiled after rvvi_if (it references the virtual type),
// before the probes (they call rvvi_register).
package rvvi_registry_pkg;

    virtual rvvi_if vifs[$];

    function automatic void rvvi_register(virtual rvvi_if v);
        vifs.push_back(v);
    endfunction

endpackage : rvvi_registry_pkg

`endif // RVVI_IF_SV
