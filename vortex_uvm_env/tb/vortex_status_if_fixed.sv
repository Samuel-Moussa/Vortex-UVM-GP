////////////////////////////////////////////////////////////////////////////////
// File: vortex_status_if.sv (CORRECTED VERSION)
// Description: Status interface - ONLY signals actually provided by Vortex DUT
//
// IMPORTANT CHANGES:
//   - Removed performance counters (cycle_count, instr_count) - NOT provided by DUT
//   - Removed PC, pipeline state - NOT provided by DUT
//   - Removed assertions on unavailable signals
//   - Kept only: busy, ebreak_detected
//
// The DUT provides minimal status outputs. Performance monitoring must be done
// via CSR reads or by tracking in the testbench.
//
// Author: Vortex UVM Team (Fixed Version)
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_STATUS_IF_SV
`define VORTEX_STATUS_IF_SV

interface vortex_status_if (
    input logic clk,
    input logic reset_n
);

    //==========================================================================
    // CORE STATUS SIGNALS (Actually provided by Vortex DUT)
    //==========================================================================
    logic       busy;               // Core is executing (DUT drives this)
    logic       ebreak_detected;    // EBREAK instruction hit (if DUT provides it)
    
    // Derived signal for convenience
    assign idle = !busy;
    logic       idle;

    //==========================================================================
    // CLOCKING BLOCK: MONITOR (Passive Observation Only)
    //==========================================================================
    clocking monitor_cb @(posedge clk);
        default input #1step;
        
        input busy;
        input ebreak_detected;
        input idle;
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
        output busy,
        output ebreak_detected
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
            $display("[STATUS @ %0t] ====================================", $time);
            $display("[STATUS @ %0t] EBREAK DETECTED - Program Complete!", $time);
            $display("[STATUS @ %0t] ====================================", $time);
        end
    end

    //==========================================================================
    // INITIAL VALUES
    //==========================================================================
    
    initial begin
        // These will be driven by DUT, but initialize for safety
        // during reset
        busy = 1'b0;
        ebreak_detected = 1'b0;
    end

endinterface : vortex_status_if

`endif // VORTEX_STATUS_IF_SV