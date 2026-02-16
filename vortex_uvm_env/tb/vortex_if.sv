////////////////////////////////////////////////////////////////////////////////
// File: vortex_if.sv
// Description: Complete interface bundle for Vortex GPGPU UVM verification
//
// This top-level interface encapsulates all sub-interfaces:
//   1. vortex_axi_if    - AXI4 memory interface
//   2. vortex_mem_if    - Custom memory interface
//   3. vortex_dcr_if    - Device Configuration Registers
//   4. vortex_status_if - Status and performance monitoring
//
// Usage in testbench:
//   vortex_if vif(clk, reset_n);
//   
//   // Access sub-interfaces:
//   vif.axi_if.master_cb.awvalid <= 1;
//   vif.mem_if.master_cb.req_valid <= 1;
//   vif.dcr_if.master_cb.wr_valid <= 1;
//   vif.status_if.monitor_cb.busy;
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_IF_SV
`define VORTEX_IF_SV

interface vortex_if (
    input logic clk,
    input logic reset_n
);

    //==========================================================================
    // SUB-INTERFACE INSTANTIATION
    //==========================================================================
    
    // AXI4 interface (for AXI wrapper version)
    vortex_axi_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(64),
        .ID_WIDTH(4)
    ) axi_if (
        .clk(clk),
        .reset_n(reset_n)
    );
    
    // Custom memory interface (for non-AXI version)
    vortex_mem_if mem_if (
        .clk(clk),
        .reset_n(reset_n)
    );
    
    // DCR (Device Configuration Register) interface
    vortex_dcr_if dcr_if (
        .clk(clk),
        .reset_n(reset_n)
    );
    
    // Status and performance monitoring interface
    vortex_status_if status_if (
        .clk(clk),
        .reset_n(reset_n)
    );

    //==========================================================================
    // MASTER CLOCKING BLOCK (Aggregated for convenience)
    //==========================================================================
    // This aggregates all sub-interface master clocking blocks
    // Useful when you need to synchronize across multiple interfaces
    
    clocking master_cb @(posedge clk);
        default input #1step output #0;
    endclocking

    //==========================================================================
    // MONITOR CLOCKING BLOCK (Aggregated for convenience)
    //==========================================================================
    
    clocking monitor_cb @(posedge clk);
        default input #1step;
    endclocking

    //==========================================================================
    // MODPORTS FOR AGGREGATED ACCESS
    //==========================================================================
    
    // For testbench master components
    modport master (
        clocking master_cb,
        input clk, reset_n
    );
    
    // For testbench monitor components
    modport monitor (
        clocking monitor_cb,
        input clk, reset_n
    );

    //==========================================================================
    // CONVENIENCE TASKS (Global Operations)
    //==========================================================================
    
    // // Initialize all interfaces to safe defaults
    // task automatic init_all_interfaces();
    //     // AXI defaults
    //     axi_if.awvalid = 1'b0;
    //     axi_if.wvalid  = 1'b0;
    //     axi_if.bready  = 1'b1;
    //     axi_if.arvalid = 1'b0;
    //     axi_if.rready  = 1'b1;
        
    //     // Memory interface defaults
    //     mem_if.req_valid = 1'b0;
    //     mem_if.rsp_ready = 1'b1;
        
    //     // DCR defaults
    //     dcr_if.wr_valid = 1'b0;
        
    //     $display("[VORTEX_IF @ %0t] All interfaces initialized", $time);
    // endtask
    
    // Wait for reset completion
    task automatic wait_reset_done();
        wait(reset_n == 1'b0);
        wait(reset_n == 1'b1);
        repeat(5) @(posedge clk);
        $display("[VORTEX_IF @ %0t] Reset sequence complete", $time);
    endtask
    
    // Wait for system idle
    task automatic wait_system_idle();
        @(posedge clk);
        wait(status_if.busy == 1'b0);
        $display("[VORTEX_IF @ %0t] System idle", $time);
    endtask
    
    // // Wait for kernel completion
    // task automatic wait_kernel_complete(input int timeout_cycles = 100000);
    //     int cycles = 0;
        
    //     fork
    //         begin
    //             // Wait for ebreak or busy going low
    //             while (cycles < timeout_cycles) begin
    //                 @(posedge clk);
    //                 cycles++;
    //                 if (status_if.ebreak_detected || !status_if.busy) begin
    //                     $display("[VORTEX_IF @ %0t] Kernel completed in %0d cycles", 
    //                         $time, cycles);
    //                     return;
    //                 end
    //             end
    //             $error("[VORTEX_IF @ %0t] Kernel timeout after %0d cycles!", 
    //                 $time, timeout_cycles);
    //         end
    //     join
    // endtask


    task automatic wait_kernel_complete(input int timeout_cycles = 100000);
    int cycles = 0;

    while (cycles < timeout_cycles) begin
        @(posedge clk);
        cycles++;

        if (status_if.ebreak_detected || !status_if.busy) begin
            $display("[VORTEX_IF @ %0t] Kernel completed in %0d cycles",
                     $time, cycles);
            return;
        end
      end

          $error("[VORTEX_IF @ %0t] Kernel timeout after %0d cycles!",
             $time, timeout_cycles);
     endtask


    //==========================================================================
    // SYSTEM-LEVEL ASSERTIONS
    //==========================================================================
    
    // When busy, at least one sub-interface should be active
    property system_activity_p;
        @(posedge clk) disable iff (!reset_n)
        status_if.busy |-> (
            mem_if.req_valid || mem_if.rsp_valid ||
            axi_if.awvalid || axi_if.wvalid || axi_if.arvalid ||
            axi_if.rvalid || axi_if.bvalid
        );
    endproperty
    
    // DCR writes should only happen when system is idle or during config phase
    property dcr_write_timing_p;
        @(posedge clk) disable iff (!reset_n)
        dcr_if.wr_valid |-> !status_if.busy;
    endproperty
    
    // Reset behavior: all valid signals should be low after reset
    property reset_clears_valids_p;
        @(posedge clk)
        $fell(reset_n) |=> ##[1:10] (
            !axi_if.awvalid && !axi_if.wvalid && !axi_if.arvalid &&
            !mem_if.req_valid && !dcr_if.wr_valid
        );
    endproperty
    
    assert_system_activity: assert property (system_activity_p)
        else $warning("[VORTEX_IF] System busy but no interface activity!");
    
    assert_dcr_write_timing: assert property (dcr_write_timing_p)
        else $warning("[VORTEX_IF] DCR write during kernel execution!");
    
    assert_reset_clears_valids: assert property (reset_clears_valids_p)
        else $error("[VORTEX_IF] Valid signals not cleared after reset!");

    //==========================================================================
    // SYSTEM-LEVEL COVERAGE
    //==========================================================================
    
    covergroup system_cg @(posedge clk);
        option.per_instance = 1;
        option.name = "vortex_system_coverage";
        
        // System states
        system_state_cp: coverpoint {status_if.busy, status_if.idle} {
            bins idle           = {2'b01};
            bins busy           = {2'b10};
            bins idle_to_busy   = (2'b01 => 2'b10);
            bins busy_to_idle   = (2'b10 => 2'b01);
        }
        
        // Interface usage patterns
        axi_usage_cp: coverpoint {axi_if.awvalid, axi_if.arvalid} {
            bins no_access      = {2'b00};
            bins write_only     = {2'b10};
            bins read_only      = {2'b01};
            bins simultaneous   = {2'b11};
        }
        
        mem_usage_cp: coverpoint {mem_if.req_valid, mem_if.req_rw} {
            bins idle           = {2'b00};
            bins read           = {2'b10};
            bins write          = {2'b11};
        }
        
        dcr_activity_cp: coverpoint dcr_if.wr_valid {
            bins inactive       = {0};
            bins active         = {1};
        }
        
        // Cross coverage: system state with interface usage
        system_axi_cross: cross system_state_cp, axi_usage_cp;
        system_mem_cross: cross system_state_cp, mem_usage_cp;
        
    endgroup
    
    system_cg sys_cov = new();

    // //==========================================================================
    // // DEBUG: Interface Status Display
    // //==========================================================================
    
    // task automatic print_status();
    //     $display("================================================================================");
    //     $display("VORTEX INTERFACE STATUS @ %0t", $time);
    //     $display("================================================================================");
    //     $display("Clock: %b | Reset: %b", clk, reset_n);
    //     $display("");
    //     $display("STATUS INTERFACE:");
    //     $display("  Busy:   %b", status_if.busy);
    //     $display("  Idle:   %b", status_if.idle);
    //     $display("  ebreak: %b", status_if.ebreak_detected);
    //     $display("  Cycles: %0d", status_if.cycle_count);
    //     $display("  Instrs: %0d", status_if.instr_count);
    //     // $display("  IPC:    %0.2f", status_if.ipc);
    //     $display("");
    //     $display("AXI INTERFACE:");
    //     $display("  AW: valid=%b ready=%b addr=0x%h", 
    //         axi_if.awvalid, axi_if.awready, axi_if.awaddr);
    //     $display("  W:  valid=%b ready=%b last=%b", 
    //         axi_if.wvalid, axi_if.wready, axi_if.wlast);
    //     $display("  B:  valid=%b ready=%b", 
    //         axi_if.bvalid, axi_if.bready);
    //     $display("  AR: valid=%b ready=%b addr=0x%h", 
    //         axi_if.arvalid, axi_if.arready, axi_if.araddr);
    //     $display("  R:  valid=%b ready=%b last=%b", 
    //         axi_if.rvalid, axi_if.rready, axi_if.rlast);
    //     $display("");
    //     $display("MEMORY INTERFACE:");
    //     $display("  Req: valid=%b ready=%b rw=%b addr=0x%h", 
    //         mem_if.req_valid, mem_if.req_ready, mem_if.req_rw, mem_if.req_addr);
    //     $display("  Rsp: valid=%b ready=%b", 
    //         mem_if.rsp_valid, mem_if.rsp_ready);
    //     $display("");
    //     $display("DCR INTERFACE:");
    //     $display("  Write: valid=%b addr=0x%h data=0x%h", 
    //         dcr_if.wr_valid, dcr_if.wr_addr, dcr_if.wr_data);
    //     $display("================================================================================");
    // endtask

    //==========================================================================
    // DEBUG: Interface Status Display
    //==========================================================================
    
    task automatic print_status();
        real ipc_calculated;
        
        $display("================================================================================");
        $display("VORTEX INTERFACE STATUS @ %0t", $time);
        $display("================================================================================");
        $display("Clock: %b | Reset: %b", clk, reset_n);
        $display("");
        $display("STATUS INTERFACE:");
        $display("  Busy:   %b", status_if.busy);
        $display("  Idle:   %b", status_if.idle);
        $display("  ebreak: %b", status_if.ebreak_detected);
        $display("  Cycles: %0d", status_if.cycle_count);
        $display("  Instrs: %0d", status_if.instr_count);
        
        // Calculate IPC (instead of reading non-existent status_if.ipc)
        if (status_if.cycle_count > 0 && status_if.instr_count > 0) begin
            ipc_calculated = real'(status_if.instr_count) / real'(status_if.cycle_count);
            $display("  IPC:    %.4f (calculated)", ipc_calculated);
        end else begin
            $display("  IPC:    N/A");
        end
        
        $display("");
        $display("AXI INTERFACE:");
        $display("  AW: valid=%b ready=%b addr=0x%h", 
            axi_if.awvalid, axi_if.awready, axi_if.awaddr);
        $display("  W:  valid=%b ready=%b last=%b", 
            axi_if.wvalid, axi_if.wready, axi_if.wlast);
        $display("  B:  valid=%b ready=%b", 
            axi_if.bvalid, axi_if.bready);
        $display("  AR: valid=%b ready=%b addr=0x%h", 
            axi_if.arvalid, axi_if.arready, axi_if.araddr);
        $display("  R:  valid=%b ready=%b last=%b", 
            axi_if.rvalid, axi_if.rready, axi_if.rlast);
        $display("");
        $display("MEMORY INTERFACE:");
        $display("  Req: valid=%b ready=%b rw=%b addr=0x%h", 
            mem_if.req_valid, mem_if.req_ready, mem_if.req_rw, mem_if.req_addr);
        $display("  Rsp: valid=%b ready=%b", 
            mem_if.rsp_valid, mem_if.rsp_ready);
        $display("");
        $display("DCR INTERFACE:");
        $display("  Write: valid=%b addr=0x%h data=0x%h", 
            dcr_if.wr_valid, dcr_if.wr_addr, dcr_if.wr_data);
        $display("================================================================================");
    endtask



    
    // Automatic status printing on significant events
    always @(posedge clk) begin
        if (reset_n) begin
            // Print on ebreak
            if (status_if.ebreak_detected) begin
                $display("");
                print_status();
            end
        end
    end

    //==========================================================================
    // INITIAL BLOCK
    //==========================================================================
    
    initial begin
        $display("================================================================================");
        $display("VORTEX INTERFACE INITIALIZED");
        $display("================================================================================");
        $display("Sub-interfaces instantiated:");
        $display("  - vortex_axi_if    (AXI4 memory interface)");
        $display("  - vortex_mem_if    (Custom memory interface)");
        $display("  - vortex_dcr_if    (Device Configuration Registers)");
        $display("  - vortex_status_if (Status and performance monitoring)");
        $display("All interfaces use clocking blocks for race-free operation");
        $display("================================================================================");
    end

endinterface : vortex_if

`endif // VORTEX_IF_SV