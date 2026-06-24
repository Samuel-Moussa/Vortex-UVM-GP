////////////////////////////////////////////////////////////////////////////////
// File: uvm_tests/axi_memory_test.sv
// Description: AXI Memory Interface Directed Test
//
// Drives the axi_traffic kernel (axi_traffic.elf) against the DUT and SimX
// specifically on the AXI4 memory path (+USE_AXI_WRAPPER required). The kernel
// covers four AXI-specific traffic patterns in one binary:
//   T1: Multi-line sequential R/W — 4 threads write+read 4 cache lines in
//       parallel; exercises multiple sequential AW/W and AR/R transactions
//       and the B-channel response pipeline
//   T2: Byte-granularity writes   — 4 threads write individual bytes across
//       one cache line via char* stores; exercises non-trivial wstrb patterns
//       in the AXI W channel
//   T3: Write-then-read ordering  — per-thread store immediately followed by
//       load to the same address; exercises correct AXI W→AR/R ordering
//   T4: Dense back-to-back writes — 4 cache lines written sequentially by
//       thread 0, then read back in parallel; stresses the AW/W pipeline
//       depth and B-channel ID matching in the AXI wrapper
//
// AXI configuration verified:
//   DATA_WIDTH = 512 bits (64 bytes = one cache line per AXI beat)
//   ADDR_WIDTH = 32 bits (RV32)
//   ID_WIDTH   = 8 bits (1 cluster / 1 core configuration)
//   AXI_NUM_BANKS = 1 (single AXI port)
//
// Note on ID_WIDTH: vortex_axi_if.sv declares a generous upper-bound of
// ID_WIDTH=50 for interface compatibility across configs, but the DUT drives
// only the low 8 bits for this 1c/1c config. No test code interprets the ID
// directly; this is a known-harmless oversize in the interface declaration.
//
// This test REQUIRES the AXI path. It fatals if +USE_AXI_WRAPPER was not
// passed (cfg.axi_agent_enable == 0). Do not run it under custom-mem — use
// functional_memory_test for that.
//
// Check model: black-box end-state equivalence vs SimX (Gate 1) plus an
// absolute sentinel check at RESULT_ADDR=0x80010000 (Gate 2).
//
// Minimum config: num_warps >= 4, num_threads >= 4, +USE_AXI_WRAPPER.
// The test fatals (does not silently adjust) if these requirements are not met.
//
// Run:
//   make sim TEST=axi_memory_test PROGRAM_NAME=axi_traffic \
//            INTERFACE=axi TIMEOUT=5000000
////////////////////////////////////////////////////////////////////////////////

`ifndef AXI_MEMORY_TEST_SV
`define AXI_MEMORY_TEST_SV

