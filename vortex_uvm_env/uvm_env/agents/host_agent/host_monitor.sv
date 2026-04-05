////////////////////////////////////////////////////////////////////////////////
// File: host_monitor.sv
// Description: Host Agent Monitor with Clocking Blocks
//
// This monitor observes high-level operations by tracking:
//   - DCR writes (via dcr_vif.monitor_cb)
//   - Status changes (via status_vif.monitor_cb)
//   - Kernel execution events
//
// Key Features:
//   ✓ Passive observation using monitor modports
//   ✓ Execution lifecycle tracking
//   ✓ Performance metrics calculation
//   ✓ Event generation for synchronization
//
// FIX (March 2026) — TB_TOP DCR bypass path:
//   Smoke and functional tests launch via TB_TOP's DCR initial block,
//   bypassing the host driver entirely.  In this path the DUT starts
//   executing as soon as reset deasserts, so busy=1 may be seen before
//   UVM's run_phase begins.  The original monitor_kernel_execution() only
//   detected the 0→1 rising edge, so it never set kernel_running=1 and
//   the subsequent busy=0 completion event was also missed.
//
//   Fix: sample busy at run_phase entry and synthesise a launch event
//   immediately if already high.  The falling edge (busy 1→0) and
//   ebreak_detected are both monitored for completion, regardless of
//   whether the launch edge was explicitly observed.
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_MONITOR_SV
`define HOST_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import host_agent_pkg::*;


class host_monitor extends uvm_monitor;
    `uvm_component_utils(host_monitor)
    
    //==========================================================================
    // Virtual Interfaces (with monitor modports)
    //==========================================================================
    virtual vortex_dcr_if.monitor    dcr_vif;
    virtual vortex_status_if.monitor status_vif;
    
    //==========================================================================
    // Analysis Port
    //==========================================================================
    uvm_analysis_port #(host_transaction) ap;
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Internal State Tracking
    //==========================================================================
    bit [31:0] last_startup_addr;
    bit        kernel_running;
    time       kernel_start_time;
    longint    kernel_start_cycle;
    
    //==========================================================================
    // Statistics
    //==========================================================================
    int num_dcr_writes;
    int num_kernel_launches;
    int num_kernel_completions;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "host_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
        kernel_running = 0;
        num_dcr_writes = 0;
        num_kernel_launches = 0;
        num_kernel_completions = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get DCR interface
        if (!uvm_config_db#(virtual vortex_dcr_if)::get(this, "", "dcr_vif", dcr_vif)) begin
            `uvm_fatal("HOST_MON", "Failed to get dcr_vif from config DB")
        end
        
        // Get status interface
        if (!uvm_config_db#(virtual vortex_status_if)::get(this, "", "status_vif", status_vif)) begin
            `uvm_fatal("HOST_MON", "Failed to get status_vif from config DB")
        end
        
        // Get configuration object
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("HOST_MON", "No vortex_config found")
        end
    endfunction
    
    //==========================================================================
    // Run Phase
    // Fork parallel monitoring tasks
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        fork
            monitor_dcr_writes();
            monitor_kernel_execution();
            monitor_performance();
        join
    endtask
    
    //==========================================================================
    // Monitor DCR Writes
    // Observes DCR configuration writes
    //==========================================================================
    virtual task monitor_dcr_writes();
        host_transaction trans;
        
        forever begin
            @(dcr_vif.monitor_cb);
            
            if (dcr_vif.monitor_cb.wr_valid) begin
                trans = host_transaction::type_id::create("dcr_trans");
                trans.op_type = host_transaction::HOST_CONFIGURE_DCR;
                trans.dcr_address = dcr_vif.monitor_cb.wr_addr;
                trans.dcr_data = dcr_vif.monitor_cb.wr_data;
                
                `uvm_info("HOST_MON", $sformatf("DCR Write: [0x%08h] = 0x%08h",
                    trans.dcr_address, trans.dcr_data), UVM_HIGH)
                
                // Track startup address configuration
                if (trans.dcr_address == VX_DCR_BASE_STARTUP_ADDR0) begin
                    last_startup_addr = trans.dcr_data;
                    `uvm_info("HOST_MON", $sformatf("Startup address set to 0x%08h",
                        last_startup_addr), UVM_MEDIUM)
                end
                
                num_dcr_writes++;
                ap.write(trans);
            end
        end
    endtask
    
    //==========================================================================
    // Monitor Kernel Execution
    // Detects kernel start and completion via busy signal edge detection.
    //
    // FIX (March 2026): TB_TOP DCR flow bypasses the host driver entirely.
    // The DUT starts executing as soon as reset deasserts — busy may already
    // be HIGH before UVM's run_phase begins, so the 0→1 edge is invisible.
    //
    // Solution: treat busy=1 at ANY point as a launch event when
    // kernel_running==0, including if it was already high at startup.
    // Completion is detected on busy=0 OR ebreak_detected, regardless of
    // whether the explicit launch edge was seen.  This makes the monitor
    // correct for both the host-driver path and the TB_TOP DCR path.
    //==========================================================================
    virtual task monitor_kernel_execution();
        host_transaction trans;
        longint elapsed_cycles;
        real final_ipc;
        bit prev_busy;

        // Sample initial busy state — if already high at run_phase start,
        // synthesise a launch event immediately so completion is tracked.
        @(status_vif.monitor_cb);
        prev_busy = status_vif.monitor_cb.busy;

        if (prev_busy && !kernel_running) begin
            kernel_running     = 1;
            kernel_start_time  = $time;
            kernel_start_cycle = status_vif.monitor_cb.cycle_count;

            trans = host_transaction::type_id::create("launch_trans_init");
            trans.op_type        = host_transaction::HOST_LAUNCH_KERNEL;
            trans.startup_address = last_startup_addr;
            trans.start_time     = $time;
            num_kernel_launches++;

            `uvm_info("HOST_MON",
                $sformatf("Kernel already running at run_phase start (busy=1 @ cycle %0d) — TB_TOP DCR flow detected",
                          kernel_start_cycle), UVM_LOW)
            ap.write(trans);
        end

        forever begin
            @(status_vif.monitor_cb);

            // ----------------------------------------------------------------
            // Launch detection: busy 0→1 rising edge
            // Covers the normal host-driver path where busy rises during sim.
            // ----------------------------------------------------------------
            if (status_vif.monitor_cb.busy && !prev_busy && !kernel_running) begin
                kernel_running     = 1;
                kernel_start_time  = $time;
                kernel_start_cycle = status_vif.monitor_cb.cycle_count;

                trans = host_transaction::type_id::create("launch_trans");
                trans.op_type         = host_transaction::HOST_LAUNCH_KERNEL;
                trans.startup_address = last_startup_addr;
                trans.start_time      = $time;
                num_kernel_launches++;

                `uvm_info("HOST_MON", $sformatf(
                    "Kernel execution started at time %0t, cycle %0d",
                    $time, kernel_start_cycle), UVM_LOW)
                ap.write(trans);
            end

            // ----------------------------------------------------------------
            // Completion detection: busy 1→0 falling edge OR ebreak_detected.
            //
            // If kernel_running was never set (e.g. busy was already 0 before
            // run_phase and never went high), skip — nothing to complete.
            //
            // ebreak_detected in TB_TOP is only asserted AFTER busy=0 AND
            // AXI channels idle, so the busy=0 condition fires first in
            // practice.  Checking both handles any ordering edge cases.
            // ----------------------------------------------------------------
            if (kernel_running &&
                (!status_vif.monitor_cb.busy || status_vif.monitor_cb.ebreak_detected)) begin

                kernel_running = 0;

                trans = host_transaction::type_id::create("done_trans");
                trans.op_type       = host_transaction::HOST_WAIT_DONE;
                trans.completion_flag = 1;
                trans.start_time    = kernel_start_time;
                trans.end_time      = $time;

                elapsed_cycles = status_vif.monitor_cb.cycle_count - kernel_start_cycle;

                if (elapsed_cycles > 0)
                    final_ipc = real'(status_vif.monitor_cb.instr_count) / real'(elapsed_cycles);
                else
                    final_ipc = 0.0;

                num_kernel_completions++;

                `uvm_info("HOST_MON", $sformatf(
                    "Kernel execution completed at time %0t  cycles=%0d  instrs=%0d  IPC=%.3f",
                    $time, elapsed_cycles,
                    status_vif.monitor_cb.instr_count, final_ipc), UVM_LOW)

                ap.write(trans);
            end

            prev_busy = status_vif.monitor_cb.busy;
        end
    endtask
    
    //==========================================================================
    // Monitor Performance
    // Periodic performance reporting
    //==========================================================================
    virtual task monitor_performance();
        bit prev_busy;
        real current_ipc;
        
        prev_busy = 0;
        
        forever begin
            @(status_vif.monitor_cb);
            
            // Detect busy state changes
            if (status_vif.monitor_cb.busy != prev_busy) begin
                `uvm_info("HOST_MON", $sformatf("Busy signal changed: %b → %b at cycle %0d",
                    prev_busy, status_vif.monitor_cb.busy,
                    status_vif.monitor_cb.cycle_count), UVM_HIGH)
                prev_busy = status_vif.monitor_cb.busy;
            end
            
            // Periodic performance updates (every 10000 cycles)
            if (status_vif.monitor_cb.busy &&
                (status_vif.monitor_cb.cycle_count % 10000 == 0)) begin
                
                // Calculate current IPC
                if (status_vif.monitor_cb.cycle_count > 0) begin
                    current_ipc = real'(status_vif.monitor_cb.instr_count) / 
                                  real'(status_vif.monitor_cb.cycle_count);
                end else begin
                    current_ipc = 0.0;
                end
                
                // `uvm_info("HOST_MON", $sformatf(
                //     "Performance Update @ cycle %0d:\n" +
                //     "  Instructions: %0d\n" +
                //     "  IPC:          %.3f\n" +
                //     "  Cache Misses: %0d",
                //     status_vif.monitor_cb.cycle_count,
                //     status_vif.monitor_cb.instr_count,
                //     current_ipc,
                //     status_vif.monitor_cb.cache_miss_count), UVM_DEBUG)
                `uvm_info("HOST_MON", $sformatf(
    "Performance: cycles=%0d, instrs=%0d, IPC=%.3f",
    status_vif.monitor_cb.cycle_count,
    status_vif.monitor_cb.instr_count,
    current_ipc), UVM_DEBUG)

            end
        end
    endtask
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("HOST_MON", {"\n",
            "========================================\n",
            "    Host Monitor Statistics\n",
            "========================================\n",
            $sformatf("  DCR Writes:        %0d\n", num_dcr_writes),
            $sformatf("  Kernel Launches:   %0d\n", num_kernel_launches),
            $sformatf("  Kernel Completions:%0d\n", num_kernel_completions),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : host_monitor

`endif // HOST_MONITOR_SV