////////////////////////////////////////////////////////////////////////////////
// File: vortex_config.sv
// Description: Unified UVM configuration class that mirrors VX_config.vh
//
// Universal config for: DUT RTL, simx golden model, all UVM agents,
// drivers, monitors, scoreboard. Controlled from terminal via:
//   - Compile time: +define+<PARAM>
//   - Runtime:      +<PLUSARG>
//
// Terminal Interface (run_vortex_uvm.sh):
//   --cores=N          → +NUM_CORES=N       (compile+runtime)
//   --warps=N          → +NUM_WARPS=N       (compile+runtime)
//   --threads=N        → +NUM_THREADS=N     (compile+runtime)
//   --clusters=N       → +NUM_CLUSTERS=N    (compile+runtime)
//   --interface=axi    → +USE_AXI_WRAPPER   (compile+runtime)
//   --timeout=N        → +TIMEOUT=N         (runtime)
//   --program=PATH     → +PROGRAM=PATH      (runtime)
//   --no-waves         → +NO_WAVES          (runtime)
//   --verbose          → +VERBOSE           (runtime)
//   (wave path)        → +WAVE=PATH         (runtime)
//
// Author: Vortex UVM Team
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_CONFIG_SV
`define VORTEX_CONFIG_SV

package vortex_config_pkg;

import uvm_pkg::*;
`include "uvm_macros.svh"

// ===========================================================================
// Memory Interface Parameters
// Derived from RTL (VX_define.vh):
//
//   VX_MEM_DATA_WIDTH  = L3_LINE_SIZE * 8       = 64 * 8 = 512 bits (fixed)
//   VX_MEM_BYTEEN_WIDTH= L3_LINE_SIZE            = 64 bytes         (fixed)
//   VX_MEM_TAG_WIDTH   = L3_MEM_TAG_WIDTH        = 8 bits           (fixed)
//                        (`define L3_MEM_TAG_WIDTH 8  in VX_define.vh)
//
//   VX_MEM_ADDR_WIDTH  = MEM_ADDR_WIDTH - CLOG2(L3_LINE_SIZE)
//                      = 32 - 6 = 26  (XLEN=32, default)   → WORD address
//                      = 48 - 6 = 42  (XLEN=64)
//
//   AXI_ADDR_WIDTH     = MEM_ADDR_WIDTH           → BYTE address
//                      = 32 (RV32) or 48 (RV64)
//
//   AXI_ID_WIDTH       = VX_MEM_TAG_WIDTH = 8
//
// These are package-level constants used to size ALL interfaces and
// transactions. Never override them with wrong values.
// ===========================================================================

parameter VX_MEM_LINE_SIZE    = 64;                     // L3_LINE_SIZE bytes
parameter VX_MEM_OFFSET_BITS  = 6;                      // $clog2(VX_MEM_LINE_SIZE)
parameter VX_MEM_DATA_WIDTH   = VX_MEM_LINE_SIZE * 8;  // 512 bits — NEVER changes
parameter VX_MEM_BYTEEN_WIDTH = VX_MEM_LINE_SIZE;       // 64 bytes  — NEVER changes
parameter VX_MEM_TAG_WIDTH    = 8;                      // L3_MEM_TAG_WIDTH (VX_define.vh)

`ifdef XLEN_64
    parameter VX_MEM_ADDR_WIDTH = 42;   // 48 - 6  (word address, RV64)
    parameter AXI_ADDR_WIDTH    = 48;   // byte address, RV64
`else
    parameter VX_MEM_ADDR_WIDTH = 26;   // 32 - 6 (word address, RV32, default)
    parameter AXI_ADDR_WIDTH    = 32;   // byte address, RV32
`endif

// Derived AXI width constants (pkg-level, used for interface sizing)
parameter AXI_DATA_WIDTH = VX_MEM_DATA_WIDTH;   // 512
parameter AXI_STRB_WIDTH = VX_MEM_LINE_SIZE;    // 64
parameter AXI_ID_WIDTH   = VX_MEM_TAG_WIDTH;    // 8

// ===========================================================================
// DCR (Device Configuration Register) Parameters — from VX_types.vh
// ===========================================================================

parameter VX_DCR_ADDR_WIDTH          = 12;
parameter VX_DCR_DATA_WIDTH          = 32;

parameter VX_DCR_BASE_STATE_BEGIN    = 12'h001;
parameter VX_DCR_BASE_STARTUP_ADDR0  = 12'h001;
parameter VX_DCR_BASE_STARTUP_ADDR1  = 12'h002;
parameter VX_DCR_BASE_STARTUP_ARG0   = 12'h003;
parameter VX_DCR_BASE_STARTUP_ARG1   = 12'h004;
parameter VX_DCR_BASE_MPM_CLASS      = 12'h005;
parameter VX_DCR_BASE_STATE_END      = 12'h006;

parameter VX_DCR_BASE_STATE_COUNT    = (VX_DCR_BASE_STATE_END - VX_DCR_BASE_STATE_BEGIN);

function automatic bit [11:0] VX_DCR_BASE_STATE(input bit [11:0] addr);
    return (addr - VX_DCR_BASE_STATE_BEGIN);
endfunction

parameter VX_DCR_MPM_CLASS_NONE = 0;
parameter VX_DCR_MPM_CLASS_CORE = 1;
parameter VX_DCR_MPM_CLASS_MEM  = 2;

// ===========================================================================
// General
// ===========================================================================

parameter STARTUP_ADDR = 32'h80000000;


// Package-level reset delay constant — needed by vortex_tb_top.sv
// module parameter at elaboration time (class fields are not accessible then).
`ifdef RESET_DELAY
    parameter RTL_RESET_DELAY = `RESET_DELAY;
`else
    parameter RTL_RESET_DELAY = 8;   // RTL VX_config.vh default
