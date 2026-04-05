////////////////////////////////////////////////////////////////////////////////
// File: axi_sequences.sv
// Description: AXI4 Sequence Library
//
// This file contains a collection of reusable AXI4 sequences that generate
// various transaction patterns. Sequences are composable building blocks
// for test scenarios.
//
// Included Sequences:
//   1. axi_base_sequence       - Abstract base class for all AXI sequences
//   2. axi_single_write_seq    - Single write transaction
//   3. axi_single_read_seq     - Single read transaction
//   4. axi_write_read_seq      - Write then read same address (RAW)
//   5. axi_burst_write_seq     - Multi-beat write burst
//   6. axi_burst_read_seq      - Multi-beat read burst
//   7. axi_random_seq          - Randomized mix of reads and writes
//   8. axi_stress_seq          - High-throughput stress test
//
// Usage Example:
//   axi_write_read_seq seq = axi_write_read_seq::type_id::create("seq");
//   seq.addr = 32'h1000;
//   seq.data = 64'hDEADBEEF;
//   seq.start(env.axi_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_SEQUENCES_SV
`define AXI_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import axi_agent_pkg::*;

//==============================================================================
// Base AXI Sequence
// Abstract base class providing common functionality
//==============================================================================
class axi_base_sequence extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_base_sequence)
    
    // Configuration handle for constraints
    vortex_config cfg;
    
    function new(string name = "axi_base_sequence");
        super.new(name);
    endfunction
    
    // pre_body(): runs immediately before body(), after m_sequencer is bound.
    // Using m_sequencer as context for config_db::get() is correct here
    // because vortex_env sets cfg on the sequencer component.
    // pre_start() would also work but runs before m_sequencer is set.
    virtual task pre_body();
        super.pre_body();
        if (m_sequencer != null) begin
            if (!uvm_config_db#(vortex_config)::get(m_sequencer, "", "cfg", cfg)) begin
                `uvm_warning("AXI_SEQ", "No cfg in config_db — creating default")
                cfg = vortex_config::type_id::create("cfg");
                cfg.set_defaults_from_vx_config();
            end
        end
    endtask
    
endclass : axi_base_sequence
 
//==============================================================================
// Single Write Sequence
// Writes a single data value to specified address
//==============================================================================
class axi_single_write_seq extends axi_base_sequence;
    `uvm_object_utils(axi_single_write_seq)
 
    // Public parameters — set before starting sequence.
    // addr: byte address of the write target.
    // data: 512-bit cache-line data (VX_MEM_DATA_WIDTH = 512).
    // strobe: 64-byte enable mask (DATA_WIDTH/8 = 64 bytes per beat).
    rand bit [31:0]  addr;
    rand bit [511:0] data;    // FIX: was [63:0] — must be [511:0] for 512-bit AXI data
    rand bit [63:0]  strobe;  // FIX: was [7:0]  — must be [63:0] for 64-byte strobe
 
    constraint default_strobe_c {
        soft strobe == 64'hFFFF_FFFF_FFFF_FFFF;  // FIX: all 64 bytes enabled
    }
 
    function new(string name = "axi_single_write_seq");
        super.new(name);
    endfunction
 
    virtual task body();
        axi_transaction trans;
 
        trans = axi_transaction::type_id::create("trans");
        trans.cfg = cfg;
        start_item(trans);
 
        // FIX: Use randomize() with inline constraints so rand fields
        // (trans_type, addr, len, size, burst) are solved correctly.
        // Setting them before randomize() would have them overridden.
        // Setting non-rand data/strobe AFTER randomize() is correct.
        assert(trans.randomize() with {
            trans_type == axi_transaction::AXI_WRITE;
            this.addr  == local::addr;
            len        == 8'h0;    // 1 beat
            size       == 3'h3;    // 8 bytes (log2 of beat size)
            burst      == axi_transaction::AXI_INCR;
        });
 
        // Set data fields after randomize() (not rand — safe to set directly)
        trans.wdata[0] = data;
        trans.wstrb[0] = strobe;
 
        finish_item(trans);
        `uvm_info("AXI_SEQ", $sformatf("Single write: addr=0x%h", addr), UVM_MEDIUM)
    endtask
 
