////////////////////////////////////////////////////////////////////////////////
// File: mem_sequences.sv
// Description: Memory Sequence Library for Vortex Custom Memory Interface
//
// This file contains a collection of reusable memory sequences that generate
// various transaction patterns for verification.
//
// STATUS (2026-06-28): DORMANT BY CONFIG, not dead code.
//   The primary config drives the AXI interface, so mem_agent runs PASSIVE
//   (monitor-only) and NONE of these sequences are started. They become live
//   only in the non-AXI custom-memory build (USE_AXI_WRAPPER undefined), where
//   mem_agent is ACTIVE. Keep them for that config; do not delete.
//
// Included Sequences:
//   1. mem_base_sequence          - Abstract base class
//   2. mem_write_sequence         - Single word write
//   3. mem_read_sequence          - Single word read
//   4. mem_write_read_sequence    - Write then read (RAW test)
//   5. mem_block_write_sequence   - Block write (multiple words)
//   6. mem_block_read_sequence    - Block read (multiple words)
//   7. mem_random_sequence        - Randomized mix of reads/writes
//
// Usage Example:
//   mem_write_read_sequence seq = mem_write_read_sequence::type_id::create("seq");
//   seq.addr = 32'h80000000;
//   seq.data = 64'hDEADBEEFCAFEBABE;
//   seq.start(env.mem_agent.m_sequencer);
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef MEM_SEQUENCES_SV
`define MEM_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import mem_agent_pkg::*;

//==============================================================================
// Base Memory Sequence
// Abstract base class providing common functionality
//==============================================================================
class mem_base_sequence extends uvm_sequence #(mem_transaction);
    `uvm_object_utils(mem_base_sequence)
    
    // Configuration handle
    vortex_config cfg;
    
    function new(string name = "mem_base_sequence");
        super.new(name);
    endfunction
    
    // FIX 2: pre_body() — runs immediately before body(), after m_sequencer is bound.
    // pre_start() runs before m_sequencer is set, so get(m_sequencer,...) returned null.
    virtual task pre_body();
        super.pre_body();
        if (!uvm_config_db#(vortex_config)::get(m_sequencer, "", "cfg", cfg)) begin
            `uvm_warning("MEM_SEQ", "No cfg found on sequencer — using defaults")
            cfg = vortex_config::type_id::create("cfg");
            cfg.set_defaults_from_vx_config();
        end
    endtask
    
endclass : mem_base_sequence
 
//==============================================================================
// Single Write Sequence
// Writes a 64-bit value to specified address
//==============================================================================
class mem_write_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_write_sequence)
 
    // FIX 3: Field widths corrected to match mem_transaction exactly.
    // addr is a WORD (cache-line = 64-byte) address, NOT a byte address.
    //   byte_addr = word_addr << VX_MEM_OFFSET_BITS (= << 6)
    // data is a full 512-bit cache line (VX_MEM_DATA_WIDTH).
    // byteen is a 64-byte enable mask (VX_MEM_BYTEEN_WIDTH).
    rand bit [vortex_config_pkg::VX_MEM_ADDR_WIDTH-1:0]   addr;
    rand bit [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0]   data;
    rand bit [vortex_config_pkg::VX_MEM_BYTEEN_WIDTH-1:0] byteen;
 
    // Full 64-byte cache-line enable by default (soft — override for partial writes)
    constraint default_byteen_c {
        soft byteen == {vortex_config_pkg::VX_MEM_BYTEEN_WIDTH{1'b1}};
    }
 
    function new(string name = "mem_write_sequence");
        super.new(name);
    endfunction
 
    virtual task body();
        mem_transaction trans;
 
        trans = mem_transaction::type_id::create("trans");
        start_item(trans);
 
        assert(trans.randomize() with {
            rw     == 1'b1;
            addr   == local::addr;
            data   == local::data;
            byteen == local::byteen;
        });
 
        finish_item(trans);
        `uvm_info("MEM_SEQ", $sformatf("Write: word_addr=0x%h byteen=0x%h", addr, byteen), UVM_MEDIUM)
    endtask
 
endclass : mem_write_sequence
 
//==============================================================================
// Single Read Sequence
// Reads a 64-bit value from specified address
// NOTE: read_data is populated after sequence completes
//==============================================================================
class mem_read_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_read_sequence)
 
    // FIX 4: addr is a WORD (cache-line) address — bit[VX_MEM_ADDR_WIDTH-1:0].
    // FIX 8: read_data is 512-bit to capture the full cache-line response.
    //        Callers that need a specific sub-word (e.g. [31:0]) select it
    //        directly: rd_seq.read_data[31:0].
    rand bit [vortex_config_pkg::VX_MEM_ADDR_WIDTH-1:0]   addr;
    bit      [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0]   read_data;  // 512-bit
 
    function new(string name = "mem_read_sequence");
        super.new(name);
    endfunction
 
    virtual task body();
        mem_transaction trans;
 
        trans = mem_transaction::type_id::create("trans");
        start_item(trans);
 
        // FIX 4: byteen must be 64-bit full-line enable
        assert(trans.randomize() with {
            rw     == 1'b0;
            addr   == local::addr;
            byteen == {vortex_config_pkg::VX_MEM_BYTEEN_WIDTH{1'b1}};
        });
 
        finish_item(trans);
 
        // FIX 8: capture full 512-bit response
        read_data = trans.rsp_data;
        `uvm_info("MEM_SEQ", $sformatf("Read: word_addr=0x%h => data[31:0]=0x%h", addr, read_data[31:0]), UVM_MEDIUM)
    endtask
 
endclass : mem_read_sequence
 
//==============================================================================
// Write-Read-Verify Sequence
// Tests Read-After-Write (RAW) hazard
// Verifies that written data can be read back correctly
//==============================================================================
class mem_write_read_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_write_read_sequence)
 
    // FIX: addr is a WORD (cache-line) address; data is a full 512-bit cache line.
    rand bit [vortex_config_pkg::VX_MEM_ADDR_WIDTH-1:0]   addr;
    rand bit [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0]   data;
    
    function new(string name = "mem_write_read_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        mem_write_sequence wr_seq;
        mem_read_sequence  rd_seq;
        
        // First: Write data
        wr_seq = mem_write_sequence::type_id::create("wr_seq");
        wr_seq.addr = addr;
        wr_seq.data = data;
        wr_seq.byteen = {vortex_config_pkg::VX_MEM_BYTEEN_WIDTH{1'b1}};  // FIX 5: 64-byte full-line enable
        wr_seq.start(m_sequencer);
        
        // Then: Read back same address
        rd_seq = mem_read_sequence::type_id::create("rd_seq");
        rd_seq.addr = addr;
        rd_seq.start(m_sequencer);
        
        // Verify data matches
        if (rd_seq.read_data != data) begin
            `uvm_error("MEM_SEQ", $sformatf(
                "Data mismatch at 0x%h: wrote 0x%h, read 0x%h",
                addr, data, rd_seq.read_data))
        end else begin
            `uvm_info("MEM_SEQ", $sformatf(
                "✓ Verified: [0x%h] = 0x%h", addr, data), UVM_LOW)
        end
    endtask
    
endclass : mem_write_read_sequence
 
//==============================================================================
// Block Write Sequence
// Writes multiple consecutive 64-bit words
//==============================================================================
class mem_block_write_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_block_write_sequence)
 
    // FIX 6: start_addr is a WORD (cache-line = 64-byte) address.
    // data[] holds 512-bit cache-line values (one per word).
    rand bit [vortex_config_pkg::VX_MEM_ADDR_WIDTH-1:0]   start_addr;
    rand int                                                num_words;
    rand bit [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0]   data[];
 
    constraint reasonable_size_c {
        num_words inside {[1:64]};
        // FIX 6: dynamic array size constraints unreliable in QuestaSim 2021.
        // data[] is resized in post_randomize() instead.
    }
 
    function void post_randomize();
        data = new[num_words];
        foreach (data[i]) data[i] = {$urandom(), $urandom(), $urandom(), $urandom(),
                                      $urandom(), $urandom(), $urandom(), $urandom(),
                                      $urandom(), $urandom(), $urandom(), $urandom(),
                                      $urandom(), $urandom(), $urandom(), $urandom()};  // 16x32=512 bits
    endfunction
 
    function new(string name = "mem_block_write_sequence");
        super.new(name);
    endfunction
 
    virtual task body();
        mem_write_sequence wr_seq;
        `uvm_info("MEM_SEQ", $sformatf("Block write: word_addr=0x%h, %0d cache lines", start_addr, num_words), UVM_LOW)
 
        for (int i = 0; i < num_words; i++) begin
            wr_seq = mem_write_sequence::type_id::create($sformatf("wr_seq_%0d", i));
            wr_seq.addr   = start_addr + i;  // FIX 6: stride=1 (next cache line word address)
            wr_seq.data   = data[i];
            wr_seq.byteen = {vortex_config_pkg::VX_MEM_BYTEEN_WIDTH{1'b1}};  // FIX 6: 64-byte
            wr_seq.start(m_sequencer);
        end
 
        `uvm_info("MEM_SEQ", $sformatf("Block write complete: %0d cache lines", num_words), UVM_LOW)
    endtask
 
endclass : mem_block_write_sequence
 
//==============================================================================
// Block Read Sequence
// Reads multiple consecutive 64-bit words
//==============================================================================
class mem_block_read_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_block_read_sequence)
 
    // FIX 7: start_addr is a WORD (cache-line = 64-byte) address.
    // read_data[] holds full 512-bit cache-line responses (one per word).
    // Callers select sub-fields: rd_seq.read_data[0][31:0] for the first word.
    rand bit [vortex_config_pkg::VX_MEM_ADDR_WIDTH-1:0]   start_addr;
    rand int                                                num_words;
    bit      [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0]   read_data[];
 
    constraint reasonable_size_c {
        num_words inside {[1:64]};
    }
 
    function new(string name = "mem_block_read_sequence");
        super.new(name);
    endfunction
 
    virtual task body();
        mem_read_sequence rd_seq;
        read_data = new[num_words];
 
        `uvm_info("MEM_SEQ", $sformatf("Block read: word_addr=0x%h, %0d cache lines", start_addr, num_words), UVM_LOW)
 
        for (int i = 0; i < num_words; i++) begin
            rd_seq = mem_read_sequence::type_id::create($sformatf("rd_seq_%0d", i));
            rd_seq.addr = start_addr + i;  // FIX 7: stride=1 (next cache line word address)
            rd_seq.start(m_sequencer);
            read_data[i] = rd_seq.read_data;  // 512-bit capture
        end
 
        `uvm_info("MEM_SEQ", $sformatf("Block read complete: %0d cache lines", num_words), UVM_LOW)
    endtask
 
endclass : mem_block_read_sequence
 
//==============================================================================
// Random Memory Test Sequence
// Generates random mix of reads and writes
//==============================================================================
class mem_random_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_random_sequence)
    
    rand int num_transactions;
    
    constraint reasonable_count_c {
        num_transactions inside {[10:100]};
    }
    
    function new(string name = "mem_random_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        mem_transaction trans;
        
        `uvm_info("MEM_SEQ", $sformatf(
            "Starting random sequence: %0d transactions", 
            num_transactions), UVM_LOW)
        
        for (int i = 0; i < num_transactions; i++) begin
            trans = mem_transaction::type_id::create($sformatf("trans_%0d", i));
            
            start_item(trans);
            assert(trans.randomize());
            finish_item(trans);
        end
        
        `uvm_info("MEM_SEQ", $sformatf(
            "Random sequence complete: %0d transactions", 
            num_transactions), UVM_LOW)
    endtask
    
endclass : mem_random_sequence
 
`endif // MEM_SEQUENCES_SV