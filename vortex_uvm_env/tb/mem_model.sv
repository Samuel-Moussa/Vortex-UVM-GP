// ============================================================================
// File: env/mem_model.sv
// Description: Shared sparse memory model for Vortex UVM testbench
// Author: Vortex UVM Team
// License: Apache-2.0
// ============================================================================

`ifndef MEM_MODEL_SV
`define MEM_MODEL_SV

// ✅ ADD: Import UVM
import uvm_pkg::*;
`include "uvm_macros.svh"

// ✅ CHANGE: Extend from uvm_object instead of plain class
class mem_model extends uvm_object;
  
  // ✅ ADD: UVM registration macro
  `uvm_object_utils(mem_model)

  // --------------------------------------------------------------------------
  // Storage: byte-addressable sparse memory (associative array)
  // --------------------------------------------------------------------------
  bit [7:0] memory [bit [63:0]];


  // --------------------------------------------------------------------------
  // Statistics
  // --------------------------------------------------------------------------
  int unsigned num_reads;
  int unsigned num_writes;
  longint unsigned total_bytes_written;


  // --------------------------------------------------------------------------
  // Constructor / Reset
  // --------------------------------------------------------------------------
  
  // ✅ CHANGE: UVM constructor signature
  function new(string name = "mem_model");
    super.new(name);
    reset();
  endfunction


  function void reset();
    memory.delete();
    num_reads = 0;
    num_writes = 0;
    total_bytes_written = 0;
  endfunction

  // --------------------------------------------------------------------------
  // Byte operations
  // --------------------------------------------------------------------------
  function void write_byte(bit [63:0] addr, bit [7:0] data);
    memory[addr] = data;
    num_writes++;
    total_bytes_written++;
  endfunction

  function bit [7:0] read_byte(bit [63:0] addr);
    num_reads++;
    if (memory.exists(addr))
      return memory[addr];
    else
      return 8'h00; // default for uninitialized
  endfunction

  // --------------------------------------------------------------------------
  // 32-bit word (little-endian)
  // --------------------------------------------------------------------------
  function void write_word(bit [63:0] addr, bit [31:0] data);
    write_byte(addr + 0, data[7:0]);
    write_byte(addr + 1, data[15:8]);
    write_byte(addr + 2, data[23:16]);
    write_byte(addr + 3, data[31:24]);
  endfunction

  function bit [31:0] read_word(bit [63:0] addr);
    bit [31:0] data;
    data[7:0]   = read_byte(addr + 0);
    data[15:8]  = read_byte(addr + 1);
    data[23:16] = read_byte(addr + 2);
    data[31:24] = read_byte(addr + 3);
    return data;
  endfunction

  // --------------------------------------------------------------------------
  // 64-bit dword (little-endian)
  // --------------------------------------------------------------------------
  function void write_dword(bit [63:0] addr, bit [63:0] data);
    write_word(addr + 0, data[31:0]);
    write_word(addr + 4, data[63:32]);
  endfunction

  function bit [63:0] read_dword(bit [63:0] addr);
    bit [63:0] data;
    data[31:0]  = read_word(addr + 0);
    data[63:32] = read_word(addr + 4);
    return data;
  endfunction

  // --------------------------------------------------------------------------
  // Block operations
  // --------------------------------------------------------------------------
  function void write_block(bit [63:0] base_addr, const ref byte bytes[]);
    for (int i = 0; i < bytes.size(); i++) begin
      write_byte(base_addr + i, bytes[i]);
    end
  endfunction

  function void read_block(bit [63:0] base_addr, int num_bytes, output byte bytes[]);
    bytes = new[num_bytes];
    for (int i = 0; i < num_bytes; i++) begin
      bytes[i] = read_byte(base_addr + i);
    end
  endfunction

  // --------------------------------------------------------------------------
  // Load from Verilog hex (readmemh-style words with @addr markers)
  // Notes:
  // - Accepts lines like "@00000000" then 32-bit words per line (little-endian)
  // - base_addr allows remapping the file's 0 to any address
  // --------------------------------------------------------------------------
  function int load_hex_file(string file_path, bit [63:0] base_addr = 64'h0);
    int fd;
    string line;
    bit [31:0] addr_off = 32'h0;
    bit [31:0] word;
    int bytes_loaded = 0;

    fd = $fopen(file_path, "r");
    if (fd == 0) begin
      $error("[MEM_MODEL] Failed to open file: %s", file_path);
      return -1;
    end

    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (line.len() == 0) continue;

      // Skip comments starting with // or #
      if ((line.len() >= 2 && line.tolower()[0] == "/" && line.tolower()[1] == "/") ||
          (line.tolower()[0] == "#"))
        continue;

      // Address marker: @XXXXXXXX
      if (line.tolower()[0] == "@") begin
        //void'($sscanf(line.substr(1), "%h", addr_off));
        void'($sscanf(line, "@%h", addr_off));
        continue;
      end

      // 32-bit data word
      if ($sscanf(line, "%h", word) == 1) begin
        write_word(base_addr + addr_off, word);
        addr_off += 4;
        bytes_loaded += 4;
      end
    end

    $fclose(fd);
    $display("[MEM_MODEL] Loaded %0d bytes from %s at 0x%016h",
             bytes_loaded, file_path, base_addr);
    return bytes_loaded;
  endfunction

  // --------------------------------------------------------------------------
  // Load raw binary file
  // --------------------------------------------------------------------------
  function int load_binary_file(string file_path, bit [63:0] base_addr = 64'h0);
    int fd;
    byte b;
    bit [63:0] addr = base_addr;
    int bytes_loaded = 0;

    fd = $fopen(file_path, "rb");
    if (fd == 0) begin
      $error("[MEM_MODEL] Failed to open file: %s", file_path);
      return -1;
    end

    while (!$feof(fd)) begin
      if ($fread(b, fd) == 1) begin
        write_byte(addr, b);
        addr++;
        bytes_loaded++;
      end
    end

    $fclose(fd);
    $display("[MEM_MODEL] Loaded %0d bytes from %s at 0x%016h",
             bytes_loaded, file_path, base_addr);
    return bytes_loaded;
  endfunction

  // --------------------------------------------------------------------------
  // Region utilities
  // --------------------------------------------------------------------------
  function void fill_region(bit [63:0] start_addr, int unsigned size_bytes, bit [7:0] pattern);
    for (int unsigned i = 0; i < size_bytes; i++) begin
      write_byte(start_addr + i, pattern);
    end
  endfunction

  function void clear_region(bit [63:0] start_addr, int unsigned size_bytes);
    fill_region(start_addr, size_bytes, 8'h00);
  endfunction

  // --------------------------------------------------------------------------
  // Dump helpers (for debug)
  // --------------------------------------------------------------------------
  function void dump_words(bit [63:0] start_addr, int unsigned num_words);
    $display("Memory Dump @ 0x%016h (32-bit words):", start_addr);
    for (int unsigned i = 0; i < num_words; i++) begin
      bit [63:0] a = start_addr + (i * 4);
      $display("0x%016h: %08h", a, read_word(a));
    end
  endfunction

  function void dump_dwords(bit [63:0] start_addr, int unsigned num_dwords);
    $display("Memory Dump @ 0x%016h (64-bit dwords):", start_addr);
    for (int unsigned i = 0; i < num_dwords; i++) begin
      bit [63:0] a = start_addr + (i * 8);
      $display("0x%016h: %016h", a, read_dword(a));
    end
  endfunction

  // --------------------------------------------------------------------------
  // Comparison
  // Returns number of mismatched bytes and fills 'mismatch_offsets' with
  // byte offsets (0..num_bytes-1) relative to start_addr.
  // --------------------------------------------------------------------------
  function int compare_region(
    mem_model other,
    bit [63:0] start_addr,
    int unsigned num_bytes,
    output int mismatch_offsets[$]
  );
    int mismatches = 0;
    for (int unsigned i = 0; i < num_bytes; i++) begin
      bit [63:0] a = start_addr + i;
      bit [7:0] d0 = read_byte(a);
      bit [7:0] d1 = other.read_byte(a);
      if (d0 != d1) begin
        mismatch_offsets.push_back(i);
        mismatches++;
      end
    end
    return mismatches;
  endfunction

  // --------------------------------------------------------------------------
  // Stats
  // --------------------------------------------------------------------------
  function void print_statistics();
    $display("================================================================");
    $display("  mem_model statistics");
    $display("----------------------------------------------------------------");
    $display("  Reads                 : %0d", num_reads);
    $display("  Writes                : %0d", num_writes);
    $display("  Bytes written         : %0d", total_bytes_written);
    $display("  Allocated byte entries: %0d", memory.num());
    $display("================================================================");
  endfunction

endclass : mem_model

`endif // MEM_MODEL_SV











// ////////////////////////////////////////////////////////////////////////////////
// // File: env/mem_model.sv
// // Description: Shared memory model for testbench
// ////////////////////////////////////////////////////////////////////////////////

// `ifndef MEM_MODEL_SV
// `define MEM_MODEL_SV

// class mem_model;
    
//     //==========================================================================
//     // Memory Storage (Sparse Array - Only Allocates Used Addresses)
//     //==========================================================================
//     bit [7:0] memory[bit [63:0]];  // Byte-addressable sparse array
    
//     //==========================================================================
//     // Statistics
//     //==========================================================================
//     int num_reads;
//     int num_writes;
//     longint total_bytes_written;
    
//     //==========================================================================
//     // Constructor
//     //==========================================================================
//     function new();
//         num_reads = 0;
//         num_writes = 0;
//         total_bytes_written = 0;
//     endfunction
    
//     //==========================================================================
//     // Byte Operations
//     //==========================================================================
    
//     function void write_byte(bit [63:0] addr, bit [7:0] data);
//         memory[addr] = data;
//         num_writes++;
//         total_bytes_written++;
//     endfunction
    
//     function bit [7:0] read_byte(bit [63:0] addr);
//         num_reads++;
//         if (memory.exists(addr))
//             return memory[addr];
//         else
//             return 8'h00;  // Uninitialized memory returns 0
//     endfunction
    
//     //==========================================================================
//     // Word Operations (32-bit, Little-Endian)
//     //==========================================================================
    
//     function void write_word(bit [63:0] addr, bit [31:0] data);
//         write_byte(addr + 0, data[7:0]);
//         write_byte(addr + 1, data[15:8]);
//         write_byte(addr + 2, data[23:16]);
//         write_byte(addr + 3, data[31:24]);
//     endfunction
    
//     function bit [31:0] read_word(bit [63:0] addr);
//         bit [31:0] data;
//         data[7:0]   = read_byte(addr + 0);
//         data[15:8]  = read_byte(addr + 1);
//         data[23:16] = read_byte(addr + 2);
//         data[31:24] = read_byte(addr + 3);
//         return data;
//     endfunction
    
//     //==========================================================================
//     // Double-Word Operations (64-bit, Little-Endian)
//     //==========================================================================
    
//     function void write_dword(bit [63:0] addr, bit [63:0] data);
//         write_word(addr + 0, data[31:0]);
//         write_word(addr + 4, data[63:32]);
//     endfunction
    
//     function bit [63:0] read_dword(bit [63:0] addr);
//         bit [63:0] data;
//         data[31:0]  = read_word(addr + 0);
//         data[63:32] = read_word(addr + 4);
//         return data;
//     endfunction
    
//     //==========================================================================
//     // Load Program from Hex File
//     //==========================================================================
    
//     function int load_hex_file(string file_path, bit [63:0] base_addr);
//         int fd;
//         bit [31:0] addr_offset;
//         bit [31:0] data_word;
//         string line;
//         int bytes_loaded;
        
//         fd = $fopen(file_path, "r");
//         if (fd == 0) begin
//             $error("Failed to open file: %s", file_path);
//             return -1;
//         end
        
//         bytes_loaded = 0;
//         addr_offset = 0;
        
//         // Parse Verilog hex format
//         while (!$feof(fd)) begin
//             $fgets(line, fd);
            
//             // Skip comments and empty lines
//             if (line.len() == 0 || line[0] == "/" || line[0] == "#")
//                 continue;
            
//             // Parse address (@XXXXXXXX)
//             if (line[0] == "@") begin
//                 $sscanf(line.substr(1), "%h", addr_offset);
//                 continue;
//             end
            
//             // Parse data word
//             if ($sscanf(line, "%h", data_word) == 1) begin
//                 write_word(base_addr + addr_offset, data_word);
//                 addr_offset += 4;
//                 bytes_loaded += 4;
//             end
//         end
        
//         $fclose(fd);
        
//         $display("[MEM_MODEL] Loaded %0d bytes from %s at 0x%016h",
//                  bytes_loaded, file_path, base_addr);
        
//         return bytes_loaded;
//     endfunction
    
//     //==========================================================================
//     // Load Binary File
//     //==========================================================================
    
//     function int load_binary_file(string file_path, bit [63:0] base_addr);
//         int fd;
//         bit [7:0] data_byte;
//         bit [63:0] addr;
//         int bytes_loaded;
        
//         fd = $fopen(file_path, "rb");
//         if (fd == 0) begin
//             $error("Failed to open file: %s", file_path);
//             return -1;
//         end
        
//         addr = base_addr;
//         bytes_loaded = 0;
        
//         while (!$feof(fd)) begin
//             if ($fread(data_byte, fd) == 1) begin
//                 write_byte(addr, data_byte);
//                 addr++;
//                 bytes_loaded++;
//             end
//         end
        
//         $fclose(fd);
        
//         $display("[MEM_MODEL] Loaded %0d bytes from %s at 0x%016h",
//                  bytes_loaded, file_path, base_addr);
        
//         return bytes_loaded;
//     endfunction
    
//     //==========================================================================
//     // Memory Region Operations
//     //==========================================================================
    
//     function void fill_region(bit [63:0] start_addr, int size_bytes, bit [7:0] pattern);
//         for (int i = 0; i < size_bytes; i++) begin
//             write_byte(start_addr + i, pattern);
//         end
//     endfunction
    
//     function void clear_region(bit [63:0] start_addr, int size_bytes);
//         fill_region(start_addr, size_bytes, 8'h00);
//     endfunction
    
//     //==========================================================================
//     // Dump Memory Region (for Debug)
//     //==========================================================================
    
//     function void dump_region(bit [63:0] start_addr, int num_words);
//         $display("Memory Dump @ 0x%016h:", start_addr);
//         $display("Address          | +0       +4       +8       +C");
//         $display("-----------------+------------------------------------");
        
//         for (int i = 0; i < num_words; i += 4) begin
//             bit [63:0] addr = start_addr + (i * 4);
//             $display("0x%016h | %08h %08h %08h %08h",
//                      addr,
//                      read_word(addr + 0),
//                      read_word(addr + 4),
//                      read_word(addr + 8),
//                      read_word(addr + 12));
//         end
//     endfunction
    
//     //==========================================================================
//     // Compare Regions (for Scoreboard)
//     //==========================================================================
    
//     function int compare_region(
//         mem_model other,
//         bit [63:0] start_addr,
//         int num_bytes,
//         output int mismatches[$]
//     );
//         int num_errors = 0;
        
//         for (int i = 0; i < num_bytes; i++) begin
//             bit [63:0] addr = start_addr + i;
//             bit [7:0] this_data = read_byte(addr);
//             bit [7:0] other_data = other.read_byte(addr);
            
//             if (this_data != other_data) begin
//                 mismatches.push_back(i);
//                 num_errors++;
//             end
//         end
        
//         return num_errors;
//     endfunction
    
//     //==========================================================================
//     // Statistics
//     //==========================================================================
    
//     function void print_statistics();
//         $display("================================================================================");
//         $display("  Memory Model Statistics");
//         $display("================================================================================");
//         $display("  Total Reads:       %0d", num_reads);
//         $display("  Total Writes:      %0d", num_writes);
//         $display("  Bytes Written:     %0d", total_bytes_written);
//         $display("  Allocated Entries: %0d", memory.size());
//         $display("================================================================================");
//     endfunction
    
//     //==========================================================================
//     // Reset
//     //==========================================================================
    
//     function void reset();
//         memory.delete();
//         num_reads = 0;
//         num_writes = 0;
//         total_bytes_written = 0;
//     endfunction
    
// endclass : mem_model

// `endif // MEM_MODEL_SV
