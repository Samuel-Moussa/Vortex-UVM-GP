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
//   ID_WIDTH = VX_MEM_TAG_WIDTH  (derived; =50 for debug UUID_WIDTH=44)
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
    parameter ADDR_WIDTH            = 32,    // byte address (32 RV32, 48 RV64)
    parameter DATA_WIDTH            = 512,   // FIX: was 64 — must be VX_MEM_DATA_WIDTH = 512
    parameter ID_WIDTH              = 50,    // overridden at instantiation = VX_MEM_TAG_WIDTH
    parameter bit ENABLE_FULL_AXI_CHECKS = 1'b1  // set 0 to silence Groups A/C/D/E/F; existing handshake checks stay on
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
    // W Channel: this environment uses single-beat writes, so WLAST must be
    // asserted on every accepted write beat. WLAST is only meaningful when
    // WVALID is high; it may remain at its driven value when idle.
    // -----------------------------------------------------------------------
    property wlast_asserted_on_write_p;
        @(posedge clk) disable iff (!reset_n)
        (wvalid && wready) |-> wlast;
    endproperty

    assert_wlast_asserted: assert property (wlast_asserted_on_write_p)
        else $error("[VORTEX_AXI_IF] WLAST missing on accepted write beat!");

    // -----------------------------------------------------------------------
    // B Channel: BVALID must not assert unless at least one completed write
    // (WLAST accepted) is outstanding. Use a counter to support multiple
    // outstanding single-beat writes.
    // -----------------------------------------------------------------------
    int unsigned completed_writes_outstanding;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            completed_writes_outstanding <= '0;
        end else begin
            automatic int signed next_completed;

            next_completed = int'(completed_writes_outstanding);
            if (wvalid && wready && wlast)
                next_completed++;
            if (bvalid && bready)
                next_completed--;

            // Clamp to zero for safety if protocol violations create extra B handshakes.
            if (next_completed < 0)
                next_completed = 0;

            completed_writes_outstanding <= int'(next_completed);
        end
    end

    property bvalid_after_wlast_p;
        @(posedge clk) disable iff (!reset_n)
        $rose(bvalid) |-> (completed_writes_outstanding > 0 || (wvalid && wready && wlast));
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

    // ============================================================
    // FULL AXI4 PROTOCOL CHECKS (Groups A / C / D / E / F)
    // Kill-switch: ENABLE_FULL_AXI_CHECKS=0 silences all groups below.
    // The existing handshake-stability checks above are always-on and
    // are never gated by this parameter.
    // ============================================================
    generate if (ENABLE_FULL_AXI_CHECKS) begin : g_full_axi_checks

    // ============ GROUP A — BURST LEGALITY ============
    // Combinational checks on every AW/AR handshake; no new state.
    // A5/A6/A7/A8 are vacuous today (Vortex issues single-beat FIXED only —
    // see VX_axi_adapter.sv:262,264,297) but are retained to guard against
    // future RTL changes that enable multi-beat or INCR/WRAP bursts.

    // A1: AWBURST must not be RESERVED (2'b11 is undefined per AXI4 A3.4.1)
    property aw_burst_legal_p;
        @(posedge clk) disable iff (!reset_n)
        (awvalid && awready) |-> (awburst != 2'b11);
    endproperty
    assert_aw_burst_legal: assert property (aw_burst_legal_p)
        else $error("[AXI SVA-A1] AWBURST is RESERVED (2'b11)!");

    // A2: ARBURST must not be RESERVED
    property ar_burst_legal_p;
        @(posedge clk) disable iff (!reset_n)
        (arvalid && arready) |-> (arburst != 2'b11);
    endproperty
    assert_ar_burst_legal: assert property (ar_burst_legal_p)
        else $error("[AXI SVA-A2] ARBURST is RESERVED (2'b11)!");

    // A3: AWSIZE must not exceed log2(DATA_WIDTH/8) — max transfer granularity
    property aw_size_legal_p;
        @(posedge clk) disable iff (!reset_n)
        (awvalid && awready) |-> (awsize <= $clog2(DATA_WIDTH/8));
    endproperty
    assert_aw_size_legal: assert property (aw_size_legal_p)
        else $error("[AXI SVA-A3] AWSIZE=%0d exceeds max %0d for DATA_WIDTH=%0d",
                    awsize, $clog2(DATA_WIDTH/8), DATA_WIDTH);

    // A4: ARSIZE must not exceed max supported transfer size
    property ar_size_legal_p;
        @(posedge clk) disable iff (!reset_n)
        (arvalid && arready) |-> (arsize <= $clog2(DATA_WIDTH/8));
    endproperty
    assert_ar_size_legal: assert property (ar_size_legal_p)
        else $error("[AXI SVA-A4] ARSIZE=%0d exceeds max %0d for DATA_WIDTH=%0d",
                    arsize, $clog2(DATA_WIDTH/8), DATA_WIDTH);

    // A5: WRAP burst must have length 2/4/8/16 beats (awlen ∈ {1,3,7,15})
    property aw_wrap_len_legal_p;
        @(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awburst == 2'b10) |->
            (awlen inside {8'd1, 8'd3, 8'd7, 8'd15});
    endproperty
    assert_aw_wrap_len_legal: assert property (aw_wrap_len_legal_p)
        else $error("[AXI SVA-A5] AWBURST=WRAP but AWLEN=%0d not in {1,3,7,15}", awlen);

    // A6: Same for AR WRAP burst
    property ar_wrap_len_legal_p;
        @(posedge clk) disable iff (!reset_n)
        (arvalid && arready && arburst == 2'b10) |->
            (arlen inside {8'd1, 8'd3, 8'd7, 8'd15});
    endproperty
    assert_ar_wrap_len_legal: assert property (ar_wrap_len_legal_p)
        else $error("[AXI SVA-A6] ARBURST=WRAP but ARLEN=%0d not in {1,3,7,15}", arlen);

    // A7: INCR burst must not cross a 4 KB address boundary (AXI4 A3.4.3)
    // check: awaddr[11:0] + total_bytes <= 4096
    property aw_4k_boundary_p;
        @(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awburst == 2'b01) |->
            ((awaddr[11:0] + ((awlen + 1) << awsize)) <= 13'h1000);
    endproperty
    assert_aw_4k_boundary: assert property (aw_4k_boundary_p)
        else $error("[AXI SVA-A7] AW INCR burst crosses 4KB: addr=0x%0h len=%0d size=%0d",
                    awaddr, awlen, awsize);

    // A8: Same for AR INCR burst
    property ar_4k_boundary_p;
        @(posedge clk) disable iff (!reset_n)
        (arvalid && arready && arburst == 2'b01) |->
            ((araddr[11:0] + ((arlen + 1) << arsize)) <= 13'h1000);
    endproperty
    assert_ar_4k_boundary: assert property (ar_4k_boundary_p)
        else $error("[AXI SVA-A8] AR INCR burst crosses 4KB: addr=0x%0h len=%0d size=%0d",
                    araddr, arlen, arsize);

    // ============ GROUP C — OUTSTANDING-TRANSACTION SCOREBOARDS ============
    // C1: Every B response must correspond to at least one outstanding AW.
    // C2: Every R beat must correspond to at least one outstanding AR beat.
    //
    // Implementation history (kept here so the next reviewer doesn't redo this):
    //  - V1 (associative arrays + always @ blocking): false-fired every B
    //    because Questa does not apply preponed sampled-value semantics to
    //    associative arrays — SVA in Observed read the post-decrement value.
    //  - V2 (fixed int arrays + always_ff + _prev snapshot via NBA): also
    //    false-fired. The _prev snapshot is itself NBA-updated, so SVA at
    //    cycle N samples _prev's value from end of N-1, which reflects cnt
    //    from end of N-2 (two cycles late). For Vortex where R fires the
    //    cycle after AR, _prev[id] was still 0 when the R-cycle SVA checked.
    //  - V3 (fixed int arrays + always_ff + SVA reads cnt directly): C2 OK
    //    but C1 still false-fires. Questa appears to mishandle preponed
    //    sampling of `unpacked_int_array[bit_select_index]` inside SVA when
    //    that array is updated by an always_ff inside generate-inside-iface.
    //
    // V4 (this version): drop per-ID granularity and use scalar TOTAL
    // counters. The existing `completed_writes_outstanding` at line 428
    // already uses this exact pattern (scalar int + always_ff NBA, checked
    // directly in SVA at line 452), and it works. Per-ID matching is nice-to-
    // have but not load-bearing for our scope — the RTL's own RUNTIME_ASSERTs
    // at VX_axi_adapter.sv:314 (bresp=0) and 333-334 (rlast=1, rresp=0) plus
    // the existing tier of per-channel handshake checks cover the rest.
    // RLAST-per-ID drain check (former C2b) is dropped — for Vortex's single-
    // beat reads the existing rlast_not_early_p / rlast_on_last_beat_p
    // (lines 485-501) already enforce the timing.

    int unsigned outstanding_aw_total; // C1: total outstanding AW (incremented at AW handshake, decremented at B)
    int unsigned outstanding_r_total;  // C2: total outstanding R beats (incremented by arlen+1 at AR, decremented at each R beat)

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            outstanding_aw_total <= 0;
            outstanding_r_total  <= 0;
        end else begin
            // AW/B: per-cycle net change (handles same-cycle AW+B correctly)
            case ({awvalid && awready, bvalid && bready})
                2'b10: outstanding_aw_total <= outstanding_aw_total + 1;
                2'b01: outstanding_aw_total <= outstanding_aw_total - 1;
                default: ; // 2'b00 or 2'b11 → no net change
            endcase
            // AR/R: AR adds (arlen+1) beats, each R handshake removes one
            case ({arvalid && arready, rvalid && rready})
                2'b10: outstanding_r_total <= outstanding_r_total + (int'(arlen) + 1);
                2'b01: outstanding_r_total <= outstanding_r_total - 1;
                2'b11: outstanding_r_total <= outstanding_r_total + (int'(arlen) + 1) - 1;
                default: ;
            endcase
        end
    end

    // C1: B handshake requires at least one outstanding AW (any ID).
    property bvalid_has_outstanding_aw_p;
        @(posedge clk) disable iff (!reset_n)
        (bvalid && bready) |-> (outstanding_aw_total > 0);
    endproperty
    assert_bvalid_has_outstanding_aw: assert property (bvalid_has_outstanding_aw_p)
        else $error("[AXI SVA-C1] B handshake (BID=0x%0h) but no outstanding AW (total=%0d)!",
                    bid, outstanding_aw_total);

    // C2: R handshake requires at least one outstanding AR beat (any ID).
    property rvalid_has_outstanding_ar_p;
        @(posedge clk) disable iff (!reset_n)
        (rvalid && rready) |-> (outstanding_r_total > 0);
    endproperty
    assert_rvalid_has_outstanding_ar: assert property (rvalid_has_outstanding_ar_p)
        else $error("[AXI SVA-C2] R handshake (RID=0x%0h) but no outstanding AR beat (total=%0d)!",
                    rid, outstanding_r_total);

    // ============ GROUP D — RESET BEHAVIOUR ============
    // No 'disable iff' on D1/D2 — these ARE the reset checks.
    // Use `!== 1'b1` (case-inequality) rather than `!signal` so that
    // uninitialised X/Z at sim startup (before the DUT has driven its
    // outputs) does not propagate to an X consequent and false-fire.
    // Only a firmly-1 VALID counts as a violation.

    // D1: No VALID may be firmly 1 while reset is asserted
    property valids_low_during_reset_p;
        @(posedge clk)
        (!reset_n) |-> (awvalid !== 1'b1) && (wvalid  !== 1'b1) && (bvalid !== 1'b1) &&
                       (arvalid !== 1'b1) && (rvalid !== 1'b1);
    endproperty
    assert_valids_low_during_reset: assert property (valids_low_during_reset_p)
        else $error("[AXI SVA-D1] A VALID is asserted while reset_n=0!");

    // D2: No VALID may be firmly 1 on the first active cycle after reset deassertion.
    // RTL confirmed safe: VX_axi_adapter FIFOs reset to empty (lines 262,264,297),
    // so all master VALIDs settle to 0 by the time reset_n rises.
    property valids_low_after_reset_p;
        @(posedge clk)
        $rose(reset_n) |-> (awvalid !== 1'b1) && (wvalid  !== 1'b1) && (bvalid !== 1'b1) &&
                           (arvalid !== 1'b1) && (rvalid !== 1'b1);
    endproperty
    assert_valids_low_after_reset: assert property (valids_low_after_reset_p)
        else $error("[AXI SVA-D2] A VALID is asserted on the cycle reset_n rises!");

    // ============ GROUP E — EXTENDED CHANNEL STABILITY ============
    // Full AXI4 rule: ALL signals on a channel must hold stable while
    // VALID is asserted and READY has not yet been returned.
    // Existing checks already cover: awaddr, awid, araddr, arid, wdata, rdata.
    // These add the remaining control fields.

    // E1: All remaining AW control fields stable while AWVALID && !AWREADY
    property aw_signals_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (awvalid && !awready) |=>
            $stable({awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion});
    endproperty
    assert_aw_signals_stable: assert property (aw_signals_stable_p)
        else $error("[AXI SVA-E1] AW control field(s) changed before AWREADY!");

    // E2: All remaining AR control fields stable while ARVALID && !ARREADY
    property ar_signals_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (arvalid && !arready) |=>
            $stable({arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion});
    endproperty
    assert_ar_signals_stable: assert property (ar_signals_stable_p)
        else $error("[AXI SVA-E2] AR control field(s) changed before ARREADY!");

    // E3: WSTRB must hold stable while WVALID && !WREADY
    property w_strb_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (wvalid && !wready) |=> $stable(wstrb);
    endproperty
    assert_w_strb_stable: assert property (w_strb_stable_p)
        else $error("[AXI SVA-E3] WSTRB changed before WREADY!");

    // ============ GROUP F — COVERAGE COVER POINTS ============

    // AW burst type distribution
    cover_aw_burst_fixed:  cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awburst == 2'b00));
    cover_aw_burst_incr:   cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awburst == 2'b01));
    cover_aw_burst_wrap:   cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awburst == 2'b10));

    // Write response codes seen
    cover_bresp_okay:      cover property (@(posedge clk) disable iff (!reset_n)
        (bvalid && bready && bresp == 2'b00));
    cover_bresp_slverr:    cover property (@(posedge clk) disable iff (!reset_n)
        (bvalid && bready && bresp == 2'b10));
    cover_bresp_decerr:    cover property (@(posedge clk) disable iff (!reset_n)
        (bvalid && bready && bresp == 2'b11));

    // Read response codes seen
    cover_rresp_okay:      cover property (@(posedge clk) disable iff (!reset_n)
        (rvalid && rready && rresp == 2'b00));
    cover_rresp_slverr:    cover property (@(posedge clk) disable iff (!reset_n)
        (rvalid && rready && rresp == 2'b10));
    cover_rresp_decerr:    cover property (@(posedge clk) disable iff (!reset_n)
        (rvalid && rready && rresp == 2'b11));

    // AWLEN distribution brackets (1 beat, 2-4, 5-16, 17-64, 65-255)
    cover_awlen_1beat:     cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awlen == 8'd0));
    cover_awlen_2to4:      cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awlen inside {[8'd1:8'd3]}));
    cover_awlen_5to16:     cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awlen inside {[8'd4:8'd15]}));
    cover_awlen_17to64:    cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awlen inside {[8'd16:8'd63]}));
    cover_awlen_65to255:   cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && awready && awlen inside {[8'd64:8'd255]}));

    // Both AW and AR address channels simultaneously active (interleaved traffic)
    cover_concurrent_aw_ar: cover property (@(posedge clk) disable iff (!reset_n)
        (awvalid && arvalid));

    end endgenerate // g_full_axi_checks

endinterface : vortex_axi_if

`endif // VORTEX_AXI_IF_SV
