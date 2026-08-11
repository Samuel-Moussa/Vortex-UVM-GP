////////////////////////////////////////////////////////////////////////////////
// File: vx_cache_probe.sv
// Description: PASSIVE cache-event coverage probe (FW-6 / gap G1).
//
// WHY THIS EXISTS
//   The functional coverage model had NO cache-event coverage at any level. The
//   only cache-adjacent coverpoints (cp_id_route / cross_type_route in the
//   collector) sample memory ROUTING TAG BITS, not cache behaviour. So hit/miss,
//   eviction, writeback, MSHR pressure and flush were observed by nothing —
//   leaving the cache hierarchy, one of the likeliest homes for real bugs,
//   covered only by code coverage plus end-state/lockstep equivalence. A cache
//   with a latent corner-case bug can satisfy both of those.
//   See docs/COVERAGE_TRACEABILITY_MATRIX.md gap G1.
//
// WHERE IT BINDS
//   Into VX_cache_bank — the bank pipeline, which is where hit/miss is actually
//   resolved. One probe instance per bank per cache, so L1 I$/D$, L2 and L3 each
//   appear as SEPARATE covergroup instances in the UCDB hierarchy (per-config
//   sign-off is unaffected; instances are never blended).
//
// CONFIG-AWARENESS (the important property)
//   This probe is config-aware BY CONSTRUCTION rather than by `ifdef:
//   VX_cache_wrap.sv:160 instantiates VX_cache — and therefore VX_cache_bank —
//   ONLY when `PASSTHRU == 0`. With L2/L3 disabled those levels are pure bypass,
//   no bank exists, so `bind` creates NO instance and contributes NO bins. There
//   is no unreachable 0% block to waive, and no denominator inflation on the
//   default (L2/L3-off) build — the failure mode that made the TCU covergroup a
//   ~195-bin dead block before it was gated (vx_instr_probe.sv).
//   A belt-and-braces `ENABLE` parameter is provided so the bind site can also
//   suppress a level explicitly; it defaults to on.
//
// PASSIVE — NEVER A CHECKER
//   Observability only. Nothing here drives a signal or produces a pass/fail
//   verdict; the only checkers remain the end-state and lockstep comparisons.
////////////////////////////////////////////////////////////////////////////////

`ifndef VX_CACHE_PROBE_SV
`define VX_CACHE_PROBE_SV

