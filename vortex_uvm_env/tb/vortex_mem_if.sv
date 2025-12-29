////////////////////////////////////////////////////////////////////////////////
// File: vortex_mem_if.sv
// Description: Vortex custom memory interface with proper clocking blocks
//
// Protocol: Request-Response with valid-ready handshakes
//   - Request:  Master → Slave (read or write)
//   - Response: Slave → Master (data or ack)
//
// Clocking Blocks:
//   - master_cb:  For drivers (active agents)
//   - slave_cb:   For memory responders
//   - monitor_cb: For passive monitoring
//
// Author: Vortex UVM Team
// Date: 2025-01-XX
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_MEM_IF_SV
`define VORTEX_MEM_IF_SV

//`include "VX_define.vh"

import vortex_config_pkg::*;

interface vortex_mem_if (
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
    // REQUEST CHANNEL SIGNALS (Master → Slave)
    //==========================================================================
    logic                       req_valid;
    logic                       req_ready;
    logic                       req_rw;         // 0=read, 1=write
    logic [ADDR_WIDTH-1:0]      req_addr;
    logic [DATA_WIDTH-1:0]      req_data;
    logic [BYTEEN_WIDTH-1:0]    req_byteen;
    logic [TAG_WIDTH-1:0]       req_tag;

    //==========================================================================
    // RESPONSE CHANNEL SIGNALS (Slave → Master)
    //==========================================================================
    logic                       rsp_valid;
    logic                       rsp_ready;
    logic [DATA_WIDTH-1:0]      rsp_data;
    logic [TAG_WIDTH-1:0]       rsp_tag;

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
    // CLOCKING BLOCK: SLAVE (For Memory Models)
    //==========================================================================
    clocking slave_cb @(posedge clk);
        default input #1step output #0;
        
        // Request inputs (slave responds to these)
        input   req_valid;
        input   req_rw;
        input   req_addr;
        input   req_data;
        input   req_byteen;
        input   req_tag;
        output  req_ready;
        
        // Response outputs
        output  rsp_valid;
        output  rsp_data;
        output  rsp_tag;
        input   rsp_ready;
    endclocking

    //==========================================================================
    // CLOCKING BLOCK: MONITOR (For Passive Observation)
    //==========================================================================
    clocking monitor_cb @(posedge clk);
        default input #1step;
        
        // Monitor all signals (input only)
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
    // MODPORTS
    //==========================================================================
    
    // For UVM driver (uses master_cb)
    modport master_driver (
        clocking master_cb,
        input clk,
        input reset_n
    );
    
    // For memory model (uses slave_cb)
    modport slave_responder (
        clocking slave_cb,
        input clk,
        input reset_n
    );
    
    // For UVM monitor (uses monitor_cb)
    modport monitor (
        clocking monitor_cb,
        input clk,
        input reset_n
    );
    
    // For DUT connection (direct signal access)
    modport dut_master (
        output req_valid, req_rw, req_addr, req_data, req_byteen, req_tag,
        input  req_ready,
        input  rsp_valid, rsp_data, rsp_tag,
        output rsp_ready
    );
    
    modport dut_slave (
        input  req_valid, req_rw, req_addr, req_data, req_byteen, req_tag,
        output req_ready,
        output rsp_valid, rsp_data, rsp_tag,
        input  rsp_ready
    );

    //==========================================================================
    // HELPER FUNCTIONS
    //==========================================================================
    
    // Check if request handshake occurred
    function automatic bit req_fire();
        return (req_valid && req_ready);
    endfunction
    
    // Check if response handshake occurred
    function automatic bit rsp_fire();
        return (rsp_valid && rsp_ready);
    endfunction
    
    // Check if this is a read request
    function automatic bit is_read();
        return (req_valid && !req_rw);
    endfunction
    
    // Check if this is a write request
    function automatic bit is_write();
        return (req_valid && req_rw);
    endfunction

    //==========================================================================
    // TASKS FOR TESTBENCH
    //==========================================================================
    
    // Task: Wait for N clock cycles
    task automatic wait_clks(int n);
        repeat(n) @(posedge clk);
    endtask
    
    // Task: Wait for request handshake
    task automatic wait_req_handshake();
        do @(posedge clk);
        while (!req_fire());
    endtask
    
    // Task: Wait for response handshake
    task automatic wait_rsp_handshake();
        do @(posedge clk);
        while (!rsp_fire());
    endtask

    // //==========================================================================
    // // PROTOCOL ASSERTIONS
    // //==========================================================================
    
    // // Request valid must remain stable until ready
    // property req_valid_stable_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     (req_valid && !req_ready) |=> req_valid;
    // endproperty
    
    // // Request address must remain stable until handshake
    // property req_addr_stable_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     (req_valid && !req_ready) |=> $stable(req_addr);
    // endproperty
    
    // // Request data must remain stable until handshake
    // property req_data_stable_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     (req_valid && req_rw && !req_ready) |=> $stable(req_data);
    // endproperty
    
    // // Response valid must remain stable until ready
    // property rsp_valid_stable_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     (rsp_valid && !rsp_ready) |=> rsp_valid;
    // endproperty
    
    // // Response data must remain stable until handshake
    // property rsp_data_stable_p;
    //     @(posedge clk) disable iff (!reset_n)
    //     (rsp_valid && !rsp_ready) |=> $stable(rsp_data);
    // endproperty
    
    // // Assertions
    // assert_req_valid_stable: assert property (req_valid_stable_p)
    //     else $error("[VORTEX_MEM_IF] req_valid dropped before req_ready!");
    
    // assert_req_addr_stable: assert property (req_addr_stable_p)
    //     else $error("[VORTEX_MEM_IF] req_addr changed before handshake!");
    
    // assert_req_data_stable: assert property (req_data_stable_p)
    //     else $error("[VORTEX_MEM_IF] req_data changed before handshake!");
    
    // assert_rsp_valid_stable: assert property (rsp_valid_stable_p)
    //     else $error("[VORTEX_MEM_IF] rsp_valid dropped before rsp_ready!");
    
    // assert_rsp_data_stable: assert property (rsp_data_stable_p)
    //     else $error("[VORTEX_MEM_IF] rsp_data changed before handshake!");

    // //==========================================================================
    // // COVERAGE
    // //==========================================================================
    
    // covergroup mem_protocol_cg @(posedge clk);
    //     option.per_instance = 1;
        
    //     // Request types
    //     req_type_cp: coverpoint {req_valid, req_rw} {
    //         bins read  = {2'b10};
    //         bins write = {2'b11};
    //         bins idle  = {2'b00};
    //     }
        
    //     // Handshake scenarios
    //     req_handshake_cp: coverpoint {req_valid, req_ready} {
    //         bins accepted       = {2'b11};
    //         bins waiting        = {2'b10};
    //         bins idle           = {2'b00};
    //         bins ready_no_valid = {2'b01};
    //     }
        
    //     rsp_handshake_cp: coverpoint {rsp_valid, rsp_ready} {
    //         bins accepted       = {2'b11};
    //         bins waiting        = {2'b10};
    //         bins idle           = {2'b00};
    //         bins ready_no_valid = {2'b01};
    //     }
        
    //     // Byte enable patterns
    //     byteen_cp: coverpoint req_byteen {
    //         bins all_bytes   = {4'b1111};
    //         bins lower_half  = {4'b0011};
    //         bins upper_half  = {4'b1100};
    //         bins single_byte[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
    //         bins other[] = default;
    //     }
        
    //     // Cross coverage: Request type with handshake
    //     req_cross: cross req_type_cp, req_handshake_cp;
    // endgroup
    
    // mem_protocol_cg mem_cov = new();

    //==========================================================================
    // INITIAL SIGNAL VALUES
    //==========================================================================
    
    initial begin
        req_valid  = 1'b0;
        req_rw     = 1'b0;
        req_addr   = '0;
        req_data   = '0;
        req_byteen = '0;
        req_tag    = '0;
        rsp_ready  = 1'b1; // Default: always ready to accept responses
    end

endinterface : vortex_mem_if

`endif // VORTEX_MEM_IF_SV