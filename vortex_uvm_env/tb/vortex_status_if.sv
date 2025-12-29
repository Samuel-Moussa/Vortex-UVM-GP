////////////////////////////////////////////////////////////////////////////////
// File: vortex_status_if.sv
// Description: Status and control signal interface with clocking blocks
//
// Protocol: Passive monitoring only (read-only signals)
//   - Busy: Core is executing
//   - ebreak: Program completion signal
//   - Debug signals: PC, stalls, performance counters
//
// Clocking Block:
//   - monitor_cb: For passive monitoring only
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_STATUS_IF_SV
`define VORTEX_STATUS_IF_SV

interface vortex_status_if (
    input logic clk,
    input logic reset_n
);

    //==========================================================================
    // CORE STATUS SIGNALS
    //==========================================================================
    logic       busy;               // Core is executing
    logic       ebreak_detected;    // Program hit ebreak instruction
    logic       idle;               // Core is idle (opposite of busy)
    
    //==========================================================================
    // PROGRAM COUNTER (DEBUG)
    //==========================================================================
    logic [31:0] pc;                // Current program counter
    logic [31:0] next_pc;           // Next PC value
    logic        pc_valid;          // PC is valid
    
    //==========================================================================
    // PIPELINE STALL SIGNALS (DEBUG)
    //==========================================================================
    logic        fetch_stall;
    logic        decode_stall;
    logic        issue_stall;
    logic        execute_stall;
    logic        commit_stall;
    logic        memory_stall;
    
    //==========================================================================
    // WARP/THREAD STATUS (DEBUG)
    //==========================================================================
    logic [31:0] active_warps;      // Bitmask of active warps
    logic [31:0] active_threads;    // Bitmask of active threads
    logic [7:0]  warp_id;           // Current warp ID
    logic [7:0]  thread_id;         // Current thread ID
    
    //==========================================================================
    // PERFORMANCE COUNTERS (OPTIONAL)
    //==========================================================================
    logic [63:0] cycle_count;       // Total cycles
    logic [63:0] instr_count;       // Instructions retired
    logic [63:0] load_count;        // Load instructions
    logic [63:0] store_count;       // Store instructions
    logic [63:0] branch_count;      // Branch instructions
    logic [63:0] cache_miss_count;  // Cache misses

    //==========================================================================
    // CLOCKING BLOCK: MONITOR (Passive Observation Only)
    //==========================================================================
    clocking monitor_cb @(posedge clk);
        default input #1step;
        
        // All signals are inputs (read-only)
        input busy;
        input ebreak_detected;
        input idle;
        input pc, next_pc, pc_valid;
        input fetch_stall, decode_stall, issue_stall, execute_stall, commit_stall, memory_stall;
        input active_warps, active_threads, warp_id, thread_id;
        input cycle_count, instr_count, load_count, store_count, branch_count, cache_miss_count;
    endclocking

    //==========================================================================
    // MODPORTS
    //==========================================================================
    
    // For UVM monitor (read-only)
    modport monitor (
        clocking monitor_cb,
        input clk, reset_n
    );
    
    // For DUT connection
    modport dut (
        output busy, ebreak_detected, idle,
        output pc, next_pc, pc_valid,
        output fetch_stall, decode_stall, issue_stall, execute_stall, commit_stall, memory_stall,
        output active_warps, active_threads, warp_id, thread_id,
        output cycle_count, instr_count, load_count, store_count, branch_count, cache_miss_count
    );

    //==========================================================================
    // HELPER FUNCTIONS
    //==========================================================================
    
    function automatic bit is_busy();
        return busy;
    endfunction
    
    function automatic bit is_idle();
        return !busy;
    endfunction
    
    function automatic bit has_completed();
        return ebreak_detected;
    endfunction
    
    function automatic bit is_stalled();
        return (fetch_stall || decode_stall || issue_stall || 
                execute_stall || commit_stall || memory_stall);
    endfunction
    
    function automatic int count_active_warps();
        int count = 0;
        for (int i = 0; i < 32; i++) begin
            if (active_warps[i]) count++;
        end
        return count;
    endfunction
    
    function automatic int count_active_threads();
        int count = 0;
        for (int i = 0; i < 32; i++) begin
            if (active_threads[i]) count++;
        end
        return count;
    endfunction

    //==========================================================================
    // DERIVED SIGNALS
    //==========================================================================
    
    // Calculate IPC (Instructions Per Cycle)
    real ipc;
    always_comb begin
        if (cycle_count > 0)
            ipc = real'(instr_count) / real'(cycle_count);
        else
            ipc = 0.0;
    end
    
    // Calculate cache miss rate
    real cache_miss_rate;
    always_comb begin
        if ((load_count + store_count) > 0)
            cache_miss_rate = real'(cache_miss_count) / real'(load_count + store_count);
        else
            cache_miss_rate = 0.0;
    end

    //==========================================================================
    // TASKS FOR TESTBENCH
    //==========================================================================
    
    // Task: Wait until core is busy
    task automatic wait_busy();
        @(monitor_cb iff monitor_cb.busy);
    endtask
    
    // Task: Wait until core is idle
    task automatic wait_idle();
        @(monitor_cb iff !monitor_cb.busy);
    endtask
    
    // Task: Wait for ebreak
    task automatic wait_ebreak();
        @(monitor_cb iff monitor_cb.ebreak_detected);
    endtask
    
    // Task: Wait for specific PC
    task automatic wait_pc(input logic [31:0] target_pc);
        @(monitor_cb iff (monitor_cb.pc == target_pc));
    endtask

    //==========================================================================
    // MONITORS: State Transitions
    //==========================================================================
    
    // Monitor busy transitions
    always @(posedge clk) begin
        if (reset_n) begin
            static bit prev_busy = 0;
            if (busy && !prev_busy)
                $display("[STATUS @ %0t] Core started (IDLE → BUSY)", $time);
            else if (!busy && prev_busy)
                $display("[STATUS @ %0t] Core stopped (BUSY → IDLE)", $time);
            prev_busy = busy;
        end
    end
    
    // Monitor ebreak
    always @(posedge clk) begin
        if (reset_n && ebreak_detected) begin
            $display("[STATUS @ %0t] EBREAK detected! Program completed.", $time);
            $display("[STATUS @ %0t] Performance Summary:", $time);
            $display("                  Cycles:       %0d", cycle_count);
            $display("                  Instructions: %0d", instr_count);
            $display("                  IPC:          %0.2f", ipc);
        end
    end

    // //==========================================================================
    // // COVERAGE
    // //==========================================================================
    
    // covergroup status_cg @(posedge clk);
    //     option.per_instance = 1;
        
    //     // Busy state coverage
    //     busy_cp: coverpoint busy {
    //         bins idle = {0};
    //         bins busy = {1};
    //         bins idle_to_busy = (0 => 1);
    //         bins busy_to_idle = (1 => 0);
    //     }
        
    //     // Completion coverage
    //     ebreak_cp: coverpoint ebreak_detected {
    //         bins no_ebreak = {0};
    //         bins ebreak    = {1};
    //     }
        
    //     // Stall types coverage
    //     stall_type_cp: coverpoint {fetch_stall, decode_stall, issue_stall, 
    //                                 execute_stall, commit_stall, memory_stall} {
    //         bins no_stall       = {6'b000000};
    //         bins fetch_only     = {6'b100000};
    //         bins decode_only    = {6'b010000};
    //         bins issue_only     = {6'b001000};
    //         bins execute_only   = {6'b000100};
    //         bins commit_only    = {6'b000010};
    //         bins memory_only    = {6'b000001};
    //         bins multiple_stalls = {[6'b000011:6'b111111]};
    //     }
        
    //     // Active warp count
    //     active_warp_count_cp: coverpoint count_active_warps() {
    //         bins none   = {0};
    //         bins one    = {1};
    //         bins few    = {[2:4]};
    //         bins many   = {[5:16]};
    //         bins all    = {[17:32]};
    //     }
        
    //     // IPC ranges
    //     ipc_cp: coverpoint ipc {
    //         bins very_low  = {[0.0:0.25]};
    //         bins low       = {[0.25:0.5]};
    //         bins medium    = {[0.5:0.75]};
    //         bins high      = {[0.75:1.0]};
    //         bins very_high = {[1.0:$]};
    //     }
        
    //     // Cross coverage
    //     busy_stall_cross: cross busy_cp, stall_type_cp;
    // endgroup
    
    // status_cg status_cov = new();

    // //==========================================================================
    // // PERFORMANCE ASSERTIONS
    // //==========================================================================
    
    // // Performance counter monotonicity
    // property cycle_count_monotonic_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     busy |-> ##1 (cycle_count > $past(cycle_count));
    // endproperty
    
    // property instr_count_monotonic_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     (busy && !is_stalled()) |-> ##[1:10] (instr_count >= $past(instr_count));
    // endproperty
    
    // assert_cycle_count_monotonic: assert property (cycle_count_monotonic_p)
    //     else $warning("[STATUS_IF] Cycle count did not increase!");
    
    // // Busy must be high when there are active warps
    // property busy_when_active_warps_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     (active_warps != 0) |-> busy;
    // endproperty
    
    // assert_busy_when_active: assert property (busy_when_active_warps_p)
    //     else $error("[STATUS_IF] Core idle but warps are active!");

    //==========================================================================
    // INITIAL VALUES
    //==========================================================================
    
    initial begin
        // Initialize optional signals to safe defaults
        pc = '0;
        next_pc = '0;
        pc_valid = 0;
        active_warps = '0;
        active_threads = '0;
        warp_id = '0;
        thread_id = '0;
        cycle_count = '0;
        instr_count = '0;
        load_count = '0;
        store_count = '0;
        branch_count = '0;
        cache_miss_count = '0;
    end

endinterface : vortex_status_if

`endif // VORTEX_STATUS_IF_SV