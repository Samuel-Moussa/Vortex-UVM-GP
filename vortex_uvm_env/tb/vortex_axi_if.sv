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
// Clocking Blocks:
//   - master_cb:  For AXI master drivers
//   - slave_cb:   For AXI slave responders
//   - monitor_cb: For passive monitoring
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_AXI_IF_SV
`define VORTEX_AXI_IF_SV

interface vortex_axi_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH   = 4
) (
    input logic clk,
    input logic reset_n
);

    //==========================================================================
    // AXI WRITE ADDRESS CHANNEL (AW)
    //==========================================================================
    logic [ID_WIDTH-1:0]     awid;
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic [7:0]              awlen;        // Burst length - 1
    logic [2:0]              awsize;       // Bytes per beat
    logic [1:0]              awburst;      // Burst type
    logic                    awlock;       // Lock type
    logic [3:0]              awcache;      // Cache type
    logic [2:0]              awprot;       // Protection type
    logic [3:0]              awqos;        // Quality of Service
    logic [3:0]              awregion;     // Region identifier
    logic                    awvalid;
    logic                    awready;

    //==========================================================================
    // AXI WRITE DATA CHANNEL (W)
    //==========================================================================
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;        // Write strobes
    logic                    wlast;        // Last beat in burst
    logic                    wvalid;
    logic                    wready;

    //==========================================================================
    // AXI WRITE RESPONSE CHANNEL (B)
    //==========================================================================
    logic [ID_WIDTH-1:0]     bid;
    logic [1:0]              bresp;        // Write response
    logic                    bvalid;
    logic                    bready;

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
    logic                    arready;

    //==========================================================================
    // AXI READ DATA CHANNEL (R)
    //==========================================================================
    logic [ID_WIDTH-1:0]     rid;
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rlast;
    logic                    rvalid;
    logic                    rready;

    //==========================================================================
    // CLOCKING BLOCK: MASTER (For AXI Master Driver)
    //==========================================================================
    clocking master_cb @(posedge clk);
        default input #1step output #0;
        
        // Write Address Channel
        output  awid, awaddr, awlen, awsize, awburst;
        output  awlock, awcache, awprot, awqos, awregion;
        output  awvalid;
        input   awready;
        
        // Write Data Channel
        output  wdata, wstrb, wlast, wvalid;
        input   wready;
        
        // Write Response Channel
        input   bid, bresp, bvalid;
        output  bready;
        
        // Read Address Channel
        output  arid, araddr, arlen, arsize, arburst;
        output  arlock, arcache, arprot, arqos, arregion;
        output  arvalid;
        input   arready;
        
        // Read Data Channel
        input   rid, rdata, rresp, rlast, rvalid;
        output  rready;
    endclocking

    //==========================================================================
    // CLOCKING BLOCK: SLAVE (For AXI Slave Responder)
    //==========================================================================
    clocking slave_cb @(posedge clk);
        default input #1step output #0;
        
        // Write Address Channel
        input   awid, awaddr, awlen, awsize, awburst;
        input   awlock, awcache, awprot, awqos, awregion;
        input   awvalid;
        output  awready;
        
        // Write Data Channel
        input   wdata, wstrb, wlast, wvalid;
        output  wready;
        
        // Write Response Channel
        output  bid, bresp, bvalid;
        input   bready;
        
        // Read Address Channel
        input   arid, araddr, arlen, arsize, arburst;
        input   arlock, arcache, arprot, arqos, arregion;
        input   arvalid;
        output  arready;
        
        // Read Data Channel
        output  rid, rdata, rresp, rlast, rvalid;
        input   rready;
    endclocking

    //==========================================================================
    // CLOCKING BLOCK: MONITOR (For Passive Observation)
    //==========================================================================
    clocking monitor_cb @(posedge clk);
        default input #1step;
        
        // All signals are inputs for monitor
        input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    //==========================================================================
    // MODPORTS
    //==========================================================================
    
    // For UVM master driver
    modport master_driver (
        clocking master_cb,
        input clk, reset_n
    );
    
    // For UVM slave driver
    modport slave_driver (
        clocking slave_cb,
        input clk, reset_n
    );
    
    // For UVM monitor
    modport monitor (
        clocking monitor_cb,
        input clk, reset_n
    );
    
    // For DUT master connection
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
    
    // Decode burst type
    function automatic string decode_burst(logic [1:0] burst);
        case (burst)
            2'b00: return "FIXED";
            2'b01: return "INCR";
            2'b10: return "WRAP";
            default: return "RESERVED";
        endcase
    endfunction
    
    // Decode response
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
    
    // R Channel: RVALID must remain stable until RREADY
    property r_valid_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (rvalid && !rready) |=> rvalid;
    endproperty
    
    property r_data_stable_p;
        @(posedge clk) disable iff (!reset_n)
        (rvalid && !rready) |=> $stable(rdata);
    endproperty
    
    // Assertions
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
        
        // Burst types
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
        
        // Burst lengths
        awlen_cp: coverpoint awlen {
            bins single = {0};
            bins short_burst = {[1:7]};
            bins long_burst  = {[8:255]};
        }
        
        // Transfer sizes
        awsize_cp: coverpoint awsize {
            bins bytee  = {3'b000};
            bins hword = {3'b001};
            bins word  = {3'b010};
            bins dword = {3'b011};
        }
        
        // Response types
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
        
        // Cross coverage
        write_burst_cross: cross awburst_cp, awlen_cp, awsize_cp;
        read_burst_cross:  cross arburst_cp, awlen_cp, awsize_cp;
    endgroup
    
    axi_protocol_cg axi_cov = new();

    //==========================================================================
    // INITIAL SIGNAL VALUES
    //==========================================================================
    
    // initial begin
    //     // Master outputs
    //     awvalid = 1'b0;
    //     wvalid  = 1'b0;
    //     bready  = 1'b1;
    //     arvalid = 1'b0;
    //     rready  = 1'b1;
        
    //     // Initialize address/data to zero
    //     awid = '0;
    //     awaddr = '0;
    //     awlen = '0;
    //     awsize = '0;
    //     awburst = 2'b01; // INCR
    //     wdata = '0;
    //     wstrb = '0;
    //     arid = '0;
    //     araddr = '0;
    //     arlen = '0;
    //     arsize = '0;
    //     arburst = 2'b01; // INCR
    // end

endinterface : vortex_axi_if

`endif // VORTEX_AXI_IF_SV