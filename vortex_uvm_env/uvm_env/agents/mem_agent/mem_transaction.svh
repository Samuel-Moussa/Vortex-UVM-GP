////////////////////////////////////////////////////////////////////////////////
// File: mem_transaction.sv
// Description: Memory Transaction for Vortex Custom Memory Interface
//
// This transaction represents a single memory request-response pair on the
// Vortex custom memory interface (not AXI). It models:
//   - Read or Write operation
//   - 512-bit data width  (VX_MEM_DATA_WIDTH  = L3_LINE_SIZE*8 = 512 bits)
//   - 26-bit word address (VX_MEM_ADDR_WIDTH  = 32-6 = 26 bits, RV32)
//                         (VX_MEM_ADDR_WIDTH  = 48-6 = 42 bits, RV64)
//   - 64-bit byte enables (VX_MEM_BYTEEN_WIDTH = L3_LINE_SIZE  = 64 bytes)
//   - 8-bit tag           (VX_MEM_TAG_WIDTH   = L3_MEM_TAG_WIDTH = 8 bits)
//
// NOTE: addr is a WORD (cache-line) address, NOT a byte address.
//       byte_addr = word_addr << 6  (shift by log2(64))
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef MEM_TRANSACTION_SV
`define MEM_TRANSACTION_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;


class mem_transaction extends uvm_sequence_item;
    
    //==========================================================================
    // Transaction Fields - Match Vortex Memory Interface
    //==========================================================================
    
    // Request fields (driven by driver, captured by monitor)
    rand bit rw;  // 0=READ, 1=WRITE
    rand bit [vortex_config_pkg::VX_MEM_ADDR_WIDTH-1:0] addr;     // 32-bit address
    rand bit [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0] data;     // 64-bit write data
    rand bit [vortex_config_pkg::VX_MEM_BYTEEN_WIDTH-1:0] byteen; // 8-bit byte enable
    rand bit [vortex_config_pkg::VX_MEM_TAG_WIDTH-1:0] tag;       // Transaction ID
    
    // Response fields (captured by monitor/driver)
    bit [vortex_config_pkg::VX_MEM_DATA_WIDTH-1:0] rsp_data;      // Read data response
    bit [vortex_config_pkg::VX_MEM_TAG_WIDTH-1:0] rsp_tag;        // Response tag (should match req tag)
    
    // Timing information (for performance analysis)
    time req_time;           // Simulation time when request was issued
    time rsp_time;           // Simulation time when response was received
    int latency_cycles;      // Response latency in clock cycles
    
    // Status flags
    bit completed;           // Set to 1 when response is received
    bit error;               // Set to 1 if tag mismatch or timeout
    
    //==========================================================================
    // Constraints
    //==========================================================================
    
    // Address alignment based on byte enable pattern.
    // addr is a WORD (cache-line, 64-byte) address — sub-line alignment
    // is expressed via byteen. A full-line access (byteen=all-ones) needs
    // no additional alignment constraint because the word address IS the
    // cache line address.
    // Partial-line patterns constrain the lower byte-enable bits.
    constraint addr_alignment_c {
        // Full cache-line access: no extra constraint needed
        // Partial lower-64-bit (8-byte sub-word): lower addr bits irrelevant
        // at cache-line granularity; byteen selects the sub-word within line.
        1'b1;  // placeholder — word address is inherently cache-line aligned
    }
    
    // Valid word-address range.
    // STARTUP_ADDR (from pkg) is a BYTE address; shift >>6 to get word address.
    // The pkg STARTUP_ADDR = 32'h80000000 is the RV32 default.
    constraint valid_addr_c {
        addr inside {
            [(vortex_config_pkg::STARTUP_ADDR >> 6) :
             ((vortex_config_pkg::STARTUP_ADDR >> 6) + 26'h3FFFFF)]  // ~256MB
        };
    }
    
    // Byte enable must have at least one bit set (64-bit field)
    constraint valid_byteen_c {
        byteen != '0;
    }
    
    // Common byte-enable patterns for a 64-byte cache line (soft — overridable)
    constraint reasonable_byteen_c {
        soft byteen inside {
            {64{1'b1}},                  // Full 64-byte cache line
            64'h0000_0000_FFFF_FFFF,     // Lower 32 bytes
            64'hFFFF_FFFF_0000_0000,     // Upper 32 bytes
            64'h0000_0000_0000_00FF,     // First 8 bytes (doubleword)
            64'hFF00_0000_0000_0000,     // Last 8 bytes
            64'h0000_0000_0000_000F,     // First 4 bytes (word)
            64'h0000_0000_0000_0003,     // First 2 bytes (halfword)
            64'h0000_0000_0000_0001      // First byte
        };
    }
    
    //==========================================================================
    // UVM Automation Macros
    // Provides copy, compare, print, record functionality
    //==========================================================================
    `uvm_object_utils_begin(mem_transaction)
        `uvm_field_int(rw, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(byteen, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(tag, UVM_ALL_ON)
        `uvm_field_int(rsp_data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rsp_tag, UVM_ALL_ON)
        `uvm_field_int(completed, UVM_ALL_ON)
    `uvm_object_utils_end
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "mem_transaction");
        super.new(name);
        completed = 0;
        error = 0;
    endfunction
    
    //==========================================================================
    // Helper Methods
    //==========================================================================
    
    // Check if this is a read transaction
    function bit is_read();
        return (rw == 1'b0);
    endfunction
    
    // Check if this is a write transaction
    function bit is_write();
        return (rw == 1'b1);
    endfunction
    
    // Calculate and return latency (returns -1 if not completed)
    function int get_latency();
        if (completed)
            return latency_cycles;
        else
            return -1;
    endfunction
    
    // Get the number of active bytes (for partial writes) — byteen is 64 bits
    function int get_active_bytes();
        int count = 0;
        for (int i = 0; i < 64; i++) begin
            if (byteen[i]) count++;
        end
        return count;
    endfunction
    
    // Get human-readable access size string
    function string get_access_size_string();
        case (get_active_bytes())
            1:  return "BYTE";
            2:  return "HALFWORD";
            4:  return "WORD";
            8:  return "DOUBLEWORD";
            32: return "HALF_LINE";
            64: return "FULL_LINE";
            default: return $sformatf("%0d BYTES", get_active_bytes());
        endcase
    endfunction
    
    //==========================================================================
    // Convert to String (for debugging and logging)
    //==========================================================================
    virtual function string convert2string();
        string s;
        s = super.convert2string();
        s = {s, "\n┌─ Memory Transaction ─────────────"};
        s = {s, $sformatf("\n│ Type:        %s", rw ? "WRITE" : "READ")};
        s = {s, $sformatf("\n│ Address:     0x%h", addr)};
        s = {s, $sformatf("\n│ Access Size: %s", get_access_size_string())};
        
        if (rw) begin
            s = {s, $sformatf("\n│ Write Data:  0x%h", data)};
            s = {s, $sformatf("\n│ Byte Enable: 0x%h", byteen)};
        end
        
        s = {s, $sformatf("\n│ Tag:         %0d", tag)};
        
        if (completed) begin
            if (!rw) begin
                s = {s, $sformatf("\n│ Read Data:   0x%h", rsp_data)};
            end
            s = {s, $sformatf("\n│ Latency:     %0d cycles", latency_cycles)};
            s = {s, $sformatf("\n│ Status:      %s", error ? "✗ ERROR" : "✓ OK")};
        end else begin
            s = {s, "\n│ Status:      PENDING"};
        end
        
        s = {s, "\n└──────────────────────────────────"};
        return s;
    endfunction
    
    //==========================================================================
    // Comparison Function (for scoreboard matching)
    // Compares key identifying fields (not responses)
    //==========================================================================
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        mem_transaction rhs_;
        
        if (!$cast(rhs_, rhs)) begin
            `uvm_error("MEM_TRANS", "Cast failed in do_compare")
            return 0;
        end
        
        return (
            super.do_compare(rhs, comparer) &&
            (rw == rhs_.rw) &&
            (addr == rhs_.addr) &&
            (rw ? (data == rhs_.data) : 1) &&  // Compare data only for writes
            (byteen == rhs_.byteen)
        );
    endfunction
    
    //==========================================================================
    // Deep Copy Function
    // Used when transactions need to be cloned
    //==========================================================================
    virtual function void do_copy(uvm_object rhs);
        mem_transaction rhs_;
        
        if (!$cast(rhs_, rhs)) begin
            `uvm_error("MEM_TRANS", "Cast failed in do_copy")
            return;
        end
        
        super.do_copy(rhs);
        
        // Copy all fields
        rw = rhs_.rw;
        addr = rhs_.addr;
        data = rhs_.data;
        byteen = rhs_.byteen;
        tag = rhs_.tag;
        rsp_data = rhs_.rsp_data;
        rsp_tag = rhs_.rsp_tag;
        req_time = rhs_.req_time;
        rsp_time = rhs_.rsp_time;
        latency_cycles = rhs_.latency_cycles;
        completed = rhs_.completed;
        error = rhs_.error;
    endfunction
    
endclass : mem_transaction

`endif // MEM_TRANSACTION_SV