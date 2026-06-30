////////////////////////////////////////////////////////////////////////////////
// File: status_monitor.sv
// Description: Status Agent Monitor with Execution Tracking
//
// Key Responsibilities:
//   1. Sample status signals every cycle via clocking block
//   2. Detect execution start (busy goes HIGH) — edge triggered
//   3. Detect execution completion (ebreak_detected goes HIGH) — edge triggered
//      and broadcast immediately (not waiting for next sample interval)
//   4. Track pipeline performance
//   5. Broadcast status snapshots to scoreboard
//
// Fix applied (Mar 2026):
//   - EBREAK transaction is broadcast immediately on detection, not deferred
//     to the next sample_interval tick. This prevents the spurious
//     "Execution started but did not complete" warning in check_phase when
//     the objection drops before the next periodic sample fires.
//   - detect_state_transitions() drives execution_complete event AND calls
//     ap.write() directly with an EBREAK snapshot.
//   - check_phase warning suppressed if ebreak was detected mid-interval.
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef STATUS_MONITOR_SV
`define STATUS_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import status_agent_pkg::*;

class status_monitor extends uvm_monitor;
    `uvm_component_utils(status_monitor)

    //==========================================================================
    // Virtual Interface Handle
    //==========================================================================
    virtual vortex_status_if.monitor vif;

    //==========================================================================
    // Analysis Port
    //==========================================================================
    uvm_analysis_port #(status_transaction) ap;

    //==========================================================================
    // Configuration Object
    //==========================================================================
    vortex_config cfg;

    //==========================================================================
    // Execution State Tracking
    //==========================================================================
    bit prev_busy;
    bit prev_ebreak;
    bit [31:0] prev_pc;

    time    execution_start_time;
    time    execution_end_time;
    longint execution_start_cycle;

    bit execution_started;
    bit execution_completed;

    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int  num_busy_transitions;
    int  num_idle_transitions;
    int  num_stall_cycles;
    int  total_execution_cycles;
    real peak_ipc;
    longint total_instructions;

    //==========================================================================
    // Sampling Control
    //==========================================================================
    int sample_interval;
    int sample_counter;

    //==========================================================================
    // Events
    //==========================================================================
    event execution_start;
    event execution_complete;
    event stall_detected;

    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "status_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);

        prev_busy         = 0;
        prev_ebreak       = 0;
        prev_pc           = 0;
        execution_started   = 0;
        execution_completed = 0;

        num_busy_transitions   = 0;
        num_idle_transitions   = 0;
        num_stall_cycles       = 0;
        total_execution_cycles = 0;
        peak_ipc               = 0.0;
        total_instructions     = 0;

        sample_interval = 1;
        sample_counter  = 0;
    endfunction

    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual vortex_status_if)::get(
                this, "", "vif", vif))
            `uvm_fatal("STATUS_MON", "Failed to get virtual interface")

        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("STATUS_MON", "No vortex_config found — using defaults")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end

        if (cfg != null && cfg.status_sample_interval > 0)
            sample_interval = cfg.status_sample_interval;
    endfunction

    //==========================================================================
    // Run Phase — three parallel threads
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        fork
            monitor_status();           // Periodic status broadcast
            detect_state_transitions(); // Edge detection + immediate EBREAK
            track_performance();        // IPC tracking
        join
    endtask

    //==========================================================================
    // monitor_status
    // Samples at sample_interval ticks and broadcasts to scoreboard.
    // Does NOT handle EBREAK — detect_state_transitions does that immediately.
    //==========================================================================
    virtual task monitor_status();
        status_transaction trans;

        forever begin
            @(vif.monitor_cb);

            sample_counter++;
            if (sample_counter < sample_interval) continue;
            sample_counter = 0;

            // Skip periodic sample if EBREAK just fired this cycle —
            // detect_state_transitions already sent the definitive snapshot.
            if (vif.monitor_cb.ebreak_detected && !prev_ebreak) continue;

            trans = status_transaction::type_id::create("trans");
            trans.busy            = vif.monitor_cb.busy;
            trans.ebreak_detected = vif.monitor_cb.ebreak_detected;
            trans.idle            = !vif.monitor_cb.busy;
            trans.cycle_count     = vif.monitor_cb.cycle_count;
            trans.instr_count     = vif.monitor_cb.instr_count;
            trans.pc              = vif.monitor_cb.pc;
            trans.fetch_stall     = vif.monitor_cb.fetch_stall;
            trans.memory_stall    = vif.monitor_cb.memory_stall;
            trans.sample_time     = $time;
            trans.calculate_metrics();
            ap.write(trans);
        end
    endtask

    //==========================================================================
    // detect_state_transitions
    // Edge-triggered detection of busy/ebreak transitions.
    // On EBREAK: broadcasts transaction IMMEDIATELY via ap.write() and
    // triggers the execution_complete event — no wait for next sample tick.
    //==========================================================================
    virtual task detect_state_transitions();
        real final_ipc = 0.0;

        forever begin
            @(vif.monitor_cb);

            // ---------------------------------------------------------------
            // IDLE → BUSY edge (execution starts)
            // ---------------------------------------------------------------
            if (vif.monitor_cb.busy && !prev_busy) begin
                execution_start_time  = $time;
                execution_start_cycle = vif.monitor_cb.cycle_count;
                execution_started     = 1;
                num_busy_transitions++;
                -> execution_start;

                `uvm_info("STATUS_MON", $sformatf("✓ Execution started @ cycle %0d, time %0t", vif.monitor_cb.cycle_count, $time), UVM_LOW)
            end

            // ---------------------------------------------------------------
            // BUSY → IDLE edge
            // ---------------------------------------------------------------
            if (!vif.monitor_cb.busy && prev_busy) begin
                num_idle_transitions++;
                `uvm_info("STATUS_MON", $sformatf("Core went idle @ cycle %0d", vif.monitor_cb.cycle_count), UVM_MEDIUM)
            end

            // ---------------------------------------------------------------
            // EBREAK rising edge — broadcast immediately, do not wait for
            // the next sample_interval tick.
            // ---------------------------------------------------------------
            if (vif.monitor_cb.ebreak_detected && !prev_ebreak) begin
                status_transaction ebreak_txn;

                execution_end_time     = $time;
                execution_completed    = 1;
                total_execution_cycles = int'(vif.monitor_cb.cycle_count
                                             - execution_start_cycle);
                total_instructions     = vif.monitor_cb.instr_count;

                if (total_execution_cycles > 0)
                    final_ipc = real'(total_instructions) /
                                real'(total_execution_cycles);

                // Build the definitive EBREAK snapshot and send NOW
                ebreak_txn = status_transaction::type_id::create("ebreak_txn");
                ebreak_txn.busy            = vif.monitor_cb.busy;
                ebreak_txn.ebreak_detected = 1'b1;
                ebreak_txn.idle            = !vif.monitor_cb.busy;
                ebreak_txn.cycle_count     = vif.monitor_cb.cycle_count;
                ebreak_txn.instr_count     = vif.monitor_cb.instr_count;
                ebreak_txn.pc              = vif.monitor_cb.pc;
                ebreak_txn.fetch_stall     = vif.monitor_cb.fetch_stall;
                ebreak_txn.memory_stall    = vif.monitor_cb.memory_stall;
                ebreak_txn.sample_time     = $time;
                ebreak_txn.calculate_metrics();
                ap.write(ebreak_txn);   // <— immediate, before any objection drop

                -> execution_complete;  // Signal scoreboard / base test

                `uvm_info("STATUS_MON", {"\n",
                    "========================================\n",
                    "  Program Execution Complete (EBREAK)\n",
                    "========================================\n",
                    $sformatf("  End Time:     %0t\n",  $time),
                    $sformatf("  Duration:     %0t\n",  execution_end_time - execution_start_time),
                    $sformatf("  Total Cycles: %0d\n",  total_execution_cycles),
                    $sformatf("  Total Instrs: %0d\n",  total_instructions),
                    $sformatf("  Final IPC:    %.3f\n", final_ipc),
                    "========================================"
                }, UVM_LOW)
            end

            // PC change (debug only)
            if (vif.monitor_cb.pc != prev_pc && vif.monitor_cb.pc != 0) begin
                `uvm_info("STATUS_MON", $sformatf("PC: 0x%08h → 0x%08h", prev_pc, vif.monitor_cb.pc), UVM_DEBUG)
            end

            prev_busy   = vif.monitor_cb.busy;
            prev_ebreak = vif.monitor_cb.ebreak_detected;
            prev_pc     = vif.monitor_cb.pc;
        end
    endtask

    //==========================================================================
    // track_performance
    //==========================================================================
    virtual task track_performance();
        real current_ipc;

        forever begin
            @(vif.monitor_cb);

            if (vif.monitor_cb.cycle_count > 0)
                current_ipc = real'(vif.monitor_cb.instr_count) /
                              real'(vif.monitor_cb.cycle_count);
            else
                current_ipc = 0.0;

            if (current_ipc > peak_ipc)
                peak_ipc = current_ipc;

            if (vif.monitor_cb.busy &&
                vif.monitor_cb.cycle_count > 0 &&
                (vif.monitor_cb.cycle_count % 10000 == 0))
                `uvm_info("STATUS_MON", $sformatf("Performance @ cycle %0d: instrs=%0d, IPC=%.3f", vif.monitor_cb.cycle_count, vif.monitor_cb.instr_count, current_ipc), UVM_DEBUG)
        end
    endtask

    //==========================================================================
    // Wait helpers
    //==========================================================================
    task wait_execution_start();
        if (!execution_started) @(execution_start);
    endtask

    task wait_execution_complete();
        if (!execution_completed) @(execution_complete);
    endtask

    //==========================================================================
    // Check Phase
    // Only warn "did not complete" if execution actually started.
    // If execution_completed is already set (EBREAK fired before check_phase),
    // stay silent — this is the normal PASS path.
    //==========================================================================
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        if (!execution_started)
            `uvm_warning("STATUS_MON", "Core never became busy — no execution detected")

        // Only warn if started but EBREAK was never seen.
        // Do NOT warn if execution_completed is set — that's a clean exit.
        if (execution_started && !execution_completed)
            `uvm_warning("STATUS_MON", "Execution started but did not complete (no EBREAK)")
    endfunction

    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        real avg_ipc, stall_pct;
        super.report_phase(phase);

        if (total_execution_cycles > 0) begin
            avg_ipc   = real'(total_instructions) / real'(total_execution_cycles);
            stall_pct = (real'(num_stall_cycles) / real'(total_execution_cycles))
                        * 100.0;
        end else begin
            avg_ipc   = 0.0;
            stall_pct = 0.0;
        end

        `uvm_info("STATUS_MON", {"\n",
            "========================================\n",
            "    Status Monitor Statistics\n",
            "========================================\n",
            $sformatf("  Busy Transitions:    %0d\n", num_busy_transitions),
            $sformatf("  Idle Transitions:    %0d\n", num_idle_transitions),
            $sformatf("  Execution Started:   %s\n",
                      execution_started   ? "YES" : "NO"),
            $sformatf("  Execution Completed: %s\n",
                      execution_completed ? "YES" : "NO"),
            $sformatf("  Total Cycles:        %0d\n", total_execution_cycles),
            $sformatf("  Total Instructions:  %0d\n", total_instructions),
            $sformatf("  Average IPC:         %.3f\n", avg_ipc),
            $sformatf("  Peak IPC:            %.3f\n", peak_ipc),
            $sformatf("  Stall Cycles:        %0d (%.2f%%)\n",
                      num_stall_cycles, stall_pct),
            $sformatf("  Execution Time:      %0t\n",
                      execution_completed ?
                      (execution_end_time - execution_start_time) : 0),
            "========================================"
        }, UVM_LOW)
    endfunction

endclass : status_monitor

`endif // STATUS_MONITOR_SV