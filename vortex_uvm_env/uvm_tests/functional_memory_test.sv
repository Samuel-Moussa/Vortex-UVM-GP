`ifndef FUNCTIONAL_MEMORY_TEST_SV
`define FUNCTIONAL_MEMORY_TEST_SV

class functional_memory_test extends vortex_base_test;

  `uvm_component_utils(functional_memory_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    mem_write_read_sequence seq = mem_write_read_sequence::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(m_env.m_mem_agent.m_sequencer);
    phase.drop_objection(this);
  endtask

endclass : functional_memory_test

`endif // FUNCTIONAL_MEMORY_TEST_SV
