////////////////////////////////////////////////////////////////////////////////
// File: axi_agent_pkg.sv
// Description: AXI4 Agent Package
//
// This package bundles all AXI4 UVM agent components into a single importable
// unit. It provides:
//   - All AXI transaction types
//   - Driver, Monitor, Sequencer, Agent classes
//   - Complete sequence library
//   - AXI4 protocol definitions
//
// Usage in test environment:
//   import axi_agent_pkg::*;
//
// Dependencies:
//   - uvm_pkg (UVM library)
//   - vortex_config_pkg (Vortex configuration)
//   - vortex_axi_if (AXI interface definition)
//
// Compilation Order:
//   1. Compile vortex_config_pkg.sv
//   2. Compile vortex_axi_if.sv
//   3. Compile axi_agent_pkg.sv
//   4. Use in test environment
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_AGENT_PKG_SV
`define AXI_AGENT_PKG_SV

package axi_agent_pkg;
    
    //==========================================================================
    // Import Required Packages
    //==========================================================================
    
    // UVM base library - provides all UVM classes and macros
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Vortex configuration package - provides vortex_config class
    import vortex_config_pkg::*;
    
    //==========================================================================
    // AXI4 Protocol Constants
    // Derived from AMBA AXI4 specification
    //==========================================================================
    
    // Burst Type Encodings (AxBURST)
    parameter bit [1:0] AXI_BURST_FIXED = 2'b00;  // Same address (FIFO)
    parameter bit [1:0] AXI_BURST_INCR  = 2'b01;  // Incrementing address
    parameter bit [1:0] AXI_BURST_WRAP  = 2'b10;  // Wrapping burst
    parameter bit [1:0] AXI_BURST_RSVD  = 2'b11;  // Reserved
    
    // Response Type Encodings (BRESP, RRESP)
    parameter bit [1:0] AXI_RESP_OKAY   = 2'b00;  // Normal success
    parameter bit [1:0] AXI_RESP_EXOKAY = 2'b01;  // Exclusive access OK
    parameter bit [1:0] AXI_RESP_SLVERR = 2'b10;  // Slave error
    parameter bit [1:0] AXI_RESP_DECERR = 2'b11;  // Decode error
    
    // Transfer Size Encodings (AxSIZE) - bytes per beat
    parameter bit [2:0] AXI_SIZE_1B   = 3'b000;   // 1 byte
    parameter bit [2:0] AXI_SIZE_2B   = 3'b001;   // 2 bytes
    parameter bit [2:0] AXI_SIZE_4B   = 3'b010;   // 4 bytes
    parameter bit [2:0] AXI_SIZE_8B   = 3'b011;   // 8 bytes
    parameter bit [2:0] AXI_SIZE_16B  = 3'b100;   // 16 bytes
    parameter bit [2:0] AXI_SIZE_32B  = 3'b101;   // 32 bytes
    parameter bit [2:0] AXI_SIZE_64B  = 3'b110;   // 64 bytes
    parameter bit [2:0] AXI_SIZE_128B = 3'b111;   // 128 bytes
    
    // Cache Control Encodings (AxCACHE)
    // [0]: Bufferable, [1]: Cacheable, [2]: Read-allocate, [3]: Write-allocate
    parameter bit [3:0] AXI_CACHE_DEV_NOBUF   = 4'b0000;  // Device non-bufferable
    parameter bit [3:0] AXI_CACHE_DEV_BUF     = 4'b0001;  // Device bufferable
    parameter bit [3:0] AXI_CACHE_NORM_NOCACH = 4'b0010;  // Normal non-cacheable
    parameter bit [3:0] AXI_CACHE_NORM_BUF    = 4'b0011;  // Normal bufferable
    parameter bit [3:0] AXI_CACHE_WTHRU       = 4'b1010;  // Write-through
    parameter bit [3:0] AXI_CACHE_WBACK       = 4'b1111;  // Write-back
    
    // Protection Control Encodings (AxPROT)
    // [0]: Privileged, [1]: Non-secure, [2]: Instruction
    parameter bit [2:0] AXI_PROT_PRIV_SEC_DATA  = 3'b000;
    parameter bit [2:0] AXI_PROT_PRIV_SEC_INST  = 3'b100;
    parameter bit [2:0] AXI_PROT_UNPR_SEC_DATA  = 3'b001;
    parameter bit [2:0] AXI_PROT_PRIV_NSEC_DATA = 3'b010;
    
    // Lock Type Encodings (AxLOCK)
    parameter bit AXI_LOCK_NORMAL    = 1'b0;      // Normal access
    parameter bit AXI_LOCK_EXCLUSIVE = 1'b1;      // Exclusive access
    
    // Maximum Values (AXI4 Specification Limits)
    parameter int AXI_MAX_BURST_LEN = 256;        // Maximum beats per burst
    parameter int AXI_4KB_BOUNDARY  = 4096;       // Address boundary limit
    
    //==========================================================================
    // AXI Agent Configuration Parameters
    // These can be overridden via vortex_config
    //==========================================================================
    
    // Default ID width (can be 1-16 bits)
    parameter int DEFAULT_AXI_ID_WIDTH = 4;       // 16 possible IDs
    
    // Default data width (must match DUT)
    parameter int DEFAULT_AXI_DATA_WIDTH = 64;    // 64-bit data bus
    
    // Default address width
    parameter int DEFAULT_AXI_ADDR_WIDTH = 32;    // 32-bit address space
    
    // Default timeout for handshakes (clock cycles)
    parameter int DEFAULT_AXI_TIMEOUT = 1000;     // 1000 cycle timeout
    
    //==========================================================================
    // Include Agent Component Files
    // Order matters: transaction first, then components using it
    //==========================================================================
    
    // Transaction class (sequence item)
    `include "axi_transaction.sv"
    
    // Driver (active component)
    `include "axi_driver.sv"
    
    // Monitor (passive observer)
    `include "axi_monitor.sv"
    
    // Sequencer (transaction arbiter)
    `include "axi_sequencer.sv"
    
    // Sequences (stimulus generators)
    `include "axi_sequences.sv"
    
    // Agent container (top-level)
    `include "axi_agent.sv"
    
    //==========================================================================
    // Utility Functions
    // Helper functions for address calculations and conversions
    //==========================================================================
    
    // Convert byte count to AXI SIZE encoding
    // Returns 3-bit encoding for AxSIZE field
    function automatic bit [2:0] bytes_to_axi_size(int num_bytes);
        case (num_bytes)
            1:   return AXI_SIZE_1B;
            2:   return AXI_SIZE_2B;
            4:   return AXI_SIZE_4B;
            8:   return AXI_SIZE_8B;
            16:  return AXI_SIZE_16B;
            32:  return AXI_SIZE_32B;
            64:  return AXI_SIZE_64B;
            128: return AXI_SIZE_128B;
            default: begin
                $error("[AXI_PKG] Invalid byte count %0d for AXI SIZE", num_bytes);
                return AXI_SIZE_1B;
            end
        endcase
    endfunction
    
    // Convert AXI SIZE encoding to byte count
    function automatic int axi_size_to_bytes(bit [2:0] size);
        return (1 << size);
    endfunction
    
    // Calculate aligned address for AXI transfer
    // AXI requires address to be aligned to transfer size
    function automatic bit [31:0] align_address(bit [31:0] addr, bit [2:0] size);
        int mask = (1 << size) - 1;
        return (addr & ~mask);
    endfunction
    
    // Check if burst crosses 4KB boundary
    // Returns 1 if violation, 0 if OK
    function automatic bit crosses_4kb_boundary(
        bit [31:0] addr,
        bit [7:0]  len,
        bit [2:0]  size
    );
        bit [31:0] start_addr = addr;
        bit [31:0] end_addr = addr + ((len + 1) * (1 << size)) - 1;
        bit [31:0] start_page = start_addr & ~32'h00000FFF;
        bit [31:0] end_page = end_addr & ~32'h00000FFF;
        return (start_page != end_page);
    endfunction
    
    // Calculate next address in a burst
    // Handles FIXED, INCR, and WRAP burst types
    function automatic bit [31:0] get_burst_address(
        bit [31:0] base_addr,
        bit [7:0]  len,
        bit [2:0]  size,
        bit [1:0]  burst,
        int        beat_num
    );
        int bytes_per_beat = (1 << size);
        int total_bytes = (len + 1) * bytes_per_beat;
        bit [31:0] next_addr;
        
        case (burst)
            AXI_BURST_FIXED: begin
                // All beats use same address
                next_addr = base_addr;
            end
            
            AXI_BURST_INCR: begin
                // Incrementing address
                next_addr = base_addr + (beat_num * bytes_per_beat);
            end
            
            AXI_BURST_WRAP: begin
                // Wrapping burst within boundary
                int wrap_boundary = total_bytes;
                int offset = (base_addr + (beat_num * bytes_per_beat)) % wrap_boundary;
                next_addr = (base_addr & ~(wrap_boundary - 1)) | offset;
            end
            
            default: begin
                $error("[AXI_PKG] Invalid burst type %0d", burst);
                next_addr = base_addr;
            end
        endcase
        
        return next_addr;
    endfunction
    
    // Decode burst type to string
    function automatic string decode_burst_type(bit [1:0] burst);
        case (burst)
            AXI_BURST_FIXED: return "FIXED";
            AXI_BURST_INCR:  return "INCR";
            AXI_BURST_WRAP:  return "WRAP";
            default:         return "RESERVED";
        endcase
    endfunction
    
    // Decode response to string
    function automatic string decode_response(bit [1:0] resp);
        case (resp)
            AXI_RESP_OKAY:   return "OKAY";
            AXI_RESP_EXOKAY: return "EXOKAY";
            AXI_RESP_SLVERR: return "SLVERR";
            AXI_RESP_DECERR: return "DECERR";
        endcase
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
    function automatic string get_axi_agent_version();
        return "Vortex AXI4 UVM Agent v1.0.0";
    endfunction
    
    // Print package configuration summary
    function automatic void print_axi_agent_info();
        $display("================================================================================");
        $display("  %s", get_axi_agent_version());
        $display("================================================================================");
        $display("  AXI4 Protocol Constants:");
        $display("    Max Burst Length:    %0d beats", AXI_MAX_BURST_LEN);
        $display("    Address Boundary:    %0d bytes (4KB)", AXI_4KB_BOUNDARY);
        $display("  Default Configuration:");
        $display("    ID Width:            %0d bits", DEFAULT_AXI_ID_WIDTH);
        $display("    Data Width:          %0d bits", DEFAULT_AXI_DATA_WIDTH);
        $display("    Address Width:       %0d bits", DEFAULT_AXI_ADDR_WIDTH);
        $display("    Timeout:             %0d cycles", DEFAULT_AXI_TIMEOUT);
        $display("  Included Components:");
        $display("    ✓ axi_transaction    - Sequence item");
        $display("    ✓ axi_driver         - Active stimulus driver");
        $display("    ✓ axi_monitor        - Passive protocol monitor");
        $display("    ✓ axi_sequencer      - Transaction arbiter");
        $display("    ✓ axi_sequences      - Pre-built stimulus library");
        $display("    ✓ axi_agent          - Container component");
        $display("================================================================================");
    endfunction
    
endpackage : axi_agent_pkg

`endif // AXI_AGENT_PKG_SV
