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
//   3. dcr_perf_config_sequence     - Performance monitoring configuration
//   4. dcr_random_sequence          - Randomized DCR traffic
//   (dcr_minimal_startup_sequence removed 2026-06-28 — redundant subset of
//    dcr_startup_config_sequence, never started; I5 hygiene.)
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
 
    // FIX 5: cfg field + pre_body() so derived sequences can read
    // cfg.startup_addr, cfg.test_timeout_cycles, etc.
    vortex_config cfg;
 
    function new(string name = "dcr_base_sequence");
        super.new(name);
    endfunction
 
    virtual task pre_body();
        super.pre_body();
        if (m_sequencer != null) begin
            if (!uvm_config_db#(vortex_config)::get(m_sequencer, "", "cfg", cfg))
                `uvm_warning("DCR_SEQ", "No vortex_config found on sequencer — cfg will be null")
        end
    endtask
 
    // FIX 2: write_dcr — set addr/data AFTER randomize() to avoid constraint conflict.
    //
    // dcr_transaction has valid_addr_c: addr inside {DCR_STARTUP_ADDR0..DCR_MPM_CLASS}.
    // Using randomize() with {this.addr == local::addr} would fail if addr is not one
    // of those 5 enum values, because both constraints would be active simultaneously.
    //
    // Correct pattern: randomize() to satisfy all intra-transaction constraints
    // (startup_pc_align_c etc.), then OVERRIDE addr and data directly.
    // addr and data are rand fields so direct assignment is legal post-randomize.
    //
    // FIX 3: Use VX_DCR_BASE_* word addresses directly (same as TB_TOP).
    // dcr_transaction enum applies << 2 (byte-addr) but the hardware interface
    // vortex_dcr_if.wr_addr is word-addressed (VX_DCR_ADDR_WIDTH=12 bits).
    // Callers pass VX_DCR_BASE_* word address values — stored directly in trans.addr.
    task write_dcr(bit [VX_DCR_ADDR_WIDTH-1:0] addr, bit [VX_DCR_DATA_WIDTH-1:0] data);
        dcr_transaction trans;
 
        trans = dcr_transaction::type_id::create("trans");
        start_item(trans);
 
        // Randomize to satisfy startup_pc_align_c and other intra-constraints,
        // then override addr/data with the caller-specified values.
        void'(trans.randomize());
        trans.addr = addr;
        trans.data = data;
 
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
        // FIX 4: cfg is populated by pre_body() (inherited from dcr_base_sequence)
        // using m_sequencer as context — the only correct way to get config in a sequence.
        // The old (null, get_full_name()) pattern never matched vortex_env's registration.
        if (cfg != null && startup_pc == 64'h80000000)
            startup_pc = cfg.startup_addr;
 
        `uvm_info("DCR_SEQ", $sformatf(
            "Configuring startup: PC=0x%016h, argv=0x%016h",
            startup_pc, argv_ptr), UVM_LOW)
 
        // FIX 3: Use VX_DCR_BASE_* word-address constants (matches vortex_dcr_if.wr_addr).
        // NOT VX_DCR_BASE_STARTUP_ADDR0 which applies <<2 (byte-addressing).
        write_dcr(VX_DCR_BASE_STARTUP_ADDR0, startup_pc[31:0]);
        write_dcr(VX_DCR_BASE_STARTUP_ADDR1, startup_pc[63:32]);
 
        if (argv_ptr != 0) begin
            write_dcr(VX_DCR_BASE_STARTUP_ARG0, argv_ptr[31:0]);
            write_dcr(VX_DCR_BASE_STARTUP_ARG1, argv_ptr[63:32]);
        end
 
        `uvm_info("DCR_SEQ", "Startup configuration complete", UVM_LOW)
    endtask
 
endclass : dcr_startup_config_sequence
 
//==============================================================================
// Performance Configuration Sequence
// Configures performance monitoring class
//==============================================================================
class dcr_perf_config_sequence extends dcr_base_sequence;
    `uvm_object_utils(dcr_perf_config_sequence)
 
    // FIX 6: VX_DCR_MPM_CLASS_* constants come from vortex_config_pkg (VX_types.vh).
    // If they are not defined there, this sequence causes a compile error.
    // Using integer literals as safe fallback values (0=NONE, 1=CORE, 2=MEM).
    // Replace with VX_DCR_MPM_CLASS_NONE/CORE/MEM if confirmed in vortex_config.sv.
    bit [31:0] mpm_class;  // NOT rand — caller sets this explicitly
 
    function new(string name = "dcr_perf_config_sequence");
        super.new(name);
        mpm_class = 32'h0;  // 0 = disabled / NONE class
    endfunction
 
    virtual task body();
        `uvm_info("DCR_SEQ", $sformatf("Performance monitoring class: 0x%0h", mpm_class), UVM_LOW)
        // FIX 3: VX_DCR_BASE_MPM_CLASS word address
        write_dcr(VX_DCR_BASE_MPM_CLASS, mpm_class);
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