// ============================================================================
// File: env/mem_model.sv
// Description: Shared sparse memory model for Vortex UVM testbench
// Author: Vortex UVM Team
// License: Apache-2.0
// ============================================================================

`ifndef MEM_MODEL_SV
`define MEM_MODEL_SV

package mem_model_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class mem_model extends uvm_object;
    
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
    // Load from Verilog hex file
    // --------------------------------------------------------------------------
    function int load_hex_file(string file_path, bit [63:0] base_addr = 64'h0);
      int fd;
      string line;
      bit [63:0] addr_off = 64'h0;
      int bytes_loaded = 0;

      fd = $fopen(file_path, "r");
      if (fd == 0) begin
        $error("[MEM_MODEL] Failed to open file: %s", file_path);
        return -1;
      end

      while (!$feof(fd)) begin
        int line_len;
        void'($fgets(line, fd));
        line_len = line.len();
        if (line_len == 0) continue;

        while (line_len > 0 &&
               (line[line_len-1] == "\n" || line[line_len-1] == "\r")) begin
          line = line.substr(0, line_len-2);
          line_len = line.len();
        end
        if (line_len == 0) continue;

        if ((line_len >= 2 && line[0] == "/" && line[1] == "/") ||
            (line[0] == "#"))
          continue;

        if (line[0] == "@") begin
          void'($sscanf(line, "@%h", addr_off));
          continue;
        end

        begin
          int ci;
          int tok_start;
          bit format_detected;
          bit is_byte_fmt;

          format_detected = 0;
          is_byte_fmt     = 1;
          tok_start       = 0;
          ci              = 0;

          while (ci <= line_len) begin
            bit is_sep;
            int tok_len;
            string tok;

            is_sep = (ci == line_len) ||
                     (line[ci] == " ") || (line[ci] == "\t");

            if (!is_sep) begin ci++; continue; end

            tok_len = ci - tok_start;
            ci++;

            if (tok_len == 0) begin tok_start = ci; continue; end

            tok = line.substr(tok_start, tok_start + tok_len - 1);
            tok_start = ci;

            if (!format_detected) begin
              is_byte_fmt     = (tok_len <= 2);
              format_detected = 1;
            end

            if (is_byte_fmt) begin
              bit [7:0] bval;
              void'($sscanf(tok, "%h", bval));
              write_byte(base_addr + addr_off, bval);
              addr_off     += 1;
              bytes_loaded += 1;
            end else begin
              bit [31:0] wval;
              void'($sscanf(tok, "%h", wval));
              write_word(base_addr + addr_off, wval);
              addr_off     += 4;
              bytes_loaded += 4;
            end
          end
        end
      end

      $fclose(fd);
      $display("[MEM_MODEL] Loaded %0d bytes from %s at base=0x%016h",
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

    // --------------------------------------------------------------------------
    // 512-bit cache-line operations
    // --------------------------------------------------------------------------
    function void write_line(bit [63:0] base_addr, bit [511:0] data);
      for (int i = 0; i < 64; i++)
        write_byte(base_addr + i, data[i*8 +: 8]);
    endfunction

    function bit [511:0] read_line(bit [63:0] base_addr);
      bit [511:0] data;
      for (int i = 0; i < 64; i++)
        data[i*8 +: 8] = read_byte(base_addr + i);
      return data;
    endfunction

  endclass : mem_model

endpackage : mem_model_pkg

`endif // MEM_MODEL_SV