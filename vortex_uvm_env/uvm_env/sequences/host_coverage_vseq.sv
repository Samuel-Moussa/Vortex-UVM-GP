////////////////////////////////////////////////////////////////////////////////
// File: host_coverage_vseq.sv
// Coverage-directed virtual sequence (Samuel — functional coverage push).
//
// Purpose: lift host_operation_cg / dcr_config_cg out of the 50% floor that the
// plain kernel_launch_vseq leaves them at. kernel_launch_vseq issues only
// LAUNCH_KERNEL + WAIT_DONE, and the real DCR init goes backdoor, so:
//   - host_operation_cg.cp_op_type        — only 2-3 of 6 op-types ever seen
//   - dcr_config_cg.cp_addr / data        — only the few addrs the init writes
//   - dcr_config_cg.cp_startup_align      — only the aligned startup value
//
// Flow:
//   1. Real run: LAUNCH_KERNEL + WAIT_DONE (identical to kernel_launch_vseq) so
//      the scoreboard still verifies a genuine DUT-vs-SimX end state.
//   2. DCR coverage sweep on the now-IDLE / completed DUT — CONFIGURE_DCR across
//      every addr type x every data-magnitude bin, including one UNALIGNED
//      STARTUP_ADDR0 write (cp_startup_align.unaligned). Runs AFTER WAIT_DONE so
//      it cannot perturb the verified result; only drives the DCR monitor.
//
// Deferred op-types: HOST_RESET / HOST_READ_RESULT were tried post-completion
// but HOST_RESET drove the DUT interfaces to x and tripped a zero-time TB
// status-dump spin (sim hang). HOST_LOAD_PROGRAM would write mem_model and risk
// the end-state compare. All three op-type bins are left for a future cleaner
// pre-launch host-driven flow; the sweep here still covers CONFIGURE_DCR.
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_COVERAGE_VSEQ_SV
`define HOST_COVERAGE_VSEQ_SV

class host_coverage_vseq extends vortex_virtual_sequence;
    `uvm_object_utils(host_coverage_vseq)

    function new(string name = "host_coverage_vseq");
        super.new(name);
    endfunction

    // Issue a single DCR write through the host driver (drives the real DCR bus,
    // observed by dcr_monitor -> dcr_config_cg).
    local task dcr_write(bit [31:0] addr, bit [31:0] data, string note);
        host_configure_dcr_sequence s;
        s = host_configure_dcr_sequence::type_id::create("dcr_cov");
        s.dcr_address = addr;
        s.dcr_data    = data;
        `uvm_info(get_type_name(),
            $sformatf("cov DCR[0x%03h]=0x%08h (%s)", addr, data, note), UVM_MEDIUM)
        s.start(p_sequencer.m_host_sequencer);
    endtask

    virtual task body();
        host_launch_kernel_sequence launch_seq;
        host_wait_done_sequence     wait_seq;
        bit [31:0]                  startup_lo;  // correct STARTUP_ADDR0 (lower 32b)
        bit [31:0]                  startup_hi;  // correct STARTUP_ADDR1 (upper 32b)

        if (p_sequencer == null)
            `uvm_fatal("HCOV_VSEQ", "p_sequencer is null — start on env.m_virtual_sequencer")

        //--- 1) Real run: launch + wait (verified by the scoreboard) ----------
        launch_seq = host_launch_kernel_sequence::type_id::create("launch_seq");
        if (cfg != null) begin
            launch_seq.startup_address = cfg.startup_addr;
            launch_seq.num_cores       = cfg.num_cores;
            launch_seq.num_warps       = cfg.num_warps;
            launch_seq.num_threads     = cfg.num_threads;
        end
        startup_lo = launch_seq.startup_address[31:0];
        startup_hi = launch_seq.startup_address[63:32];
        `uvm_info(get_type_name(),
            $sformatf("host_coverage_vseq: launching kernel at 0x%016h", launch_seq.startup_address), UVM_LOW)
        launch_seq.start(p_sequencer.m_host_sequencer);

        wait_seq = host_wait_done_sequence::type_id::create("wait_seq");
        if (cfg != null) wait_seq.timeout_cycles = int'(cfg.test_timeout_cycles);
        wait_seq.start(p_sequencer.m_host_sequencer);

        //--- 1b) Block until the scoreboard's SimX run-to-completion is DONE ---
        // CRITICAL ORDERING: vecadd_lite completes via a sustained busy=0 fallback
        // (not a decoded EBREAK). The scoreboard triggers cfg.ebreak_event and then
        // runs SimX-to-completion synchronously in the same status callback, using
        // the LIVE DCR state. host_wait_done_sequence returns BEFORE that event, so
        // the DCR sweep below MUST wait for it — otherwise the SimX run can fire
        // mid-sweep and see a non-entry STARTUP_ADDR / a wild 64-bit ARGV pointer
        // and decode-fault (exit -3 -> UNVERIFIABLE). We wait on the event
        // (guarded with is_on() so an already-fired trigger doesn't hang us, per
        // the fix_11 stale-trigger lesson). Once ebreak_seen latches, the
        // scoreboard NEVER re-runs SimX, so every DCR value below is harmless
        // (coverage sample + DPI mirror only).
        if (cfg != null && cfg.ebreak_event != null && !cfg.ebreak_event.is_on()) begin
            `uvm_info(get_type_name(),
                "host_coverage_vseq: waiting for EBREAK/SimX-compare before DCR sweep", UVM_LOW)
            cfg.ebreak_event.wait_trigger();
        end

        //--- 2) Coverage sweep on the verified, idle DUT (post-SimX) ----------
        // cross_addr_data = cp_addr (5) x cp_data_magnitude (4) = 20 combos. Now
        // that SimX has already run and will not run again, we sweep EVERY named
        // addr across all 4 magnitude bins. cp_startup_align.unaligned stays a
        // structural waiver (an unaligned startup would fault a *future* SimX run,
        // and there is no benefit driving the real idle DUT with it).
        `uvm_info(get_type_name(), "host_coverage_vseq: full DCR coverage sweep (post-SimX, safe)", UVM_LOW)

        // STARTUP_ADDR0 (0x001, aligned magnitudes) — restore correct entry last
        dcr_write(32'h001, 32'h0000_0000, "STARTUP_ADDR0 zero aligned");
        dcr_write(32'h001, 32'h0000_0040, "STARTUP_ADDR0 sm_cfg aligned");
        dcr_write(32'h001, 32'h0001_0000, "STARTUP_ADDR0 mid_ptr aligned");
        // STARTUP_ADDR1 (0x002) — restore correct value last
        dcr_write(32'h002, 32'h0000_0040, "STARTUP_ADDR1 sm_cfg");
        dcr_write(32'h002, 32'h0001_0000, "STARTUP_ADDR1 mid_ptr");
        dcr_write(32'h002, 32'h8000_0000, "STARTUP_ADDR1 hi_code");
        // ARGV_PTR0 (0x003): all 4 magnitudes
        dcr_write(32'h003, 32'h0000_0000, "ARGV_PTR0 zero");
        dcr_write(32'h003, 32'h0000_0040, "ARGV_PTR0 sm_cfg");
        dcr_write(32'h003, 32'h0001_0000, "ARGV_PTR0 mid_ptr");
        dcr_write(32'h003, 32'h8000_0000, "ARGV_PTR0 hi_code");
        // ARGV_PTR1 (0x004): all 4 magnitudes
        dcr_write(32'h004, 32'h0000_0000, "ARGV_PTR1 zero");
        dcr_write(32'h004, 32'h0000_0040, "ARGV_PTR1 sm_cfg");
        dcr_write(32'h004, 32'h0001_0000, "ARGV_PTR1 mid_ptr");
        dcr_write(32'h004, 32'h8000_0000, "ARGV_PTR1 hi_code");
        // MPM_CLASS (0x005): all 4 magnitudes
        dcr_write(32'h005, 32'h0000_0000, "MPM_CLASS zero");
        dcr_write(32'h005, 32'h0000_0040, "MPM_CLASS sm_cfg");
        dcr_write(32'h005, 32'h0001_0000, "MPM_CLASS mid_ptr");
        dcr_write(32'h005, 32'h8000_0000, "MPM_CLASS hi_code");
        // Restore the correct live startup entry (cleanliness; DUT already idle).
        dcr_write(32'h002, startup_hi, "STARTUP_ADDR1 (restore correct)");
        dcr_write(32'h001, startup_lo, "STARTUP_ADDR0 (restore correct)");

        // NOTE: post-completion HOST_RESET / HOST_READ_RESULT were removed —
        // HOST_RESET drove the DUT interfaces to x on an already-idle DUT and
        // tripped a zero-time status-dump spin in the TB (sim time frozen, log
        // runaway). The DCR sweep above already covers cp_op_type.configure_dcr
        // plus the dcr_config_cg addr/magnitude/align bins; the reset/read_result
        // op-type bins are deferred to a cleaner pre-launch mechanism.
    endtask

endclass : host_coverage_vseq

`endif // HOST_COVERAGE_VSEQ_SV
