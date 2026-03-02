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

// `ifndef VORTEX_MEM_IF_SV
// `define VORTEX_MEM_IF_SV

// //`include "VX_define.vh"

// import vortex_config_pkg::*;

// interface vortex_mem_if (
//     input logic clk,
//     input logic reset_n
// );

// //==========================================================================
//     // PARAMETERS
//     //==========================================================================
//     localparam ADDR_WIDTH   = vortex_config_pkg::VX_MEM_ADDR_WIDTH;
//     localparam DATA_WIDTH   = vortex_config_pkg::VX_MEM_DATA_WIDTH;
//     localparam BYTEEN_WIDTH = vortex_config_pkg::VX_MEM_BYTEEN_WIDTH;
//     localparam TAG_WIDTH    = vortex_config_pkg::VX_MEM_TAG_WIDTH;

//     //==========================================================================
//     // REQUEST CHANNEL SIGNALS (Master → Slave)
//     //==========================================================================
//     logic                       req_valid;
//     logic                       req_ready;
//     logic                       req_rw;         // 0=read, 1=write
//     logic [ADDR_WIDTH-1:0]      req_addr;
//     logic [DATA_WIDTH-1:0]      req_data;
//     logic [BYTEEN_WIDTH-1:0]    req_byteen;
//     logic [TAG_WIDTH-1:0]       req_tag;

//     //==========================================================================
//     // RESPONSE CHANNEL SIGNALS (Slave → Master)
//     //==========================================================================
//     logic                       rsp_valid;
//     logic                       rsp_ready;
//     logic [DATA_WIDTH-1:0]      rsp_data;
//     logic [TAG_WIDTH-1:0]       rsp_tag;

//     //==========================================================================
//     // CLOCKING BLOCK: MASTER (For UVM Drivers)
//     //==========================================================================
//     clocking master_cb @(posedge clk);
//         default input #1step output #0;
        
//         // Request outputs (master drives these)
//         output  req_valid;
//         output  req_rw;
//         output  req_addr;
//         output  req_data;
//         output  req_byteen;
//         output  req_tag;
//         input   req_ready;
        
//         // Response inputs/outputs
//         input   rsp_valid;
//         input   rsp_data;
//         input   rsp_tag;
//         output  rsp_ready;
//     endclocking

//     //==========================================================================
//     // CLOCKING BLOCK: SLAVE (For Memory Models)
//     //==========================================================================
//     clocking slave_cb @(posedge clk);
//         default input #1step output #0;
        
//         // Request inputs (slave responds to these)
//         input   req_valid;
//         input   req_rw;
//         input   req_addr;
//         input   req_data;
//         input   req_byteen;
//         input   req_tag;
//         output  req_ready;
        
//         // Response outputs
//         output  rsp_valid;
//         output  rsp_data;
//         output  rsp_tag;
//         input   rsp_ready;
//     endclocking

    
    
// //==========================================================================
// // CLOCKING BLOCK: MONITOR (for UVM Monitor - observe all signals)
// //==========================================================================
// clocking monitor_cb @(posedge clk);
//     input req_valid;
//     input req_ready;
//     input req_rw;
//     input req_addr;
//     input req_data;
//     input req_byteen;
//     input req_tag;
    
//     input rsp_valid;
//     input rsp_ready;
//     input rsp_data;
//     input rsp_tag;
// endclocking

// //==========================================================================
// // CLOCKING BLOCK: MEM_RESPONDER (for Memory Model - ONLY response signals)
// //==========================================================================
// clocking mem_responder_cb @(posedge clk);
//     // Input: Observe requests from DUT (read-only, no driving)
//     input  req_valid;
//     input  req_rw;
//     input  req_addr;
//     input  req_data;
//     input  req_byteen;
//     input  req_tag;
//     input  rsp_ready;
    
//     // Output: Drive ONLY response signals (DUT doesn't drive these)
//     output req_ready;
//     output rsp_valid;
//     output rsp_data;
//     output rsp_tag;
// endclocking


//     // //==========================================================================
//     // // MODPORTS
//     // //==========================================================================
    
//     // For UVM driver (uses master_cb)
//     modport master_driver (
//         clocking master_cb,
//         input clk,
//         input reset_n
//     );
    
//     // For memory model (uses slave_cb)
//     modport slave_responder (
//         clocking slave_cb,
//         input clk,
//         input reset_n
//     );
    
//     // For UVM monitor (uses monitor_cb)
//     modport monitor (
//         clocking monitor_cb,
//         input clk,
//         input reset_n
//     );
    
//     // For testbench memory responder (uses mem_responder_cb)

//     modport mem_responder (
//     input clk,
//     input reset_n,
//     clocking mem_responder_cb
// );

    
//     // // For DUT connection (direct signal access)
//     // modport dut_master (
//     //     output req_valid, req_rw, req_addr, req_data, req_byteen, req_tag,
//     //     input  req_ready,
//     //     input  rsp_valid, rsp_data, rsp_tag,
//     //     output rsp_ready
//     // );
    
//     // modport dut_slave (
//     //     input  req_valid, req_rw, req_addr, req_data, req_byteen, req_tag,
//     //     output req_ready,
//     //     output rsp_valid, rsp_data, rsp_tag,
//     //     input  rsp_ready
//     // );



// // //==========================================================================
// // // MODPORTS
// // //==========================================================================
// // modport monitor (
// //     input clk,
// //     input reset_n,
// //     input req_valid, req_ready, req_rw, req_addr, req_data, req_byteen, req_tag,
// //     input rsp_valid, rsp_ready, rsp_data, rsp_tag,
// //     clocking monitor_cb
// // );


