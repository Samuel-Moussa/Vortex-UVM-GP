////////////////////////////////////////////////////////////////////////////////
// File: vortex_scoreboard.sv
// Description: Scoreboard for Vortex GPGPU Verification
//
// Compares DUT transactions against the simx reference model via DPI-C.
// Receives transactions from all agents and performs result checking.
//
// Key Features:
//   - DPI-C integration with simx reference model
//   - Multi-agent transaction collection
//   - Automatic result comparison
//   - Pass/fail statistics tracking
//   - Memory transaction shadowing
//
// Author: Vortex UVM Team
// Date: December 2025
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_SCOREBOARD_SV
`define VORTEX_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

import vortex_config_pkg::*;
import mem_agent_pkg::*;
import axi_agent_pkg::*;
import dcr_agent_pkg::*;
import host_agent_pkg::*;
import status_agent_pkg::*;

class vortex_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(vortex_scoreboard)

  //==========================================================================
  // Configuration
  //==========================================================================
  vortex_config cfg;

  //==========================================================================
  // Analysis Exports (receive transactions from agents)
  //==========================================================================
  uvm_analysis_imp_mem#(mem_transaction, vortex_scoreboard) mem_export;
  uvm_analysis_imp_axi#(axi_transaction, vortex_scoreboard) axi_export;
  uvm_analysis_imp_dcr#(dcr_transaction, vortex_scoreboard) dcr_export;
  uvm_analysis_imp_host#(host_transaction, vortex_scoreboard) host_export;
  uvm_analysis_imp_status#(status_transaction, vortex_scoreboard) status_export;

  //==========================================================================
  // Scoreboards and Queues
  //==========================================================================
  mem_transaction mem_queue[$];
  axi_transaction axi_queue[$];
  int unsigned num_transactions;
  int unsigned num_comparisons;
  int unsigned num_passed;
  int unsigned num_failed;

  // Shadow memory for tracking writes
  bit [63:0] shadow_memory[bit [31:0]];

  //==========================================================================
  // DPI-C Imports for simx Reference Model
  //==========================================================================
  import "DPI-C" function int simx_init(string config_file);
  import "DPI-C" function void simx_cleanup();
  import "DPI-C" function int simx_dcr_write(int addr, int data);
  import "DPI-C" function int simx_mem_write(longint addr, longint data, int size);
  import "DPI-C" function longint simx_mem_read(longint addr, int size);
  import "DPI-C" function int simx_run_step();
  import "DPI-C" function int simx_get_status(output int busy, output int ebreak);
  import "DPI-C" function void simx_dump_state();

  //==========================================================================
  // Constructor
  //==========================================================================
  function new(string name = "vortex_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    mem_export = new("mem_export", this);
    axi_export = new("axi_export", this);
    dcr_export = new("dcr_export", this);
    host_export = new("host_export", this);
    status_export = new("status_export", this);
  endfunction

  //==========================================================================
  // Build Phase
  //==========================================================================
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("SCOREBOARD", "Failed to get vortex_config")
    end

    num_transactions = 0;
    num_comparisons = 0;
    num_passed = 0;
    num_failed = 0;

  endfunction : build_phase

  //==========================================================================
  // Run Phase - Initialize simx
  //==========================================================================
  virtual task run_phase(uvm_phase phase);
    int status;

    if (cfg.simx_enable) begin
      `uvm_info("SCOREBOARD", $sformatf("Initializing simx from: %s", cfg.simx_path), UVM_MEDIUM)
      
      status = simx_init(cfg.simx_path);
      
      if (status != 0) begin
        `uvm_error("SCOREBOARD", $sformatf("simx initialization failed with status %0d", status))
      end else begin
        `uvm_info("SCOREBOARD", "simx initialized successfully", UVM_MEDIUM)
      end
    end else begin
      `uvm_info("SCOREBOARD", "simx reference model disabled", UVM_MEDIUM)
    end

  endtask : run_phase

  //==========================================================================
  // Analysis Write Methods (called by agents via analysis ports)
  //==========================================================================

  // Memory transaction received
  virtual function void write_mem(mem_transaction tr);
    num_transactions++;
    
    `uvm_info("SCOREBOARD", $sformatf("MEM transaction received: %s addr=0x%h data=0x%h", 
              tr.rw ? "WRITE" : "READ", tr.addr, tr.data), UVM_DEBUG)
    
    if (cfg.simx_enable) begin
      if (tr.rw) begin
        // Write to shadow memory
        shadow_memory[tr.addr] = tr.data;
        
        // Update simx model
        void'(simx_mem_write(tr.addr, tr.data, 8)); // 64-bit writes
      end else begin
        // Read - compare with simx
        bit [63:0] expected_data;
        expected_data = simx_mem_read(tr.addr, 8);
        
        num_comparisons++;
        if (tr.data === expected_data) begin
          num_passed++;
          `uvm_info("SCOREBOARD", $sformatf("MEM READ MATCH: addr=0x%h data=0x%h", 
                    tr.addr, tr.data), UVM_HIGH)
        end else begin
          num_failed++;
          `uvm_error("SCOREBOARD", $sformatf("MEM READ MISMATCH: addr=0x%h DUT=0x%h simx=0x%h", 
                     tr.addr, tr.data, expected_data))
        end
      end
    end
  endfunction : write_mem

  // AXI transaction received
  virtual function void write_axi(axi_transaction tr);
    num_transactions++;
    
    `uvm_info("SCOREBOARD", $sformatf("AXI transaction received: id=%0d addr=0x%h", 
              tr.id, tr.addr), UVM_DEBUG)
    
    // AXI transactions can be processed similarly to mem transactions
    // For now, just track them
  endfunction : write_axi

  // DCR transaction received
  virtual function void write_dcr(dcr_transaction tr);
    num_transactions++;
    
    `uvm_info("SCOREBOARD", $sformatf("DCR write received: addr=0x%h data=0x%h", 
              tr.addr, tr.data), UVM_DEBUG)
    
    if (cfg.simx_enable) begin
      void'(simx_dcr_write(tr.addr, tr.data));
    end
  endfunction : write_dcr

  // Host transaction received
  virtual function void write_host(host_transaction tr);
    num_transactions++;
    
    `uvm_info("SCOREBOARD", $sformatf("HOST transaction received: type=%s", 
              tr.op_type.name()), UVM_DEBUG)
    
    // Track high-level operations
  endfunction : write_host

  // Status transaction received
  virtual function void write_status(status_transaction tr);
    `uvm_info("SCOREBOARD", $sformatf("STATUS update: busy=%0b ebreak=%0b cycles=%0d", 
              tr.busy, tr.ebreak_detected, tr.cycle_count), UVM_DEBUG)
    
    // Monitor execution status
    if (tr.ebreak_detected) begin
      `uvm_info("SCOREBOARD", "EBREAK detected - kernel execution complete", UVM_MEDIUM)
    end
  endfunction : write_status

  //==========================================================================
  // Report Results
  //==========================================================================
  virtual function void report_results();
    `uvm_info("SCOREBOARD", {"\n",
      "========================================\n",
      " Scoreboard Results\n",
      "========================================\n",
      $sformatf(" Total Transactions: %0d\n", num_transactions),
      $sformatf(" Total Comparisons:  %0d\n", num_comparisons),
      $sformatf(" Passed:             %0d\n", num_passed),
      $sformatf(" Failed:             %0d\n", num_failed),
      $sformatf(" Pass Rate:          %0.2f%%\n", 
                num_comparisons > 0 ? (real'(num_passed)/real'(num_comparisons))*100.0 : 0.0),
      "========================================\n"
    }, UVM_NONE)

    if (num_failed > 0) begin
      `uvm_error("SCOREBOARD", $sformatf("%0d comparison(s) failed!", num_failed))
    end else if (num_comparisons > 0) begin
      `uvm_info("SCOREBOARD", "All comparisons passed!", UVM_NONE)
    end
  endfunction : report_results

  //==========================================================================
  // Final Phase - Cleanup simx
  //==========================================================================
  virtual function void final_phase(uvm_phase phase);
    super.final_phase(phase);
    
    if (cfg.simx_enable) begin
      `uvm_info("SCOREBOARD", "Cleaning up simx", UVM_MEDIUM)
      simx_cleanup();
    end
  endfunction : final_phase

endclass : vortex_scoreboard

`endif // VORTEX_SCOREBOARD_SV




















