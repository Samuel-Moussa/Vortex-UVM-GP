////////////////////////////////////////////////////////////////////////////////
// File: vortex_config.sv
// Description: Unified UVM configuration class that mirrors VX_config.vh
//
// This configuration object provides a 1:1 mapping to the RTL configuration
// parameters defined in hw/rtl/VX_config.vh from the vortexgpgpu/vortex repo.
//
// Configuration hierarchy:
//   - Hardware Architecture (clusters, cores, warps, threads)
//   - ISA Extensions (F, D, M, A, C, ZICOND)
//   - Cache Hierarchy (I$, D$, L2, L3)
//   - Memory System (addressing, block size)
//   - Simulation/Test Settings
//
// Usage:
//   vortex_config cfg = vortex_config::type_id::create("cfg");
//   cfg.randomize() with {
//       num_clusters == 2;
//       num_cores == 4;
//       num_warps == 8;
//   };
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_CONFIG_SV
`define VORTEX_CONFIG_SV


package vortex_config_pkg;

import uvm_pkg::*;
`include "uvm_macros.svh"

// Memory interface parameters (matching VX_define.vh)
parameter VX_MEM_ADDR_WIDTH   = 32;
parameter VX_MEM_DATA_WIDTH   = 64;
parameter VX_MEM_TAG_WIDTH    = 8;
parameter VX_MEM_BYTEEN_WIDTH = VX_MEM_DATA_WIDTH/8;

// Startup address
parameter STARTUP_ADDR = 32'h80000000;

// DCR base addresses (from VX_define.vh)
parameter VX_DCR_BASE_STARTUP_ADDR0 = 32'h00000800;  // Default from set_defaults_from_vx_config
parameter VX_DCR_BASE_MPM_CLASS     = 32'h00000840;  // Default from set_defaults_from_vx_config