// // // Deprecated - for backward compatibility
// // modport master_cb (
// //     input clk,
// //     input reset_n,
// //     clocking monitor_cb  // Driver sees everything as input when passive
// // );


//     //==========================================================================
//     // HELPER FUNCTIONS
//     //==========================================================================
    
//     // Check if request handshake occurred
//     function automatic bit req_fire();
//         return (req_valid && req_ready);
//     endfunction
    
//     // Check if response handshake occurred
//     function automatic bit rsp_fire();
//         return (rsp_valid && rsp_ready);
//     endfunction
    
//     // Check if this is a read request
//     function automatic bit is_read();
//         return (req_valid && !req_rw);
//     endfunction
    
//     // Check if this is a write request
//     function automatic bit is_write();
//         return (req_valid && req_rw);
//     endfunction

//     //==========================================================================
//     // TASKS FOR TESTBENCH
//     //==========================================================================
    
//     // Task: Wait for N clock cycles
//     task automatic wait_clks(int n);
//         repeat(n) @(posedge clk);
//     endtask
    
//     // Task: Wait for request handshake
//     task automatic wait_req_handshake();
//         do @(posedge clk);
//         while (!req_fire());
//     endtask
    
//     // Task: Wait for response handshake
//     task automatic wait_rsp_handshake();
//         do @(posedge clk);
//         while (!rsp_fire());
//     endtask

//     //==========================================================================
//     // PROTOCOL ASSERTIONS
//     //==========================================================================
    
//     // Request valid must remain stable until ready
//     property req_valid_stable_p;
//         @(posedge clk) disable iff (!reset_n)
//         (req_valid && !req_ready) |=> req_valid;
//     endproperty
    
//     // Request address must remain stable until handshake
//     property req_addr_stable_p;
//         @(posedge clk) disable iff (!reset_n)
//         (req_valid && !req_ready) |=> $stable(req_addr);
//     endproperty
    
//     // Request data must remain stable until handshake
//     property req_data_stable_p;
//         @(posedge clk) disable iff (!reset_n)
//         (req_valid && req_rw && !req_ready) |=> $stable(req_data);
//     endproperty
    
//     // Response valid must remain stable until ready
//     property rsp_valid_stable_p;
//         @(posedge clk) disable iff (!reset_n)
//         (rsp_valid && !rsp_ready) |=> rsp_valid;
//     endproperty
    
//     // Response data must remain stable until handshake
//     property rsp_data_stable_p;
//         @(posedge clk) disable iff (!reset_n)
//         (rsp_valid && !rsp_ready) |=> $stable(rsp_data);
//     endproperty
    
//     // Assertions
//     assert_req_valid_stable: assert property (req_valid_stable_p)
//         else $error("[VORTEX_MEM_IF] req_valid dropped before req_ready!");
    
//     assert_req_addr_stable: assert property (req_addr_stable_p)
//         else $error("[VORTEX_MEM_IF] req_addr changed before handshake!");
    
//     assert_req_data_stable: assert property (req_data_stable_p)
//         else $error("[VORTEX_MEM_IF] req_data changed before handshake!");
    
//     assert_rsp_valid_stable: assert property (rsp_valid_stable_p)
//         else $error("[VORTEX_MEM_IF] rsp_valid dropped before rsp_ready!");
    
//     assert_rsp_data_stable: assert property (rsp_data_stable_p)
//         else $error("[VORTEX_MEM_IF] rsp_data changed before handshake!");

//     //==========================================================================
//     // COVERAGE
//     //==========================================================================
    
//     covergroup mem_protocol_cg @(posedge clk);
//         option.per_instance = 1;
        
//         // Request types
//         req_type_cp: coverpoint {req_valid, req_rw} {
//             bins read  = {2'b10};
//             bins write = {2'b11};
//             bins idle  = {2'b00};
//         }
        
//         // Handshake scenarios
//         req_handshake_cp: coverpoint {req_valid, req_ready} {
//             bins accepted       = {2'b11};
//             bins waiting        = {2'b10};
//             bins idle           = {2'b00};
//             bins ready_no_valid = {2'b01};
//         }
        
//         rsp_handshake_cp: coverpoint {rsp_valid, rsp_ready} {
//             bins accepted       = {2'b11};
//             bins waiting        = {2'b10};
//             bins idle           = {2'b00};
//             bins ready_no_valid = {2'b01};
//         }
        
//         // Byte enable patterns
//         byteen_cp: coverpoint req_byteen {
//             bins all_bytes   = {4'b1111};
//             bins lower_half  = {4'b0011};
//             bins upper_half  = {4'b1100};
//             bins single_byte[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
//             bins other[] = default;
//         }
        
//         // Cross coverage: Request type with handshake
//         req_cross: cross req_type_cp, req_handshake_cp;
//     endgroup
    
//     mem_protocol_cg mem_cov = new();

//     //==========================================================================
//     // INITIAL SIGNAL VALUES
//     //==========================================================================
    
//     // initial begin
//     //     req_valid  = 1'b0;
//     //     req_rw     = 1'b0;
//     //     req_addr   = '0;
//     //     req_data   = '0;
//     //     req_byteen = '0;
//     //     req_tag    = '0;
//     //     rsp_ready  = 1'b1; // Default: always ready to accept responses
//     // end

// endinterface : vortex_mem_if

// `endif // VORTEX_MEM_IF_SV




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