////////////////////////////////////////////////////////////////////////////////
// File: rvvi_txn.svh
// Description: Phase-A / A1(c) RVVI transaction — one captured DUT beat
//   (commit writeback or LSU load writeback), published by rvvi_monitor on its
//   analysis port and consumed by lockstep_scoreboard (routed on rec.kind).
//   Thin by design: the payload is the existing lockstep_pkg::dut_retire_s
//   record — the scoreboard's aggregation/compare logic is unchanged.
// Author: Vortex UVM (Samuel) — Phase A1(c)
////////////////////////////////////////////////////////////////////////////////

`ifndef RVVI_TXN_SV
`define RVVI_TXN_SV

class rvvi_txn extends uvm_sequence_item;
    `uvm_object_utils(rvvi_txn)

    lockstep_pkg::dut_retire_s rec;

    function new(string name = "rvvi_txn");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("kind=%0d uuid=%0h wid=%0d sid=%0d pc=%0h rd=%0d tmask=%0h",
                         rec.kind, rec.uuid, rec.wid, rec.sid, rec.pc, rec.rd, rec.tmask);
    endfunction

endclass : rvvi_txn

`endif // RVVI_TXN_SV
