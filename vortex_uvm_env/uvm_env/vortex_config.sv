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
parameter VX_MEM_DATA_WIDTH   = 512; //it was 64 
parameter VX_MEM_TAG_WIDTH    = 8;
parameter VX_MEM_BYTEEN_WIDTH = VX_MEM_DATA_WIDTH/8;


// ===========================================================================
// DCR (Device Configuration Register) Parameters
// From VX_types.vh
// ===========================================================================
parameter VX_DCR_ADDR_WIDTH = 12;  // From VX_types.vh: `VX_DCR_ADDR_BITS 12
parameter VX_DCR_DATA_WIDTH = 32;  // DCR registers are 32-bit

// DCR Base Addresses (from VX_types.vh)
parameter VX_DCR_BASE_STATE_BEGIN       = 12'h001;
parameter VX_DCR_BASE_STARTUP_ADDR0     = 12'h001;  // Startup address 0
parameter VX_DCR_BASE_STARTUP_ADDR1     = 12'h002;  // Startup address 1
parameter VX_DCR_BASE_STARTUP_ARG0      = 12'h003;  // Startup argument 0
parameter VX_DCR_BASE_STARTUP_ARG1      = 12'h004;  // Startup argument 1
parameter VX_DCR_BASE_MPM_CLASS         = 12'h005;  // MPM (Performance Monitoring) class
parameter VX_DCR_BASE_STATE_END         = 12'h006;

// DCR Address Calculation Function
function automatic bit [11:0] VX_DCR_BASE_STATE(input bit [11:0] addr);
    return (addr - VX_DCR_BASE_STATE_BEGIN);
endfunction

parameter VX_DCR_BASE_STATE_COUNT = (VX_DCR_BASE_STATE_END - VX_DCR_BASE_STATE_BEGIN);

// MPM (Performance Monitoring) Classes
parameter VX_DCR_MPM_CLASS_NONE = 0;
parameter VX_DCR_MPM_CLASS_CORE = 1;
parameter VX_DCR_MPM_CLASS_MEM  = 2;

// // ===========================================================================
// // CSR (Control and Status Register) Parameters
// // From VX_types.vh
// // ===========================================================================
// parameter VX_CSR_ADDR_WIDTH = 12;  // From VX_types.vh: `VX_CSR_ADDR_BITS 12

// // Key CSR Addresses
// parameter VX_CSR_FFLAGS      = 12'h001;
// parameter VX_CSR_FRM         = 12'h002;
// parameter VX_CSR_FCSR        = 12'h003;
// parameter VX_CSR_SATP        = 12'h180;
// parameter VX_CSR_MSTATUS     = 12'h300;
// parameter VX_CSR_MISA        = 12'h301;
// parameter VX_CSR_MTVEC       = 12'h305;
// parameter VX_CSR_MSCRATCH    = 12'h340;
// parameter VX_CSR_MEPC        = 12'h341;
// parameter VX_CSR_MCAUSE      = 12'h342;

// // GPU-specific CSR Addresses
// parameter VX_CSR_THREAD_ID   = 12'hCC0;
// parameter VX_CSR_WARP_ID     = 12'hCC1;
// parameter VX_CSR_CORE_ID     = 12'hCC2;
// parameter VX_CSR_NUM_THREADS = 12'hFC0;
// parameter VX_CSR_NUM_WARPS   = 12'hFC1;
// parameter VX_CSR_NUM_CORES   = 12'hFC2;



// ===========================================================================
// General Configuration
// ===========================================================================
parameter STARTUP_ADDR = 32'h80000000;  // Default startup address



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
// AXI4 INTERFACE CONFIGURATION
//==========================================================================

// AXI4 bus parameters
rand int unsigned       AXI_ID_WIDTH;      // AXI transaction ID width (4-16 typical)
rand int unsigned       AXI_ADDR_WIDTH;    // AXI address width (32 or 64)
rand int unsigned       AXI_DATA_WIDTH;    // AXI data width (64, 128, 256, 512)
rand int unsigned       AXI_USER_WIDTH;    // AXI user signal width
rand int unsigned       AXI_STRB_WIDTH;    // AXI strobe width (DATA_WIDTH/8)

// AXI4 burst parameters
rand int unsigned       AXI_MAX_BURST_LEN; // Maximum burst length (1-256)
rand bit [2:0]          AXI_BURST_TYPE;    // 0=FIXED, 1=INCR, 2=WRAP

// AXI4 timing
rand int unsigned       timeout_cycles;    // Transaction timeout in cycles
rand int unsigned       axi_ready_delay_min;
rand int unsigned       axi_ready_delay_max;



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
// CLOCK AND TIMING CONFIGURATION
//==========================================================================

// Clock frequency (for performance calculations)
rand int unsigned       CLK_FREQ_MHZ;          // Clock frequency in MHz
rand real            CLK_PERIOD_NS;         // Clock period in nanoseconds

// Timing parameters
rand int unsigned       max_latency_cycles;    // Maximum expected latency
rand int unsigned       min_inter_req_delay;   // Minimum cycles between requests
rand int unsigned       max_inter_req_delay;   // Maximum cycles between requests
rand int unsigned       status_sample_interval;



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
    
    // AXI configuration constraints
constraint axi_config_c {
    // ID width typically 4-16 bits
    AXI_ID_WIDTH inside {[4:16]};
    
    // Address width matches memory addressing
    AXI_ADDR_WIDTH == mem_addr_width;
    
    // Data width: standard AXI widths
    AXI_DATA_WIDTH inside {32, 64, 128, 256, 512};
    
    // User signals (optional, typically 0-8 bits)
    AXI_USER_WIDTH inside {[0:8]};
    
    // Strobe width derived from data width
    AXI_STRB_WIDTH == (AXI_DATA_WIDTH / 8);
    
    // Burst length: AXI4 supports 1-256
    AXI_MAX_BURST_LEN inside {[1:256]};
    
    // Default to INCR bursts
    soft AXI_BURST_TYPE == 3'b001; // INCR
    
    // Timeout reasonable
    timeout_cycles inside {[1000:100000]};
    
    // Ready delays for realistic timing
    axi_ready_delay_min inside {[0:5]};
    axi_ready_delay_max inside {[axi_ready_delay_min:20]};
}

