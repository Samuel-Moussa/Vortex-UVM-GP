// ////////////////////////////////////////////////////////////////////////////////
// // File: vortex_mem_if.sv
// // Description: Vortex custom memory interface with proper clocking blocks
// //
// // Protocol: Request-Response with valid-ready handshakes
// //   - Request:  Master → Slave (read or write)
// //   - Response: Slave → Master (data or ack)
// //
// // Clocking Blocks:
// //   - master_cb:  For drivers (active agents)
// //   - slave_cb:   For memory responders
// //   - monitor_cb: For passive monitoring
// //
// // Author: Vortex UVM Team
// // Date: 2025-01-XX
// ////////////////////////////////////////////////////////////////////////////////



////////////////////////////////////////////////////////////////////////////////
// File: vortex_mem_if.sv - ARRAY VERSION
// Description: Vortex custom memory interface with ARRAY signals
//
// This version uses arrays to match Vortex port arrays directly
// No conversion needed in tb_top!
//
// Author: Vortex UVM Team
// Date: February 2026
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_MEM_IF_SV
`define VORTEX_MEM_IF_SV

import vortex_config_pkg::*;

interface vortex_mem_if #(
    parameter NUM_PORTS = 1  // Match VX_MEM_PORTS
) (
    input logic clk,
    input logic reset_n
);

    //==========================================================================
    // PARAMETERS
    //==========================================================================
    localparam ADDR_WIDTH   = vortex_config_pkg::VX_MEM_ADDR_WIDTH;
    localparam DATA_WIDTH   = vortex_config_pkg::VX_MEM_DATA_WIDTH;
    localparam BYTEEN_WIDTH = vortex_config_pkg::VX_MEM_BYTEEN_WIDTH;
    localparam TAG_WIDTH    = vortex_config_pkg::VX_MEM_TAG_WIDTH;

    //==========================================================================
    // REQUEST CHANNEL SIGNALS - ARRAYS!
    //==========================================================================
    logic                       req_valid   [NUM_PORTS];
    logic                       req_ready   [NUM_PORTS];
    logic                       req_rw      [NUM_PORTS];
    logic [ADDR_WIDTH-1:0]      req_addr    [NUM_PORTS];
    logic [DATA_WIDTH-1:0]      req_data    [NUM_PORTS];
    logic [BYTEEN_WIDTH-1:0]    req_byteen  [NUM_PORTS];
    logic [TAG_WIDTH-1:0]       req_tag     [NUM_PORTS];

    //==========================================================================
    // RESPONSE CHANNEL SIGNALS - ARRAYS!
    //==========================================================================
    logic                       rsp_valid   [NUM_PORTS];
    logic                       rsp_ready   [NUM_PORTS];
    logic [DATA_WIDTH-1:0]      rsp_data    [NUM_PORTS];
    logic [TAG_WIDTH-1:0]       rsp_tag     [NUM_PORTS];

    //==========================================================================
    // CLOCKING BLOCK: MASTER (For UVM Drivers)
    //==========================================================================
    clocking master_cb @(posedge clk);
        default input #1step output #0;
        
        // Request outputs (master drives these)
        output  req_valid;
        output  req_rw;
        output  req_addr;
        output  req_data;
        output  req_byteen;
        output  req_tag;
        input   req_ready;
        
        // Response inputs/outputs
        input   rsp_valid;
        input   rsp_data;
        input   rsp_tag;
        output  rsp_ready;
    endclocking

    //==========================================================================
    // CLOCKING BLOCK: MEMORY RESPONDER (For tb_top)
    //==========================================================================
    clocking mem_responder_cb @(posedge clk);
        default input #1step output #0;
        
        // Input: Observe requests from DUT
        input   req_valid;
        input   req_rw;
        input   req_addr;
        input   req_data;
        input   req_byteen;
        input   req_tag;
        input   rsp_ready;
        
        // Output: Drive responses
        output  req_ready;
        output  rsp_valid;
        output  rsp_data;
        output  rsp_tag;
    endclocking

    //==========================================================================
    // CLOCKING BLOCK: MONITOR
    //==========================================================================
    clocking monitor_cb @(posedge clk);
        input req_valid;
        input req_ready;
        input req_rw;
        input req_addr;
        input req_data;
        input req_byteen;
        input req_tag;
        
        input rsp_valid;
        input rsp_ready;
        input rsp_data;
        input rsp_tag;
    endclocking

    //==========================================================================
    // ASSERTIONS
    //==========================================================================
    
    // Request protocol checks (for port 0)
    property req_valid_stable;
        @(posedge clk) disable iff (!reset_n)
        (req_valid[0] && !req_ready[0]) |=> $stable(req_valid[0]);
    endproperty
    
    property req_addr_stable;
        @(posedge clk) disable iff (!reset_n)
        (req_valid[0] && !req_ready[0]) |=> $stable(req_addr[0]);
    endproperty
    
    assert_req_valid_stable: assert property (req_valid_stable)
        else $error("[MEM_IF] req_valid changed while !req_ready");
    
    assert_req_addr_stable: assert property (req_addr_stable)
        else $error("[MEM_IF] req_addr changed while !req_ready");
    
    // Response protocol checks (for port 0)
    property rsp_valid_stable;
        @(posedge clk) disable iff (!reset_n)
        (rsp_valid[0] && !rsp_ready[0]) |=> $stable(rsp_valid[0]);
    endproperty
    
    property rsp_data_stable;
        @(posedge clk) disable iff (!reset_n)
        (rsp_valid[0] && !rsp_ready[0]) |=> $stable(rsp_data[0]);
    endproperty
    
    assert_rsp_valid_stable: assert property (rsp_valid_stable)
        else $error("[MEM_IF] rsp_valid changed while !rsp_ready");
    
    assert_rsp_data_stable: assert property (rsp_data_stable)
        else $error("[MEM_IF] rsp_data changed while !rsp_ready");

    //==========================================================================
    // DEBUG
    //==========================================================================
    
    `ifdef DEBUG_MEM_IF
    always @(posedge clk) begin
        if (req_valid[0] && req_ready[0]) begin
            $display("[MEM_IF @ %0t] REQ: %s addr=0x%h tag=%0d",
                     $time, req_rw[0] ? "WRITE" : "READ", 
                     req_addr[0], req_tag[0]);
        end
        if (rsp_valid[0] && rsp_ready[0]) begin
            $display("[MEM_IF @ %0t] RSP: data=0x%h tag=%0d",
                     $time, rsp_data[0], rsp_tag[0]);
        end
    end
    `endif

endinterface : vortex_mem_if

`endif // VORTEX_MEM_IF_SV