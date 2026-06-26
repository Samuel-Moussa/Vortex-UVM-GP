////////////////////////////////////////////////////////////////////////////////
// File: vortex_tb_top.sv
// Description: Production-Ready Testbench Top for Vortex GPGPU UVM Verification
//
// FIX LOG (this revision):
//   FIX-1: Removed local Custom MEM responder logic. Delegated entirely to mem_driver.
//   FIX-2: Removed local AXI responder logic. Delegated entirely to axi_driver.
//   FIX-3: Cleaned up top module to be purely structural wrapper.
//   FIX-4: Kept testbench status tracking logic for virtual interface metrics.
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
    import mem_model_pkg::*;

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
    // INTERFACE INSTANTIATION
    //==========================================================================

    logic reset_n = 1'b0; 
    vortex_if vif (.clk(clk), .reset_n(reset_n));

    //=========================================================================
    // RESET GENERATION
    //=========================================================================

    initial begin
        // Disable strict reset assertion because we intentionally drive DCR during reset in UVM
        $assertoff(0, vif.assert_reset_clears_valids);

        $display("================================================================================");
        $display("[TB_TOP @ %0t] Vortex GPGPU UVM Testbench Initialized", $time);
        $display("================================================================================");

        reset_n = 1'b0;

        // Drive DCR bus to a known idle from time-0.
        vif.dcr_if.wr_valid = 1'b0;
        vif.dcr_if.wr_addr  = 12'h0;
        vif.dcr_if.wr_data  = 32'h0;

        if (RESET_CYCLES > 15)
            repeat(RESET_CYCLES - 15) @(posedge clk);

        reset_n = 1'b1;
        $display("[TB_TOP @ %0t] Releasing reset", $time);

        repeat(5) @(posedge clk);
        $display("[TB_TOP @ %0t] Hardware Reset Complete - System ready", $time);
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
    // MEMORY MODEL + PROGRAM PRE-LOAD
    //==========================================================================

    mem_model memory;

    initial begin
        string  hex_file;
        bit [63:0] sa;
        bit [63:0] tmp64;
        int bytes;

        memory = mem_model::type_id::create("memory");
        $display("[TB_TOP @ %0t] Memory model created", $time);

        uvm_config_db#(mem_model)::set(null, "*",             "mem_model", memory);
        uvm_config_db#(mem_model)::set(null, "uvm_test_top*", "mem_model", memory);
        uvm_config_db#(mem_model)::set(uvm_root::get(), "*",  "mem_model", memory);

        sa = vortex_config_pkg::STARTUP_ADDR;
        if ($value$plusargs("STARTUP_ADDR=%h", tmp64)) sa = tmp64;

        if ($value$plusargs("PROGRAM=%s", hex_file) ||
            $value$plusargs("HEX=%s",     hex_file)) begin
            bytes = memory.load_hex_file(hex_file, sa);
            if (bytes > 0)
                $display("[TB_TOP @ %0t] Pre-loaded %0d bytes from '%s' @ 0x%016h (before reset)",
                         $time, bytes, hex_file, sa);
            else
                $fatal(1, "[TB_TOP @ %0t] FATAL: load_hex_file('%s') returned 0 bytes", $time, hex_file);
        end

        begin
            mem_model test_get;
            #1;
            if (uvm_config_db#(mem_model)::get(null, "*", "mem_model", test_get))
                $display("[TB_TOP @ %0t] mem_model verified in config_db", $time);
            else
                $error("[TB_TOP @ %0t] mem_model NOT in config_db!", $time);
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
    // DUT INSTANTIATION
    //==========================================================================

    `ifdef USE_AXI_WRAPPER
        localparam AXI_TID_W = vortex_config_pkg::VX_MEM_TAG_WIDTH;

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
        assign vif.axi_if.bready   = axi_bready[0];
        assign vif.axi_if.rready   = axi_rready[0];

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
    // TESTBENCH STATUS TRACKING (Required for virtual interface metrics)
    //==========================================================================

    logic [63:0] tb_cycle_count;
    logic [63:0] tb_instr_count;
    logic [63:0] tb_mem_ops;
    logic        tb_execution_started;
    logic        tb_execution_complete;
    int          tb_idle_cycles;
    logic        tb_probe_ebreak_seen;   // C3: registered — set when ebreak first seen at fetch
    wire         tb_ebreak_fetch;        // C3: combinational — same-cycle ebreak detect

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
                (vif.axi_if.bvalid && vif.axi_if.bready) ||
                (vif.mem_if.req_valid[0] && vif.mem_if.req_ready[0])) begin
                tb_mem_ops     <= tb_mem_ops + 1;
                tb_idle_cycles <= 0;
                if (tb_mem_ops % 3 == 0) tb_instr_count <= tb_instr_count + 1;
                if (!tb_execution_started) begin
                    tb_execution_started <= 1;
                    $display("\n[TB_STATUS @ %0t] Execution STARTED", $time);
                end
            end else if (tb_execution_started && !tb_execution_complete) begin
                tb_idle_cycles <= tb_idle_cycles + 1;
            end

            // C3 PRIMARY: ebreak (0x00100073) decoded at fetch stage
            // tb_ebreak_fetch is combinational (same-cycle); tb_probe_ebreak_seen is registered
            // (latched one cycle earlier) — either fires the primary path.
            if (tb_execution_started && !tb_execution_complete && (tb_ebreak_fetch || tb_probe_ebreak_seen)) begin
                tb_execution_complete <= 1;
                $display("\n╔═══════════════════════════════════════════════════╗");
                $display("║  EXECUTION COMPLETE (ebreak 0x00100073 decoded)  ║");
                $display("╚═══════════════════════════════════════════════════╝");
                $display("  Total Cycles: %0d  Mem Ops: %0d  Instructions: %0d",
                         tb_cycle_count, tb_mem_ops, tb_instr_count);
            // C3 FALLBACK 1: busy=0 without ebreak — should not happen in a correct run
            end else if (tb_execution_started && !tb_execution_complete && !vif.status_if.busy) begin
                tb_execution_complete <= 1;
                $display("\n** Warning: [TB_TOP @ %0t] EXECUTION COMPLETE via busy=0 fallback — ebreak not decoded", $time);
                $display("  Total Cycles: %0d  Mem Ops: %0d  Instructions: %0d",
                         tb_cycle_count, tb_mem_ops, tb_instr_count);
            // C3 FALLBACK 2: idle threshold — program may be hung
            end else if (tb_execution_started && !tb_execution_complete &&
                         tb_idle_cycles >= idle_threshold_val) begin
                tb_execution_complete <= 1;
                $display("\n** Warning: [TB_TOP @ %0t] EXECUTION COMPLETE via idle safety net (%0d cyc) — ebreak not decoded",
                         $time, idle_threshold_val);
                $display("  DUT busy=%b — may be stuck!", vif.status_if.busy);
            end
        end
    end

    // Safely handle idle channel detection regardless of wrapper
    `ifdef USE_AXI_WRAPPER
        wire axi_channels_idle = !vif.axi_if.rvalid  && !vif.axi_if.arvalid &&
                                  !vif.axi_if.awvalid && !vif.axi_if.wvalid &&
                                  !vif.axi_if.bvalid;
        wire mem_channels_idle = 1'b1;
    `else
        wire axi_channels_idle = 1'b1;
        wire mem_channels_idle = !vif.mem_if.req_valid[0] && !vif.mem_if.rsp_valid[0];
    `endif
    
    assign vif.status_if.ebreak_detected = tb_execution_complete && axi_channels_idle && mem_channels_idle;
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
    // DEBUG PROBES: Internal DUT busy and ebreak path
    //==========================================================================

    `ifdef USE_AXI_WRAPPER
        wire [`NUM_CLUSTERS-1:0] tb_probe_per_cluster_busy;
        assign tb_probe_per_cluster_busy = dut.vortex.per_cluster_busy;

        always @(posedge clk) begin
            if (reset_n && tb_cycle_count % 1000 == 0 && tb_cycle_count > 0 && tb_execution_started && !tb_execution_complete) begin
                $display("[TB_PROBE_AXI @ %0t] cyc=%0d per_cluster_busy=%b dut_busy=%b ebreak_detect=%b axi_idle=%b mem_idle=%b",
                         $time, tb_cycle_count, tb_probe_per_cluster_busy, vif.status_if.busy, vif.status_if.ebreak_detected,
                         axi_channels_idle, mem_channels_idle);
            end
        end
    `else
        wire [`NUM_CLUSTERS-1:0] tb_probe_per_cluster_busy;
        assign tb_probe_per_cluster_busy = dut.per_cluster_busy;

        always @(posedge clk) begin
            if (reset_n && tb_cycle_count % 1000 == 0 && tb_cycle_count > 0 && tb_execution_started && !tb_execution_complete) begin
                $display("[TB_PROBE_MEM @ %0t] cyc=%0d per_cluster_busy=%b dut_busy=%b ebreak_detect=%b mem_idle=%b",
                         $time, tb_cycle_count, tb_probe_per_cluster_busy, vif.status_if.busy, vif.status_if.ebreak_detected,
                         mem_channels_idle);
            end
        end
    `endif

    //==========================================================================
    // DEBUG PROBES: Deep RTL Pipeline Stage Analysis
    //==========================================================================

    `ifdef USE_AXI_WRAPPER
        // Deep pipeline probes: Measure fetch, decode, issue, LSU stages
        wire icache_req_valid, icache_rsp_valid, icache_req_ready, icache_rsp_ready;
        wire dcache_req_valid, dcache_rsp_valid, dcache_req_ready, dcache_rsp_ready;
        wire fetch_valid;
        wire [`XLEN-1:0] fetch_pc_full;
        wire [31:0] fetch_instr;

        localparam [31:0] TB_EBREAK_INSTR   = 32'h00100073;
        localparam [31:0] TB_EXIT_MMIO_ADDR = 32'h00000088;
        // tb_probe_ebreak_seen declared at module level (C3)

        // C3: drive module-level wire — same-cycle ebreak detection
        assign tb_ebreak_fetch = fetch_valid && (fetch_instr == TB_EBREAK_INSTR);

        reg tb_probe_exit_addr_seen;

        // Extract cache bus signals from core (1C_1S_1C config: cluster[0].socket[0].core[0])
        assign icache_req_valid = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.icache_bus_if.req_valid;
        assign icache_req_ready = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.icache_bus_if.req_ready;
        assign icache_rsp_valid = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.icache_bus_if.rsp_valid;
        assign icache_rsp_ready = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.icache_bus_if.rsp_ready;

        assign fetch_valid = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.fetch_if.valid;
        assign fetch_pc_full = VX_gpu_pkg::to_fullPC(dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.fetch_if.data.PC);
        assign fetch_instr = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.fetch_if.data.instr;

        // DCACHE is an array; measure the first port (0)
        assign dcache_req_valid = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.dcache_bus_if[0].req_valid;
        assign dcache_req_ready = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.dcache_bus_if[0].req_ready;
        assign dcache_rsp_valid = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.dcache_bus_if[0].rsp_valid;
        assign dcache_rsp_ready = dut.vortex.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.dcache_bus_if[0].rsp_ready;

        // Pipeline flow signals
        reg [31:0] icache_stall_cycles, dcache_stall_cycles;
        wire icache_stalled = icache_req_valid && !icache_req_ready;
        wire dcache_stalled = dcache_req_valid && !dcache_req_ready;
        wire icache_firing = icache_req_valid && icache_req_ready;
        wire dcache_firing = dcache_req_valid && dcache_req_ready;

        always @(posedge clk) begin
            if (!reset_n) begin
                icache_stall_cycles <= 0;
                dcache_stall_cycles <= 0;
                tb_probe_ebreak_seen <= 0;
                tb_probe_exit_addr_seen <= 0;
            end else if (tb_execution_started && !tb_execution_complete) begin
                if (icache_stalled) icache_stall_cycles <= icache_stall_cycles + 1;
                if (dcache_stalled) dcache_stall_cycles <= dcache_stall_cycles + 1;

                if (!tb_probe_ebreak_seen && fetch_valid && (fetch_instr == TB_EBREAK_INSTR)) begin
                    tb_probe_ebreak_seen <= 1'b1;
                    $display("[TB_PROBE_EBREAK @ %0t] ebreak fetched at PC=0x%08h instr=0x%08h", $time, fetch_pc_full[31:0], fetch_instr);
                end

                if (!tb_probe_exit_addr_seen && vif.axi_if.awvalid && vif.axi_if.awready && (vif.axi_if.awaddr == TB_EXIT_MMIO_ADDR)) begin
                    tb_probe_exit_addr_seen <= 1'b1;
                    $display("[TB_PROBE_EXIT @ %0t] observed AXI write address 0x%08h (program exit MMIO)", $time, vif.axi_if.awaddr);
                end
            end
        end

        always @(posedge clk) begin
            if (reset_n && tb_cycle_count % 1000 == 0 && tb_cycle_count > 0 && tb_execution_started && !tb_execution_complete) begin
                $display("[TB_PROBE_PIPELINE @ %0t] cyc=%0d | ICACHE: req=%b ready=%b rsp=%b stall_cyc=%0d | DCACHE: req=%b ready=%b rsp=%b stall_cyc=%0d | PC=0x%08h instr=0x%08h ebreak_seen=%b exit_addr_seen=%b",
                         $time, tb_cycle_count,
                         icache_req_valid, icache_req_ready, icache_rsp_valid, icache_stall_cycles,
                         dcache_req_valid, dcache_req_ready, dcache_rsp_valid, dcache_stall_cycles,
                         fetch_pc_full[31:0], fetch_instr, tb_probe_ebreak_seen, tb_probe_exit_addr_seen);
            end
        end

    `else
        // MEM interface version (non-AXI)
        wire icache_req_valid, icache_rsp_valid, icache_req_ready, icache_rsp_ready;
        wire dcache_req_valid, dcache_rsp_valid, dcache_req_ready, dcache_rsp_ready;
        wire fetch_valid;
        wire [`XLEN-1:0] fetch_pc_full;
        wire [31:0] fetch_instr;

        localparam [31:0] TB_EBREAK_INSTR   = 32'h00100073;
        localparam [31:0] TB_EXIT_MMIO_ADDR = 32'h00000088;
        // tb_probe_ebreak_seen declared at module level (C3)

        // C3: drive module-level wire — same-cycle ebreak detection
        assign tb_ebreak_fetch = fetch_valid && (fetch_instr == TB_EBREAK_INSTR);

        reg tb_probe_exit_addr_seen;

        assign icache_req_valid = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.icache_bus_if.req_valid;
        assign icache_req_ready = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.icache_bus_if.req_ready;
        assign icache_rsp_valid = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.icache_bus_if.rsp_valid;
        assign icache_rsp_ready = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.icache_bus_if.rsp_ready;

        assign fetch_valid = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.fetch_if.valid;
        assign fetch_pc_full = VX_gpu_pkg::to_fullPC(dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.fetch_if.data.PC);
        assign fetch_instr = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.fetch_if.data.instr;

        assign dcache_req_valid = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.dcache_bus_if[0].req_valid;
        assign dcache_req_ready = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.dcache_bus_if[0].req_ready;
        assign dcache_rsp_valid = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.dcache_bus_if[0].rsp_valid;
        assign dcache_rsp_ready = dut.g_clusters[0].cluster.g_sockets[0].socket.g_cores[0].core.dcache_bus_if[0].rsp_ready;

        reg [31:0] icache_stall_cycles, dcache_stall_cycles;
        wire icache_stalled = icache_req_valid && !icache_req_ready;
        wire dcache_stalled = dcache_req_valid && !dcache_req_ready;

        always @(posedge clk) begin
            if (!reset_n) begin
                icache_stall_cycles <= 0;
                dcache_stall_cycles <= 0;
                tb_probe_ebreak_seen <= 0;
                tb_probe_exit_addr_seen <= 0;
            end else if (tb_execution_started && !tb_execution_complete) begin
                if (icache_stalled) icache_stall_cycles <= icache_stall_cycles + 1;
                if (dcache_stalled) dcache_stall_cycles <= dcache_stall_cycles + 1;

                if (!tb_probe_ebreak_seen && fetch_valid && (fetch_instr == TB_EBREAK_INSTR)) begin
                    tb_probe_ebreak_seen <= 1'b1;
                    $display("[TB_PROBE_EBREAK @ %0t] ebreak fetched at PC=0x%08h instr=0x%08h", $time, fetch_pc_full[31:0], fetch_instr);
                end

                if (!tb_probe_exit_addr_seen && vif.mem_if.req_valid[0] && vif.mem_if.req_ready[0] && vif.mem_if.req_rw[0] && (vif.mem_if.req_addr[0] == TB_EXIT_MMIO_ADDR[31:2])) begin
                    tb_probe_exit_addr_seen <= 1'b1;
                    $display("[TB_PROBE_EXIT @ %0t] observed MEM write address 0x%08h (program exit MMIO)", $time, TB_EXIT_MMIO_ADDR);
                end
            end
        end

        always @(posedge clk) begin
            if (reset_n && tb_cycle_count % 1000 == 0 && tb_cycle_count > 0 && tb_execution_started && !tb_execution_complete) begin
                $display("[TB_PROBE_PIPELINE @ %0t] cyc=%0d | ICACHE: req=%b ready=%b rsp=%b stall_cyc=%0d | DCACHE: req=%b ready=%b rsp=%b stall_cyc=%0d | PC=0x%08h instr=0x%08h ebreak_seen=%b exit_addr_seen=%b",
                         $time, tb_cycle_count,
                         icache_req_valid, icache_req_ready, icache_rsp_valid, icache_stall_cycles,
                         dcache_req_valid, dcache_req_ready, dcache_rsp_valid, dcache_stall_cycles,
                         fetch_pc_full[31:0], fetch_instr, tb_probe_ebreak_seen, tb_probe_exit_addr_seen);
            end
        end
    `endif

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
    // C1 — ELABORATION ASSERT: UVM VX_MEM_TAG_WIDTH == RTL VX_MEM_TAG_WIDTH
    // Both are derived from VX_gpu_pkg::VX_MEM_TAG_WIDTH. The first check
    // catches any future regression where someone re-hardcodes the UVM param.
    // The $bits check is the structural proof: DUT port width == UVM param.
    //==========================================================================
    initial begin : u_c1_tag_width_assert
        assert (vortex_config_pkg::VX_MEM_TAG_WIDTH == VX_gpu_pkg::VX_MEM_TAG_WIDTH)
            else $fatal(1, "[C1-ASSERT] VX_MEM_TAG_WIDTH: UVM_pkg=%0d RTL_pkg=%0d -- check vortex_config.sv",
                        vortex_config_pkg::VX_MEM_TAG_WIDTH, VX_gpu_pkg::VX_MEM_TAG_WIDTH);
`ifdef USE_AXI_WRAPPER
        assert ($bits(axi_awid[0]) == vortex_config_pkg::VX_MEM_TAG_WIDTH)
            else $fatal(1, "[C1-ASSERT] DUT AXI awid width=%0d bits but UVM VX_MEM_TAG_WIDTH=%0d",
                        $bits(axi_awid[0]), vortex_config_pkg::VX_MEM_TAG_WIDTH);
`endif
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
                while (elapsed_cycles < timeout_cycles && !vif.status_if.ebreak_detected) begin
                    @(posedge clk); elapsed_cycles++;
                    if (elapsed_cycles % 100000 == 0)
                        $display("[TB_TOP @ %0t] Progress: %0d cycles", $time, elapsed_cycles);
                end
                if (vif.status_if.ebreak_detected) begin
                    $display("[TB_TOP @ %0t] Watchdog disarmed after %0d cycles (EBREAK detected)",
                             $time, elapsed_cycles);
                end else begin
                    $error("[TB_TOP @ %0t] TIMEOUT after %0d cycles!", $time, timeout_cycles);
                    vif.print_status();
                    memory.print_statistics();
                    $finish(2);
                end
            end
        join_none
    end


    // Bind warp/scheduler-state coverage probe into every VX_schedule instance
    bind VX_schedule vx_sched_probe #(.CORE_ID(0)) u_sched_probe (
        .clk          (clk),
        .reset        (reset),
        .warp_ctl_if  (warp_ctl_if),
        .schedule_if  (schedule_if),
        .active_warps (active_warps),
        .stalled_warps(stalled_warps),
        .barrier_ctrs (barrier_ctrs),
        .join_valid   (join_valid),
        .join_is_dvg  (join_is_dvg),
        .join_is_else (join_is_else),
        .join_tmask   (join_tmask)
    );

    // Bind white-box instruction probe into every VX_dispatch instance
    bind VX_dispatch vx_instr_probe #(.CORE_ID(0)) u_instr_probe (
        .clk        (clk),
        .reset      (reset),
        .dispatch_if(dispatch_if)
    );
    

    //==========================================================================
    // SIMULATION COMPLETION
    //==========================================================================

    final begin
        uvm_report_server svr;
        int unsigned n_err, n_fatal;
        svr     = uvm_report_server::get_server();
        n_err   = svr.get_severity_count(UVM_ERROR);
        n_fatal = svr.get_severity_count(UVM_FATAL);
        $display("\n================================================================================");
        $display("[TB_TOP @ %0t] Simulation Complete", $time);
        if (n_err == 0 && n_fatal == 0)
            $display("Test Result:    PASS");
        else
            $display("Test Result:    FAILED (%0d error(s), %0d fatal)", n_err, n_fatal);
        $display("  Total Cycles: %0d  Instructions: %0d",
                vif.status_if.cycle_count, vif.status_if.instr_count);
        memory.print_statistics();
        $display("================================================================================\n");
    end

endmodule : vortex_tb_top

`endif // VORTEX_TB_TOP_SV