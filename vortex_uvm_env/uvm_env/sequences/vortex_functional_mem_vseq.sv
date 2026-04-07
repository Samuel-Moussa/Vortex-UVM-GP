////////////////////////////////////////////////////////////////////////////////
// File: vortex_functional_mem_vseq.sv
// Description: Functional Memory Virtual Sequence
//
// Waits for EBREAK (DUT execution complete) then reads the result directly
// from mem_model and compares against the golden value.
//
// Golden: program_with_store.hex writes 0x00000003 to byte address 0x80001000
//
// WHY mem_model direct read (not agent sequence):
//   In MEM mode, mem_agent is PASSIVE — m_mem_sequencer is null.
//   In AXI mode, axi_sequencer expects axi_transaction, not mem_transaction.
//   mem_model IS the ground truth — TB_TOP writes every DUT store into it.
//   Reading mem_model directly after EBREAK is correct and interface-agnostic.
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_FUNCTIONAL_MEM_VSEQ_SV
`define VORTEX_FUNCTIONAL_MEM_VSEQ_SV

// This file is `included inside vortex_test_pkg — all imports are provided
// by the enclosing package scope. Do NOT add standalone import statements.

class vortex_functional_mem_vseq extends vortex_virtual_sequence;
    `uvm_object_utils(vortex_functional_mem_vseq)

    // Byte address of the result: program writes 0x3 to 0x80001000
    static const bit [63:0] OUTPUT_BYTE_ADDR = 64'h8000_1000;
    // Golden value: program computes 1+2=3 and stores it
    static const bit [31:0] GOLDEN_VALUE     = 32'h0000_0003;

    // Number of iterations (referenced by functional_memory_test banner)
    int unsigned num_iterations = 1;

    function new(string name = "vortex_functional_mem_vseq");
        super.new(name);
    endfunction

    //==========================================================================
    // body()
    // pre_body() already populated cfg from p_sequencer.cfg.
    // We wait for EBREAK then read mem_model directly.
    //==========================================================================
    virtual task body();
        mem_model  m_mem;
        bit [511:0] cache_line;
        bit [31:0]  result;
        bit [63:0]  cache_line_byte_addr;

        // Align to cache-line boundary (64-byte = VX_MEM_LINE_SIZE)
        // 0x80001000 is already 64-byte aligned (0x80001000 % 64 == 0)
        cache_line_byte_addr = OUTPUT_BYTE_ADDR &
                               ~(64'(vortex_config_pkg::VX_MEM_LINE_SIZE) - 1);

        // ── Wait for DUT to finish ───────────────────────────────────────────
        // cfg.ebreak_event is triggered by vortex_scoreboard.write_status()
        // the moment the status_agent monitor sees ebreak_detected == 1.
        // This unblocks at exactly the cycle EBREAK fires — no polling.
        `uvm_info("FUNC_MEM_VSEQ",
            $sformatf("Waiting for EBREAK (timeout=%0d cycles)...",
                cfg.test_timeout_cycles), UVM_MEDIUM)
        wait_for_execution_complete();
        `uvm_info("FUNC_MEM_VSEQ", "EBREAK received — reading result from mem_model", UVM_LOW)

        // ── Read result from mem_model ───────────────────────────────────────
        if (!uvm_config_db #(mem_model)::get(null, "*", "mem_model", m_mem)) begin
            `uvm_fatal("FUNC_MEM_VSEQ",
                "mem_model not found in config_db — was it set by TB_TOP?")
        end

        cache_line = m_mem.read_line(cache_line_byte_addr);

        // The sw instruction stores a 32-bit word.
        // Byte offset within cache line = OUTPUT_BYTE_ADDR % VX_MEM_LINE_SIZE = 0
        // so result is in bits [31:0] of the cache line.
        result = cache_line[31:0];

        `uvm_info("FUNC_MEM_VSEQ",
            $sformatf("mem_model[0x%016h] cache_line[31:0] = 0x%08h",
                cache_line_byte_addr, result), UVM_LOW)

        // ── Golden check ─────────────────────────────────────────────────────
        if (result !== GOLDEN_VALUE) begin
            `uvm_error("FUNC_MEM_VSEQ",
                $sformatf("GOLDEN MISMATCH @ 0x%016h : got 0x%08h expected 0x%08h",
                    OUTPUT_BYTE_ADDR, result, GOLDEN_VALUE))
        end else begin
            `uvm_info("FUNC_MEM_VSEQ",
                $sformatf("GOLDEN MATCH ✓  mem_model[0x%016h] = 0x%08h",
                    OUTPUT_BYTE_ADDR, result), UVM_LOW)
        end
    endtask

endclass : vortex_functional_mem_vseq

`endif // VORTEX_FUNCTIONAL_MEM_VSEQ_SV