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
// Sub-interface sizing comes exclusively from vortex_config_pkg parameters,
// which are the single source of truth derived from VX_define.vh:
//
//   AXI_ADDR_W = vortex_config_pkg::AXI_ADDR_WIDTH  (32 RV32, 48 RV64)
//   AXI_DATA_W = vortex_config_pkg::AXI_DATA_WIDTH  (512, fixed)
//   AXI_ID_W   = vortex_config_pkg::AXI_ID_WIDTH    (8,   fixed = VX_MEM_TAG_WIDTH)
//
// Usage in testbench:
//   vortex_if vif(clk, reset_n);
//
//   // Access sub-interfaces:
//   vif.axi_if.awvalid
//   vif.mem_if.mem_responder_cb.req_valid[0]
//   vif.dcr_if.wr_valid
//   vif.status_if.busy
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_IF_SV
`define VORTEX_IF_SV

// Pull in RTL defines only for RTL-side macros that the DUT uses
`include "VX_define.vh"

// Import vortex_config_pkg — single source of truth for all TB widths
import vortex_config_pkg::*;

interface vortex_if (
    input logic clk,
    input logic reset_n
);

    //==========================================================================
    // SUB-INTERFACE INSTANTIATION
    // Parameters sourced from vortex_config_pkg, NOT from raw RTL macros.
    //   AXI_ID_WIDTH   = 8   (VX_MEM_TAG_WIDTH = L3_MEM_TAG_WIDTH)
    //   AXI_DATA_WIDTH = 512 (VX_MEM_DATA_WIDTH = L3_LINE_SIZE * 8)
    //   AXI_ADDR_WIDTH = 32 or 48 (byte address, XLEN-dependent)
    //==========================================================================

    // AXI4 interface (for AXI wrapper version)
    vortex_axi_if #(
        .ADDR_WIDTH (vortex_config_pkg::AXI_ADDR_WIDTH),   // 32 RV32, 48 RV64
        .DATA_WIDTH (vortex_config_pkg::AXI_DATA_WIDTH),   // 512 (fixed)
        .ID_WIDTH   (vortex_config_pkg::AXI_ID_WIDTH)      // 8   (fixed)
    ) axi_if (.clk(clk), .reset_n(reset_n));

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

    modport master (
        clocking master_cb,
        input clk, reset_n
    );

    modport monitor (
        clocking monitor_cb,
        input clk, reset_n
    );

    //==========================================================================
    // CONVENIENCE TASKS
    //==========================================================================

    // Wait for reset completion.
    // FIX: level-check first — if reset is already deasserted, skip the wait.
    // The original wait(reset_n==0) hangs forever if called post-reset.
    task automatic wait_reset_done();
        if (reset_n === 1'b0) wait(reset_n === 1'b1);
        repeat(5) @(posedge clk);
        $display("[VORTEX_IF @ %0t] Reset sequence complete", $time);
    endtask

    // Wait for system idle
    task automatic wait_system_idle();
        @(posedge clk);
        wait(status_if.busy == 1'b0);
        $display("[VORTEX_IF @ %0t] System idle", $time);
    endtask

    // Wait for kernel completion with timeout
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

    // DCR writes should only happen when system is idle or during config phase.
    // Note: DCR writes DURING reset (before reset_n=1) are the normal startup
    // sequence — the assertion is disabled during reset via 'disable iff (!reset_n)'.
    // In practice the RTL initializes DCRs during reset; the TB DCR sequence
    // also runs during reset, so this assertion correctly fires only post-reset.
    property dcr_write_timing_p;
        @(posedge clk) disable iff (!reset_n)
        dcr_if.wr_valid |-> !status_if.busy;
    endproperty

    // Reset behavior: AXI/MEM valid signals should clear after reset deassertion.
    // DCR wr_valid is excluded — TB DCR driver runs during reset and deasserts
    // naturally; the assertion would false-fire on the post-reset idle state.
    property reset_clears_valids_p;
        @(posedge clk)
        $fell(reset_n) |=> ##[1:10] (
            !axi_if.awvalid && !axi_if.wvalid && !axi_if.arvalid &&
            !mem_if.req_valid[0]
        );
    endproperty

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

        system_state_cp: coverpoint {status_if.busy, status_if.idle} {
            bins idle         = {2'b01};
            bins busy         = {2'b10};
            bins idle_to_busy = (2'b01 => 2'b10);
            bins busy_to_idle = (2'b10 => 2'b01);
        }

        axi_usage_cp: coverpoint {axi_if.awvalid, axi_if.arvalid} {
            bins no_access    = {2'b00};
            bins write_only   = {2'b10};
            bins read_only    = {2'b01};
            bins simultaneous = {2'b11};
        }

        mem_usage_cp: coverpoint {mem_if.req_valid[0], mem_if.req_rw[0]} {
            bins idle  = {2'b00};
            bins read  = {2'b10};
            bins write = {2'b11};
        }

        dcr_activity_cp: coverpoint dcr_if.wr_valid {
            bins inactive = {0};
            bins active   = {1};
        }

        system_axi_cross: cross system_state_cp, axi_usage_cp;
        system_mem_cross: cross system_state_cp, mem_usage_cp;

    endgroup

    system_cg sys_cov = new();

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
            mem_if.req_valid[0], mem_if.req_ready[0],
            mem_if.req_rw[0], mem_if.req_addr[0]);
        $display("  Rsp: valid=%b ready=%b",
            mem_if.rsp_valid[0], mem_if.rsp_ready[0]);
        $display("");
        $display("DCR INTERFACE:");
        $display("  Write: valid=%b addr=0x%h data=0x%h",
            dcr_if.wr_valid, dcr_if.wr_addr, dcr_if.wr_data);
        $display("================================================================================");
    endtask

    // Automatic status printing on ebreak
    always @(posedge clk) begin
        if (reset_n) begin
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
        $display("  - vortex_axi_if    ADDR=%0d DATA=%0d ID=%0d",
            vortex_config_pkg::AXI_ADDR_WIDTH,
            vortex_config_pkg::AXI_DATA_WIDTH,
            vortex_config_pkg::AXI_ID_WIDTH);
        $display("  - vortex_mem_if    ADDR=%0d DATA=%0d TAG=%0d",
            vortex_config_pkg::VX_MEM_ADDR_WIDTH,
            vortex_config_pkg::VX_MEM_DATA_WIDTH,
            vortex_config_pkg::VX_MEM_TAG_WIDTH);
        $display("  - vortex_dcr_if    ADDR=%0d DATA=%0d",
            vortex_config_pkg::VX_DCR_ADDR_WIDTH,
            vortex_config_pkg::VX_DCR_DATA_WIDTH);
        $display("  - vortex_status_if (Status and performance monitoring)");
        $display("All interfaces use clocking blocks for race-free operation");
        $display("================================================================================");
    end

endinterface : vortex_if

`endif // VORTEX_IF_SV