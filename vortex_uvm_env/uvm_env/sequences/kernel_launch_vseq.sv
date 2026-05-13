 ////////////////////////////////////////////////////////////////////////////////
// File: kernel_launch_vseq.sv
// Simple virtual sequence to launch a kernel via the host sequencer and wait
// for completion. Used by `kernel_launch_test`.
////////////////////////////////////////////////////////////////////////////////

`ifndef KERNEL_LAUNCH_VSEQ_SV
`define KERNEL_LAUNCH_VSEQ_SV

class kernel_launch_vseq extends vortex_virtual_sequence;
    `uvm_object_utils(kernel_launch_vseq)

    function new(string name = "kernel_launch_vseq");
        super.new(name);
    endfunction

    virtual task body();
        host_launch_kernel_sequence launch_seq;
        host_wait_done_sequence   wait_seq;

        // Ensure p_sequencer is available
        if (p_sequencer == null) begin
            `uvm_fatal("K_L_VSEQ", "p_sequencer is null — start this sequence on env.m_virtual_sequencer")
        end

        // Create and configure launch sequence
        launch_seq = host_launch_kernel_sequence::type_id::create("launch_seq");
        if (cfg != null) begin
            launch_seq.startup_address = cfg.startup_addr;
            launch_seq.num_cores       = cfg.num_cores;
            launch_seq.num_warps       = cfg.num_warps;
            launch_seq.num_threads     = cfg.num_threads;
        end

        `uvm_info(get_type_name(), $sformatf("kernel_launch_vseq: launching kernel at 0x%016h", launch_seq.startup_address), UVM_LOW)
        launch_seq.start(p_sequencer.m_host_sequencer);

        // Wait for the kernel to complete
        wait_seq = host_wait_done_sequence::type_id::create("wait_seq");
        if (cfg != null) wait_seq.timeout_cycles = int'(cfg.test_timeout_cycles);
        `uvm_info(get_type_name(), $sformatf("kernel_launch_vseq: waiting for completion (timeout=%0d cycles)", wait_seq.timeout_cycles), UVM_LOW)
        wait_seq.start(p_sequencer.m_host_sequencer);
    endtask

endclass : kernel_launch_vseq

`endif // KERNEL_LAUNCH_VSEQ_SV