class vortex_config extends uvm_object;
    
    `uvm_object_utils(vortex_config)
    
    //==========================================================================
    // ARCHITECTURE CONFIGURATION (Maps to VX_config.vh)
    //==========================================================================
    
    // Cluster/Core/Warp/Thread Hierarchy
    rand int unsigned       num_clusters;      // NUM_CLUSTERS (1-4 typical)
    rand int unsigned       num_cores;         // NUM_CORES (1-32)
    rand int unsigned       num_warps;         // NUM_WARPS (1-16)
    rand int unsigned       num_threads;       // NUM_THREADS (1-8)
    rand int unsigned       num_barriers;      // NUM_BARRIERS (typically num_warps/2)
    
    // Socket configuration (derived)
    int unsigned            socket_size;       // SOCKET_SIZE
    
    //==========================================================================
    // ISA CONFIGURATION (Extension Enables)
    //==========================================================================
    
    // Base architecture
    rand bit                xlen_64;           // XLEN_64 or XLEN_32
    rand int unsigned       xlen;              // Derived: 64 or 32
    
    // Standard RISC-V Extensions
    rand bit                ext_f_enable;      // EXT_F_ENABLE (single-precision float)
    rand bit                ext_d_enable;      // EXT_D_ENABLE (double-precision float)
    rand bit                ext_m_enable;      // EXT_M_ENABLE (multiply/divide)
    rand bit                ext_a_enable;      // EXT_A_ENABLE (atomic operations)
    rand bit                ext_c_enable;      // EXT_C_ENABLE (compressed instructions)
    rand bit                ext_zicond_enable; // EXT_ZICOND_ENABLE (conditional operations)
    
    // Floating-point configuration
    rand int unsigned       flen;              // FLEN: 32 or 64
    
    //==========================================================================
    // CACHE HIERARCHY (Enable/Disable and Sizes)
    //==========================================================================
    
    // Cache enables
    rand bit                icache_enable;     // ICACHE_ENABLE
    rand bit                dcache_enable;     // DCACHE_ENABLE
    rand bit                l2_enable;         // L2_ENABLE
    rand bit                l3_enable;         // L3_ENABLE
    
    // Cache sizes (in bytes)
    rand int unsigned       icache_size;       // ICACHE_SIZE
    rand int unsigned       dcache_size;       // DCACHE_SIZE
    rand int unsigned       l2_cache_size;     // L2_CACHE_SIZE
    rand int unsigned       l3_cache_size;     // L3_CACHE_SIZE
    
    // Cache line size
    rand int unsigned       cache_line_size;   // Typically 64 bytes
    
    // Number of cache instances (derived)
    int unsigned            num_icaches;       // NUM_ICACHES
    int unsigned            num_dcaches;       // NUM_DCACHES
    
    //==========================================================================
    // MEMORY SYSTEM CONFIGURATION
    //==========================================================================
    
    // Memory parameters
    rand int unsigned       mem_block_size;    // MEM_BLOCK_SIZE (32, 64, 128)
    rand int unsigned       mem_addr_width;    // MEM_ADDR_WIDTH (32 or 48)
    rand int unsigned       mem_data_width;    // MEM_DATA_WIDTH (typically 64)
    rand int unsigned       mem_tag_width;     // MEM_TAG_WIDTH
    rand int unsigned       mem_byteen_width;  // MEM_BYTEEN_WIDTH (mem_data_width/8)
    
    // Memory address regions
    rand bit [63:0]         startup_addr;      // STARTUP_ADDR (default 0x80000000)
    rand bit [63:0]         stack_base_addr;   // Stack base address
    rand bit [63:0]         io_base_addr;      // IO_BASE_ADDR
    rand bit [63:0]         io_addr_end;       // IO_ADDR_END
    
    //==========================================================================
    // PIPELINE CONFIGURATION
    //==========================================================================
    
    // Issue width and buffer sizes
    rand int unsigned       issue_width;       // ISSUE_WIDTH (1 or 2)
    rand int unsigned       ibuf_size;         // IBUF_SIZE (instruction buffer)
    
    // Execution lanes
    rand int unsigned       num_alu_lanes;     // NUM_ALU_LANES (= NUM_THREADS)
    rand int unsigned       num_fpu_lanes;     // NUM_FPU_LANES (= NUM_THREADS)
    rand int unsigned       num_lsu_lanes;     // NUM_LSU_LANES (= NUM_THREADS)
    
    //==========================================================================
    // DCR (DEVICE CONFIGURATION REGISTER) ADDRESSES
    //==========================================================================
    
    // DCR base addresses (from VX_define.vh)
    bit [31:0]              dcr_base_startup_addr0;  // VX_DCR_BASE_STARTUP_ADDR0
    bit [31:0]              dcr_base_mpm_class;      // VX_DCR_BASE_MPM_CLASS
    
    //==========================================================================
    // SIMULATION/TEST CONFIGURATION
    //==========================================================================
    
    // Timeouts
    rand int unsigned       global_timeout_cycles;
    rand int unsigned       test_timeout_cycles;
    rand int unsigned       reset_cycles;
    rand int unsigned       reset_delay;       // RESET_DELAY
    
    // Verbosity
    rand uvm_verbosity      default_verbosity;
    rand bit                enable_transaction_recording;
    rand bit                enable_coverage;
    rand bit                enable_assertions;
    
    // Debug and tracing
    rand bit                dump_waves;
    string                  wave_file_name;
    rand bit                trace_enable;
    rand int unsigned       trace_level;       // 0-3
    
    //==========================================================================
    // AGENT CONFIGURATION
    //==========================================================================
    
    // Agent enables
    rand bit                mem_agent_enable;
    rand bit                axi_agent_enable;
    rand bit                dcr_agent_enable;
    rand bit                host_agent_enable;
    rand bit                status_agent_enable;
    
    // Agent modes (active/passive)
    rand bit                mem_agent_is_active;
    rand bit                axi_agent_is_active;
    rand bit                dcr_agent_is_active;
    rand bit                host_agent_is_active;
    rand bit                status_agent_is_active;  // Always passive
    
    //==========================================================================
    // GOLDEN MODEL (simx) CONFIGURATION
    //==========================================================================
    
    rand bit                simx_enable;
    string                  simx_path;
    rand bit                simx_debug_enable;
    rand int unsigned       simx_timeout_cycles;
    string                  simx_trace_file;
    
    //==========================================================================
    // TEST-SPECIFIC CONFIGURATION
    //==========================================================================
    
    // Program/kernel configuration
    string                  program_path;
    string                  program_type;       // "hex", "elf", "bin"
    rand bit [63:0]         program_load_addr;
    rand bit [63:0]         program_entry_point;
    
    // Kernel launch parameters
    rand bit [31:0]         kernel_num_groups;
    rand bit [31:0]         kernel_group_size;
    
    // Memory initialization
    rand bit                init_memory_random;
    rand bit                clear_memory_on_reset;
    
    // Result checking
    rand bit [63:0]         result_base_addr;
    rand int unsigned       result_size_bytes;
    
    //==========================================================================
    // SCOREBOARD CONFIGURATION
    //==========================================================================
    
    rand bit                enable_scoreboard;
    rand bit                strict_ordering;
    rand bit                compare_on_the_fly;
    
    //==========================================================================
    // CONSTRAINTS (Matching Vortex Hardware Limitations)
    //==========================================================================
    
    // Hardware architecture constraints
    constraint valid_hw_config_c {
        // Cluster/Core scaling
        num_clusters inside {[1:4]};
        num_cores inside {[1:32]};
        num_warps inside {[1:16]};
        num_threads inside {[1:8]};
        
        // Barriers are typically half the warps
        num_barriers == (num_warps / 2);
        
        // Cache sizes must be powers of 2
        icache_size inside {4096, 8192, 16384, 32768, 65536};
        dcache_size inside {4096, 8192, 16384, 32768, 65536};
        l2_cache_size inside {65536, 131072, 262144, 524288, 1048576};
        l3_cache_size inside {262144, 524288, 1048576, 2097152};
        
        // Memory parameters
        mem_block_size inside {32, 64, 128};
        mem_addr_width inside {32, 48};
        mem_data_width inside {32, 64};
        
        // Cache line size
        cache_line_size inside {32, 64};
        
        // Issue width
        issue_width inside {[1:2]};
        
        // Instruction buffer size
        ibuf_size inside {2, 4, 8};
    }
    
    // ISA consistency constraints
    constraint isa_consistency_c {
        // D extension requires F extension
        ext_d_enable -> ext_f_enable;
        
        // FLEN determined by extensions
        if (ext_d_enable)
            flen == 64;
        else if (ext_f_enable)
            flen == 32;
        else
            flen == 0;
        
        // XLEN consistency
        xlen == (xlen_64 ? 64 : 32);
    }
    
    // Cache hierarchy constraints
    constraint cache_hierarchy_c {
        // L3 requires L2, L2 can exist independently
        l3_enable -> l2_enable;
        
        // L3 requires multiple clusters
        l3_enable -> (num_clusters > 1);
        
        // If caches disabled, set sizes to 0
        if (!icache_enable) icache_size == 0;
        if (!dcache_enable) dcache_size == 0;
        if (!l2_enable) l2_cache_size == 0;
        if (!l3_enable) l3_cache_size == 0;
    }
    
    // Execution lane constraints
    constraint lane_config_c {
        // Lanes equal number of threads
        num_alu_lanes == num_threads;
        num_fpu_lanes == num_threads;
        num_lsu_lanes == num_threads;
    }
    
    // Default agent configuration
    constraint default_agents_c {
        // Core agents always enabled
        mem_agent_enable == 1;
        dcr_agent_enable == 1;
        host_agent_enable == 1;
        status_agent_enable == 1;
        
        // AXI agent optional (use custom memory by default)
        soft axi_agent_enable == 0;
        
        // Agent activity modes
        mem_agent_is_active == 1;
        dcr_agent_is_active == 1;
        host_agent_is_active == 1;
        status_agent_is_active == 0; // Always passive
    }
    
    // Timeout constraints
    constraint reasonable_timeouts_c {
        global_timeout_cycles inside {[50000:1000000]};
        test_timeout_cycles inside {[10000:100000]};
        reset_cycles inside {[10:100]};
        reset_delay inside {[10:100]};
        simx_timeout_cycles == test_timeout_cycles;
    }
    
    // Memory addressing constraints
    constraint valid_memory_addrs_c {
        // 32-bit mode: upper bits must be zero
        if (!xlen_64) {
            startup_addr[63:32] == 32'h0;
            stack_base_addr[63:32] == 32'h0;
            io_base_addr[63:32] == 32'h0;
            io_addr_end[63:32] == 32'h0;
            program_load_addr[63:32] == 32'h0;
            program_entry_point[63:32] == 32'h0;
            result_base_addr[63:32] == 32'h0;
        }
        
        // Word-aligned addresses
        startup_addr[1:0] == 2'b00;
        program_load_addr[1:0] == 2'b00;
        program_entry_point[1:0] == 2'b00;
        result_base_addr[1:0] == 2'b00;
        
        // IO address range validity
        io_addr_end > io_base_addr;
    }
    
    //==========================================================================
    // CONSTRUCTOR
    //==========================================================================
    
    function new(string name = "vortex_config");
        super.new(name);
        
        // Initialize from VX_config.vh defaults
        set_defaults_from_vx_config();
    endfunction
    
    //==========================================================================
    // CONFIGURATION METHODS
    //==========================================================================
    
    // Set defaults matching VX_config.vh
    virtual function void set_defaults_from_vx_config();
        
        // Architecture defaults
        `ifdef NUM_CLUSTERS
            num_clusters = `NUM_CLUSTERS;
        `else
            num_clusters = 1;
        `endif
        
        `ifdef NUM_CORES
            num_cores = `NUM_CORES;
        `else
            num_cores = 1;
        `endif
        
        `ifdef NUM_WARPS
            num_warps = `NUM_WARPS;
        `else
            num_warps = 4;
        `endif
        
        `ifdef NUM_THREADS
            num_threads = `NUM_THREADS;
        `else
            num_threads = 4;
        `endif
        
        `ifdef NUM_BARRIERS
            num_barriers = `NUM_BARRIERS;
        `else
            num_barriers = num_warps / 2;
        `endif
        
        // ISA configuration
        `ifdef XLEN_64
            xlen_64 = 1;
            xlen = 64;
        `else
            xlen_64 = 0;
            xlen = 32;
        `endif
        
        `ifdef EXT_F_ENABLE
            ext_f_enable = `EXT_F_ENABLE;
        `else
            ext_f_enable = 1;
        `endif
        
        `ifdef EXT_D_ENABLE
            ext_d_enable = `EXT_D_ENABLE;
        `else
            ext_d_enable = 0;
        `endif
        
        `ifdef EXT_M_ENABLE
            ext_m_enable = `EXT_M_ENABLE;
        `else
            ext_m_enable = 1;
        `endif
        
        `ifdef EXT_A_ENABLE
            ext_a_enable = `EXT_A_ENABLE;
        `else
            ext_a_enable = 0;
        `endif
        
        `ifdef EXT_C_ENABLE
            ext_c_enable = `EXT_C_ENABLE;
        `else
            ext_c_enable = 0;
        `endif
        
        `ifdef EXT_ZICOND_ENABLE
            ext_zicond_enable = `EXT_ZICOND_ENABLE;
        `else
            ext_zicond_enable = 1;
        `endif
        
        // FLEN based on extensions
        if (ext_d_enable)
            flen = 64;
        else if (ext_f_enable)
            flen = 32;
        else
            flen = 0;
        
        // Cache enables
        `ifdef ICACHE_ENABLE
            icache_enable = `ICACHE_ENABLE;
        `else
            icache_enable = 1;
        `endif
        
        `ifdef DCACHE_ENABLE
            dcache_enable = `DCACHE_ENABLE;
        `else
            dcache_enable = 1;
        `endif
        
        `ifdef L2_ENABLE
            l2_enable = `L2_ENABLE;
        `else
            l2_enable = 0;
        `endif
        
        `ifdef L3_ENABLE
            l3_enable = `L3_ENABLE;
        `else
            l3_enable = 0;
        `endif
        
        // Cache sizes
        `ifdef ICACHE_SIZE
            icache_size = `ICACHE_SIZE;
        `else
            icache_size = 16384;  // 16KB
        `endif
        
        `ifdef DCACHE_SIZE
            dcache_size = `DCACHE_SIZE;
        `else
            dcache_size = 16384;  // 16KB
        `endif
        
        `ifdef L2_CACHE_SIZE
            l2_cache_size = `L2_CACHE_SIZE;
        `else
            l2_cache_size = 131072;  // 128KB
        `endif
        
        `ifdef L3_CACHE_SIZE
            l3_cache_size = `L3_CACHE_SIZE;
        `else
            l3_cache_size = 524288;  // 512KB
        `endif
        
        cache_line_size = 64;
        
        // Derived cache counts
        socket_size = (num_cores < 4) ? num_cores : 4;
        num_icaches = icache_enable ? ((socket_size + 3) / 4) : 0;
        num_dcaches = dcache_enable ? ((socket_size + 3) / 4) : 0;
        
        // Memory system
        `ifdef MEM_BLOCK_SIZE
            mem_block_size = `MEM_BLOCK_SIZE;
        `else
            mem_block_size = 64;
        `endif
        
        `ifdef MEM_ADDR_WIDTH
            mem_addr_width = `MEM_ADDR_WIDTH;
        `else
            mem_addr_width = xlen_64 ? 48 : 32;
        `endif
        
        mem_data_width = 64;
        mem_tag_width = 8;
        mem_byteen_width = mem_data_width / 8;
        
        `ifdef STARTUP_ADDR
            startup_addr = `STARTUP_ADDR;
        `else
            startup_addr = 64'h80000000;
        `endif
        
        stack_base_addr = startup_addr + 64'h100000;  // 1MB after startup
        
        `ifdef IO_BASE_ADDR
            io_base_addr = `IO_BASE_ADDR;
        `else
            io_base_addr = 64'hFF000000;
        `endif
        
        `ifdef IO_ADDR_END
            io_addr_end = `IO_ADDR_END;
        `else
            io_addr_end = 64'hFFFFFFFF;
        `endif
        
        // Pipeline configuration
        issue_width = (num_warps < 8) ? 1 : (num_warps / 8);
        ibuf_size = 4;
        
        num_alu_lanes = num_threads;
        num_fpu_lanes = num_threads;
        num_lsu_lanes = num_threads;
        
        // DCR addresses (from VX_define.vh)
        `ifdef VX_DCR_BASE_STARTUP_ADDR0
            dcr_base_startup_addr0 = `VX_DCR_BASE_STARTUP_ADDR0;
        `else
            dcr_base_startup_addr0 = 32'h00000800;
        `endif
        
        `ifdef VX_DCR_BASE_MPM_CLASS
            dcr_base_mpm_class = `VX_DCR_BASE_MPM_CLASS;
        `else
            dcr_base_mpm_class = 32'h00000840;
        `endif
        
        // Simulation settings
        global_timeout_cycles = 100000;
        test_timeout_cycles = 50000;
        
        `ifdef RESET_DELAY
            reset_cycles = `RESET_DELAY;
            reset_delay = `RESET_DELAY;
        `else
            reset_cycles = 20;
            reset_delay = 20;
        `endif
        
        default_verbosity = UVM_MEDIUM;
        enable_transaction_recording = 1;
        enable_coverage = 1;
        enable_assertions = 1;
        
        dump_waves = 1;
        wave_file_name = "vortex_sim.vcd";
        trace_enable = 0;
        trace_level = 0;
        
        // Agent configuration
        mem_agent_enable = 1;
        axi_agent_enable = 0;
        dcr_agent_enable = 1;
        host_agent_enable = 1;
        status_agent_enable = 1;
        
        mem_agent_is_active = 1;
        axi_agent_is_active = 0;
        dcr_agent_is_active = 1;
        host_agent_is_active = 1;
        status_agent_is_active = 0;
        
        // // Golden model
        // simx_enable = 1;
        // simx_path = {getenv("VORTEX_HOME"), "/sim/simx/simx"};
        // simx_debug_enable = 0;
        // simx_timeout_cycles = test_timeout_cycles;
        // simx_trace_file = "simx_trace.log";
        
        // Test configuration
        program_path = "";
        program_type = "hex";
        program_load_addr = startup_addr;
        program_entry_point = startup_addr;
        
        kernel_num_groups = 1;
        kernel_group_size = num_threads;
        
        init_memory_random = 0;
        clear_memory_on_reset = 1;
        
        result_base_addr = startup_addr + 64'h100000;
        result_size_bytes = 1024;
        
        // Scoreboard
        enable_scoreboard = 1;
        strict_ordering = 0;
        compare_on_the_fly = 1;
    endfunction
    
    // Apply command-line plusargs (matching Vortex blackbox.sh)
    virtual function void apply_plusargs();
        int tmp;
        string str_tmp;
        
        // Architecture configuration
        if ($value$plusargs("CLUSTERS=%d", tmp) || $value$plusargs("clusters=%d", tmp))
            num_clusters = tmp;
        
        if ($value$plusargs("CORES=%d", tmp) || $value$plusargs("cores=%d", tmp))
            num_cores = tmp;
        
        if ($value$plusargs("WARPS=%d", tmp) || $value$plusargs("warps=%d", tmp))
            num_warps = tmp;
        
        if ($value$plusargs("THREADS=%d", tmp) || $value$plusargs("threads=%d", tmp))
            num_threads = tmp;
        
        // Cache enables
        if ($test$plusargs("L2CACHE") || $test$plusargs("l2cache"))
            l2_enable = 1;
        
        if ($test$plusargs("L3CACHE") || $test$plusargs("l3cache"))
            l3_enable = 1;
        
        // ISA options
        if ($test$plusargs("XLEN_64") || $test$plusargs("xlen=64")) begin
            xlen_64 = 1;
            xlen = 64;
        end
        
        // Program configuration
        if ($value$plusargs("PROGRAM=%s", str_tmp) || $value$plusargs("APP=%s", str_tmp))
            program_path = str_tmp;
        
        if ($value$plusargs("HEX=%s", str_tmp))
            program_path = str_tmp;
        
        if ($value$plusargs("STARTUP_ADDR=%h", tmp))
            startup_addr = tmp;
        
        // Simulation control
        if ($value$plusargs("TIMEOUT=%d", tmp))
            test_timeout_cycles = tmp;
        
        if ($test$plusargs("NO_WAVES") || $test$plusargs("no_waves"))
            dump_waves = 0;
        
        if ($test$plusargs("DISABLE_SIMX") || $test$plusargs("disable_simx"))
            simx_enable = 0;
        
        // Debug/verbosity
        if ($test$plusargs("VERBOSE") || $test$plusargs("verbose"))
            default_verbosity = UVM_HIGH;
        
        if ($test$plusargs("DEBUG") || $test$plusargs("debug") || $value$plusargs("DEBUG=%d", tmp)) begin
            default_verbosity = UVM_DEBUG;
            trace_enable = 1;
            trace_level = (tmp > 0) ? tmp : 1;
        end
        
        if ($value$plusargs("TRACE=%d", tmp)) begin
            trace_enable = 1;
            trace_level = tmp;
        end
        
        // Driver selection
        if ($value$plusargs("DRIVER=%s", str_tmp)) begin
            case (str_tmp)
                "rtlsim", "vlsim": begin
                    // RTL simulation mode
                end
                "simx": begin
                    simx_enable = 1;
                end
                "fpga", "opae", "xrt": begin
                    // FPGA mode
                    simx_enable = 0;
                end
            endcase
        end
        
        // Recalculate derived parameters
        num_barriers = num_warps / 2;
        socket_size = (num_cores < 4) ? num_cores : 4;
        num_icaches = icache_enable ? ((socket_size + 3) / 4) : 0;
        num_dcaches = dcache_enable ? ((socket_size + 3) / 4) : 0;
        num_alu_lanes = num_threads;
        num_fpu_lanes = num_threads;
        num_lsu_lanes = num_threads;
        issue_width = (num_warps < 8) ? 1 : (num_warps / 8);
    endfunction
    
    // Print comprehensive configuration summary
    virtual function void print_config(uvm_verbosity verbosity = UVM_MEDIUM);
        `uvm_info("VORTEX_CFG", "================================================================================", verbosity)
        `uvm_info("VORTEX_CFG", "                VORTEX UVM CONFIGURATION SUMMARY", verbosity)
        `uvm_info("VORTEX_CFG", "                (Mirrors hw/rtl/VX_config.vh)", verbosity)
        `uvm_info("VORTEX_CFG", "================================================================================", verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Hardware Architecture ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Clusters:       %0d", num_clusters), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Cores:          %0d", num_cores), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Warps:          %0d", num_warps), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Threads:        %0d", num_threads), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Barriers:       %0d", num_barriers), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Socket Size:    %0d", socket_size), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Issue Width:    %0d", issue_width), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- ISA Configuration ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  XLEN:           %0d", xlen), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  FLEN:           %0d", flen), verbosity)
        `uvm_info("VORTEX_CFG", "\n  Extensions:", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    F (Float):      %s", ext_f_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    D (Double):     %s", ext_d_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    M (Mul/Div):    %s", ext_m_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    A (Atomic):     %s", ext_a_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    C (Compressed): %s", ext_c_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    ZICOND:         %s", ext_zicond_enable ? "✓" : "✗"), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Cache Hierarchy ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  I$:  %s (%0d KB, %0d instances)", 
            icache_enable ? "ON" : "OFF", icache_size/1024, num_icaches), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  D$:  %s (%0d KB, %0d instances)", 
            dcache_enable ? "ON" : "OFF", dcache_size/1024, num_dcaches), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  L2:  %s (%0d KB)", 
            l2_enable ? "ON" : "OFF", l2_cache_size/1024), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  L3:  %s (%0d KB)", 
            l3_enable ? "ON" : "OFF", l3_cache_size/1024), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Line Size:      %0d bytes", cache_line_size), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Memory System ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Block Size:     %0d bytes", mem_block_size), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Addr Width:     %0d bits", mem_addr_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Data Width:     %0d bits", mem_data_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Startup Addr:   0x%h", startup_addr), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Stack Base:     0x%h", stack_base_addr), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  IO Base:        0x%h", io_base_addr), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Pipeline Configuration ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  ALU Lanes:      %0d", num_alu_lanes), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  FPU Lanes:      %0d", num_fpu_lanes), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  LSU Lanes:      %0d", num_lsu_lanes), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Issue Width:    %0d", issue_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  IBUF Size:      %0d", ibuf_size), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Simulation Settings ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Test Timeout:   %0d cycles", test_timeout_cycles), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Reset Cycles:   %0d", reset_cycles), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Dump Waves:     %s", dump_waves ? "YES" : "NO"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  simx Enable:    %s", simx_enable ? "YES" : "NO"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Verbosity:      %s", default_verbosity.name()), verbosity)
        
        if (program_path != "")
            `uvm_info("VORTEX_CFG", $sformatf("  Program:        %s", program_path), verbosity)
        
        `uvm_info("VORTEX_CFG", "================================================================================\n", verbosity)
    endfunction
    
    // Generate Verilog defines for compilation
    virtual function string get_verilog_defines();
        string defines = "";
        
        defines = {defines, $sformatf("+define+NUM_CLUSTERS=%0d ", num_clusters)};
        defines = {defines, $sformatf("+define+NUM_CORES=%0d ", num_cores)};
        defines = {defines, $sformatf("+define+NUM_WARPS=%0d ", num_warps)};
        defines = {defines, $sformatf("+define+NUM_THREADS=%0d ", num_threads)};
        defines = {defines, $sformatf("+define+NUM_BARRIERS=%0d ", num_barriers)};
        
        if (xlen_64)
            defines = {defines, "+define+XLEN_64 "};
        
        if (ext_f_enable)
            defines = {defines, "+define+EXT_F_ENABLE=1 "};
        if (ext_d_enable)
            defines = {defines, "+define+EXT_D_ENABLE=1 "};
        if (ext_m_enable)
            defines = {defines, "+define+EXT_M_ENABLE=1 "};
        if (ext_a_enable)
            defines = {defines, "+define+EXT_A_ENABLE=1 "};
        if (ext_c_enable)
            defines = {defines, "+define+EXT_C_ENABLE=1 "};
        if (ext_zicond_enable)
            defines = {defines, "+define+EXT_ZICOND_ENABLE=1 "};
        
        if (icache_enable)
            defines = {defines, "+define+ICACHE_ENABLE=1 "};
        if (dcache_enable)
            defines = {defines, "+define+DCACHE_ENABLE=1 "};
        if (l2_enable)
            defines = {defines, "+define+L2_ENABLE=1 "};
        if (l3_enable)
            defines = {defines, "+define+L3_ENABLE=1 "};
        
        defines = {defines, $sformatf("+define+ICACHE_SIZE=%0d ", icache_size)};
        defines = {defines, $sformatf("+define+DCACHE_SIZE=%0d ", dcache_size)};
        defines = {defines, $sformatf("+define+L2_CACHE_SIZE=%0d ", l2_cache_size)};
        defines = {defines, $sformatf("+define+L3_CACHE_SIZE=%0d ", l3_cache_size)};
        
        defines = {defines, $sformatf("+define+MEM_BLOCK_SIZE=%0d ", mem_block_size)};
        defines = {defines, $sformatf("+define+STARTUP_ADDR=64'h%h ", startup_addr)};
        
        return defines;
    endfunction
    
    // Validate configuration consistency
    virtual function bit is_valid();
        bit valid = 1;
        
        if (num_cores == 0 || num_warps == 0 || num_threads == 0) begin
            `uvm_error("VORTEX_CFG", "Invalid: zero cores/warps/threads")
            valid = 0;
        end
        
        if (ext_d_enable && !ext_f_enable) begin
            `uvm_error("VORTEX_CFG", "Invalid ISA: D extension requires F extension")
            valid = 0;
        end
        
        if (l3_enable && !l2_enable) begin
            `uvm_error("VORTEX_CFG", "Invalid cache: L3 requires L2")
            valid = 0;
        end
        
        if (l3_enable && num_clusters <= 1) begin
            `uvm_warning("VORTEX_CFG", "L3 cache typically requires multiple clusters")
        end
        
        if (simx_enable && simx_path == "") begin
            `uvm_error("VORTEX_CFG", "simx enabled but path not specified")
            valid = 0;
        end
        
        if (!xlen_64 && mem_addr_width > 32) begin
            `uvm_error("VORTEX_CFG", "32-bit mode cannot have addr_width > 32")
            valid = 0;
        end
        
        return valid;
    endfunction
    
    // Get configuration summary string (for logging)
    virtual function string get_config_string();
        return $sformatf("%0dC_%0dW_%0dT_%s_%s", 
            num_cores, num_warps, num_threads,
            xlen_64 ? "RV64" : "RV32",
            ext_f_enable ? (ext_d_enable ? "FD" : "F") : "");
    endfunction

endclass : vortex_config

endpackage : vortex_config_pkg


`endif // VORTEX_CONFIG_SV