// Clock and timing constraints
constraint clock_config_c {
    // Typical FPGA/ASIC frequencies
    CLK_FREQ_MHZ inside {[50:500]};
    
    // Period derived from frequency
    // Period (ns) = 1000 / Freq (MHz)
    CLK_PERIOD_NS == (1000.0 / real'(CLK_FREQ_MHZ));
    
    // Reasonable latency bounds
    max_latency_cycles inside {[10:1000]};
    
    // Inter-request delays
    min_inter_req_delay inside {[0:10]};
    max_inter_req_delay inside {[min_inter_req_delay:100]};
    status_sample_interval inside {[10:1000]};
}


    // Default agent configuration
    constraint default_agents_c {
        // Core agents always enabled
        mem_agent_enable == 1;
        dcr_agent_enable == 1;
        host_agent_enable == 1;
        status_agent_enable == 1;
        
        // AXI agent optional (use custom memory by default)
        soft axi_agent_enable == 1;
        
        // Agent activity modes
        mem_agent_is_active == 0;
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

        // AXI4 configuration defaults
`ifdef AXI_ID_WIDTH
    AXI_ID_WIDTH = `AXI_ID_WIDTH;
`else
    AXI_ID_WIDTH = 8;  // 8-bit ID (256 outstanding transactions)
`endif

`ifdef AXI_ADDR_WIDTH
    AXI_ADDR_WIDTH = `AXI_ADDR_WIDTH;
`else
    AXI_ADDR_WIDTH = mem_addr_width;
`endif

`ifdef AXI_DATA_WIDTH
    AXI_DATA_WIDTH = `AXI_DATA_WIDTH;
`else
    AXI_DATA_WIDTH = 64;  // 64-bit data bus (8 bytes)
`endif

AXI_USER_WIDTH = 1;  // Minimal user signals
AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
AXI_MAX_BURST_LEN = 16;  // Max 16-beat bursts
AXI_BURST_TYPE = 3'b001;  // INCR (incrementing address)

timeout_cycles = 10000;  // 10k cycle timeout per transaction
axi_ready_delay_min = 0;
axi_ready_delay_max = 5;


// Clock and timing configuration
`ifdef CLK_FREQ_MHZ
    CLK_FREQ_MHZ = `CLK_FREQ_MHZ;
`else
    CLK_FREQ_MHZ = 100;  // Default 100 MHz
`endif

CLK_PERIOD_NS = 1000.0 / real'(CLK_FREQ_MHZ);
max_latency_cycles = 100;
min_inter_req_delay = 0;
max_inter_req_delay = 10;
status_sample_interval = 100;


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
        axi_agent_enable = 1;
        dcr_agent_enable = 1;
        host_agent_enable = 1;
        status_agent_enable = 1;
        
        mem_agent_is_active = 0;
        axi_agent_is_active = 1;
        dcr_agent_is_active = 1;
        host_agent_is_active = 1;
        status_agent_is_active = 1;
        
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

        `uvm_info("VORTEX_CFG", "\n--- AXI4 Interface ---", verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  ID Width:       %0d bits", AXI_ID_WIDTH), verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  Addr Width:     %0d bits", AXI_ADDR_WIDTH), verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  Data Width:     %0d bits", AXI_DATA_WIDTH), verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  Max Burst Len:  %0d beats", AXI_MAX_BURST_LEN), verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  Timeout:        %0d cycles", timeout_cycles), verbosity)


`uvm_info("VORTEX_CFG", "\n--- Clock and Timing ---", verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  Clock Freq:     %0d MHz", CLK_FREQ_MHZ), verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  Clock Period:   %.2f ns", CLK_PERIOD_NS), verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  Max Latency:    %0d cycles", max_latency_cycles), verbosity)
`uvm_info("VORTEX_CFG", $sformatf("  Status Sample Rate:  %0d cycles", status_sample_interval), verbosity) 

        
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



// /* 
// ////////////////////////////////////////////////////////////////////////////////
// // File: vortex_config.sv
// // Description: Unified UVM configuration class that mirrors VX_config.vh
// //
// // This configuration object provides a 1:1 mapping to the RTL configuration
// // parameters defined in hw/rtl/VX_config.vh from the vortexgpgpu/vortex repo.
// //
// // Configuration hierarchy:
// //   - Hardware Architecture (clusters, cores, warps, threads)
// //   - ISA Extensions (F, D, M, A, C, ZICOND)
// //   - Cache Hierarchy (I$, D$, L2, L3)
// //   - Memory System (addressing, block size)
// //   - Clock and Timing (frequency, sample intervals)
// //   - Simulation/Test Settings
// //
// // Usage:
// //   vortex_config cfg = vortex_config::type_id::create("cfg");
// //   cfg.randomize() with { num_clusters == 2; num_cores == 4; num_warps == 8; };
// //
// // Author: Vortex UVM Team
// ////////////////////////////////////////////////////////////////////////////////

// `ifndef VORTEX_CONFIG_SV
// `define VORTEX_CONFIG_SV

// package vortex_config_pkg;

// import uvm_pkg::*;
// `include "uvm_macros.svh"

// // Memory interface parameters (matching VX_define.vh)
// parameter VX_MEM_ADDR_WIDTH = 32;
// parameter VX_MEM_DATA_WIDTH = 64;
// parameter VX_MEM_TAG_WIDTH = 8;
// parameter VX_MEM_BYTEEN_WIDTH = VX_MEM_DATA_WIDTH / 8;

// // DCR (Device Configuration Register) Parameters (From VX_types.vh)
// parameter VX_DCR_ADDR_WIDTH = 12;  // From VX_types.vh (VX_DCR_ADDR_BITS = 12)
// parameter VX_DCR_DATA_WIDTH = 32;  // DCR registers are 32-bit

// // DCR Base Addresses (from VX_types.vh)
// parameter VX_DCR_BASE_STATE_BEGIN      = 12'h001;
// parameter VX_DCR_BASE_STARTUP_ADDR0    = 12'h001;  // Startup address 0
// parameter VX_DCR_BASE_STARTUP_ADDR1    = 12'h002;  // Startup address 1
// parameter VX_DCR_BASE_STARTUP_ARG0     = 12'h003;  // Startup argument 0
// parameter VX_DCR_BASE_STARTUP_ARG1     = 12'h004;  // Startup argument 1
// parameter VX_DCR_BASE_MPM_CLASS        = 12'h005;  // MPM (Performance Monitoring) class
// parameter VX_DCR_BASE_STATE_END        = 12'h006;

// // DCR Address Calculation Function
// function automatic bit [11:0] VX_DCR_BASE_STATE(input bit [11:0] addr);
//     return addr - VX_DCR_BASE_STATE_BEGIN;
// endfunction

// parameter VX_DCR_BASE_STATE_COUNT = VX_DCR_BASE_STATE_END - VX_DCR_BASE_STATE_BEGIN;

// // MPM (Performance Monitoring) Classes
// parameter VX_DCR_MPM_CLASS_NONE = 0;
// parameter VX_DCR_MPM_CLASS_CORE = 1;
// parameter VX_DCR_MPM_CLASS_MEM  = 2;

// // CSR (Control and Status Register) Parameters (From VX_types.vh)
// parameter VX_CSR_ADDR_WIDTH = 12;  // From VX_types.vh (VX_CSR_ADDR_BITS = 12)

// // Key CSR Addresses
// parameter VX_CSR_FFLAGS    = 12'h001;
// parameter VX_CSR_FRM       = 12'h002;
// parameter VX_CSR_FCSR      = 12'h003;
// parameter VX_CSR_SATP      = 12'h180;
// parameter VX_CSR_MSTATUS   = 12'h300;
// parameter VX_CSR_MISA      = 12'h301;
// parameter VX_CSR_MTVEC     = 12'h305;
// parameter VX_CSR_MSCRATCH  = 12'h340;
// parameter VX_CSR_MEPC      = 12'h341;
// parameter VX_CSR_MCAUSE    = 12'h342;

// // GPU-specific CSR Addresses
// parameter VX_CSR_THREAD_ID   = 12'hCC0;
// parameter VX_CSR_WARP_ID     = 12'hCC1;
// parameter VX_CSR_CORE_ID     = 12'hCC2;
// parameter VX_CSR_NUM_THREADS = 12'hFC0;
// parameter VX_CSR_NUM_WARPS   = 12'hFC1;
// parameter VX_CSR_NUM_CORES   = 12'hFC2;

// // General Configuration
// parameter STARTUP_ADDR = 32'h80000000;  // Default startup address


// //==============================================================================
// // Main Configuration Class
// //==============================================================================
// class vortex_config extends uvm_object;
//     `uvm_object_utils(vortex_config)
    
//     //==========================================================================
//     // ARCHITECTURE CONFIGURATION (Maps to VX_config.vh)
//     //==========================================================================
    
//     // Cluster/Core/Warp/Thread Hierarchy
//     rand int unsigned       num_clusters;      // NUM_CLUSTERS: 1-4 typical
//     rand int unsigned       num_cores;         // NUM_CORES: 1-32
//     rand int unsigned       num_warps;         // NUM_WARPS: 1-16
//     rand int unsigned       num_threads;       // NUM_THREADS: 1-8
//     rand int unsigned       num_barriers;      // NUM_BARRIERS: typically num_warps/2
    
//     // Socket configuration (derived)
//     int unsigned            socket_size;       // SOCKET_SIZE
    
//     //==========================================================================
//     // ISA CONFIGURATION
//     //==========================================================================
    
//     // Base architecture
//     rand bit                xlen_64;           // XLEN=64 or XLEN=32
//     rand int unsigned       xlen;              // Derived: 64 or 32
    
//     // Standard RISC-V Extensions
//     rand bit                ext_f_enable;      // EXT_F_ENABLE: single-precision float
//     rand bit                ext_d_enable;      // EXT_D_ENABLE: double-precision float
//     rand bit                ext_m_enable;      // EXT_M_ENABLE: multiply/divide
//     rand bit                ext_a_enable;      // EXT_A_ENABLE: atomic operations
//     rand bit                ext_c_enable;      // EXT_C_ENABLE: compressed instructions
//     rand bit                ext_zicond_enable; // EXT_ZICOND_ENABLE: conditional operations
    
//     // Floating-point configuration
//     rand int unsigned       flen;              // FLEN: 32 or 64
    
//     //==========================================================================
//     // CACHE HIERARCHY (Enable/Disable and Sizes)
//     //==========================================================================
    
//     // Cache enables
//     rand bit                icache_enable;     // ICACHE_ENABLE
//     rand bit                dcache_enable;     // DCACHE_ENABLE
//     rand bit                l2_enable;         // L2_ENABLE
//     rand bit                l3_enable;         // L3_ENABLE
    
//     // Cache sizes (in bytes)
//     rand int unsigned       icache_size;       // ICACHE_SIZE
//     rand int unsigned       dcache_size;       // DCACHE_SIZE
//     rand int unsigned       l2cache_size;      // L2CACHE_SIZE
//     rand int unsigned       l3cache_size;      // L3CACHE_SIZE
    
//     // Cache line size
//     rand int unsigned       cache_line_size;   // Typically 64 bytes
    
//     // Number of cache instances (derived)
//     int unsigned            num_icaches;       // NUM_ICACHES
//     int unsigned            num_dcaches;       // NUM_DCACHES
    
//     //==========================================================================
//     // MEMORY SYSTEM CONFIGURATION
//     //==========================================================================
    
//     // Memory parameters
//     rand int unsigned       mem_block_size;    // MEM_BLOCK_SIZE: 32, 64, 128
//     rand int unsigned       mem_addr_width;    // MEM_ADDR_WIDTH: 32 or 48
//     rand int unsigned       mem_data_width;    // MEM_DATA_WIDTH: typically 64
//     rand int unsigned       mem_tag_width;     // MEM_TAG_WIDTH
//     rand int unsigned       mem_byteen_width;  // MEM_BYTEEN_WIDTH = mem_data_width/8
    
//     // Memory address regions
//     rand bit [63:0]         startup_addr;      // STARTUP_ADDR: default 0x80000000
//     rand bit [63:0]         stack_base_addr;   // Stack base address
//     rand bit [63:0]         io_base_addr;      // IO_BASE_ADDR
//     rand bit [63:0]         io_addr_end;       // IO_ADDR_END
    
//     //==========================================================================
//     // PIPELINE CONFIGURATION
//     //==========================================================================
    
//     // Issue width and buffer sizes
//     rand int unsigned       issue_width;       // ISSUE_WIDTH: 1 or 2
//     rand int unsigned       ibuf_size;         // IBUF_SIZE: instruction buffer
    
//     // Execution lanes
//     rand int unsigned       num_alu_lanes;     // NUM_ALU_LANES = NUM_THREADS
//     rand int unsigned       num_fpu_lanes;     // NUM_FPU_LANES = NUM_THREADS
//     rand int unsigned       num_lsu_lanes;     // NUM_LSU_LANES = NUM_THREADS
    
//     //==========================================================================
//     // DCR (DEVICE CONFIGURATION REGISTER) ADDRESSES
//     //==========================================================================
    
//     // DCR base addresses (from VX_define.vh)
//     bit [31:0]              dcr_base_startup_addr0;  // VX_DCR_BASE_STARTUP_ADDR0
//     bit [31:0]              dcr_base_mpm_class;      // VX_DCR_BASE_MPM_CLASS
    
//     //==========================================================================
//     // CLOCK AND TIMING CONFIGURATION
//     //==========================================================================
    
//     rand int unsigned       CLK_FREQ_MHZ;           // Clock frequency in MHz
//     rand real               CLK_PERIOD_NS;          // Clock period in ns
//     rand int unsigned       max_latency_cycles;     // Max expected latency
//     rand int unsigned       min_inter_req_delay;    // Min cycles between reqs
//     rand int unsigned       max_inter_req_delay;    // Max cycles between reqs
//     rand int unsigned       status_sample_interval; // Status sampling interval in cycles
    
//     //==========================================================================
//     // SIMULATION/TEST CONFIGURATION
//     //==========================================================================
    
//     // Timeouts
//     rand int unsigned       global_timeout_cycles;
//     rand int unsigned       test_timeout_cycles;
//     rand int unsigned       reset_cycles;
//     rand int unsigned       reset_delay;           // RESET_DELAY
    
//     // Verbosity
//     rand uvm_verbosity      default_verbosity;
//     rand bit                enable_transaction_recording;
//     rand bit                enable_coverage;
//     rand bit                enable_assertions;
    
//     // Debug and tracing
//     rand bit                dump_waves;
//     string                  wave_filename;
//     rand bit                trace_enable;
//     rand int unsigned       trace_level;          // 0-3
    
//     //==========================================================================
//     // AGENT CONFIGURATION
//     //==========================================================================
    
//     // Agent enables
//     rand bit                mem_agent_enable;
//     rand bit                axi_agent_enable;
//     rand bit                dcr_agent_enable;
//     rand bit                host_agent_enable;
//     rand bit                status_agent_enable;
    
//     // Agent modes (active/passive)
//     rand bit                mem_agent_is_active;
//     rand bit                axi_agent_is_active;
//     rand bit                dcr_agent_is_active;
//     rand bit                host_agent_is_active;
//     rand bit                status_agent_is_active;  // Always passive
    
//     //==========================================================================
//     // GOLDEN MODEL (simx) CONFIGURATION
//     //==========================================================================
    
//     rand bit                simx_enable;
//     string                  simx_path;
//     rand bit                simx_debug_enable;
//     rand int unsigned       simx_timeout_cycles;
//     string                  simx_trace_file;
    
//     //==========================================================================
//     // TEST-SPECIFIC CONFIGURATION
//     //==========================================================================
    
//     // Program/kernel configuration
//     string                  program_path;
//     string                  program_type;         // "hex", "elf", "bin"
//     rand bit [63:0]         program_load_addr;
//     rand bit [63:0]         program_entry_point;
    
//     // Kernel launch parameters
//     rand bit [31:0]         kernel_num_groups;
//     rand bit [31:0]         kernel_group_size;
    
//     // Memory initialization
//     rand bit                init_memory_random;
//     rand bit                clear_memory_on_reset;
    
//     // Result checking
//     rand bit [63:0]         result_base_addr;
//     rand int unsigned       result_size_bytes;
    
//     //==========================================================================
//     // SCOREBOARD CONFIGURATION
//     //==========================================================================
    
//     rand bit                enable_scoreboard;
//     rand bit                strict_ordering;
//     rand bit                compare_on_the_fly;
    
    
//     //==========================================================================
//     // CONSTRAINTS (Matching Vortex Hardware Limitations)
//     //==========================================================================
    
//     // Hardware architecture constraints
//     constraint valid_hw_config_c {
//         // Cluster/Core scaling
//         num_clusters inside {[1:4]};
//         num_cores inside {[1:32]};
//         num_warps inside {[1:16]};
//         num_threads inside {[1:8]};
        
//         // Barriers are typically half the warps
//         num_barriers == num_warps / 2;
        
//         // Cache sizes must be powers of 2
//         icache_size inside {4096, 8192, 16384, 32768, 65536};
//         dcache_size inside {4096, 8192, 16384, 32768, 65536};
//         l2cache_size inside {65536, 131072, 262144, 524288, 1048576};
//         l3cache_size inside {262144, 524288, 1048576, 2097152};
        
//         // Memory parameters
//         mem_block_size inside {32, 64, 128};
//         mem_addr_width inside {32, 48};
//         mem_data_width inside {32, 64};
        
//         // Cache line size
//         cache_line_size inside {32, 64};
        
//         // Issue width
//         issue_width inside {1, 2};
        
//         // Instruction buffer size
//         ibuf_size inside {2, 4, 8};
//     }
    
//     // ISA consistency constraints
//     constraint isa_consistency_c {
//         // D extension requires F extension
//         ext_d_enable -> ext_f_enable;
        
//         // FLEN determined by extensions
//         if (ext_d_enable) {
//             flen == 64;
//         } else if (ext_f_enable) {
//             flen == 32;
//         } else {
//             flen == 0;
//         }
        
//         // XLEN consistency
//         xlen == (xlen_64 ? 64 : 32);
//     }
    
//     // Cache hierarchy constraints
//     constraint cache_hierarchy_c {
//         // L3 requires L2, L2 can exist independently
//         l3_enable -> l2_enable;
        
//         // L3 requires multiple clusters
//         l3_enable -> (num_clusters > 1);
        
//         // If caches disabled, set sizes to 0
//         if (!icache_enable) icache_size == 0;
//         if (!dcache_enable) dcache_size == 0;
//         if (!l2_enable) l2cache_size == 0;
//         if (!l3_enable) l3cache_size == 0;
//     }
    
//     // Execution lane constraints
//     constraint lane_config_c {
//         // Lanes == number of threads
//         num_alu_lanes == num_threads;
//         num_fpu_lanes == num_threads;
//         num_lsu_lanes == num_threads;
//     }
    
//     // Clock and timing constraints
//     constraint clock_config_c {
//         // Typical FPGA/ASIC frequencies
//         CLK_FREQ_MHZ inside {[50:500]};
        
//         // Period derived from frequency
//         CLK_PERIOD_NS == (1000.0 / real'(CLK_FREQ_MHZ));
        
//         // Reasonable latency bounds
//         max_latency_cycles inside {[10:1000]};
        
//         // Inter-request delays
//         min_inter_req_delay inside {[0:10]};
//         max_inter_req_delay inside {[min_inter_req_delay:100]};
        
//         // Status sampling interval
//         status_sample_interval inside {[10:1000]};
//     }
    
//     // Default agent configuration
//     constraint default_agents_c {
//         // Core agents always enabled
//         mem_agent_enable == 1;
//         dcr_agent_enable == 1;
//         host_agent_enable == 1;
//         status_agent_enable == 1;
        
//         // AXI agent optional (use custom memory by default)
//         soft axi_agent_enable == 0;
        
//         // Agent activity modes
//         mem_agent_is_active == 1;
//         dcr_agent_is_active == 1;
//         host_agent_is_active == 1;
//         status_agent_is_active == 0;  // Always passive
//     }
    
//     // Timeout constraints
//     constraint reasonable_timeouts_c {
//         global_timeout_cycles inside {[50000:1000000]};
//         test_timeout_cycles inside {[10000:100000]};
//         reset_cycles inside {[10:100]};
//         reset_delay inside {[10:100]};
//         simx_timeout_cycles == test_timeout_cycles;
//     }
    
//     // Memory addressing constraints
//     constraint valid_memory_addrs_c {
//         // 32-bit mode: upper bits must be zero
//         if (!xlen_64) {
//             startup_addr[63:32] == 32'h0;
//             stack_base_addr[63:32] == 32'h0;
//             io_base_addr[63:32] == 32'h0;
//             io_addr_end[63:32] == 32'h0;
//             program_load_addr[63:32] == 32'h0;
//             program_entry_point[63:32] == 32'h0;
//             result_base_addr[63:32] == 32'h0;
//         }
        
//         // Word-aligned addresses
//         startup_addr[1:0] == 2'b00;
//         program_load_addr[1:0] == 2'b00;
//         program_entry_point[1:0] == 2'b00;
//         result_base_addr[1:0] == 2'b00;
        
//         // IO address range validity
//         io_addr_end > io_base_addr;
//     }
    
    
//     //==========================================================================
//     // CONSTRUCTOR
//     //==========================================================================
    
//     function new(string name = "vortex_config");
//         super.new(name);
        
//         // Initialize from VX_config.vh defaults
//         set_defaults_from_vx_config();
//     endfunction
    
    
//     //==========================================================================
//     // CONFIGURATION METHODS
//     //==========================================================================
    
//     // Set defaults matching VX_config.vh
//     virtual function void set_defaults_from_vx_config();
//         // Architecture defaults
//         `ifdef NUM_CLUSTERS
//             num_clusters = `NUM_CLUSTERS;
//         `else
//             num_clusters = 1;
//         `endif
        
//         `ifdef NUM_CORES
//             num_cores = `NUM_CORES;
//         `else
//             num_cores = 1;
//         `endif
        
//         `ifdef NUM_WARPS
//             num_warps = `NUM_WARPS;
//         `else
//             num_warps = 4;
//         `endif
        
//         `ifdef NUM_THREADS
//             num_threads = `NUM_THREADS;
//         `else
//             num_threads = 4;
//         `endif
        
//         `ifdef NUM_BARRIERS
//             num_barriers = `NUM_BARRIERS;
//         `else
//             num_barriers = num_warps / 2;
//         `endif
        
//         // ISA configuration
//         `ifdef XLEN_64
//             xlen_64 = 1;
//             xlen = 64;
//         `else
//             xlen_64 = 0;
//             xlen = 32;
//         `endif
        
//         `ifdef EXT_F_ENABLE
//             ext_f_enable = `EXT_F_ENABLE;
//         `else
//             ext_f_enable = 1;
//         `endif
        
//         `ifdef EXT_D_ENABLE
//             ext_d_enable = `EXT_D_ENABLE;
//         `else
//             ext_d_enable = 0;
//         `endif
        
//         `ifdef EXT_M_ENABLE
//             ext_m_enable = `EXT_M_ENABLE;
//         `else
//             ext_m_enable = 1;
//         `endif
        
//         `ifdef EXT_A_ENABLE
//             ext_a_enable = `EXT_A_ENABLE;
//         `else
//             ext_a_enable = 0;
//         `endif
        
//         `ifdef EXT_C_ENABLE
//             ext_c_enable = `EXT_C_ENABLE;
//         `else
//             ext_c_enable = 0;
//         `endif
        
//         `ifdef EXT_ZICOND_ENABLE
//             ext_zicond_enable = `EXT_ZICOND_ENABLE;
//         `else
//             ext_zicond_enable = 1;
//         `endif
        
//         // FLEN based on extensions
//         if (ext_d_enable)
//             flen = 64;
//         else if (ext_f_enable)
//             flen = 32;
//         else
//             flen = 0;
        
//         // Cache enables
//         `ifdef ICACHE_ENABLE
//             icache_enable = `ICACHE_ENABLE;
//         `else
//             icache_enable = 1;
//         `endif
        
//         `ifdef DCACHE_ENABLE
//             dcache_enable = `DCACHE_ENABLE;
//         `else
//             dcache_enable = 1;
//         `endif
        
//         `ifdef L2_ENABLE
//             l2_enable = `L2_ENABLE;
//         `else
//             l2_enable = 0;
//         `endif
        
//         `ifdef L3_ENABLE
//             l3_enable = `L3_ENABLE;
//         `else
//             l3_enable = 0;
//         `endif
        
//         // Cache sizes
//         `ifdef ICACHE_SIZE
//             icache_size = `ICACHE_SIZE;
//         `else
//             icache_size = 16384;  // 16KB
//         `endif
        
//         `ifdef DCACHE_SIZE
//             dcache_size = `DCACHE_SIZE;
//         `else
//             dcache_size = 16384;  // 16KB
//         `endif
        
//         `ifdef L2CACHE_SIZE
//             l2cache_size = `L2CACHE_SIZE;
//         `else
//             l2cache_size = 131072;  // 128KB
//         `endif
        
//         `ifdef L3CACHE_SIZE
//             l3cache_size = `L3CACHE_SIZE;
//         `else
//             l3cache_size = 524288;  // 512KB
//         `endif
        
//         cache_line_size = 64;
        
//         // Derived cache counts
//         socket_size = (num_cores <= 4) ? num_cores : 4;
//         num_icaches = icache_enable ? ((socket_size + 3) / 4) : 0;
//         num_dcaches = dcache_enable ? ((socket_size + 3) / 4) : 0;
        
//         // Memory system
//         `ifdef MEM_BLOCK_SIZE
//             mem_block_size = `MEM_BLOCK_SIZE;
//         `else
//             mem_block_size = 64;
//         `endif
        
//         `ifdef MEM_ADDR_WIDTH
//             mem_addr_width = `MEM_ADDR_WIDTH;
//         `else
//             mem_addr_width = xlen_64 ? 48 : 32;
//         `endif
        
//         mem_data_width = 64;
//         mem_tag_width = 8;
//         mem_byteen_width = mem_data_width / 8;
        
//         `ifdef STARTUP_ADDR
//             startup_addr = `STARTUP_ADDR;
//         `else
//             startup_addr = 64'h80000000;
//         `endif
        
//         stack_base_addr = startup_addr + 64'h100000;  // 1MB after startup
        
//         `ifdef IO_BASE_ADDR
//             io_base_addr = `IO_BASE_ADDR;
//         `else
//             io_base_addr = 64'hFF000000;
//         `endif
        
//         `ifdef IO_ADDR_END
//             io_addr_end = `IO_ADDR_END;
//         `else
//             io_addr_end = 64'hFFFFFFFF;
//         `endif
        
//         // Pipeline configuration
//         issue_width = (num_warps > 8) ? 1 : (num_warps / 8);
//         ibuf_size = 4;
//         num_alu_lanes = num_threads;
//         num_fpu_lanes = num_threads;
//         num_lsu_lanes = num_threads;
        
//         // DCR addresses from VX_define.vh
//         `ifdef VX_DCR_BASE_STARTUP_ADDR0
//             dcr_base_startup_addr0 = `VX_DCR_BASE_STARTUP_ADDR0;
//         `else
//             dcr_base_startup_addr0 = 32'h00000800;
//         `endif
        
//         `ifdef VX_DCR_BASE_MPM_CLASS
//             dcr_base_mpm_class = `VX_DCR_BASE_MPM_CLASS;
//         `else
//             dcr_base_mpm_class = 32'h00000840;
//         `endif
        
//         // Clock and timing configuration
//         `ifdef CLK_FREQ_MHZ
//             CLK_FREQ_MHZ = `CLK_FREQ_MHZ;
//         `else
//             CLK_FREQ_MHZ = 100;  // Default 100 MHz
//         `endif
        
//         CLK_PERIOD_NS = 1000.0 / real'(CLK_FREQ_MHZ);
//         max_latency_cycles = 100;
//         min_inter_req_delay = 0;
//         max_inter_req_delay = 10;
//         status_sample_interval = 100;  // Sample status every 100 cycles
        
//         // Simulation settings
//         global_timeout_cycles = 100000;
//         test_timeout_cycles = 50000;
        
//         `ifdef RESET_DELAY
//             reset_cycles = `RESET_DELAY;
//             reset_delay = `RESET_DELAY;
//         `else
//             reset_cycles = 20;
//             reset_delay = 20;
//         `endif
        
//         default_verbosity = UVM_MEDIUM;
//         enable_transaction_recording = 1;
//         enable_coverage = 1;
//         enable_assertions = 1;
        
//         dump_waves = 1;
//         wave_filename = "vortex_sim.vcd";
//         trace_enable = 0;
//         trace_level = 0;
        
//         // Agent configuration
//         mem_agent_enable = 1;
//         axi_agent_enable = 0;
//         dcr_agent_enable = 1;
//         host_agent_enable = 1;
//         status_agent_enable = 1;
        
//         mem_agent_is_active = 1;
//         axi_agent_is_active = 0;
//         dcr_agent_is_active = 1;
//         host_agent_is_active = 1;
//         status_agent_is_active = 0;
        
//         // Golden model
//         simx_enable = 1;
//         simx_path = {$getenv("VORTEX_HOME"), "/sim/simx/simx"};
//         simx_debug_enable = 0;
//         simx_timeout_cycles = test_timeout_cycles;
//         simx_trace_file = "simx_trace.log";
        
//         // Test configuration
//         program_path = "";
//         program_type = "hex";
//         program_load_addr = startup_addr;
//         program_entry_point = startup_addr;
//         kernel_num_groups = 1;
//         kernel_group_size = num_threads;
        
//         init_memory_random = 0;
//         clear_memory_on_reset = 1;
        
//         result_base_addr = startup_addr + 64'h100000;
//         result_size_bytes = 1024;
        
//         // Scoreboard
//         enable_scoreboard = 1;
//         strict_ordering = 0;
//         compare_on_the_fly = 1;
//     endfunction
    
    
//     // Apply command-line plusargs (matching Vortex blackbox.sh)
//     virtual function void apply_plusargs();
//         int tmp;
//         string str_tmp;
        
//         // Architecture configuration
//         if ($value$plusargs("CLUSTERS=%d", tmp) || $value$plusargs("clusters=%d", tmp))
//             num_clusters = tmp;
//         if ($value$plusargs("CORES=%d", tmp) || $value$plusargs("cores=%d", tmp))
//             num_cores = tmp;
//         if ($value$plusargs("WARPS=%d", tmp) || $value$plusargs("warps=%d", tmp))
//             num_warps = tmp;
//         if ($value$plusargs("THREADS=%d", tmp) || $value$plusargs("threads=%d", tmp))
//             num_threads = tmp;
        
//         // Cache enables
//         if ($test$plusargs("L2CACHE") || $test$plusargs("l2cache"))
//             l2_enable = 1;
//         if ($test$plusargs("L3CACHE") || $test$plusargs("l3cache"))
//             l3_enable = 1;
        
//         // ISA options
//         if ($test$plusargs("XLEN64") || $test$plusargs("xlen64")) begin
//             xlen_64 = 1;
//             xlen = 64;
//         end
        
//         // Program configuration
//         if ($value$plusargs("PROGRAM=%s", str_tmp) || $value$plusargs("APP=%s", str_tmp))
//             program_path = str_tmp;
//         if ($value$plusargs("HEX=%s", str_tmp))
//             program_path = str_tmp;
//         if ($value$plusargs("STARTUP_ADDR=%h", tmp))
//             startup_addr = tmp;
        
//         // Simulation control
//         if ($value$plusargs("TIMEOUT=%d", tmp))
//             test_timeout_cycles = tmp;
//         if ($test$plusargs("NOWAVES") || $test$plusargs("nowaves"))
//             dump_waves = 0;
//         if ($test$plusargs("DISABLE_SIMX") || $test$plusargs("disable_simx"))
//             simx_enable = 0;
        
//         // Debug/verbosity
//         if ($test$plusargs("VERBOSE") || $test$plusargs("verbose"))
//             default_verbosity = UVM_HIGH;
//         if ($test$plusargs("DEBUG") || $test$plusargs("debug") || $value$plusargs("DEBUG=%d", tmp)) begin
//             default_verbosity = UVM_DEBUG;
//             trace_enable = 1;
//             trace_level = (tmp > 0) ? tmp : 1;
//         end
//         if ($value$plusargs("TRACE=%d", tmp)) begin
//             trace_enable = 1;
//             trace_level = tmp;
//         end
        
//         // Driver selection
//         if ($value$plusargs("DRIVER=%s", str_tmp)) begin
//             case (str_tmp)
//                 "rtlsim", "vlsim": begin
//                     // RTL simulation mode
//                 end
//                 "simx": begin
//                     simx_enable = 1;
//                 end
//                 "fpga", "opae", "xrt": begin
//                     // FPGA mode
//                     simx_enable = 0;
//                 end
//             endcase
//         end
        
//         // Recalculate derived parameters
//         num_barriers = num_warps / 2;
//         socket_size = (num_cores <= 4) ? num_cores : 4;
//         num_icaches = icache_enable ? ((socket_size + 3) / 4) : 0;
//         num_dcaches = dcache_enable ? ((socket_size + 3) / 4) : 0;
//         num_alu_lanes = num_threads;
//         num_fpu_lanes = num_threads;
//         num_lsu_lanes = num_threads;
//         issue_width = (num_warps > 8) ? 1 : (num_warps / 8);
//     endfunction
    
    
//     // Print comprehensive configuration summary
//     virtual function void print_config(uvm_verbosity verbosity = UVM_MEDIUM);
//         `uvm_info("VORTEX_CFG", "==================================================================", verbosity)
//         `uvm_info("VORTEX_CFG", "  VORTEX UVM CONFIGURATION SUMMARY", verbosity)
//         `uvm_info("VORTEX_CFG", "  (Mirrors hw/rtl/VX_config.vh)", verbosity)
//         `uvm_info("VORTEX_CFG", "==================================================================", verbosity)
        
//         `uvm_info("VORTEX_CFG", "\n--- Hardware Architecture ---", verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Clusters:       %0d", num_clusters), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Cores:          %0d", num_cores), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Warps:          %0d", num_warps), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Threads:        %0d", num_threads), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Barriers:       %0d", num_barriers), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Socket Size:    %0d", socket_size), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Issue Width:    %0d", issue_width), verbosity)
        
//         `uvm_info("VORTEX_CFG", "\n--- ISA Configuration ---", verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  XLEN:           %0d", xlen), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  FLEN:           %0d", flen), verbosity)
//         `uvm_info("VORTEX_CFG", "  Extensions:", verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("    F (Float):    %s", ext_f_enable ? "✓" : "✗"), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("    D (Double):   %s", ext_d_enable ? "✓" : "✗"), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("    M (Mul/Div):  %s", ext_m_enable ? "✓" : "✗"), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("    A (Atomic):   %s", ext_a_enable ? "✓" : "✗"), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("    C (Compress): %s", ext_c_enable ? "✓" : "✗"), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("    ZICOND:       %s", ext_zicond_enable ? "✓" : "✗"), verbosity)
        
//         `uvm_info("VORTEX_CFG", "\n--- Cache Hierarchy ---", verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  I$:             %s (%0d KB, %0d instances)", 
//             icache_enable ? "ON" : "OFF", icache_size/1024, num_icaches), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  D$:             %s (%0d KB, %0d instances)", 
//             dcache_enable ? "ON" : "OFF", dcache_size/1024, num_dcaches), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  L2:             %s (%0d KB)", 
//             l2_enable ? "ON" : "OFF", l2cache_size/1024), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  L3:             %s (%0d KB)", 
//             l3_enable ? "ON" : "OFF", l3cache_size/1024), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Line Size:      %0d bytes", cache_line_size), verbosity)
        
//         `uvm_info("VORTEX_CFG", "\n--- Memory System ---", verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Block Size:     %0d bytes", mem_block_size), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Addr Width:     %0d bits", mem_addr_width), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Data Width:     %0d bits", mem_data_width), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Startup Addr:   0x%h", startup_addr), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Stack Base:     0x%h", stack_base_addr), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  IO Base:        0x%h", io_base_addr), verbosity)
        
//         `uvm_info("VORTEX_CFG", "\n--- Pipeline Configuration ---", verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  ALU Lanes:      %0d", num_alu_lanes), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  FPU Lanes:      %0d", num_fpu_lanes), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  LSU Lanes:      %0d", num_lsu_lanes), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Issue Width:    %0d", issue_width), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  IBUF Size:      %0d", ibuf_size), verbosity)
        
//         `uvm_info("VORTEX_CFG", "\n--- Clock and Timing ---", verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Clock Freq:          %0d MHz", CLK_FREQ_MHZ), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Clock Period:        %.2f ns", CLK_PERIOD_NS), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Max Latency:         %0d cycles", max_latency_cycles), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Status Sample Rate:  %0d cycles", status_sample_interval), verbosity)
        
//         `uvm_info("VORTEX_CFG", "\n--- Simulation Settings ---", verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Test Timeout:   %0d cycles", test_timeout_cycles), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Reset Cycles:   %0d", reset_cycles), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Dump Waves:     %s", dump_waves ? "YES" : "NO"), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  simx Enable:    %s", simx_enable ? "YES" : "NO"), verbosity)
//         `uvm_info("VORTEX_CFG", $sformatf("  Verbosity:      %s", default_verbosity.name()), verbosity)
        
//         if (program_path != "")
//             `uvm_info("VORTEX_CFG", $sformatf("  Program:        %s", program_path), verbosity)
        
//         `uvm_info("VORTEX_CFG", "==================================================================", verbosity)
//     endfunction
    
    
//     // Generate Verilog defines for compilation
//     virtual function string get_verilog_defines();
//         string defines = "";
        
//         defines = {defines, $sformatf("+define+NUM_CLUSTERS=%0d ", num_clusters)};
//         defines = {defines, $sformatf("+define+NUM_CORES=%0d ", num_cores)};
//         defines = {defines, $sformatf("+define+NUM_WARPS=%0d ", num_warps)};
//         defines = {defines, $sformatf("+define+NUM_THREADS=%0d ", num_threads)};
//         defines = {defines, $sformatf("+define+NUM_BARRIERS=%0d ", num_barriers)};
        
//         if (xlen_64)
//             defines = {defines, "+define+XLEN_64 "};
        
//         if (ext_f_enable)
//             defines = {defines, "+define+EXT_F_ENABLE=1 "};
//         if (ext_d_enable)
//             defines = {defines, "+define+EXT_D_ENABLE=1 "};
//         if (ext_m_enable)
//             defines = {defines, "+define+EXT_M_ENABLE=1 "};
//         if (ext_a_enable)
//             defines = {defines, "+define+EXT_A_ENABLE=1 "};
//         if (ext_c_enable)
//             defines = {defines, "+define+EXT_C_ENABLE=1 "};
//         if (ext_zicond_enable)
//             defines = {defines, "+define+EXT_ZICOND_ENABLE=1 "};
        
//         if (icache_enable)
//             defines = {defines, "+define+ICACHE_ENABLE=1 "};
//         if (dcache_enable)
//             defines = {defines, "+define+DCACHE_ENABLE=1 "};
//         if (l2_enable)
//             defines = {defines, "+define+L2_ENABLE=1 "};
//         if (l3_enable)
//             defines = {defines, "+define+L3_ENABLE=1 "};
        
//         defines = {defines, $sformatf("+define+ICACHE_SIZE=%0d ", icache_size)};
//         defines = {defines, $sformatf("+define+DCACHE_SIZE=%0d ", dcache_size)};
//         defines = {defines, $sformatf("+define+L2CACHE_SIZE=%0d ", l2cache_size)};
//         defines = {defines, $sformatf("+define+L3CACHE_SIZE=%0d ", l3cache_size)};
//         defines = {defines, $sformatf("+define+MEM_BLOCK_SIZE=%0d ", mem_block_size)};
//         defines = {defines, $sformatf("+define+STARTUP_ADDR=64'h%h ", startup_addr)};
        
//         return defines;
//     endfunction
    
    
//     // Validate configuration consistency
//     virtual function bit is_valid();
//         bit valid = 1;
        
//         if (num_cores == 0 || num_warps == 0 || num_threads == 0) begin
//             `uvm_error("VORTEX_CFG", "Invalid: zero cores/warps/threads")
//             valid = 0;
//         end
        
//         if (ext_d_enable && !ext_f_enable) begin
//             `uvm_error("VORTEX_CFG", "Invalid ISA: D extension requires F extension")
//             valid = 0;
//         end
        
//         if (l3_enable && !l2_enable) begin
//             `uvm_error("VORTEX_CFG", "Invalid cache: L3 requires L2")
//             valid = 0;
//         end
        
//         if (l3_enable && (num_clusters == 1)) begin
//             `uvm_warning("VORTEX_CFG", "L3 cache typically requires multiple clusters")
//         end
        
//         if (simx_enable && (simx_path == "")) begin
//             `uvm_error("VORTEX_CFG", "simx enabled but path not specified")
//             valid = 0;
//         end
        
//         if (!xlen_64 && (mem_addr_width > 32)) begin
//             `uvm_error("VORTEX_CFG", "32-bit mode cannot have addr_width > 32")
//             valid = 0;
//         end
        
//         return valid;
//     endfunction
    
    
//     // Get configuration summary string (for logging)
//     virtual function string get_config_string();
//         return $sformatf("%0dC/%0dW/%0dT[%s%s]",
//             num_cores, num_warps, num_threads,
//             xlen_64 ? "RV64" : "RV32",
//             ext_f_enable ? (ext_d_enable ? "FD" : "F") : "");
//     endfunction

// endclass : vortex_config

// endpackage : vortex_config_pkg

// `endif // VORTEX_CONFIG_SV

// */



/*


////////////////////////////////////////////////////////////////////////////////
// File: vortex_config.sv (COMPREHENSIVE - Fixes All 3 Previous Versions)
// Description: Unified UVM configuration package that mirrors VX_config.vh,
//              VX_types.vh, and VX_define.vh from the official Vortex repo
//
// CRITICAL FIX: All parameters are now `localparam` (Verilog-accessible)
// instead of `parameter`, allowing interfaces to read them via scope resolution
//
// This file serves as the SINGLE SOURCE OF TRUTH for:
//   1. Hardware architecture configuration (clusters, cores, warps, threads)
//   2. Memory interface parameters (widths, addressing)
//   3. DCR (Device Configuration Register) address space
//   4. AXI4 bus parameters
//   5. ISA extensions
//   6. Cache hierarchy
//   7. UVM configuration and test control
//
// Integration Flow:
//   1. vortex_config_pkg exports localparam values
//   2. Interfaces (vortex_mem_if, vortex_dcr_if, etc.) import these
//   3. Testbench and RTL use consistent configuration
//   4. UVM test reads via plusargs and applies to simulation
//
// Usage:
//   - Interfaces: import vortex_config_pkg::*; localparam ADDR_WIDTH = VX_MEM_ADDR_WIDTH;
//   - Tests: cfg.apply_plusargs(); cfg.print_config();
//   - Scripts: run_uvmt.sh +CORES=4 +WARPS=8 +PROGRAM=app.hex
//
// Author: Vortex UVM Team
// Last Updated: December 28, 2025
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_CONFIG_SV
`define VORTEX_CONFIG_SV

package vortex_config_pkg;

import uvm_pkg::*;
`include "uvm_macros.svh"

// ============================================================================
// SECTION 1: MEMORY INTERFACE PARAMETERS
// (CRITICAL: These are localparam so interfaces can read them!)
// ============================================================================

parameter int unsigned VX_MEM_ADDR_WIDTH   = 32;  // Memory address width
parameter int unsigned VX_MEM_DATA_WIDTH   = 64;  // Memory data width (8 bytes)
parameter int unsigned VX_MEM_TAG_WIDTH    = 8;   // Memory request tag
parameter int unsigned VX_MEM_BYTEEN_WIDTH = VX_MEM_DATA_WIDTH / 8;  // Byte enables

// ============================================================================
// SECTION 2: DCR (DEVICE CONFIGURATION REGISTER) PARAMETERS
// From VX_types.vh - CRITICAL FOR DCR INTERFACE
// ============================================================================

parameter int unsigned VX_DCR_ADDR_WIDTH = 12;   // DCR address width
parameter int unsigned VX_DCR_DATA_WIDTH = 32;   // DCR data width (32-bit registers)

// DCR Base Addresses - These were MISSING in previous versions!
// Now explicitly defined so vortex_dcr_if.sv can find them
parameter bit [11:0] VX_DCR_BASE_STARTUP_ADDR0  = 12'h001;  // Startup PC low
parameter bit [11:0] VX_DCR_BASE_STARTUP_ADDR1  = 12'h002;  // Startup PC high
parameter bit [11:0] VX_DCR_BASE_STARTUP_ARG0   = 12'h003;  // Startup arg 0
parameter bit [11:0] VX_DCR_BASE_STARTUP_ARG1   = 12'h004;  // Startup arg 1
parameter bit [11:0] VX_DCR_BASE_MPM_CLASS      = 12'h005;  // Performance monitoring class
// DCR register count
parameter bit [11:0] VX_DCR_BASE_STATE_BEGIN = 12'h001;
parameter bit [11:0] VX_DCR_BASE_STATE_END   = 12'h006;
parameter int unsigned VX_DCR_BASE_STATE_COUNT = (VX_DCR_BASE_STATE_END - VX_DCR_BASE_STATE_BEGIN);

// MPM (Performance Monitoring) class values
parameter int unsigned VX_DCR_MPM_CLASS_NONE = 0;
parameter int unsigned VX_DCR_MPM_CLASS_CORE = 1;
parameter int unsigned VX_DCR_MPM_CLASS_MEM  = 2;

// ============================================================================
// SECTION 3: HARDWARE ARCHITECTURE (Mirror VX_config.vh)
// ============================================================================

// Cluster/Core/Warp/Thread Hierarchy
parameter int unsigned NUM_CLUSTERS = 1;      // NUM_CLUSTERS
parameter int unsigned NUM_CORES    = 1;      // NUM_CORES
parameter int unsigned NUM_WARPS    = 4;      // NUM_WARPS
parameter int unsigned NUM_THREADS  = 4;      // NUM_THREADS

// Derived parameters
parameter int unsigned NUM_BARRIERS = (NUM_WARPS + 1) / 2;  // ~NUM_WARPS/2
parameter int unsigned SOCKET_SIZE  = (NUM_CORES <= 4) ? NUM_CORES : 4;
parameter int unsigned NUM_SOCKETS  = (NUM_CORES + SOCKET_SIZE - 1) / SOCKET_SIZE;

// ============================================================================
// SECTION 4: ISA CONFIGURATION (RISC-V Extensions)
// ============================================================================

parameter bit XLEN_64         = 1'b0;  // 0=32-bit, 1=64-bit
parameter int unsigned XLEN   = XLEN_64 ? 64 : 32;
parameter bit EXT_M_ENABLE    = 1'b1;  // Multiply/Divide
parameter bit EXT_A_ENABLE    = 1'b0;  // Atomic
parameter bit EXT_F_ENABLE    = 1'b0;  // Single-precision FP
parameter bit EXT_D_ENABLE    = 1'b0;  // Double-precision FP
parameter bit EXT_C_ENABLE    = 1'b0;  // Compressed
parameter bit EXT_ZICOND_ENABLE = 1'b0; // Conditional ops

parameter int unsigned FLEN = EXT_D_ENABLE ? 64 : (EXT_F_ENABLE ? 32 : 0);

// ============================================================================
// SECTION 5: CACHE HIERARCHY (Enable/Disable and Sizes)
// ============================================================================

parameter bit ICACHE_ENABLE   = 1'b1;  // Instruction cache
parameter bit DCACHE_ENABLE   = 1'b1;  // Data cache
parameter bit L2_ENABLE       = 1'b0;  // L2 cache
parameter bit L3_ENABLE       = 1'b0;  // L3 cache

parameter int unsigned ICACHE_SIZE = 16384;   // 16 KB
parameter int unsigned DCACHE_SIZE = 16384;   // 16 KB
parameter int unsigned L2_CACHE_SIZE = 1048576;  // 1 MB
parameter int unsigned L3_CACHE_SIZE = 1048576;  // 1 MB

parameter int unsigned NUM_ICACHES = ICACHE_ENABLE ? ((SOCKET_SIZE + 3) / 4) : 0;
parameter int unsigned NUM_DCACHES = DCACHE_ENABLE ? ((SOCKET_SIZE + 3) / 4) : 0;

// ============================================================================
// SECTION 6: MEMORY SYSTEM
// ============================================================================

parameter int unsigned MEM_BLOCK_SIZE  = 64;   // Cache line / block size (bytes)
parameter int unsigned MEM_ADDR_WIDTH  = 32;   // Physical address width
parameter int unsigned LMEM_LOG_SIZE   = 14;   // Local memory: 2^14 = 16 KB

// Address regions
parameter bit [63:0] STARTUP_ADDR      = 32'h80000000;  // Default program entry
parameter bit [63:0] STACK_BASE_ADDR   = 32'hFFFF0000;  // Stack base
parameter bit [63:0] IO_BASE_ADDR      = 32'h00000040;  // IO peripheral base
parameter bit [63:0] USER_BASE_ADDR    = 32'h00010000;  // User code base
parameter bit [63:0] LMEM_BASE_ADDR    = STACK_BASE_ADDR;

// ============================================================================
// SECTION 7: AXI4 INTERFACE CONFIGURATION
// ============================================================================

parameter int unsigned AXI_ID_WIDTH    = 4;    // Transaction ID width
parameter int unsigned AXI_ADDR_WIDTH  = 32;   // Address width
parameter int unsigned AXI_DATA_WIDTH  = 64;   // Data width (64-bit)
parameter int unsigned AXI_USER_WIDTH  = 0;    // User signal width
parameter int unsigned AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8;  // Write strobes
parameter int unsigned AXI_MAX_BURST_LEN = 256;  // Max burst length
parameter bit [2:0]    AXI_BURST_TYPE   = 3'b001; // INCR (incrementing addresses)

// ============================================================================
// SECTION 8: PIPELINE CONFIGURATION
// ============================================================================

parameter int unsigned ISSUE_WIDTH     = (NUM_WARPS > 8) ? 1 : ((NUM_WARPS + 7) / 8);
parameter int unsigned IBUF_SIZE       = 4;    // Instruction buffer depth
parameter int unsigned NUM_ALU_LANES   = NUM_THREADS;
parameter int unsigned NUM_FPU_LANES   = NUM_THREADS;
parameter int unsigned NUM_LSU_LANES   = NUM_THREADS;
parameter int unsigned NUM_SFU_LANES   = NUM_THREADS;

// ============================================================================
// SECTION 9: TIMING PARAMETERS
// ============================================================================

parameter int unsigned RESET_DELAY = 8;           // Reset duration in cycles
parameter int unsigned STALL_TIMEOUT = 100000;    // Simulation timeout

// ============================================================================
// SECTION 10: UVM CONFIGURATION CLASS
// ============================================================================

class vortex_config extends uvm_object;
    
    `uvm_object_utils(vortex_config)
    
    //========================================================================
    // HARDWARE ARCHITECTURE (Randomizable)
    //========================================================================
    
    rand int unsigned num_clusters;
    rand int unsigned num_cores;
    rand int unsigned num_warps;
    rand int unsigned num_threads;
    rand int unsigned num_barriers;
    
    // Derived (non-randomizable)
    int unsigned socket_size;
    int unsigned num_sockets;
    
    //========================================================================
    // ISA CONFIGURATION
    //========================================================================
    
    rand bit xlen_64;
    rand int unsigned xlen;
    rand bit ext_m_enable;
    rand bit ext_a_enable;
    rand bit ext_f_enable;
    rand bit ext_d_enable;
    rand bit ext_c_enable;
    rand int unsigned flen;
    
    //========================================================================
    // CACHE CONFIGURATION
    //========================================================================
    
    rand bit icache_enable;
    rand bit dcache_enable;
    rand bit l2_enable;
    rand bit l3_enable;
    
    rand int unsigned icache_size;
    rand int unsigned dcache_size;
    rand int unsigned l2_cache_size;
    rand int unsigned l3_cache_size;
    rand int unsigned cache_line_size;
    
    int unsigned num_icaches;
    int unsigned num_dcaches;
    
    //========================================================================
    // MEMORY CONFIGURATION
    //========================================================================
    
    rand int unsigned mem_block_size;
    rand int unsigned mem_addr_width;
    rand int unsigned mem_data_width;
    rand int unsigned mem_tag_width;
    rand int unsigned mem_byteen_width;
    
    rand bit [63:0] startup_addr;
    rand bit [63:0] stack_base_addr;
    rand bit [63:0] io_base_addr;
    rand bit [63:0] user_base_addr;
    
    //========================================================================
    // AXI4 CONFIGURATION
    //========================================================================
    
    rand int unsigned axi_id_width;
    rand int unsigned axi_addr_width;
    rand int unsigned axi_data_width;
    rand int unsigned axi_user_width;
    int unsigned axi_strb_width;
    
    rand int unsigned axi_max_burst_len;
    rand bit [2:0] axi_burst_type;
    
    //========================================================================
    // TIMING AND SIMULATION
    //========================================================================
    
    rand int unsigned timeout_cycles;
    rand int unsigned reset_cycles;
    rand int unsigned test_timeout_cycles;
    
    rand uvm_verbosity default_verbosity;
    rand bit enable_transaction_recording;
    rand bit enable_coverage;
    rand bit enable_assertions;
    
    rand bit dump_waves;
    string wave_filename = "vortex_sim.vcd";
    rand bit trace_enable;
    rand int unsigned trace_level;  // 0-3
    
    rand int unsigned clk_freq_mhz;
    rand real clk_period_ns;
    
    //========================================================================
    // AGENT CONFIGURATION
    //========================================================================
    
    rand bit mem_agent_enable;
    rand bit axi_agent_enable;
    rand bit dcr_agent_enable;
    rand bit host_agent_enable;
    rand bit status_agent_enable;
    
    rand bit mem_agent_is_active;
    rand bit axi_agent_is_active;
    rand bit dcr_agent_is_active;
    rand bit host_agent_is_active;
    bit status_agent_is_active = 0;  // Always passive
    
    //========================================================================
    // GOLDEN MODEL (SIMX) CONFIGURATION
    //========================================================================
    
    rand bit simx_enable;
    string simx_path;
    rand bit simx_debug_enable;
    rand int unsigned simx_timeout_cycles;
    string simx_trace_file = "simx_trace.log";
    
    //========================================================================
    // PROGRAM/TEST CONFIGURATION
    //========================================================================
    
    string program_path = "";
    string program_type = "hex";  // hex, elf, bin
    rand bit [63:0] program_load_addr;
    rand bit [63:0] program_entry_point;
    
    rand bit [31:0] kernel_num_groups;
    rand bit [31:0] kernel_group_size;
    
    rand bit init_memory_random;
    rand bit clear_memory_on_reset;
    
    rand bit [63:0] result_base_addr;
    rand int unsigned result_size_bytes;
    
    //========================================================================
    // SCOREBOARD CONFIGURATION
    //========================================================================
    
    rand bit enable_scoreboard;
    rand bit strict_ordering;
    rand bit compare_on_the_fly;
    
    //========================================================================
    // CONSTRAINTS
    //========================================================================
    
    constraint valid_hw_config_c {
        num_clusters inside {[1:4]};
        num_cores inside {[1:32]};
        num_warps inside {[1:16]};
        num_threads inside {[1:8]};
        
        num_barriers == (num_warps / 2);
        
        icache_size inside {4096, 8192, 16384, 32768, 65536};
        dcache_size inside {4096, 8192, 16384, 32768, 65536};
        l2_cache_size inside {65536, 131072, 262144, 524288, 1048576};
        l3_cache_size inside {262144, 524288, 1048576, 2097152};
        
        mem_block_size inside {32, 64, 128};
        mem_addr_width inside {32, 48};
        mem_data_width inside {32, 64};
        
        cache_line_size inside {32, 64};
    }
    
    constraint isa_consistency_c {
        ext_d_enable -> ext_f_enable;
        
        if (ext_d_enable)
            flen == 64;
        else if (ext_f_enable)
            flen == 32;
        else
            flen == 0;
        
        xlen == (xlen_64 ? 64 : 32);
    }
    
    constraint cache_hierarchy_c {
        l3_enable -> l2_enable;
        l3_enable -> (num_clusters > 1);
        
        if (!icache_enable) icache_size == 0;
        if (!dcache_enable) dcache_size == 0;
        if (!l2_enable) l2_cache_size == 0;
        if (!l3_enable) l3_cache_size == 0;
    }
    
    constraint axi_config_c {
        axi_id_width inside {[4:16]};
        axi_addr_width == mem_addr_width;
        axi_data_width inside {32, 64, 128, 256, 512};
        axi_user_width inside {[0:8]};
        axi_strb_width == (axi_data_width / 8);
        axi_max_burst_len inside {[1:256]};
        soft axi_burst_type == 3'b001;  // INCR
    }
    
    constraint timing_config_c {
        clk_freq_mhz inside {[50:500]};
        clk_period_ns == (1000.0 / real'(clk_freq_mhz));
        timeout_cycles inside {[1000:100000]};
        reset_cycles inside {[1:100]};
    }
    
    //========================================================================
    // CONSTRUCTOR
    //========================================================================
    
    function new(string name = "vortex_config");
        super.new(name);
        set_defaults_from_vx_config();
    endfunction
    
    //========================================================================
    // SET DEFAULTS
    //========================================================================

    virtual function void set_defaults_from_vx_config();
        // Hardware defaults
        num_clusters = NUM_CLUSTERS;
        num_cores = NUM_CORES;
        num_warps = NUM_WARPS;
        num_threads = NUM_THREADS;
        num_barriers = NUM_BARRIERS;
        socket_size = SOCKET_SIZE;
        num_sockets = NUM_SOCKETS;
        
        // ISA defaults
        xlen_64 = XLEN_64;
        xlen = XLEN;
        ext_m_enable = EXT_M_ENABLE;
        ext_a_enable = EXT_A_ENABLE;
        ext_f_enable = EXT_F_ENABLE;
        ext_d_enable = EXT_D_ENABLE;
        flen = FLEN;
        
        // Cache defaults
        icache_enable = ICACHE_ENABLE;
        dcache_enable = DCACHE_ENABLE;
        l2_enable = L2_ENABLE;
        l3_enable = L3_ENABLE;
        
        icache_size = ICACHE_SIZE;
        dcache_size = DCACHE_SIZE;
        l2_cache_size = L2_CACHE_SIZE;
        l3_cache_size = L3_CACHE_SIZE;
        cache_line_size = MEM_BLOCK_SIZE;
        
        num_icaches = NUM_ICACHES;
        num_dcaches = NUM_DCACHES;
        
        // Memory defaults
        mem_block_size = MEM_BLOCK_SIZE;
        mem_addr_width = MEM_ADDR_WIDTH;
        mem_data_width = VX_MEM_DATA_WIDTH;
        mem_tag_width = VX_MEM_TAG_WIDTH;
        mem_byteen_width = VX_MEM_BYTEEN_WIDTH;
        
        startup_addr = STARTUP_ADDR;
        stack_base_addr = STACK_BASE_ADDR;
        io_base_addr = IO_BASE_ADDR;
        user_base_addr = USER_BASE_ADDR;
        
        // AXI defaults
        axi_id_width = AXI_ID_WIDTH;
        axi_addr_width = AXI_ADDR_WIDTH;
        axi_data_width = AXI_DATA_WIDTH;
        axi_user_width = AXI_USER_WIDTH;
        axi_strb_width = AXI_STRB_WIDTH;
        axi_max_burst_len = AXI_MAX_BURST_LEN;
        axi_burst_type = AXI_BURST_TYPE;
        
        // Timing defaults
        timeout_cycles = 100000;
        reset_cycles = RESET_DELAY;
        test_timeout_cycles = 50000;
        clk_freq_mhz = 100;
        clk_period_ns = 1000.0 / real'(clk_freq_mhz);
        
        // Simulation defaults
        default_verbosity = UVM_MEDIUM;
        enable_transaction_recording = 1;
        enable_coverage = 1;
        enable_assertions = 1;
        
        dump_waves = 1;
        trace_enable = 0;
        trace_level = 0;
        
        // Agent defaults
        mem_agent_enable = 1;
        axi_agent_enable = 0;
        dcr_agent_enable = 1;
        host_agent_enable = 1;
        status_agent_enable = 1;
        
        mem_agent_is_active = 1;
        axi_agent_is_active = 0;
        dcr_agent_is_active = 1;
        host_agent_is_active = 1;
        
        // simx defaults
        simx_enable = 1;
        simx_debug_enable = 0;
        simx_timeout_cycles = test_timeout_cycles;
        
        // Program defaults
        program_load_addr = startup_addr;
        program_entry_point = startup_addr;
        kernel_num_groups = 1;
        kernel_group_size = num_threads;
        
        init_memory_random = 0;
        clear_memory_on_reset = 1;
        
        result_base_addr = startup_addr + 64'h100000;
        result_size_bytes = 1024;
        
        // Scoreboard defaults
        enable_scoreboard = 1;
        strict_ordering = 0;
        compare_on_the_fly = 1;
    endfunction
    
    //========================================================================
    // APPLY COMMAND-LINE PLUSARGS
    //========================================================================
    
    virtual function void apply_plusargs();
        int tmp;
        string str_tmp;
        
        // Architecture
        if ($value$plusargs("CORES=%d", tmp) || $value$plusargs("cores=%d", tmp))
            num_cores = tmp;
        if ($value$plusargs("WARPS=%d", tmp) || $value$plusargs("warps=%d", tmp))
            num_warps = tmp;
        if ($value$plusargs("THREADS=%d", tmp) || $value$plusargs("threads=%d", tmp))
            num_threads = tmp;
        if ($value$plusargs("CLUSTERS=%d", tmp) || $value$plusargs("clusters=%d", tmp))
            num_clusters = tmp;
        
        // ISA
        if ($test$plusargs("XLEN64") || $test$plusargs("xlen64")) begin
            xlen_64 = 1;
            xlen = 64;
        end
        
        // Caches
        if ($test$plusargs("L2CACHE") || $test$plusargs("l2cache"))
            l2_enable = 1;
        if ($test$plusargs("L3CACHE") || $test$plusargs("l3cache"))
            l3_enable = 1;
        
        // Program
        if ($value$plusargs("PROGRAM=%s", str_tmp) || 
            $value$plusargs("APP=%s", str_tmp) ||
            $value$plusargs("HEX=%s", str_tmp))
            program_path = str_tmp;
        
        if ($value$plusargs("STARTUP_ADDR=%h", tmp))
            startup_addr = tmp;
        
        // Simulation
        if ($value$plusargs("TIMEOUT=%d", tmp))
            test_timeout_cycles = tmp;
        
        if ($test$plusargs("NOWAVES") || $test$plusargs("nowaves"))
            dump_waves = 0;
        
        if ($test$plusargs("DISABLE_SIMX") || $test$plusargs("disable_simx"))
            simx_enable = 0;
        
        if ($test$plusargs("VERBOSE") || $test$plusargs("verbose"))
            default_verbosity = UVM_HIGH;
        
        if ($test$plusargs("DEBUG") || $test$plusargs("debug") || 
            $value$plusargs("DEBUG=%d", tmp)) begin
            default_verbosity = UVM_DEBUG;
            trace_enable = 1;
            trace_level = (tmp > 0) ? tmp : 1;
        end
        
        if ($value$plusargs("TRACE=%d", tmp)) begin
            trace_enable = 1;
            trace_level = tmp;
        end
        
        // Recalculate derived values
        num_barriers = (num_warps + 1) / 2;
        socket_size = (num_cores <= 4) ? num_cores : 4;
        num_sockets = (num_cores + socket_size - 1) / socket_size;
        num_icaches = icache_enable ? ((socket_size + 3) / 4) : 0;
        num_dcaches = dcache_enable ? ((socket_size + 3) / 4) : 0;
    endfunction
    
    //========================================================================
    // PRINT CONFIGURATION
    //========================================================================
    
    virtual function void print_config(uvm_verbosity verbosity = UVM_MEDIUM);
        `uvm_info("VORTEX_CFG", "==================================================", verbosity)
        `uvm_info("VORTEX_CFG", "  VORTEX UVM CONFIGURATION", verbosity)
        `uvm_info("VORTEX_CFG", "==================================================", verbosity)
        
        `uvm_info("VORTEX_CFG", $sformatf("Clusters: %0d", num_clusters), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("Cores: %0d", num_cores), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("Warps: %0d", num_warps), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("Threads: %0d", num_threads), verbosity)
        
        `uvm_info("VORTEX_CFG", $sformatf("XLEN: %0d", xlen), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("FLEN: %0d", flen), verbosity)
        
        `uvm_info("VORTEX_CFG", $sformatf("ICache: %s", icache_enable ? "enabled" : "disabled"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("DCache: %s", dcache_enable ? "enabled" : "disabled"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("L2: %s", l2_enable ? "enabled" : "disabled"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("L3: %s", l3_enable ? "enabled" : "disabled"), verbosity)
        
        `uvm_info("VORTEX_CFG", $sformatf("Startup Addr: 0x%h", startup_addr), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("Program: %s", program_path), verbosity)
        
        `uvm_info("VORTEX_CFG", "==================================================", verbosity)
    endfunction

endclass : vortex_config

endpackage : vortex_config_pkg

`endif // VORTEX_CONFIG_SV
*/