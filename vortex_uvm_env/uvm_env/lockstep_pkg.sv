////////////////////////////////////////////////////////////////////////////////
// File: lockstep_pkg.sv
// Description: Phase-A / A0 lockstep DUT-retire capture channel.
//
//   RVVI-style per-instruction lockstep needs the DUT's retired-writeback
//   stream available to a UVM component. The commit probe (vx_commit_probe.sv)
//   lives in the RTL/module domain and is bound into every VX_commit; a UVM
//   scoreboard lives in the class domain. This package is the neutral hand-off:
//   a global (static, compilation-unit-lifetime) queue that the probe pushes
//   into and the lockstep scoreboard drains.
//
//   Kept deliberately RTL-macro-free: fields are stored in widened scalar types
//   (longint/int/byte), so nothing here depends on `SIMD_WIDTH / `XLEN / UUID
//   widths. The probe does the width/PC conversion at push time.
//
//   GATING: `lockstep_en` defaults 0. The probe sets it from `+LOCKSTEP` at
//   time 0. When 0, the probe never pushes and this channel is inert, so a
//   default (no-plusarg) run is byte-identical to before.
//
//   ONE record == ONE commit BEAT (a warp-instruction may span sop..eop beats,
//   lanes placed by `sid`). The scoreboard aggregates beats into one logical
//   retirement before comparing against SimX's single per-warp-instr record.
//
// Author: Vortex UVM (Samuel) — Phase A0
////////////////////////////////////////////////////////////////////////////////

`ifndef LOCKSTEP_PKG_SV
`define LOCKSTEP_PKG_SV

package lockstep_pkg;

    // One commit beat captured from commit_arb_if[i].data (writeback beats only).
    typedef struct {
        longint  unsigned uuid;    // per-warp-instruction id (cross-check key)
        int      unsigned cid;     // core id (A0: 0 — single core; A1: real)
        int      unsigned wid;     // warp id
        int      unsigned sid;     // SIMD-group index → lane base = sid*SIMD_WIDTH
        longint  unsigned pc;      // FULL byte PC (to_fullPC applied at push)
        int      unsigned rd;      // destination register
        byte     unsigned wb;      // writeback valid (always 1 here — we gate on it)
        int      unsigned tmask;   // per-SIMD-lane active mask for this beat
        byte     unsigned sop;     // start-of-packet
        byte     unsigned eop;     // end-of-packet
        longint  unsigned data[];  // this beat's SIMD lanes (size = SIMD_WIDTH)
    } dut_retire_s;

    // Global hand-off queue: probe (module domain) → scoreboard (class domain).
    dut_retire_s dut_retire_q[$];

    // Parallel LOAD-writeback channel (vx_lsu_probe.sv). Load *data* is not
    // observable at the commit-arb tap (OBS-002: commit `data` is stale for
    // loads — they finish via the async LSU response path). The LSU slice's
    // result_if DOES carry the final aligned per-lane load value, so a second
    // passive probe captures it here (same dut_retire_s shape, `sid`=LSU pid).
    // The scoreboard overlays this real data onto the matching commit retirement
    // (by uuid) so loads get per-instruction DATA-compared instead of skipped.
    dut_retire_s dut_load_q[$];

    // Set from +LOCKSTEP by the probe at time 0. Default 0 = channel inert.
    bit lockstep_en = 1'b0;

    // Negative-test hook (+LOCKSTEP_INJECT): flip one bit of the FIRST captured
    // wb lane exactly once, globally, to prove the comparator is non-vacuous
    // (must produce a field_mismatch at a known uuid/PC/lane). Default off.
    bit inject_en   = 1'b0;
    bit inject_done = 1'b0;

    // Push helper (kept as a function so the probe stays a one-liner call).
    function automatic void ls_push(dut_retire_s r);
        dut_retire_q.push_back(r);
    endfunction

    // Push helper for the LSU load-writeback channel.
    function automatic void ls_push_load(dut_retire_s r);
        dut_load_q.push_back(r);
    endfunction

    // Drain helper for the scoreboard (returns and clears both queues).
    function automatic void ls_reset();
        dut_retire_q.delete();
        dut_load_q.delete();
    endfunction

endpackage : lockstep_pkg

`endif // LOCKSTEP_PKG_SV