// `ifndef VORTEX_SCOREBOARD_SV
// `define VORTEX_SCOREBOARD_SV

// `include "simx_wrapper.sv"

// class vortex_scoreboard extends uvm_scoreboard;

//   `uvm_component_utils(vortex_scoreboard)

//   // Analysis exports for all agents
//   uvm_analysis_imp #(mem_transaction, vortex_scoreboard) mem_export;
//   uvm_analysis_imp #(axi_transaction, vortex_scoreboard) axi_export;
//   uvm_analysis_imp #(dcr_transaction, vortex_scoreboard) dcr_export;
//   uvm_analysis_imp #(host_transaction, vortex_scoreboard) host_export;

//   // Queues to store expected and actual transactions
//   mem_transaction expected_mem_q[$];
//   mem_transaction actual_mem_q[$];

//   // simx wrapper instance
//   simx_wrapper m_simx_wrapper;

//   function new(string name, uvm_component parent);
//     super.new(name, parent);
//     mem_export = new("mem_export", this);
//     axi_export = new("axi_export", this);
//     dcr_export = new("dcr_export", this);
//     host_export = new("host_export", this);
//   endfunction

//   function void build_phase(uvm_phase phase);
//     super.build_phase(phase);
//     m_simx_wrapper = new();
//     m_simx_wrapper.simx_init();
//   endfunction

