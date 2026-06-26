////////////////////////////////////////////////////////////////////////////////
// File: uvm_tests/warp_scheduling_test.sv
// Description: Warp Scheduling Directed Test
//
// Drives the warp_test kernel (warp_test.elf) against the DUT and SimX.
// The kernel covers four warp/thread-management scenarios in one binary:
//   T1: Thread Mask Control (TMC)
//   T2: Nested Warp Divergence (Split/Join / IPDOM stack)
//   T3: Warp Spawn and Scheduling (wspawn, asymmetric workloads)
//   T4: Thread Local Storage / warp context isolation
//
// Each sub-test writes position-unique sentinels to the result region.
// Any DUT scheduling or divergence bug manifests as a memory or console
// mismatch caught by the scoreboard. No new scoreboard fields are added;
// the check is pure black-box end-state equivalence vs SimX.
//
// Minimum config: num_warps >= 4, num_threads >= 4.
// The test fatals (does not silently adjust) if these minimums are not met.
//
// Run:
//   make sim TEST=warp_scheduling_test PROGRAM_NAME=warp_test \
//            INTERFACE=axi TIMEOUT=5000000
////////////////////////////////////////////////////////////////////////////////

`ifndef WARP_SCHEDULING_TEST_SV
`define WARP_SCHEDULING_TEST_SV

class warp_scheduling_test extends kernel_launch_test;
    `uvm_component_utils(warp_scheduling_test)

    localparam int MIN_WARPS   = 4;
    localparam int MIN_THREADS = 4;

    function new(string name = "warp_scheduling_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void customize_config();
        // Set our default program before calling super, so super's fallback
        // (which fills program_path only when empty) does not overwrite it.
        // If +PROGRAM was passed via plusarg, apply_plusargs() already set
        // cfg.program_path before this method runs — we do not overwrite that.
        if (cfg.program_path == "")
            cfg.program_path = "../Vortex/tests/kernel/warp_test/warp_test.elf";

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
                $sformatf("warp_scheduling_test requires num_warps >= %0d (configured: %0d). Pass +NUM_WARPS=%0d or higher.",
                    MIN_WARPS, cfg.num_warps, MIN_WARPS))
        end
        if (cfg.num_threads < MIN_THREADS) begin
            `uvm_fatal(get_type_name(),
                $sformatf("warp_scheduling_test requires num_threads >= %0d (configured: %0d). Pass +NUM_THREADS=%0d or higher.",
                    MIN_THREADS, cfg.num_threads, MIN_THREADS))
        end
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info(get_type_name(), {"\n",
            "----------------------------------------------------------------\n",
            " WARP SCHEDULING TEST                                          \n",
            "----------------------------------------------------------------\n",
            "  Scenarios:                                                   \n",
            "    T1: Thread Mask Control (TMC)                              \n",
            "    T2: Nested Divergence — Split/Join (IPDOM stack)           \n",
            "    T3: Warp Spawn + Scheduling (asymmetric workloads)         \n",
            "    T4: Thread Local Storage / warp context isolation          \n",
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

endclass : warp_scheduling_test

`endif // WARP_SCHEDULING_TEST_SV
