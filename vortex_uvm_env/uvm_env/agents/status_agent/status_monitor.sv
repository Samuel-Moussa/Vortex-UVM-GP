////////////////////////////////////////////////////////////////////////////////
// File: status_monitor.sv
// Description: Status Agent Monitor with Execution Tracking
//
// This monitor passively observes the Vortex GPU's status interface to track
// execution progress, performance metrics, and detect program completion.
//
// Key Responsibilities:
//   1. Sample status signals periodically
//   2. Detect execution start (busy goes HIGH)
//   3. Detect execution completion (ebreak_detected goes HIGH)
//   4. Track pipeline stalls and performance
//   5. Broadcast status snapshots to scoreboard
//
// **Critical for Option A (Final State Comparison)**:
//   - Triggers execution_complete event when EBREAK is detected
//   - Scoreboard waits for this event to compare RTL vs simx memory
//   - Provides execution statistics for test reporting
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
    // Uses monitor modport with clocking block for passive observation
    //==========================================================================
    virtual vortex_status_if.monitor vif;
    
    //==========================================================================
    // Analysis Port
    // Broadcasts status snapshots to scoreboard
    //==========================================================================
    uvm_analysis_port #(status_transaction) ap;
    
    //==========================================================================
    // Configuration Object
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Execution State Tracking
    //==========================================================================
    bit prev_busy;               // Previous busy state (for edge detection)
    bit prev_ebreak;             // Previous ebreak state
    bit [31:0] prev_pc;          // Previous PC value
    
    time execution_start_time;   // Simulation time when execution started
    time execution_end_time;     // Simulation time when execution completed
    longint execution_start_cycle; // Cycle count when execution started
    
    bit execution_started;       // Flag: execution has started
    bit execution_completed;     // Flag: execution has completed (EBREAK)
    
    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int num_busy_transitions;    // Count of idle→busy transitions
    int num_idle_transitions;    // Count of busy→idle transitions
    int num_stall_cycles;        // Total cycles with any stall condition
    int total_execution_cycles;  // Total cycles from start to EBREAK
    
    real peak_ipc;               // Maximum IPC observed (CORRECTED: was longint)
    longint total_instructions;  // Total instructions executed
    
    //==========================================================================
    // Sampling Control
    //==========================================================================
    int sample_interval;         // Sample every N cycles (1 = every cycle)
    int sample_counter;          // Counter for sampling
    
    //==========================================================================
    // Events
    // Other components can wait on these events
    //==========================================================================
    event execution_start;       // Triggered when busy goes HIGH
    event execution_complete;    // Triggered when EBREAK detected
    event stall_detected;        // Triggered when any stall occurs
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "status_monitor", uvm_component parent = null);
        super.new(name, parent);
        
        // Create analysis port
        ap = new("ap", this);
        
        // Initialize state tracking
        prev_busy = 0;
        prev_ebreak = 0;
        prev_pc = 0;
        execution_started = 0;
        execution_completed = 0;
        
        // Initialize statistics
        num_busy_transitions = 0;
        num_idle_transitions = 0;
        num_stall_cycles = 0;
        total_execution_cycles = 0;
        peak_ipc = 0.0;  // CORRECTED: Initialize as real
        
        // Sampling defaults
        sample_interval = 1;  // Sample every cycle by default
        sample_counter = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface from config DB
        if (!uvm_config_db#(virtual vortex_status_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("STATUS_MON", "Failed to get virtual interface from config DB")
        end
        
        // Get configuration object
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("STATUS_MON", "No vortex_config found - using defaults")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
        
        // Configure sampling interval from config
        if (cfg != null && cfg.status_sample_interval > 0) begin
            sample_interval = cfg.status_sample_interval;
        end
    endfunction
    
    //==========================================================================
    // Run Phase
    // Fork multiple parallel monitoring tasks
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        fork
            monitor_status();           // Sample status and broadcast
            detect_state_transitions(); // Track busy/idle/ebreak edges
            track_performance();        // Monitor IPC and stalls
        join
    endtask
    
    //==========================================================================
    // Monitor Status
    // Periodically sample status interface and broadcast transactions
    //==========================================================================
    // virtual task monitor_status();
    //     status_transaction trans;
        
    //     forever begin
    //         @(vif.monitor_cb);
            
    //         // Sample at configured interval
    //         sample_counter++;
    //         if (sample_counter >= sample_interval) begin
    //             sample_counter = 0;
                
    //             // Create new status snapshot
    //             trans = status_transaction::type_id::create("trans");
                
    //             // Capture all status fields from clocking block
    //             trans.busy             = vif.monitor_cb.busy;
    //             trans.ebreak_detected  = vif.monitor_cb.ebreak_detected;
    //             trans.idle             = !vif.monitor_cb.busy;
    //             trans.pc               = vif.monitor_cb.pc;
    //             trans.next_pc          = vif.monitor_cb.next_pc;
    //             trans.pc_valid         = vif.monitor_cb.pc_valid;
    //             trans.fetch_stall      = vif.monitor_cb.fetch_stall;
    //             trans.decode_stall     = vif.monitor_cb.decode_stall;
    //             trans.issue_stall      = vif.monitor_cb.issue_stall;
    //             trans.execute_stall    = vif.monitor_cb.execute_stall;
    //             trans.commit_stall     = vif.monitor_cb.commit_stall;
    //             trans.memory_stall     = vif.monitor_cb.memory_stall;
    //             trans.active_warps     = vif.monitor_cb.active_warps;
    //             trans.active_threads   = vif.monitor_cb.active_threads;
    //             trans.warp_id          = vif.monitor_cb.warp_id;
    //             trans.thread_id        = vif.monitor_cb.thread_id;
    //             trans.cycle_count      = vif.monitor_cb.cycle_count;
    //             trans.instr_count      = vif.monitor_cb.instr_count;
    //             trans.load_count       = vif.monitor_cb.load_count;
    //             trans.store_count      = vif.monitor_cb.store_count;
    //             trans.branch_count     = vif.monitor_cb.branch_count;
    //             trans.cache_miss_count = vif.monitor_cb.cache_miss_count;
    //             trans.sample_time      = $time;
                
    //             // Calculate derived metrics
    //             trans.calculate_metrics();
                
    //             // Update stall counter
    //             if (trans.is_stalled()) 
    //                 num_stall_cycles++;
                
    //             // Broadcast to scoreboard
    //             ap.write(trans);
    //         end
    //     end
    // endtask


    virtual task monitor_status();
    status_transaction trans;
    
    forever begin
        @(vif.monitor_cb);
        
        // Sample at configured interval
        sample_counter++;
        if (sample_counter >= sample_interval) begin
            sample_counter = 0;
            
            // Create new status snapshot
            trans = status_transaction::type_id::create("trans");
            
            // Sample ONLY available signals from interface
            trans.busy = vif.monitor_cb.busy;
            trans.ebreak_detected = vif.monitor_cb.ebreak_detected;
            trans.idle = !vif.monitor_cb.busy;
            trans.cycle_count = vif.monitor_cb.cycle_count;
            trans.instr_count = vif.monitor_cb.instr_count;
            trans.pc = vif.monitor_cb.pc;  // TB-tracked
            
            trans.sample_time = $time;
            
            // Calculate derived metrics
            trans.calculate_metrics();
            
            // Broadcast to scoreboard
            ap.write(trans);
        end
    end
endtask

    
    //==========================================================================
    // Detect State Transitions
    // Monitor busy, ebreak, and PC transitions
    //==========================================================================
    virtual task detect_state_transitions();

        real final_ipc = 0.0;
                
        forever begin
            @(vif.monitor_cb);
            
            // IDLE → BUSY transition (execution starts)
            if (vif.monitor_cb.busy && !prev_busy) begin
                execution_start_time = $time;
                execution_start_cycle = vif.monitor_cb.cycle_count;
                execution_started = 1;
                num_busy_transitions++;
                
                -> execution_start;  // Trigger event
                
                `uvm_info("STATUS_MON", $sformatf(
                    "✓ Execution started @ cycle %0d, time %0t",
                    vif.monitor_cb.cycle_count, $time), UVM_LOW)
            end
            
            // BUSY → IDLE transition
            if (!vif.monitor_cb.busy && prev_busy) begin
                num_idle_transitions++;
                
                `uvm_info("STATUS_MON", $sformatf(
                    "Core went idle @ cycle %0d",
                    vif.monitor_cb.cycle_count), UVM_MEDIUM)
            end
            
            // EBREAK detection (program completion)
            if (vif.monitor_cb.ebreak_detected && !prev_ebreak) begin
                execution_end_time = $time;
                execution_completed = 1;
                total_execution_cycles = vif.monitor_cb.cycle_count - execution_start_cycle;
                total_instructions = vif.monitor_cb.instr_count;
                
                -> execution_complete;  // Trigger event (CRITICAL for Option A)
                
                // Calculate final IPC

                if (total_execution_cycles > 0) begin
                    final_ipc = real'(total_instructions) / real'(total_execution_cycles);
                end
                
                `uvm_info("STATUS_MON", {"\n",
                    "========================================\n",
                    "  Program Execution Complete (EBREAK)\n",
                    "========================================\n",
                    $sformatf("  End Time:       %0t\n", $time),
                    $sformatf("  Duration:       %0t\n", execution_end_time - execution_start_time),
                    $sformatf("  Total Cycles:   %0d\n", total_execution_cycles),
                    $sformatf("  Total Instrs:   %0d\n", total_instructions),
                    $sformatf("  Final IPC:      %.3f\n", final_ipc),
                    //$sformatf("  Cache Misses:   %0d\n", vif.monitor_cb.cache_miss_count),
                    "========================================"
                }, UVM_LOW)
            end
            
            // // PC change detection (for debugging)
            // if (vif.monitor_cb.pc_valid && vif.monitor_cb.pc != prev_pc) begin
            //     `uvm_info("STATUS_MON", $sformatf(
            //         "PC: 0x%08h → 0x%08h",
            //         prev_pc, vif.monitor_cb.pc), UVM_DEBUG)
            // end
            // PC change detection (for debugging) - pc_valid not available
if (vif.monitor_cb.pc != prev_pc && vif.monitor_cb.pc != 0) begin
    `uvm_info("STATUS_MON", $sformatf(
        "PC: 0x%08h → 0x%08h",
        prev_pc, vif.monitor_cb.pc), UVM_DEBUG)
end

            
            // Update previous values
            prev_busy   = vif.monitor_cb.busy;
            prev_ebreak = vif.monitor_cb.ebreak_detected;
            prev_pc     = vif.monitor_cb.pc;
        end
    endtask
    
    // //==========================================================================
    // // Track Performance
    // // Monitor IPC and detect stalls in real-time
    // //==========================================================================
    // virtual task track_performance();
    //     real current_ipc;
        
    //     forever begin
    //         @(vif.monitor_cb);
            
    //         // Calculate current IPC (CORRECTED: calculate instead of reading from interface)
    //         if (vif.monitor_cb.cycle_count > 0) begin
    //             current_ipc = real'(vif.monitor_cb.instr_count) / real'(vif.monitor_cb.cycle_count);
    //         end else begin
    //             current_ipc = 0.0;
    //         end
            
    //         // Update peak IPC
    //         if (current_ipc > peak_ipc) 
    //             peak_ipc = current_ipc;
            
    //         // Detect any stall condition
    //         if (vif.monitor_cb.busy &&
    //             (vif.monitor_cb.fetch_stall   || vif.monitor_cb.decode_stall  ||
    //              vif.monitor_cb.issue_stall   || vif.monitor_cb.execute_stall ||
    //              vif.monitor_cb.commit_stall  || vif.monitor_cb.memory_stall)) begin
    //             -> stall_detected;
    //         end
            
    //         // // Periodic performance reporting (every 10000 cycles)
    //         // if (vif.monitor_cb.busy && (vif.monitor_cb.cycle_count % 10000 == 0)) begin
    //         //     `uvm_info("STATUS_MON", $sformatf(
    //         //         "Performance @ cycle %0d: instrs=%0d, IPC=%.3f, stalls=%0d, cache_misses=%0d",
    //         //         vif.monitor_cb.cycle_count, 
    //         //         vif.monitor_cb.instr_count,
    //         //         current_ipc, 
    //         //         num_stall_cycles, 
    //         //         vif.monitor_cb.cache_miss_count), UVM_DEBUG)
    //         // end
    //                     // Periodic performance reporting (every 10000 cycles)
    //         if (vif.monitor_cb.busy && (vif.monitor_cb.cycle_count % 10000 == 0)) begin
    //             `uvm_info("STATUS_MON", $sformatf(
    //                 "Performance @ cycle %0d: instrs=%0d, IPC=%.3f, stalls=%0d",
    //                 vif.monitor_cb.cycle_count, 
    //                 vif.monitor_cb.instr_count,
    //                 current_ipc, 
    //                 num_stall_cycles), UVM_DEBUG)
    //         end
    //     end
    // endtask


    //==========================================================================
// Track Performance
// Monitor IPC in real-time
// Note: Stall signals not available from Vortex DUT
//==========================================================================
virtual task track_performance();
    real current_ipc;
    
    forever begin
        @(vif.monitor_cb);
        
        // Calculate current IPC
        if (vif.monitor_cb.cycle_count > 0) begin
            current_ipc = real'(vif.monitor_cb.instr_count) / real'(vif.monitor_cb.cycle_count);
        end else begin
            current_ipc = 0.0;
        end
        
        // Update peak IPC
        if (current_ipc > peak_ipc) 
            peak_ipc = current_ipc;
        
        // Note: Stall detection not available - Vortex RTL doesn't expose stall signals
        
        // Periodic performance reporting (every 10000 cycles)
        if (vif.monitor_cb.busy && (vif.monitor_cb.cycle_count % 10000 == 0)) begin
            `uvm_info("STATUS_MON", $sformatf(
                "Performance @ cycle %0d: instrs=%0d, IPC=%.3f",
                vif.monitor_cb.cycle_count, 
                vif.monitor_cb.instr_count,
                current_ipc), UVM_DEBUG)
        end
    end
endtask

    
    //==========================================================================
    // Wait for Execution Start
    // Blocking task that other components can call
    //==========================================================================
    task wait_execution_start();
        if (!execution_started) 
            @(execution_start);
    endtask
    
    //==========================================================================
    // Wait for Execution Complete
    // Blocking task that scoreboard uses for Option A
    // CRITICAL: Scoreboard waits here before comparing memory
    //==========================================================================
    task wait_execution_complete();
        if (!execution_completed) 
            @(execution_complete);
    endtask
    
    //==========================================================================
    // Check Phase
    // Verify execution started and completed
    //==========================================================================
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        
        if (!execution_started) begin
            `uvm_warning("STATUS_MON", "Core never became busy - no execution detected")
        end
        
        if (execution_started && !execution_completed) begin
            `uvm_warning("STATUS_MON", "Execution started but did not complete (no EBREAK)")
        end
    endfunction
    
    //==========================================================================
    // Report Phase
    // Print comprehensive execution statistics
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        real avg_ipc, stall_percentage;
        
        super.report_phase(phase);
        
        // Calculate final metrics
        if (total_execution_cycles > 0) begin
            avg_ipc = real'(total_instructions) / real'(total_execution_cycles);
            stall_percentage = (real'(num_stall_cycles) / real'(total_execution_cycles)) * 100.0;
        end else begin
            avg_ipc = 0.0;
            stall_percentage = 0.0;
        end
        
        `uvm_info("STATUS_MON", {"\n",
            "========================================\n",
            "    Status Monitor Statistics\n",
            "========================================\n",
            $sformatf("  Busy Transitions:   %0d\n", num_busy_transitions),
            $sformatf("  Idle Transitions:   %0d\n", num_idle_transitions),
            $sformatf("  Execution Started:  %s\n", execution_started ? "YES" : "NO"),
            $sformatf("  Execution Completed:%s\n", execution_completed ? "YES" : "NO"),
            $sformatf("  Total Cycles:       %0d\n", total_execution_cycles),
            $sformatf("  Total Instructions: %0d\n", total_instructions),
            $sformatf("  Average IPC:        %.3f\n", avg_ipc),
            $sformatf("  Peak IPC:           %.3f\n", peak_ipc),
            $sformatf("  Stall Cycles:       %0d (%.2f%%)\n", num_stall_cycles, stall_percentage),
            $sformatf("  Execution Time:     %0t\n", 
                execution_completed ? (execution_end_time - execution_start_time) : 0),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : status_monitor

`endif // STATUS_MONITOR_SV
