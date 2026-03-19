////////////////////////////////////////////////////////////////////////////////
// File: axi_transaction.sv
// Description: AXI4 Transaction Sequence Item
//
// This class represents a single AXI4 transaction that can be either a 
// write or read operation. It supports:
//   - Burst transactions (up to 256 beats per AXI4 spec)
//   - Multiple burst types (FIXED, INCR, WRAP)
//   - Configurable transfer sizes (1, 2, 4, 8 bytes per beat)
//   - Out-of-order transaction support via ID field
//   - 4KB boundary checks (AXI4 requirement)
//   - Byte-enable (strobe) support for partial writes
//
// Transaction Flow:
//   1. Sequence creates and randomizes transaction
//   2. Driver allocates ID and drives to DUT
//   3. Monitor captures transaction and responses
//   4. Scoreboard compares against reference model
//
// Key Features:
//   ✓ Configurable ID width (from vortex_config)
//   ✓ Automatic array allocation in post_randomize
//   ✓ Cycle-accurate timing instrumentation
//   ✓ Helper functions for address calculation
//   ✓ Comprehensive constraints matching AXI4 protocol
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_TRANSACTION_SV
`define AXI_TRANSACTION_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;

class axi_transaction extends uvm_sequence_item;
    
    //==========================================================================
    // Enumerated Types
    //==========================================================================
    
    // Transaction type: READ or WRITE
    typedef enum {
        AXI_READ,
        AXI_WRITE
    } axi_trans_type_e;
    
    // Burst type per AXI4 specification
    // FIXED: Same address for all beats (FIFO access)
    // INCR:  Incrementing addresses (normal memory access)
    // WRAP:  Wrapping addresses within boundary (cache line)
    typedef enum bit [1:0] {
        AXI_FIXED = 2'b00,
        AXI_INCR  = 2'b01,
        AXI_WRAP  = 2'b10
    } axi_burst_type_e;
    
    // Response type per AXI4 specification
    // OKAY:   Successful transaction
    // EXOKAY: Exclusive access succeeded
    // SLVERR: Slave error (address doesn't exist)
    // DECERR: Decode error (no slave at address)
    typedef enum bit [1:0] {
        AXI_OKAY   = 2'b00,
        AXI_EXOKAY = 2'b01,
        AXI_SLVERR = 2'b10,
        AXI_DECERR = 2'b11
    } axi_resp_e;

    //==========================================================================
    // Configuration Handle
    // Used to get parameterized values like AXI_ID_WIDTH
    //==========================================================================
    vortex_config cfg;
    //==========================================================================
    // Transaction Fields - Common to Both Read and Write
    //==========================================================================
    
    // Transaction type selector
    rand axi_trans_type_e trans_type;
    
    // Transaction ID — AXI_ID_WIDTH = VX_MEM_TAG_WIDTH = 8 (256 IDs)
    rand bit [7:0] id;
    
    // Starting address — 64-bit to cover both RV32 (32-bit) and RV64 (48-bit)
    // RV32 upper bits constrained to 0 via cfg; stored wide to avoid truncation
    rand bit [63:0] addr;
    
    // Burst length minus 1 (AXI4 encoding)
    // len=0 means 1 beat, len=255 means 256 beats
    rand bit [7:0] len;
    
    // Bytes per beat as power of 2 (AXI4 encoding)
    // size=0: 1 byte,  size=1: 2 bytes
    // size=2: 4 bytes, size=3: 8 bytes
    rand bit [2:0] size;
    
    // Burst type selector
    rand axi_burst_type_e burst;
    
    //==========================================================================
    // Write-Specific Fields
    // Only valid when trans_type == AXI_WRITE
    //==========================================================================
    
    // Write data array — one entry per beat, 512-bit wide (VX_MEM_DATA_WIDTH=512)
    rand bit [511:0] wdata[];
    
    // Write strobe array — 64 bytes per 512-bit beat (VX_MEM_BYTEEN_WIDTH=64)
    rand bit [63:0] wstrb[];
    
    //==========================================================================
    // Read-Specific Fields
    //==========================================================================
    
    // Read data — 512-bit wide (VX_MEM_DATA_WIDTH=512)
    bit [511:0] rdata[];
    
    // Read response array - one per beat (can have errors mid-burst)
    axi_resp_e rresp[];
    
    //==========================================================================
    // Write Response Field
    // Populated when B channel response arrives
    //==========================================================================
    axi_resp_e bresp;
    
    //==========================================================================
    // Timing Instrumentation
    // Used for latency calculation and performance analysis
    // All values in clock cycles (not simulation time)
    //==========================================================================
    
    // Cycle when address phase completed (AW/AR handshake)
    longint addr_cycle;
    
    // Cycle when each data beat completed (W/R handshakes)
    // Array size matches beat count
    longint data_cycle[];
    
    // Cycle when final response received (B or last R)
    longint resp_cycle;
    
    // Calculated latency: resp_cycle - addr_cycle
    int latency_cycles;
    
    //==========================================================================
    // Status Flags
    //==========================================================================
    
    // Set to 1 when transaction fully completes
    bit completed;
    
    // Set to 1 if any response was not OKAY
    bit error;
    
    //==========================================================================
    // Constraints
    //==========================================================================
    
    // ID is 8-bit fixed (AXI_ID_WIDTH = VX_MEM_TAG_WIDTH = 8)
    // No additional constraint needed — field declaration enforces 8-bit range
    constraint valid_id_c {
        id < (1 << AXI_ID_WIDTH);  // AXI_ID_WIDTH = 8 from vortex_config_pkg
    }
    
    // Burst length must be valid AXI4 range
    // 0-255 represents 1-256 beats
    constraint valid_len_c {
        len inside {[0:255]};
    }
    
    // Transfer size must be valid
    // 0-3 represents 1, 2, 4, 8 byte transfers
    constraint valid_size_c {
        size inside {[0:3]};
    }
    
    // Address must be aligned to transfer size
    // Prevents unaligned accesses which are protocol violations
    constraint addr_alignment_c {
        //if (size == 0) addr[0:0] == 1'b0;   // Byte access (always aligned)
        if (size == 1) addr[0:0] == 1'b0;   // Halfword must be even address
        if (size == 2) addr[1:0] == 2'b00;  // Word must be 4-byte aligned
        if (size == 3) addr[2:0] == 3'b000; // Doubleword must be 8-byte aligned
    }
    
    // AXI4 Protocol Requirement: Bursts cannot cross 4KB boundaries
    constraint no_4kb_cross_c {
        (addr & 64'hFFFFFFFFFFFFF000) == 
        ((addr + ((len + 1) * (1 << size))) & 64'hFFFFFFFFFFFFF000);
    }
    
    // Soft constraint for typical burst lengths
    constraint reasonable_burst_c {
        soft len inside {0, 1, 3, 7, 15}; // 1, 2, 4, 8, 16 beats
    }
    
    // Soft constraint for typical burst type
    constraint typical_burst_type_c {
        soft burst == AXI_INCR;
    }
    
    // Data array size must match burst length
    constraint data_size_c {
        if (trans_type == AXI_WRITE) {
            wdata.size() == len + 1;
            wstrb.size() == len + 1;
        }
        solve len before wdata;
        solve len before wstrb;
    }
    
    // Default to full byte enables — 64 bytes per 512-bit beat
    constraint full_strobes_c {
        foreach (wstrb[i]) {
            soft wstrb[i] == 64'hFFFF_FFFF_FFFF_FFFF;
        }
    }
    
    //==========================================================================
    // UVM Automation Macros
    // Provides copy, compare, print, record functionality
    //==========================================================================
    `uvm_object_utils_begin(axi_transaction)
        `uvm_field_enum(axi_trans_type_e, trans_type, UVM_ALL_ON)
        `uvm_field_int(id, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(len, UVM_ALL_ON)
        `uvm_field_int(size, UVM_ALL_ON)
        `uvm_field_enum(axi_burst_type_e, burst, UVM_ALL_ON)
        `uvm_field_array_int(wdata, UVM_ALL_ON | UVM_HEX)
        `uvm_field_enum(axi_resp_e, bresp, UVM_ALL_ON)
        `uvm_field_int(completed, UVM_ALL_ON)
    `uvm_object_utils_end
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "axi_transaction");
        super.new(name);
        completed = 0;
        error = 0;
    endfunction
    
    //==========================================================================
    // Post-Randomize Hook
    // Called automatically after successful randomization
    // Allocates response arrays based on randomized transaction parameters
    //==========================================================================
    function void post_randomize();
        // Allocate response arrays for read transactions
        // Size matches burst length
        if (trans_type == AXI_READ) begin
            rdata = new[len + 1];
            rresp = new[len + 1];
        end
        
        // Allocate timing arrays for all transactions
        // Tracks when each beat completes
        data_cycle = new[len + 1];
    endfunction
    
    //==========================================================================
    // Helper Functions
    //==========================================================================
    
    // Returns total number of beats in this burst
    // AXI encodes len as (beats - 1), so add 1
    function int get_num_beats();
        return len + 1;
    endfunction
    
    // Returns bytes transferred per beat
    // size encodes this as power of 2: 2^size bytes
    function int get_bytes_per_beat();
        return (1 << size);
    endfunction
    
    // Returns total bytes transferred in entire burst
    function int get_total_bytes();
        return get_num_beats() * get_bytes_per_beat();
    endfunction
    
    // Calculates the address for a specific beat number
    function bit [63:0] get_next_addr(int beat_num);
        bit [63:0] next_addr;
        
        case (burst)
            AXI_FIXED: begin
                next_addr = addr;
            end
            AXI_INCR: begin
                next_addr = addr + (beat_num * get_bytes_per_beat());
            end
            AXI_WRAP: begin
                int wrap_boundary = get_num_beats() * get_bytes_per_beat();
                int offset = (addr + (beat_num * get_bytes_per_beat())) % wrap_boundary;
                next_addr = (addr & ~(wrap_boundary - 1)) | offset;
            end
            default: next_addr = addr;
        endcase
        
        return next_addr;
    endfunction
    
    // Checks if burst violates 4KB boundary rule
    function bit crosses_4kb_boundary();
        bit [63:0] start_page = addr & 64'hFFFFFFFFFFFFF000;
        bit [63:0] end_addr   = addr + get_total_bytes() - 1;
        bit [63:0] end_page   = end_addr & 64'hFFFFFFFFFFFFF000;
        return (start_page != end_page);
    endfunction
    
    // Checks if all responses are OKAY
    // Returns 1 if transaction succeeded, 0 if any error
    function bit is_response_ok();
        if (trans_type == AXI_WRITE) begin
            // Write transactions have single response
            return (bresp == AXI_OKAY);
        end else begin
            // Read transactions have one response per beat
            foreach (rresp[i]) begin
                if (rresp[i] != AXI_OKAY)
                    return 0;
            end
            return 1;
        end
    endfunction
    
    //==========================================================================
    // Convert to String
    // Provides human-readable representation for debugging
    //==========================================================================
    virtual function string convert2string();
        string s;
        s = super.convert2string();
        s = {s, $sformatf("\n┌─ AXI Transaction ────────────────────────")};
        s = {s, $sformatf("\n│ Type:      %s", trans_type.name())};
        s = {s, $sformatf("\n│ ID:        %0d", id)};
        s = {s, $sformatf("\n│ Address:   0x%h", addr)};
        s = {s, $sformatf("\n│ Length:    %0d beats", get_num_beats())};
        s = {s, $sformatf("\n│ Size:      %0d bytes/beat", get_bytes_per_beat())};
        s = {s, $sformatf("\n│ Burst:     %s", burst.name())};
        s = {s, $sformatf("\n│ Total:     %0d bytes", get_total_bytes())};
        
        if (completed) begin
            s = {s, $sformatf("\n│ Latency:   %0d cycles", latency_cycles)};
            s = {s, $sformatf("\n│ Response:  %s", is_response_ok() ? "✓ OK" : "✗ ERROR")};
        end else begin
            s = {s, "\n│ Status:    PENDING"};
        end
        
        s = {s, "\n└──────────────────────────────────────────"};
        return s;
    endfunction
    
    //==========================================================================
    // Compare Function
    // Used by scoreboard to match transactions
    // Compares key identifying fields (not data/response)
    //==========================================================================
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi_transaction rhs_;
        
        // Type cast to axi_transaction
        if (!$cast(rhs_, rhs)) begin
            `uvm_error("AXI_TRANS", "Cast failed in do_compare")
            return 0;
        end
        
        // Compare key fields that identify transaction
        return (
            super.do_compare(rhs, comparer) &&
            (trans_type == rhs_.trans_type) &&
            (id == rhs_.id) &&
            (addr == rhs_.addr) &&
            (len == rhs_.len) &&
            (size == rhs_.size)
        );
    endfunction
    
endclass : axi_transaction

`endif // AXI_TRANSACTION_SV