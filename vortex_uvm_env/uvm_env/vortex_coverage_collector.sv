////////////////////////////////////////////////////////////////////////////////
// File: vortex_coverage_collector.sv
// Description: Functional Coverage Collector for Vortex GPGPU
//
// This component collects functional coverage by subscribing to transactions
// from all agent monitors. It tracks:
//   - Memory operations (reads, writes, burst sizes)
//   - AXI transactions (burst types, sizes, responses)
//   - DCR configurations (startup address, performance counters)
//   - Host operations (program loading, kernel launches)
//   - Execution status (warps, threads, stalls, IPC)
//
// Coverage Goals:
//   ✓ Operation types and combinations
//   ✓ Configuration parameter coverage
//   ✓ Performance scenarios (high IPC, stalls, cache misses)
//   ✓ Cross-coverage between interfaces
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_COVERAGE_COLLECTOR_SV
`define VORTEX_COVERAGE_COLLECTOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import vortex_config_pkg::*;

// Import transaction types from agent packages
import mem_agent_pkg::*;
import axi_agent_pkg::*;
import dcr_agent_pkg::*;
import host_agent_pkg::*;
import status_agent_pkg::*;


class vortex_coverage_collector extends uvm_component;
    `uvm_component_utils(vortex_coverage_collector)
    
    //==========================================================================
    // Analysis Imports (Subscribe to All Agents)
    // NOTE: Using separate `uvm_analysis_imp_decl` macros for each type
    //==========================================================================
    
    // Declare analysis import types
    `uvm_analysis_imp_decl(_mem)
    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_dcr)
    `uvm_analysis_imp_decl(_host)
    `uvm_analysis_imp_decl(_status)
    
    // Analysis imports
    uvm_analysis_imp_mem    #(mem_transaction, vortex_coverage_collector)    mem_imp;
    uvm_analysis_imp_axi    #(axi_transaction, vortex_coverage_collector)    axi_imp;
    uvm_analysis_imp_dcr    #(dcr_transaction, vortex_coverage_collector)    dcr_imp;
    uvm_analysis_imp_host   #(host_transaction, vortex_coverage_collector)   host_imp;
    uvm_analysis_imp_status #(status_transaction, vortex_coverage_collector) status_imp;
    
    //==========================================================================
    // Configuration
    //==========================================================================
    vortex_config cfg;
    
    //==========================================================================
    // Current Transaction Samples (for coverage)
    //==========================================================================
    mem_transaction    current_mem_trans;
    axi_transaction    current_axi_trans;
    dcr_transaction    current_dcr_trans;
    host_transaction   current_host_trans;
    status_transaction current_status_trans;
    
    //==========================================================================
    // Coverage Groups
    //==========================================================================
    
    // Memory Operation Coverage
    covergroup mem_operation_cg;
        option.per_instance = 1;
        
        cp_rw: coverpoint current_mem_trans.rw {
            bins read  = {0};
            bins write = {1};
        }
        
        cp_byteen: coverpoint current_mem_trans.byteen {
            bins byte_0    = {4'b0001};
            bins byte_1    = {4'b0010};
            bins byte_2    = {4'b0100};
            bins byte_3    = {4'b1000};
            bins halfword  = {4'b0011, 4'b1100};
            bins word      = {4'b1111};
            bins sparse[]  = default;
        }
        
        cp_addr_align: coverpoint current_mem_trans.addr[1:0] {
            bins aligned   = {2'b00};
            bins unaligned = {2'b01, 2'b10, 2'b11};
        }
        
        cross_rw_byteen: cross cp_rw, cp_byteen;
    endgroup
    
    // AXI Transaction Coverage
    covergroup axi_transaction_cg;
        option.per_instance = 1;
        
        cp_burst: coverpoint current_axi_trans.burst {
            bins fixed = {0};
            bins incr  = {1};
            bins wrap  = {2};
        }
        
        cp_size: coverpoint current_axi_trans.size {
            bins Byte     = {0};
            bins halfword = {1};
            bins word     = {2};
            bins dword    = {3};
            bins larger[] = {[4:7]};
        }
        
        cp_len: coverpoint current_axi_trans.len {
            bins single   = {0};
            bins short[]  = {[1:3]};
            bins Medium[] = {[4:15]};
            bins long[]   = {[16:255]};
        }
        
        cp_resp: coverpoint current_axi_trans.resp {
            bins okay   = {0};
            bins exokay = {1};
            bins slverr = {2};
            bins decerr = {3};
        }
        
        cross_burst_size_len: cross cp_burst, cp_size, cp_len;
    endgroup
    
    // DCR Configuration Coverage
    covergroup dcr_config_cg;
        option.per_instance = 1;
        
        cp_addr: coverpoint current_dcr_trans.addr {
            bins startup_addr0 = {12'h001};
            bins startup_addr1 = {12'h002};
            bins argv_ptr0     = {12'h003};
            bins argv_ptr1     = {12'h004};
            bins mpm_class     = {12'h005};
            bins other[]       = default;
        }
    endgroup
    
    // Host Operation Coverage
    covergroup host_operation_cg;
        option.per_instance = 1;
        
        cp_op_type: coverpoint current_host_trans.op_type {
            bins reset          = {host_transaction::HOST_RESET};
            bins load_program   = {host_transaction::HOST_LOAD_PROGRAM};
            bins configure_dcr  = {host_transaction::HOST_CONFIGURE_DCR};
            bins launch_kernel  = {host_transaction::HOST_LAUNCH_KERNEL};
            bins wait_done      = {host_transaction::HOST_WAIT_DONE};
            bins read_result    = {host_transaction::HOST_READ_RESULT};
        }
        
        cp_completion: coverpoint current_host_trans.completion_flag 
            iff (current_host_trans.op_type == host_transaction::HOST_WAIT_DONE) {
            bins completed = {1};
            bins timeout   = {0};
        }
    endgroup
    
    // Status/Performance Coverage
    covergroup status_performance_cg;
        option.per_instance = 1;
        
        cp_busy: coverpoint current_status_trans.busy {
            bins idle = {0};
            bins busy = {1};
        }
        
        cp_ipc: coverpoint current_status_trans.ipc {
            bins zero      = {[0.0:0.01]};
            bins very_low  = {[0.01:0.25]};
            bins low       = {[0.25:0.5]};
            bins Medium    = {[0.5:0.75]};
            bins high      = {[0.75:1.0]};
            bins very_high = {[1.0:4.0]};
        }
    endgroup
    
    //==========================================================================
    // Constructor
    //==========================================================================
    function new(string name = "vortex_coverage_collector", uvm_component parent = null);
        super.new(name, parent);
        
        // Create analysis imports
        mem_imp    = new("mem_imp", this);
        axi_imp    = new("axi_imp", this);
        dcr_imp    = new("dcr_imp", this);
        host_imp   = new("host_imp", this);
        status_imp = new("status_imp", this);
        
        // Create coverage groups
        mem_operation_cg     = new();
        axi_transaction_cg   = new();
        dcr_config_cg        = new();
        host_operation_cg    = new();
        status_performance_cg = new();
    endfunction
    
    //==========================================================================
    // Build Phase
    //==========================================================================
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("COVERAGE", "No vortex_config found", UVM_MEDIUM)
        end
    endfunction
    
    //==========================================================================
    // Write Methods (Called by Agent Monitors via analysis_imp)
    //==========================================================================
    
    virtual function void write_mem(mem_transaction trans);
        if (!cfg.enable_coverage) return;
        
        current_mem_trans = trans;
        mem_operation_cg.sample();
        
        `uvm_info("COVERAGE", "Sampled memory transaction", UVM_DEBUG)
    endfunction
    
    virtual function void write_axi(axi_transaction trans);
        if (!cfg.enable_coverage) return;
        
        current_axi_trans = trans;
        axi_transaction_cg.sample();
        
        `uvm_info("COVERAGE", "Sampled AXI transaction", UVM_DEBUG)
    endfunction
    
    virtual function void write_dcr(dcr_transaction trans);
        if (!cfg.enable_coverage) return;
        
        current_dcr_trans = trans;
        dcr_config_cg.sample();
        
        `uvm_info("COVERAGE", "Sampled DCR transaction", UVM_DEBUG)
    endfunction
    
    virtual function void write_host(host_transaction trans);
        if (!cfg.enable_coverage) return;
        
        current_host_trans = trans;
        host_operation_cg.sample();
        
        `uvm_info("COVERAGE", "Sampled host transaction", UVM_DEBUG)
    endfunction
    
    virtual function void write_status(status_transaction trans);
        if (!cfg.enable_coverage) return;
        
        current_status_trans = trans;
        status_performance_cg.sample();
        
        `uvm_info("COVERAGE", "Sampled status transaction", UVM_DEBUG)
    endfunction
    
    //==========================================================================
    // Report Phase
    //==========================================================================
    virtual function void report_phase(uvm_phase phase);
        real mem_cov, axi_cov, dcr_cov, host_cov, status_cov;
        real total_cov;
        
        super.report_phase(phase);
        
        if (!cfg.enable_coverage) return;
        
        // Get coverage percentages
        mem_cov    = mem_operation_cg.get_coverage();
        axi_cov    = axi_transaction_cg.get_coverage();
        dcr_cov    = dcr_config_cg.get_coverage();
        host_cov   = host_operation_cg.get_coverage();
        status_cov = status_performance_cg.get_coverage();
        
        // Calculate average
        total_cov = (mem_cov + axi_cov + dcr_cov + host_cov + status_cov) / 5.0;
        
        `uvm_info("COVERAGE", {"\n",
            "========================================\n",
            "    Functional Coverage Report\n",
            "========================================\n",
            $sformatf("  Memory Operations:    %.2f%%\n", mem_cov),
            $sformatf("  AXI Transactions:     %.2f%%\n", axi_cov),
            $sformatf("  DCR Configuration:    %.2f%%\n", dcr_cov),
            $sformatf("  Host Operations:      %.2f%%\n", host_cov),
            $sformatf("  Status/Performance:   %.2f%%\n", status_cov),
            "----------------------------------------\n",
            $sformatf("  TOTAL COVERAGE:       %.2f%%\n", total_cov),
            "========================================"
        }, UVM_LOW)
    endfunction
    
endclass : vortex_coverage_collector


`endif // VORTEX_COVERAGE_COLLECTOR_SV









