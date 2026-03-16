////////////////////////////////////////////////////////////////////////////////
// File: dcr_sequences.sv
// Description: DCR Sequence Library for Vortex GPU Configuration
//
// This file contains a collection of reusable DCR sequences for configuring
// the Vortex GPU before execution.
//
// Included Sequences:
//   1. dcr_base_sequence            - Abstract base class with write_dcr helper
//   2. dcr_startup_config_sequence  - Configure startup PC and argv pointer
//   3. dcr_minimal_startup_sequence - Minimal config (PC only)
//   4. dcr_perf_config_sequence     - Performance monitoring configuration
//   5. dcr_random_sequence          - Randomized DCR traffic
//
// Usage Example:
//   dcr_startup_config_sequence seq = dcr_startup_config_sequence::type_id::create("seq");
//   seq.startup_pc = 64'h80000000;
//   seq.argv_ptr = 64'h0;
//   seq.start(env.dcr_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef DCR_SEQUENCES_SV
`define DCR_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import dcr_agent_pkg::*;


//==============================================================================
// Base DCR Sequence
// Provides common write_dcr helper method
//==============================================================================
class dcr_base_sequence extends uvm_sequence #(dcr_transaction);
    `uvm_object_utils(dcr_base_sequence)
    
    function new(string name = "dcr_base_sequence");
        super.new(name);
    endfunction
    
    // Helper task to write a single DCR
    task write_dcr(bit [31:0] addr, bit [31:0] data);
        dcr_transaction trans;
        
        trans = dcr_transaction::type_id::create("trans");
        
        start_item(trans);
        
        // Force specific address and data
        assert(trans.randomize() with {
            this.addr == local::addr;
            this.data == local::data;
        });
        
        finish_item(trans);
        
        `uvm_info("DCR_SEQ", $sformatf("DCR Write: %s = 0x%08h",
            trans.get_dcr_name(), data), UVM_MEDIUM)
    endtask
    
endclass : dcr_base_sequence



// //==============================================================================
// // Base DCR Sequence
// //==============================================================================
// class dcr_base_sequence extends uvm_sequence #(dcr_transaction);
//     `uvm_object_utils(dcr_base_sequence)
    
//     function new(string name = "dcr_base_sequence");
//         super.new(name);
//     endfunction
    
//     // Helper task - writes specific DCR value (no randomization)
//     task write_dcr(bit [31:0] write_addr, bit [31:0] write_data);
//         dcr_transaction trans;
        
//         trans = dcr_transaction::type_id::create("trans");
//         start_item(trans);
        
//         // Direct assignment
//         trans.addr = write_addr;
//         trans.data = write_data;
        
//         finish_item(trans);
        
//         `uvm_info("DCR_SEQ", 
//                  $sformatf("DCR Write: addr=0x%03h data=0x%08h", 
//                            write_addr, write_data), 
//                  UVM_MEDIUM)
//     endtask
    
// endclass : dcr_base_sequence


