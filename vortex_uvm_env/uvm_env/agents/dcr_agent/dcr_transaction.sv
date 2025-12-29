////////////////////////////////////////////////////////////////////////////////
// File: dcr_transaction.sv
// Description: DCR (Device Configuration Register) Transaction Class
//
// This transaction represents a write to one of Vortex's Device Configuration
// Registers (DCRs). DCRs are write-only registers used to configure the GPU
// before execution begins.
//
// Key DCRs:
//   - STARTUP_ADDR0/1: 64-bit program counter (entry point)
//   - ARGV_PTR0/1:     64-bit pointer to program arguments  
//   - MPM_CLASS:       Performance monitoring configuration
//
// Protocol:
//   - Write-only (no read-back)
//   - Single-cycle write (wr_valid asserted for 1 cycle)
//   - Byte-addressed (word index << 2)
//   - No handshake or response
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef DCR_TRANSACTION_SV
`define DCR_TRANSACTION_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;
import dcr_agent_pkg::*;


class dcr_transaction extends uvm_sequence_item;
    
    //==========================================================================
    // Transaction Fields
    //==========================================================================
    
    // DCR address (byte-addressed)
    rand bit [VX_DCR_ADDR_WIDTH-1:0] addr;
    
    // Data to write
    rand bit [VX_DCR_DATA_WIDTH-1:0] data;
    
    // Timing information
    time write_time;
    
    // Status
    bit completed;
    
    //==========================================================================
    // DCR Address Enumeration (BYTE-ADDRESSED)
    // Addresses are (word_index << 2) per Vortex spec
    //==========================================================================
    
    typedef enum bit [31:0] {
        DCR_STARTUP_ADDR0 = (VX_DCR_BASE_STARTUP_ADDR0 << 2),  // PC[31:0]
        DCR_STARTUP_ADDR1 = (VX_DCR_BASE_STARTUP_ADDR1 << 2),  // PC[63:32]
        DCR_ARGV_PTR0     = (VX_DCR_BASE_STARTUP_ARG0  << 2),  // argv[31:0]
        DCR_ARGV_PTR1     = (VX_DCR_BASE_STARTUP_ARG1  << 2),  // argv[63:32]
        DCR_MPM_CLASS     = (VX_DCR_BASE_MPM_CLASS     << 2)   // Perf monitor
    } dcr_addr_e;
    
    //==========================================================================
    // Constraints
    //==========================================================================
    
    // Only allow writes to valid DCR addresses
    constraint valid_addr_c {
        addr inside {
            DCR_STARTUP_ADDR0,
            DCR_STARTUP_ADDR1,
            DCR_ARGV_PTR0,
            DCR_ARGV_PTR1,
            DCR_MPM_CLASS
        };
    }
    
    // Startup PC must be word-aligned
    constraint startup_pc_align_c {
        if (addr == DCR_STARTUP_ADDR0 || addr == DCR_STARTUP_ADDR1) {
            data[1:0] == 2'b00;  // 4-byte word aligned
        }
    }
    
    //==========================================================================
    // UVM Automation Macros
    //==========================================================================
    `uvm_object_utils_begin(dcr_transaction)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(completed, UVM_ALL_ON)
    `uvm_object_utils_end
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "dcr_transaction");
        super.new(name);
        completed = 0;
    endfunction
    
    //==========================================================================
    // Helper Methods
    //==========================================================================
    
    // Get human-readable DCR name from address
    function string get_dcr_name();
        case (addr)
            DCR_STARTUP_ADDR0: return "STARTUP_ADDR0";
            DCR_STARTUP_ADDR1: return "STARTUP_ADDR1";
            DCR_ARGV_PTR0:     return "ARGV_PTR0";
            DCR_ARGV_PTR1:     return "ARGV_PTR1";
            DCR_MPM_CLASS:     return "MPM_CLASS";
            default:           return $sformatf("UNKNOWN[0x%h]", addr);
        endcase
    endfunction
    
    // Check if this is a startup configuration register
    function bit is_startup_config();
        return (addr == DCR_STARTUP_ADDR0 ||
                addr == DCR_STARTUP_ADDR1 ||
                addr == DCR_ARGV_PTR0 ||
                addr == DCR_ARGV_PTR1);
    endfunction
    
    // Check if this is a performance monitoring configuration
    function bit is_perf_config();
        return (addr == DCR_MPM_CLASS);
    endfunction
    
    //==========================================================================
    // Convert to String (for debugging and logging)
    //==========================================================================
    virtual function string convert2string();
        return $sformatf(
            "DCR %s [0x%08h] = 0x%08h (%s)",
            get_dcr_name(),
            addr,
            data,
            completed ? "DONE" : "PENDING"
        );
    endfunction
    
    //==========================================================================
    // Comparison Function (for scoreboard)
    //==========================================================================
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        dcr_transaction rhs_;
        
        if (!$cast(rhs_, rhs)) begin
            `uvm_error("DCR_TRANS", "Cast failed in do_compare")
            return 0;
        end
        
        return (
            super.do_compare(rhs, comparer) &&
            (addr == rhs_.addr) &&
            (data == rhs_.data)
        );
    endfunction
    
    //==========================================================================
    // Deep Copy Function
    //==========================================================================
    virtual function void do_copy(uvm_object rhs);
        dcr_transaction rhs_;
        
        if (!$cast(rhs_, rhs)) begin
            `uvm_error("DCR_TRANS", "Cast failed in do_copy")
            return;
        end
        
        super.do_copy(rhs);
        
        addr = rhs_.addr;
        data = rhs_.data;
        write_time = rhs_.write_time;
        completed = rhs_.completed;
    endfunction
    
endclass : dcr_transaction

`endif // DCR_TRANSACTION_SV
