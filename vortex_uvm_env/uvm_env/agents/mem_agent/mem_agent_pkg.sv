////////////////////////////////////////////////////////////////////////////////
// File: mem_agent_pkg.sv
// Description: Memory Agent Package for Vortex Custom Memory Interface
//
// This package bundles all memory agent components into a single importable
// unit. It provides:
//   - Memory transaction class
//   - Driver, Monitor, Sequencer, Agent classes
//   - Complete sequence library
//   - Memory protocol definitions
//
// Usage in test environment:
//   import mem_agent_pkg::*;
//
// Dependencies:
//   - uvm_pkg (UVM library)
//   - vortex_config_pkg (Vortex configuration)
//   - vortex_mem_if (Memory interface definition)
//
// Compilation Order:
//   1. Compile vortex_config_pkg.sv
//   2. Compile vortex_mem_if.sv
//   3. Compile mem_agent_pkg.sv
//   4. Use in test environment
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef MEM_AGENT_PKG_SV
`define MEM_AGENT_PKG_SV

package mem_agent_pkg;
    
    //==========================================================================
    // Import Required Packages
    //==========================================================================
    
    // UVM base library - provides all UVM classes and macros
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Vortex configuration package - provides vortex_config class and parameters
    import vortex_config_pkg::*;
    
    //==========================================================================
    // Memory Protocol Constants
    // Derived from Vortex memory interface specification
    //==========================================================================
    
    // Memory operation types
    parameter bit MEM_READ  = 1'b0;
    parameter bit MEM_WRITE = 1'b1;
    
    // Common byte enable patterns (for 64-bit/8-byte data width)
    parameter bit [7:0] BYTEEN_FULL_WORD  = 8'hFF;  // All 8 bytes
    parameter bit [7:0] BYTEEN_LOWER_WORD = 8'h0F;  // Lower 4 bytes
    parameter bit [7:0] BYTEEN_UPPER_WORD = 8'hF0;  // Upper 4 bytes
    parameter bit [7:0] BYTEEN_BYTE_0     = 8'h01;  // Byte 0 only
    parameter bit [7:0] BYTEEN_BYTE_1     = 8'h02;  // Byte 1 only
    parameter bit [7:0] BYTEEN_BYTE_2     = 8'h04;  // Byte 2 only
    parameter bit [7:0] BYTEEN_BYTE_3     = 8'h08;  // Byte 3 only
    parameter bit [7:0] BYTEEN_BYTE_4     = 8'h10;  // Byte 4 only
    parameter bit [7:0] BYTEEN_BYTE_5     = 8'h20;  // Byte 5 only
    parameter bit [7:0] BYTEEN_BYTE_6     = 8'h40;  // Byte 6 only
    parameter bit [7:0] BYTEEN_BYTE_7     = 8'h80;  // Byte 7 only
    
    //==========================================================================
    // Include Agent Component Files
    // Order matters: transaction first, then components using it
    //==========================================================================
    
    // Transaction class (sequence item)
    `include "mem_transaction.sv"
    
    // Driver (active component)
    `include "mem_driver.sv"
    
    // Monitor (passive observer)
    `include "mem_monitor.sv"
    
    // Sequencer (transaction arbiter)
    `include "mem_sequencer.sv"
    
    // Sequences (stimulus generators)
    `include "mem_sequences.sv"
    
    // Agent container (top-level)
    `include "mem_agent.sv"
    
    //==========================================================================
    // Utility Functions
    // Helper functions for memory operations
    //==========================================================================
    
    // Convert byte count to byte enable mask
    // Returns appropriate byteen value for specified number of bytes
    function automatic bit [7:0] bytes_to_byteen(int num_bytes, int start_byte = 0);
        bit [7:0] mask = 0;
        
        for (int i = 0; i < num_bytes; i++) begin
            if (start_byte + i < 8) begin
                mask[start_byte + i] = 1'b1;
            end
        end
        
        return mask;
    endfunction
    
    // Count number of active bytes in byte enable
    function automatic int count_active_bytes(bit [7:0] byteen);
        int count = 0;
        
        for (int i = 0; i < 8; i++) begin
            if (byteen[i]) count++;
        end
        
        return count;
    endfunction
    
    // Check if address is aligned to specified boundary
    function automatic bit is_aligned(bit [31:0] addr, int alignment);
        return ((addr & (alignment - 1)) == 0);
    endfunction
    
    // Align address down to specified boundary
    function automatic bit [31:0] align_address(bit [31:0] addr, int alignment);
        return (addr & ~(alignment - 1));
    endfunction
    
    // Apply byte enable mask to data
    function automatic bit [63:0] apply_byteen(
        bit [63:0] data,
        bit [7:0]  byteen,
        bit [63:0] original_data = 64'h0
    );
        bit [63:0] result = original_data;
        
        for (int i = 0; i < 8; i++) begin
            if (byteen[i]) begin
                result[(i*8)+:8] = data[(i*8)+:8];
            end
        end
        
        return result;
    endfunction
    
    // Convert bytes to human-readable size string
    function automatic string bytes_to_string(longint bytes);
        real kb = real'(bytes) / 1024.0;
        real mb = kb / 1024.0;
        real gb = mb / 1024.0;
        
        if (gb >= 1.0)
            return $sformatf("%.2f GB", gb);
        else if (mb >= 1.0)
            return $sformatf("%.2f MB", mb);
        else if (kb >= 1.0)
            return $sformatf("%.2f KB", kb);
        else
            return $sformatf("%0d B", bytes);
    endfunction
    
    //==========================================================================
    // Package Information
    //==========================================================================
    
    // Version information for debug
    function automatic string get_mem_agent_version();
        return "Vortex Memory UVM Agent v1.0.0";
    endfunction
    
    // Print package configuration summary
    function automatic void print_mem_agent_info();
        $display("================================================================================");
        $display("  %s", get_mem_agent_version());
        $display("================================================================================");
        $display("  Memory Interface Configuration:");
        $display("    Address Width:       %0d bits", VX_MEM_ADDR_WIDTH);
        $display("    Data Width:          %0d bits", VX_MEM_DATA_WIDTH);
        $display("    Byte Enable Width:   %0d bits", VX_MEM_BYTEEN_WIDTH);
        $display("    Tag Width:           %0d bits", VX_MEM_TAG_WIDTH);
        $display("  Included Components:");
        $display("    ✓ mem_transaction    - Sequence item (64-bit data)");
        $display("    ✓ mem_driver         - Active stimulus driver");
        $display("    ✓ mem_monitor        - Passive protocol monitor");
        $display("    ✓ mem_sequencer      - Transaction arbiter");
        $display("    ✓ mem_sequences      - Pre-built stimulus library");
        $display("    ✓ mem_agent          - Container component");
        $display("================================================================================");
    endfunction
    
endpackage : mem_agent_pkg

`endif // MEM_AGENT_PKG_SV
