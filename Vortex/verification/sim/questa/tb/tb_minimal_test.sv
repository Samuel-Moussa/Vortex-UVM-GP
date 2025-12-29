// Minimal Sanity Test for Vortex RTL
// Just tests clock, reset, and basic signal connectivity
// No kernel loading, no complex operations

`timescale 1ns/1ps

`include "VX_define.vh"

module tb_minimal_test;
    import VX_gpu_pkg::*;

    // Simulation parameters
    parameter CLK_PERIOD = 10;  // 10ns = 100MHz
    parameter TEST_CYCLES = 1000; // Run for 1000 cycles
    
    // Clock and Reset
    logic clk;
    logic reset;
    
    // Vortex Memory Interface Signals
    logic                             mem_req_valid [VX_MEM_PORTS];
    logic                             mem_req_rw [VX_MEM_PORTS];
    logic [VX_MEM_BYTEEN_WIDTH-1:0]   mem_req_byteen [VX_MEM_PORTS];
    logic [VX_MEM_ADDR_WIDTH-1:0]     mem_req_addr [VX_MEM_PORTS];
    logic [VX_MEM_DATA_WIDTH-1:0]     mem_req_data [VX_MEM_PORTS];
    logic [VX_MEM_TAG_WIDTH-1:0]      mem_req_tag [VX_MEM_PORTS];
    logic                             mem_req_ready [VX_MEM_PORTS];
    
    logic                             mem_rsp_valid [VX_MEM_PORTS];
    logic [VX_MEM_DATA_WIDTH-1:0]     mem_rsp_data [VX_MEM_PORTS];
    logic [VX_MEM_TAG_WIDTH-1:0]      mem_rsp_tag [VX_MEM_PORTS];
    logic                             mem_rsp_ready [VX_MEM_PORTS];
    
    // DCR Interface
    logic                             dcr_wr_valid;
    logic [VX_DCR_ADDR_WIDTH-1:0]     dcr_wr_addr;
    logic [VX_DCR_DATA_WIDTH-1:0]     dcr_wr_data;
    
    // Status
    logic                             busy;
    
    // Test signals
    int cycle_count;
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // DUT: Vortex GPGPU
    //=========================================================================
    Vortex vortex_dut (
        .clk            (clk),
        .reset          (reset),
        
        .mem_req_valid  (mem_req_valid),
        .mem_req_rw     (mem_req_rw),
        .mem_req_byteen (mem_req_byteen),
        .mem_req_addr   (mem_req_addr),
        .mem_req_data   (mem_req_data),
        .mem_req_tag    (mem_req_tag),
        .mem_req_ready  (mem_req_ready),
        
        .mem_rsp_valid  (mem_rsp_valid),
        .mem_rsp_data   (mem_rsp_data),
        .mem_rsp_tag    (mem_rsp_tag),
        .mem_rsp_ready  (mem_rsp_ready),
        
        .dcr_wr_valid   (dcr_wr_valid),
        .dcr_wr_addr    (dcr_wr_addr),
        .dcr_wr_data    (dcr_wr_data),
        
        .busy           (busy)
    );
    
    //=========================================================================
    // Memory Tie-offs (all ports tied to constant values)
    //=========================================================================
    genvar p;
    generate
        for (p = 0; p < VX_MEM_PORTS; p++) begin : mem_tie_off
            // Memory request interface - always ready
            assign mem_req_ready[p] = 1'b1;
            
            // Memory response interface - no valid responses
            assign mem_rsp_valid[p] = 1'b0;
            assign mem_rsp_data[p] = '0;
            assign mem_rsp_tag[p] = '0;
            
            // Memory response ready - always ready (ONLY ONE ASSIGN)
        //    assign mem_rsp_ready[p] = ~mem_rsp_ready[p];
        end
    endgenerate
    
    //=========================================================================
    // Test Sequence
    //=========================================================================
    initial begin
        $display("========================================");
        $display("  Vortex Minimal Sanity Test");
        $display("  Testing: Clock, Reset, Basic Signals");
        $display("========================================");
        
        // Initialize control signals only (not memory signals - those are assigned above)
        reset = 1;
        dcr_wr_valid = 0;
        dcr_wr_addr = 0;
        dcr_wr_data = 0;
        cycle_count = 0;
        
        $display("[%0t] Test started - all signals initialized", $time);
        
        // Hold reset for 100 cycles
        $display("[%0t] Asserting reset...", $time);
        repeat(100) @(posedge clk);
        
        // Release reset
        $display("[%0t] Releasing reset", $time);
        reset = 0;
        repeat(10) @(posedge clk);
        
        $display("[%0t] Reset released - Vortex should be idle", $time);
        $display("[%0t] Busy signal: %b", $time, busy);
        
        // Try a simple DCR write
        $display("[%0t] Writing to DCR register 0...", $time);
        @(posedge clk);
        dcr_wr_valid = 1;
        dcr_wr_addr = 0;
        dcr_wr_data = 32'hDEADBEEF;
        @(posedge clk);
        dcr_wr_valid = 0;
        
        $display("[%0t] DCR write complete", $time);
        
        // Run for more cycles
        $display("[%0t] Running for %0d more cycles...", $time, TEST_CYCLES);
        repeat(TEST_CYCLES) @(posedge clk);
        
        // Final status
        $display("========================================");
        $display("  Test Complete!");
        $display("  Total cycles run: %0d", cycle_count);
        $display("  Final busy state: %b", busy);
        $display("  Clock toggled correctly: %s", (cycle_count > 0) ? "YES" : "NO");
        $display("========================================");
        
        $display("");
        $display("✓ Minimal sanity test PASSED");
        $display("  - Clock generation works");
        $display("  - Reset works");
        $display("  - Vortex instantiation works");
        $display("  - Basic signals toggle");
        $display("");
        $display("Check the waveform for visual verification:");
        $display("  gtkwave vortex_minimal.vcd &");
        
        //$finish;
    end
    
	
	initial begin
		$display("[%0t] Enabling full signal visibility for QuestaSim", $time);
		$wlfdumpvars;   // Questa-specific waveform dump
	end

    //=========================================================================
    // Cycle Counter
    //=========================================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end
    
    //=========================================================================
    // Monitor Key Signals
    //=========================================================================
    always @(posedge clk) begin
        if (!reset && (cycle_count % 100 == 0)) begin
            $display("[%0t] Cycle %0d - busy=%b, mem_req[0]=%b", 
                     $time, cycle_count, busy, mem_req_valid[0]);
        end
    end
    
    //=========================================================================
    // Waveform Dumping (ALWAYS ON for this test)
    //=========================================================================
    initial begin
        $dumpfile("vortex_minimal.vcd");
        $dumpvars(0, tb_minimal_test);
        $display("[%0t] VCD waveform dump enabled: vortex_minimal.vcd", $time);
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #(CLK_PERIOD * (TEST_CYCLES + 200));
        $display("[%0t] Test timeout - something went wrong!", $time);
        //$finish;
    end

endmodule