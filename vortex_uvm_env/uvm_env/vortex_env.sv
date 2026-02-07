// // ////////////////////////////////////////////////////////////////////////////////
// // // File: vortex_env.sv
// // // Description: Top-Level Vortex UVM Environment
// // //
// // // This is the main environment class that instantiates and connects all
// // // verification components following the Synopsys UVM Cookbook structure:
// // //
// // // Components:
// // //   ✓ 5 UVM Agents (mem, axi, dcr, host, status)
// // //   ✓ Virtual Sequencer (multi-agent coordination)
// // //   ✓ Coverage Collector (functional coverage)
// // //   ✓ Configuration Object (vortex_config)
// // //   □ Scoreboard (will be added after DPI-C wrapper)
// // //
// // // Agent Configuration:
// // //   • mem_agent    - ACTIVE  (custom memory interface)
// // //   • axi_agent    - ACTIVE  (AXI4 interface)
// // //   • dcr_agent    - ACTIVE  (device configuration registers)
// // //   • host_agent   - ACTIVE  (high-level host operations)
// // //   • status_agent - PASSIVE (execution status monitoring)
// // //
// // // Author: Vortex UVM Team
// // ////////////////////////////////////////////////////////////////////////////////
// ////////////////////////////////////////////////////////////////////////////////

// `ifndef VORTEX_ENV_SV
// `define VORTEX_ENV_SV

// import uvm_pkg::*;
// `include "uvm_macros.svh"

// // Import all agent packages
// import vortex_config_pkg::*;
// import mem_agent_pkg::*;
// import axi_agent_pkg::*;
// import dcr_agent_pkg::*;
// import host_agent_pkg::*;
// import status_agent_pkg::*;

// class vortex_env extends uvm_env;
//   `uvm_component_utils(vortex_env)

//   //==========================================================================
//   // Configuration
//   //==========================================================================
//   vortex_config cfg;

//   //==========================================================================
//   // Agent Instances
//   //==========================================================================
//   mem_agent    m_mem_agent;
//   axi_agent    m_axi_agent;
//   dcr_agent    m_dcr_agent;
//   host_agent   m_host_agent;
//   status_agent m_status_agent;

//   //==========================================================================
//   // Virtual Sequencer (for coordinated sequences)
//   //==========================================================================
//   vortex_virtual_sequencer m_virtual_sequencer;

//   //==========================================================================
//   // Scoreboard (DUT vs. simx reference model comparison)
//   //==========================================================================
//   vortex_scoreboard m_scoreboard;

//   //==========================================================================
//   // Functional Coverage Collector
//   //==========================================================================
//   vortex_coverage m_coverage;

//   //==========================================================================
//   // Constructor
//   //==========================================================================
//   function new(string name = "vortex_env", uvm_component parent = null);
//     super.new(name, parent);
//   endfunction

//   //==========================================================================
//   // Build Phase
//   //==========================================================================
//   virtual function void build_phase(uvm_phase phase);
//     super.build_phase(phase);

//     // Get configuration from config database
//     if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
//       `uvm_info("VORTEX_ENV", "No vortex_config found - creating default", UVM_MEDIUM)
//       cfg = vortex_config::type_id::create("cfg");
//       cfg.set_defaults_from_vx_config();
//     end

//     // Apply command-line plusargs
//     cfg.apply_plusargs();

//     // Validate configuration
//     if (!cfg.is_valid()) begin
//       `uvm_fatal("VORTEX_ENV", "Invalid configuration detected!")
//     end

//     // Print configuration summary
//     cfg.print_config(UVM_MEDIUM);

//     // Propagate configuration to all sub-components
//     uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);

//     // Create agents based on configuration
//     if (cfg.mem_agent_enable) begin
//       m_mem_agent = mem_agent::type_id::create("m_mem_agent", this);
//       `uvm_info("VORTEX_ENV", "Memory agent created", UVM_MEDIUM)
//     end

//     if (cfg.axi_agent_enable) begin
//       m_axi_agent = axi_agent::type_id::create("m_axi_agent", this);
//       `uvm_info("VORTEX_ENV", "AXI agent created", UVM_MEDIUM)
//     end

//     if (cfg.dcr_agent_enable) begin
//       m_dcr_agent = dcr_agent::type_id::create("m_dcr_agent", this);
//       `uvm_info("VORTEX_ENV", "DCR agent created", UVM_MEDIUM)
//     end

