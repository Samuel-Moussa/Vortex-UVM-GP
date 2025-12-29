////////////////////////////////////////////////////////////////////////////////
// File: vortex_config.sv
// Description: Complete UVM configuration mirroring ALL VX_*.vh files
//
// This configuration maps 1:1 with Vortex RTL configuration:
//   - VX_config.vh  → Hardware architecture parameters
//   - VX_define.vh  → Derived values and macros
//   - VX_types.vh   → CSR/DCR addresses and constants
//   - VX_platform.vh → Platform-specific settings
//
// The goal is to have a single UVM config object that represents the
// complete Vortex configuration and can be used for:
//   - DUT compilation parameters
//   - Golden model (simx) configuration
//   - Test constraints and coverage
//   - Scoreboard checking
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_CONFIG_SV
`define VORTEX_CONFIG_SV

// Include VX header files to get all defines
`include "VX_define.vh"

class vortex_config extends uvm_object;
    
    `uvm_object_utils(vortex_config)
    
    //==========================================================================
    // ARCHITECTURE PARAMETERS (from VX_config.vh)
    //==========================================================================
    
    // Core architecture
    rand int unsigned       num_clusters;      // NUM_CLUSTERS
    rand int unsigned       num_cores;         // NUM_CORES
    rand int unsigned       num_warps;         // NUM_WARPS
    rand int unsigned       num_threads;       // NUM_THREADS
    rand int unsigned       num_barriers;      // NUM_BARRIERS
    
    // Socket configuration (derived from VX_define.vh)
    int unsigned            socket_size;       // SOCKET_SIZE
    int unsigned            num_sockets;       // NUM_SOCKETS
    
    // Register file
    int unsigned            num_iregs;         // NUM_IREGS (always 32)
    int unsigned            num_regs;          // NUM_REGS (32 or 64 if FP enabled)
    
    //==========================================================================
    // ISA CONFIGURATION (from VX_config.vh)
    //==========================================================================
    
    // Base ISA
    rand bit                xlen_64;           // XLEN=64 (else XLEN=32)
    int unsigned            xlen;              // 32 or 64
    int unsigned            flen;              // FLEN (0, 32, or 64)
    
    // Standard RISC-V Extensions
    rand bit                ext_f_enable;      // EXT_F_ENABLE (single-precision FP)
    rand bit                ext_d_enable;      // EXT_D_ENABLE (double-precision FP)
    rand bit                ext_m_enable;      // EXT_M_ENABLE (multiply/divide)
    rand bit                ext_a_enable;      // EXT_A_ENABLE (atomic)
    rand bit                ext_c_enable;      // EXT_C_ENABLE (compressed)
    rand bit                ext_zicond_enable; // EXT_ZICOND_ENABLE (conditional ops)
    
    //==========================================================================
    // DERIVED ISA VALUES (from VX_define.vh)
    //==========================================================================
    
    // Bit widths (calculated from parameters)
    int unsigned            nw_bits;           // CLOG2(NUM_WARPS)
    int unsigned            nw_width;          // UP(NW_BITS)
    int unsigned            nt_bits;           // CLOG2(NUM_THREADS)
    int unsigned            nt_width;          // UP(NT_BITS)
    int unsigned            nc_bits;           // CLOG2(NUM_CORES)
    int unsigned            nc_width;          // UP(NC_BITS)
    int unsigned            nb_bits;           // CLOG2(NUM_BARRIERS)
    int unsigned            nb_width;          // UP(NB_BITS)
    int unsigned            nri_bits;          // CLOG2(NUM_IREGS)
    int unsigned            nr_bits;           // CLOG2(NUM_REGS)
    
    // Execution units (from VX_define.vh)
    int unsigned            ex_alu;            // 0
    int unsigned            ex_lsu;            // 1
    int unsigned            ex_sfu;            // 2
    int unsigned            ex_fpu;            // 2 + EXT_F_ENABLED
    int unsigned            num_ex_units;      // 3 + EXT_F_ENABLED
    int unsigned            ex_bits;           // CLOG2(NUM_EX_UNITS)
    
    //==========================================================================
    // CACHE HIERARCHY (from VX_config.vh)
    //==========================================================================
    
    // Cache enables
    rand bit                icache_enable;     // ICACHE_ENABLE
    rand bit                dcache_enable;     // DCACHE_ENABLE
    rand bit                l2_enable;         // L2_ENABLE
    rand bit                l3_enable;         // L3_ENABLE
    
    // Cache sizes (bytes)
    rand int unsigned       icache_size;       // ICACHE_SIZE
    rand int unsigned       dcache_size;       // DCACHE_SIZE
    rand int unsigned       l2_cache_size;     // L2_CACHE_SIZE
    rand int unsigned       l3_cache_size;     // L3_CACHE_SIZE
    
    // Cache line size
    rand int unsigned       l1_line_size;      // L1_LINE_SIZE
    rand int unsigned       l2_line_size;      // L2_LINE_SIZE
    rand int unsigned       l3_line_size;      // L3_LINE_SIZE
    
    // Number of cache instances (derived)
    int unsigned            num_icaches;       // NUM_ICACHES
    int unsigned            num_dcaches;       // NUM_DCACHES
    
    //==========================================================================
    // MEMORY SYSTEM (from VX_config.vh and VX_define.vh)
    //==========================================================================
    
    // Memory parameters
    rand int unsigned       mem_block_size;    // MEM_BLOCK_SIZE
    rand int unsigned       mem_addr_width;    // MEM_ADDR_WIDTH
    
    // Memory interface widths (from VX_define.vh)
    int unsigned            vx_mem_byteen_width; // VX_MEM_BYTEEN_WIDTH
    int unsigned            vx_mem_addr_width;   // VX_MEM_ADDR_WIDTH
    int unsigned            vx_mem_data_width;   // VX_MEM_DATA_WIDTH
    int unsigned            vx_mem_tag_width;    // VX_MEM_TAG_WIDTH (fixed at 8)
    
    // DCR interface widths (from VX_define.vh)
    int unsigned            vx_dcr_addr_width;   // VX_DCR_ADDR_WIDTH
    int unsigned            vx_dcr_data_width;   // VX_DCR_DATA_WIDTH (always 32)
    
    // Memory regions
    rand bit [63:0]         startup_addr;      // STARTUP_ADDR
    rand bit [63:0]         stack_base_addr;   // Stack base
    rand bit [63:0]         io_base_addr;      // IO_BASE_ADDR
    rand bit [63:0]         io_addr_end;       // IO_ADDR_END
    
    // Local memory
    rand bit                lmem_enable;       // LMEM_ENABLE
    rand int unsigned       lmem_size;         // LMEM_SIZE
    
    //==========================================================================
    // DCR ADDRESSES (from VX_types.vh)
    //==========================================================================
    
    // These are constants, not configurable
    bit [11:0]              dcr_base_startup_addr0;  // VX_DCR_BASE_STARTUP_ADDR0
    bit [11:0]              dcr_base_startup_addr1;  // VX_DCR_BASE_STARTUP_ADDR1
    bit [11:0]              dcr_base_startup_arg0;   // VX_DCR_BASE_STARTUP_ARG0
    bit [11:0]              dcr_base_startup_arg1;   // VX_DCR_BASE_STARTUP_ARG1
    bit [11:0]              dcr_base_mpm_class;      // VX_DCR_BASE_MPM_CLASS
    
    // DCR MPM classes
    bit [31:0]              dcr_mpm_class_none;      // VX_DCR_MPM_CLASS_NONE
    bit [31:0]              dcr_mpm_class_core;      // VX_DCR_MPM_CLASS_CORE
    bit [31:0]              dcr_mpm_class_mem;       // VX_DCR_MPM_CLASS_MEM
    
    //==========================================================================
    // PIPELINE CONFIGURATION (from VX_define.vh)
    //==========================================================================
    
    // Issue configuration
    rand int unsigned       issue_width;       // ISSUE_WIDTH
    rand int unsigned       ibuf_size;         // IBUF_SIZE
    
    // Execution lanes
    int unsigned            num_alu_lanes;     // NUM_ALU_LANES
    int unsigned            num_fpu_lanes;     // NUM_FPU_LANES
    int unsigned            num_lsu_lanes;     // NUM_LSU_LANES
    
    // Divergence stack
    int unsigned            dv_stack_size;     // DV_STACK_SIZE
    int unsigned            dv_stack_sizew;    // DV_STACK_SIZEW
    
    //==========================================================================
    // DEBUG AND PERFORMANCE (from VX_platform.vh)
    //==========================================================================
    
    rand bit                ndebug;            // NDEBUG (disable debug features)
    int unsigned            uuid_width;        // UUID_WIDTH (44 if debug, 1 if not)
    int unsigned            perf_ctr_bits;     // PERF_CTR_BITS (always 44)
    
    //==========================================================================
    // SIMULATION CONFIGURATION
    //==========================================================================
    
    // Timeouts
    rand int unsigned       global_timeout_cycles;
    rand int unsigned       test_timeout_cycles;
    rand int unsigned       reset_cycles;
    rand int unsigned       reset_delay;
    
    // Verbosity
    rand uvm_verbosity      default_verbosity;
    rand bit                enable_transaction_recording;
    rand bit                enable_coverage;
    rand bit                enable_assertions;
    
    // Debug
    rand bit                dump_waves;
    string                  wave_file_name;
    rand bit                trace_enable;
    rand int unsigned       trace_level;
    
    //==========================================================================
    // AGENT CONFIGURATION
    //==========================================================================
    
    // Agent enables
    rand bit                mem_agent_enable;
    rand bit                axi_agent_enable;
    rand bit                dcr_agent_enable;
    rand bit                host_agent_enable;
    rand bit                status_agent_enable;
    
    // Agent activity modes
    rand bit                mem_agent_is_active;
    rand bit                axi_agent_is_active;
    rand bit                dcr_agent_is_active;
    rand bit                host_agent_is_active;
    rand bit                status_agent_is_active;
    
    // Agent-specific settings
    rand int unsigned       dcr_write_spacing;
    rand int unsigned       status_sample_interval;
    
    //==========================================================================
    // GOLDEN MODEL (simx) CONFIGURATION
    //==========================================================================
    
    rand bit                simx_enable;
    string                  simx_path;
    rand bit                simx_debug_enable;
    rand int unsigned       simx_timeout_cycles;
    string                  simx_trace_file;
    
    //==========================================================================
    // TEST CONFIGURATION
    //==========================================================================
    
    // Program loading
    string                  program_path;
    string                  program_type;
    rand bit [63:0]         program_load_addr;
    rand bit [63:0]         program_entry_point;
    
    // Kernel parameters
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
    // CONSTRAINTS
    //==========================================================================
    
    // Hardware architecture constraints
    constraint valid_hw_config_c {
        num_clusters inside {[1:4]};
        num_cores inside {[1:32]};
        num_warps inside {[1:16]};
        num_threads inside {[1:8]};
        num_barriers == (num_warps / 2);
        
        // Cache sizes (power of 2)
        icache_size inside {4096, 8192, 16384, 32768, 65536};
        dcache_size inside {4096, 8192, 16384, 32768, 65536};
        l2_cache_size inside {65536, 131072, 262144, 524288, 1048576};
        l3_cache_size inside {262144, 524288, 1048576, 2097152};
        
        // Line sizes (power of 2)
        l1_line_size inside {32, 64};
        l2_line_size inside {64, 128};
        l3_line_size inside {64, 128};
        
        // Memory parameters
        mem_block_size inside {32, 64, 128};
        mem_addr_width inside {32, 48};
        
        // Issue width
        issue_width inside {[1:2]};
        ibuf_size inside {2, 4, 8};
        
        // Local memory
        if (lmem_enable) {
            lmem_size inside {4096, 8192, 16384, 32768};
        } else {
            lmem_size == 0;
        }
    }
    
    // ISA consistency
    constraint isa_consistency_c {
        ext_d_enable -> ext_f_enable;
    }
    
    // Cache hierarchy
    constraint cache_hierarchy_c {
        l3_enable -> l2_enable;
        l3_enable -> (num_clusters > 1);
        
        if (!icache_enable) icache_size == 0;
        if (!dcache_enable) dcache_size == 0;
        if (!l2_enable) l2_cache_size == 0;
        if (!l3_enable) l3_cache_size == 0;
    }
    
    // Default agent configuration
    constraint default_agents_c {
        mem_agent_enable == 1;
        dcr_agent_enable == 1;
        host_agent_enable == 1;
        status_agent_enable == 1;
        soft axi_agent_enable == 0;
        
        mem_agent_is_active == 1;
        dcr_agent_is_active == 1;
        host_agent_is_active == 1;
        status_agent_is_active == 0;
        
        dcr_write_spacing inside {[0:5]};
        status_sample_interval inside {[1:10]};
    }
    
    // Timeout constraints
    constraint reasonable_timeouts_c {
        global_timeout_cycles inside {[50000:1000000]};
        test_timeout_cycles inside {[10000:100000]};
        reset_cycles inside {[10:100]};
        reset_delay inside {[10:100]};
        simx_timeout_cycles == test_timeout_cycles;
    }
    
    // Memory addressing
    constraint valid_memory_addrs_c {
        if (!xlen_64) {
            startup_addr[63:32] == 32'h0;
            stack_base_addr[63:32] == 32'h0;
            io_base_addr[63:32] == 32'h0;
            io_addr_end[63:32] == 32'h0;
            program_load_addr[63:32] == 32'h0;
            program_entry_point[63:32] == 32'h0;
            result_base_addr[63:32] == 32'h0;
        }
        
        // Word-aligned
        startup_addr[1:0] == 2'b00;
        program_load_addr[1:0] == 2'b00;
        program_entry_point[1:0] == 2'b00;
        result_base_addr[1:0] == 2'b00;
        
        io_addr_end > io_base_addr;
    }
    
    //==========================================================================
    // CONSTRUCTOR
    //==========================================================================
    
    function new(string name = "vortex_config");
        super.new(name);
        set_defaults_from_vx_defines();
    endfunction
    
    //==========================================================================
    // INITIALIZATION FROM VX_*.vh FILES
    //==========================================================================
    
    virtual function void set_defaults_from_vx_defines();
        
        // Architecture (from VX_config.vh via defines)
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
        
        // ISA
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
        
        // Cache enables
        `ifdef ICACHE_ENABLE
            icache_enable = 1;
        `else
            icache_enable = 0;
        `endif
        
        `ifdef DCACHE_ENABLE
            dcache_enable = 1;
        `else
            dcache_enable = 0;
        `endif
        
        `ifdef L2_ENABLE
            l2_enable = 1;
        `else
            l2_enable = 0;
        `endif
        
        `ifdef L3_ENABLE
            l3_enable = 1;
        `else
            l3_enable = 0;
        `endif
        
        // Cache sizes
        `ifdef ICACHE_SIZE
            icache_size = `ICACHE_SIZE;
        `else
            icache_size = 16384;
        `endif
        
        `ifdef DCACHE_SIZE
            dcache_size = `DCACHE_SIZE;
        `else
            dcache_size = 16384;
        `endif
        
        `ifdef L2_CACHE_SIZE
            l2_cache_size = `L2_CACHE_SIZE;
        `else
            l2_cache_size = 131072;
        `endif
        
        `ifdef L3_CACHE_SIZE
            l3_cache_size = `L3_CACHE_SIZE;
        `else
            l3_cache_size = 524288;
        `endif
        
        // Line sizes
        `ifdef L1_LINE_SIZE
            l1_line_size = `L1_LINE_SIZE;
        `else
            l1_line_size = 64;
        `endif
        
        `ifdef L2_LINE_SIZE
            l2_line_size = `L2_LINE_SIZE;
        `else
            l2_line_size = 64;
        `endif
        
        `ifdef L3_LINE_SIZE
            l3_line_size = `L3_LINE_SIZE;
        `else
            l3_line_size = 64;
        `endif
        
        // Memory
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
        
        `ifdef STARTUP_ADDR
            startup_addr = `STARTUP_ADDR;
        `else
            startup_addr = 64'h80000000;
        `endif
        
        stack_base_addr = startup_addr + 64'h100000;
        
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
        
        // Local memory
        `ifdef LMEM_ENABLE
            lmem_enable = 1;
            `ifdef LMEM_SIZE
                lmem_size = `LMEM_SIZE;
            `else
                lmem_size = 16384;
            `endif
        `else
            lmem_enable = 0;
            lmem_size = 0;
        `endif
        
        // Calculate derived values
        calculate_derived_values();
        
        // DCR addresses (constants from VX_types.vh)
        dcr_base_startup_addr0 = `VX_DCR_BASE_STARTUP_ADDR0;
        dcr_base_startup_addr1 = `VX_DCR_BASE_STARTUP_ADDR1;
        dcr_base_startup_arg0  = `VX_DCR_BASE_STARTUP_ARG0;
        dcr_base_startup_arg1  = `VX_DCR_BASE_STARTUP_ARG1;
        dcr_base_mpm_class     = `VX_DCR_BASE_MPM_CLASS;
        
        dcr_mpm_class_none = `VX_DCR_MPM_CLASS_NONE;
        dcr_mpm_class_core = `VX_DCR_MPM_CLASS_CORE;
        dcr_mpm_class_mem  = `VX_DCR_MPM_CLASS_MEM;
        
        // Debug
        `ifdef NDEBUG
            ndebug = 1;
            uuid_width = 1;
        `else
            ndebug = 0;
            uuid_width = 44;
        `endif
        
        perf_ctr_bits = 44;
        
        // Simulation defaults
        global_timeout_cycles = 100000;
        test_timeout_cycles = 50000;
        reset_cycles = 20;
        reset_delay = 20;
        
        default_verbosity = UVM_MEDIUM;
        enable_transaction_recording = 1;
        enable_coverage = 1;
        enable_assertions = 1;
        
        dump_waves = 1;
        wave_file_name = "vortex_sim.vcd";
        trace_enable = 0;
        trace_level = 0;
        
        // Agents
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
        
        dcr_write_spacing = 0;
        status_sample_interval = 1;
        
        // Golden model
        simx_enable = 1;
        simx_path = "";
        simx_debug_enable = 0;
        simx_timeout_cycles = test_timeout_cycles;
        simx_trace_file = "simx_trace.log";
        
        // Test
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
    
    //==========================================================================
    // CALCULATE DERIVED VALUES (from VX_define.vh macros)
    //==========================================================================
    
    virtual function void calculate_derived_values();
        // Bit widths (using CLOG2 and UP macros)
        nw_bits = $clog2(num_warps);
        nw_width = (nw_bits != 0) ? nw_bits : 1;
        
        nt_bits = $clog2(num_threads);
        nt_width = (nt_bits != 0) ? nt_bits : 1;
        
        nc_bits = $clog2(num_cores);
        nc_width = (nc_bits != 0) ? nc_bits : 1;
        
        nb_bits = $clog2(num_barriers);
        nb_width = (nb_bits != 0) ? nb_bits : 1;
        
        // Register file
        num_iregs = 32;
        nri_bits = 5;  // CLOG2(32)
        
        if (ext_f_enable) begin
            num_regs = 64;  // 2 * NUM_IREGS
            flen = ext_d_enable ? 64 : 32;
        end else begin
            num_regs = 32;
            flen = 0;
        end
        
        nr_bits = $clog2(num_regs);
        
        // Socket configuration (from VX_define.vh)
        socket_size = (num_cores < 4) ? num_cores : 4;
        num_sockets = (num_cores + socket_size - 1) / socket_size;
        
        // Cache instances
        num_icaches = icache_enable ? ((socket_size + 3) / 4) : 0;
        num_dcaches = dcache_enable ? ((socket_size + 3) / 4) : 0;
        
        // Execution units (from VX_define.vh)
        ex_alu = 0;
        ex_lsu = 1;
        ex_sfu = 2;
        ex_fpu = 2 + (ext_f_enable ? 1 : 0);
        num_ex_units = 3 + (ext_f_enable ? 1 : 0);
        ex_bits = $clog2(num_ex_units);
        
        // Execution lanes
        num_alu_lanes = num_threads;
        num_fpu_lanes = num_threads;
        num_lsu_lanes = num_threads;
        
        // Pipeline
        issue_width = (num_warps < 8) ? 1 : (num_warps / 8);
        ibuf_size = 4;
        
        // Divergence stack
        dv_stack_size = (num_threads > 1) ? (num_threads - 1) : 1;
        dv_stack_sizew = (dv_stack_size > 1) ? $clog2(dv_stack_size) : 1;
        
        // Memory interface widths (from VX_define.vh)
        vx_mem_byteen_width = l3_line_size;
        vx_mem_addr_width = mem_addr_width - $clog2(l3_line_size);
        vx_mem_data_width = l3_line_size * 8;
        vx_mem_tag_width = 8;  // Fixed for UVM testbench
        
        vx_dcr_addr_width = 12;  // VX_DCR_ADDR_BITS
        vx_dcr_data_width = 32;  // Always 32
    endfunction
    
    //==========================================================================
    // APPLY PLUSARGS (Command-line overrides)
    //==========================================================================
    
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
        
        // ISA configuration
        if ($test$plusargs("XLEN_64") || $test$plusargs("xlen=64")) begin
            xlen_64 = 1;
            xlen = 64;
        end
        
        if ($test$plusargs("EXT_F") || $test$plusargs("ext_f"))
            ext_f_enable = 1;

        if ($test$plusargs("EXT_D") || $test$plusargs("ext_d"))
            ext_d_enable = 1;
        
        if ($test$plusargs("EXT_M") || $test$plusargs("ext_m"))
            ext_m_enable = 1;
        
        if ($test$plusargs("EXT_A") || $test$plusargs("ext_a"))
            ext_a_enable = 1;
        
        if ($test$plusargs("EXT_C") || $test$plusargs("ext_c"))
            ext_c_enable = 1;
        
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
        
        // Recalculate derived parameters after plusargs
        calculate_derived_values();
    endfunction
    
    //==========================================================================
    // PRINT CONFIGURATION SUMMARY
    //==========================================================================
    
    virtual function void print_config(uvm_verbosity verbosity = UVM_MEDIUM);
        `uvm_info("VORTEX_CFG", "================================================================================", verbosity)
        `uvm_info("VORTEX_CFG", "                VORTEX UVM CONFIGURATION SUMMARY", verbosity)
        `uvm_info("VORTEX_CFG", "                (Mirrors VX_*.vh configuration)", verbosity)
        `uvm_info("VORTEX_CFG", "================================================================================", verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Hardware Architecture (VX_config.vh) ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Clusters:       %0d", num_clusters), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Cores:          %0d", num_cores), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Warps:          %0d", num_warps), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Threads:        %0d", num_threads), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Barriers:       %0d", num_barriers), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Socket Size:    %0d", socket_size), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Num Sockets:    %0d", num_sockets), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- ISA Configuration (VX_config.vh) ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  XLEN:           %0d", xlen), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  FLEN:           %0d", flen), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  NUM_REGS:       %0d", num_regs), verbosity)
        `uvm_info("VORTEX_CFG", "\n  Extensions:", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    F (Float):      %s", ext_f_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    D (Double):     %s", ext_d_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    M (Mul/Div):    %s", ext_m_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    A (Atomic):     %s", ext_a_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    C (Compressed): %s", ext_c_enable ? "✓" : "✗"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("    ZICOND:         %s", ext_zicond_enable ? "✓" : "✗"), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Derived Values (VX_define.vh) ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  NW_BITS:        %0d", nw_bits), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  NT_BITS:        %0d", nt_bits), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  NC_BITS:        %0d", nc_bits), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  NR_BITS:        %0d", nr_bits), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  NUM_EX_UNITS:   %0d", num_ex_units), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Issue Width:    %0d", issue_width), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Cache Hierarchy (VX_config.vh) ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  I$:  %s (%0d KB, %0d instances, line=%0d)", 
            icache_enable ? "ON" : "OFF", icache_size/1024, num_icaches, l1_line_size), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  D$:  %s (%0d KB, %0d instances, line=%0d)", 
            dcache_enable ? "ON" : "OFF", dcache_size/1024, num_dcaches, l1_line_size), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  L2:  %s (%0d KB, line=%0d)", 
            l2_enable ? "ON" : "OFF", l2_cache_size/1024, l2_line_size), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  L3:  %s (%0d KB, line=%0d)", 
            l3_enable ? "ON" : "OFF", l3_cache_size/1024, l3_line_size), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Memory System (VX_define.vh) ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  MEM_BLOCK_SIZE:       %0d", mem_block_size), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  MEM_ADDR_WIDTH:       %0d", mem_addr_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  VX_MEM_ADDR_WIDTH:    %0d", vx_mem_addr_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  VX_MEM_DATA_WIDTH:    %0d", vx_mem_data_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  VX_MEM_BYTEEN_WIDTH:  %0d", vx_mem_byteen_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  VX_MEM_TAG_WIDTH:     %0d", vx_mem_tag_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  VX_DCR_ADDR_WIDTH:    %0d", vx_dcr_addr_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  VX_DCR_DATA_WIDTH:    %0d", vx_dcr_data_width), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Memory Regions ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Startup Address:   0x%h", startup_addr), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Stack Base:        0x%h", stack_base_addr), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  IO Base:           0x%h", io_base_addr), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  IO End:            0x%h", io_addr_end), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Local Mem:         %s (%0d KB)", 
            lmem_enable ? "ON" : "OFF", lmem_size/1024), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- DCR Addresses (VX_types.vh) ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  STARTUP_ADDR0:  0x%03h", dcr_base_startup_addr0), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  STARTUP_ADDR1:  0x%03h", dcr_base_startup_addr1), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  STARTUP_ARG0:   0x%03h", dcr_base_startup_arg0), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  STARTUP_ARG1:   0x%03h", dcr_base_startup_arg1), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  MPM_CLASS:      0x%03h", dcr_base_mpm_class), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Pipeline Configuration (VX_define.vh) ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  ALU Lanes:      %0d", num_alu_lanes), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  FPU Lanes:      %0d", num_fpu_lanes), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  LSU Lanes:      %0d", num_lsu_lanes), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Issue Width:    %0d", issue_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  IBUF Size:      %0d", ibuf_size), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  DV Stack Size:  %0d", dv_stack_size), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Debug & Performance (VX_platform.vh) ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  NDEBUG:         %s", ndebug ? "YES" : "NO"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  UUID_WIDTH:     %0d", uuid_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  PERF_CTR_BITS:  %0d", perf_ctr_bits), verbosity)
        
        `uvm_info("VORTEX_CFG", "\n--- Simulation Settings ---", verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Test Timeout:   %0d cycles", test_timeout_cycles), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Reset Cycles:   %0d", reset_cycles), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Dump Waves:     %s", dump_waves ? "YES" : "NO"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  simx Enable:    %s", simx_enable ? "YES" : "NO"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Verbosity:      %s", default_verbosity.name()), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Trace Level:    %0d", trace_level), verbosity)
        
        if (program_path != "")
            `uvm_info("VORTEX_CFG", $sformatf("  Program:        %s", program_path), verbosity)
        
        `uvm_info("VORTEX_CFG", "================================================================================\n", verbosity)
    endfunction
    
    //==========================================================================
    // GENERATE VERILOG DEFINES FOR COMPILATION
    //==========================================================================
    
    virtual function string get_verilog_defines();
        string defines = "";
        
        // Architecture
        defines = {defines, $sformatf("+define+NUM_CLUSTERS=%0d ", num_clusters)};
        defines = {defines, $sformatf("+define+NUM_CORES=%0d ", num_cores)};
        defines = {defines, $sformatf("+define+NUM_WARPS=%0d ", num_warps)};
        defines = {defines, $sformatf("+define+NUM_THREADS=%0d ", num_threads)};
        defines = {defines, $sformatf("+define+NUM_BARRIERS=%0d ", num_barriers)};
        
        // ISA
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
        
        // Caches
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
        
        defines = {defines, $sformatf("+define+L1_LINE_SIZE=%0d ", l1_line_size)};
        defines = {defines, $sformatf("+define+L2_LINE_SIZE=%0d ", l2_line_size)};
        defines = {defines, $sformatf("+define+L3_LINE_SIZE=%0d ", l3_line_size)};
        
        // Memory
        defines = {defines, $sformatf("+define+MEM_BLOCK_SIZE=%0d ", mem_block_size)};
        defines = {defines, $sformatf("+define+MEM_ADDR_WIDTH=%0d ", mem_addr_width)};
        defines = {defines, $sformatf("+define+STARTUP_ADDR=64'h%h ", startup_addr)};
        
        if (lmem_enable) begin
            defines = {defines, "+define+LMEM_ENABLE=1 "};
            defines = {defines, $sformatf("+define+LMEM_SIZE=%0d ", lmem_size)};
        end
        
        // Debug
        if (ndebug)
            defines = {defines, "+define+NDEBUG "};
        
        return defines;
    endfunction
    
    //==========================================================================
    // VALIDATE CONFIGURATION
    //==========================================================================
    
    virtual function bit is_valid();
        bit valid = 1;
        
        // Hardware checks
        if (num_cores == 0 || num_warps == 0 || num_threads == 0) begin
            `uvm_error("VORTEX_CFG", "Invalid: zero cores/warps/threads")
            valid = 0;
        end
        
        if (num_barriers != (num_warps / 2)) begin
            `uvm_warning("VORTEX_CFG", $sformatf(
                "num_barriers (%0d) should be num_warps/2 (%0d)", 
                num_barriers, num_warps/2))
        end
        
        // ISA checks
        if (ext_d_enable && !ext_f_enable) begin
            `uvm_error("VORTEX_CFG", "Invalid ISA: D extension requires F extension")
            valid = 0;
        end
        
        if (flen != 0 && !ext_f_enable) begin
            `uvm_error("VORTEX_CFG", "FLEN != 0 but F extension disabled")
            valid = 0;
        end
        
        // Cache checks
        if (l3_enable && !l2_enable) begin
            `uvm_error("VORTEX_CFG", "Invalid cache: L3 requires L2")
            valid = 0;
        end
        
        if (l3_enable && num_clusters <= 1) begin
            `uvm_warning("VORTEX_CFG", "L3 cache enabled but only 1 cluster")
        end
        
        // Memory checks
        if (!xlen_64 && mem_addr_width > 32) begin
            `uvm_error("VORTEX_CFG", "32-bit mode cannot have mem_addr_width > 32")
            valid = 0;
        end
        
        if (io_addr_end <= io_base_addr) begin
            `uvm_error("VORTEX_CFG", "IO_ADDR_END must be > IO_BASE_ADDR")
            valid = 0;
        end
        
        // Golden model checks
        if (simx_enable && simx_path == "") begin
            `uvm_error("VORTEX_CFG", "simx enabled but path not specified")
            valid = 0;
        end
        
        // Derived value checks
        if (socket_size != ((num_cores < 4) ? num_cores : 4)) begin
            `uvm_error("VORTEX_CFG", "SOCKET_SIZE calculation mismatch")
            valid = 0;
        end
        
        if (num_ex_units != (3 + (ext_f_enable ? 1 : 0))) begin
            `uvm_error("VORTEX_CFG", "NUM_EX_UNITS calculation mismatch")
            valid = 0;
        end
        
        return valid;
    endfunction
    
    //==========================================================================
    // GENERATE CONFIGURATION STRING
    //==========================================================================
    
    virtual function string get_config_string();
        string cfg_str;
        
        cfg_str = $sformatf("%0dCL_%0dC_%0dW_%0dT", 
            num_clusters, num_cores, num_warps, num_threads);
        
        cfg_str = {cfg_str, "_", xlen_64 ? "RV64" : "RV32"};
        
        if (ext_f_enable)
            cfg_str = {cfg_str, ext_d_enable ? "FD" : "F"};
        if (ext_m_enable)
            cfg_str = {cfg_str, "M"};
        if (ext_a_enable)
            cfg_str = {cfg_str, "A"};
        if (ext_c_enable)
            cfg_str = {cfg_str, "C"};
        
        if (l2_enable)
            cfg_str = {cfg_str, "_L2"};
        if (l3_enable)
            cfg_str = {cfg_str, "_L3"};
        
        return cfg_str;
    endfunction
    
    //==========================================================================
    // GENERATE SIMX COMMAND LINE
    //==========================================================================
    
    virtual function string get_simx_cmdline();
        string cmdline = simx_path;
        
        cmdline = {cmdline, $sformatf(" --clusters=%0d", num_clusters)};
        cmdline = {cmdline, $sformatf(" --cores=%0d", num_cores)};
        cmdline = {cmdline, $sformatf(" --warps=%0d", num_warps)};
        cmdline = {cmdline, $sformatf(" --threads=%0d", num_threads)};
        
        if (xlen_64)
            cmdline = {cmdline, " --xlen=64"};
        
        if (ext_f_enable)
            cmdline = {cmdline, " --ext_f"};
        if (ext_d_enable)
            cmdline = {cmdline, " --ext_d"};
        
        if (l2_enable)
            cmdline = {cmdline, " --l2cache"};
        if (l3_enable)
            cmdline = {cmdline, " --l3cache"};
        
        if (simx_debug_enable)
            cmdline = {cmdline, " --debug=3"};
        
        if (program_path != "")
            cmdline = {cmdline, " ", program_path};
        
        return cmdline;
    endfunction

endclass : vortex_config

`endif // VORTEX_CONFIG_SV