endclass : axi_single_write_seq
 
//==============================================================================
// Single Read Sequence
// Reads a single data value from specified address
// NOTE: Response data is NOT available in sequence (UVM rule)
//       Use monitor/scoreboard to capture read data
//==============================================================================
class axi_single_read_seq extends axi_base_sequence;
    `uvm_object_utils(axi_single_read_seq)
    
    // Public parameters
    rand bit [31:0] addr;           // Target address
    
    function new(string name = "axi_single_read_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_transaction trans;
 
        trans = axi_transaction::type_id::create("trans");
        trans.cfg = cfg;
        start_item(trans);
 
        // FIX: use inline constraints so rand fields are solved correctly.
        assert(trans.randomize() with {
            trans_type == axi_transaction::AXI_READ;
            this.addr  == local::addr;
            len        == 8'h0;
            size       == 3'h3;
            burst      == axi_transaction::AXI_INCR;
        });
 
        finish_item(trans);
        `uvm_info("AXI_SEQ", $sformatf("Single read: addr=0x%h", addr), UVM_MEDIUM)
    endtask
 
endclass : axi_single_read_seq
 
//==============================================================================
// Write-Then-Read Sequence
// Tests Read-After-Write (RAW) hazard
//==============================================================================
class axi_write_read_seq extends axi_base_sequence;
    `uvm_object_utils(axi_write_read_seq)
    
    rand bit [31:0] addr;
    rand bit [63:0] data;
    
    function new(string name = "axi_write_read_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_transaction trans;
        
        // First: Write — use inline constraints (FIX: randomize order)
        trans = axi_transaction::type_id::create("wr_trans");
        trans.cfg = cfg;
        start_item(trans);
        assert(trans.randomize() with {
            trans_type == axi_transaction::AXI_WRITE;
            this.addr  == local::addr;
            len        == 8'h0;
            size       == 3'h3;
            burst      == axi_transaction::AXI_INCR;
        });
        trans.wdata[0] = data;
        trans.wstrb[0] = 64'hFFFF_FFFF_FFFF_FFFF;  // FIX: 64-byte strobe
        finish_item(trans);
        `uvm_info("AXI_SEQ", $sformatf("Write: addr=0x%h, data=0x%h", addr, data), UVM_MEDIUM)
 
        // Then: Read same address
        trans = axi_transaction::type_id::create("rd_trans");
        trans.cfg = cfg;
        start_item(trans);
        assert(trans.randomize() with {
            trans_type == axi_transaction::AXI_READ;
            this.addr  == local::addr;
            len        == 8'h0;
            size       == 3'h3;
            burst      == axi_transaction::AXI_INCR;
        });
        finish_item(trans);
        `uvm_info("AXI_SEQ", $sformatf("Read: addr=0x%h (expecting data=0x%h)", addr, data), UVM_MEDIUM)
    endtask
    
endclass : axi_write_read_seq
 
//==============================================================================
// Burst Write Sequence
// Multi-beat write burst with configurable length
//==============================================================================
class axi_burst_write_seq extends axi_base_sequence;
    `uvm_object_utils(axi_burst_write_seq)
 
    rand bit [31:0]  addr;
    rand int         num_beats;    // number of beats (1-16)
    rand bit [511:0] data[];       // FIX: was [63:0] — must be [511:0] per beat
 
    constraint valid_burst_c {
        num_beats inside {[1:16]};
        // FIX: dynamic array size constraints are unreliable in QuestaSim 2021.
        // data[] is resized in post_randomize() to match num_beats instead.
    }
 
    // FIX: resize data[] after num_beats is solved
    function void post_randomize();
        data = new[num_beats];
        foreach (data[i]) data[i] = $urandom();
    endfunction
 
    function new(string name = "axi_burst_write_seq");
        super.new(name);
    endfunction
 
    virtual task body();
        axi_transaction trans;
 
        trans = axi_transaction::type_id::create("trans");
        trans.cfg = cfg;
        start_item(trans);
 
        // FIX: inline constraints so rand fields solved correctly
        assert(trans.randomize() with {
            trans_type == axi_transaction::AXI_WRITE;
            this.addr  == local::addr;
            len        == 8'(num_beats - 1);
            size       == 3'h3;
            burst      == axi_transaction::AXI_INCR;
        });
 
        // Copy data array (data[] resized in post_randomize, trans.wdata[] sized by randomize via len)
        foreach (data[i]) begin
            if (i < trans.wdata.size()) begin
                trans.wdata[i] = data[i];
                trans.wstrb[i] = 64'hFFFF_FFFF_FFFF_FFFF;  // FIX: 64-byte strobe
            end
        end
 
        finish_item(trans);
        `uvm_info("AXI_SEQ", $sformatf("Burst write: addr=0x%h, %0d beats", addr, num_beats), UVM_MEDIUM)
    endtask
 
endclass : axi_burst_write_seq
 
//==============================================================================
// Burst Read Sequence
// Multi-beat read burst with configurable length
//==============================================================================
class axi_burst_read_seq extends axi_base_sequence;
    `uvm_object_utils(axi_burst_read_seq)
    
    rand bit [31:0] addr;
    rand int        num_beats;
    
    constraint valid_burst_c {
        num_beats inside {[1:16]};
    }
    
    function new(string name = "axi_burst_read_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_transaction trans;
 
        trans = axi_transaction::type_id::create("trans");
        trans.cfg = cfg;
        start_item(trans);
 
        // FIX: inline constraints so rand fields solved correctly
        assert(trans.randomize() with {
            trans_type == axi_transaction::AXI_READ;
            this.addr  == local::addr;
            len        == 8'(num_beats - 1);
            size       == 3'h3;
            burst      == axi_transaction::AXI_INCR;
        });
 
        finish_item(trans);
        `uvm_info("AXI_SEQ", $sformatf("Burst read: addr=0x%h, %0d beats", addr, num_beats), UVM_MEDIUM)
    endtask
 
endclass : axi_burst_read_seq
 
//==============================================================================
// Random AXI Sequence
// Generates random mix of reads and writes
//==============================================================================
class axi_random_seq extends axi_base_sequence;
    `uvm_object_utils(axi_random_seq)
    
    rand int num_transactions;
    
    constraint reasonable_count_c {
        num_transactions inside {[10:50]};
    }
    
    function new(string name = "axi_random_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_transaction trans;
        
        for (int i = 0; i < num_transactions; i++) begin
            trans = axi_transaction::type_id::create($sformatf("trans_%0d", i));
            trans.cfg = cfg;
            
            start_item(trans);
            assert(trans.randomize());
            finish_item(trans);
        end
        
        `uvm_info("AXI_SEQ", $sformatf(
            "Random sequence complete: %0d transactions", 
            num_transactions), UVM_LOW)
    endtask
    
endclass : axi_random_seq
 
//==============================================================================
// Stress Sequence
// Back-to-back transactions for throughput testing
//==============================================================================
class axi_stress_seq extends axi_base_sequence;
    `uvm_object_utils(axi_stress_seq)
    
    rand int num_writes;
    rand int num_reads;
    
    constraint stress_load_c {
        num_writes inside {[50:100]};
        num_reads inside {[50:100]};
    }
    
    function new(string name = "axi_stress_seq");
        super.new(name);
    endfunction
    
    virtual task body();
        axi_transaction trans;
        
        // Generate writes
        for (int i = 0; i < num_writes; i++) begin
            trans = axi_transaction::type_id::create($sformatf("wr_%0d", i));
            trans.cfg = cfg;
            
            start_item(trans);
            assert(trans.randomize() with {
                trans_type == axi_transaction::AXI_WRITE;
            });
            finish_item(trans);
        end
        
        // Generate reads
        for (int i = 0; i < num_reads; i++) begin
            trans = axi_transaction::type_id::create($sformatf("rd_%0d", i));
            trans.cfg = cfg;
            
            start_item(trans);
            assert(trans.randomize() with {
                trans_type == axi_transaction::AXI_READ;
            });
            finish_item(trans);
        end
        
        `uvm_info("AXI_SEQ", $sformatf(
            "Stress test complete: %0d writes, %0d reads", 
            num_writes, num_reads), UVM_LOW)
    endtask
    
endclass : axi_stress_seq
 
`endif // AXI_SEQUENCES_SV