class axi_memory_test extends kernel_launch_test;
    `uvm_component_utils(axi_memory_test)

    localparam int MIN_WARPS   = 4;
    localparam int MIN_THREADS = 4;

    function new(string name = "axi_memory_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void customize_config();
        // Set our default program before calling super, so super's fallback
        // (which fills program_path only when empty) does not overwrite it.
        // If +PROGRAM was passed via plusarg, apply_plusargs() already set
        // cfg.program_path before this method runs — we do not overwrite that.
        if (cfg.program_path == "")
            cfg.program_path = "../Vortex/tests/kernel/axi_traffic/axi_traffic.elf";

        // Delegate to kernel_launch_test for scoreboard/coverage/SimX enable,
        // conform-timeout detection, and RESULT_BASE_ADDR / RESULT_SIZE_BYTES
        // plusarg handling.
        super.customize_config();

        // Set scenario-specific result window unless the user provided an
        // explicit +RESULT_BASE_ADDR override (super sets addr=0 when no plusarg).
        if (cfg.result_base_addr == 64'h0) begin
            cfg.result_base_addr  = 64'h0000_0000_8001_0000;
            cfg.result_size_bytes = 4;
        end

        // Enforce minimum hardware configuration for this scenario.
        // Policy: fatal-and-refuse — never silently bump the operator's config.
        if (cfg.num_warps < MIN_WARPS) begin
            `uvm_fatal(get_type_name(),
                $sformatf("axi_memory_test requires num_warps >= %0d (configured: %0d). Pass +NUM_WARPS=%0d or higher.",
                    MIN_WARPS, cfg.num_warps, MIN_WARPS))
        end
        if (cfg.num_threads < MIN_THREADS) begin
            `uvm_fatal(get_type_name(),
                $sformatf("axi_memory_test requires num_threads >= %0d (configured: %0d). Pass +NUM_THREADS=%0d or higher.",
                    MIN_THREADS, cfg.num_threads, MIN_THREADS))
        end

        // This test by name targets the AXI memory path. Running it under
        // custom-mem would defeat its purpose. apply_plusargs() sets
        // axi_agent_enable=1 when +USE_AXI_WRAPPER is present; if it is still
        // 0 here, the operator forgot the flag.
        if (!cfg.axi_agent_enable) begin
            `uvm_fatal(get_type_name(),
                "axi_memory_test requires the AXI interface (Vortex_axi wrapper). Add +USE_AXI_WRAPPER to the simulation command, or use INTERFACE=axi in the make invocation.")
        end
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info(get_type_name(), {"\n",
            "----------------------------------------------------------------\n",
            " AXI MEMORY TEST                                               \n",
            "----------------------------------------------------------------\n",
            "  Scenarios:                                                   \n",
            "    T1: Multi-line sequential R/W (AW/W + AR/R pipeline)      \n",
            "    T2: Byte-granularity writes (AXI wstrb coverage)          \n",
            "    T3: Write-then-read ordering (AXI W → AR/R)               \n",
            "    T4: Dense back-to-back writes (B-channel ID matching)     \n",
            "  AXI config: DATA=512b  ADDR=32b  ID=8b  BANKS=1             \n",
            "  Check model: black-box end-state vs SimX                    \n",
            "    Sentinel memory window: 0x80010000 (4 bytes)               \n",
            "    Console compare:        vx_printf output streams           \n",
            $sformatf("  Warps=%0d Threads=%0d\n", cfg.num_warps, cfg.num_threads),
            $sformatf("  Program: %s\n", cfg.program_path),
            "----------------------------------------------------------------"
        }, UVM_LOW)
    endfunction

    // load_program, run_test_stimulus: inherited from kernel_launch_test.
    //
    // check_results: extends the inherited equivalence gate with an absolute
    // sentinel check. The inherited gate verifies DUT == SimX end-state; this
    // override additionally verifies that RESULT_ADDR holds 0x900DCAFE — the
    // kernel's success magic. Without this second gate, a test where both DUT
    // and SimX produce the same wrong output would pass the scoreboard silently.
    virtual function void check_results();
        mem_model mem;
        bit [31:0] sentinel;

        // Gate 1: DUT-vs-SimX equivalence (inherited scoreboard gate)
        super.check_results();

        // Gate 2: absolute-correctness sentinel — only meaningful if gate 1 passed.
        // If gate 1 already failed, the kernel did not complete or both sides
        // diverged; adding more errors here would be noise.
        if (!test_passed) return;

        if (!uvm_config_db#(mem_model)::get(null, "*", "mem_model", mem)) begin
            `uvm_error(get_type_name(),
                "FAIL — mem_model not available for absolute sentinel check at RESULT_ADDR")
            test_passed = 0;
            return;
        end

        sentinel = mem.read_word(64'h0000_0000_8001_0000);
        if (sentinel !== 32'h900DCAFE) begin
            `uvm_error(get_type_name(),
                $sformatf("FAIL — kernel reported errors: RESULT_ADDR=0x80010000=0x%08h (expected 0x900DCAFE); DUT==SimX equivalence held but the kernel itself failed",
                    sentinel))
            test_passed = 0;
        end else begin
            `uvm_info(get_type_name(),
                "PASS — RESULT_ADDR=0x900DCAFE: kernel success sentinel confirmed",
                UVM_LOW)
        end
    endfunction

endclass : axi_memory_test

`endif // AXI_MEMORY_TEST_SV