//     if (cfg.host_agent_enable) begin
//       m_host_agent = host_agent::type_id::create("m_host_agent", this);
//       `uvm_info("VORTEX_ENV", "Host agent created", UVM_MEDIUM)
//     end

//     if (cfg.status_agent_enable) begin
//       m_status_agent = status_agent::type_id::create("m_status_agent", this);
//       `uvm_info("VORTEX_ENV", "Status agent created", UVM_MEDIUM)
//     end

//     // Create virtual sequencer
//     m_virtual_sequencer = vortex_virtual_sequencer::type_id::create("m_virtual_sequencer", this);
//     `uvm_info("VORTEX_ENV", "Virtual sequencer created", UVM_MEDIUM)

//     // Create scoreboard if enabled
//     if (cfg.enable_scoreboard) begin
//       m_scoreboard = vortex_scoreboard::type_id::create("m_scoreboard", this);
//       `uvm_info("VORTEX_ENV", "Scoreboard created", UVM_MEDIUM)
//     end

//     // Create coverage collector if enabled
//     if (cfg.enable_coverage) begin
//       m_coverage = vortex_coverage::type_id::create("m_coverage", this);
//       `uvm_info("VORTEX_ENV", "Coverage collector created", UVM_MEDIUM)
//     end

//   endfunction : build_phase

//   //==========================================================================
//   // Connect Phase
//   //==========================================================================
//   virtual function void connect_phase(uvm_phase phase);
//     super.connect_phase(phase);

//     // Connect agent sequencers to virtual sequencer
//     if (m_mem_agent != null && m_mem_agent.m_sequencer != null) begin
//       m_virtual_sequencer.m_mem_sequencer = m_mem_agent.m_sequencer;
//     end

//     if (m_axi_agent != null && m_axi_agent.m_sequencer != null) begin
//       m_virtual_sequencer.m_axi_sequencer = m_axi_agent.m_sequencer;
//     end

//     if (m_dcr_agent != null && m_dcr_agent.m_sequencer != null) begin
//       m_virtual_sequencer.m_dcr_sequencer = m_dcr_agent.m_sequencer;
//     end

//     if (m_host_agent != null && m_host_agent.m_sequencer != null) begin
//       m_virtual_sequencer.m_host_sequencer = m_host_agent.m_sequencer;
//     end

//     // Connect agent analysis ports to scoreboard
//     if (m_scoreboard != null) begin
//       if (m_mem_agent != null) begin
//         m_mem_agent.ap.connect(m_scoreboard.mem_export);
//       end

//       if (m_axi_agent != null) begin
//         m_axi_agent.ap.connect(m_scoreboard.axi_export);
//       end

//       if (m_dcr_agent != null) begin
//         m_dcr_agent.ap.connect(m_scoreboard.dcr_export);
//       end

//       if (m_host_agent != null) begin
//         m_host_agent.ap.connect(m_scoreboard.host_export);
//       end

//       if (m_status_agent != null) begin
//         m_status_agent.ap.connect(m_scoreboard.status_export);
//       end
//     end

//     // Connect agent analysis ports to coverage collector
//     if (m_coverage != null) begin
//       if (m_mem_agent != null) begin
//         m_mem_agent.ap.connect(m_coverage.mem_export);
//       end

//       if (m_axi_agent != null) begin
//         m_axi_agent.ap.connect(m_coverage.axi_export);
//       end

//       if (m_dcr_agent != null) begin
//         m_dcr_agent.ap.connect(m_coverage.dcr_export);
//       end

//       if (m_host_agent != null) begin
//         m_host_agent.ap.connect(m_coverage.host_export);
//       end

//       if (m_status_agent != null) begin
//         m_status_agent.ap.connect(m_coverage.status_export);
//       end
//     end

//   endfunction : connect_phase

//   //==========================================================================
//   // End of Elaboration Phase
//   //==========================================================================
//   virtual function void end_of_elaboration_phase(uvm_phase phase);
//     super.end_of_elaboration_phase(phase);
    
