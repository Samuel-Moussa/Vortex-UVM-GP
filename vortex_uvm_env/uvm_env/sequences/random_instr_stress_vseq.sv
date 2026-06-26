////////////////////////////////////////////////////////////////////////////////
// File: uvm_env/sequences/random_instr_stress_vseq.sv
// Description: Virtual Sequence for Random Instruction Stress Test
//
// Extends vortex_virtual_sequence (same as kernel_launch_vseq.sv).
// Uses p_sequencer.m_host_sequencer — exactly as kernel_launch_vseq.sv does.
// cfg is populated by vortex_virtual_sequence::pre_body() automatically.
//
// Key difference vs kernel_launch_vseq:
//   - Wraps launch + wait_done in a for-loop (num_iterations)
//   - Calls cfg.ebreak_event.reset() before each iteration so
//     wait_for_execution_complete() blocks correctly on iterations 2+
//     (the event stays triggered after iter 0 otherwise)
////////////////////////////////////////////////////////////////////////////////

`ifndef RANDOM_INSTR_STRESS_VSEQ_SV
`define RANDOM_INSTR_STRESS_VSEQ_SV

class random_instr_stress_vseq extends vortex_virtual_sequence;
    `uvm_object_utils(random_instr_stress_vseq)

    // Knob — set by the test before calling vseq.start()
    int unsigned num_iterations = 1;

    function new(string name = "random_instr_stress_vseq");
        super.new(name);
    endfunction

    virtual task body();
        host_launch_kernel_sequence launch_seq;
        host_wait_done_sequence     wait_seq;

        if (p_sequencer == null)
            `uvm_fatal("STRESS_VSEQ",
                "p_sequencer is null — start this sequence on env.m_virtual_sequencer")

        if (cfg == null)
            `uvm_fatal("STRESS_VSEQ",
                "cfg is null — pre_body() did not find vortex_config on the virtual sequencer")

        for (int iter = 0; iter < int'(num_iterations); iter++) begin

            `uvm_info("STRESS_VSEQ",
                $sformatf("--- Stress iteration %0d / %0d ---",
                           iter+1, num_iterations), UVM_LOW)

            // Reset ebreak_event so wait_trigger() blocks on every iteration
            // after the first (event stays triggered from previous iteration).
            if (cfg.ebreak_event != null)
                cfg.ebreak_event.reset();

            // 1. Launch kernel already loaded into mem_model by load_program()
            launch_seq = host_launch_kernel_sequence::type_id::create(
                             $sformatf("launch_seq_%0d", iter));
            launch_seq.startup_address = cfg.startup_addr;
            launch_seq.num_cores       = cfg.num_cores;
            launch_seq.num_warps       = cfg.num_warps;
            launch_seq.num_threads     = cfg.num_threads;

            `uvm_info("STRESS_VSEQ",
                $sformatf("Iter %0d: launching at 0x%016h (cores=%0d warps=%0d threads=%0d)",
                           iter+1, launch_seq.startup_address,
                           launch_seq.num_cores,
                           launch_seq.num_warps,
                           launch_seq.num_threads), UVM_LOW)

            launch_seq.start(p_sequencer.m_host_sequencer);

            // 2. Wait for EBREAK — same mechanism as kernel_launch_vseq.sv
            wait_seq = host_wait_done_sequence::type_id::create(
                           $sformatf("wait_seq_%0d", iter));
            wait_seq.timeout_cycles = int'(cfg.test_timeout_cycles);

            `uvm_info("STRESS_VSEQ",
                $sformatf("Iter %0d: waiting for EBREAK (timeout=%0d cycles)",
                           iter+1, wait_seq.timeout_cycles), UVM_LOW)

            wait_seq.start(p_sequencer.m_host_sequencer);

            `uvm_info("STRESS_VSEQ",
                $sformatf("Iter %0d: DONE", iter+1), UVM_LOW)

        end // for

        `uvm_info("STRESS_VSEQ",
            $sformatf("random_instr_stress_vseq complete — %0d iteration(s) passed",
                       num_iterations), UVM_LOW)

    endtask

endclass : random_instr_stress_vseq

`endif // RANDOM_INSTR_STRESS_VSEQ_SV
