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
// ============================================================================
// HOW TO ADD A NEW DPI FUNCTION IN THE FUTURE
// ============================================================================
// Step 1 — Steven adds the C++ function to simx_dpi.cpp with extern "C".
//           Example:
//             extern "C" int simx_get_reg(int core, int warp, int thread, int reg_id) {...}
//
// Step 2 — Rebuild the shared library:
//             cd <simx_dpi_dir>
//             make build
//           This regenerates simx_model.so.
//
// Step 3 — Add the DPI import here at compilation-unit scope (in the block
//           labelled "DPI-C IMPORTS" below). The SV signature must exactly
//           match the C++ function prototype:
//             import "DPI-C" function int simx_get_reg(int core, int warp,
//                                                      int thread, int reg_id);
//
// Step 4 — Call it anywhere inside the class (run_phase, write_*, etc.).
//           Always guard with:  if (cfg.simx_enable) begin ... end
//
// Step 5 — Recompile only the UVM env (no need to recompile RTL):
//             vlog -sv -suppress 2167 +incdir+$UVM_HOME $UVM_HOME/uvm_pkg.sv
//             vlog -sv -f uvm_env.flist
//
// Step 6 — Run with the new .so:
//             vsim ... -sv_lib simx_model ...
//           (simx_model path is already in run_vortex_uvm_enhanced.sh)
//
// ============================================================================
// HOW TO REMOVE A DPI FUNCTION
// ============================================================================
// Step 1 — Delete or comment out the import line below.
// Step 2 — Remove every call site inside the class.
// Step 3 — Recompile UVM env (Step 5 above). The .so does not need rebuilding
//           unless you also changed the C++ side.
//
// ============================================================================
// CURRENT DPI FUNCTIONS (matched to simx_dpi.cpp latest version)
// ============================================================================
//   simx_init(int cores, int warps, int threads)      -> int
//   simx_cleanup()                                    -> void
//   simx_write_mem(longint addr, int size, byte[])    -> void
//   simx_read_mem(longint addr, int size, byte[])     -> void (inout)
//   simx_load_bin(string filepath, longint addr)      -> int
//   simx_load_hex(string filepath)                    -> int
//   simx_dcr_write(int addr, int value)               -> void
//   simx_run()                                        -> int
//   simx_step(int cycles)                             -> int
//   simx_is_done()                                    -> int
//   simx_get_exitcode()                               -> int
//   simx_init_exit_code_register()                    -> void
//
// Author: Vortex UVM Team
// Date: March 2026
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_SCOREBOARD_SV
`define VORTEX_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_env_pkg::*;
import vortex_config_pkg::*;
import mem_agent_pkg::*;
import axi_agent_pkg::*;
import dcr_agent_pkg::*;
import host_agent_pkg::*;
import status_agent_pkg::*;

// `uvm_analysis_imp_decl(_mem)
// `uvm_analysis_imp_decl(_axi)
// `uvm_analysis_imp_decl(_dcr)
// `uvm_analysis_imp_decl(_host)
// `uvm_analysis_imp_decl(_status)

//------------------------------------------------------------------------------
// Shared analysis imp declarations — guarded against double-declaration.
//------------------------------------------------------------------------------