//     `uvm_info("VORTEX_ENV", {"\n",
//       "========================================\n",
//       " Vortex UVM Environment Summary\n",
//       "========================================\n",
//       $sformatf(" Config: %s\n", cfg.get_config_string()),
//       $sformatf(" Mem Agent: %s\n", m_mem_agent != null ? "✓" : "✗"),
//       $sformatf(" AXI Agent: %s\n", m_axi_agent != null ? "✓" : "✗"),
//       $sformatf(" DCR Agent: %s\n", m_dcr_agent != null ? "✓" : "✗"),
//       $sformatf(" Host Agent: %s\n", m_host_agent != null ? "✓" : "✗"),
//       $sformatf(" Status Agent: %s\n", m_status_agent != null ? "✓" : "✗"),
//       $sformatf(" Virtual Sequencer: %s\n", m_virtual_sequencer != null ? "✓" : "✗"),
//       $sformatf(" Scoreboard: %s\n", m_scoreboard != null ? "✓" : "✗"),
//       $sformatf(" Coverage: %s\n", m_coverage != null ? "✓" : "✗"),
//       "========================================\n"
//     }, UVM_MEDIUM)
//   endfunction : end_of_elaboration_phase

//   //==========================================================================
//   // Run Phase
//   //==========================================================================
//   virtual task run_phase(uvm_phase phase);
//     super.run_phase(phase);
//     // Environment-level run-time functionality can be added here
//   endtask : run_phase

//   //==========================================================================
//   // Report Phase
//   //==========================================================================
//   virtual function void report_phase(uvm_phase phase);
//     super.report_phase(phase);
    
//     if (m_scoreboard != null) begin
//       m_scoreboard.report_results();
//     end

//     if (m_coverage != null) begin
//       m_coverage.report_coverage();
//     end

//   endfunction : report_phase

// endclass : vortex_env

// `endif // VORTEX_ENV_SV

//////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// File: vortex_env.sv (Simplified for Initial Testing)
// Description: Minimal UVM Environment - Agents Only
//
// This version EXCLUDES:
//   - Scoreboard (commented out)
//   - Coverage collector (commented out)
//   - SimX integration (not needed yet)
//
// Use this to verify agents and basic infrastructure work on Windows.
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_ENV_SV
`define VORTEX_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

// Import all agent packages
import vortex_config_pkg::*;
import mem_agent_pkg::*;
import axi_agent_pkg::*;
import dcr_agent_pkg::*;
import host_agent_pkg::*;
import status_agent_pkg::*;

`include "vortex_virtual_sequencer.sv"

