////////////////////////////////////////////////////////////////////////////////
// File: vortex_env.sv
// Description: Top-Level Vortex UVM Environment
//
// Instantiates and connects all verification components:
//   ✓ 5 UVM Agents  (mem, axi, dcr, host, status)
//   ✓ Virtual Sequencer
//   ✓ Scoreboard     (vortex_scoreboard)   – gated by cfg.enable_scoreboard
//   ✓ Coverage       (vortex_coverage_collector) – gated by cfg.enable_coverage
//
// Analysis port wiring (confirmed from agent source):
//   Every agent exposes a single top-level  uvm_analysis_port #(T) ap
//   that is forwarded from the internal monitor.  The env connects these
//   directly to the scoreboard exports and coverage imps.
//
// FIX (March 2026):
//   connect_phase virtual sequencer wiring for axi_agent, dcr_agent, and
//   host_agent was missing the get_is_active() guard.  When any of these
//   agents runs in PASSIVE mode their m_sequencer is never created
//   (build_phase only creates it when UVM_ACTIVE), so assigning a null
//   handle to the virtual sequencer caused any virtual sequence using
//   p_sequencer.m_axi_sequencer / m_dcr_sequencer / m_host_sequencer to
//   crash at runtime.  All three assignments now mirror the mem_agent
//   pattern: null-check AND active-check AND sequencer-null-check.
//
// Author: Vortex UVM Team
// Date: December 2025
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_ENV_SV
`define VORTEX_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

import vortex_config_pkg::*;
import mem_agent_pkg::*;
import axi_agent_pkg::*;
import dcr_agent_pkg::*;
import host_agent_pkg::*;
import status_agent_pkg::*;
import vortex_env_pkg::*;

// `include "vortex_virtual_sequencer.sv"

// Note: scoreboard and coverage_collector are included by vortex_env_pkg.sv
// Do NOT include them here again to avoid double-compilation errors.

