////////////////////////////////////////////////////////////////////////////////
// File: vortex_functional_mem_vseq.sv
// Description: Functional Memory Virtual Sequence
//
// Reads the output buffer written by program_with_store.hex via the
// custom MEM agent and compares against the golden value.
//
// Requires: program_with_store.hex (sw x3, 0(t3) writes 3 to 0x80001000)
//
// Key facts from actual sequence files:
//   mem_block_read_sequence.start_addr  → bit[31:0], must be [2:0]==0
//   mem_block_read_sequence.num_words   → int, constraint {[4:256]}
//   mem_block_read_sequence.read_data[] → bit[63:0] per word
//   sw stores 32-bit → result is in read_data[0][31:0]
//
// cfg is available from pre_body() — do NOT call super.body()
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_FUNCTIONAL_MEM_VSEQ_SV
`define VORTEX_FUNCTIONAL_MEM_VSEQ_SV

class vortex_functional_mem_vseq extends vortex_virtual_sequence;
    `uvm_object_utils(vortex_functional_mem_vseq)

    // ── parameters ──────────────────────────────────────────────────────────
    // 0x80001000[2:0] == 0  → satisfies start_addr 8-byte-aligned constraint
    static const bit [31:0] OUTPUT_ADDR  = 32'h8000_1000;
    static const bit [31:0] GOLDEN_VALUE = 32'h0000_0003;  // 1 + 2 = 3

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

        `uvm_info("FUNC_MEM_VSEQ",
            $sformatf("Reading output buffer @ 0x%08h via MEM agent", OUTPUT_ADDR),
            UVM_LOW)

        rd_seq = mem_block_read_sequence::type_id::create("rd_seq");

        // start_addr: 0x80001000 — [2:0]==0 ✓  satisfies addr_aligned_c
        rd_seq.start_addr = OUTPUT_ADDR;

        // num_words: must be >= 4 (constraint reasonable_size_c {[4:256]})
        // We only care about word [0], but must meet the minimum.
        rd_seq.num_words = 4;

        rd_seq.start(p_sequencer.m_mem_sequencer);

        // read_data[] is bit[63:0].  sw x3 stores 32 bits → lower half.
        if (rd_seq.read_data[0][31:0] !== GOLDEN_VALUE) begin
            `uvm_error("FUNC_MEM_VSEQ",
                $sformatf("GOLDEN MISMATCH @ 0x%08h : got 0x%08h, expected 0x%08h",
                           OUTPUT_ADDR,
                           rd_seq.read_data[0][31:0],
                           GOLDEN_VALUE))
        end else begin
            `uvm_info("FUNC_MEM_VSEQ",
                $sformatf("GOLDEN MATCH ✓  mem[0x%08h][31:0] = 0x%08h",
                           OUTPUT_ADDR, rd_seq.read_data[0][31:0]), UVM_LOW)
        end
    endtask

endclass : vortex_functional_mem_vseq

`endif // VORTEX_FUNCTIONAL_MEM_VSEQ_SV