class vortex_env extends uvm_env;
  `uvm_component_utils(vortex_env)

  //==========================================================================
  // Configuration
  //==========================================================================
  vortex_config cfg;

  //==========================================================================
  // Agent Instances
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
  // TODO: Add these components after Windows testing
  //==========================================================================
  // vortex_scoreboard m_scoreboard;  // Uncomment when ready
  // vortex_coverage m_coverage;      // Uncomment when ready

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

    // Get configuration from config database
    if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
      `uvm_info("VORTEX_ENV", "No vortex_config found - creating default", UVM_MEDIUM)
      cfg = vortex_config::type_id::create("cfg");
      cfg.set_defaults_from_vx_config();
    end

    // Apply command-line plusargs
    cfg.apply_plusargs();

    // Validate configuration
    if (!cfg.is_valid()) begin
      `uvm_fatal("VORTEX_ENV", "Invalid configuration detected!")
    end

    // Print configuration summary
    cfg.print_config(UVM_MEDIUM);

    // Propagate configuration to all sub-components
    uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);

    // Create agents based on configuration
    if (cfg.mem_agent_enable) begin
      m_mem_agent = mem_agent::type_id::create("m_mem_agent", this);
      
      // Configure agent as PASSIVE (monitor only - no driver/sequencer)
      m_mem_agent.is_active = UVM_PASSIVE;
      
      `uvm_info("VORTEX_ENV", "Memory agent created (PASSIVE mode - monitor only)", UVM_MEDIUM)
    end
    
    //// Create agents based on configuration
    // if (cfg.mem_agent_enable) begin
    //   m_mem_agent = mem_agent::type_id::create("m_mem_agent", this);
    //   `uvm_info("VORTEX_ENV", "Memory agent created", UVM_MEDIUM)
    // end


    if (cfg.axi_agent_enable) begin
      m_axi_agent = axi_agent::type_id::create("m_axi_agent", this);
      `uvm_info("VORTEX_ENV", "AXI agent created", UVM_MEDIUM)
    end

    if (cfg.dcr_agent_enable) begin
      m_dcr_agent = dcr_agent::type_id::create("m_dcr_agent", this);
      `uvm_info("VORTEX_ENV", "DCR agent created", UVM_MEDIUM)
    end

    if (cfg.host_agent_enable) begin
      m_host_agent = host_agent::type_id::create("m_host_agent", this);
      `uvm_info("VORTEX_ENV", "Host agent created", UVM_MEDIUM)
    end

    if (cfg.status_agent_enable) begin
      m_status_agent = status_agent::type_id::create("m_status_agent", this);
      `uvm_info("VORTEX_ENV", "Status agent created", UVM_MEDIUM)
    end

    // Create virtual sequencer
    m_virtual_sequencer = vortex_virtual_sequencer::type_id::create("m_virtual_sequencer", this);
    `uvm_info("VORTEX_ENV", "Virtual sequencer created", UVM_MEDIUM)

    /* COMMENTED OUT FOR INITIAL TESTING
    // Create scoreboard if enabled
    if (cfg.enable_scoreboard) begin
      m_scoreboard = vortex_scoreboard::type_id::create("m_scoreboard", this);
      `uvm_info("VORTEX_ENV", "Scoreboard created", UVM_MEDIUM)
    end

    // Create coverage collector if enabled
    if (cfg.enable_coverage) begin
      m_coverage = vortex_coverage::type_id::create("m_coverage", this);
      `uvm_info("VORTEX_ENV", "Coverage collector created", UVM_MEDIUM)
    end
    */

    `uvm_info("VORTEX_ENV", "Environment build complete (minimal version)", UVM_LOW)

  endfunction : build_phase

  //==========================================================================
  // Connect Phase
  //==========================================================================
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);


    // // Connect agent sequencers to virtual sequencer
    // if (m_mem_agent != null && m_mem_agent.m_sequencer != null) begin
    //   m_virtual_sequencer.m_mem_sequencer = m_mem_agent.m_sequencer;
    // end
    
    // Connect agent sequencers to virtual sequencer (only if ACTIVE)
    if (m_mem_agent != null && m_mem_agent.get_is_active() == UVM_ACTIVE && m_mem_agent.m_sequencer != null) begin
      m_virtual_sequencer.m_mem_sequencer = m_mem_agent.m_sequencer;
    end


    if (m_axi_agent != null && m_axi_agent.m_sequencer != null) begin
      m_virtual_sequencer.m_axi_sequencer = m_axi_agent.m_sequencer;
    end

    if (m_dcr_agent != null && m_dcr_agent.m_sequencer != null) begin
      m_virtual_sequencer.m_dcr_sequencer = m_dcr_agent.m_sequencer;
    end

    if (m_host_agent != null && m_host_agent.m_sequencer != null) begin
      m_virtual_sequencer.m_host_sequencer = m_host_agent.m_sequencer;
    end

    /* COMMENTED OUT FOR INITIAL TESTING
    // Connect agent analysis ports to scoreboard
    if (m_scoreboard != null) begin
      if (m_mem_agent != null) m_mem_agent.ap.connect(m_scoreboard.mem_export);
      if (m_axi_agent != null) m_axi_agent.ap.connect(m_scoreboard.axi_export);
      if (m_dcr_agent != null) m_dcr_agent.ap.connect(m_scoreboard.dcr_export);
      if (m_host_agent != null) m_host_agent.ap.connect(m_scoreboard.host_export);
      if (m_status_agent != null) m_status_agent.ap.connect(m_scoreboard.status_export);
    end

    // Connect to coverage collector
    if (m_coverage != null) begin
      if (m_mem_agent != null) m_mem_agent.ap.connect(m_coverage.mem_export);
      // ... etc
    end
    */

  endfunction : connect_phase

  //==========================================================================
  // End of Elaboration Phase
  //==========================================================================
  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    
    `uvm_info("VORTEX_ENV", {"\n",
      "========================================\n",
      " Vortex UVM Environment (Minimal)\n",
      "========================================\n",
      $sformatf(" Config: %s\n", cfg.get_config_string()),
      $sformatf(" Mem Agent: %s\n", m_mem_agent != null ? "✓" : "✗"),
      $sformatf(" AXI Agent: %s\n", m_axi_agent != null ? "✓" : "✗"),
      $sformatf(" DCR Agent: %s\n", m_dcr_agent != null ? "✓" : "✗"),
      $sformatf(" Host Agent: %s\n", m_host_agent != null ? "✓" : "✗"),
      $sformatf(" Status Agent: %s\n", m_status_agent != null ? "✓" : "✗"),
      $sformatf(" Virtual Sequencer: %s\n", m_virtual_sequencer != null ? "✓" : "✗"),
      " Scoreboard: DISABLED\n",
      " Coverage: DISABLED\n",
      "========================================\n"
    }, UVM_LOW)
  endfunction : end_of_elaboration_phase

  //==========================================================================
  // Report Phase
  //==========================================================================
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    
    `uvm_info("VORTEX_ENV", "Environment testing complete (agents only)", UVM_LOW)

    /* COMMENTED OUT FOR INITIAL TESTING
    if (m_scoreboard != null) m_scoreboard.report_results();
    if (m_coverage != null) m_coverage.report_coverage();
    */

  endfunction : report_phase

