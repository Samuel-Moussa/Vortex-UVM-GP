////////////////////////////////////////////////////////////////////////////////
// File: mem_transaction.sv
// Description: Memory Transaction for Vortex Custom Memory Interface
//
// This transaction represents a single memory request-response pair on the
// Vortex custom memory interface (not AXI). It models:
//   - Read or Write operation
//   - 64-bit data width (VX_MEM_DATA_WIDTH = 64)
//   - 32-bit address space (VX_MEM_ADDR_WIDTH = 32)
//   - 8-bit byte enables (8 bytes for 64-bit data)
//   - Tag-based request/response matching
//
// Usage:
//   - Driver: Drives transactions to DUT
//   - Monitor: Captures transactions from interface
//   - Scoreboard: Compares against simx golden model
//
// **Note for Final State Comparison**:
//   For Option A (final state after EBREAK), the scoreboard will:
//   1. Collect all write transactions during execution
//   2. Build RTL memory state
//   3. Compare against simx memory state at EBREAK
//   This transaction provides the foundation for that tracking.
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
    
    // Address alignment based on byte enable pattern
    // Ensures addresses are properly aligned for access size
    constraint addr_alignment_c {
        // Full 64-bit (8-byte) access must be 8-byte aligned
        (byteen == 8'hFF) -> (addr[2:0] == 3'b000);
        
        // 32-bit (4-byte) access must be 4-byte aligned
        (byteen == 8'h0F || byteen == 8'hF0) -> (addr[1:0] == 2'b00);
        
        // 16-bit (2-byte) access must be 2-byte aligned
        (byteen == 8'h03 || byteen == 8'h0C || 
         byteen == 8'h30 || byteen == 8'hC0) -> (addr[0] == 1'b0);
    }
    
    // Valid address range - must be within Vortex memory space
    // STARTUP_ADDR is typically 0x80000000 (DRAM region)
    constraint valid_addr_c {
        addr inside {
            [vortex_config_pkg::STARTUP_ADDR:
             (vortex_config_pkg::STARTUP_ADDR + 32'h0FFFFFFF)]  // 256MB range
        };
    }
    
    // Byte enable must have at least one bit set
    // Zero byte enable is illegal
    constraint valid_byteen_c {
        byteen != 8'h00;
    }
    
    // Common byte enable patterns (soft constraint - can be overridden)
    // Favors full-word and aligned accesses
    constraint reasonable_byteen_c {
        soft byteen inside {
            8'hFF,  // Full 64-bit word (8 bytes)
            8'h0F,  // Lower 32-bit word (4 bytes)
            8'hF0,  // Upper 32-bit word (4 bytes)
            8'h03,  // Byte 0-1 (halfword)
            8'h0C,  // Byte 2-3 (halfword)
            8'h30,  // Byte 4-5 (halfword)
            8'hC0,  // Byte 6-7 (halfword)
            8'h01,  // Byte 0
            8'h02,  // Byte 1
            8'h04,  // Byte 2
            8'h08,  // Byte 3
            8'h10,  // Byte 4
            8'h20,  // Byte 5
            8'h40,  // Byte 6
            8'h80   // Byte 7
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
    
    // Get the number of active bytes (for partial writes)
    function int get_active_bytes();
        int count = 0;
        for (int i = 0; i < 8; i++) begin
            if (byteen[i]) count++;
        end
        return count;
    endfunction
    
    // Get human-readable access size string
    function string get_access_size_string();
        case (get_active_bytes())
            1: return "BYTE";
            2: return "HALFWORD";
            4: return "WORD";
            8: return "DOUBLEWORD";
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