// `ifndef VORTEX_COVERAGE_COLLECTOR_SV
// `define VORTEX_COVERAGE_COLLECTOR_SV

// import uvm_pkg::*;
// `include "uvm_macros.svh"
// import vortex_config_pkg::*;

// // Import transaction types from agent packages
// import mem_agent_pkg::*;
// import axi_agent_pkg::*;
// import dcr_agent_pkg::*;
// import host_agent_pkg::*;
// import status_agent_pkg::*;

// class vortex_coverage_collector extends uvm_subscriber #(uvm_sequence_item);
//     `uvm_component_utils(vortex_coverage_collector)
    
//     //==========================================================================
//     // Analysis Imports (Subscribe to All Agents)
//     //==========================================================================
//     uvm_analysis_imp_mem    #(mem_transaction, vortex_coverage_collector)    mem_imp;
//     uvm_analysis_imp_axi    #(axi_transaction, vortex_coverage_collector)    axi_imp;
//     uvm_analysis_imp_dcr    #(dcr_transaction, vortex_coverage_collector)    dcr_imp;
//     uvm_analysis_imp_host   #(host_transaction, vortex_coverage_collector)   host_imp;
//     uvm_analysis_imp_status #(status_transaction, vortex_coverage_collector) status_imp;
    
//     //==========================================================================
//     // Configuration
//     //==========================================================================
//     vortex_config cfg;
    