endclass : vortex_env

`endif // VORTEX_ENV_SV


////////////////////////////////////////////////////////////////////////////////

// `ifndef VORTEX_ENV_SV
// `define VORTEX_ENV_SV

// import uvm_pkg::*;
// `include "uvm_macros.svh"
// import vortex_config_pkg::*;

// // Import all agent packages
// import mem_agent_pkg::*;
// import axi_agent_pkg::*;
// import dcr_agent_pkg::*;
// import host_agent_pkg::*;
// import status_agent_pkg::*;

// class vortex_env extends uvm_env;
//     `uvm_component_utils(vortex_env)
    
//     //==========================================================================
//     // Configuration Object
//     // Single source of truth for entire testbench
//     //==========================================================================
//     vortex_config cfg;
    
//     //==========================================================================
//     // UVM Agents
//     //==========================================================================
//     mem_agent    mem_agent;      // Custom memory interface (ACTIVE)
//     axi_agent    axi_agent;      // AXI4 interface (ACTIVE)
//     dcr_agent    dcr_agent;      // Device Configuration Registers (ACTIVE)
//     host_agent   host_agent;     // High-level host operations (ACTIVE)
//     status_agent status_agent;   // Execution status monitoring (PASSIVE)
    
//     //==========================================================================
//     // Virtual Sequencer
//     // Provides centralized access to all agent sequencers
//     //==========================================================================
//     vortex_virtual_sequencer virtual_sequencer;
    
//     //==========================================================================
//     // Coverage Collector
//     // Collects functional coverage from all agents
//     //==========================================================================
//     vortex_coverage_collector coverage_collector;
    
//     //==========================================================================
//     // Scoreboard (Placeholder - will be added after DPI-C wrapper)
//     //==========================================================================
//     // vortex_scoreboard scoreboard;
    
//     //==========================================================================
//     // Constructor
//     //==========================================================================
//     function new(string name = "vortex_env", uvm_component parent = null);
//         super.new(name, parent);
//     endfunction
    
//     //==========================================================================
//     // Build Phase
//     // Create all environment components
//     //==========================================================================
//     virtual function void build_phase(uvm_phase phase);
//         super.build_phase(phase);
        
//         `uvm_info("VORTEX_ENV", "Building Vortex UVM Environment...", UVM_LOW)
        
//         //----------------------------------------------------------------------
//         // Get Configuration Object
//         //----------------------------------------------------------------------
//         if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
//             `uvm_info("VORTEX_ENV", "No config found - creating default", UVM_MEDIUM)
//             cfg = vortex_config::type_id::create("cfg");
//             cfg.set_defaults_from_vx_config();
//             cfg.apply_plusargs();
//         end
        
//         // Store configuration for child components
//         uvm_config_db#(vortex_config)::set(this, "*", "cfg", cfg);
        
//         // Print configuration summary
//         cfg.print_config(UVM_MEDIUM);
        
//         //----------------------------------------------------------------------
//         // Create Agents (Based on Configuration)
//         //----------------------------------------------------------------------
        
//         // Memory Agent (Always enabled)
//         if (cfg.mem_agent_enable) begin
//             `uvm_info("VORTEX_ENV", "Creating mem_agent (ACTIVE)", UVM_MEDIUM)
//             mem_agent = mem_agent::type_id::create("mem_agent", this);
            
//             if (cfg.mem_agent_is_active)
//                 mem_agent.set_is_active(UVM_ACTIVE);
//             else
//                 mem_agent.set_is_active(UVM_PASSIVE);
//         end
        
//         // AXI Agent (Configurable - ACTIVE when enabled)
//         if (cfg.axi_agent_enable) begin
//             `uvm_info("VORTEX_ENV", "Creating axi_agent (ACTIVE)", UVM_MEDIUM)
//             axi_agent = axi_agent::type_id::create("axi_agent", this);
            
