////////////////////////////////////////////////////////////////////////////////
// File: mem_sequences.sv
// Description: Memory Sequence Library for Vortex Custom Memory Interface
//
// This file contains a collection of reusable memory sequences that generate
// various transaction patterns for verification.
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
    
    // Pre-start hook: Get configuration from sequencer
    virtual task pre_start();
        super.pre_start();
        
        if (!uvm_config_db#(vortex_config)::get(m_sequencer, "", "cfg", cfg)) begin
            `uvm_warning("MEM_SEQ", "No config found - using defaults")
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
    
    // Public parameters - set before starting sequence
    rand bit [31:0] addr;
    rand bit [63:0] data;        // 64-bit data for Vortex
    rand bit [7:0]  byteen;      // 8-bit byte enable (8 bytes)
    
    // Default to 64-bit aligned, full word access
    constraint addr_aligned_c {
        addr[2:0] == 3'b000;     // 8-byte aligned
    }
    
    // Default to full byte enables
    constraint default_byteen_c {
        soft byteen == 8'hFF;    // All 8 bytes enabled
    }
    
    function new(string name = "mem_write_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        mem_transaction trans;
        
        trans = mem_transaction::type_id::create("trans");
        
        start_item(trans);
        
        // Configure as write with specified parameters
        assert(trans.randomize() with {
            rw == 1'b1;                      // Write operation
            addr == local::addr;
            data == local::data;
            byteen == local::byteen;
        });
        
        finish_item(trans);
        
        `uvm_info("MEM_SEQ", $sformatf(
            "Write: [0x%h] = 0x%h (byteen=0x%h)", 
            addr, data, byteen), UVM_MEDIUM)
    endtask
    
endclass : mem_write_sequence

//==============================================================================
// Single Read Sequence
// Reads a 64-bit value from specified address
// NOTE: read_data is populated after sequence completes
//==============================================================================
class mem_read_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_read_sequence)
    
    // Public parameters
    rand bit [31:0] addr;
    bit [63:0] read_data;        // Captured from response
    
    // 64-bit aligned address
    constraint addr_aligned_c {
        addr[2:0] == 3'b000;
    }
    
    function new(string name = "mem_read_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        mem_transaction trans;
        
        trans = mem_transaction::type_id::create("trans");
        
        start_item(trans);
        
        // Configure as read
        assert(trans.randomize() with {
            rw == 1'b0;                      // Read operation
            addr == local::addr;
            byteen == 8'hFF;                 // Full word read
        });
        
        finish_item(trans);
        
        // Capture read data from completed transaction
        read_data = trans.rsp_data;
        
        `uvm_info("MEM_SEQ", $sformatf(
            "Read: [0x%h] => 0x%h", addr, read_data), UVM_MEDIUM)
    endtask
    
endclass : mem_read_sequence

//==============================================================================
// Write-Read-Verify Sequence
// Tests Read-After-Write (RAW) hazard
// Verifies that written data can be read back correctly
//==============================================================================
class mem_write_read_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_write_read_sequence)
    
    rand bit [31:0] addr;
    rand bit [63:0] data;
    
    constraint addr_aligned_c {
        addr[2:0] == 3'b000;
    }
    
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
        wr_seq.byteen = 8'hFF;
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
    
    rand bit [31:0] start_addr;
    rand int        num_words;
    rand bit [63:0] data[];
    
    constraint addr_aligned_c {
        start_addr[2:0] == 3'b000;       // 8-byte aligned
    }
    
    constraint reasonable_size_c {
        num_words inside {[4:256]};
        num_words % 4 == 0;              // Multiple of 4 for alignment
    }
    
    constraint data_size_c {
        data.size() == num_words;
    }
    
    function new(string name = "mem_block_write_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        mem_write_sequence wr_seq;
        
        `uvm_info("MEM_SEQ", $sformatf(
            "Block write: addr=0x%h, %0d words (64-bit)",
            start_addr, num_words), UVM_LOW)
        
        // Write each word sequentially
        for (int i = 0; i < num_words; i++) begin
            wr_seq = mem_write_sequence::type_id::create($sformatf("wr_seq_%0d", i));
            wr_seq.addr   = start_addr + (i * 8);  // 8 bytes per word
            wr_seq.data   = data[i];
            wr_seq.byteen = 8'hFF;
            wr_seq.start(m_sequencer);
        end
        
        `uvm_info("MEM_SEQ", $sformatf(
            "Block write complete: %0d words written", num_words), UVM_LOW)
    endtask
    
endclass : mem_block_write_sequence

//==============================================================================
// Block Read Sequence
// Reads multiple consecutive 64-bit words
//==============================================================================
class mem_block_read_sequence extends mem_base_sequence;
    `uvm_object_utils(mem_block_read_sequence)
    
    rand bit [31:0] start_addr;
    rand int        num_words;
    bit [63:0]      read_data[];     // Captured read data
    
    constraint addr_aligned_c {
        start_addr[2:0] == 3'b000;
    }
    
    constraint reasonable_size_c {
        num_words inside {[4:256]};
    }
    
    function new(string name = "mem_block_read_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        mem_read_sequence rd_seq;
        
        // Allocate read data array
        read_data = new[num_words];
        
        `uvm_info("MEM_SEQ", $sformatf(
            "Block read: addr=0x%h, %0d words (64-bit)",
            start_addr, num_words), UVM_LOW)
        
        // Read each word sequentially
        for (int i = 0; i < num_words; i++) begin
            rd_seq = mem_read_sequence::type_id::create($sformatf("rd_seq_%0d", i));
            rd_seq.addr = start_addr + (i * 8);  // 8 bytes per word
            rd_seq.start(m_sequencer);
            read_data[i] = rd_seq.read_data;
        end
        
        `uvm_info("MEM_SEQ", $sformatf(
            "Block read complete: %0d words read", num_words), UVM_LOW)
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
