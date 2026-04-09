////////////////////////////////////////////////////////////////////////////////
// File: vortex_axi_if.sv
// Description: AXI4 interface with proper clocking blocks
//
// Full AXI4 protocol with 5 independent channels:
//   - AW: Write Address
//   - W:  Write Data
//   - B:  Write Response
//   - AR: Read Address
//   - R:  Read Data
//
// Default parameters match Vortex memory bus exactly:
//   ADDR_WIDTH = AXI_ADDR_WIDTH  (32 RV32, 48 RV64) — set by vortex_if
//   DATA_WIDTH = 512             (VX_MEM_DATA_WIDTH = L3_LINE_SIZE * 8)
//   ID_WIDTH   = 8               (VX_MEM_TAG_WIDTH  = L3_MEM_TAG_WIDTH)
//
// Clocking Blocks:
//   - master_cb:  All 'input' (DUT is master, TB observes) — no dual driver
//   - slave_cb:   All 'input' (TB drives directly in always_ff/initial)
//   - monitor_cb: All 'input' (passive observation)
//
// Fixed issues:
//   - AXI4 violations (AWVALID drop, WLAST timing, ID ordering, BVALID timing) pass silently. No SVA properties on any channel.
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_AXI_IF_SV
`define VORTEX_AXI_IF_SV

interface automatic vortex_axi_if #(
    parameter ADDR_WIDTH = 32,   // byte address (32 RV32, 48 RV64)
    parameter DATA_WIDTH = 512,  // FIX: was 64 — must be VX_MEM_DATA_WIDTH = 512
    parameter ID_WIDTH   = 50     // will be parametrized later to VX_MEM_TAG_WIDTH  for now = 50 for 1CL,1C,4T,4W
) (
    input logic clk,
    input logic reset_n
);

    //==========================================================================
    // AXI WRITE ADDRESS CHANNEL (AW)
    // DUT-driven (master outputs) — no initial value needed (DUT resets them)
    //==========================================================================
    logic [ID_WIDTH-1:0]     awid;
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic [7:0]              awlen;
    logic [2:0]              awsize;
    logic [1:0]              awburst;
    logic                    awlock;
    logic [3:0]              awcache;
    logic [2:0]              awprot;
    logic [3:0]              awqos;
    logic [3:0]              awregion;
    logic                    awvalid;
    // TB-driven slave response — initialised to 0 so DUT sees no X before first clk.
    // Inline initial value is the only correct way: a separate initial block would
    // create a second driver on an always_ff variable (Questa vopt-7061 error).
    logic                    awready = 1'b0;

    //==========================================================================
    // AXI WRITE DATA CHANNEL (W)
    //==========================================================================
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wlast;
    logic                    wvalid;
    logic                    wready  = 1'b0;  // TB-driven

    //==========================================================================
    // AXI WRITE RESPONSE CHANNEL (B)
    //==========================================================================
    logic [ID_WIDTH-1:0]     bid     = '0;    // TB-driven
    logic [1:0]              bresp   = 2'b00; // TB-driven
    logic                    bvalid  = 1'b0;  // TB-driven
    logic                    bready;          // DUT-driven

    //==========================================================================
    // AXI READ ADDRESS CHANNEL (AR)
    //==========================================================================
    logic [ID_WIDTH-1:0]     arid;
    logic [ADDR_WIDTH-1:0]   araddr;
    logic [7:0]              arlen;
    logic [2:0]              arsize;
    logic [1:0]              arburst;
    logic                    arlock;
    logic [3:0]              arcache;
    logic [2:0]              arprot;
    logic [3:0]              arqos;
    logic [3:0]              arregion;
    logic                    arvalid;
    logic                    arready;         // TB-driven via assign in tb_top

    //==========================================================================
    // AXI READ DATA CHANNEL (R)
    //==========================================================================
    logic [ID_WIDTH-1:0]     rid     = '0;    // TB-driven
    logic [DATA_WIDTH-1:0]   rdata   = '0;    // TB-driven
    logic [1:0]              rresp   = 2'b00; // TB-driven
    logic                    rlast   = 1'b0;  // TB-driven
    logic                    rvalid  = 1'b0;  // TB-driven
    logic                    rready;          // DUT-driven

    //==========================================================================
    // CLOCKING BLOCK: MASTER (Observe-only — DUT is AXI master)
    //==========================================================================
    // FIX (vopt-3838/7061): In USE_AXI_WRAPPER mode the DUT drives all AW/W/AR
    // outputs; the TB is always the AXI slave. A clocking block 'output' creates
    // an implicit NBA procedural driver on the net — conflicts with the DUT's
    // continuous assign in tb_top.
    // Solution: all signals declared 'input' (observe-only). Zero drivers added.
    clocking master_cb @(posedge clk);
        default input #1step output #0;

        // Write Address Channel — DUT drives, TB observes
        input   awid, awaddr, awlen, awsize, awburst;
        input   awlock, awcache, awprot, awqos, awregion;
        input   awvalid;
        input   awready;

        // Write Data Channel — DUT drives, TB observes
        input   wdata, wstrb, wlast, wvalid;
        input   wready;

        // Write Response Channel
        input   bid, bresp, bvalid;
        input   bready;

        // Read Address Channel — DUT drives, TB observes
        input   arid, araddr, arlen, arsize, arburst;
        input   arlock, arcache, arprot, arqos, arregion;
        input   arvalid;
        input   arready;

        // Read Data Channel
        input   rid, rdata, rresp, rlast, rvalid;
        input   rready;
    endclocking

// CLOCKING BLOCK DRIVER
// Used by axi_driver.sv when UVM TB acts as AXI master
// (custom mem path / standalone agent tests)
// TB-driven signals are OUTPUT; DUT/slave responses are INPUT.
clocking driver_cb @(posedge clk);
    default input #1step output #0;
    // TB drives these (master outputs):
    input  awvalid, awid, awaddr, awlen, awsize, awburst;  // DUT master — observe only
    input  awlock, awcache, awprot, awqos, awregion;
    input  wvalid, wdata, wstrb, wlast;  // DUT master — observe only
    input  bready;  // DUT master — observe only
    input  arvalid, arid, araddr, arlen, arsize, arburst;  // DUT master — observe only
    input  arlock, arcache, arprot, arqos, arregion;
    input  rready;  // DUT master — observe only
    // Slave/DUT responses — TB observes:
    input  awready;
    input  wready;
    input  bid, bresp, bvalid;
    input  arready;
    input  rid, rdata, rresp, rlast, rvalid;
endclocking


    //==========================================================================
    // CLOCKING BLOCK: SLAVE (Observe-only — TB drives signals directly)
    //==========================================================================
    // FIX (vopt-7061): tb_top drives all TB-slave signals directly via always_ff
    // (not through clocking block NBA scheduling). A clocking block 'output'
    // creates an implicit procedural driver on the net — conflicting with the
    // always_ff driver in tb_top → dual-driver.
    // Solution: all signals are 'input' (observe-only). tb_top drives directly.
    clocking slave_cb @(posedge clk);
        default input #1step output #0;

        // Write Address Channel — DUT drives, TB observes
        input   awid, awaddr, awlen, awsize, awburst;
        input   awlock, awcache, awprot, awqos, awregion;
        input   awvalid;
        input   awready;    // TB drives directly in tb_top always_ff

        // Write Data Channel — DUT drives, TB observes
        input   wdata, wstrb, wlast, wvalid;
        input   wready;     // TB drives directly in tb_top always_ff

        // Write Response Channel
        input   bid, bresp, bvalid;  // TB drives directly in tb_top always_ff
        input   bready;

        // Read Address Channel — DUT drives, TB observes
        input   arid, araddr, arlen, arsize, arburst;
        input   arlock, arcache, arprot, arqos, arregion;
        input   arvalid;
        input   arready;    // TB drives directly in tb_top always_ff

        // Read Data Channel
        input   rid, rdata, rresp, rlast, rvalid;  // TB drives directly
        input   rready;
    endclocking

    //==========================================================================
    // CLOCKING BLOCK: MONITOR (Passive Observation)
    //==========================================================================
    clocking monitor_cb @(posedge clk);
        default input #1step;

        input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    //==========================================================================
    // MODPORTS
    //==========================================================================

    modport master_driver (
        clocking master_cb,
        clocking driver_cb,
        input clk, reset_n
    );

    modport slave_driver (
        clocking slave_cb,
        input clk, reset_n
    );

    modport monitor (
        clocking monitor_cb,
        input clk, reset_n
    );

    // For DUT master connection (DUT drives its outputs here)
    modport dut_master (
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    // For DUT slave connection
    modport dut_slave (
        input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );

    //==========================================================================
    // HELPER FUNCTIONS
    //==========================================================================

    function automatic bit aw_fire();
        return (awvalid && awready);
    endfunction

    function automatic bit w_fire();
        return (wvalid && wready);
    endfunction

    function automatic bit b_fire();
        return (bvalid && bready);
    endfunction

    function automatic bit ar_fire();
        return (arvalid && arready);
    endfunction

    function automatic bit r_fire();
        return (rvalid && rready);
    endfunction

    function automatic string decode_burst(logic [1:0] burst);
        case (burst)
            2'b00: return "FIXED";
            2'b01: return "INCR";
            2'b10: return "WRAP";
            default: return "RESERVED";
        endcase
    endfunction

    function automatic string decode_resp(logic [1:0] resp);
        case (resp)
            2'b00: return "OKAY";
            2'b01: return "EXOKAY";
            2'b10: return "SLVERR";
            2'b11: return "DECERR";
        endcase
    endfunction

    //==========================================================================
    // PROTOCOL ASSERTIONS
    //==========================================================================

    // AW Channel: AWVALID must remain stable until AWREADY
    property aw_valid_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (awvalid && !awready) |=> awvalid;
    endproperty

    property aw_addr_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (awvalid && !awready) |=> $stable(awaddr);
    endproperty

    // W Channel: WVALID must remain stable until WREADY
    property w_valid_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (wvalid && !wready) |=> wvalid;
    endproperty

    property w_data_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (wvalid && !wready) |=> $stable(wdata);
    endproperty

    // B Channel: BVALID must remain stable until BREADY
    property b_valid_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (bvalid && !bready) |=> bvalid;
    endproperty

    // AR Channel: ARVALID must remain stable until ARREADY
    property ar_valid_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (arvalid && !arready) |=> arvalid;
    endproperty

    property ar_addr_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (arvalid && !arready) |=> $stable(araddr);
    endproperty

    // R Channel: RVALID must remain stable until RREADY, except after rlast
    property r_valid_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (rvalid && !rready && !rlast) |=> rvalid;
    endproperty

    property r_data_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (rvalid && !rready && !rlast) |=> $stable(rdata);
    endproperty

    assert_aw_valid_stable: assert property (aw_valid_stable_p)
        else $error("[VORTEX_AXI_IF] AWVALID dropped before AWREADY!");

    assert_aw_addr_stable: assert property (aw_addr_stable_p)
        else $error("[VORTEX_AXI_IF] AWADDR changed before handshake!");

    assert_w_valid_stable: assert property (w_valid_stable_p)
        else $error("[VORTEX_AXI_IF] WVALID dropped before WREADY!");

    assert_w_data_stable: assert property (w_data_stable_p)
        else $error("[VORTEX_AXI_IF] WDATA changed before handshake!");

    assert_b_valid_stable: assert property (b_valid_stable_p)
        else $error("[VORTEX_AXI_IF] BVALID dropped before BREADY!");

    assert_ar_valid_stable: assert property (ar_valid_stable_p)
        else $error("[VORTEX_AXI_IF] ARVALID dropped before ARREADY!");

    assert_ar_addr_stable: assert property (ar_addr_stable_p)
        else $error("[VORTEX_AXI_IF] ARADDR changed before handshake!");

    assert_r_valid_stable: assert property (r_valid_stable_p)
        else $error("[VORTEX_AXI_IF] RVALID dropped before RREADY!");

    assert_r_data_stable: assert property (r_data_stable_p)
        else $error("[VORTEX_AXI_IF] RDATA changed before handshake!");

    //==========================================================================
    // COVERAGE
    //==========================================================================

    covergroup axi_protocol_cg @(posedge clk);
        option.per_instance = 1;

        awburst_cp: coverpoint awburst {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }

        arburst_cp: coverpoint arburst {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }

        awlen_cp: coverpoint awlen {
            bins single      = {0};
            bins short_burst = {[1:7]};
            bins long_burst  = {[8:255]};
        }

        awsize_cp: coverpoint awsize {
            bins bytee = {3'b000};
            bins hword = {3'b001};
            bins word  = {3'b010};
            bins dword = {3'b011};
        }

        bresp_cp: coverpoint bresp {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }

        rresp_cp: coverpoint rresp {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }

        write_burst_cross: cross awburst_cp, awlen_cp, awsize_cp;
        read_burst_cross:  cross arburst_cp, awlen_cp, awsize_cp;
    endgroup

    axi_protocol_cg axi_cov = new();

    // No initial signal assignments — signals start X, driven by DUT/TB only.

    //==========================================================================
    // ADDITIONAL SVA PROPERTIES (wlast_before_bvalid, rlast_beat_count,
    //                            id_stable, bvalid_after_wlast)
    //==========================================================================

    // -----------------------------------------------------------------------
    // AW Channel: AWID must remain stable while AWVALID and not yet accepted
    // -----------------------------------------------------------------------
    property awid_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (awvalid && !awready) |=> $stable(awid);
    endproperty

    assert_awid_stable: assert property (awid_stable_p)
        else $error("[VORTEX_AXI_IF] AWID changed before AWREADY handshake!");

    // -----------------------------------------------------------------------
    // AR Channel: ARID must remain stable while ARVALID and not yet accepted
    // -----------------------------------------------------------------------
    property arid_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (arvalid && !arready) |=> $stable(arid);
    endproperty

    assert_arid_stable: assert property (arid_stable_p)
        else $error("[VORTEX_AXI_IF] ARID changed before ARREADY handshake!");

    // -----------------------------------------------------------------------
    // W Channel: WLAST must assert on the final beat of the burst.
    // Specifically: once WVALID goes high, WLAST must eventually assert
    // before or when WVALID drops after the handshake completes.
    // This property checks WLAST is not held high across two separate
    // write handshakes (i.e. it deasserts after the beat it marks).
    // -----------------------------------------------------------------------
    property wlast_deasserts_after_beat_p;
        @(posedge clk) disable iff (!reset_n)
        (wvalid && wready && wlast) |=> !wlast;
    endproperty

    assert_wlast_deasserts: assert property (wlast_deasserts_after_beat_p)
        else $error("[VORTEX_AXI_IF] WLAST held high across consecutive beats!");

    // -----------------------------------------------------------------------
    // B Channel: BVALID must not assert until WLAST has been accepted.
    // Track whether the write data burst has completed using a flag.
    // BVALID before WLAST handshake = protocol violation.
    // -----------------------------------------------------------------------
    logic wlast_accepted;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            wlast_accepted <= 1'b0;
        else if (wvalid && wready && wlast)
            wlast_accepted <= 1'b1;
        else if (bvalid && bready)
            wlast_accepted <= 1'b0;
    end

    property bvalid_after_wlast_p;
        @(posedge clk) disable iff (!reset_n)
        $rose(bvalid) |-> wlast_accepted;
    endproperty

    assert_bvalid_after_wlast: assert property (bvalid_after_wlast_p)
        else $error("[VORTEX_AXI_IF] BVALID asserted before WLAST accepted!");

    // -----------------------------------------------------------------------
    // R Channel: RLAST beat count check.
    // RLAST must assert exactly on beat number (arlen+1), not before.
    // Track beats per burst and verify rlast only fires on the last beat.
    // -----------------------------------------------------------------------
    logic [7:0] r_beat_count;
    logic [7:0] r_burst_len;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_beat_count <= 8'h0;
            r_burst_len  <= 8'h0;
        end else begin
            // Latch burst length on AR handshake
            if (arvalid && arready)
                r_burst_len <= arlen;
            // Count R beats
            if (rvalid && rready) begin
                if (rlast)
                    r_beat_count <= 8'h0;
                else
                    r_beat_count <= r_beat_count + 1;
            end
        end
    end

    // RLAST must not assert before the last beat
    property rlast_not_early_p;
        @(posedge clk) disable iff (!reset_n)
        (rvalid && rready && rlast) |-> (r_beat_count == r_burst_len);
    endproperty

    // RLAST must assert on the last beat (no silent extra beats)
    property rlast_on_last_beat_p;
        @(posedge clk) disable iff (!reset_n)
        (rvalid && rready && !rlast) |-> (r_beat_count < r_burst_len);
    endproperty

    assert_rlast_not_early: assert property (rlast_not_early_p)
        else $error("[VORTEX_AXI_IF] RLAST asserted early! beat=%0d expected=%0d",
                    r_beat_count, r_burst_len);

    assert_rlast_on_last_beat: assert property (rlast_on_last_beat_p)
        else $error("[VORTEX_AXI_IF] Beat after RLAST expected but more beats present!");

    // -----------------------------------------------------------------------
    // W Channel: WVALID must not assert before AW handshake has occurred.
    // AXI4 allows W before AW but this is optional — for Vortex which always
    // sends AW before W, flag any violation as a warning-level cover.
    // -----------------------------------------------------------------------
    logic aw_accepted;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            aw_accepted <= 1'b0;
        else if (awvalid && awready)
            aw_accepted <= 1'b1;
        else if (wvalid && wready && wlast)
            aw_accepted <= 1'b0;
    end

    // Cover point: W before AW (legal in AXI4 but unexpected for Vortex)
    cover_w_before_aw: cover property (
        @(posedge clk) disable iff (!reset_n)
        $rose(wvalid) && !aw_accepted
    );

endinterface : vortex_axi_if

`endif // VORTEX_AXI_IF_SV
