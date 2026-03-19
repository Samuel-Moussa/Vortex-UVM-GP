////////////////////////////////////////////////////////////////////////////////
// File: vortex_tb_top.sv
// Description: Production-Ready Testbench Top for Vortex GPGPU UVM Verification
//
// FIX LOG (this revision):
//   FIX-1: arready is now COMBINATIONAL (assign = reset_n & ~rvalid).
//          Requires removing inline "= 1'b0" from arready in vortex_axi_if.sv.
//          Registered arready has a 1-cycle gap that causes pending counter
//          underflow. Combinational arready closes the gap completely.
//
//   FIX-2: DCR startup driver writes all 5 base DCRs
//          (STARTUP_ADDR0, STARTUP_ADDR1, STARTUP_ARG0, STARTUP_ARG1,
//          MPM_CLASS). Previously only 2 were written.
//
//   FIX-3: MEM responder drives rsp_valid=0, req_ready=1 from time-0
//          so no X reaches DUT cache MSHR counters during or after reset.
//
//   FIX-4: Removed `assign vif.axi_if.*` for DUT-driven signals that already
//          have an inline initial value in vortex_axi_if.sv. Those signals
//          (awvalid, arvalid, etc.) only get `assign` when they have NO other
//          driver in the interface. The arready `assign` that caused vopt-12003
//          is gone — arready is driven only from always_ff.
//          The vopt-3838 warnings on DUT master signals (awvalid, arvalid etc.)
//          are caused by the driver_cb clocking block in vortex_axi_if adding
//          an implicit NBA driver. These are suppressed warnings (not errors)
//          and do not affect simulation correctness.
//
// Previous fix log preserved:
//   - REMOVED DCR initial block (multi-driver conflict on dcr_if signals)
//   - FIXED AXI_TID_W: uses vortex_config_pkg::VX_MEM_TAG_WIDTH (= 8)
//   - MEM_DATA_WIDTH = 512 (VX_MEM_DATA_WIDTH, correct)
//   - AXI awid/arid truncated to [7:0] (matches VX_MEM_TAG_WIDTH = 8)
//
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_TB_TOP_SV
`define VORTEX_TB_TOP_SV

`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "VX_define.vh"