//             if (cfg.axi_agent_is_active)
//                 axi_agent.set_is_active(UVM_ACTIVE);
//             else
//                 axi_agent.set_is_active(UVM_PASSIVE);
//         end
        
//         // DCR Agent (Always enabled)
//         if (cfg.dcr_agent_enable) begin
//             `uvm_info("VORTEX_ENV", "Creating dcr_agent (ACTIVE)", UVM_MEDIUM)
//             dcr_agent = dcr_agent::type_id::create("dcr_agent", this);
            
//             if (cfg.dcr_agent_is_active)
//                 dcr_agent.set_is_active(UVM_ACTIVE);
//             else
//                 dcr_agent.set_is_active(UVM_PASSIVE);
//         end
        
//         // Host Agent (Always enabled)
//         if (cfg.host_agent_enable) begin
//             `uvm_info("VORTEX_ENV", "Creating host_agent (ACTIVE)", UVM_MEDIUM)
//             host_agent = host_agent::type_id::create("host_agent", this);
            
//             if (cfg.host_agent_is_active)
//                 host_agent.set_is_active(UVM_ACTIVE);
//             else
//                 host_agent.set_is_active(UVM_PASSIVE);
//         end
        
//         // Status Agent (Always passive)
//         if (cfg.status_agent_enable) begin
//             `uvm_info("VORTEX_ENV", "Creating status_agent (PASSIVE)", UVM_MEDIUM)
//             status_agent = status_agent::type_id::create("status_agent", this);
//             status_agent.set_is_active(UVM_PASSIVE);
//         end
        
//         //----------------------------------------------------------------------
//         // Create Virtual Sequencer (if any agent is active)
//         //----------------------------------------------------------------------
//         if (cfg.mem_agent_is_active || cfg.axi_agent_is_active || 
//             cfg.dcr_agent_is_active || cfg.host_agent_is_active) begin
//             `uvm_info("VORTEX_ENV", "Creating virtual_sequencer", UVM_MEDIUM)
//             virtual_sequencer = vortex_virtual_sequencer::type_id::create("virtual_sequencer", this);
//         end
        
//         //----------------------------------------------------------------------
//         // Create Coverage Collector
//         //----------------------------------------------------------------------
//         if (cfg.enable_coverage) begin
//             `uvm_info("VORTEX_ENV", "Creating coverage_collector", UVM_MEDIUM)
//             coverage_collector = vortex_coverage_collector::type_id::create("coverage_collector", this);
//         end
        
//         //----------------------------------------------------------------------
//         // Create Scoreboard (Placeholder - will be enabled after DPI-C)
//         //----------------------------------------------------------------------
//         // if (cfg.enable_scoreboard) begin
//         //     `uvm_info("VORTEX_ENV", "Creating scoreboard", UVM_MEDIUM)
//         //     scoreboard = vortex_scoreboard::type_id::create("scoreboard", this);
//         // end
        
//     endfunction : build_phase
    
//     //==========================================================================
//     // Connect Phase
//     // Connect all analysis ports between components
//     //==========================================================================
//     virtual function void connect_phase(uvm_phase phase);
//         super.connect_phase(phase);
        
//         `uvm_info("VORTEX_ENV", "Connecting Vortex UVM Environment...", UVM_LOW)
        
//         //----------------------------------------------------------------------
//         // Connect Virtual Sequencer to Agent Sequencers
//         //----------------------------------------------------------------------
//         if (virtual_sequencer != null) begin
            
//             // Connect mem_sequencer
//             if (mem_agent != null && mem_agent.m_sequencer != null) begin
//                 virtual_sequencer.mem_sequencer = mem_agent.m_sequencer;
//                 `uvm_info("VORTEX_ENV", "Connected mem_sequencer to virtual_sequencer", UVM_MEDIUM)
//             end
            
//             // Connect axi_sequencer
//             if (axi_agent != null && axi_agent.m_sequencer != null) begin
//                 virtual_sequencer.axi_sequencer = axi_agent.m_sequencer;
//                 `uvm_info("VORTEX_ENV", "Connected axi_sequencer to virtual_sequencer", UVM_MEDIUM)
//             end
            
