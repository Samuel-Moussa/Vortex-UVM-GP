////////////////////////////////////////////////////////////////////////////////
// File: host_coverage_test.sv
// Coverage-directed test (Samuel — functional coverage push).
//
// Reuses kernel_launch_test wholesale (program preload, scoreboard, completion
// checks) and only swaps the stimulus vseq for host_coverage_vseq, which runs
// the real launch+wait and then sweeps the remaining host/DCR op-type and
// data-magnitude bins on the idle DUT. See host_coverage_vseq.sv for the flow.
//
// Run: make sim-only TEST=host_coverage_test PROGRAM_NAME=vecadd_lite \
//        CLUSTERS=1 CORES=1 WARPS=4 THREADS=4 TIMEOUT=200000
////////////////////////////////////////////////////////////////////////////////

`ifndef HOST_COVERAGE_TEST_SV
`define HOST_COVERAGE_TEST_SV

class host_coverage_test extends kernel_launch_test;
    `uvm_component_utils(host_coverage_test)

    function new(string name = "host_coverage_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Only the stimulus phase differs from kernel_launch_test.
    virtual task run_test_stimulus();
        host_coverage_vseq vseq;

        if (env == null || env.m_virtual_sequencer == null)
            `uvm_fatal(get_type_name(), "Virtual sequencer is null")

        vseq     = host_coverage_vseq::type_id::create("vseq");
        vseq.cfg = cfg;
        `uvm_info(get_type_name(),
            $sformatf("Executing host_coverage_vseq at 0x%016h (cores=%0d warps=%0d threads=%0d)",
                cfg.startup_addr, cfg.num_cores, cfg.num_warps, cfg.num_threads), UVM_LOW)
        vseq.start(env.m_virtual_sequencer);
    endtask

endclass : host_coverage_test

`endif // HOST_COVERAGE_TEST_SV