class vortex_env extends uvm_env;
  `uvm_component_utils(vortex_env)

  //==========================================================================
  // Configuration
  //==========================================================================
  vortex_config cfg;

  //==========================================================================
  // Agents
  //==========================================================================
  mem_agent    m_mem_agent;
  axi_agent    m_axi_agent;
  dcr_agent    m_dcr_agent;
  host_agent   m_host_agent;
  status_agent m_status_agent;

  //==========================================================================
  // Virtual Sequencer
  //==========================================================================
  vortex_virtual_sequencer m_virtual_sequencer;

  //==========================================================================
  // Scoreboard  (enabled via cfg.enable_scoreboard)
  //==========================================================================
  vortex_scoreboard m_scoreboard;

  //==========================================================================
  // Coverage Collector  (enabled via cfg.enable_coverage)
  //==========================================================================
  vortex_coverage_collector m_coverage;

  //==========================================================================
  // Constructor
  //==========================================================================
  function new(string name = "vortex_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //==========================================================================
  // Build Phase
  //==========================================================================
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // ------------------------------------------------------------------
    // Get (or create) configuration
    // ------------------------------------------------------------------
    if (!uvm_config_db #(vortex_config)::get(this, "", "cfg", cfg)) begin
      `uvm_info("VORTEX_ENV",
        "No vortex_config found in config DB – creating default", UVM_MEDIUM)
      cfg = vortex_config::type_id::create("cfg");
      cfg.set_defaults_from_vx_config();
      cfg.apply_plusargs();
    end

    if (!cfg.is_valid())
      `uvm_fatal("VORTEX_ENV", "Invalid configuration detected!")

    cfg.print_config(UVM_MEDIUM);

    // Propagate to all children
    uvm_config_db #(vortex_config)::set(this, "*", "cfg", cfg);

    // ------------------------------------------------------------------
    // Create agents
    // ------------------------------------------------------------------
    if (cfg.mem_agent_enable) begin
      m_mem_agent = mem_agent::type_id::create("m_mem_agent", this);
      // Active when the custom-mem path is the primary memory interface;
      // passive when the AXI wrapper is driving (mem_agent is then a pure
      // observer of internal-bus traffic). Driving the responder is required
      // for the DUT to receive memory responses on the custom-mem path —
      // without it, rsp_valid/rsp_data/rsp_tag/req_ready are never sourced
      // and the DUT either stalls or X-cascades through its i-cache MSHR.
      m_mem_agent.is_active = cfg.axi_agent_enable ? UVM_PASSIVE : UVM_ACTIVE;
      `uvm_info("VORTEX_ENV",
                $sformatf("mem_agent created (%s)",
                          cfg.axi_agent_enable ? "PASSIVE" : "ACTIVE"),
                UVM_MEDIUM)
    end

    if (cfg.axi_agent_enable) begin
      m_axi_agent = axi_agent::type_id::create("m_axi_agent", this);
      `uvm_info("VORTEX_ENV", "axi_agent created", UVM_MEDIUM)
    end

    if (cfg.dcr_agent_enable) begin
      m_dcr_agent = dcr_agent::type_id::create("m_dcr_agent", this);
      `uvm_info("VORTEX_ENV", "dcr_agent created", UVM_MEDIUM)
    end

    if (cfg.host_agent_enable) begin
      m_host_agent = host_agent::type_id::create("m_host_agent", this);
      `uvm_info("VORTEX_ENV", "host_agent created", UVM_MEDIUM)
    end

    if (cfg.status_agent_enable) begin
      m_status_agent = status_agent::type_id::create("m_status_agent", this);
      `uvm_info("VORTEX_ENV", "status_agent created (always PASSIVE)", UVM_MEDIUM)
    end

    // ------------------------------------------------------------------
    // Virtual sequencer (always created – sequencers may be null if
    // the corresponding agent is passive/disabled, which is fine)
    // ------------------------------------------------------------------
    m_virtual_sequencer =
      vortex_virtual_sequencer::type_id::create("m_virtual_sequencer", this);
    `uvm_info("VORTEX_ENV", "Virtual sequencer created", UVM_MEDIUM)

    // ------------------------------------------------------------------
    // Scoreboard
    // ------------------------------------------------------------------
    if (cfg.enable_scoreboard) begin
      m_scoreboard =
        vortex_scoreboard::type_id::create("m_scoreboard", this);
      `uvm_info("VORTEX_ENV", "Scoreboard created", UVM_MEDIUM)
    end else begin
      `uvm_info("VORTEX_ENV", "Scoreboard DISABLED (cfg.enable_scoreboard=0)",
                UVM_MEDIUM)
    end

    // ------------------------------------------------------------------
    // Coverage collector
    // ------------------------------------------------------------------
    if (cfg.enable_coverage) begin
      m_coverage =
        vortex_coverage_collector::type_id::create("m_coverage", this);
      `uvm_info("VORTEX_ENV", "Coverage collector created", UVM_MEDIUM)
    end else begin
      `uvm_info("VORTEX_ENV",
                "Coverage collector DISABLED (cfg.enable_coverage=0)", UVM_MEDIUM)
    end

  endfunction : build_phase

  //==========================================================================
  // Connect Phase
  //==========================================================================
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // ------------------------------------------------------------------
    // Virtual sequencer ← agent sequencers (only when agent is ACTIVE)
    // ------------------------------------------------------------------
    if (m_mem_agent != null &&
        m_mem_agent.get_is_active() == UVM_ACTIVE &&
        m_mem_agent.m_sequencer != null)
      m_virtual_sequencer.m_mem_sequencer = m_mem_agent.m_sequencer;

    if (m_axi_agent  != null &&
        m_axi_agent.get_is_active()  == UVM_ACTIVE &&
        m_axi_agent.m_sequencer  != null)
      m_virtual_sequencer.m_axi_sequencer = m_axi_agent.m_sequencer;

    if (m_dcr_agent  != null &&
        m_dcr_agent.get_is_active()  == UVM_ACTIVE &&
        m_dcr_agent.m_sequencer  != null)
      m_virtual_sequencer.m_dcr_sequencer = m_dcr_agent.m_sequencer;

    if (m_host_agent != null &&
        m_host_agent.get_is_active() == UVM_ACTIVE &&
        m_host_agent.m_sequencer != null)
      m_virtual_sequencer.m_host_sequencer = m_host_agent.m_sequencer;

    // ------------------------------------------------------------------
    // Scoreboard ← agent analysis ports
    // Each agent exposes a single top-level  ap  forwarded from its monitor.
    // ------------------------------------------------------------------
    if (m_scoreboard != null) begin
      if (m_mem_agent    != null)
        m_mem_agent.ap.connect(m_scoreboard.mem_export);

      if (m_axi_agent    != null) begin
        m_axi_agent.ap_write.connect(m_scoreboard.axi_export);
        m_axi_agent.ap_read.connect(m_scoreboard.axi_export);
      end

      if (m_dcr_agent    != null)
        m_dcr_agent.ap.connect(m_scoreboard.dcr_export);

      if (m_host_agent   != null)
        m_host_agent.ap.connect(m_scoreboard.host_export);

      if (m_status_agent != null)
        m_status_agent.ap.connect(m_scoreboard.status_export);

      `uvm_info("VORTEX_ENV", "Scoreboard connected to all agents", UVM_MEDIUM)
    end

    // ------------------------------------------------------------------
    // Coverage collector ← agent analysis ports
    // ------------------------------------------------------------------
    if (m_coverage != null) begin
      if (m_mem_agent    != null)
        m_mem_agent.ap.connect(m_coverage.mem_imp);

      if (m_axi_agent    != null) begin
        m_axi_agent.ap_write.connect(m_coverage.axi_imp);
        m_axi_agent.ap_read.connect(m_coverage.axi_imp);
      end

      if (m_dcr_agent    != null)
        m_dcr_agent.ap.connect(m_coverage.dcr_imp);

      if (m_host_agent   != null)
        m_host_agent.ap.connect(m_coverage.host_imp);

      if (m_status_agent != null)
        m_status_agent.ap.connect(m_coverage.status_imp);

      `uvm_info("VORTEX_ENV",
                "Coverage collector connected to all agents", UVM_MEDIUM)
    end

  endfunction : connect_phase

  //==========================================================================
  // End of Elaboration Phase – topology summary
  //==========================================================================
  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);

    `uvm_info("VORTEX_ENV", {"\n",
      "╔══════════════════════════════════════════════╗\n",
      "║       Vortex UVM Environment Topology        ║\n",
      "╠══════════════════════════════════════════════╣\n",
      $sformatf("║  Config        : %-27s║\n", cfg.get_config_string()),
      "╠══════════════════════════════════════════════╣\n",
      $sformatf("║  mem_agent     : %-27s║\n",
        m_mem_agent    != null ?
          (m_mem_agent.get_is_active()==UVM_ACTIVE ? "ACTIVE" : "PASSIVE") :
          "DISABLED"),
      $sformatf("║  axi_agent     : %-27s║\n",
        m_axi_agent    != null ?
          (m_axi_agent.get_is_active()==UVM_ACTIVE ? "ACTIVE" : "PASSIVE") :
          "DISABLED"),
      $sformatf("║  dcr_agent     : %-27s║\n",
        m_dcr_agent    != null ?
          (m_dcr_agent.get_is_active()==UVM_ACTIVE ? "ACTIVE" : "PASSIVE") :
          "DISABLED"),
      $sformatf("║  host_agent    : %-27s║\n",
        m_host_agent   != null ?
          (m_host_agent.get_is_active()==UVM_ACTIVE ? "ACTIVE" : "PASSIVE") :
          "DISABLED"),
      $sformatf("║  status_agent  : %-27s║\n",
        m_status_agent != null ? "PASSIVE" : "DISABLED"),
      "╠══════════════════════════════════════════════╣\n",
      $sformatf("║  Scoreboard    : %-27s║\n",
        m_scoreboard != null ? "ENABLED" : "DISABLED"),
      $sformatf("║  Coverage      : %-27s║\n",
        m_coverage   != null ? "ENABLED" : "DISABLED"),
      $sformatf("║  Virt Seqr     : %-27s║\n",
        m_virtual_sequencer != null ? "CREATED" : "MISSING"),
      "╚══════════════════════════════════════════════╝\n"
    }, UVM_LOW)

    if (cfg.default_verbosity >= UVM_HIGH)
      uvm_top.print_topology();
  endfunction : end_of_elaboration_phase

  //==========================================================================
  // Report Phase
  //==========================================================================
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    // Individual report_phase() on scoreboard and coverage_collector
    // are called automatically by the UVM phase machinery – no need to
    // call report_results() / report_coverage() manually here.
    `uvm_info("VORTEX_ENV", "Environment report phase complete", UVM_LOW)
  endfunction : report_phase

endclass : vortex_env

`endif // VORTEX_ENV_SV