
`ifndef MEM_WRITE_READ_SEQUENCE_SV
`define MEM_WRITE_READ_SEQUENCE_SV

class mem_write_read_sequence extends vortex_base_sequence;

  `uvm_object_utils(mem_write_read_sequence)

  function new(string name = "mem_write_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    mem_transaction wr_trans;
    mem_transaction rd_trans;

    // Write transaction
    wr_trans = mem_transaction::type_id::create("wr_trans");
    start_item(wr_trans);
    assert(wr_trans.randomize() with { rw == 1; });
    finish_item(wr_trans);

    // Read transaction
    rd_trans = mem_transaction::type_id::create("rd_trans");
    start_item(rd_trans);
    assert(rd_trans.randomize() with { rw == 0; addr == wr_trans.addr; });
    finish_item(rd_trans);

  endtask

endclass : mem_write_read_sequence

`endif // MEM_WRITE_READ_SEQUENCE_SV
