////////////////////////////////////////////////////////////////////////////////
// File: uvm_tests/functional_memory_test.sv
// Description: Functional Memory Directed Test
//
// Drives the functional_mem kernel (functional_mem.elf) against the DUT and
// SimX. The kernel covers four memory-subsystem scenarios in one binary:
//   T1: Word/halfword/byte access — all 4 threads, catches data-path width bugs
//   T2: Per-thread strided access — each thread writes buf[tid*4], catches
//       per-lane address computation bugs
//   T3: Tight read-after-write   — store + load to same address per thread,
//       catches LSU bypass and write-through failures
//   T4: Cross-warp visibility    — warp 0 writes a shared buffer, vx_barrier,
//       all warps confirm every entry is visible; catches cache coherence and
//       barrier-ordering bugs
//
// This test exercises the custom-mem memory path by default (no
// +USE_AXI_WRAPPER). It also runs cleanly under the AXI path
// (+USE_AXI_WRAPPER) for secondary coverage — the kernel is interface-
// agnostic, so the same binary can stress both paths.
//
// Check model: black-box end-state equivalence vs SimX (Gate 1) plus an
// absolute sentinel check at RESULT_ADDR=0x80010000 (Gate 2).
//
// Minimum config: num_warps >= 4, num_threads >= 4.
// The test fatals (does not silently adjust) if these minimums are not met.
//
// Run (custom-mem path, default):
//   make sim TEST=functional_memory_test PROGRAM_NAME=functional_mem \
//            INTERFACE=mem TIMEOUT=5000000
//
// Run (AXI path, secondary):
//   make sim TEST=functional_memory_test PROGRAM_NAME=functional_mem \
//            INTERFACE=axi TIMEOUT=5000000
////////////////////////////////////////////////////////////////////////////////

`ifndef FUNCTIONAL_MEMORY_TEST_SV
`define FUNCTIONAL_MEMORY_TEST_SV

class functional_memory_test extends kernel_launch_test;
    `uvm_component_utils(functional_memory_test)

    localparam int MIN_WARPS   = 4;
    localparam int MIN_THREADS = 4;

    function new(string name = "functional_memory_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void customize_config();
        // Set our default program before calling super, so super's fallback
        // (which fills program_path only when empty) does not overwrite it.
        // If +PROGRAM was passed via plusarg, apply_plusargs() already set
        // cfg.program_path before this method runs — we do not overwrite that.
        if (cfg.program_path == "")
            cfg.program_path = "../Vortex/tests/kernel/functional_mem/functional_mem.elf";

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
                $sformatf("functional_memory_test requires num_warps >= %0d (configured: %0d). Pass +NUM_WARPS=%0d or higher.",
                    MIN_WARPS, cfg.num_warps, MIN_WARPS))
        end
        if (cfg.num_threads < MIN_THREADS) begin
            `uvm_fatal(get_type_name(),
                $sformatf("functional_memory_test requires num_threads >= %0d (configured: %0d). Pass +NUM_THREADS=%0d or higher.",
                    MIN_THREADS, cfg.num_threads, MIN_THREADS))
        end
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info(get_type_name(), {"\n",
            "----------------------------------------------------------------\n",
            " FUNCTIONAL MEMORY TEST                                        \n",
            "----------------------------------------------------------------\n",
            "  Scenarios:                                                   \n",
            "    T1: Word/Halfword/Byte access (data-path width)            \n",
            "    T2: Per-thread strided access (address computation)        \n",
            "    T3: Tight Read-After-Write (LSU bypass/write-through)      \n",
            "    T4: Cross-warp memory visibility (barrier + cache)         \n",
            "  Interface: ",
            cfg.axi_agent_enable ? "AXI4 (secondary coverage)\n" :
                                   "Custom-MEM (primary)\n",
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

endclass : functional_memory_test

`endif // FUNCTIONAL_MEMORY_TEST_SV
