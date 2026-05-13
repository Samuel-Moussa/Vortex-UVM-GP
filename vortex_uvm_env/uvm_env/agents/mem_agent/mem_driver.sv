////////////////////////////////////////////////////////////////////////////////
// File: mem_driver.sv
// Description: Custom Memory Agent Driver (Slave Responder)
//
// This driver acts as the memory responder for the Vortex DUT when the custom
// memory interface is used (USE_AXI_WRAPPER is NOT defined).
// It monitors requests from the DUT and interacts with the shared `mem_model`.
////////////////////////////////////////////////////////////////////////////////

`ifndef MEM_DRIVER_SV
`define MEM_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import mem_agent_pkg::*;
import mem_model_pkg::*;

class mem_driver extends uvm_driver #(mem_transaction);
    `uvm_component_utils(mem_driver)
    
    //==========================================================================
    // Virtual Interface Handle
    //==========================================================================
    virtual vortex_mem_if vif;
    
    //==========================================================================
    // Configuration & Memory Model
    //==========================================================================
    vortex_config cfg;
    mem_model     memory;
    
    //==========================================================================
    // Local State for Response
    //==========================================================================
    logic                                            mem_rsp_valid_r;
    logic [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0] mem_rsp_data_r;
    logic [vortex_config_pkg::VX_MEM_TAG_WIDTH-1:0]  mem_rsp_tag_r;

    // Statistics
    int num_reads;
    int num_writes;
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mem_driver", uvm_component parent = null);
        super.new(name, parent);
        num_reads  = 0;
        num_writes = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual vortex_mem_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MEM_DRV", "Failed to get virtual interface from config DB")
        end
        
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("MEM_DRV", "No vortex_config found - using defaults", UVM_LOW)
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end

        if (!uvm_config_db#(mem_model)::get(this, "", "mem_model", memory)) begin
            `uvm_fatal("MEM_DRV", "Failed to get mem_model from config DB! Responder requires memory access.")
        end
    endfunction
    
    //==========================================================================
    // Reset Phase
    //==========================================================================
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        phase.raise_objection(this);

        `uvm_info("MEM_DRV", "Waiting for reset...", UVM_MEDIUM)
        
        if (vif.reset_n !== 1'b0) wait(vif.reset_n === 1'b0);

        mem_rsp_valid_r = 1'b0;
        mem_rsp_data_r  = '0;
        mem_rsp_tag_r   = '0;

        wait(vif.reset_n === 1'b1);
        `uvm_info("MEM_DRV", "Reset complete — Custom MEM responder ready", UVM_MEDIUM)
        
        phase.drop_objection(this);
    endtask

    //==========================================================================
    // Run Phase
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        wait(vif.reset_n === 1'b1);
        
        // Emulate COMBINATIONAL continuous assignment safely inside a class
        fork
            forever begin
                vif.req_ready[0] = (!mem_rsp_valid_r || vif.rsp_ready[0]);
                vif.rsp_valid[0] = mem_rsp_valid_r;
                vif.rsp_data[0]  = mem_rsp_data_r;
                vif.rsp_tag[0]   = mem_rsp_tag_r;
                @(mem_rsp_valid_r or vif.rsp_ready[0] or mem_rsp_data_r or mem_rsp_tag_r);
            end
        join_none

        forever begin
            @(posedge vif.clk);
            
            if (mem_rsp_valid_r && vif.rsp_ready[0]) begin
                mem_rsp_valid_r = 1'b0;
            end

            if (vif.req_valid[0] && (!mem_rsp_valid_r || vif.rsp_ready[0])) begin
                automatic bit [31:0] byte_addr = vif.req_addr[0] << 6;
                
                if (vif.req_rw[0]) begin
                    // Write Request
                    automatic bit [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0] wdata = vif.req_data[0];
                    automatic bit [vortex_config_pkg::VX_MEM_BYTEEN_WIDTH-1:0] byteen = vif.req_byteen[0];
                    
                    for (int i = 0; i < vortex_config_pkg::VX_MEM_BYTEEN_WIDTH; i++) begin
                        if (byteen[i]) begin
                            memory.write_byte(byte_addr + i, wdata[i*8 +: 8]);
                        end
                    end
                    num_writes++;
                    `uvm_info("MEM_DRV", $sformatf("MEM WRITE ACCEPTED: byte_addr=0x%08h tag=0x%02h", 
                              byte_addr, vif.req_tag[0]), UVM_HIGH)
                            
                end else begin
                    // Read Request
                    automatic logic [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0] rdata = memory.read_line(byte_addr);
                    
                    // X-State Protection (Defaulting to NOPs if uninitialized)
                    for (int i = 0; i < vortex_config_pkg::VX_MEM_DATA_WIDTH/32; i++) begin
                        if ($isunknown(rdata[i*32 +: 32])) begin
                            rdata[i*32 +: 32] = 32'h00000013;
                        end
                    end
                    
                    mem_rsp_valid_r = 1'b1;
                    mem_rsp_data_r  = rdata;
                    mem_rsp_tag_r   = vif.req_tag[0];
                    
                    num_reads++;
                    `uvm_info("MEM_DRV", $sformatf("MEM READ QUEUED: byte_addr=0x%08h tag=0x%02h", 
                              byte_addr, vif.req_tag[0]), UVM_HIGH)
                end
            end
        end
    endtask
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("MEM_DRV", {"\n",
            "========================================\n",
            "    Memory Driver (Responder) Stats\n",
            "========================================\n",
            $sformatf("  Total Reads Processed:  %0d\n", num_reads),
            $sformatf("  Total Writes Processed: %0d\n", num_writes),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : mem_driver

`endif // MEM_DRIVER_SV