//   function void final_phase(uvm_phase phase);
//     super.final_phase(phase);
//     m_simx_wrapper.simx_shutdown();
//   endfunction

//   // Write functions for each agent's analysis port

//   virtual function void write_mem(mem_transaction trans);
//     `uvm_info("SCOREBOARD", "Received memory transaction from DUT", UVM_LOW)
//     actual_mem_q.push_back(trans);
//   endfunction

//   virtual function void write_axi(axi_transaction trans);
//     `uvm_info("SCOREBOARD", "Received AXI transaction from DUT", UVM_LOW)
//     // Convert AXI transaction to memory transaction and push to actual_mem_q
//   endfunction

//   virtual function void write_dcr(dcr_transaction trans);
//     `uvm_info("SCOREBOARD", "Received DCR transaction from DUT", UVM_LOW)
//     // Pass DCR writes to the reference model
//     m_simx_wrapper.simx_write_dcr(trans.addr, trans.data);
//   endfunction

//   virtual function void write_host(host_transaction trans);
//     `uvm_info("SCOREBOARD", "Received host transaction from DUT", UVM_LOW)
//     // Trigger kernel execution in the reference model
//     m_simx_wrapper.simx_execute_kernel(trans.kernel_addr, trans.num_warps, trans.num_threads);
//     // The reference model would then generate expected memory transactions
//     // and push them to the expected_mem_q
//   endfunction

//   // Main scoreboard comparison logic
//   virtual task run_phase(uvm_phase phase);
//     forever begin
//       @(posedge vif.clk);
//       if (actual_mem_q.size() > 0 && expected_mem_q.size() > 0) begin
//         mem_transaction act_trans = actual_mem_q.pop_front();
//         mem_transaction exp_trans = expected_mem_q.pop_front();
//         if (!act_trans.compare(exp_trans)) begin
//           `uvm_error("SCOREBOARD", "Memory transaction mismatch!")
//           $display("Expected: %s", exp_trans.sprint());
//           $display("Actual:   %s", act_trans.sprint());
//         end
//       end
//     end
//   endtask

// endclass : vortex_scoreboard

// `endif // VORTEX_SCOREBOARD_SV