module vx_cache_probe import VX_gpu_pkg::*; #(
    // Mirrored from the bound VX_cache_bank so the covergroup can label itself
    // and adapt its bins to the geometry actually elaborated. Never hardcoded:
    // the bind site passes the bank's own parameters straight through.
    parameter string INSTANCE_ID = "",
    parameter BANK_ID             = 0,
    parameter CACHE_SIZE          = 1024,
    parameter NUM_WAYS            = 1,
    parameter WRITEBACK           = 0,
    // Passed straight through from VX_cache_bank.sv:42. A cache built with
    // WRITE_ENABLE=0 has no write datapath at all (VX_cache_bank.sv:271 g_data_sel
    // and :590 g_mreq_queue are both generate-gated on it), so write and flush
    // activity is structurally impossible rather than merely unstimulated. In
    // this design the only such cache is the icache (VX_socket.sv:106 passes
    // .WRITE_ENABLE (0)); every other level is writable, so no bins are lost
    // where they are reachable.
    parameter WRITE_ENABLE        = 1,
    parameter ENABLE              = 1   // explicit suppression hook (see header)
) (
    input wire clk,
    input wire reset,

    // Bank pipeline stage-1 state (connected by bind from VX_cache_bank scope).
    // stage 1 is where the tag lookup result is known.
    input wire valid_st1,
    input wire is_creq_st1,     // a core request (vs fill/flush/replay traffic)
    input wire is_fill_st1,     // a fill returning from the next level
    input wire is_flush_st1,
    input wire is_replay_st1,   // an MSHR replay of a previously-missed request
    input wire is_hit_st1,
    input wire rw_st1,          // 0 = read, 1 = write
    input wire is_dirty_st1,    // victim dirty => this fill causes a writeback

    // Bank performance outputs (already exist on VX_cache_bank)
    input wire perf_read_miss,
    input wire perf_write_miss,
    input wire perf_mshr_stall
);

    // ---------------------------------------------------------------------
    // Sampled event decode. A "cache access" for coverage purposes is a core
    // request resolving in stage 1 — that is the point at which hit/miss is
    // meaningful. Fill / flush / replay are tracked as separate event kinds
    // rather than being folded into the hit/miss ratio, which would distort it.
    // ---------------------------------------------------------------------
    wire access_st1   = valid_st1 && is_creq_st1;
    wire fill_st1     = valid_st1 && is_fill_st1;
    wire flush_st1    = valid_st1 && is_flush_st1;
    wire writeback_ev = fill_st1  && is_dirty_st1;   // dirty victim evicted

    bit        s_is_write;
    bit        s_is_hit;
    bit        s_is_replay;
    bit        s_mshr_stall;
    bit [2:0]  s_event;   // see cp_event bins below

    localparam EV_NONE      = 3'd0;
    localparam EV_ACCESS    = 3'd1;
    localparam EV_FILL      = 3'd2;
    localparam EV_WRITEBACK = 3'd3;
    localparam EV_FLUSH     = 3'd4;

    // ---------------------------------------------------------------------
    // Covergroup. Bins are geometry-aware where it matters:
    //   - the writeback/dirty-eviction bins are only reachable on a WRITEBACK
    //     cache; on a write-through cache (WRITEBACK==0) a victim is never
    //     dirty, so those bins are ignore_bins rather than a permanent hole.
    //     This mirrors the project rule that exclusions must be structural and
    //     RTL-cited, never convenience.
    // ---------------------------------------------------------------------
    covergroup cache_event_cg @(posedge clk);
        option.per_instance = 1;
        option.name         = $sformatf("cache_event_cg_%s_b%0d", INSTANCE_ID, BANK_ID);

        // What kind of cache event occurred this cycle.
        cp_event: coverpoint s_event {
            bins access    = {EV_ACCESS};
            bins fill      = {EV_FILL};
            bins writeback = {EV_WRITEBACK};
            bins flush     = {EV_FLUSH};
            ignore_bins none = {EV_NONE};
            // A dirty victim cannot occur on a write-through cache: no line is
            // ever held modified, so the eviction never carries data back.
            // NOTE: the with_expr must reference `item` -- a purely constant
            // expression is rejected (vlog-13185). Including `item` makes this a
            // normal per-value filter that happens to be gated on the parameter.
            ignore_bins wb_unreachable = {EV_WRITEBACK}
                                         with (item == EV_WRITEBACK && WRITEBACK == 0);
            // A read-only cache is never flushed, for TWO independent structural
            // reasons -- either alone is sufficient:
            //   1. There is no dirty state to write back and no write datapath to
            //      invalidate through (WRITE_ENABLE=0 removes both generate blocks,
            //      VX_cache_bank.sv:271 and :590).
            //   2. MEM_REQ_FLAG_FLUSH has exactly ONE producer in the whole design,
            //      VX_lsu_slice.sv:73 (= req_is_fence), which drives the DCACHE
            //      path. VX_fetch.sv contains no flush logic whatsoever, so no
            //      flush request can ever be addressed to the icache.
            // Same `item`-referencing form as above (vlog-13185).
            ignore_bins flush_unreachable = {EV_FLUSH}
                                         with (item == EV_FLUSH && WRITE_ENABLE == 0);
        }

        // Hit vs miss on a core request — the primary cache-quality signal.
        cp_hit: coverpoint s_is_hit iff (s_event == EV_ACCESS) {
            bins hit  = {1};
            bins miss = {0};
        }

        // Read vs write access.
        cp_rw: coverpoint s_is_write iff (s_event == EV_ACCESS) {
            bins rd = {0};
            bins wr = {1};
            // No write can reach a cache built without a write datapath
            // (WRITE_ENABLE=0 -> VX_cache_bank.sv:271/:590 not generated). The
            // icache is fed only by VX_fetch, which issues reads exclusively.
            // NOTE: this also removes <wr,hit> and <wr,miss> from cross_rw_hit
            // automatically -- a cross is built from the coverpoint's REMAINING
            // bins, so the two cross bins must NOT be waived separately.
            ignore_bins wr_unreachable = {1} with (item == 1 && WRITE_ENABLE == 0);
        }

        // MSHR replay: a request that previously missed being re-driven. Exercises
        // the miss-tracking path rather than the plain hit path.
        cp_replay: coverpoint s_is_replay iff (s_event == EV_ACCESS) {
            bins normal = {0};
            bins replay = {1};
        }

        // MSHR back-pressure — the bank could not accept work. This is the
        // occupancy/pressure dimension that no previous covergroup observed.
        cp_mshr_stall: coverpoint s_mshr_stall {
            bins no_stall = {0};
            bins stall    = {1};
        }

        // The cross that actually matters: all four combinations of
        // {read,write} x {hit,miss} must be exercised at this cache level.
        cross_rw_hit: cross cp_rw, cp_hit;
    endgroup

    cache_event_cg cg_inst;

    initial begin
        if (ENABLE != 0)
            cg_inst = new();
    end

    always @(posedge clk) begin
        if (reset) begin
            s_event      <= EV_NONE;
            s_is_write   <= 1'b0;
            s_is_hit     <= 1'b0;
            s_is_replay  <= 1'b0;
            s_mshr_stall <= 1'b0;
        end else begin
            // Priority: a core access is the most informative event; the others
            // are background traffic and are reported when no access resolves.
            s_event      <= access_st1   ? EV_ACCESS    :
                            writeback_ev ? EV_WRITEBACK :
                            fill_st1     ? EV_FILL      :
                            flush_st1    ? EV_FLUSH     : EV_NONE;
            s_is_write   <= rw_st1;
            s_is_hit     <= is_hit_st1;
            s_is_replay  <= is_replay_st1;
            s_mshr_stall <= perf_mshr_stall;
        end
    end

endmodule

`endif // VX_CACHE_PROBE_SV