//     //==========================================================================
//     // Current Transaction Samples
//     // Used for cross-coverage
//     //==========================================================================
//     mem_transaction    current_mem_trans;
//     axi_transaction    current_axi_trans;
//     dcr_transaction    current_dcr_trans;
//     host_transaction   current_host_trans;
//     status_transaction current_status_trans;
    
//     //==========================================================================
//     // Coverage Groups
//     //==========================================================================
    
//     // Memory Operation Coverage
//     covergroup mem_operation_cg;
//         option.per_instance = 1;
        
//         // Operation type
//         cp_rw: coverpoint current_mem_trans.req_rw {
//             bins read  = {0};
//             bins write = {1};
//         }
        
//         // Byte enable patterns
//         cp_byteen: coverpoint current_mem_trans.req_byteen {
//             bins byte_0    = {4'b0001};
//             bins byte_1    = {4'b0010};
//             bins byte_2    = {4'b0100};
//             bins byte_3    = {4'b1000};
//             bins halfword  = {4'b0011, 4'b1100};
//             bins word      = {4'b1111};
//             bins sparse[]  = default;
//         }
        
//         // Address alignment
//         cp_addr_align: coverpoint current_mem_trans.req_addr[1:0] {
//             bins aligned   = {2'b00};
//             bins unaligned = {2'b01, 2'b10, 2'b11};
//         }
        