//==============================================================================
class vortex_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(vortex_scoreboard)

  //==========================================================================
  // Configuration
  //==========================================================================
  vortex_config cfg;

  //==========================================================================
  // Analysis Exports
  //==========================================================================
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

  //==========================================================================
  // State flags
  //==========================================================================
  bit simx_ran;    // Set after simx_run() completes
  bit ebreak_seen; // Set when status monitor reports EBREAK

  //==========================================================================
  // Statistics
  //==========================================================================
  int unsigned num_transactions;
  int unsigned num_comparisons;
  int unsigned num_passed;
  int unsigned num_failed;
  int unsigned num_dcr_writes;
  int unsigned num_unchecked;

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

    num_transactions = 0;  num_comparisons = 0;
    num_passed       = 0;  num_failed      = 0;
    num_dcr_writes   = 0;  num_unchecked   = 0;
    simx_ran         = 0;  ebreak_seen     = 0;
  endfunction : build_phase

  //==========================================================================
  // Run Phase — initialise SimX and pre-load program
  //==========================================================================
  virtual task run_phase(uvm_phase phase);
    int status;

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

    // Install exit-code bootstrap so x3=0 is guaranteed before main program
    simx_init_exit_code_register();

    // Pre-load program into SimX RAM (mirrors what +PROGRAM does in the RTL TB)
    if (cfg.program_path != "") begin
      status = simx_load_bin(cfg.program_path, 64'(cfg.startup_addr));
      if (status != 0)
        `uvm_error("SCOREBOARD",
          $sformatf("simx_load_bin('%s') failed", cfg.program_path))
      else
        `uvm_info("SCOREBOARD",
          $sformatf("SimX: loaded '%s' @ 0x%0h", cfg.program_path, cfg.startup_addr),
          UVM_MEDIUM)
    end
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
      shadow_memory[tr.addr] = tr.data;
      if (cfg.simx_enable) begin
        byte unsigned wr[];  wr = new[8];
        for (int i = 0; i < 8; i++) wr[i] = tr.data[i*8 +: 8];
        simx_write_mem(64'(tr.addr), 8, wr);
      end
    end else begin
      if (tr.completed) compare_mem_transaction(tr);
      else              mem_pending_q.push_back(tr);
    end
  endfunction : write_mem

  virtual function void write_axi(axi_transaction tr);
    num_transactions++;
    `uvm_info("SCOREBOARD",
      $sformatf("AXI %s  id=%0d  addr=0x%08h  len=%0d",
                tr.trans_type == axi_transaction::AXI_WRITE ? "WR":"RD",
                tr.id, tr.addr, tr.len), UVM_DEBUG)

    if (tr.trans_type == axi_transaction::AXI_WRITE) begin
      for (int beat = 0; beat <= tr.len; beat++) begin
        bit [63:0] baddr = tr.get_next_addr(beat);
        bit [63:0] bdata = (beat < tr.wdata.size()) ? tr.wdata[beat] : '0;
        shadow_memory[baddr[31:0]] = bdata;
        if (cfg.simx_enable) begin
          byte unsigned wr[];  wr = new[8];
          for (int i = 0; i < 8; i++) wr[i] = bdata[i*8 +: 8];
          simx_write_mem(baddr, 8, wr);
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
    `uvm_info("SCOREBOARD",
      $sformatf("SimX done — exit code = %0d", exitcode), UVM_MEDIUM)

    if (exitcode != 0)
      `uvm_error("SCOREBOARD",
        $sformatf("SimX exit code=%0d (non-zero = program failed)", exitcode))

    if (simx_is_done() != 1)
      `uvm_warning("SCOREBOARD",
        "simx_is_done() != 1 after simx_run() — unexpected state")

    if (cfg.result_size_bytes > 0) begin
      `uvm_info("SCOREBOARD",
        $sformatf("Comparing result region: base=0x%08h  size=%0d bytes",
                  cfg.result_base_addr, cfg.result_size_bytes), UVM_MEDIUM)
      compare_result_region(cfg.result_base_addr, cfg.result_size_bytes);
    end else
      `uvm_info("SCOREBOARD",
        "result_size_bytes=0 — no result comparison performed", UVM_MEDIUM)
  endfunction : run_final_comparison

  //==========================================================================
  // compare_result_region
  //==========================================================================
  local function void compare_result_region(bit [31:0] base_addr, int size_bytes);
    byte unsigned simx_bytes[];
    simx_bytes = new[size_bytes];
    simx_read_mem(64'(base_addr), size_bytes, simx_bytes);

    for (int offset = 0; offset + 7 < size_bytes; offset += 8) begin
      bit [31:0] waddr = base_addr + offset;
      bit [63:0] simx_word, dut_word;
      for (int i = 0; i < 8; i++)
        simx_word[i*8 +: 8] = simx_bytes[offset + i];
      num_comparisons++;
      if (!shadow_memory.exists(waddr)) begin
        `uvm_warning("SCOREBOARD",
          $sformatf("Result addr 0x%08h not written by DUT — skipping", waddr))
        num_comparisons--;
        continue;
      end
      dut_word = shadow_memory[waddr];
      if (dut_word === simx_word) begin
        num_passed++;
        `uvm_info("SCOREBOARD",
          $sformatf("RESULT PASS  addr=0x%08h  DUT=0x%016h  SimX=0x%016h",
                    waddr, dut_word, simx_word), UVM_HIGH)
      end else begin
        num_failed++;
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
    num_comparisons++;
    if (cfg.simx_enable && simx_ran) begin
      byte unsigned rd[];  rd = new[8];
      simx_read_mem(64'(tr.addr), 8, rd);
      expected = '0;
      for (int i = 0; i < 8; i++) expected[i*8 +: 8] = rd[i];
    end else if (shadow_memory.exists(tr.addr)) begin
      expected = shadow_memory[tr.addr];
    end else begin
      `uvm_warning("SCOREBOARD",
        $sformatf("MEM RD 0x%08h — no reference, skipping", tr.addr))
      num_comparisons--;  return;
    end
    if (tr.rsp_data === expected) begin
      num_passed++;
      `uvm_info("SCOREBOARD",
        $sformatf("MEM RD PASS  addr=0x%08h  data=0x%016h", tr.addr, tr.rsp_data),
        UVM_HIGH)
    end else begin
      num_failed++;
      `uvm_error("SCOREBOARD",
        $sformatf("MEM RD FAIL  addr=0x%08h  DUT=0x%016h  exp=0x%016h",
                  tr.addr, tr.rsp_data, expected))
    end
  endfunction : compare_mem_transaction

  //==========================================================================
  // compare_axi_transaction
  //==========================================================================
  local function void compare_axi_transaction(axi_transaction tr);
    for (int beat = 0; beat <= tr.len; beat++) begin
      bit [63:0] baddr    = tr.get_next_addr(beat);
      bit [63:0] dut_data = (beat < tr.rdata.size()) ? tr.rdata[beat] : '0;
      bit [63:0] expected;
      num_comparisons++;
      if (cfg.simx_enable && simx_ran) begin
        byte unsigned rd[];  rd = new[8];
        simx_read_mem(baddr, 8, rd);
        expected = '0;
        for (int i = 0; i < 8; i++) expected[i*8 +: 8] = rd[i];
      end else if (shadow_memory.exists(baddr[31:0])) begin
        expected = shadow_memory[baddr[31:0]];
      end else begin
        `uvm_warning("SCOREBOARD",
          $sformatf("AXI RD beat[%0d] 0x%08h — no reference, skipping", beat, baddr))
        num_comparisons--;  continue;
      end
      if (dut_data === expected) begin
        num_passed++;
        `uvm_info("SCOREBOARD",
          $sformatf("AXI RD PASS  beat[%0d] addr=0x%08h  data=0x%016h",
                    beat, baddr, dut_data), UVM_HIGH)
      end else begin
        num_failed++;
        `uvm_error("SCOREBOARD",
          $sformatf("AXI RD FAIL  beat[%0d] addr=0x%08h  DUT=0x%016h  exp=0x%016h",
                    beat, baddr, dut_data, expected))
      end
    end
  endfunction : compare_axi_transaction

  //==========================================================================
  // flush_pending_queues
  //==========================================================================
  local function void flush_pending_queues();
    while (mem_pending_q.size() > 0) begin
      mem_transaction tr = mem_pending_q.pop_front();
      num_unchecked++;
      `uvm_warning("SCOREBOARD",
        $sformatf("Pending MEM RD never completed: addr=0x%08h tag=%0d",
                  tr.addr, tr.tag))
    end
    while (axi_pending_q.size() > 0) begin
      axi_transaction tr = axi_pending_q.pop_front();
      num_unchecked++;
      `uvm_warning("SCOREBOARD",
        $sformatf("Pending AXI RD never completed: addr=0x%08h id=%0d",
                  tr.addr, tr.id))
    end
  endfunction : flush_pending_queues

  //==========================================================================
  // Extract Phase — fallback if EBREAK never arrived
  //==========================================================================
  virtual function void extract_phase(uvm_phase phase);
    super.extract_phase(phase);
    if (!ebreak_seen && cfg.simx_enable)
      `uvm_warning("SCOREBOARD",
        "EBREAK never observed — running final comparison at extract_phase")
    if (!ebreak_seen) run_final_comparison();
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
    real pass_rate = (num_comparisons > 0)
                     ? (real'(num_passed) / real'(num_comparisons)) * 100.0
                     : 0.0;
    `uvm_info("SCOREBOARD", {"\n",
      "╔══════════════════════════════════════════╗\n",
      "║        Vortex Scoreboard Results         ║\n",
      "╠══════════════════════════════════════════╣\n",
      $sformatf("║  Total Transactions : %-19d║\n", num_transactions),
      $sformatf("║  DCR Writes         : %-19d║\n", num_dcr_writes),
      $sformatf("║  Comparisons        : %-19d║\n", num_comparisons),
      $sformatf("║  Passed             : %-19d║\n", num_passed),
      $sformatf("║  Failed             : %-19d║\n", num_failed),
      $sformatf("║  Unchecked (no rsp) : %-19d║\n", num_unchecked),
      $sformatf("║  Pass Rate          : %-17.2f%% ║\n", pass_rate),
      $sformatf("║  SimX Enabled       : %-19s║\n", cfg.simx_enable ? "YES":"NO"),
      $sformatf("║  SimX Ran           : %-19s║\n", simx_ran        ? "YES":"NO"),
      "╚══════════════════════════════════════════╝\n"
    }, UVM_NONE)

    if (num_failed > 0)
      `uvm_error("SCOREBOARD",
        $sformatf("SIMULATION FAILED — %0d comparison(s) did not match!", num_failed))
    else if (num_unchecked > 0)
      `uvm_warning("SCOREBOARD",
        $sformatf("SIMULATION INCOMPLETE — %0d response(s) never received", num_unchecked))
    else if (num_comparisons > 0)
      `uvm_info("SCOREBOARD", "SIMULATION PASSED — all comparisons matched!", UVM_NONE)
    else
      `uvm_warning("SCOREBOARD", "No data comparisons were performed.")
  endfunction : report_results

endclass : vortex_scoreboard

`endif // VORTEX_SCOREBOARD_SV