//             // Connect dcr_sequencer
//             if (dcr_agent != null && dcr_agent.m_sequencer != null) begin
//                 virtual_sequencer.dcr_sequencer = dcr_agent.m_sequencer;
//                 `uvm_info("VORTEX_ENV", "Connected dcr_sequencer to virtual_sequencer", UVM_MEDIUM)
//             end
            
//             // Connect host_sequencer
//             if (host_agent != null && host_agent.m_sequencer != null) begin
//                 virtual_sequencer.host_sequencer = host_agent.m_sequencer;
//                 `uvm_info("VORTEX_ENV", "Connected host_sequencer to virtual_sequencer", UVM_MEDIUM)
//             end
//         end
        
//         //----------------------------------------------------------------------
//         // Connect Coverage Collector to Agent Monitors
//         //----------------------------------------------------------------------
//         if (coverage_collector != null) begin
            
//             // Connect mem_agent monitor
//             if (mem_agent != null && mem_agent.m_monitor != null) begin
//                 mem_agent.m_monitor.ap.connect(coverage_collector.mem_imp);
//                 `uvm_info("VORTEX_ENV", "Connected mem_monitor to coverage_collector", UVM_MEDIUM)
//             end
            
//             // Connect axi_agent monitor
//             if (axi_agent != null && axi_agent.m_monitor != null) begin
//                 axi_agent.m_monitor.ap.connect(coverage_collector.axi_imp);
//                 `uvm_info("VORTEX_ENV", "Connected axi_monitor to coverage_collector", UVM_MEDIUM)
//             end
            
//             // Connect dcr_agent monitor
//             if (dcr_agent != null && dcr_agent.m_monitor != null) begin
//                 dcr_agent.m_monitor.ap.connect(coverage_collector.dcr_imp);
//                 `uvm_info("VORTEX_ENV", "Connected dcr_monitor to coverage_collector", UVM_MEDIUM)
//             end
            
//             // Connect host_agent monitor
//             if (host_agent != null && host_agent.m_monitor != null) begin
//                 host_agent.m_monitor.ap.connect(coverage_collector.host_imp);
//                 `uvm_info("VORTEX_ENV", "Connected host_monitor to coverage_collector", UVM_MEDIUM)
//             end
            
//             // Connect status_agent monitor
//             if (status_agent != null && status_agent.m_monitor != null) begin
//                 status_agent.m_monitor.ap.connect(coverage_collector.status_imp);
//                 `uvm_info("VORTEX_ENV", "Connected status_monitor to coverage_collector", UVM_MEDIUM)
//             end
//         end
        
//         //----------------------------------------------------------------------
//         // Connect Scoreboard (Placeholder - will be enabled after DPI-C)
//         //----------------------------------------------------------------------
//         // if (scoreboard != null) begin
//         //     // Connect mem_agent monitor to scoreboard
//         //     if (mem_agent != null && mem_agent.m_monitor != null)
//         //         mem_agent.m_monitor.ap.connect(scoreboard.mem_imp);
//         //     
//         //     // Connect status_agent monitor to scoreboard
//         //     if (status_agent != null && status_agent.m_monitor != null)
//         //         status_agent.m_monitor.ap.connect(scoreboard.status_imp);
//         //     
//         //     // Connect host_agent monitor to scoreboard
//         //     if (host_agent != null && host_agent.m_monitor != null)
//         //         host_agent.m_monitor.ap.connect(scoreboard.host_imp);
//         //     
//         //     // Connect dcr_agent monitor to scoreboard
//         //     if (dcr_agent != null && dcr_agent.m_monitor != null)
//         //         dcr_agent.m_monitor.ap.connect(scoreboard.dcr_imp);
//         // end
        
//     endfunction : connect_phase
    
//     //==========================================================================
//     // End of Elaboration Phase
//     // Print environment topology
//     //==========================================================================
//     virtual function void end_of_elaboration_phase(uvm_phase phase);
//         super.end_of_elaboration_phase(phase);
        
