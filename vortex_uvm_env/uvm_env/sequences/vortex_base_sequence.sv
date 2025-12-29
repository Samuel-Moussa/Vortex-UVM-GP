`ifndef VORTEX_BASE_SEQUENCE_SV
`define VORTEX_BASE_SEQUENCE_SV

class vortex_base_sequence extends uvm_sequence;

  `uvm_object_utils(vortex_base_sequence)

  function new(string name = "vortex_base_sequence");
    super.new(name);
  endfunction

  // Sequencer handles for all agents
  mem_sequencer m_mem_sequencer;
  axi_sequencer m_axi_sequencer;
  dcr_sequencer m_dcr_sequencer;
  host_sequencer m_host_sequencer;

  virtual task body();
    // Get the sequencer handles from the config DB
    uvm_config_db#(mem_sequencer)::get(null, get_full_name(), "m_mem_sequencer", m_mem_sequencer);
    uvm_config_db#(axi_sequencer)::get(null, get_full_name(), "m_axi_sequencer", m_axi_sequencer);
    uvm_config_db#(dcr_sequencer)::get(null, get_full_name(), "m_dcr_sequencer", m_dcr_sequencer);
    uvm_config_db#(host_sequencer)::get(null, get_full_name(), "m_host_sequencer", m_host_sequencer);
  endtask

endclass : vortex_base_sequence

`endif // VORTEX_BASE_SEQUENCE_SV
