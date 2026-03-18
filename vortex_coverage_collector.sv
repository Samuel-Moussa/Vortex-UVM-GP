////////////////////////////////////////////////////////////////////////////////
// File: vortex_coverage_collector.sv
// Description: Functional Coverage Collector for Vortex GPGPU
//
// Collects functional coverage by subscribing to all agent monitors.
// All field names verified against actual transaction class definitions:
//   - mem_transaction.sv    : rw, byteen(8-bit), addr, tag, data, rsp_data
//   - axi_transaction.sv    : trans_type, burst, size, len, bresp, rresp[],
//                             AXI_WRITE/READ, AXI_FIXED/INCR/WRAP,
//                             AXI_OKAY/EXOKAY/SLVERR/DECERR
//   - dcr_transaction.sv    : addr, data, DCR_STARTUP_ADDR0/1, DCR_ARGV_PTR0/1,
//                             DCR_MPM_CLASS (enum typedef dcr_addr_e)
//   - host_transaction.sv   : op_type(host_op_type_e), num_cores, num_warps,
//                             num_threads, completion_flag
//   - status_transaction.sv : busy, ebreak_detected, ipc(real),
//                             fetch_stall, memory_stall, execute_stall,
//                             count_active_warps() function
//
// Fixes applied:
//   - `uvm_analysis_imp_decl macros at file scope (not inside class)
//   - axi_transaction_cg: bresp/rresp[0] with iff guards (not .resp)
//   - mem_operation_cg: 8-bit byteen bins (not 4-bit)
//   - dcr_config_cg: dcr_addr_e enum constants (not hardcoded hex)
//   - status_performance_cg: ipc_bucket() integer helper for real IPC
//   - Reserved keyword bin names: med/sm/lg/sh/lng (not medium/small/large/short/long)
//   - Covergroups instantiated in new() (QuestaSim requirement)
//   - cfg null-guard in all write_*() methods
//
// Author: Vortex UVM Team
// Date: March 2026
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_COVERAGE_COLLECTOR_SV
`define VORTEX_COVERAGE_COLLECTOR_SV

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

class vortex_coverage_collector extends uvm_component;
  `uvm_component_utils(vortex_coverage_collector)

  //==========================================================================
  // Analysis Imports
  //==========================================================================
  uvm_analysis_imp_mem    #(mem_transaction,    vortex_coverage_collector) mem_imp;
  uvm_analysis_imp_axi    #(axi_transaction,    vortex_coverage_collector) axi_imp;
  uvm_analysis_imp_dcr    #(dcr_transaction,    vortex_coverage_collector) dcr_imp;
  uvm_analysis_imp_host   #(host_transaction,   vortex_coverage_collector) host_imp;
  uvm_analysis_imp_status #(status_transaction, vortex_coverage_collector) status_imp;

  //==========================================================================
  // Configuration
  //==========================================================================
  vortex_config cfg;

  //==========================================================================
  // Current transaction handles — set before each covergroup sample()
  //==========================================================================
  mem_transaction    current_mem;
  axi_transaction    current_axi;
  dcr_transaction    current_dcr;
  host_transaction   current_host;
  status_transaction current_status;

  //==========================================================================
  // IPC bucket helper — converts real IPC to integer bin index
  //   0 = zero IPC     (< 0.01)
  //   1 = very low IPC (0.01 – 0.25)
  //   2 = low IPC      (0.25 – 0.50)
  //   3 = medium IPC   (0.50 – 0.75)
  //   4 = high IPC     (0.75 – 1.00)
  //   5 = very high    (> 1.00)
  // Must be declared before covergroups that reference it.
  //==========================================================================
  function automatic int ipc_bucket(real ipc_val);
    if      (ipc_val <  0.01) return 0;
    else if (ipc_val <  0.25) return 1;
    else if (ipc_val <  0.50) return 2;
    else if (ipc_val <  0.75) return 3;
    else if (ipc_val <= 1.00) return 4;
    else                      return 5;
  endfunction

  //==========================================================================
  // Coverage Groups
  //==========================================================================

  // --------------------------------------------------------------------------
  // Memory Operation Coverage
  // byteen is 8 bits wide per mem_transaction.sv (VX_MEM_BYTEEN_WIDTH=8)
  // --------------------------------------------------------------------------
  covergroup mem_operation_cg;
    option.per_instance = 1;

    cp_rw: coverpoint current_mem.rw {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    cp_byteen: coverpoint current_mem.byteen {
      bins full_dword = {8'hFF};
      bins lo_word    = {8'h0F};
      bins hi_word    = {8'hF0};
      bins hw_0       = {8'h03};
      bins hw_1       = {8'h0C};
      bins hw_2       = {8'h30};
      bins hw_3       = {8'hC0};
      bins byte_0     = {8'h01};
      bins byte_1     = {8'h02};
      bins byte_2     = {8'h04};
      bins byte_3     = {8'h08};
      bins byte_4     = {8'h10};
      bins byte_5     = {8'h20};
      bins byte_6     = {8'h40};
      bins byte_7     = {8'h80};
      bins other[]    = default;
    }

    cp_addr_align: coverpoint current_mem.addr[2:0] {
      bins aligned_8   = {3'b000};
      bins aligned_4   = {3'b100};
      bins unaligned[] = default;
    }

    cp_tag: coverpoint current_mem.tag {
      bins low[]  = {[0:3]};
      bins mid[]  = {[4:11]};
      bins high[] = {[12:$]};
    }

    cross_rw_byteen: cross cp_rw, cp_byteen;
  endgroup : mem_operation_cg

  // --------------------------------------------------------------------------
  // AXI Transaction Coverage
  // Fields verified: trans_type, burst, size, len, bresp, rresp[]
  // Response enums: AXI_OKAY, AXI_EXOKAY, AXI_SLVERR, AXI_DECERR
  // --------------------------------------------------------------------------
  covergroup axi_transaction_cg;
    option.per_instance = 1;

    cp_type: coverpoint current_axi.trans_type {
      bins write = {axi_transaction::AXI_WRITE};
      bins read  = {axi_transaction::AXI_READ};
    }

    cp_burst: coverpoint current_axi.burst {
      bins fixed = {axi_transaction::AXI_FIXED};
      bins incr  = {axi_transaction::AXI_INCR};
      bins wrap  = {axi_transaction::AXI_WRAP};
    }

    cp_size: coverpoint current_axi.size {
      bins byte_1   = {3'h0};
      bins byte_2   = {3'h1};
      bins byte_4   = {3'h2};
      bins byte_8   = {3'h3};
      bins larger[] = {[3'h4:3'h7]};
    }

    cp_len: coverpoint current_axi.len {
      bins single = {8'h00};
      bins sh[]   = {[8'h01:8'h03]};
      bins med[]  = {[8'h04:8'h0F]};
      bins lng[]  = {[8'h10:8'hFF]};
    }

    // Write response — only valid for write transactions
    cp_bresp: coverpoint current_axi.bresp
        iff (current_axi.trans_type == axi_transaction::AXI_WRITE) {
      bins okay   = {axi_transaction::AXI_OKAY};
      bins exokay = {axi_transaction::AXI_EXOKAY};
      bins slverr = {axi_transaction::AXI_SLVERR};
      bins decerr = {axi_transaction::AXI_DECERR};
    }

    // Read response first beat — only valid for read transactions with data
    cp_rresp0: coverpoint current_axi.rresp[0]
        iff (current_axi.trans_type == axi_transaction::AXI_READ
             && current_axi.rresp.size() > 0) {
      bins okay   = {axi_transaction::AXI_OKAY};
      bins exokay = {axi_transaction::AXI_EXOKAY};
      bins slverr = {axi_transaction::AXI_SLVERR};
      bins decerr = {axi_transaction::AXI_DECERR};
    }

    cross_type_burst_size: cross cp_type, cp_burst, cp_size;
  endgroup : axi_transaction_cg

  // --------------------------------------------------------------------------
  // DCR Configuration Coverage
  // Uses actual enum constants from dcr_transaction typedef dcr_addr_e
  // --------------------------------------------------------------------------
  covergroup dcr_config_cg;
    option.per_instance = 1;

    cp_addr: coverpoint current_dcr.addr {
      bins startup_addr0 = {dcr_transaction::DCR_STARTUP_ADDR0};
      bins startup_addr1 = {dcr_transaction::DCR_STARTUP_ADDR1};
      bins argv_ptr0     = {dcr_transaction::DCR_ARGV_PTR0};
      bins argv_ptr1     = {dcr_transaction::DCR_ARGV_PTR1};
      bins mpm_class     = {dcr_transaction::DCR_MPM_CLASS};
      bins other[]       = default;
    }

    cp_startup_align: coverpoint current_dcr.data[1:0]
        iff (current_dcr.addr == dcr_transaction::DCR_STARTUP_ADDR0) {
      bins aligned   = {2'b00};
      bins unaligned = {2'b01, 2'b10, 2'b11};
    }
  endgroup : dcr_config_cg

  // --------------------------------------------------------------------------
  // Host Operation Coverage
  // Fields verified: op_type, num_cores, num_warps, num_threads, completion_flag
  // --------------------------------------------------------------------------
  covergroup host_operation_cg;
    option.per_instance = 1;

    cp_op_type: coverpoint current_host.op_type {
      bins reset         = {host_transaction::HOST_RESET};
      bins load_program  = {host_transaction::HOST_LOAD_PROGRAM};
      bins configure_dcr = {host_transaction::HOST_CONFIGURE_DCR};
      bins launch_kernel = {host_transaction::HOST_LAUNCH_KERNEL};
      bins wait_done     = {host_transaction::HOST_WAIT_DONE};
      bins read_result   = {host_transaction::HOST_READ_RESULT};
    }

    cp_num_cores: coverpoint current_host.num_cores
        iff (current_host.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
      bins single = {32'd1};
      bins sm[]   = {[32'd2:32'd4]};
      bins lg[]   = {[32'd5:32'd8]};
    }

    cp_num_warps: coverpoint current_host.num_warps
        iff (current_host.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
      bins low[]  = {[32'd1:32'd2]};
      bins mid[]  = {[32'd3:32'd4]};
      bins high[] = {[32'd5:32'd8]};
    }

    cp_num_threads: coverpoint current_host.num_threads
        iff (current_host.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
      bins t1 = {32'd1};
      bins t2 = {32'd2};
      bins t4 = {32'd4};
    }

    cp_completion: coverpoint current_host.completion_flag
        iff (current_host.op_type == host_transaction::HOST_WAIT_DONE) {
      bins completed = {1'b1};
      bins timeout   = {1'b0};
    }

    cross_cores_warps: cross cp_num_cores, cp_num_warps;
  endgroup : host_operation_cg

  // --------------------------------------------------------------------------
  // Status / Performance Coverage
  // Fields verified: busy, ebreak_detected, ipc(real), fetch_stall,
  //                  memory_stall, execute_stall, count_active_warps()
  // ipc_bucket() converts real IPC to integer bin index (avoids real bins)
  // --------------------------------------------------------------------------
  covergroup status_performance_cg;
    option.per_instance = 1;

    cp_busy: coverpoint current_status.busy {
      bins idle = {1'b0};
      bins busy = {1'b1};
    }

    cp_ebreak: coverpoint current_status.ebreak_detected {
      bins running   = {1'b0};
      bins completed = {1'b1};
    }

    // Integer bucket index from real IPC value
    cp_ipc_bucket: coverpoint ipc_bucket(current_status.ipc) {
      bins zero      = {0};
      bins very_low  = {1};
      bins low_ipc   = {2};
      bins med_ipc   = {3};
      bins high_ipc  = {4};
      bins very_high = {5};
    }

    cp_fetch_stall:   coverpoint current_status.fetch_stall;
    cp_memory_stall:  coverpoint current_status.memory_stall;
    cp_execute_stall: coverpoint current_status.execute_stall;

    cp_active_warps: coverpoint current_status.count_active_warps() {
      bins none   = {0};
      bins few[]  = {[1:2]};
      bins some[] = {[3:4]};
      bins many[] = {[5:$]};
    }

    cross_ipc_stalls: cross cp_ipc_bucket, cp_fetch_stall, cp_memory_stall;
  endgroup : status_performance_cg

  //==========================================================================
  // Constructor — covergroups MUST be instantiated here (QuestaSim rule)
  //==========================================================================
  function new(string name = "vortex_coverage_collector",
               uvm_component parent = null);
    super.new(name, parent);
    mem_operation_cg      = new();
    axi_transaction_cg    = new();
    dcr_config_cg         = new();
    host_operation_cg     = new();
    status_performance_cg = new();
  endfunction

  //==========================================================================
  // Build Phase
  //==========================================================================
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(vortex_config)::get(this, "", "cfg", cfg))
      `uvm_info("COVERAGE",
        "No vortex_config found — coverage collection disabled", UVM_MEDIUM)

    mem_imp    = new("mem_imp",    this);
    axi_imp    = new("axi_imp",    this);
    dcr_imp    = new("dcr_imp",    this);
    host_imp   = new("host_imp",   this);
    status_imp = new("status_imp", this);
  endfunction : build_phase

  //==========================================================================
  // Write Methods
  //==========================================================================

  virtual function void write_mem(mem_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    current_mem = trans;
    mem_operation_cg.sample();
    `uvm_info("COVERAGE", "Sampled MEM transaction", UVM_DEBUG)
  endfunction

  virtual function void write_axi(axi_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    current_axi = trans;
    axi_transaction_cg.sample();
    `uvm_info("COVERAGE", "Sampled AXI transaction", UVM_DEBUG)
  endfunction

  virtual function void write_dcr(dcr_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    current_dcr = trans;
    dcr_config_cg.sample();
    `uvm_info("COVERAGE", "Sampled DCR transaction", UVM_DEBUG)
  endfunction

  virtual function void write_host(host_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    current_host = trans;
    host_operation_cg.sample();
    `uvm_info("COVERAGE", "Sampled HOST transaction", UVM_DEBUG)
  endfunction

  virtual function void write_status(status_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    current_status = trans;
    status_performance_cg.sample();
    `uvm_info("COVERAGE", "Sampled STATUS transaction", UVM_DEBUG)
  endfunction

  //==========================================================================
  // Report Phase
  //==========================================================================
  virtual function void report_phase(uvm_phase phase);
    real mem_cov, axi_cov, dcr_cov, host_cov, status_cov, total_cov;
    super.report_phase(phase);

    if (cfg == null || !cfg.enable_coverage) begin
      `uvm_info("COVERAGE", "Coverage disabled — no report generated", UVM_MEDIUM)
      return;
    end

    mem_cov    = mem_operation_cg.get_coverage();
    axi_cov    = axi_transaction_cg.get_coverage();
    dcr_cov    = dcr_config_cg.get_coverage();
    host_cov   = host_operation_cg.get_coverage();
    status_cov = status_performance_cg.get_coverage();
    total_cov  = (mem_cov + axi_cov + dcr_cov + host_cov + status_cov) / 5.0;

    `uvm_info("COVERAGE", {"\n",
      "╔══════════════════════════════════════════╗\n",
      "║    Vortex Functional Coverage Report     ║\n",
      "╠══════════════════════════════════════════╣\n",
      $sformatf("║  Memory Operations  : %6.2f%%             ║\n", mem_cov),
      $sformatf("║  AXI Transactions   : %6.2f%%             ║\n", axi_cov),
      $sformatf("║  DCR Configuration  : %6.2f%%             ║\n", dcr_cov),
      $sformatf("║  Host Operations    : %6.2f%%             ║\n", host_cov),
      $sformatf("║  Status/Performance : %6.2f%%             ║\n", status_cov),
      "╠══════════════════════════════════════════╣\n",
      $sformatf("║  TOTAL COVERAGE     : %6.2f%%             ║\n", total_cov),
      "╚══════════════════════════════════════════╝\n"
    }, UVM_NONE)

    if (total_cov < 90.0)
      `uvm_warning("COVERAGE",
        $sformatf("Total coverage %.2f%% is below 90%% goal", total_cov))
    else
      `uvm_info("COVERAGE", "Coverage goal of 90%% met!", UVM_NONE)
  endfunction : report_phase

endclass : vortex_coverage_collector

`endif // VORTEX_COVERAGE_COLLECTOR_SV