//==============================================================================
// Startup Configuration Sequence
// Configures startup PC and optional argv pointer
//==============================================================================
class dcr_startup_config_sequence extends dcr_base_sequence;
    `uvm_object_utils(dcr_startup_config_sequence)
    
    // Public parameters - set before starting sequence
    rand bit [63:0] startup_pc;  // 64-bit program counter (entry point)
    rand bit [63:0] argv_ptr;    // 64-bit pointer to program arguments
    
    // PC must be word-aligned
    constraint pc_align_c {
        startup_pc[1:0] == 2'b00;
    }
    
    function new(string name = "dcr_startup_config_sequence");
        super.new(name);
        // RTL default fallback — overridden from cfg.startup_addr in body()
        // RV32 default = 0x80000000, RV64 default = 0x080000000
        startup_pc = 64'h80000000;
        argv_ptr = 64'h0;
    endfunction
    
    virtual task body();
        // Pull startup_pc from vortex_config in config DB (set by apply_plusargs).
        // This is the ONLY correct source — honours +STARTUP_ADDR plusarg at runtime.
        begin
            vortex_config cfg;
            if (uvm_config_db #(vortex_config)::get(
                    null, get_full_name(), "cfg", cfg)) begin
                startup_pc = cfg.startup_addr;
                `uvm_info("DCR_SEQ",
                    $sformatf("startup_pc from cfg.startup_addr: 0x%016h", startup_pc),
                    UVM_HIGH)
            end else begin
                `uvm_info("DCR_SEQ",
                    $sformatf("cfg not in config DB — using startup_pc=0x%016h", startup_pc),
                    UVM_MEDIUM)
            end
        end

        `uvm_info("DCR_SEQ", $sformatf(
            "Configuring startup: PC=0x%016h, argv=0x%016h",
            startup_pc, argv_ptr), UVM_LOW)
        
        // Write 64-bit startup PC (split into two 32-bit DCRs)
        write_dcr(dcr_transaction::DCR_STARTUP_ADDR0, startup_pc[31:0]);
        write_dcr(dcr_transaction::DCR_STARTUP_ADDR1, startup_pc[63:32]);
        
        // Write argv pointer if non-zero (optional)
        if (argv_ptr != 0) begin
            write_dcr(dcr_transaction::DCR_ARGV_PTR0, argv_ptr[31:0]);
            write_dcr(dcr_transaction::DCR_ARGV_PTR1, argv_ptr[63:32]);
        end
        
        `uvm_info("DCR_SEQ", "Startup configuration complete", UVM_LOW)
    endtask
    
endclass : dcr_startup_config_sequence

//==============================================================================
// Minimal Startup Sequence
// Configures only the startup PC (minimum required configuration)
//==============================================================================
class dcr_minimal_startup_sequence extends dcr_base_sequence;
    `uvm_object_utils(dcr_minimal_startup_sequence)
    
    rand bit [63:0] startup_pc;
    
    constraint pc_align_c {
        startup_pc[1:0] == 2'b00;
    }
    
    function new(string name = "dcr_minimal_startup_sequence");
        super.new(name);
        startup_pc = 64'h80000000;  // RTL default; overridden from cfg in body()
    endfunction
    
    virtual task body();
        // Pull startup_pc from cfg.startup_addr — honours +STARTUP_ADDR plusarg
        begin
            vortex_config cfg;
            if (uvm_config_db #(vortex_config)::get(
                    null, get_full_name(), "cfg", cfg)) begin
                startup_pc = cfg.startup_addr;
                `uvm_info("DCR_SEQ",
                    $sformatf("startup_pc from cfg.startup_addr: 0x%016h", startup_pc),
                    UVM_HIGH)
            end else begin
                `uvm_info("DCR_SEQ",
                    $sformatf("cfg not in config DB — using startup_pc=0x%016h", startup_pc),
                    UVM_MEDIUM)
            end
        end

        `uvm_info("DCR_SEQ", $sformatf(
            "Minimal startup configuration: PC=0x%016h", startup_pc), UVM_LOW)
        
        // Write only the startup PC
        write_dcr(dcr_transaction::DCR_STARTUP_ADDR0, startup_pc[31:0]);
        write_dcr(dcr_transaction::DCR_STARTUP_ADDR1, startup_pc[63:32]);
    endtask
    
endclass : dcr_minimal_startup_sequence

//==============================================================================
// Performance Configuration Sequence
// Configures performance monitoring class
//==============================================================================
class dcr_perf_config_sequence extends dcr_base_sequence;
    `uvm_object_utils(dcr_perf_config_sequence)
    
    rand bit [31:0] mpm_class;
    
    // Constrain to valid MPM class values
    constraint mpm_class_c {
        mpm_class inside {
            VX_DCR_MPM_CLASS_NONE,
            VX_DCR_MPM_CLASS_CORE,
            VX_DCR_MPM_CLASS_MEM
        };
    }
    
    function new(string name = "dcr_perf_config_sequence");
        super.new(name);
        mpm_class = VX_DCR_MPM_CLASS_NONE;  // Disabled by default
    endfunction
    
    virtual task body();
        `uvm_info("DCR_SEQ", $sformatf(
            "Performance monitoring class: 0x%0h", mpm_class), UVM_LOW)
        
        write_dcr(dcr_transaction::DCR_MPM_CLASS, mpm_class);
    endtask
    
endclass : dcr_perf_config_sequence

//==============================================================================
// Random DCR Sequence
// Generates random legal DCR traffic for stress testing
//==============================================================================
class dcr_random_sequence extends dcr_base_sequence;
    `uvm_object_utils(dcr_random_sequence)
    
    rand int num_writes;
    
    constraint count_c {
        num_writes inside {[5:20]};
    }
    
    function new(string name = "dcr_random_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        dcr_transaction trans;
        
        `uvm_info("DCR_SEQ", $sformatf(
            "Random DCR traffic: %0d writes", num_writes), UVM_LOW)
        
        repeat (num_writes) begin
            trans = dcr_transaction::type_id::create("trans");
            
            start_item(trans);
            assert(trans.randomize());
            finish_item(trans);
        end
        
        `uvm_info("DCR_SEQ", "Random DCR sequence complete", UVM_LOW)
    endtask
    
endclass : dcr_random_sequence

`endif // DCR_SEQUENCES_SV