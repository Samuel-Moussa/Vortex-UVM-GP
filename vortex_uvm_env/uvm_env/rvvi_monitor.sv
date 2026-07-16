////////////////////////////////////////////////////////////////////////////////
// File: rvvi_monitor.sv
// Description: Phase-A / A1(c) RVVI monitor (core-v-verif uvma_rvvi style).
//
//   Discovers every rvvi_if instance the bound probes registered in
//   rvvi_registry_pkg (snapshot after #1 — all time-0 initial-block
//   registrations are complete by then), then drains each interface's record
//   queue and publishes one rvvi_txn per record on the analysis port. The
//   lockstep_scoreboard subscribes and routes on rec.kind.
//
//   DRAIN GUARANTEE: the vif queues are persistent. The per-vif run_phase
//   threads drain on @(posedge vif.clk) — losing a same-edge scheduling race
//   against a probe push only delays that record to the next edge. When
//   run_phase ends these threads die, so extract_phase does a final sweep;
//   UVM runs ALL extract_phases before ANY check_phase, so the scoreboard
//   always sees the complete stream. ap.write() from a function phase is
//   legal (write is a function).
//
//   STREAMING: records flow during run_phase, not end-of-run — this is the
//   enabler for the ENH-1 single-pass step-follower rework.
//
//   Created only when cfg.enable_lockstep (+LOCKSTEP); a default run has no
//   monitor and the probes never push → byte-identical.
//
// Author: Vortex UVM (Samuel) — Phase A1(c)
////////////////////////////////////////////////////////////////////////////////

`ifndef RVVI_MONITOR_SV
`define RVVI_MONITOR_SV

class rvvi_monitor extends uvm_monitor;
    `uvm_component_utils(rvvi_monitor)

    uvm_analysis_port #(rvvi_txn) ap;

    // Snapshot of the registry (taken once, after #1).
    local virtual rvvi_if m_vifs[$];

    // Liveness/debug tallies for the end-of-run report.
    local int unsigned n_published;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
    endfunction

    // Pop everything currently queued in one vif and publish it.
    function void drain(virtual rvvi_if v);
        while (v.size() > 0) begin
            rvvi_txn t = rvvi_txn::type_id::create("rvvi_txn");
            t.rec = v.pop();
            ap.write(t);
            n_published++;
        end
    endfunction

    task run_phase(uvm_phase phase);
        #1;  // all probe time-0 registrations are complete past t=0
        m_vifs = rvvi_registry_pkg::vifs;
        `uvm_info("RVVI_MON", $sformatf(
            "discovered %0d rvvi_if instance(s) (commit + LSU probes)", m_vifs.size()), UVM_LOW)
        if (m_vifs.size() == 0)
            `uvm_warning("RVVI_MON",
                "no rvvi_if registered — probes not bound? lockstep will see no DUT records")
        foreach (m_vifs[i]) begin
            automatic virtual rvvi_if v = m_vifs[i];
            fork
                forever begin
                    @(posedge v.clk);
                    drain(v);
                end
            join_none
        end
    endtask

    // Final sweep: run_phase threads are killed at phase end; anything still
    // queued (last-edge race, post-objection pushes) is flushed here, before
    // the scoreboard's check_phase compare.
    function void extract_phase(uvm_phase phase);
        super.extract_phase(phase);
        foreach (m_vifs[i]) drain(m_vifs[i]);
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("RVVI_MON", $sformatf(
            "published %0d rvvi_txn record(s) from %0d interface(s)",
            n_published, m_vifs.size()), UVM_LOW)
    endfunction

endclass : rvvi_monitor

`endif // RVVI_MONITOR_SV
