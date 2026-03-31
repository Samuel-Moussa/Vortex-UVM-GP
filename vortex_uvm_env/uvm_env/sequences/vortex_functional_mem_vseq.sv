////////////////////////////////////////////////////////////////////////////////
// File: vortex_functional_mem_vseq.sv
// Description: Functional Memory Virtual Sequence
//
// Reads the output buffer written by program_with_store.hex via the
// custom MEM agent and compares against the golden value.
//
// Requires: program_with_store.hex (sw x3, 0(t3) writes 3 to 0x80001000)
//
// Key facts from actual mem_sequences.sv:
//   mem_block_read_sequence.start_addr  -> rand bit[31:0], [2:0]==0 (8-byte aligned)
//   mem_block_read_sequence.num_words   -> rand int, constraint {[4:256]}
//   mem_block_read_sequence.read_data[] -> bit[63:0] per word (64-bit)
//   sw stores 32-bit -> result is in read_data[0][31:0]
//
// cfg is available from pre_body() - do NOT call super.body()
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_FUNCTIONAL_MEM_VSEQ_SV
`define VORTEX_FUNCTIONAL_MEM_VSEQ_SV 

`include "../agents/mem_agent/mem_sequences.sv"

class vortex_functional_mem_vseq extends vortex_virtual_sequence;
    `uvm_object_utils(vortex_functional_mem_vseq)

    // Output address: 0x80001000 — [2:0]==0 satisfies addr_aligned_c
    static const bit [31:0] OUTPUT_ADDR  = 32'h8000_1000;
    // Golden: program does 1+2=3, stores to 0x80001000
    static const bit [31:0] GOLDEN_VALUE = 32'h0000_0003;

    // Number of read-back iterations (referenced by functional_memory_test)
    int unsigned num_iterations = 1;

    function new(string name = "vortex_functional_mem_vseq");
        super.new(name);
    endfunction

    //==========================================================================
    // body()
    // cfg already populated by pre_body() from p_sequencer.cfg.
    // Do NOT call super.body().
    //==========================================================================
    virtual task body();
        mem_block_read_sequence rd_seq;

        `uvm_info("FUNC_MEM_VSEQ", $sformatf("Reading output buffer @ 0x%08h via MEM agent", OUTPUT_ADDR), UVM_LOW)

        rd_seq = mem_block_read_sequence::type_id::create("rd_seq");

        // Must meet constraint addr_aligned_c: start_addr[2:0] == 3'b000
        rd_seq.start_addr = OUTPUT_ADDR;  // 0x80001000[2:0] == 0 OK

        // Must meet constraint reasonable_size_c: num_words inside {[4:256]}
        rd_seq.num_words = 4;  // minimum legal value; we only check [0]

        // mem_block_read_sequence extends mem_base_sequence, runs on mem sequencer
        rd_seq.start(p_sequencer.m_mem_sequencer);

        // read_data[] is bit[63:0]. sw x3 stores 32-bit value -> lower word
        if (rd_seq.read_data[0][31:0] !== GOLDEN_VALUE) begin
            `uvm_error("FUNC_MEM_VSEQ", $sformatf("GOLDEN MISMATCH @ 0x%08h : got 0x%08h expected 0x%08h", OUTPUT_ADDR, rd_seq.read_data[0][31:0], GOLDEN_VALUE))
        end else begin
            `uvm_info("FUNC_MEM_VSEQ", $sformatf("GOLDEN MATCH: mem[0x%08h][31:0] = 0x%08h", OUTPUT_ADDR, rd_seq.read_data[0][31:0]), UVM_LOW)
        end
    endtask

endclass : vortex_functional_mem_vseq

`endif // VORTEX_FUNCTIONAL_MEM_VSEQ_SV