//         // Cross coverage
//         cross_rw_byteen: cross cp_rw, cp_byteen;
//     endgroup
    
//     // AXI Transaction Coverage
//     covergroup axi_transaction_cg;
//         option.per_instance = 1;
        
//         // Burst type
//         cp_burst: coverpoint current_axi_trans.burst {
//             bins fixed = {0};
//             bins incr  = {1};
//             bins wrap  = {2};
//         }
        
//         // Burst size
//         cp_size: coverpoint current_axi_trans.size {
//             bins byte     = {0};
//             bins halfword = {1};
//             bins word     = {2};
//             bins dword    = {3};
//             bins larger[] = {[4:7]};
//         }
        
//         // Burst length
//         cp_len: coverpoint current_axi_trans.len {
//             bins single   = {0};
//             bins short[]  = {[1:3]};
//             bins medium[] = {[4:15]};
//             bins long[]   = {[16:255]};
//         }
        
//         // Response
//         cp_resp: coverpoint current_axi_trans.resp {
//             bins okay   = {0};
//             bins exokay = {1};
//             bins slverr = {2};
//             bins decerr = {3};
//         }
        
//         // Cross coverage
//         cross_burst_size_len: cross cp_burst, cp_size, cp_len;
//     endgroup
    
//     // DCR Configuration Coverage
//     covergroup dcr_config_cg;
//         option.per_instance = 1;
        
//         // DCR address ranges
//         cp_addr: coverpoint current_dcr_trans.addr {
//             bins startup_addr0 = {dcr_transaction::DCR_STARTUP_ADDR0};
//             bins startup_addr1 = {dcr_transaction::DCR_STARTUP_ADDR1};
//             bins argv_ptr0     = {dcr_transaction::DCR_ARGV_PTR0};
//             bins argv_ptr1     = {dcr_transaction::DCR_ARGV_PTR1};
//             bins mpm_class     = {dcr_transaction::DCR_MPM_CLASS};
//             bins other[]       = default;
//         }
        
//         // Startup address alignment (lower 32-bit word)
//         cp_startup_align: coverpoint current_dcr_trans.data[1:0] 
//             iff (current_dcr_trans.addr == dcr_transaction::DCR_STARTUP_ADDR0) {
//             bins aligned   = {2'b00};
//             bins unaligned = {2'b01, 2'b10, 2'b11};
//         }
//     endgroup
    
