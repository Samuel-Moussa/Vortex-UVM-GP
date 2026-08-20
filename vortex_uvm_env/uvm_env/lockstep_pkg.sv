////////////////////////////////////////////////////////////////////////////////
// File: lockstep_pkg.sv
// Description: Phase-A lockstep record type + module-domain gating flags.
//
//   RVVI-style per-instruction lockstep needs the DUT's retired-writeback
//   stream available to a UVM component. The probes (vx_commit_probe.sv,
//   vx_lsu_probe.sv) live in the RTL/module domain and are bound into every
//   VX_commit / VX_lsu_slice; the lockstep scoreboard lives in the class
//   domain. This package holds the SHARED RECORD TYPE and the plusarg gate
//   flags. The hand-off itself is A1(c)'s rvvi_if + rvvi_monitor + analysis
//   port (see rvvi_if.sv) — the former global package queues are gone.
//
//   Kept deliberately RTL-macro-free: fields are stored in widened scalar types
//   (longint/int/byte), so nothing here depends on `SIMD_WIDTH / `XLEN / UUID
//   widths. The probe does the width/PC conversion at push time.
//
//   GATING: `lockstep_en` defaults 0. The probe sets it from `+LOCKSTEP` at
//   time 0. When 0, the probes never push and the whole channel is inert, so a
//   default (no-plusarg) run is byte-identical to before.
//
//   ONE record == ONE commit BEAT (a warp-instruction may span sop..eop beats,
//   lanes placed by `sid`). The scoreboard aggregates beats into one logical
//   retirement before comparing against SimX's single per-warp-instr record.
//
// Author: Vortex UVM (Samuel) — Phase A0 (queues removed in A1(c))
////////////////////////////////////////////////////////////////////////////////

`ifndef LOCKSTEP_PKG_SV
`define LOCKSTEP_PKG_SV

package lockstep_pkg;

    // Record source, carried in dut_retire_s.kind so ONE rvvi_if type / ONE
    // analysis stream serves both probes; the scoreboard routes on it.
    //   KIND_COMMIT — commit-arb writeback beat (vx_commit_probe)
    //   KIND_LOAD   — LSU load-writeback beat  (vx_lsu_probe, OBS-002 overlay)
    localparam byte unsigned KIND_COMMIT = 8'd0;
    localparam byte unsigned KIND_LOAD   = 8'd1;

    // One captured beat (commit_arb_if[i].data or lsu result_if.data).
    typedef struct {
        byte     unsigned kind;    // KIND_COMMIT / KIND_LOAD (routing key)
        longint  unsigned uuid;    // per-warp-instruction id (cross-check key)
        int      unsigned cid;     // core id (superseded: SB derives it from uuid)
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

    // Set from +LOCKSTEP by the probe at time 0. Default 0 = channel inert.
    bit lockstep_en = 1'b0;

    // Negative-test hook (+LOCKSTEP_INJECT): flip one bit of the FIRST captured
    // wb lane exactly once, globally, to prove the comparator is non-vacuous
    // (must produce a field_mismatch at a known uuid/PC/lane). Default off.
    bit inject_en   = 1'b0;
    bit inject_done = 1'b0;

endpackage : lockstep_pkg

`endif // LOCKSTEP_PKG_SV
