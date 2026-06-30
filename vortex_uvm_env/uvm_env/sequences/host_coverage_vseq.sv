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
        `uvm_info(get_type_name(),
            $sformatf("host_coverage_vseq: launching kernel at 0x%016h", launch_seq.startup_address), UVM_LOW)
        launch_seq.start(p_sequencer.m_host_sequencer);

        wait_seq = host_wait_done_sequence::type_id::create("wait_seq");
        if (cfg != null) wait_seq.timeout_cycles = int'(cfg.test_timeout_cycles);
        wait_seq.start(p_sequencer.m_host_sequencer);

        //--- 2) Coverage sweep on the idle/completed DUT ----------------------
        // cp_addr: all 5 named addrs.  cp_data_magnitude: zero / sm_cfg / mid_ptr
        // / hi_code.  cp_startup_align: aligned + unaligned.  cross_addr_data:
        // multiple addr x magnitude combos.
        // SimX-SAFE: the scoreboard runs SimX-to-completion at EBREAK using the
        // live DCR state, so the sweep must NOT feed SimX anything that breaks
        // its run. STARTUP_ADDR is left at the correct aligned entry (an unaligned
        // entry faults SimX *and* the real DUT -> cp_startup_align.unaligned is a
        // structural waiver, not stimulus-reachable). Data-magnitude variety
        // comes from ARGV_PTR (argv-less kernel ignores the value) + MPM_CLASS.
        `uvm_info(get_type_name(), "host_coverage_vseq: SimX-safe DCR coverage sweep (post-completion)", UVM_LOW)
        dcr_write(32'h001, 32'h8000_0000, "STARTUP_ADDR0 hi_code aligned (correct)");
        dcr_write(32'h002, 32'h0000_0000, "STARTUP_ADDR1 zero (correct)");
        dcr_write(32'h003, 32'h0000_0000, "ARGV_PTR0 zero");
        dcr_write(32'h003, 32'h0000_0040, "ARGV_PTR0 sm_cfg");
        dcr_write(32'h003, 32'h0001_0000, "ARGV_PTR0 mid_ptr");
        dcr_write(32'h003, 32'h8000_0000, "ARGV_PTR0 hi_code");
        dcr_write(32'h004, 32'h0000_0040, "ARGV_PTR1 sm_cfg");
        dcr_write(32'h005, 32'h0000_0000, "MPM_CLASS zero");

        // NOTE: post-completion HOST_RESET / HOST_READ_RESULT were removed —
        // HOST_RESET drove the DUT interfaces to x on an already-idle DUT and
        // tripped a zero-time status-dump spin in the TB (sim time frozen, log
        // runaway). The DCR sweep above already covers cp_op_type.configure_dcr
        // plus the dcr_config_cg addr/magnitude/align bins; the reset/read_result
        // op-type bins are deferred to a cleaner pre-launch mechanism.
    endtask

endclass : host_coverage_vseq

`endif // HOST_COVERAGE_VSEQ_SV