//     // Host Operation Coverage
//     covergroup host_operation_cg;
//         option.per_instance = 1;
        
//         // Operation type
//         cp_op_type: coverpoint current_host_trans.op_type {
//             bins reset          = {host_transaction::HOST_RESET};
//             bins load_program   = {host_transaction::HOST_LOAD_PROGRAM};
//             bins configure_dcr  = {host_transaction::HOST_CONFIGURE_DCR};
//             bins launch_kernel  = {host_transaction::HOST_LAUNCH_KERNEL};
//             bins wait_done      = {host_transaction::HOST_WAIT_DONE};
//             bins read_result    = {host_transaction::HOST_READ_RESULT};
//         }
        
//         // Kernel configuration
//         cp_num_cores: coverpoint current_host_trans.num_cores 
//             iff (current_host_trans.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
//             bins single = {1};
//             bins small  = {[2:4]};
//             bins large  = {[5:8]};
//         }
        
//         cp_num_warps: coverpoint current_host_trans.num_warps 
//             iff (current_host_trans.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
//             bins low  = {[1:2]};
//             bins mid  = {[3:4]};
//             bins high = {[5:8]};
//         }
        
//         // Completion status
//         cp_completion: coverpoint current_host_trans.completion_flag 
//             iff (current_host_trans.op_type == host_transaction::HOST_WAIT_DONE) {
//             bins completed = {1};
//             bins timeout   = {0};
//         }
        
//         // Cross coverage
//         cross_cores_warps: cross cp_num_cores, cp_num_warps;
//     endgroup
    
//     // Status/Performance Coverage
//     covergroup status_performance_cg;
//         option.per_instance = 1;
        
//         // Execution state
//         cp_busy: coverpoint current_status_trans.busy {
//             bins idle = {0};
//             bins busy = {1};
//         }
        
//         // IPC bins
//         cp_ipc: coverpoint current_status_trans.ipc {
//             bins zero      = {[0.0:0.01]};
//             bins very_low  = {[0.01:0.25]};
//             bins low       = {[0.25:0.5]};
//             bins medium    = {[0.5:0.75]};
//             bins high      = {[0.75:1.0]};
//             bins very_high = {[1.0:4.0]};
//         }
        
//         // Stall conditions
//         cp_fetch_stall: coverpoint current_status_trans.fetch_stall;
//         cp_memory_stall: coverpoint current_status_trans.memory_stall;
        
//         // Active warps
//         cp_active_warps: coverpoint current_status_trans.count_active_warps() {
//             bins none   = {0};
//             bins few    = {[1:2]};
//             bins some   = {[3:4]};
//             bins many[] = {[5:8]};
//         }
        
//         // Cross coverage
//         cross_ipc_stalls: cross cp_ipc, cp_fetch_stall, cp_memory_stall;
//     endgroup
    
//     //==========================================================================
//     // Constructor
//     //==========================================================================
//     function new(string name = "vortex_coverage_collector", uvm_component parent = null);
//         super.new(name, parent);
        
//         // Create analysis imports
//         mem_imp    = new("mem_imp", this);
//         axi_imp    = new("axi_imp", this);
//         dcr_imp    = new("dcr_imp", this);
//         host_imp   = new("host_imp", this);
//         status_imp = new("status_imp", this);
        
//         // Create coverage groups
//         mem_operation_cg     = new();
//         axi_transaction_cg   = new();
//         dcr_config_cg        = new();
//         host_operation_cg    = new();
//         status_performance_cg = new();
//     endfunction
    
//     //==========================================================================
//     // Build Phase
//     //==========================================================================
//     virtual function void build_phase(uvm_phase phase);
//         super.build_phase(phase);
        
