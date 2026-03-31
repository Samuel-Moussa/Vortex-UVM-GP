////////////////////////////////////////////////////////////////////////////////
// File: vortex_axi_mem_vseq.sv
// Description: AXI Memory Virtual Sequence
//
// Drives a burst read on the AXI AR channel and verifies the
// protocol handshake completes without error.
//
// Key facts from actual axi_sequences.sv:
//   axi_burst_read_seq.addr      → rand bit[31:0]     ✓ canonical name
//   axi_burst_read_seq.num_beats → rand int            ✓ canonical name
//   axi_burst_read_seq has NO read_data field
//   (UVM rule: "Response data NOT available in sequence — use monitor")
//   The sequence fires uvm_error internally on protocol violations.
//
// cfg is available from pre_body() — do NOT call super.body()
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_AXI_MEM_VSEQ_SV
`define VORTEX_AXI_MEM_VSEQ_SV

class vortex_axi_mem_vseq extends vortex_virtual_sequence;
    `uvm_object_utils(vortex_axi_mem_vseq)

    // Read from instruction region — always populated after load_program()
    bit [31:0]   read_addr = 32'h8000_0000;
    int unsigned num_beats = 16;  // 16 × 8 bytes = 128 bytes (2 cache lines)

    function new(string name = "vortex_axi_mem_vseq");
        super.new(name);
    endfunction

    //==========================================================================
    // body()
    // cfg already populated by pre_body() from p_sequencer.cfg.
    // Do NOT call super.body().
    //==========================================================================
    virtual task body();
        axi_burst_read_seq  rd_seq;
        uvm_report_server   rs;
        int                 err_before;

        // Snapshot error count before issuing the burst so we can detect
        // any NEW protocol errors introduced by this specific transaction.
        rs         = uvm_report_server::get_server();
        err_before = rs.get_severity_count(UVM_ERROR);

        `uvm_info("AXI_MEM_VSEQ",
            $sformatf("AXI burst read: %0d beats from 0x%08h",
                       num_beats, read_addr), UVM_LOW)

        // ── confirmed field names from actual axi_sequences.sv ─────────────
        rd_seq           = axi_burst_read_seq::type_id::create("rd_seq");
        rd_seq.addr      = read_addr;    // .addr       ✓
        rd_seq.num_beats = num_beats;    // .num_beats  ✓
        rd_seq.start(p_sequencer.m_axi_sequencer);

        // Protocol check: no new errors during the burst.
        // Read data is captured by axi_monitor, not the sequence (UVM rule).
        if (rs.get_severity_count(UVM_ERROR) > err_before) begin
            `uvm_error("AXI_MEM_VSEQ",
                "AXI burst read raised protocol error — check axi_monitor output")
        end else begin
            `uvm_info("AXI_MEM_VSEQ",
                $sformatf("AXI burst read PASSED ✓  %0d beats, no protocol errors",
                           num_beats), UVM_LOW)
        end
    endtask

endclass : vortex_axi_mem_vseq

`endif // VORTEX_AXI_MEM_VSEQ_SV