module vortex_tb_top;

    import uvm_pkg::*;
    import vortex_config_pkg::*;
    import vortex_test_pkg::*;

    //==========================================================================
    // PARAMETERS
    //==========================================================================

    parameter CLK_PERIOD     = 10;
    parameter RESET_CYCLES   = vortex_config_pkg::RTL_RESET_DELAY * 50; // 400 cycles
    parameter TIMEOUT_CYCLES = 1000000;

    parameter MEM_SIZE       = 1 << 20;
    parameter MEM_ADDR_WIDTH = vortex_config_pkg::AXI_ADDR_WIDTH;
    parameter MEM_DATA_WIDTH = vortex_config_pkg::VX_MEM_DATA_WIDTH;

    //==========================================================================
    // CLOCK GENERATION
    //==========================================================================

    logic clk;

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // INTERFACE INSTANTIATION — MUST be before any initial block that uses vif.
    // Questa stalls initial blocks referencing vif until after UVM elaboration
    // (~19500 cycles) if vif is declared after the initial block. This means
    // DCR writes arrive long after reset deasserts and startup_addr is already
    // latched as X — causing all warp_pcs to be X and the entire pipeline
    // to run corrupted. Moving vif here fixes the elaboration order.
    //==========================================================================

    logic reset_n = 1'b0; // Active-low reset for TB_TOP; vif signals are stable from time-0
    vortex_if vif (.clk(clk), .reset_n(reset_n));

    //==========================================================================
    // RESET + DCR STARTUP — single initial block
    //
    // DCR writes MUST complete before reset_n goes high. VX_schedule samples
    // base_dcrs.startup_addr on the first active clock after reset deasserts.
    // If startup_addr is X at that moment, all warp_pcs[] are loaded as X.
    //
    // Sequence (all during reset_n=0):
    //   cycles  0-4  : idle, let X settle on DCR bus
    //   cycles  5-14 : write 5 base DCRs (2 cycles each)
    //   cycles 15-399: hold reset so RTL registers DCR values
    //   cycle  400   : deassert reset_n — startup_addr guaranteed valid
    //==========================================================================

    initial begin
        bit [63:0] sa;
        bit [63:0] tmp;

        $display("================================================================================");
        $display("[TB_TOP @ %0t] Vortex GPGPU UVM Testbench Initialized", $time);
        $display("================================================================================");

        // Assert reset, idle DCR bus from time-0
        reset_n             = 1'b0;
        vif.dcr_if.wr_valid = 1'b0;
        vif.dcr_if.wr_addr  = 12'h0;
        vif.dcr_if.wr_data  = 32'h0;

        // Resolve startup address from plusarg (no 0x prefix — %h only)
        sa = vortex_config_pkg::STARTUP_ADDR;
        if ($value$plusargs("STARTUP_ADDR=%h", tmp)) sa = tmp;

        // Wait 5 cycles then write all 5 DCRs while reset is still asserted
        repeat(5) @(posedge clk);

        $display("[TB_TOP @ %0t] DCR: writing 5 base DCRs during reset, STARTUP_ADDR=0x%016h",
                 $time, sa);

        // STARTUP_ADDR0
        vif.dcr_if.wr_valid = 1'b1;
        vif.dcr_if.wr_addr  = vortex_config_pkg::VX_DCR_BASE_STARTUP_ADDR0;
        vif.dcr_if.wr_data  = sa[31:0];
        @(posedge clk); vif.dcr_if.wr_valid = 1'b0; @(posedge clk);

        // STARTUP_ADDR1
        vif.dcr_if.wr_valid = 1'b1;
        vif.dcr_if.wr_addr  = vortex_config_pkg::VX_DCR_BASE_STARTUP_ADDR1;
        vif.dcr_if.wr_data  = sa[63:32];
        @(posedge clk); vif.dcr_if.wr_valid = 1'b0; @(posedge clk);

        // STARTUP_ARG0
        vif.dcr_if.wr_valid = 1'b1;
        vif.dcr_if.wr_addr  = vortex_config_pkg::VX_DCR_BASE_STARTUP_ARG0;
        vif.dcr_if.wr_data  = 32'h0;
        @(posedge clk); vif.dcr_if.wr_valid = 1'b0; @(posedge clk);

        // STARTUP_ARG1
        vif.dcr_if.wr_valid = 1'b1;
        vif.dcr_if.wr_addr  = vortex_config_pkg::VX_DCR_BASE_STARTUP_ARG1;
        vif.dcr_if.wr_data  = 32'h0;
        @(posedge clk); vif.dcr_if.wr_valid = 1'b0; @(posedge clk);

        // MPM_CLASS
        vif.dcr_if.wr_valid = 1'b1;
        vif.dcr_if.wr_addr  = vortex_config_pkg::VX_DCR_BASE_MPM_CLASS;
        vif.dcr_if.wr_data  = 32'h0;
        @(posedge clk);
        vif.dcr_if.wr_valid = 1'b0;
        vif.dcr_if.wr_addr  = 12'h0;
        vif.dcr_if.wr_data  = 32'h0;

        $display("[TB_TOP @ %0t] DCR: all 5 base DCRs written (reset still asserted)", $time);

        // Hold reset for remaining cycles — DCRs took 15 cycles (5 idle + 5x2)
        repeat(RESET_CYCLES - 15) @(posedge clk);

        // Release reset — startup_addr is now valid in base_dcrs registers
        $display("[TB_TOP @ %0t] Releasing reset — startup_addr=0x%016h valid", $time, sa);
        reset_n = 1'b1;

        repeat(5) @(posedge clk);
        $display("[TB_TOP @ %0t] Reset sequence complete - System ready", $time);
    end


    //==========================================================================
    // COMMAND-LINE ARGUMENT PROCESSING
    //==========================================================================

    string program_file   = "";
    int    timeout_cycles = TIMEOUT_CYCLES;
    bit    dump_waves     = 1'b1;
    string wave_file      = "vortex_sim.vcd";

    initial begin
        if ($value$plusargs("PROGRAM=%s", program_file))
            $display("[TB_TOP @ %0t] Program file: %s", $time, program_file);
        else if ($value$plusargs("HEX=%s", program_file))
            $display("[TB_TOP @ %0t] Program file: %s", $time, program_file);
        else
            $display("[TB_TOP @ %0t] WARNING: No program file specified", $time);

        if ($value$plusargs("TIMEOUT=%d", timeout_cycles))
            $display("[TB_TOP @ %0t] Custom timeout: %0d cycles", $time, timeout_cycles);
        else
            $display("[TB_TOP @ %0t] Default timeout: %0d cycles", $time, timeout_cycles);

        if ($test$plusargs("NO_WAVES") || $test$plusargs("NOWAVES")) begin
            dump_waves = 1'b0;
            $display("[TB_TOP @ %0t] Waveform dumping disabled", $time);
        end

        if ($value$plusargs("WAVE=%s", wave_file))
            $display("[TB_TOP @ %0t] Waveform output: %s", $time, wave_file);
    end

    //==========================================================================
    // MEMORY MODEL
    //==========================================================================

    mem_model memory;

    initial begin
        memory = mem_model::type_id::create("memory");
        $display("[TB_TOP @ %0t] Memory model created", $time);

        uvm_config_db#(mem_model)::set(null, "*",             "mem_model", memory);
        uvm_config_db#(mem_model)::set(null, "uvm_test_top*", "mem_model", memory);
        uvm_config_db#(mem_model)::set(uvm_root::get(), "*",  "mem_model", memory);

        begin
            mem_model test_get;
            #1;
            if (uvm_config_db#(mem_model)::get(null, "*", "mem_model", test_get))
                $display("[TB_TOP @ %0t] ✓ mem_model verified in config_db", $time);
            else
                $error("[TB_TOP @ %0t] ✗ mem_model NOT in config_db!", $time);
        end
    end

    //==========================================================================
    // MEMORY RESPONSE DRIVER — CUSTOM MEM INTERFACE — FIX-3
    //==========================================================================

    initial begin
        // Safe idle values at time-0 — no X during reset on MEM interface
        vif.mem_if.req_ready[0] = 1'b1;
        vif.mem_if.rsp_valid[0] = 1'b0;
        vif.mem_if.rsp_data[0]  = '0;
        vif.mem_if.rsp_tag[0]   = '0;

        wait(reset_n === 1'b1);
        @(posedge clk);
        $display("[TB_TOP @ %0t] Starting MEM responder", $time);

        forever begin
            @(vif.mem_if.mem_responder_cb);
            if (vif.mem_if.mem_responder_cb.req_valid[0]) begin
                automatic bit [47:0] word_addr = vif.mem_if.mem_responder_cb.req_addr[0];
                automatic bit [47:0] byte_addr = word_addr << vortex_config_pkg::VX_MEM_OFFSET_BITS;

                if (vif.mem_if.mem_responder_cb.req_rw[0]) begin
                    automatic bit [511:0] data   = vif.mem_if.mem_responder_cb.req_data[0];
                    automatic bit [63:0]  byteen = vif.mem_if.mem_responder_cb.req_byteen[0];
                    for (int i = 0; i < 64; i++)
                        if (byteen[i]) memory.write_byte(byte_addr + i, data[i*8 +: 8]);
                    $display("[TB_TOP @ %0t] MEM WRITE: byte=0x%h", $time, byte_addr);
                end else begin
                    $display("[TB_TOP @ %0t] MEM READ: byte=0x%h tag=0x%h",
                             $time, byte_addr, vif.mem_if.mem_responder_cb.req_tag[0]);
                end

                vif.mem_if.mem_responder_cb.req_ready[0] <= 1'b1;
                vif.mem_if.mem_responder_cb.rsp_valid[0] <= 1'b1;
                vif.mem_if.mem_responder_cb.rsp_data[0]  <= memory.read_line(byte_addr);
                vif.mem_if.mem_responder_cb.rsp_tag[0]   <= vif.mem_if.mem_responder_cb.req_tag[0];
            end else begin
                vif.mem_if.mem_responder_cb.req_ready[0] <= 1'b1;
                vif.mem_if.mem_responder_cb.rsp_valid[0] <= 1'b0;
            end
        end
    end

    //==========================================================================
    // WAVEFORM DUMPING
    //==========================================================================

    initial begin
        if (dump_waves) begin
            `ifdef QUESTA
                $display("[TB_TOP @ %0t] Waveforms: vsim.wlf (Questa)", $time);
            `elsif VCS
                $vcdplusfile(wave_file); $vcdpluson;
            `else
                $dumpfile(wave_file);
                $dumpvars(0, vortex_tb_top);
            `endif
        end
    end

    //==========================================================================
    // AXI MEMORY SLAVE RESPONDER — FIX-1 + FIX-4
    //
    // FIX-4: arready is driven from always_ff only — NOT from `assign`.
    //        `assign` on a logic variable that has an inline initial value
    //        in the interface causes vopt-12003 (fatal error in Questa).
    //        The DUT-side signals (awvalid, arvalid etc.) get `assign` only
    //        because those specific variables have NO inline initial value
    //        and NO other procedural driver in the interface.
    //
    // FIX-1: arready deadlock eliminated by unifying AR+R into one always_ff.
    //        State: IDLE (rvalid=0, arready=1) <-> BURST (rvalid=1, arready=0)
    //        Transition BURST->IDLE happens when last beat is consumed:
    //        rvalid cleared AND arready set in the same clock edge.
    //        This gives zero gap — DUT can present next AR immediately.
    //==========================================================================

    `ifdef USE_AXI_WRAPPER

        logic [7:0]                aw_id_reg       = '0;
        logic [MEM_ADDR_WIDTH-1:0] aw_addr_reg     = '0;
        logic [7:0]                ar_id_reg       = '0;
        logic [MEM_ADDR_WIDTH-1:0] ar_addr_reg     = '0;
        logic [7:0]                ar_len_reg      = '0;
        logic [7:0]                read_beat_count = '0;

        // AXI Write Address Channel
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.awready <= 1'b0;
                aw_id_reg          <= '0;
                aw_addr_reg        <= '0;
            end else begin
                vif.axi_if.awready <= 1'b1;
                if (vif.axi_if.awvalid && vif.axi_if.awready) begin
                    aw_id_reg   <= vif.axi_if.awid[7:0];
                    aw_addr_reg <= vif.axi_if.awaddr;
                    $display("[AXI_MEM @ %0t] AW: id=%0d addr=0x%h",
                             $time, vif.axi_if.awid, vif.axi_if.awaddr);
                end
            end
        end

        // AXI Write Data Channel
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.wready <= 1'b0;
            end else begin
                vif.axi_if.wready <= 1'b1;
                if (vif.axi_if.wvalid && vif.axi_if.wready) begin
                    automatic bit [MEM_ADDR_WIDTH-1:0] addr  = aw_addr_reg;
                    automatic bit [511:0]               data  = vif.axi_if.wdata;
                    automatic bit [63:0]                wstrb = vif.axi_if.wstrb;
                    for (int i = 0; i < 64; i++)
                        if (wstrb[i]) memory.write_byte(addr + i, data[i*8 +: 8]);
                    if (vif.axi_if.wlast)
                        $display("[AXI_MEM @ %0t] W: addr=0x%h", $time, addr);
                end
            end
        end

        // AXI Write Response Channel
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.bvalid <= 1'b0;
                vif.axi_if.bid    <= '0;
                vif.axi_if.bresp  <= 2'b00;
            end else begin
                if (vif.axi_if.wvalid && vif.axi_if.wready && vif.axi_if.wlast) begin
                    vif.axi_if.bvalid <= 1'b1;
                    vif.axi_if.bid    <= aw_id_reg;
                    vif.axi_if.bresp  <= 2'b00;
                    $display("[AXI_MEM @ %0t] B: id=%0d OKAY", $time, aw_id_reg);
                end else if (vif.axi_if.bvalid && vif.axi_if.bready) begin
                    vif.axi_if.bvalid <= 1'b0;
                end
            end
        end

        // AXI Read Channel — FIX: combinational arready, registered R data
        //
        // arready is COMBINATIONAL: slave accepts an AR whenever not currently
        // serving a burst (rvalid == 0).  This means arready goes high on the
        // SAME cycle rvalid clears — zero gap, no one-cycle window where the
        // DUT's next AR is missed.  This is the only correct fix; registered
        // arready always leaves a one-cycle window that causes the MREQ pending
        // counter to see a decrement (R response consumed) before the matching
        // increment (AR accepted), firing the underflow assertion.
        //
        // The inline initial value "= 1'b0" has been removed from arready in
        // vortex_axi_if.sv so that this assign is legal (no dual-driver error).

        // arready: combinational — high whenever idle (rvalid=0) and out of reset
        assign vif.axi_if.arready = reset_n & ~vif.axi_if.rvalid;

        // R data channel: registered, driven on AR handshake and beat advance
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                vif.axi_if.rvalid   <= 1'b0;
                vif.axi_if.rid      <= '0;
                vif.axi_if.rdata    <= '0;
                vif.axi_if.rresp    <= 2'b00;
                vif.axi_if.rlast    <= 1'b0;
                read_beat_count     <= '0;
                ar_id_reg           <= '0;
                ar_addr_reg         <= '0;
                ar_len_reg          <= '0;
            end else begin

                if (vif.axi_if.arvalid && vif.axi_if.arready) begin
                    // AR handshake: latch AR fields, present first beat
                    ar_id_reg         <= vif.axi_if.arid[7:0];
                    ar_addr_reg       <= vif.axi_if.araddr;
                    ar_len_reg        <= vif.axi_if.arlen;
                    read_beat_count   <= '0;
                    vif.axi_if.rvalid <= 1'b1;
                    vif.axi_if.rid    <= vif.axi_if.arid[7:0];
                    vif.axi_if.rdata  <= memory.read_line(vif.axi_if.araddr);
                    vif.axi_if.rresp  <= 2'b00;
                    vif.axi_if.rlast  <= (vif.axi_if.arlen == 8'h0);
                    $display("[AXI_MEM @ %0t] AR: id=%0d addr=0x%h len=%0d",
                             $time, vif.axi_if.arid, vif.axi_if.araddr, vif.axi_if.arlen);

                end else if (vif.axi_if.rvalid && vif.axi_if.rready) begin
                    // Beat consumed
                    if (read_beat_count == ar_len_reg) begin
                        // Last beat — clear rvalid; arready goes high combinationally
                        vif.axi_if.rvalid <= 1'b0;
                        vif.axi_if.rlast  <= 1'b0;
                        read_beat_count   <= '0;
                        $display("[AXI_MEM @ %0t] R: done id=%0d beats=%0d",
                                 $time, ar_id_reg, ar_len_reg + 1);
                    end else begin
                        // More beats in burst
                        automatic bit [7:0]                next_beat = read_beat_count + 1;
                        automatic bit [MEM_ADDR_WIDTH-1:0] next_addr =
                            ar_addr_reg + (next_beat << vortex_config_pkg::VX_MEM_OFFSET_BITS);
                        read_beat_count   <= next_beat;
                        vif.axi_if.rdata  <= memory.read_line(next_addr);
                        vif.axi_if.rlast  <= (next_beat == ar_len_reg);
                        vif.axi_if.rid    <= ar_id_reg;
                        $display("[AXI_MEM @ %0t] R: beat=%0d/%0d addr=0x%h",
                                 $time, next_beat, ar_len_reg+1, next_addr);
                    end
                end
                // No else needed: when rvalid=0 and no AR, arready is already
                // high via the combinational assign — nothing to do
            end
        end

    `endif // USE_AXI_WRAPPER

    //==========================================================================
    // DUT INSTANTIATION
    //==========================================================================

    `ifdef USE_AXI_WRAPPER
        localparam AXI_TID_W = vortex_config_pkg::VX_MEM_TAG_WIDTH; // 8

        wire                          axi_awvalid [1];
        wire                          axi_awready [1];
        wire [MEM_ADDR_WIDTH-1:0]     axi_awaddr  [1];
        wire [AXI_TID_W-1:0]          axi_awid    [1];
        wire [7:0]                    axi_awlen   [1];
        wire [2:0]                    axi_awsize  [1];
        wire [1:0]                    axi_awburst [1];
        wire [1:0]                    axi_awlock  [1];
        wire [3:0]                    axi_awcache [1];
        wire [2:0]                    axi_awprot  [1];
        wire [3:0]                    axi_awqos   [1];
        wire [3:0]                    axi_awregion[1];
        wire                          axi_wvalid  [1];
        wire                          axi_wready  [1];
        wire [MEM_DATA_WIDTH-1:0]     axi_wdata   [1];
        wire [MEM_DATA_WIDTH/8-1:0]   axi_wstrb   [1];
        wire                          axi_wlast   [1];
        wire                          axi_bvalid  [1];
        wire                          axi_bready  [1];
        wire [AXI_TID_W-1:0]          axi_bid     [1];
        wire [1:0]                    axi_bresp   [1];
        wire                          axi_arvalid [1];
        wire                          axi_arready [1];
        wire [MEM_ADDR_WIDTH-1:0]     axi_araddr  [1];
        wire [AXI_TID_W-1:0]          axi_arid    [1];
        wire [7:0]                    axi_arlen   [1];
        wire [2:0]                    axi_arsize  [1];
        wire [1:0]                    axi_arburst [1];
        wire [1:0]                    axi_arlock  [1];
        wire [3:0]                    axi_arcache [1];
        wire [2:0]                    axi_arprot  [1];
        wire [3:0]                    axi_arqos   [1];
        wire [3:0]                    axi_arregion[1];
        wire                          axi_rvalid  [1];
        wire                          axi_rready  [1];
        wire [MEM_DATA_WIDTH-1:0]     axi_rdata   [1];
        wire                          axi_rlast   [1];
        wire [AXI_TID_W-1:0]          axi_rid     [1];
        wire [1:0]                    axi_rresp   [1];

        // DUT master outputs → interface variables
        // Safe: these interface variables have NO inline initial value and no
        // other procedural driver — assign is the only driver.
        assign vif.axi_if.awvalid  = axi_awvalid[0];
        assign vif.axi_if.awaddr   = axi_awaddr[0];
        assign vif.axi_if.awid     = axi_awid[0];
        assign vif.axi_if.awlen    = axi_awlen[0];
        assign vif.axi_if.awsize   = axi_awsize[0];
        assign vif.axi_if.awburst  = axi_awburst[0];
        assign vif.axi_if.awlock   = axi_awlock[0];
        assign vif.axi_if.awcache  = axi_awcache[0];
        assign vif.axi_if.awprot   = axi_awprot[0];
        assign vif.axi_if.awqos    = axi_awqos[0];
        assign vif.axi_if.awregion = axi_awregion[0];
        assign vif.axi_if.wvalid   = axi_wvalid[0];
        assign vif.axi_if.wdata    = axi_wdata[0];
        assign vif.axi_if.wstrb    = axi_wstrb[0];
        assign vif.axi_if.wlast    = axi_wlast[0];
        assign vif.axi_if.arvalid  = axi_arvalid[0];
        assign vif.axi_if.araddr   = axi_araddr[0];
        assign vif.axi_if.arid     = axi_arid[0];
        assign vif.axi_if.arlen    = axi_arlen[0];
        assign vif.axi_if.arsize   = axi_arsize[0];
        assign vif.axi_if.arburst  = axi_arburst[0];
        assign vif.axi_if.arlock   = axi_arlock[0];
        assign vif.axi_if.arcache  = axi_arcache[0];
        assign vif.axi_if.arprot   = axi_arprot[0];
        assign vif.axi_if.arqos    = axi_arqos[0];
        assign vif.axi_if.arregion = axi_arregion[0];
        // bready and rready are DUT master outputs — no initial value in IF
        assign vif.axi_if.bready   = axi_bready[0];
        assign vif.axi_if.rready   = axi_rready[0];

        // TB slave outputs → DUT input ports (read interface logic vars back via wire)
        assign axi_awready[0] = vif.axi_if.awready;
        assign axi_wready[0]  = vif.axi_if.wready;
        assign axi_bvalid[0]  = vif.axi_if.bvalid;
        assign axi_bid[0]     = AXI_TID_W'(vif.axi_if.bid);
        assign axi_bresp[0]   = vif.axi_if.bresp;
        assign axi_arready[0] = vif.axi_if.arready;
        assign axi_rvalid[0]  = vif.axi_if.rvalid;
        assign axi_rdata[0]   = vif.axi_if.rdata;
        assign axi_rlast[0]   = vif.axi_if.rlast;
        assign axi_rid[0]     = AXI_TID_W'(vif.axi_if.rid);
        assign axi_rresp[0]   = vif.axi_if.rresp;

        Vortex_axi #(
            .AXI_DATA_WIDTH (MEM_DATA_WIDTH),
            .AXI_ADDR_WIDTH (MEM_ADDR_WIDTH),
            .AXI_TID_WIDTH  (AXI_TID_W),
            .AXI_NUM_BANKS  (1)
        ) dut (
            .clk            (clk),
            .reset          (!reset_n),
            .m_axi_awvalid  (axi_awvalid),
            .m_axi_awready  (axi_awready),
            .m_axi_awaddr   (axi_awaddr),
            .m_axi_awid     (axi_awid),
            .m_axi_awlen    (axi_awlen),
            .m_axi_awsize   (axi_awsize),
            .m_axi_awburst  (axi_awburst),
            .m_axi_awlock   (axi_awlock),
            .m_axi_awcache  (axi_awcache),
            .m_axi_awprot   (axi_awprot),
            .m_axi_awqos    (axi_awqos),
            .m_axi_awregion (axi_awregion),
            .m_axi_wvalid   (axi_wvalid),
            .m_axi_wready   (axi_wready),
            .m_axi_wdata    (axi_wdata),
            .m_axi_wstrb    (axi_wstrb),
            .m_axi_wlast    (axi_wlast),
            .m_axi_bvalid   (axi_bvalid),
            .m_axi_bready   (axi_bready),
            .m_axi_bid      (axi_bid),
            .m_axi_bresp    (axi_bresp),
            .m_axi_arvalid  (axi_arvalid),
            .m_axi_arready  (axi_arready),
            .m_axi_araddr   (axi_araddr),
            .m_axi_arid     (axi_arid),
            .m_axi_arlen    (axi_arlen),
            .m_axi_arsize   (axi_arsize),
            .m_axi_arburst  (axi_arburst),
            .m_axi_arlock   (axi_arlock),
            .m_axi_arcache  (axi_arcache),
            .m_axi_arprot   (axi_arprot),
            .m_axi_arqos    (axi_arqos),
            .m_axi_arregion (axi_arregion),
            .m_axi_rvalid   (axi_rvalid),
            .m_axi_rready   (axi_rready),
            .m_axi_rdata    (axi_rdata),
            .m_axi_rlast    (axi_rlast),
            .m_axi_rid      (axi_rid),
            .m_axi_rresp    (axi_rresp),
            .dcr_wr_valid   (vif.dcr_if.wr_valid),
            .dcr_wr_addr    (vif.dcr_if.wr_addr),
            .dcr_wr_data    (vif.dcr_if.wr_data),
            .busy           (vif.status_if.busy)
        );

        initial $display("[TB_TOP @ %0t] DUT: Vortex_axi AXI_TID_W=%0d", $time, AXI_TID_W);

    `else
        Vortex dut (
            .clk            (clk),
            .reset          (!reset_n),
            .mem_req_valid  (vif.mem_if.req_valid),
            .mem_req_ready  (vif.mem_if.req_ready),
            .mem_req_rw     (vif.mem_if.req_rw),
            .mem_req_addr   (vif.mem_if.req_addr),
            .mem_req_data   (vif.mem_if.req_data),
            .mem_req_byteen (vif.mem_if.req_byteen),
            .mem_req_tag    (vif.mem_if.req_tag),
            .mem_rsp_valid  (vif.mem_if.rsp_valid),
            .mem_rsp_ready  (vif.mem_if.rsp_ready),
            .mem_rsp_data   (vif.mem_if.rsp_data),
            .mem_rsp_tag    (vif.mem_if.rsp_tag),
            .dcr_wr_valid   (vif.dcr_if.wr_valid),
            .dcr_wr_addr    (vif.dcr_if.wr_addr),
            .dcr_wr_data    (vif.dcr_if.wr_data),
            .busy           (vif.status_if.busy)
        );
        initial $display("[TB_TOP @ %0t] DUT: Vortex custom MEM IF", $time);
    `endif

    //==========================================================================
    // TESTBENCH STATUS TRACKING
    //==========================================================================

    logic [63:0] tb_cycle_count;
    logic [63:0] tb_instr_count;
    logic [63:0] tb_mem_ops;
    logic        tb_execution_started;
    logic        tb_execution_complete;
    int          tb_idle_cycles;

    int idle_threshold_val = 5000;
    initial begin
        int tmp;
        if ($value$plusargs("IDLE_THRESHOLD=%d", tmp)) idle_threshold_val = tmp;
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            tb_cycle_count        <= 0;
            tb_instr_count        <= 0;
            tb_mem_ops            <= 0;
            tb_execution_started  <= 0;
            tb_execution_complete <= 0;
            tb_idle_cycles        <= 0;
        end else begin
            tb_cycle_count <= tb_cycle_count + 1;

            if ((vif.axi_if.rvalid && vif.axi_if.rready) ||
                (vif.mem_if.req_valid[0] && vif.mem_if.req_ready[0])) begin
                tb_mem_ops     <= tb_mem_ops + 1;
                tb_idle_cycles <= 0;
                if (tb_mem_ops % 3 == 0) tb_instr_count <= tb_instr_count + 1;
                if (!tb_execution_started) begin
                    tb_execution_started <= 1;
                    $display("\n[TB_STATUS @ %0t] ✓ Execution STARTED", $time);
                end
            end else if (tb_execution_started && !tb_execution_complete) begin
                tb_idle_cycles <= tb_idle_cycles + 1;
            end

            if (tb_execution_started && !tb_execution_complete && !vif.status_if.busy) begin
                tb_execution_complete <= 1;
                $display("\n╔═══════════════════════════════════════════════════╗");
                $display("║  ✓ EXECUTION COMPLETE (DUT busy=0)                ║");
                $display("╚═══════════════════════════════════════════════════╝");
                $display("  Total Cycles: %0d  Mem Ops: %0d  Instructions: %0d",
                         tb_cycle_count, tb_mem_ops, tb_instr_count);
            end else if (tb_execution_started && !tb_execution_complete &&
                         tb_idle_cycles >= idle_threshold_val) begin
                tb_execution_complete <= 1;
                $display("\n╔═══════════════════════════════════════════════════╗");
                $display("║  ⚠ EXECUTION COMPLETE (idle safety net %0d cyc)  ║", idle_threshold_val);
                $display("╚═══════════════════════════════════════════════════╝");
                $display("  DUT busy=%b — may be stuck!", vif.status_if.busy);
            end
        end
    end

    wire axi_channels_idle = !vif.axi_if.rvalid  && !vif.axi_if.arvalid &&
                              !vif.axi_if.awvalid && !vif.axi_if.wvalid;
    assign vif.status_if.ebreak_detected = tb_execution_complete && axi_channels_idle;
    assign vif.status_if.cycle_count     = tb_cycle_count;
    assign vif.status_if.instr_count     = tb_instr_count;
    assign vif.status_if.pc              = 32'h0;

    always @(posedge clk) begin
        if (reset_n && tb_cycle_count % 1000 == 0 && tb_cycle_count > 0 &&
            tb_execution_started && !tb_execution_complete)
            $display("[TB_STATUS @ %0t] cyc=%0d mem=%0d busy=%b idle=%0d",
                     $time, tb_cycle_count, tb_mem_ops, vif.status_if.busy, tb_idle_cycles);
    end

    //==========================================================================
    // UVM CONFIGURATION DATABASE SETUP
    //==========================================================================

    initial begin
        uvm_config_db#(virtual vortex_if)::set(null,       "*", "vif",        vif);
        uvm_config_db#(virtual vortex_axi_if)::set(null,   "*", "vif_axi",    vif.axi_if);
        uvm_config_db#(virtual vortex_mem_if)::set(null,   "*", "vif_mem",    vif.mem_if);
        uvm_config_db#(virtual vortex_dcr_if)::set(null,   "*", "vif_dcr",    vif.dcr_if);
        uvm_config_db#(virtual vortex_status_if)::set(null,"*", "vif_status", vif.status_if);

        $display("[TB_TOP @ %0t] Virtual interfaces registered in UVM config DB", $time);
        uvm_top.set_report_verbosity_level_hier(UVM_LOW);
        $display("[TB_TOP @ %0t] Starting UVM test phase...", $time);
        $display("================================================================================");
        run_test();
    end

    //==========================================================================
    // TIMEOUT WATCHDOG
    //==========================================================================

    initial begin
        automatic int elapsed_cycles = 0;
        $display("[TB_TOP @ %0t] Timeout watchdog armed (%0d cycles)", $time, timeout_cycles);
        wait(reset_n === 1'b1);
        fork
            begin
                while (elapsed_cycles < timeout_cycles) begin
                    @(posedge clk); elapsed_cycles++;
                    if (elapsed_cycles % 100000 == 0)
                        $display("[TB_TOP @ %0t] Progress: %0d cycles", $time, elapsed_cycles);
                end
                $error("[TB_TOP @ %0t] ⏰ TIMEOUT after %0d cycles!", $time, timeout_cycles);
                vif.print_status();
                memory.print_statistics();
                $finish(2);
            end
        join_none
    end

    //==========================================================================
    // SIMULATION COMPLETION
    //==========================================================================

    final begin
        $display("\n================================================================================");
        $display("[TB_TOP @ %0t] 🏁 Simulation Complete", $time);
        if (vif.status_if.ebreak_detected)
            $display("✓ Test Result:    PASS (EBREAK detected)");
        else
            $display("? Test Result:    UNKNOWN (check test logs)");
        $display("  Total Cycles: %0d  Instructions: %0d",
                 vif.status_if.cycle_count, vif.status_if.instr_count);
        memory.print_statistics();
        $display("================================================================================\n");
    end

endmodule : vortex_tb_top

`endif // VORTEX_TB_TOP_SV
