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
//   mem_block_read_sequence.start_addr  -> bit[VX_MEM_ADDR_WIDTH-1:0] = bit[25:0] WORD addr
//   mem_block_read_sequence.num_words   -> rand int, constraint {[1:64]}
//   mem_block_read_sequence.read_data[] -> bit[VX_MEM_DATA_WIDTH-1:0] = bit[511:0] per cache line
//   sw stores 32-bit -> result is in read_data[0][31:0] (byte offset 0 of the cache line)
//
// cfg is available from pre_body() - do NOT call super.body()
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_FUNCTIONAL_MEM_VSEQ_SV
`define VORTEX_FUNCTIONAL_MEM_VSEQ_SV

// This file is `included inside vortex_test_pkg.
// All imports (uvm_pkg, vortex_env_pkg, mem_agent_pkg, etc.) are provided
// by the enclosing package scope — do NOT re-import them here.

class vortex_functional_mem_vseq extends vortex_virtual_sequence;
    `uvm_object_utils(vortex_functional_mem_vseq)

    // FIX: start_addr is a WORD (cache-line = 64-byte) address, not a byte address.
    //      word_addr = byte_addr >> VX_MEM_OFFSET_BITS = 0x80001000 >> 6 = 0x2000040
    //      VX_MEM_ADDR_WIDTH = 26 bits; 0x2000040 fits (< 0x3FFFFFF).
    static const bit [vortex_config_pkg::VX_MEM_ADDR_WIDTH-1:0] OUTPUT_ADDR_WORD = 26'h200_0040;
    // Golden: program writes value 3 to byte address 0x80001000
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

        `uvm_info("FUNC_MEM_VSEQ", $sformatf("Reading output buffer @ word_addr=0x%08h via MEM agent", OUTPUT_ADDR_WORD), UVM_LOW)

        rd_seq = mem_block_read_sequence::type_id::create("rd_seq");

        // FIX: start_addr is bit[VX_MEM_ADDR_WIDTH-1:0] — a cache-line WORD address.
        // OUTPUT_ADDR_WORD = 0x80001000 >> 6 = 0x2000040.
        rd_seq.start_addr = OUTPUT_ADDR_WORD;

        // FIX: reasonable_size_c now allows {[1:64]} — use 1 (read one cache line).
        rd_seq.num_words = 1;

        // mem_block_read_sequence extends mem_base_sequence, runs on mem sequencer
        // Guard: m_mem_sequencer is null when mem_agent is PASSIVE.
        if (p_sequencer.m_axi_sequencer == null) begin
            `uvm_fatal("FUNC_MEM_VSEQ",
                "m_axi_sequencer is null — axi_agent must be ACTIVE to run this sequence.")
        end
        rd_seq.start(p_sequencer.m_axi_sequencer);

        // read_data[] is bit[63:0]. sw x3 stores 32-bit value -> lower word
        if (rd_seq.read_data[0][31:0] !== GOLDEN_VALUE) begin
            `uvm_error("FUNC_MEM_VSEQ", $sformatf("GOLDEN MISMATCH @ word_addr=0x%08h : got 0x%08h expected 0x%08h", OUTPUT_ADDR_WORD, rd_seq.read_data[0][31:0], GOLDEN_VALUE))
        end else begin
            `uvm_info("FUNC_MEM_VSEQ", $sformatf("GOLDEN MATCH: mem[word_addr=0x%08h][31:0] = 0x%08h", OUTPUT_ADDR_WORD, rd_seq.read_data[0][31:0]), UVM_LOW)
        end
    endtask

endclass : vortex_functional_mem_vseq

`endif // VORTEX_FUNCTIONAL_MEM_VSEQ_SV