//         // Get configuration
//         if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg)) begin
//             `uvm_info("COVERAGE", "No vortex_config found", UVM_MEDIUM)
//         end
        
//         // Check if coverage is enabled
//         if (!cfg.enable_coverage) begin
//             `uvm_info("COVERAGE", "Functional coverage disabled by configuration", UVM_LOW)
//         end
//     endfunction
    
//     //==========================================================================
//     // Write Methods (Called by Agent Monitors)
//     //==========================================================================
    
//     virtual function void write_mem(mem_transaction trans);
//         if (!cfg.enable_coverage) return;
        
//         current_mem_trans = trans;
//         mem_operation_cg.sample();
        
//         `uvm_info("COVERAGE", "Sampled memory transaction", UVM_DEBUG)
//     endfunction
    
//     virtual function void write_axi(axi_transaction trans);
//         if (!cfg.enable_coverage) return;
        
//         current_axi_trans = trans;
//         axi_transaction_cg.sample();
        
//         `uvm_info("COVERAGE", "Sampled AXI transaction", UVM_DEBUG)
//     endfunction
    
//     virtual function void write_dcr(dcr_transaction trans);
//         if (!cfg.enable_coverage) return;
        
//         current_dcr_trans = trans;
//         dcr_config_cg.sample();
        
//         `uvm_info("COVERAGE", "Sampled DCR transaction", UVM_DEBUG)
//     endfunction
    
//     virtual function void write_host(host_transaction trans);
//         if (!cfg.enable_coverage) return;
        
//         current_host_trans = trans;
//         host_operation_cg.sample();
        
//         `uvm_info("COVERAGE", "Sampled host transaction", UVM_DEBUG)
//     endfunction
    
//     virtual function void write_status(status_transaction trans);
//         if (!cfg.enable_coverage) return;
        
//         current_status_trans = trans;
//         status_performance_cg.sample();
        
//         `uvm_info("COVERAGE", "Sampled status transaction", UVM_DEBUG)
//     endfunction
    
//     //==========================================================================
//     // Required write() method from uvm_subscriber
//     //==========================================================================
//     virtual function void write(uvm_sequence_item t);
//         // Not used - we use specific write_* methods instead
//     endfunction
    
//     //==========================================================================
//     // Report Phase
//     //==========================================================================
//     virtual function void report_phase(uvm_phase phase);
//         real mem_cov, axi_cov, dcr_cov, host_cov, status_cov;
//         real total_cov;
        
//         super.report_phase(phase);
        
//         if (!cfg.enable_coverage) return;
        
//         // Get coverage percentages
//         mem_cov    = mem_operation_cg.get_coverage();
//         axi_cov    = axi_transaction_cg.get_coverage();
//         dcr_cov    = dcr_config_cg.get_coverage();
//         host_cov   = host_operation_cg.get_coverage();
//         status_cov = status_performance_cg.get_coverage();
        
//         // Calculate average
//         total_cov = (mem_cov + axi_cov + dcr_cov + host_cov + status_cov) / 5.0;
        
//         `uvm_info("COVERAGE", {"\n",
//             "========================================\n",
//             "    Functional Coverage Report\n",
//             "========================================\n",
//             $sformatf("  Memory Operations:    %.2f%%\n", mem_cov),
//             $sformatf("  AXI Transactions:     %.2f%%\n", axi_cov),
//             $sformatf("  DCR Configuration:    %.2f%%\n", dcr_cov),
//             $sformatf("  Host Operations:      %.2f%%\n", host_cov),
//             $sformatf("  Status/Performance:   %.2f%%\n", status_cov),
//             "----------------------------------------\n",
//             $sformatf("  TOTAL COVERAGE:       %.2f%%\n", total_cov),
//             "========================================"
//         }, UVM_LOW)
//     endfunction
    
// endclass : vortex_coverage_collector

// `endif // VORTEX_COVERAGE_COLLECTOR_SV
