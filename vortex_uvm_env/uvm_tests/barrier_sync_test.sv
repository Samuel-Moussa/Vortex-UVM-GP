////////////////////////////////////////////////////////////////////////////////
// File: uvm_tests/barrier_sync_test.sv
// Description: Barrier Synchronization Directed Test
//
// Drives the barrier_test kernel (barrier_test.elf) against the DUT and SimX.
// The kernel covers four barrier synchronization scenarios:
//   T1: Basic barrier      — pre/post sentinel pattern (hold-then-release)
//   T2: Staggered arrival  — asymmetric stall before barrier, post-barrier
//                             cross-check of all warps' pre-barrier writes
//   T3: Shared accumulator — two-phase accumulation with barrier between phases;
//                             catches early release via partial-sum detection
//   T4: Double barrier     — barrier used twice in sequence; catches one-shot
//                             (non-rearming) barrier implementations
//
// Minimum config: num_warps >= 4.
// The test fatals (does not silently adjust) if this minimum is not met.
//
// Run:
//   make sim TEST=barrier_sync_test PROGRAM_NAME=barrier_test \
//            INTERFACE=axi TIMEOUT=5000000
////////////////////////////////////////////////////////////////////////////////

`ifndef BARRIER_SYNC_TEST_SV
`define BARRIER_SYNC_TEST_SV

class barrier_sync_test extends kernel_launch_test;
    `uvm_component_utils(barrier_sync_test)

    localparam int MIN_WARPS = 4;

    function new(string name = "barrier_sync_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void customize_config();
        // Set our default program before calling super so super's fallback
        // (fills program_path only when empty) does not overwrite it.
        if (cfg.program_path == "")
            cfg.program_path = "../Vortex/tests/kernel/barrier_test/barrier_test.elf";

        // Delegate: enables scoreboard/coverage/SimX, handles plusargs.
        super.customize_config();

        // Scenario-specific result window (super sets addr=0 when no plusarg).
        if (cfg.result_base_addr == 64'h0) begin
            cfg.result_base_addr  = 64'h0000_0000_8001_0000;
            cfg.result_size_bytes = 4;
        end

        // Enforce minimum: meaningful barrier sync requires at least 4 warps.
        // Policy: fatal-and-refuse — do not silently adjust operator config.
        if (cfg.num_warps < MIN_WARPS) begin
            `uvm_fatal(get_type_name(),
                $sformatf("barrier_sync_test requires num_warps >= %0d (configured: %0d). Pass +NUM_WARPS=%0d or higher.",
                    MIN_WARPS, cfg.num_warps, MIN_WARPS))
        end
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info(get_type_name(), {"\n",
            "----------------------------------------------------------------\n",
            " BARRIER SYNCHRONIZATION TEST                                  \n",
            "----------------------------------------------------------------\n",
            "  Scenarios:                                                   \n",
            "    T1: Basic barrier — pre/post sentinel pattern              \n",
            "    T2: Staggered arrival — hold until slowest warp arrives    \n",
            "    T3: Shared accumulator — phase separation via barrier      \n",
            "    T4: Double barrier — barrier rearm after first release     \n",
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

endclass : barrier_sync_test

`endif // BARRIER_SYNC_TEST_SV
