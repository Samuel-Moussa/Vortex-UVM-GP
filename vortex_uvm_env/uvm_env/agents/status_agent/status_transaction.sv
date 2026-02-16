////////////////////////////////////////////////////////////////////////////////
// File: status_transaction.sv
// Description: Status Transaction for Vortex Execution Status Monitoring
//
// This transaction represents a snapshot of the Vortex GPU's execution status.
// It captures:
//   - Core busy/idle state
//   - Program counter and execution progress
//   - Pipeline stall conditions
//   - Active warp/thread counts
//   - Performance counters (cycles, instructions, cache stats)
//
// Key Features:
//   - Real-time performance metrics (IPC, cache miss rate)
//   - Stall detection and classification
//   - EBREAK detection (program completion)
//   - Warp/thread activity tracking
//
// Usage:
//   - Status monitor samples the interface periodically
//   - Each sample creates a status_transaction
//   - Scoreboard uses ebreak_detected to trigger final comparison
//
// **For Option A (Final State Comparison)**:
//   The scoreboard waits for ebreak_detected signal, then compares
//   RTL memory state vs simx memory state
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef STATUS_TRANSACTION_SV
`define STATUS_TRANSACTION_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import status_agent_pkg::*;


class status_transaction extends uvm_sequence_item;
    
    //==========================================================================
    // Core Execution State
    //==========================================================================
    bit busy;                    // 1 = core is executing, 0 = idle
    bit ebreak_detected;         // 1 = EBREAK instruction executed (program end)
    bit idle;                    // !busy (redundant but convenient)
    
    //==========================================================================
    // Program Counter Tracking
    //==========================================================================
    bit [31:0] pc;               // Current program counter
    bit [31:0] next_pc;          // Next PC to execute
    bit        pc_valid;         // PC value is valid
    
    //==========================================================================
    // Pipeline Stall Flags
    // Each flag indicates a specific pipeline stage is stalled
    //==========================================================================
    bit fetch_stall;             // Instruction fetch stalled
    bit decode_stall;            // Instruction decode stalled
    bit issue_stall;             // Instruction issue stalled
    bit execute_stall;           // Execution unit stalled
    bit commit_stall;            // Commit stage stalled
    bit memory_stall;            // Memory operation stalled
    
    //==========================================================================
    // Warp and Thread Activity
    // Vortex GPGPU executes multiple warps and threads in parallel
    //==========================================================================
    bit [31:0] active_warps;     // Bitmask of active warps
    bit [31:0] active_threads;   // Bitmask of active threads
    bit [7:0]  warp_id;          // Current warp ID
    bit [7:0]  thread_id;        // Current thread ID
    
    //==========================================================================
    // Performance Counters
    // Cumulative counters from start of execution
    //==========================================================================
    bit [63:0] cycle_count;      // Total clock cycles elapsed
    bit [63:0] instr_count;      // Total instructions retired
    bit [63:0] load_count;       // Total load instructions
    bit [63:0] store_count;      // Total store instructions
    bit [63:0] branch_count;     // Total branch instructions
    bit [63:0] cache_miss_count; // Total cache misses
    
    //==========================================================================
    // Timing Information
    //==========================================================================
    time sample_time;            // Simulation time when sampled
    
    //==========================================================================
    // Derived Performance Metrics
    // Calculated from counters
    //==========================================================================
    real ipc;                    // Instructions Per Cycle
    real cache_miss_rate;        // Cache miss percentage
    
    //==========================================================================
    // UVM Automation Macros
    //==========================================================================
    `uvm_object_utils_begin(status_transaction)
        `uvm_field_int(busy, UVM_ALL_ON)
        `uvm_field_int(ebreak_detected, UVM_ALL_ON)
        `uvm_field_int(idle, UVM_ALL_ON)
        `uvm_field_int(pc, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(cycle_count, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(instr_count, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "status_transaction");
        super.new(name);
        sample_time = 0;
        ipc = 0.0;
        cache_miss_rate = 0.0;
    endfunction
    
    //==========================================================================
    // Post Randomize Hook
    // Automatically calculate metrics after randomization
    //==========================================================================
    function void post_randomize();
        calculate_metrics();
    endfunction
    
    // //==========================================================================
    // // Calculate Derived Performance Metrics
    // //==========================================================================
    // function void calculate_metrics();
    //     // Calculate Instructions Per Cycle (IPC)
    //     if (cycle_count > 0)
    //         ipc = real'(instr_count) / real'(cycle_count);
    //     else
    //         ipc = 0.0;
        
    //     // Calculate Cache Miss Rate (as percentage)
    //     if ((load_count + store_count) > 0)
    //         cache_miss_rate = (real'(cache_miss_count) / real'(load_count + store_count)) * 100.0;
    //     else
    //         cache_miss_rate = 0.0;
    // endfunction

    //==========================================================================
// Calculate Derived Performance Metrics
//==========================================================================
function void calculate_metrics();
    // Calculate Instructions Per Cycle (IPC)
    if (cycle_count > 0)
        ipc = real'(instr_count) / real'(cycle_count);
    else
        ipc = 0.0;
    
    // Cache miss rate - DISABLED (load_count, store_count, cache_miss_count not available)
    cache_miss_rate = 0.0;
endfunction

    
    //==========================================================================
    // Helper Methods - Status Queries
    //==========================================================================
    
    function bit is_busy();
        return busy;
    endfunction
    
    function bit is_idle();
        return !busy;
    endfunction
    
    function bit has_completed();
        return ebreak_detected;
    endfunction
    
    function bit is_stalled();
        return (fetch_stall || decode_stall || issue_stall ||
                execute_stall || commit_stall || memory_stall);
    endfunction
    
    //==========================================================================
    // Count Active Warps
    // Returns number of warps currently active
    //==========================================================================
    function int count_active_warps();
        int count = 0;
        for (int i = 0; i < 32; i++) begin
            if (active_warps[i]) count++;
        end
        return count;
    endfunction
    
    //==========================================================================
    // Count Active Threads
    // Returns number of threads currently active
    //==========================================================================
    function int count_active_threads();
        int count = 0;
        for (int i = 0; i < 32; i++) begin
            if (active_threads[i]) count++;
        end
        return count;
    endfunction
    
    //==========================================================================
    // Get Stalled Pipeline Stages
    // Returns human-readable string of stalled stages
    //==========================================================================
    function string get_stall_stages();
        string stages = "";
        
        if (fetch_stall)   stages = {stages, "FETCH "};
        if (decode_stall)  stages = {stages, "DECODE "};
        if (issue_stall)   stages = {stages, "ISSUE "};
        if (execute_stall) stages = {stages, "EXECUTE "};
        if (commit_stall)  stages = {stages, "COMMIT "};
        if (memory_stall)  stages = {stages, "MEMORY "};
        
        return (stages == "") ? "NONE" : stages;
    endfunction
    
    //==========================================================================
    // Convert to String (for debugging and logging)
    //==========================================================================
    virtual function string convert2string();
        string s;
        
        s = super.convert2string();
        s = {s, $sformatf("\n┌─ Status Snapshot ────────────────")};
        s = {s, $sformatf("\n│ State:        %s", busy ? "BUSY" : "IDLE")};
        
        if (ebreak_detected) 
            s = {s, " [EBREAK DETECTED]"};
        
        if (pc_valid) 
            s = {s, $sformatf("\n│ PC:           0x%08h", pc)};
        
        s = {s, $sformatf("\n├─ Performance ────────────────────")};
        s = {s, $sformatf("\n│ Cycles:       %0d", cycle_count)};
        s = {s, $sformatf("\n│ Instructions: %0d", instr_count)};
        s = {s, $sformatf("\n│ IPC:          %.3f", ipc)};
        
        if (is_stalled()) 
            s = {s, $sformatf("\n│ Stalled:      %s", get_stall_stages())};
        
        if (count_active_warps() > 0) begin
            s = {s, $sformatf("\n│ Active Warps:   %0d", count_active_warps())};
            s = {s, $sformatf("\n│ Active Threads: %0d", count_active_threads())};
        end
        
        // if (cache_miss_count > 0) begin
        //     s = {s, $sformatf("\n│ Cache Misses: %0d (%.2f%%)", 
        //         cache_miss_count, cache_miss_rate)};
        // end
        
        s = {s, "\n└──────────────────────────────────"};
        
        return s;
    endfunction
    
    //==========================================================================
    // Comparison Function (for scoreboard)
    //==========================================================================
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        status_transaction rhs_;
        
        if (!$cast(rhs_, rhs)) begin
            `uvm_error("STATUS_TRANS", "Cast failed in do_compare")
            return 0;
        end
        
        return (
            super.do_compare(rhs, comparer) &&
            (busy == rhs_.busy) &&
            (ebreak_detected == rhs_.ebreak_detected) &&
            (pc == rhs_.pc)
        );
    endfunction
    
endclass : status_transaction

`endif // STATUS_TRANSACTION_SV
