////////////////////////////////////////////////////////////////////////////////
// File: axi_driver.sv
// Description: AXI4 Slave Driver (Responder)
//
// This driver acts as the memory responder for the Vortex DUT, which is an
// AXI Master. It monitors the AW/W/AR channels and responds on the B/R channels
// by interacting with the shared `mem_model`.
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import axi_agent_pkg::*;
import mem_model_pkg::*;

class axi_driver extends uvm_driver #(axi_transaction);
    `uvm_component_utils(axi_driver)

    // Virtual interface handle (full type, no modport in declaration).
    // Clocking blocks (master_cb, driver_cb) are accessed via vif.master_cb, vif.driver_cb
    virtual vortex_axi_if #(
        vortex_config_pkg::AXI_ADDR_WIDTH,
        vortex_config_pkg::AXI_DATA_WIDTH,
        vortex_config_pkg::AXI_ID_WIDTH
    ) vif;

    vortex_config cfg;
    mem_model     memory;

    // Statistics
    int num_reads_served = 0;
    int num_writes_served = 0;

    // Queues and Registers for tracking transactions
    logic [7:0] b_resp_q[$]; 
    
    logic [7:0]                                        aw_id_reg;
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0]      aw_addr_reg;
    
    logic [7:0]                                        ar_id_reg;
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0]      ar_addr_reg;
    logic [7:0]                                        ar_len_reg;
    logic [7:0]                                        read_beat_count;
    logic [7:0] aw_queue[$];   // Queue of IDs for pending writes
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0] aw_addr_queue[$];
    logic                                          aw_active;
    logic [7:0]                                    aw_active_id;
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0]  aw_active_addr;

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------
    function new(string name = "axi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // Build Phase
    //--------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(virtual vortex_axi_if #(
            vortex_config_pkg::AXI_ADDR_WIDTH,
            vortex_config_pkg::AXI_DATA_WIDTH,
            vortex_config_pkg::AXI_ID_WIDTH
        ))::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_DRV", "Failed to get virtual interface from config DB")
        end

        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("AXI_DRV", "No vortex_config found — using defaults", UVM_LOW)
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end

        if (!uvm_config_db#(mem_model)::get(this, "", "mem_model", memory)) begin
            `uvm_fatal("AXI_DRV", "Failed to get mem_model from config DB! AXI responder requires memory access.")
        end
    endfunction

    //--------------------------------------------------------------------------
    // Reset Phase
    //--------------------------------------------------------------------------
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        phase.raise_objection(this);

        `uvm_info("AXI_DRV", "Waiting for reset...", UVM_MEDIUM)

        if (vif.reset_n !== 1'b0) wait(vif.reset_n === 1'b0);

        // Initialize TB-driven slave response signals (direct assignment)
        vif.awready <= 1'b0;
        vif.wready  <= 1'b0;
        vif.bvalid  <= 1'b0;
        vif.bresp   <= 2'b00;
        vif.arready <= 1'b0;
        vif.rvalid  <= 1'b0;
        vif.rlast   <= 1'b0;
        
        aw_id_reg       = '0;
        aw_addr_reg     = '0;
        ar_id_reg       = '0;
        ar_addr_reg     = '0;
        ar_len_reg      = '0;
        read_beat_count = '0;
        b_resp_q.delete();
        aw_queue.delete();
        aw_addr_queue.delete();
        aw_active      = 1'b0;
        aw_active_id   = '0;
        aw_active_addr = '0;

        wait(vif.reset_n === 1'b1);
        `uvm_info("AXI_DRV", "Reset complete — slave responder ready", UVM_MEDIUM)
        
        phase.drop_objection(this);
    endtask

    //--------------------------------------------------------------------------
    // Run Phase
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        wait(vif.reset_n === 1'b1);
        
        fork
            handle_aw_channel();
            handle_w_channel();
            handle_b_channel();
            handle_ar_r_channels();
        join_none
    endtask

    //--------------------------------------------------------------------------
    // AW Channel: Accept Address
    //--------------------------------------------------------------------------
    virtual task handle_aw_channel();
        vif.awready <= 1'b0;
        forever begin
            @(posedge vif.clk);
            vif.awready <= 1'b1;
            if (vif.awvalid && vif.awready) begin
                aw_queue.push_back(vif.awid[7:0]);
                aw_addr_queue.push_back(vif.awaddr);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // W Channel: Accept Data & Write to mem_model
    //--------------------------------------------------------------------------
    virtual task handle_w_channel();
        logic write_complete_flag;
        write_complete_flag = 1'b0;
        vif.wready <= 1'b0;
        forever begin
            @(posedge vif.clk);

            // Latch one AW context and keep it until the WLAST beat.
            if (!aw_active && aw_queue.size() > 0) begin
                aw_active      = 1'b1;
                aw_active_id   = aw_queue.pop_front();
                aw_active_addr = aw_addr_queue.pop_front();
            end
            
            if (write_complete_flag) begin
                vif.wready <= 1'b0;
                write_complete_flag = 1'b0;
            end else begin
                vif.wready <= aw_active;
            end
            
            if (vif.wvalid && vif.wready && aw_active) begin
                automatic logic [7:0] aw_id = aw_active_id;
                automatic bit [vortex_config_pkg::AXI_ADDR_WIDTH-1:0] addr = aw_active_addr;
                automatic bit [511:0] data = vif.wdata;
                automatic bit [63:0] wstrb = vif.wstrb;
                
                for (int i = 0; i < 64; i++) begin
                    if (wstrb[i]) memory.write_byte(addr + i, data[i*8 +: 8]);
                end
                
                if (vif.wlast) begin
                    b_resp_q.push_back(aw_id);  // Queue B response with correct AW ID
                    write_complete_flag = 1'b1;
                    aw_active = 1'b0;
                end
            end
        end
        endtask

    //--------------------------------------------------------------------------
    // B Channel: Send Write Response safely
    //--------------------------------------------------------------------------
    virtual task handle_b_channel();
        int b_timeout_counter = 0;
        
        vif.bvalid <= 1'b0;
        forever begin
            @(posedge vif.clk);

            // Complete current B response before issuing the next one.
            if (vif.bvalid && vif.bready) begin
                if (b_resp_q.size() > 0)
                    void'(b_resp_q.pop_front());
                vif.bvalid <= 1'b0;
                b_timeout_counter = 0;
            end

            if (!vif.bvalid && b_resp_q.size() > 0) begin
                vif.bvalid <= 1'b1;
                vif.bid    <= b_resp_q[0];
                vif.bresp  <= 2'b00;
                num_writes_served++;
                b_timeout_counter = 0;
            end else if (vif.bvalid && !vif.bready) begin
                b_timeout_counter++;
                if (b_timeout_counter > 1000) begin
                    `uvm_error("AXI_DRV", $sformatf("B response timeout: bid=%0d not acknowledged after 1000 cycles", vif.bid))
                    b_timeout_counter = 0;
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // AR/R Channels: Accept Address & Send Read Data Response
    //--------------------------------------------------------------------------
    virtual task handle_ar_r_channels();
        vif.arready <= 1'b0;
        vif.rvalid  <= 1'b0;
        forever begin
            @(posedge vif.clk);

            // Cannot accept a new address until previous read finishes
            vif.arready <= !vif.rvalid;

            if (vif.arvalid && vif.arready) begin
                ar_id_reg         = vif.arid[7:0];
                ar_addr_reg       = vif.araddr;
                ar_len_reg        = vif.arlen;
                read_beat_count   = '0;

                vif.rvalid        <= 1'b1;
                vif.rid           <= vif.arid[7:0];
                vif.rdata         <= memory.read_line(vif.araddr);
                vif.rresp         <= 2'b00;
                vif.rlast         <= (vif.arlen == 8'h0);
                num_reads_served++;

            end else if (vif.rvalid && vif.rready) begin
                if (read_beat_count == ar_len_reg) begin
                    vif.rvalid <= 1'b0;
                    vif.rlast  <= 1'b0;
                end else begin
                    read_beat_count++;
                    vif.rdata <= memory.read_line(ar_addr_reg + (read_beat_count << vortex_config_pkg::VX_MEM_OFFSET_BITS));
                    vif.rlast <= (read_beat_count == ar_len_reg);
                    vif.rid   <= ar_id_reg;
                end
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Report Phase
    //--------------------------------------------------------------------------
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("AXI_DRV", {"\n",
            "========================================\n",
            "    AXI Slave Responder Statistics      \n",
            "========================================\n",
            $sformatf("  Total Write Requests Served: %0d\n", num_writes_served),
            $sformatf("  Total Read Requests Served:  %0d\n", num_reads_served),
            "========================================"
        }, UVM_LOW)
    endfunction

endclass : axi_driver

`endif // AXI_DRIVER_SV