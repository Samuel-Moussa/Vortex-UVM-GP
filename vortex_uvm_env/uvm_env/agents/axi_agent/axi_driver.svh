////////////////////////////////////////////////////////////////////////////////
// File: axi_driver.svh
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
    logic [vortex_config_pkg::AXI_ID_WIDTH-1:0]    b_resp_q[$]; 
    
    logic [vortex_config_pkg::AXI_ID_WIDTH-1:0]    aw_id_reg;
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0]  aw_addr_reg;
    
    logic [vortex_config_pkg::AXI_ID_WIDTH-1:0]    ar_id_reg;
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0]  ar_addr_reg;
    logic [7:0]                                    ar_len_reg;
    logic [7:0]                                    read_beat_count;
    logic [vortex_config_pkg::AXI_ID_WIDTH-1:0]    aw_queue[$];   // Queue of IDs for pending writes
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0]  aw_addr_queue[$];
    logic                                          aw_active;
    logic [vortex_config_pkg::AXI_ID_WIDTH-1:0]    aw_active_id;
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0]  aw_active_addr;

    // Backpressure throttle — plusarg-gated (+AXI_THROTTLE). Default OFF => the
    // ready signals behave EXACTLY as before (zero effect on the regression suite).
    // When ON, the slave periodically deasserts awready/wready/arready for one cycle
    // (ready stays high 3-4 of every 4-5 cycles => bounded latency, no deadlock, data
    // integrity preserved — AXI permits arbitrary ready latency). This forces
    // `valid && !ready`, exercising the master-side AXI stability assertions and the
    // downstream elastic-buffer backpressure conditions/branches — a REAL protocol test.
    bit throttle_en = 1'b0;
    int thr_aw = 0, thr_w = 0, thr_ar = 0;

    // Read-flood — plusarg-gated (+AXI_FLOOD). Default OFF. When ON, the slave greedily
    // accepts every AR and streams R responses back-to-back (instead of one-at-a-time),
    // so a burst of outstanding reads floods the DUT's read-response path faster than it
    // can drain -> the DUT deasserts m_axi_rready (= rsp_xbar_ready_in, VX_axi_adapter.sv:332)
    // -> exercises assert_r_valid_stable / assert_r_data_stable (the DUT holding R stable
    // while IT backpressures). Data is served in-order from a FIFO -> byte-exact preserved.
    // (b_valid_stable is NOT reachable: the adapter hardwires m_axi_bready=1'b1 @ :313.)
    bit flood_en = 1'b0;
    logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0] ar_flood_addr_q[$];
    logic [vortex_config_pkg::AXI_ID_WIDTH-1:0]   ar_flood_id_q[$];

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

        if ($test$plusargs("AXI_THROTTLE")) begin
            throttle_en = 1'b1;
            `uvm_info("AXI_DRV", "AXI_THROTTLE enabled — slave will inject ready wait-states (backpressure test)", UVM_LOW)
        end
        if ($test$plusargs("AXI_FLOOD")) begin
            flood_en = 1'b1;
            `uvm_info("AXI_DRV", "AXI_FLOOD enabled — slave streams read responses back-to-back (forces DUT rready backpressure)", UVM_LOW)
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
            thr_aw = thr_aw + 1;
            // throttle: hold awready LOW most cycles (pulse high 1-in-4) so an arriving
            // awvalid reliably sees !awready for >=1 cycle -> exercises stability asserts
            vif.awready <= throttle_en ? ((thr_aw % 4) == 0) : 1'b1;
            if (vif.awvalid && vif.awready) begin
                aw_queue.push_back(vif.awid);
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
            
            thr_w = thr_w + 1;
            if (write_complete_flag) begin
                vif.wready <= 1'b0;
                write_complete_flag = 1'b0;
            end else begin
                // throttle: hold wready LOW (pulse high 1-in-5) while a write is active
                vif.wready <= aw_active && (throttle_en ? ((thr_w % 5) == 0) : 1'b1);
            end
            
            if (vif.wvalid && vif.wready && aw_active) begin
                automatic bit [vortex_config_pkg::AXI_ADDR_WIDTH-1:0] addr = aw_active_addr;
                automatic bit [511:0] data = vif.wdata;
                automatic bit [63:0] wstrb = vif.wstrb;
                
                for (int i = 0; i < 64; i++) begin
                    if (wstrb[i]) memory.write_byte(addr + i, data[i*8 +: 8]);
                end
                
                if (vif.wlast) begin
                    b_resp_q.push_back(aw_active_id);  // Queue B response with the full-width AW ID
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
        if (flood_en) begin
            handle_ar_r_flood();   // aggressive back-to-back streaming (never returns)
            return;
        end
        vif.arready <= 1'b0;
        vif.rvalid  <= 1'b0;
        forever begin
            @(posedge vif.clk);

            // Cannot accept a new address until previous read finishes
            thr_ar = thr_ar + 1;
            // throttle: hold arready LOW (pulse high 1-in-3) while no read in flight
            vif.arready <= !vif.rvalid && (throttle_en ? ((thr_ar % 3) == 0) : 1'b1);

            if (vif.arvalid && vif.arready) begin
                ar_id_reg         = vif.arid;
                ar_addr_reg       = vif.araddr;
                ar_len_reg        = vif.arlen;
                read_beat_count   = '0;

                vif.rvalid        <= 1'b1;
                vif.rid           <= vif.arid;
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
    // AR/R flood: greedily accept every AR (arready always high) and stream single-beat
    // R responses back-to-back from an in-order FIFO. When the DUT deasserts rready
    // (rvalid && !rready) the current beat is HELD stable -> exercises r_valid/r_data
    // stable. Data served in program order per FIFO -> byte-exact vs SimX preserved.
    //--------------------------------------------------------------------------
    virtual task handle_ar_r_flood();
        vif.arready <= 1'b1;   // always accept addresses (flood)
        vif.rvalid  <= 1'b0;
        forever begin
            @(posedge vif.clk);
            vif.arready <= 1'b1;
            if (vif.arvalid && vif.arready) begin
                ar_flood_addr_q.push_back(vif.araddr);
                ar_flood_id_q.push_back(vif.arid);
            end
            // Advance the response only when the current beat was accepted (rready) or
            // no beat is in flight. While (rvalid && !rready) we fall through and hold
            // rvalid/rdata/rid stable — that is the case the stability assertions check.
            if (!vif.rvalid || vif.rready) begin
                if (ar_flood_addr_q.size() > 0) begin
                    automatic logic [vortex_config_pkg::AXI_ADDR_WIDTH-1:0] a = ar_flood_addr_q.pop_front();
                    vif.rvalid <= 1'b1;
                    vif.rid    <= ar_flood_id_q.pop_front();
                    vif.rdata  <= memory.read_line(a);
                    vif.rresp  <= 2'b00;
                    vif.rlast  <= 1'b1;   // Vortex AR is single-beat (arlen=0)
                    num_reads_served++;
                end else begin
                    vif.rvalid <= 1'b0;
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