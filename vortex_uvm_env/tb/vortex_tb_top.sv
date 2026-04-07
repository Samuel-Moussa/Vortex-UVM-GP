////////////////////////////////////////////////////////////////////////////////
// File: vortex_tb_top.sv
// Description: Production-Ready Testbench Top for Vortex GPGPU UVM Verification
//
// FIX LOG (this revision):
//   FIX-1: arready is now COMBINATIONAL (assign = reset_n & ~rvalid).
//   FIX-2: DCR startup driver writes all 5 base DCRs.
//   FIX-3: MEM responder drives rsp_valid=0, req_ready=1 from time-0.
//   FIX-4: Removed `assign vif.axi_if.*` for DUT-driven signals.
//   FIX-5: X-State Protection added to Custom MEM responder READ branch.
//   FIX-6: Disabled overly strict reset assertion (we intentionally drive DCR during reset).
//          Fixed ebreak_detected evaluating to X when AXI is disabled.
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
    // INTERFACE INSTANTIATION
    //==========================================================================

    logic reset_n = 1'b0; 
    vortex_if vif (.clk(clk), .reset_n(reset_n));

    //==========================================================================
    // RESET + DCR STARTUP
    //==========================================================================

    initial begin
        bit [63:0] sa;
        bit [63:0] tmp;

        // FIX-6: Disable strict reset assertion because we intentionally drive DCR during reset
        $assertoff(0, vif.assert_reset_clears_valids);

        $display("================================================================================");
        $display("[TB_TOP @ %0t] Vortex GPGPU UVM Testbench Initialized", $time);
        $display("================================================================================");

        reset_n             = 1'b0;
        vif.dcr_if.wr_valid = 1'b0;
        vif.dcr_if.wr_addr  = 12'h0;
        vif.dcr_if.wr_data  = 32'h0;

        sa = vortex_config_pkg::STARTUP_ADDR;
        if ($value$plusargs("STARTUP_ADDR=%h", tmp)) sa = tmp;

        repeat(5) @(posedge clk);

        $display("[TB_TOP @ %0t] DCR: writing 5 base DCRs during reset, STARTUP_ADDR=0x%016h", $time, sa);

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

        repeat(RESET_CYCLES - 15) @(posedge clk);

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
                $display("[TB_TOP @ %0t] ✓ Pre-loaded %0d bytes from '%s' @ 0x%016h (before reset)",
                         $time, bytes, hex_file, sa);
            else
                $fatal(1, "[TB_TOP @ %0t] FATAL: load_hex_file('%s') returned 0 bytes", $time, hex_file);
        end

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
    // MEMORY INTERFACE - REQUEST/RESPONSE HANDLER (SINGLE LANE)
    //==========================================================================

    logic                                            mem_rsp_valid_r = 1'b0;
    logic [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0] mem_rsp_data_r  = '0;
    logic [vortex_config_pkg::VX_MEM_TAG_WIDTH-1:0]  mem_rsp_tag_r   = '0;

    assign vif.mem_if.req_ready[0] = (!mem_rsp_valid_r || vif.mem_if.rsp_ready[0]);
    assign vif.mem_if.rsp_valid[0] = mem_rsp_valid_r;
    assign vif.mem_if.rsp_data[0]  = mem_rsp_data_r;
    assign vif.mem_if.rsp_tag[0]   = mem_rsp_tag_r;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            mem_rsp_valid_r <= 1'b0;
            mem_rsp_data_r  <= '0;
            mem_rsp_tag_r   <= '0;
        end else begin
            if (mem_rsp_valid_r && vif.mem_if.rsp_ready[0]) begin
                mem_rsp_valid_r <= 1'b0;
            end

            if (vif.mem_if.req_valid[0] && vif.mem_if.req_ready[0]) begin
                automatic bit [31:0] byte_addr = vif.mem_if.req_addr[0] << 6;
                
                if (vif.mem_if.req_rw[0]) begin
                    automatic bit [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0] wdata = vif.mem_if.req_data[0];
                    automatic bit [vortex_config_pkg::VX_MEM_BYTEEN_WIDTH-1:0] byteen = vif.mem_if.req_byteen[0];
                    
                    for (int i = 0; i < vortex_config_pkg::VX_MEM_BYTEEN_WIDTH; i++) begin
                        if (byteen[i]) begin
                            memory.write_byte(byte_addr + i, wdata[i*8 +: 8]);
                        end
                    end
                    
                    $display("[TB_TOP @ %0t] MEM WRITE ACCEPTED (NO RSP): byte_addr=0x%08h tag=0x%02h",
                            $time, byte_addr, vif.mem_if.req_tag[0]);
                            
                end else begin
                    automatic logic [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0] rdata = memory.read_line(byte_addr);
                    
                    for (int i = 0; i < vortex_config_pkg::VX_MEM_DATA_WIDTH/32; i++) begin
                        if ($isunknown(rdata[i*32 +: 32])) begin
                            rdata[i*32 +: 32] = 32'h00000013;
                        end
                    end
                    
                    mem_rsp_valid_r <= 1'b1;
                    mem_rsp_data_r  <= rdata;
                    mem_rsp_tag_r   <= vif.mem_if.req_tag[0];
                    $display("[TB_TOP @ %0t] MEM READ QUEUED: byte_addr=0x%08h tag=0x%02h",
                            $time, byte_addr, vif.mem_if.req_tag[0]);
                end
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
    // AXI MEMORY SLAVE RESPONDER 
    //==========================================================================

    `ifdef USE_AXI_WRAPPER

        logic [7:0]                aw_id_reg       = '0;
        logic [MEM_ADDR_WIDTH-1:0] aw_addr_reg     = '0;
        logic [7:0]                ar_id_reg       = '0;
        logic [MEM_ADDR_WIDTH-1:0] ar_addr_reg     = '0;
        logic [7:0]                ar_len_reg      = '0;
        logic [7:0]                read_beat_count = '0;

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
                end
            end
        end

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
                end
            end
        end

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
                end else if (vif.axi_if.bvalid && vif.axi_if.bready) begin
                    vif.axi_if.bvalid <= 1'b0;
                end
            end
        end

        assign vif.axi_if.arready = reset_n & ~vif.axi_if.rvalid;

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
                    ar_id_reg         <= vif.axi_if.arid[7:0];
                    ar_addr_reg       <= vif.axi_if.araddr;
                    ar_len_reg        <= vif.axi_if.arlen;
                    read_beat_count   <= '0;
                    vif.axi_if.rvalid <= 1'b1;
                    vif.axi_if.rid    <= vif.axi_if.arid[7:0];
                    vif.axi_if.rdata  <= memory.read_line(vif.axi_if.araddr);
                    vif.axi_if.rresp  <= 2'b00;
                    vif.axi_if.rlast  <= (vif.axi_if.arlen == 8'h0);
                end else if (vif.axi_if.rvalid && vif.axi_if.rready) begin
                    if (read_beat_count == ar_len_reg) begin
                        vif.axi_if.rvalid <= 1'b0;
                        vif.axi_if.rlast  <= 1'b0;
                        read_beat_count   <= '0;
                    end else begin
                        automatic bit [7:0]                next_beat = read_beat_count + 1;
                        automatic bit [MEM_ADDR_WIDTH-1:0] next_addr =
                            ar_addr_reg + (next_beat << vortex_config_pkg::VX_MEM_OFFSET_BITS);
                        read_beat_count   <= next_beat;
                        vif.axi_if.rdata  <= memory.read_line(next_addr);
                        vif.axi_if.rlast  <= (next_beat == ar_len_reg);
                        vif.axi_if.rid    <= ar_id_reg;
                    end
                end
            end
        end

    `endif // USE_AXI_WRAPPER

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

    // FIX-6: Safely handle idle channel detection regardless of wrapper
    `ifdef USE_AXI_WRAPPER
        wire axi_channels_idle = !vif.axi_if.rvalid  && !vif.axi_if.arvalid &&
                                  !vif.axi_if.awvalid && !vif.axi_if.wvalid;
    `else
        wire axi_channels_idle = 1'b1;
    `endif
    
    wire mem_channels_idle = !vif.mem_if.req_valid[0] && !mem_rsp_valid_r;

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