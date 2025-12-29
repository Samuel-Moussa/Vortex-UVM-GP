////////////////////////////////////////////////////////////////////////////////
// File: dcr_driver.sv
// Description: DCR Agent Driver with Clocking Block Support
//
// This driver actively drives DCR write transactions onto the Vortex DCR
// interface. DCR writes are simple single-cycle pulses with no handshake
// or response.
//
// Protocol:
//   1. Assert wr_valid HIGH with addr and data
//   2. Hold for 1 clock cycle
//   3. Deassert wr_valid
//   4. Transaction complete (no response)
//
// Key Features:
//   ✓ Uses master_cb clocking block for clean timing
//   ✓ Shadow register tracking (local copy of DCR state)
//   ✓ Configuration verification
//   ✓ Statistics collection
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef DCR_DRIVER_SV
`define DCR_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import dcr_agent_pkg::*;


class dcr_driver extends uvm_driver #(dcr_transaction);
    `uvm_component_utils(dcr_driver)
    
    //==========================================================================
    // Virtual Interface Handle
    // Uses master_driver modport with clocking block
    //==========================================================================
    virtual vortex_dcr_if.master_driver vif;
    
    //==========================================================================
    // Configuration Object
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Shadow Register Map
    // Local copy of all DCR values written (for verification)
    //==========================================================================
    bit [31:0] dcr_shadow[bit [31:0]];
    
    //==========================================================================
    // Statistics Counters
    //==========================================================================
    int num_writes;           // Total DCR writes
    int num_startup_configs;  // Startup-related DCRs
    int num_perf_configs;     // Performance monitor DCRs
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "dcr_driver", uvm_component parent = null);
        super.new(name, parent);
        num_writes = 0;
        num_startup_configs = 0;
        num_perf_configs = 0;
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Get virtual interface from config DB
        if (!uvm_config_db#(virtual vortex_dcr_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DCR_DRV", "Failed to get virtual interface from config DB")
        end
        
        // Get configuration object
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_warning("DCR_DRV", "No vortex_config found - using defaults")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
    endfunction
    
    //==========================================================================
    // Reset Phase
    // Initialize interface signals to idle state
    //==========================================================================
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        
        phase.raise_objection(this);
        
        // Initialize all DCR signals to idle using clocking block
        @(vif.master_cb);
        vif.master_cb.wr_valid <= 1'b0;
        vif.master_cb.wr_addr  <= '0;
        vif.master_cb.wr_data  <= '0;
        
        // Clear shadow register map
        dcr_shadow.delete();
        
        `uvm_info("DCR_DRV", "DCR driver reset complete", UVM_MEDIUM)
        
        phase.drop_objection(this);
    endtask
    
    //==========================================================================
    // Run Phase
    // Main driver loop: get transactions and drive them
    //==========================================================================
    virtual task run_phase(uvm_phase phase);
        dcr_transaction trans;
        
        forever begin
            // Get next transaction from sequencer
            seq_item_port.get_next_item(trans);
            
            `uvm_info("DCR_DRV", $sformatf("Driving DCR write:\n%s", 
                trans.convert2string()), UVM_HIGH)
            
            // Drive the DCR write
            drive_dcr_write(trans);
            
            // Notify sequencer we're done
            seq_item_port.item_done();
        end
    endtask
    
    //==========================================================================
    // Drive Single DCR Write
    // Single-cycle write pulse using clocking block
    //==========================================================================
    virtual task drive_dcr_write(dcr_transaction trans);
        
        // Record write time
        trans.write_time = $time;
        
        // Drive write signals for 1 clock cycle using clocking block
        @(vif.master_cb);
        vif.master_cb.wr_valid <= 1'b1;
        vif.master_cb.wr_addr  <= trans.addr;
        vif.master_cb.wr_data  <= trans.data;
        
        // Deassert valid on next cycle
        @(vif.master_cb);
        vif.master_cb.wr_valid <= 1'b0;
        
        // Mark transaction as completed
        trans.completed = 1;
        
        // Update statistics
        num_writes++;
        if (trans.is_startup_config()) num_startup_configs++;
        if (trans.is_perf_config()) num_perf_configs++;
        
        // Update shadow register map
        dcr_shadow[trans.addr] = trans.data;
        
        `uvm_info("DCR_DRV", $sformatf("DCR write complete: %s = 0x%08h",
            trans.get_dcr_name(), trans.data), UVM_MEDIUM)
    endtask
    
    //==========================================================================
    // Get DCR Value from Shadow Map
    // Allows other components to query DCR state
    //==========================================================================
    function bit [31:0] get_dcr_value(bit [31:0] addr);
        if (dcr_shadow.exists(addr)) 
            return dcr_shadow[addr];
        else begin
            `uvm_warning("DCR_DRV", $sformatf("DCR 0x%h never written", addr))
            return 32'h0;
        end
    endfunction
    
    //==========================================================================
    // Check Phase
    // Verify critical DCRs were configured
    //==========================================================================
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        
        // Warn if startup address was never configured
        if (!dcr_shadow.exists(dcr_transaction::DCR_STARTUP_ADDR0)) begin
            `uvm_warning("DCR_DRV", "STARTUP_ADDR0 never configured - GPU may not start")
        end
        
        // Verify word alignment for startup PC
        if (dcr_shadow.exists(dcr_transaction::DCR_STARTUP_ADDR0)) begin
            if (dcr_shadow[dcr_transaction::DCR_STARTUP_ADDR0][1:0] != 2'b00) begin
                `uvm_error("DCR_DRV", $sformatf(
                    "STARTUP_ADDR0 not word-aligned: 0x%h",
                    dcr_shadow[dcr_transaction::DCR_STARTUP_ADDR0]))
            end
        end
    endfunction
    
    //==========================================================================
    // Report Phase
    // Print statistics and DCR state summary
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("DCR_DRV", {"\n",
            "========================================\n",
            "    DCR Driver Statistics\n",
            "========================================\n",
            $sformatf("  Total Writes:       %0d\n", num_writes),
            $sformatf("  Startup Configs:    %0d\n", num_startup_configs),
            $sformatf("  Perf Configs:       %0d\n", num_perf_configs),
            $sformatf("  Unique DCRs:        %0d\n", dcr_shadow.size()),
            "========================================\n",
            "  DCR Shadow State:\n"
        }, UVM_LOW)
        
        // Print all configured DCRs
        foreach (dcr_shadow[addr]) begin
            dcr_transaction temp_trans = dcr_transaction::type_id::create("temp");
            temp_trans.addr = addr;
            `uvm_info("DCR_DRV", $sformatf("    %s = 0x%08h",
                temp_trans.get_dcr_name(), dcr_shadow[addr]), UVM_LOW)
        end
    endfunction
    
endclass : dcr_driver

`endif // DCR_DRIVER_SV