//         `uvm_info("VORTEX_ENV", {"\n",
//             "================================================================================\n",
//             "                    VORTEX UVM ENVIRONMENT TOPOLOGY\n",
//             "================================================================================\n",
//             "\n",
//             "  Configuration:\n",
//             $sformatf("    • Cores:          %0d\n", cfg.num_cores),
//             $sformatf("    • Warps:          %0d\n", cfg.num_warps),
//             $sformatf("    • Threads:        %0d\n", cfg.num_threads),
//             $sformatf("    • XLEN:           %0d\n", cfg.xlen),
//             $sformatf("    • I$ Enable:      %s\n", cfg.icache_enable ? "YES" : "NO"),
//             $sformatf("    • D$ Enable:      %s\n", cfg.dcache_enable ? "YES" : "NO"),
//             $sformatf("    • L2 Enable:      %s\n", cfg.l2_enable ? "YES" : "NO"),
//             "\n",
//             "  Active Agents:\n",
//             $sformatf("    • mem_agent:      %s\n", 
//                 (mem_agent != null) ? (mem_agent.get_is_active() == UVM_ACTIVE ? "ACTIVE" : "PASSIVE") : "DISABLED"),
//             $sformatf("    • axi_agent:      %s\n", 
//                 (axi_agent != null) ? (axi_agent.get_is_active() == UVM_ACTIVE ? "ACTIVE" : "PASSIVE") : "DISABLED"),
//             $sformatf("    • dcr_agent:      %s\n", 
//                 (dcr_agent != null) ? (dcr_agent.get_is_active() == UVM_ACTIVE ? "ACTIVE" : "PASSIVE") : "DISABLED"),
//             $sformatf("    • host_agent:     %s\n", 
//                 (host_agent != null) ? (host_agent.get_is_active() == UVM_ACTIVE ? "ACTIVE" : "PASSIVE") : "DISABLED"),
//             $sformatf("    • status_agent:   %s\n", 
//                 (status_agent != null) ? "PASSIVE" : "DISABLED"),
//             "\n",
//             "  Environment Components:\n",
//             $sformatf("    • virtual_sequencer:   %s\n", virtual_sequencer != null ? "✓" : "✗"),
//             $sformatf("    • coverage_collector:  %s\n", coverage_collector != null ? "✓" : "✗"),
//             $sformatf("    • scoreboard:          %s\n", "✗ (pending DPI-C wrapper)"),
//             "\n",
//             "  Interfaces:\n",
//             "    • vortex_mem_if     (Custom Memory)\n",
//             "    • vortex_axi_if     (AXI4)\n",
//             "    • vortex_dcr_if     (Device Config Registers)\n",
//             "    • vortex_if         (Host Interface)\n",
//             "    • vortex_status_if  (Status Monitoring)\n",
//             "\n",
//             "================================================================================"
//         }, UVM_LOW)
        
//         // Optional: Print full testbench hierarchy
//         if (cfg.default_verbosity >= UVM_HIGH) begin
//             uvm_top.print_topology();
//         end
//     endfunction : end_of_elaboration_phase
    
//     //==========================================================================
//     // Run Phase
//     // Monitor environment health
//     //==========================================================================
//     virtual task run_phase(uvm_phase phase);
//         super.run_phase(phase);
        
//         `uvm_info("VORTEX_ENV", "Vortex UVM Environment running...", UVM_LOW)
        
//         // Optional: Implement timeout watchdog
//         if (cfg.global_timeout_cycles > 0) begin
//             fork
//                 begin
//                     // Wait for timeout
//                     repeat(cfg.global_timeout_cycles) @(posedge mem_agent.mem_vif.clk);
//                     `uvm_error("VORTEX_ENV", $sformatf(
//                         "Global timeout reached after %0d cycles!", 
//                         cfg.global_timeout_cycles))
//                 end
//             join_none
//         end
//     endtask : run_phase
    
//     //==========================================================================
//     // Extract Phase
//     // Collect final statistics
//     //==========================================================================
//     virtual function void extract_phase(uvm_phase phase);
//         super.extract_phase(phase);
        
//         `uvm_info("VORTEX_ENV", "Extracting final statistics...", UVM_MEDIUM)
//     endfunction : extract_phase
    
//     //==========================================================================
//     // Report Phase
//     // Print final environment summary
//     //==========================================================================
//     virtual function void report_phase(uvm_phase phase);
//         super.report_phase(phase);
        
//         `uvm_info("VORTEX_ENV", {"\n",
//             "================================================================================\n",
//             "                    VORTEX UVM ENVIRONMENT SUMMARY\n",
//             "================================================================================\n",
//             "\n",
//             "  Environment Status:     COMPLETED\n",
//             "\n",
//             "  Component Reports:\n",
//             "    See individual agent/scoreboard/coverage reports above\n",
//             "\n",
//             "================================================================================"
//         }, UVM_LOW)
//     endfunction : report_phase
    
// endclass : vortex_env

// `endif // VORTEX_ENV_SV
