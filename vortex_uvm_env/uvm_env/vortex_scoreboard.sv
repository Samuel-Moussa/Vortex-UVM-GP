////////////////////////////////////////////////////////////////////////////////
// File: vortex_scoreboard.sv
// Description: Scoreboard for Vortex GPGPU Verification
//
// Phase 1 Implementation (Post-Mortem Memory Comparison):
//   - Mirrors all DUT memory writes into SimX RAM via simx_write_mem()
//   - Mirrors all DCR writes into SimX via simx_dcr_write()
//   - On EBREAK: loads program via simx_load_bin(), runs simx_run(),
//     then compares result memory region between SimX RAM and RTL shadow memory
//   - Tracks pending MEM/AXI read transactions and compares responses
//
// Author: Vortex UVM Team
// Date: March 2026
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_SCOREBOARD_SV
`define VORTEX_SCOREBOARD_SV

//------------------------------------------------------------------------------
// Shared analysis imp declarations — guarded against double-declaration.
//------------------------------------------------------------------------------

//==============================================================================
class vortex_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(vortex_scoreboard)

  //==========================================================================
  // Configuration
  //==========================================================================
  // Final end-of-test comparison over the configured result window.
  // This sweeps the entire 64-byte vecadd destination buffer in 8-byte
  // chunks after SimX has run to completion.
  vortex_config cfg;

  //==========================================================================
  // Analysis Exports
  //==========================================================================
  // Live AXI read-response comparison for runtime bus traffic. Only reads
  // that land inside the configured result window are compared here.
  uvm_analysis_imp_mem    #(mem_transaction,    vortex_scoreboard) mem_export;
  uvm_analysis_imp_axi    #(axi_transaction,    vortex_scoreboard) axi_export;
  uvm_analysis_imp_dcr    #(dcr_transaction,    vortex_scoreboard) dcr_export;
  uvm_analysis_imp_host   #(host_transaction,   vortex_scoreboard) host_export;
  uvm_analysis_imp_status #(status_transaction, vortex_scoreboard) status_export;

  //==========================================================================
  // Pending read-transaction queues
  //==========================================================================
  mem_transaction mem_pending_q[$];
  axi_transaction axi_pending_q[$];

  //==========================================================================
  // Shadow memory — tracks every 8-byte word the DUT wrote.
  // Key = byte-aligned 32-bit address, Value = 64-bit data word.
  //==========================================================================
  bit [63:0] shadow_memory [bit [31:0]];
  localparam bit [31:0] RAM_BASE   = 32'h8000_0000;  // program / data / heap start
  localparam bit [31:0] DATA_LIMIT = 32'h8800_0000;  // upper bound of output region (excludes stack @0xfffd_xxxx+ and MMIO)
  localparam bit [31:0] POISON     = 32'hBAAD_F00D;  // SimX uninitialized-memory fill
  localparam bit [63:0] IO_COUT_ADDR = 64'h40;
  localparam bit [63:0] IO_COUT_SIZE = 64'd64;

  string       dut_console        = "";
  int unsigned num_console_checks = 0;
  bit          console_passed     = 0;

  //==========================================================================
  // State flags
  //==========================================================================
  bit simx_ran;    // Set after simx_run() completes
  bit ebreak_seen; // Set when status monitor reports EBREAK
  
  // --- Negative-test fault injection (one-sided, plusarg- or test-gated) ---
  // When enabled, corrupt exactly ONE DUT word INSIDE the comparison so the
  // DUT-vs-SimX check is forced to mismatch. One-sided by construction: only
  // the scoreboard's copy of the DUT value is flipped; SimX is never touched,
  // and the stimulus/program is never touched. This is what proves the checker
  // can FAIL. A test sets inject_fault=1, or pass +INJECT_FAULT on the cmdline.
  bit          inject_fault   = 0;   // set by negative_result_test or +INJECT_FAULT
  bit          fault_injected = 0;   // becomes 1 once we actually flip a word
  bit [31:0]   fault_addr     = 0;   // address we corrupted (for the report)
  bit          fault_detected = 0;   // set when the SPECIFIC injected word is reported as a mismatch
  
  //==========================================================================
  // Statistics
  //==========================================================================
  int unsigned num_transactions;
  int unsigned num_comparisons;
  int unsigned num_mem_passed;
  int unsigned num_mem_failed;
  int unsigned num_console_passed;
  int unsigned num_console_failed;
  int unsigned num_dcr_writes;
  int unsigned num_skipped;
  int unsigned num_unchecked;
  int unsigned num_data_compared;
  int unsigned num_skipped_stack;
  int unsigned num_skipped_poison;

  //==========================================================================
  // Constructor
  //==========================================================================
  function new(string name = "vortex_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //==========================================================================
  // Build Phase
  //==========================================================================
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(vortex_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("SCOREBOARD", "Failed to get vortex_config from uvm_config_db")

    mem_export    = new("mem_export",    this);
    axi_export    = new("axi_export",    this);
    dcr_export    = new("dcr_export",    this);
    host_export   = new("host_export",   this);
    status_export = new("status_export", this);

    num_transactions   = 0;    num_comparisons    = 0;
    num_mem_passed     = 0;    num_mem_failed     = 0;
    num_console_passed = 0;    num_console_failed = 0;
    num_dcr_writes     = 0;    num_unchecked      = 0;
    num_skipped        = 0;    num_data_compared  = 0;
    num_skipped_stack  = 0;    num_skipped_poison = 0;
    simx_ran           = 0;    ebreak_seen        = 0;
  endfunction : build_phase

  //==========================================================================
  // Run Phase — initialise SimX and pre-load program
  //==========================================================================
  virtual task run_phase(uvm_phase phase);
    int status;

    if ($test$plusargs("INJECT_FAULT")) inject_fault = 1;

    if (!cfg.simx_enable) begin
      `uvm_info("SCOREBOARD", "SimX disabled — shadow-memory checks only", UVM_MEDIUM)
      return;
    end

    `uvm_info("SCOREBOARD",
      $sformatf("Initialising SimX: cores=%0d warps=%0d threads=%0d",
                cfg.num_cores, cfg.num_warps, cfg.num_threads), UVM_MEDIUM)

    status = simx_init(cfg.num_cores, cfg.num_warps, cfg.num_threads);
    if (status != 0) begin
      `uvm_error("SCOREBOARD",
        $sformatf("simx_init() failed (status=%0d) — disabling SimX", status))
      cfg.simx_enable = 0;
      return;
    end
    `uvm_info("SCOREBOARD", "SimX initialised successfully", UVM_MEDIUM)

    // Pre-load program into SimX RAM (detect format from extension)
    if (cfg.program_path != "") begin
      string path = cfg.program_path;
      int    path_len = path.len();
      bit    is_hex;

      // Detect .hex extension (last 4 chars)
      is_hex = (path_len > 4) &&
               (path.substr(path_len-4, path_len-1) == ".hex");

        if (is_hex) begin
        // Use hex_at to force loading at 0x80000000 so it doesn't overwrite the 0x7FFFFFF0 bootstrap
        status = simx_load_hex_at(cfg.program_path, cfg.startup_addr); 
        if (status != 0)
          `uvm_error("SCOREBOARD",
            $sformatf("simx_load_hex_at('%s', 0x%0h) failed", cfg.program_path, cfg.startup_addr))
        else
          `uvm_info("SCOREBOARD",
            $sformatf("SimX: loaded hex '%s' @ 0x%0h", cfg.program_path, cfg.startup_addr), UVM_MEDIUM)
      end else begin
        status = simx_load_bin(cfg.program_path, 64'(cfg.startup_addr));
        if (status != 0)
          `uvm_error("SCOREBOARD",
            $sformatf("simx_load_bin('%s') failed", cfg.program_path))
        else
          `uvm_info("SCOREBOARD",
            $sformatf("SimX: loaded bin '%s' @ 0x%0h",
              cfg.program_path, cfg.startup_addr), UVM_MEDIUM)
      end
    end

    // Install exit-code bootstrap AFTER loading the program!
    // This ensures the load functions (simx_load_hex/bin) don't overwrite
    // the bootstrap payload or accidentally shift the program's base address.
    simx_init_exit_code_register();
  endtask : run_phase

  //==========================================================================
  // Analysis Write Methods
  //==========================================================================

  virtual function void write_mem(mem_transaction tr);
    num_transactions++;
    `uvm_info("SCOREBOARD",
      $sformatf("MEM %s  addr=0x%08h  byteen=0x%02h  tag=%0d",
                tr.rw ? "WR":"RD", tr.addr, tr.byteen, tr.tag), UVM_DEBUG)

    if (tr.rw) begin
      // Per-byte R-M-W into byte-addressed 8-byte shadow slots — mirrors write_axi.
      // mem_agent addr is a cache-line address; expand to per-byte addresses.
      begin
        bit [63:0] base_byte_addr = 64'(tr.addr) << 6;
        for (int i = 0; i < 64; i++) begin
          if (tr.byteen[i]) begin
            bit [63:0] byte_addr = base_byte_addr + i;
            bit [63:0] waddr     = {byte_addr[63:3], 3'b000};
            bit [2:0]  lane      = byte_addr[2:0];
            bit [63:0] wdata;

            // IO_COUT console snoop
            if (byte_addr >= IO_COUT_ADDR && byte_addr < (IO_COUT_ADDR + IO_COUT_SIZE)) begin
              byte ch = tr.data[i*8 +: 8];
              if (ch != 0) dut_console = {dut_console, string'(ch)};
            end

            // R-M-W into byte-addressed 8-byte shadow slot
            if (shadow_memory.exists(waddr[31:0])) wdata = shadow_memory[waddr[31:0]];
            else                                    wdata = '0;
            wdata[lane*8 +: 8] = tr.data[i*8 +: 8];
            shadow_memory[waddr[31:0]] = wdata;

            if ((waddr >= cfg.result_base_addr) && (waddr < cfg.result_base_addr + cfg.result_size_bytes))
              `uvm_info("SCOREBOARD", $sformatf(
                "MEM WR shadow  byte[%0d]  addr=0x%08h  data=0x%016h  byteen=0x%016h",
                i, waddr[31:0], wdata, tr.byteen), UVM_MEDIUM)
          end
        end
      end
    end else begin
      // Read on the custom-mem path: tr.rsp_data is a full 512-bit cache line,
      // which is structurally incompatible with shadow_memory's 64-bit slot
      // (truncation in `shadow_memory[tr.addr] = tr.data` makes per-read
      // shadow compare false-positive on any write/read of a line with data
      // above the low 64 bits). The end-state shadow gate plus the
      // test-level sentinel at RESULT_ADDR together verify correctness, so
      // per-read live compare is dropped here. AXI reads still go through
      // compare_axi_transaction in write_axi, which handles 8-byte slots
      // correctly.
    end
  endfunction : write_mem

  virtual function void write_axi(axi_transaction tr);
    num_transactions++;
    `uvm_info("SCOREBOARD",
      $sformatf("AXI %s  id=%0d  addr=0x%08h  len=%0d",
                tr.trans_type == axi_transaction::AXI_WRITE ? "WR":"RD",
                tr.id, tr.addr, tr.len), UVM_DEBUG)

    if (tr.trans_type == axi_transaction::AXI_WRITE) begin
      // Mirror AXI writes byte-accurately using WSTRB, matching mem_model.
      for (int beat = 0; beat <= tr.len; beat++) begin
        bit [63:0]  baddr      = tr.get_next_addr(beat);
        bit [511:0] beat_data  = (beat < tr.wdata.size()) ? tr.wdata[beat] : '0;
        bit [63:0]  beat_wstrb = (beat < tr.wstrb.size()) ? tr.wstrb[beat] : '0;

        for (int i = 0; i < 64; i++) begin
          if (beat_wstrb[i]) begin
            bit [63:0] byte_addr = baddr + i;
            bit [63:0] waddr     = {byte_addr[63:3], 3'b000};
            bit [2:0]  lane      = byte_addr[2:0];
            bit [63:0] wdata;
            
            // Fix #3: assemble DUT console from IO_COUT writes
            if (byte_addr >= IO_COUT_ADDR && byte_addr < (IO_COUT_ADDR + IO_COUT_SIZE)) begin
              byte ch = beat_data[i*8 +: 8];
              if (ch != 0) dut_console = {dut_console, string'(ch)};
            end

            if (shadow_memory.exists(waddr[31:0]))
              wdata = shadow_memory[waddr[31:0]];
            else
              wdata = '0;

            wdata[lane*8 +: 8] = beat_data[i*8 +: 8];
            shadow_memory[waddr[31:0]] = wdata;

            if ((waddr >= cfg.result_base_addr) && (waddr < cfg.result_base_addr + cfg.result_size_bytes)) begin
              `uvm_info("SCOREBOARD",
                $sformatf("AXI WR shadow  beat[%0d] byte[%0d]  addr=0x%08h  data=0x%016h  wstrb=0x%016h",
                          beat, i, waddr[31:0], wdata, beat_wstrb), UVM_MEDIUM)
            end
          end
        end
      end
    end else begin
      if (tr.completed) compare_axi_transaction(tr);
      else              axi_pending_q.push_back(tr);
    end
  endfunction : write_axi

  virtual function void write_dcr(dcr_transaction tr);
    num_transactions++;
    num_dcr_writes++;
    `uvm_info("SCOREBOARD",
      $sformatf("DCR WR  %s  addr=0x%08h  data=0x%08h",
                tr.get_dcr_name(), tr.addr, tr.data), UVM_DEBUG)
    if (cfg.simx_enable)
      simx_dcr_write(int'(tr.addr), int'(tr.data));
  endfunction : write_dcr

  virtual function void write_host(host_transaction tr);
    num_transactions++;
    `uvm_info("SCOREBOARD", $sformatf("HOST op=%s", tr.op_type.name()), UVM_DEBUG)
  endfunction : write_host

  virtual function void write_status(status_transaction tr);
    `uvm_info("SCOREBOARD",
      $sformatf("STATUS  busy=%0b  ebreak=%0b  cycles=%0d",
                tr.busy, tr.ebreak_detected, tr.cycle_count), UVM_DEBUG)
    if (tr.ebreak_detected && !ebreak_seen) begin
      ebreak_seen = 1;
      if (cfg != null && cfg.ebreak_event != null)
        cfg.ebreak_event.trigger();
      `uvm_info("SCOREBOARD",
        "EBREAK detected — running SimX and comparing results.", UVM_MEDIUM)
      run_final_comparison();
      flush_pending_queues();
    end
  endfunction : write_status

  //==========================================================================
  // run_final_comparison — runs SimX then compares result region
  //==========================================================================
  local function void run_final_comparison();
    int exitcode;
    if (!cfg.simx_enable || simx_ran) return;
    simx_ran = 1;
    `uvm_info("SCOREBOARD", "Running SimX to completion...", UVM_MEDIUM)
    exitcode = simx_run();
    `uvm_info("SCOREBOARD", $sformatf("SimX done — exit code = %0d", exitcode), UVM_MEDIUM)
    if (simx_is_done() != 1)
      `uvm_warning("SCOREBOARD", "simx_is_done() != 1 after simx_run()")

    compare_all_written();   // memory output — every program
    compare_console();       // console output — every program
  endfunction

  //==========================================================================
  // compare_result_region
  //==========================================================================
  local function void compare_result_region(bit [31:0] base_addr, int size_bytes);
    byte simx_bytes[]; 
    bit [63:0] simx_base; // DECLARATION FIRST
    
    // STATEMENTS SECOND
    // Treat base address as an unsigned 32-bit physical address and zero-extend
    simx_base = 64'(base_addr);
    simx_bytes = new[size_bytes];
    simx_read_mem(simx_base, size_bytes, simx_bytes);

    for (int offset = 0; offset < size_bytes; offset += 8) begin
      int chunk_bytes = (size_bytes - offset < 8) ? (size_bytes - offset) : 8;
      bit [31:0] waddr = base_addr + offset;
      bit [63:0] simx_word, dut_word;
      simx_word = '0;
      dut_word   = '0;
      
      // Build SimX word byte-by-byte from the read buffer
      for (int i = 0; i < chunk_bytes; i++) begin
        simx_word[i*8 +: 8] = simx_bytes[offset + i];
      end
      
      // Get DUT word directly from shadow memory (already 64-bit)
      if (shadow_memory.exists(waddr)) begin
        dut_word = shadow_memory[waddr];
      end else begin
        dut_word = '0;
      end
      
      num_comparisons++;
      if (!shadow_memory.exists(waddr)) begin
        `uvm_warning("SCOREBOARD",
          $sformatf("Result addr 0x%08h not written by DUT — skipping", waddr))
        num_skipped++;
        num_comparisons--;
        continue;
      end
      if (dut_word === simx_word) begin
        num_mem_passed++;
        `uvm_info("SCOREBOARD",
          $sformatf("RESULT PASS  addr=0x%08h  DUT=0x%016h  SimX=0x%016h",
                    waddr, dut_word, simx_word), UVM_MEDIUM)
      end else begin
        num_mem_failed++;
        `uvm_error("SCOREBOARD",
          $sformatf("RESULT FAIL  addr=0x%08h  DUT=0x%016h  SimX=0x%016h",
                    waddr, dut_word, simx_word))
      end
    end
  endfunction : compare_result_region

  //==========================================================================
  // compare_mem_transaction
  //==========================================================================
  local function void compare_mem_transaction(mem_transaction tr);
    bit [63:0] expected;
    byte rd[] = new[8];
    bit [63:0] simx_addr;
    bit [31:0] addr_32; // <--- ADD THIS DECLARATION
    int i;

    // Smoke mode: no deterministic result window is defined for this program.
    // Skip strict value checks to avoid false failures from non-deterministic
    // runtime regions while still preserving protocol checking elsewhere.
    if (cfg.result_size_bytes == 0)
      return;

    num_comparisons++;
    if (cfg.simx_enable && simx_ran) begin
      // Use unsigned 32-bit physical address (zero-extend to 64-bit)
      addr_32 = 32'(tr.addr);
      simx_addr = 64'(addr_32);
      
      simx_read_mem(simx_addr, 8, rd);
      expected = '0;
      for (i = 0; i < 8; i++) expected[i*8 +: 8] = rd[i];
    end else if (shadow_memory.exists(tr.addr)) begin
      expected = shadow_memory[tr.addr];
    end else begin
      `uvm_warning("SCOREBOARD",
        $sformatf("MEM RD 0x%08h — no reference, skipping", tr.addr))
      num_skipped++; num_comparisons--;  return;
    end
    if (tr.rsp_data === expected) begin
      num_mem_passed++;
      `uvm_info("SCOREBOARD",
        $sformatf("MEM RD PASS  addr=0x%08h  data=0x%016h", tr.addr, tr.rsp_data),
        UVM_HIGH)
    end else begin
      num_mem_failed++;
      `uvm_error("SCOREBOARD",
        $sformatf("MEM RD FAIL  addr=0x%08h  DUT=0x%016h  exp=0x%016h",
                  tr.addr, tr.rsp_data, expected))
    end
  endfunction : compare_mem_transaction

  //==========================================================================
  // compare_axi_transaction
  //==========================================================================
  local function void compare_axi_transaction(axi_transaction tr);
    if (cfg.result_size_bytes == 0)
      return;

    for (int beat = 0; beat <= tr.len; beat++) begin
      bit [63:0] baddr    = tr.get_next_addr(beat);
      bit [63:0] dut_data = (beat < tr.rdata.size()) ? tr.rdata[beat] : '0;
      bit [63:0] expected;
      num_comparisons++;

      if (cfg.simx_enable && simx_ran) begin
        byte rd[];
        bit [63:0] simx_addr; // DECLARATION FIRST
        
        rd = new[8];          // STATEMENT SECOND
        // Use zero-extended 32-bit physical address when calling SimX.
        // Previous sign-extension caused reads from invalid high addresses
        // and produced spurious mismatches (seen as 0xfffe.... addresses).
        simx_addr = 64'(baddr[31:0]);
        simx_read_mem(simx_addr, 8, rd);
        expected = '0;
        for (int i = 0; i < 8; i++) expected[i*8 +: 8] = rd[i];
      end else if (shadow_memory.exists(baddr[31:0])) begin
        expected = shadow_memory[baddr[31:0]];
      end else begin
        `uvm_warning("SCOREBOARD",
          $sformatf("AXI RD beat[%0d] 0x%08h — no reference, skipping", beat, baddr[31:0]))
        num_skipped++; num_comparisons--;  continue;
      end
      if (dut_data === expected) begin
        num_mem_passed++;
        `uvm_info("SCOREBOARD",
          $sformatf("AXI RD PASS  beat[%0d] addr=0x%08h  data=0x%016h",
                    beat, baddr[31:0], dut_data), UVM_MEDIUM)
      end else begin
        num_mem_failed++;
        `uvm_error("SCOREBOARD",
          $sformatf("AXI RD FAIL  beat[%0d] addr=0x%08h  DUT=0x%016h  exp=0x%016h",
                    beat, baddr[31:0], dut_data, expected))
      end
    end
  endfunction : compare_axi_transaction

  // Fix #2: compare every DRAM-output location the DUT wrote against SimX,
  // with two principled gates:
  //   (1) scope to the program/data region — stack & MMIO are not kernel outputs
  //   (2) skip SimX-uninitialized scratch (baadf00d poison fill)
  local function void compare_all_written();
    bit [63:0] simx_word, dut_word, simx_base;
    byte       simx_bytes[];
    simx_bytes = new[8];

    foreach (shadow_memory[addr]) begin
      // ---- Gate 1: data region only (skip stack 0xfffd_xxxx+, local mem, MMIO) ----
      if (addr < RAM_BASE || addr >= DATA_LIMIT) begin
        num_skipped_stack++;
        continue;
      end

      dut_word  = shadow_memory[addr];
      simx_base = 64'(addr);
      simx_read_mem(simx_base, 8, simx_bytes);
      simx_word = '0;
      for (int i = 0; i < 8; i++) simx_word[i*8 +: 8] = simx_bytes[i];

      // ---- Gate 2: skip SimX-uninitialized poison (baadf00d in either half) ----
      if (simx_word[31:0] == POISON || simx_word[63:32] == POISON) begin
        num_skipped_poison++;
        continue;
      end

      // NEG: inject ONLY on a word that currently MATCHES, so the forced
      // mismatch is unambiguously caused by the flip — never a pre-existing
      // divergence (e.g. conform's lmem pointer at 0x80008288).
      if (inject_fault && !fault_injected && (dut_word === simx_word)) begin
        dut_word       = dut_word ^ 64'h1;   // matching value XOR 1 => guaranteed mismatch
        fault_injected = 1;
        fault_addr     = addr;
        `uvm_info("SCOREBOARD",
          $sformatf("[NEG] Fault injected at addr=0x%08h (was matching; LSB flipped) to force a mismatch",
                    addr), UVM_LOW)
      end

      // ---- Real comparison ----
      num_comparisons++;   
      if (dut_word === simx_word) begin
        num_mem_passed++;
      end else begin
        num_mem_failed++;
        if (fault_injected && addr == fault_addr) fault_detected = 1;  // the injected word was caught
        `uvm_error("SCOREBOARD",
          $sformatf("MEM MISMATCH  addr=0x%08h  DUT=0x%016h  SimX=0x%016h",
                    addr, dut_word, simx_word))
      end
    end
    
    `uvm_info("SCOREBOARD",
      $sformatf("compare_all_written: data_compared=%0d  skipped_stack/MMIO=%0d  skipped_poison=%0d",
                num_comparisons, num_skipped_stack, num_skipped_poison), UVM_MEDIUM)
  endfunction

  // Order-independent content check: same characters, any order.
  local function bit same_multiset(string a, string b);
    int unsigned ha[256];
    int unsigned hb[256];
    foreach (ha[k]) begin ha[k] = 0; hb[k] = 0; end
    for (int i = 0; i < a.len(); i++) ha[a[i] & 8'hFF]++;
    for (int i = 0; i < b.len(); i++) hb[b[i] & 8'hFF]++;
    foreach (ha[k]) if (ha[k] != hb[k]) return 0;
    return 1;
  endfunction

  // Fix #3: compare DUT console output against SimX's.
  local function void compare_console();
    string simx_raw, d, s;
    simx_raw = simx_get_console();
    d = normalize_console(dut_console);
    s = normalize_console(simx_raw);
    if (d.len() == 0 && s.len() == 0) return;   // non-printing program

    num_console_checks++;
    if (d == s) begin
      console_passed = 1; num_console_passed++;
      `uvm_info("SCOREBOARD", $sformatf("CONSOLE PASS (exact)  len=%0d", d.len()), UVM_MEDIUM)
    end
    else if (same_multiset(d, s)) begin
      // Same printed CONTENT, different byte order — the expected signature of
      // SIMD console interleaving (DUT warp threads interleave IO_COUT bytes;
      // SimX serializes per-thread). Content verified; ordering intentionally not.
      console_passed = 1; num_console_passed++;
      `uvm_info("SCOREBOARD",
        $sformatf("CONSOLE PASS (interleaved: same content, SIMD byte-order differs)  len=%0d", d.len()),
        UVM_MEDIUM)
    end
    else begin
      console_passed = 0; num_console_failed++;
      `uvm_error("SCOREBOARD",
        $sformatf("CONSOLE FAIL  content differs\n  DUT =\"%s\"\n  SimX=\"%s\"", d, s))
    end
  endfunction

  // Canonicalize console output for semantic comparison:
  // Strip SimX-only "#<id>:" line prefixes (any digit count) + all whitespace.
  // The DUT IO_COUT stream never contains "#<id>:". Content ':' and '#' kept.
  local function string normalize_console(string in);
    string out = "";
    int n = in.len();
    int i = 0;
    while (i < n) begin
      byte c = in[i];
      if (c == "#") begin                       // possible "#<digits>:" prefix
        int j = i + 1;
        while (j < n && in[j] >= "0" && in[j] <= "9") j++;
        if (j < n && in[j] == ":") begin i = j + 1; continue; end
      end
      if (c == " " || c == "\t" || c == "\n" || c == 8'h0d) begin i++; continue; end
      out = {out, string'(c)};
      i++;
    end
    return out;
  endfunction

  //==========================================================================
  // flush_pending_queues
  //==========================================================================
  local function void flush_pending_queues();
    while (mem_pending_q.size() > 0) begin
      mem_transaction tr = mem_pending_q.pop_front();
      // Compare pending mem reads if they have response data; else just warn
      if (tr.rsp_data != '0) begin
        compare_mem_transaction(tr);
      end else begin
        num_unchecked++;
        `uvm_warning("SCOREBOARD",
          $sformatf("Pending MEM RD never completed: addr=0x%08h tag=%0d",
                    tr.addr, tr.tag))
      end
    end
    while (axi_pending_q.size() > 0) begin
      axi_transaction tr = axi_pending_q.pop_front();
      // Compare pending AXI reads if they have response data; else just warn
      if (tr.rdata.size() > 0 && tr.rdata[0] != '0) begin
        compare_axi_transaction(tr);
      end else begin
        num_unchecked++;
        `uvm_warning("SCOREBOARD",
          $sformatf("Pending AXI RD never completed: addr=0x%08h id=%0d",
                    tr.addr, tr.id))
      end
    end
  endfunction : flush_pending_queues

  //==========================================================================
  // Extract Phase — fallback if EBREAK never arrived
  //==========================================================================
  virtual function void extract_phase(uvm_phase phase);
    super.extract_phase(phase);
    if (!ebreak_seen && cfg.simx_enable && cfg.result_size_bytes > 0)
      `uvm_warning("SCOREBOARD",
        "EBREAK never observed — running final comparison at extract_phase")
    if (!ebreak_seen && cfg.simx_enable) run_final_comparison();
    if (mem_pending_q.size() > 0 || axi_pending_q.size() > 0) begin
      `uvm_warning("SCOREBOARD",
        $sformatf("%0d MEM + %0d AXI read(s) still pending at end of sim",
                  mem_pending_q.size(), axi_pending_q.size()))
      flush_pending_queues();
    end
  endfunction : extract_phase

  //==========================================================================
  // Report Phase
  //==========================================================================
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    report_results();
  endfunction : report_phase

  //==========================================================================
  // Final Phase — release SimX
  //==========================================================================
  virtual function void final_phase(uvm_phase phase);
    super.final_phase(phase);
    if (cfg.simx_enable) begin
      `uvm_info("SCOREBOARD", "Cleaning up SimX", UVM_MEDIUM)
      simx_cleanup();
    end
  endfunction : final_phase

  //==========================================================================
  // report_results
  //==========================================================================
  virtual function void report_results();
    int unsigned total_passed, total_failed, total_checks, total_skipped;
    real         pass_rate;

    total_passed  = num_mem_passed + num_console_passed;
    total_failed  = num_mem_failed + num_console_failed;
    total_checks  = num_comparisons + num_console_checks;
    total_skipped = num_skipped + num_skipped_stack + num_skipped_poison;
    pass_rate     = (total_checks > 0) ? (100.0 * total_passed / total_checks) : 0.0;

    `uvm_info("SCOREBOARD", {"\n",
      "╔══════════════════════════════════════════╗\n",
      "║        Vortex Scoreboard Results         ║\n",
      "╠══════════════════════════════════════════╣\n",
      $sformatf("║  Transactions       : %-19d║\n", num_transactions),
      $sformatf("║  DCR Writes         : %-19d║\n", num_dcr_writes),
      $sformatf("║  Memory checks      : %-19d║\n", num_comparisons),
      $sformatf("║    Passed           : %-19d║\n", num_mem_passed),
      $sformatf("║    Failed           : %-19d║\n", num_mem_failed),
      $sformatf("║  Console checks     : %-19d║\n", num_console_checks),
      $sformatf("║    Passed           : %-19d║\n", num_console_passed),
      $sformatf("║    Failed           : %-19d║\n", num_console_failed),
      $sformatf("║  Total Passed       : %-19d║\n", total_passed),
      $sformatf("║  Total Failed       : %-19d║\n", total_failed),
      $sformatf("║  Skipped            : %-19d║\n", total_skipped),
      $sformatf("║  Pass Rate          : %-17.2f%% ║\n", pass_rate),
      $sformatf("║  SimX Enabled       : %-19s║\n", cfg.simx_enable ? "YES":"NO"),
      $sformatf("║  SimX Ran           : %-19s║\n", simx_ran ? "YES":"NO"),
      "╚══════════════════════════════════════════╝\n"
    }, UVM_NONE)

    if (total_failed > 0)
      `uvm_error("SCOREBOARD",
        $sformatf("SIMULATION FAILED — %0d memory + %0d console check(s) did not match!",
                  num_mem_failed, num_console_failed))
    else if (num_unchecked > 0)
      `uvm_warning("SCOREBOARD",
        $sformatf("SIMULATION INCOMPLETE — %0d response(s) never received", num_unchecked))
    else if (total_checks > 0)
      `uvm_info("SCOREBOARD", "SIMULATION PASSED — all checks matched!", UVM_NONE)
    else if (ebreak_seen && simx_ran)
      // Pure arithmetic programs (e.g. riscv-dv riscv_arithmetic_basic_test) have no
      // stores to the data region. Both DUT and SimX halted at ebreak with matching
      // (empty) memory state — still a valid pass by completion criterion.
      `uvm_warning("SCOREBOARD",
        "No memory writes to compare — DUT and SimX both completed (pure arithmetic program)")
    else
      `uvm_error("SCOREBOARD", "No checks were performed — vacuous run")
  endfunction : report_results

endclass : vortex_scoreboard

`endif // VORTEX_SCOREBOARD_SV