`endif


// ===========================================================================
// Main Configuration Class
// ===========================================================================

class vortex_config extends uvm_object;

    `uvm_object_utils(vortex_config)

    //==========================================================================
    // ARCHITECTURE
    //==========================================================================

    rand int unsigned   num_clusters;
    rand int unsigned   num_cores;
    rand int unsigned   num_warps;
    rand int unsigned   num_threads;
    rand int unsigned   num_barriers;
    int unsigned        socket_size;      // derived

    //==========================================================================
    // ISA
    //==========================================================================

    rand bit            xlen_64;
    rand int unsigned   xlen;             // derived: 32 or 64

    rand bit            ext_f_enable;
    rand bit            ext_d_enable;
    rand bit            ext_m_enable;
    rand bit            ext_a_enable;
    rand bit            ext_c_enable;
    rand bit            ext_zicond_enable;

    rand int unsigned   flen;             // derived: 0, 32, or 64

    //==========================================================================
    // CACHE HIERARCHY
    //==========================================================================

    rand bit            icache_enable;
    rand bit            dcache_enable;
    rand bit            l2_enable;
    rand bit            l3_enable;

    rand int unsigned   icache_size;
    rand int unsigned   dcache_size;
    rand int unsigned   l2_cache_size;
    rand int unsigned   l3_cache_size;

    rand int unsigned   cache_line_size;

    int unsigned        num_icaches;      // derived
    int unsigned        num_dcaches;      // derived

    //==========================================================================
    // MEMORY SYSTEM
    // mem_data_width / mem_byteen_width / mem_tag_width are READ-ONLY
    // reflections of the package params — never randomize them.
    //==========================================================================

    rand int unsigned   mem_block_size;
    rand int unsigned   mem_addr_width;   // byte-address space: 32 or 48

    // Fixed to package params — set in set_defaults, not randomized
    int unsigned        mem_data_width;   // always VX_MEM_DATA_WIDTH  = 512
    int unsigned        mem_byteen_width; // always VX_MEM_BYTEEN_WIDTH = 64
    int unsigned        mem_tag_width;    // always VX_MEM_TAG_WIDTH    = 8

    rand bit [63:0]     startup_addr;
    rand bit [63:0]     stack_base_addr;
    rand bit [63:0]     io_base_addr;
    rand bit [63:0]     io_addr_end;

    //==========================================================================
    // PIPELINE
    //==========================================================================

    rand int unsigned   issue_width;
    rand int unsigned   ibuf_size;
    rand int unsigned   num_alu_lanes;
    rand int unsigned   num_fpu_lanes;
    rand int unsigned   num_lsu_lanes;

    //==========================================================================
    // DCR ADDRESSES (informational — used by DCR driver sequences)
    //==========================================================================

    bit [31:0]          dcr_base_startup_addr0;
    bit [31:0]          dcr_base_mpm_class;

    //==========================================================================
    // AXI4 INTERFACE
    // FIXED: ID/DATA/STRB widths must match VX_MEM_* package params.
    //   AXI_ID_WIDTH   = VX_MEM_TAG_WIDTH  = 8  (NOT 50, NOT 4)
    //   AXI_DATA_WIDTH = VX_MEM_DATA_WIDTH = 512
    //   AXI_STRB_WIDTH = VX_MEM_LINE_SIZE  = 64
    //   AXI_ADDR_WIDTH = mem_addr_width    = 32 (RV32) or 48 (RV64)
    //==========================================================================

    int unsigned        AXI_ID_WIDTH;    // FIXED = 8 (= VX_MEM_TAG_WIDTH)
    rand int unsigned   AXI_ADDR_WIDTH;  // 32 or 48, tracks mem_addr_width
    int unsigned        AXI_DATA_WIDTH;  // FIXED = 512 (= VX_MEM_DATA_WIDTH)
    rand int unsigned   AXI_USER_WIDTH;
    int unsigned        AXI_STRB_WIDTH;  // FIXED = 64 (= AXI_DATA_WIDTH/8)

    rand int unsigned   AXI_MAX_BURST_LEN;
    rand bit [2:0]      AXI_BURST_TYPE;

    rand int unsigned   timeout_cycles;
    rand int unsigned   axi_ready_delay_min;
    rand int unsigned   axi_ready_delay_max;

    //==========================================================================
    // CLOCK AND TIMING
    //==========================================================================

    rand int unsigned   CLK_FREQ_MHZ;
    rand real           CLK_PERIOD_NS;
    rand int unsigned   max_latency_cycles;
    rand int unsigned   min_inter_req_delay;
    rand int unsigned   max_inter_req_delay;
    rand int unsigned   status_sample_interval;

    //==========================================================================
    // SIMULATION / TEST
    //==========================================================================

    rand int unsigned   global_timeout_cycles;
    rand int unsigned   test_timeout_cycles;
    rand int unsigned   reset_cycles;
    rand int unsigned   reset_delay;

    rand uvm_verbosity  default_verbosity;
    rand bit            enable_transaction_recording;
    rand bit            enable_coverage;
    rand bit            enable_assertions;

    rand bit            dump_waves;
    string              wave_file_name;
    rand bit            trace_enable;
    rand int unsigned   trace_level;

    //==========================================================================
    // AGENTS
    //==========================================================================

    rand bit            mem_agent_enable;
    rand bit            axi_agent_enable;
    rand bit            dcr_agent_enable;
    rand bit            host_agent_enable;
    rand bit            status_agent_enable;

    rand bit            mem_agent_is_active;
    rand bit            axi_agent_is_active;
    rand bit            dcr_agent_is_active;
    rand bit            host_agent_is_active;
    rand bit            status_agent_is_active;  // always 0

    //==========================================================================
    // GOLDEN MODEL (simx)
    //==========================================================================

    rand bit            simx_enable;
    string              simx_path;
    rand bit            simx_debug_enable;
    rand int unsigned   simx_timeout_cycles;
    string              simx_trace_file;

    //==========================================================================
    // TEST / PROGRAM
    //==========================================================================

    string              program_path;
    string              program_type;         // "hex", "elf", "bin"
    rand bit [63:0]     program_load_addr;
    rand bit [63:0]     program_entry_point;

    rand bit [31:0]     kernel_num_groups;
    rand bit [31:0]     kernel_group_size;

    rand bit            init_memory_random;
    rand bit            clear_memory_on_reset;

    rand bit [63:0]     result_base_addr;
    rand int unsigned   result_size_bytes;

    //==========================================================================
    // SCOREBOARD
    //==========================================================================

    rand bit            enable_scoreboard;
    rand bit            strict_ordering;
    rand bit            compare_on_the_fly;

    //==========================================================================
    // SYNCHRONIZATION EVENTS
    //
    // ebreak_event: triggered by vortex_scoreboard.write_status() the moment
    // the status_agent monitor observes ebreak_detected == 1 on the interface.
    //
    // Any virtual sequence waiting in wait_for_execution_complete() blocks on
    // this event instead of using a fixed #10us placeholder.  The event is
    // created in new() so it is always valid — no null-guard needed at use
    // sites.  It is NOT rand (events cannot be randomized).
    //==========================================================================
    uvm_event           ebreak_event;

    //==========================================================================
    // CONSTRAINTS
    //==========================================================================

    constraint valid_hw_config_c {
        num_clusters inside {[1:4]};
        num_cores    inside {[1:32]};
        num_warps    inside {[1:16]};
        num_threads  inside {[1:8]};
        // RTL: NUM_BARRIERS = UP(NUM_WARPS/2) = max(NUM_WARPS/2, 1)
        num_barriers == ((num_warps / 2 > 0) ? (num_warps / 2) : 1);

        icache_size   inside {4096, 8192, 16384, 32768, 65536};
        dcache_size   inside {4096, 8192, 16384, 32768, 65536};
        l2_cache_size inside {131072, 262144, 524288, 1048576, 2097152};
        l3_cache_size inside {262144, 524288, 1048576, 2097152};

        mem_block_size inside {32, 64, 128};
        mem_addr_width inside {32, 48};

        cache_line_size inside {32, 64};
        issue_width     inside {[1:2]};
        ibuf_size       inside {2, 4, 8};
    }

    constraint isa_consistency_c {
        ext_d_enable -> ext_f_enable;
        if (ext_d_enable)      flen == 64;
        else if (ext_f_enable) flen == 32;
        else                   flen == 0;
        xlen == (xlen_64 ? 64 : 32);
    }

    constraint cache_hierarchy_c {
        l3_enable -> l2_enable;
        l3_enable -> (num_clusters > 1);
        if (!icache_enable) icache_size   == 0;
        if (!dcache_enable) dcache_size   == 0;
        if (!l2_enable)     l2_cache_size == 0;
        if (!l3_enable)     l3_cache_size == 0;
    }

    constraint lane_config_c {
        num_alu_lanes == num_threads;
        num_fpu_lanes == num_threads;
        num_lsu_lanes == num_threads;
    }

    // Default path: custom mem interface (TB is memory responder).
    // +USE_AXI_WRAPPER at runtime flips these via apply_plusargs().
    constraint default_agents_c {
        mem_agent_enable    == 1;
        dcr_agent_enable    == 1;
        host_agent_enable   == 1;
        status_agent_enable == 1;

        soft axi_agent_enable == 0;

        mem_agent_is_active    == 1;   // TB is always the memory responder
        dcr_agent_is_active    == 1;
        host_agent_is_active   == 1;
        status_agent_is_active == 0;   // always passive — DUT drives busy

        // AXI active only when AXI enabled
        axi_agent_is_active == axi_agent_enable;
    }

    constraint axi_config_c {
        // AXI_ADDR_WIDTH tracks mem_addr_width (byte address space)
        AXI_ADDR_WIDTH == mem_addr_width;
        AXI_USER_WIDTH inside {[0:8]};
        AXI_MAX_BURST_LEN  inside {[1:256]};
        soft AXI_BURST_TYPE    == 3'b001;
        timeout_cycles         inside {[1000:100000]};
        axi_ready_delay_min    inside {[0:5]};
        axi_ready_delay_max    inside {[axi_ready_delay_min:20]};
    }

    constraint clock_config_c {
        CLK_FREQ_MHZ         inside {[50:500]};
        CLK_PERIOD_NS        == (1000.0 / real'(CLK_FREQ_MHZ));
        max_latency_cycles   inside {[10:1000]};
        min_inter_req_delay  inside {[0:10]};
        max_inter_req_delay  inside {[min_inter_req_delay:100]};
        status_sample_interval inside {[10:1000]};
    }

    constraint reasonable_timeouts_c {
        global_timeout_cycles inside {[50000:1000000]};
        test_timeout_cycles   inside {[10000:100000]};
        reset_cycles          inside {[10:100]};
        reset_delay           inside {[10:100]};
        simx_timeout_cycles   == test_timeout_cycles;
    }

    constraint valid_memory_addrs_c {
        if (!xlen_64) {
            startup_addr[63:32]       == 32'h0;
            stack_base_addr[63:32]    == 32'h0;
            io_base_addr[63:32]       == 32'h0;
            io_addr_end[63:32]        == 32'h0;
            program_load_addr[63:32]  == 32'h0;
            program_entry_point[63:32]== 32'h0;
            result_base_addr[63:32]   == 32'h0;
        }
        startup_addr[1:0]        == 2'b00;
        program_load_addr[1:0]   == 2'b00;
        program_entry_point[1:0] == 2'b00;
        result_base_addr[1:0]    == 2'b00;
        io_addr_end > io_base_addr;
    }

    //==========================================================================
    // CONSTRUCTOR
    //==========================================================================

    function new(string name = "vortex_config");
        super.new(name);
        // Create the ebreak synchronization event once — shared by all
        // components that receive this config object via config_db.
        ebreak_event = new("ebreak_event");
        set_defaults_from_vx_config();
    endfunction

    //==========================================================================
    // SET DEFAULTS — "cold start, no flags" baseline
    // Every value here is overridable at runtime via apply_plusargs().
    //==========================================================================

    virtual function void set_defaults_from_vx_config();

        // --- Architecture ---
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
            // RTL: `UP(`NUM_WARPS/2) = max(NUM_WARPS/2, 1)
            num_barriers = (num_warps / 2 > 0) ? (num_warps / 2) : 1;
        `endif

        // --- ISA ---
        `ifdef XLEN_64
            xlen_64 = 1; xlen = 64;
        `else
            xlen_64 = 0; xlen = 32;
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

        if      (ext_d_enable) flen = 64;
        else if (ext_f_enable) flen = 32;
        else                   flen = 0;

        // --- Cache ---
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
            l2_cache_size = 1048576;  // L2_CACHE_SIZE default (non-ALTERA_S10): 1MB
        `endif

        `ifdef L3_CACHE_SIZE
            l3_cache_size = `L3_CACHE_SIZE;
        `else
            l3_cache_size = 1048576;  // L3_CACHE_SIZE default (non-ALTERA_S10): 1MB
        `endif

        cache_line_size = 64;

        // Derived cache counts
        socket_size = (num_cores < 4) ? num_cores : 4;
        num_icaches = icache_enable ? ((socket_size + 3) / 4) : 0;
        num_dcaches = dcache_enable ? ((socket_size + 3) / 4) : 0;

        // --- Memory system ---
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

        // FIXED — must always match the package parameters above
        mem_data_width   = VX_MEM_DATA_WIDTH;    // 512
        mem_byteen_width = VX_MEM_BYTEEN_WIDTH;  // 64
        mem_tag_width    = VX_MEM_TAG_WIDTH;      // 8

        `ifdef STARTUP_ADDR
            startup_addr = `STARTUP_ADDR;
        `else
            // RTL VX_config.vh:
            //   RV32: `define STARTUP_ADDR 32'h80000000
            //   RV64: `define STARTUP_ADDR 64'h080000000
            startup_addr = xlen_64 ? 64'h080000000 : 64'h80000000;
        `endif

        // RTL VX_config.vh:
        //   RV32: `define STACK_BASE_ADDR 32'hFFFF0000
        //   RV64: `define STACK_BASE_ADDR 64'h1FFFF0000
        `ifdef STACK_BASE_ADDR
            stack_base_addr = `STACK_BASE_ADDR;
        `else
            stack_base_addr = xlen_64 ? 64'h1FFFF0000 : 64'hFFFF0000;
        `endif

        // RTL VX_config.vh:
        //   RV32: `define IO_BASE_ADDR 32'h00000040
        //   RV64: `define IO_BASE_ADDR 64'h000000040
        `ifdef IO_BASE_ADDR
            io_base_addr = `IO_BASE_ADDR;
        `else
            io_base_addr = xlen_64 ? 64'h000000040 : 64'h00000040;
        `endif

        // RTL VX_config.vh: `define IO_END_ADDR `USER_BASE_ADDR
        //   RV32 USER_BASE_ADDR: 32'h00010000
        //   RV64 USER_BASE_ADDR: 64'h000010000
        `ifdef IO_ADDR_END
            io_addr_end = `IO_ADDR_END;
        `else
            io_addr_end = xlen_64 ? 64'h000010000 : 64'h00010000;
        `endif

        // --- Pipeline ---
        issue_width   = (num_warps < 8) ? 1 : (num_warps / 8);
        ibuf_size     = 4;
        num_alu_lanes = num_threads;
        num_fpu_lanes = num_threads;
        num_lsu_lanes = num_threads;

        // --- DCR addresses ---
        `ifdef VX_DCR_BASE_STARTUP_ADDR0
            dcr_base_startup_addr0 = `VX_DCR_BASE_STARTUP_ADDR0;
        `else
            dcr_base_startup_addr0 = 32'h00000001;
        `endif

        `ifdef VX_DCR_BASE_MPM_CLASS
            dcr_base_mpm_class = `VX_DCR_BASE_MPM_CLASS;
        `else
            dcr_base_mpm_class = 32'h00000005;
        `endif

        // --- AXI4 — FIXED widths derived from VX_MEM_* pkg params ---
        // AXI_ID_WIDTH and AXI_DATA_WIDTH MUST equal pkg params.
        // Never set these to arbitrary values.
        AXI_ID_WIDTH   = VX_MEM_TAG_WIDTH;      // 8  — L3_MEM_TAG_WIDTH
        AXI_DATA_WIDTH = VX_MEM_DATA_WIDTH;      // 512 — matches mem bus
        AXI_STRB_WIDTH = VX_MEM_BYTEEN_WIDTH;    // 64

        `ifdef AXI_ADDR_WIDTH
            AXI_ADDR_WIDTH = `AXI_ADDR_WIDTH;
        `else
            AXI_ADDR_WIDTH = mem_addr_width;     // 32 RV32 / 48 RV64
        `endif

        AXI_USER_WIDTH    = 1;
        AXI_MAX_BURST_LEN = 1;                       // single-beat (1 cache line/req)
        AXI_BURST_TYPE    = 3'b001;                  // INCR

        timeout_cycles      = 10000;
        axi_ready_delay_min = 0;
        axi_ready_delay_max = 5;

        // --- Clock and timing ---
        `ifdef CLK_FREQ_MHZ
            CLK_FREQ_MHZ = `CLK_FREQ_MHZ;
        `else
            CLK_FREQ_MHZ = 100;
        `endif

        CLK_PERIOD_NS        = 1000.0 / real'(CLK_FREQ_MHZ);
        max_latency_cycles   = 200;
        min_inter_req_delay  = 0;
        max_inter_req_delay  = 10;
        status_sample_interval = 100;

        // --- Simulation ---
        global_timeout_cycles = 100000;
        test_timeout_cycles   = 50000;

        `ifdef RESET_DELAY
            reset_cycles = `RESET_DELAY;
            reset_delay  = `RESET_DELAY;
        `else
            // RTL VX_config.vh: `define RESET_DELAY 8
            reset_cycles = 8;
            reset_delay  = 8;
        `endif

        default_verbosity            = UVM_MEDIUM;
        enable_transaction_recording = 1;
        enable_coverage              = 1;
        enable_assertions            = 1;

        dump_waves     = 1;
        wave_file_name = "vortex_sim.vcd";
        trace_enable   = 0;
        trace_level    = 0;

        // --- Agents — default: custom mem path ---
        // +USE_AXI_WRAPPER at runtime flips to AXI path in apply_plusargs()
        mem_agent_enable    = 1;
        mem_agent_is_active = 1;   // TB is the memory responder
        axi_agent_enable    = 0;
        axi_agent_is_active = 0;
        dcr_agent_enable    = 1;
        dcr_agent_is_active = 1;
        host_agent_enable   = 1;
        host_agent_is_active = 1;
        status_agent_enable  = 1;
        status_agent_is_active = 0;  // always passive

        // --- simx ---
        simx_enable        = 0;
        simx_path          = "";
        simx_debug_enable  = 0;
        simx_timeout_cycles = test_timeout_cycles;
        simx_trace_file    = "simx_trace.log";

        // --- Program ---
        program_path        = "";
        program_type        = "hex";
        program_load_addr   = startup_addr;
        program_entry_point = startup_addr;
        kernel_num_groups   = 1;
        kernel_group_size   = num_threads;
        init_memory_random  = 0;
        clear_memory_on_reset = 1;
        result_base_addr    = startup_addr + 64'h100000;
        result_size_bytes   = 1024;

        // --- Scoreboard ---
        enable_scoreboard  = 1;
        strict_ordering    = 0;
        compare_on_the_fly = 1;

    endfunction

    //==========================================================================
    // APPLY PLUSARGS
    // Runtime overrides from terminal via run_vortex_uvm.sh.
    // Must be called AFTER set_defaults_from_vx_config().
    //==========================================================================

    virtual function void apply_plusargs();
        int    tmp;
        string str_tmp;

        // --- Interface path (must be FIRST — sets agent topology) ---
        if ($test$plusargs("USE_AXI_WRAPPER")) begin
            axi_agent_enable    = 1;
            axi_agent_is_active = 1;
            mem_agent_enable    = 0;
            mem_agent_is_active = 0;
            `uvm_info("VORTEX_CFG", "Interface: AXI4 (USE_AXI_WRAPPER)", UVM_MEDIUM)
        end else begin
            axi_agent_enable    = 0;
            axi_agent_is_active = 0;
            mem_agent_enable    = 1;
            mem_agent_is_active = 1;
            `uvm_info("VORTEX_CFG", "Interface: Custom MEM (default)", UVM_MEDIUM)
        end

        // --- Architecture ---
        if ($value$plusargs("NUM_CLUSTERS=%d", tmp) ||
            $value$plusargs("CLUSTERS=%d",     tmp))
            num_clusters = tmp;

        if ($value$plusargs("NUM_CORES=%d", tmp) ||
            $value$plusargs("CORES=%d",     tmp))
            num_cores = tmp;

        if ($value$plusargs("NUM_WARPS=%d", tmp) ||
            $value$plusargs("WARPS=%d",     tmp))
            num_warps = tmp;

        if ($value$plusargs("NUM_THREADS=%d", tmp) ||
            $value$plusargs("THREADS=%d",     tmp))
            num_threads = tmp;

        // --- Cache enables ---
        if ($test$plusargs("L2CACHE") || $test$plusargs("l2cache"))
            l2_enable = 1;
        if ($test$plusargs("L3CACHE") || $test$plusargs("l3cache"))
            l3_enable = 1;

        // --- ISA ---
        if ($test$plusargs("XLEN_64") || $test$plusargs("xlen=64")) begin
            xlen_64 = 1;
            xlen    = 64;
            mem_addr_width     = 48;
            AXI_ADDR_WIDTH = 48;
        end

        // --- Program ---
        if ($value$plusargs("PROGRAM=%s", str_tmp) ||
            $value$plusargs("APP=%s",     str_tmp) ||
            $value$plusargs("HEX=%s",     str_tmp)) begin
            program_path        = str_tmp;
            program_load_addr   = startup_addr;
            program_entry_point = startup_addr;
        end

        // STARTUP_ADDR: must use bit[63:0] — 'int tmp' is 32-bit and truncates RV64 addresses
        begin
            bit [63:0] addr64;
            if ($value$plusargs("STARTUP_ADDR=%h", addr64)) begin
                startup_addr        = addr64;
                program_load_addr   = addr64;
                program_entry_point = addr64;
                result_base_addr    = addr64 + 64'h100000;
                `uvm_info("VORTEX_CFG", $sformatf("STARTUP_ADDR overridden: 0x%h", startup_addr), UVM_MEDIUM)
            end
        end

        // --- Timeout ---
        if ($value$plusargs("TIMEOUT=%d", tmp)) begin
            test_timeout_cycles  = tmp;
            global_timeout_cycles = tmp * 2;
            simx_timeout_cycles  = tmp;
        end

        // --- Waveform ---
        if ($test$plusargs("NO_WAVES") || $test$plusargs("no_waves")) begin
            dump_waves = 0;
        end else if ($value$plusargs("WAVE=%s", str_tmp)) begin
            dump_waves     = 1;
            wave_file_name = str_tmp;
        end

        // --- Verbosity ---
        if ($test$plusargs("VERBOSE") || $test$plusargs("verbose"))
            default_verbosity = UVM_HIGH;

        // --- Debug/trace ---
        if ($test$plusargs("DEBUG") || $test$plusargs("debug") ||
            $value$plusargs("DEBUG=%d", tmp)) begin
            default_verbosity = UVM_DEBUG;
            trace_enable = 1;
            trace_level  = (tmp > 0) ? tmp : 1;
        end

        if ($value$plusargs("TRACE=%d", tmp)) begin
            trace_enable = 1;
            trace_level  = tmp;
        end

        // --- simx ---
        if ($test$plusargs("SIMX") || $test$plusargs("simx"))
            simx_enable = 1;
        if ($value$plusargs("SIMX_PATH=%s", str_tmp))
            simx_path = str_tmp;
        if ($test$plusargs("DISABLE_SIMX") || $test$plusargs("disable_simx"))
            simx_enable = 0;

        // --- Driver selection ---
        if ($value$plusargs("DRIVER=%s", str_tmp)) begin
            case (str_tmp)
                "simx":                  simx_enable = 1;
                "fpga", "opae", "xrt":   simx_enable = 0;
                default: ;
            endcase
        end

        // Recalculate all derived values — UP(x) = max(x,1)
        num_barriers   = (num_warps / 2 > 0) ? (num_warps / 2) : 1;
        socket_size    = (num_cores < 4) ? num_cores : 4;
        num_icaches    = icache_enable ? ((socket_size + 3) / 4) : 0;
        num_dcaches    = dcache_enable ? ((socket_size + 3) / 4) : 0;
        num_alu_lanes  = num_threads;
        num_fpu_lanes  = num_threads;
        num_lsu_lanes  = num_threads;
        issue_width    = (num_warps < 8) ? 1 : (num_warps / 8);

        // mem_data/byteen/tag NEVER change — re-assert for safety
        mem_data_width   = VX_MEM_DATA_WIDTH;    // 512
        mem_byteen_width = VX_MEM_BYTEEN_WIDTH;  // 64
        mem_tag_width    = VX_MEM_TAG_WIDTH;      // 8

        // AXI ID/DATA/STRB widths are FIXED — re-assert
        AXI_ID_WIDTH   = VX_MEM_TAG_WIDTH;    // 8
        AXI_DATA_WIDTH = VX_MEM_DATA_WIDTH;   // 512
        AXI_STRB_WIDTH = VX_MEM_BYTEEN_WIDTH; // 64
        // AXI_ADDR_WIDTH already updated above if XLEN_64

        if (program_path != "")
            program_entry_point = startup_addr;

    endfunction

    //==========================================================================
    // VALIDATION
    //==========================================================================

    virtual function bit is_valid();
        bit valid = 1;

        if (num_cores == 0 || num_warps == 0 || num_threads == 0) begin
            `uvm_error("VORTEX_CFG", "Invalid: zero cores/warps/threads")
            valid = 0;
        end
        if (ext_d_enable && !ext_f_enable) begin
            `uvm_error("VORTEX_CFG", "D extension requires F extension")
            valid = 0;
        end
        if (l3_enable && !l2_enable) begin
            `uvm_error("VORTEX_CFG", "L3 requires L2")
            valid = 0;
        end
        if (simx_enable && simx_path == "") begin
            `uvm_error("VORTEX_CFG", "simx enabled but simx_path not set — pass +SIMX_PATH=<path>")
            valid = 0;
        end
        if (!xlen_64 && mem_addr_width > 32) begin
            `uvm_error("VORTEX_CFG", "XLEN=32 but mem_addr_width > 32")
            valid = 0;
        end
        if (mem_data_width != VX_MEM_DATA_WIDTH) begin
            `uvm_fatal("VORTEX_CFG", "mem_data_width overwritten! Must equal VX_MEM_DATA_WIDTH (512)")
            valid = 0;
        end
        if (mem_tag_width != VX_MEM_TAG_WIDTH) begin
            `uvm_fatal("VORTEX_CFG", "mem_tag_width overwritten! Must equal VX_MEM_TAG_WIDTH (8)")
            valid = 0;
        end
        if (AXI_ID_WIDTH != VX_MEM_TAG_WIDTH) begin
            `uvm_fatal("VORTEX_CFG", "AXI_ID_WIDTH overwritten! Must equal VX_MEM_TAG_WIDTH (8)")
            valid = 0;
        end
        if (AXI_DATA_WIDTH != VX_MEM_DATA_WIDTH) begin
            `uvm_fatal("VORTEX_CFG", "AXI_DATA_WIDTH overwritten! Must equal VX_MEM_DATA_WIDTH (512)")
            valid = 0;
        end
        if (axi_agent_enable && mem_agent_enable) begin
            `uvm_error("VORTEX_CFG", "Both AXI and MEM agents enabled — pick one interface path")
            valid = 0;
        end
        return valid;
    endfunction

    //==========================================================================
    // PRINT SUMMARY
    //==========================================================================

    virtual function void print_config(uvm_verbosity verbosity = UVM_MEDIUM);
        `uvm_info("VORTEX_CFG", "================================================================================", verbosity)
        `uvm_info("VORTEX_CFG", "             VORTEX UVM CONFIGURATION SUMMARY", verbosity)
        `uvm_info("VORTEX_CFG", "================================================================================", verbosity)

        `uvm_info("VORTEX_CFG", $sformatf("\n--- Architecture ---"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Clusters: %0d  Cores: %0d  Warps: %0d  Threads: %0d",
            num_clusters, num_cores, num_warps, num_threads), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  XLEN: %0d  FLEN: %0d  Issue Width: %0d",
            xlen, flen, issue_width), verbosity)

        `uvm_info("VORTEX_CFG", $sformatf("\n--- Memory Interface (pkg params) ---"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Path:        %s",
            axi_agent_enable ? "AXI4 (USE_AXI_WRAPPER)" : "Custom MEM"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Data Width:  %0d bits  (VX_MEM_DATA_WIDTH=%0d)",
            mem_data_width, VX_MEM_DATA_WIDTH), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Byte Enable: %0d bits  (VX_MEM_BYTEEN_WIDTH=%0d)",
            mem_byteen_width, VX_MEM_BYTEEN_WIDTH), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Tag Width:   %0d bits  (VX_MEM_TAG_WIDTH=%0d)",
            mem_tag_width, VX_MEM_TAG_WIDTH), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Word Addr:   %0d bits  (VX_MEM_ADDR_WIDTH=%0d)",
            VX_MEM_ADDR_WIDTH, VX_MEM_ADDR_WIDTH), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Byte Addr:   %0d bits  (mem_addr_width=%0d)",
            mem_addr_width, mem_addr_width), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Startup:     0x%h", startup_addr), verbosity)

        `uvm_info("VORTEX_CFG", $sformatf("\n--- AXI4 (when USE_AXI_WRAPPER) ---"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  ID=%0d  ADDR=%0d  DATA=%0d  STRB=%0d",
            AXI_ID_WIDTH, AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_STRB_WIDTH), verbosity)

        `uvm_info("VORTEX_CFG", $sformatf("\n--- Cache ---"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  I$:%s D$:%s L2:%s L3:%s",
            icache_enable?"ON":"OFF", dcache_enable?"ON":"OFF",
            l2_enable?"ON":"OFF", l3_enable?"ON":"OFF"), verbosity)

        `uvm_info("VORTEX_CFG", $sformatf("\n--- Agents ---"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  MEM: en=%0b active=%0b  AXI: en=%0b active=%0b",
            mem_agent_enable, mem_agent_is_active,
            axi_agent_enable, axi_agent_is_active), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  DCR: en=%0b active=%0b  Status: passive",
            dcr_agent_enable, dcr_agent_is_active), verbosity)

        `uvm_info("VORTEX_CFG", $sformatf("\n--- Simulation ---"), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Timeout: %0d cycles  Reset: %0d cycles",
            test_timeout_cycles, reset_cycles), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Waves: %s  File: %s",
            dump_waves?"YES":"NO", wave_file_name), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  Program: %s", program_path), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  simx: %s  Path: %s",
            simx_enable?"ON":"OFF", simx_path), verbosity)
        `uvm_info("VORTEX_CFG", $sformatf("  CLK: %0d MHz  Period: %.2f ns",
            CLK_FREQ_MHZ, CLK_PERIOD_NS), verbosity)

        `uvm_info("VORTEX_CFG", "================================================================================\n", verbosity)
    endfunction

    //==========================================================================
    // HELPERS
    //==========================================================================

    virtual function string get_config_string();
        return $sformatf("%0dCL_%0dC_%0dW_%0dT_%s_%s_%s",
            num_clusters, num_cores, num_warps, num_threads,
            xlen_64 ? "RV64" : "RV32",
            ext_f_enable ? (ext_d_enable ? "FD" : "F") : "I",
            axi_agent_enable ? "AXI" : "MEM");
    endfunction

    virtual function string get_verilog_defines();
        string d = "";
        d = {d, $sformatf("+define+NUM_CLUSTERS=%0d ", num_clusters)};
        d = {d, $sformatf("+define+NUM_CORES=%0d ",    num_cores)};
        d = {d, $sformatf("+define+NUM_WARPS=%0d ",    num_warps)};
        d = {d, $sformatf("+define+NUM_THREADS=%0d ",  num_threads)};
        if (xlen_64)          d = {d, "+define+XLEN_64 "};
        if (ext_f_enable)     d = {d, "+define+EXT_F_ENABLE=1 "};
        if (ext_d_enable)     d = {d, "+define+EXT_D_ENABLE=1 "};
        if (ext_m_enable)     d = {d, "+define+EXT_M_ENABLE=1 "};
        if (icache_enable)    d = {d, "+define+ICACHE_ENABLE=1 "};
        if (dcache_enable)    d = {d, "+define+DCACHE_ENABLE=1 "};
        if (l2_enable)        d = {d, "+define+L2_ENABLE=1 "};
        if (l3_enable)        d = {d, "+define+L3_ENABLE=1 "};
        if (axi_agent_enable) d = {d, "+define+USE_AXI_WRAPPER "};
        d = {d, $sformatf("+define+STARTUP_ADDR=64'h%h ", startup_addr)};
        return d;
    endfunction

endclass : vortex_config

endpackage : vortex_config_pkg

`endif // VORTEX_CONFIG_SV