// =============================================================================
// vx_sched_probe.sv  —  Warp/scheduler-state functional coverage (CG2)
//
// Plan item: CG2 "warp-state coverage" — active/stalled warp counts, SIMT
// split/join divergence, reconvergence + divergence-stack depth, barrier
// hold/release, thread-mask control (tmc), and wspawn. Black-box / observe-only.
//
// HOW IT BINDS (passive, no DUT edits):
//   bind VX_schedule vx_sched_probe u_sched_probe ( ... );
// One probe per VX_schedule instance (i.e. per core). It reads VX_schedule's
// ports (warp_ctl_if, schedule_if) and a few internal scheduler registers
// (active_warps, stalled_warps, barrier_ctrs, join_* wires). It NEVER drives
// anything — every interface port is a generic (no-modport) view used read-only.
//
// RELATIONSHIP TO vx_instr_probe (avoids double-counting):
//   The instruction probe owns per-CLASS thread occupancy (cp_active_threads,
//   sampled at dispatch). This probe owns per-WARP occupancy + all warp-level
//   scheduler state. The bare per-warp occupancy coverpoint here is weight=0
//   (feeds the wid×occupancy cross only), so the occupancy histogram is counted
//   once, in the instruction probe. Everything CG2 adds is occupancy/divergence
//   conditioned on scheduler state, which the dispatch probe cannot see.
//
// SIGNAL PROVENANCE (all confirmed in VX_schedule scope @ 7a52ee5):
//   active_warps / stalled_warps        : internal regs (warp masks)
//   schedule_if.data.{tmask,wid}         : scheduler output payload
//   warp_ctl_if.split.{valid,is_dvg,then_tmask} : split events
//   warp_ctl_if.dvstack_ptr              : divergence-stack depth (push/pop)
//   join_valid/join_is_dvg/join_is_else/join_tmask : internal join wires
//   warp_ctl_if.barrier.{valid,id,is_global,is_noop,size_m1} + barrier_ctrs
//   warp_ctl_if.tmc.{valid,tmask}, warp_ctl_if.wspawn.{valid,wmask}
//
// PARAM NOTE: like vx_instr_probe, this compiles in the UVM vlog pass without
// VX_define.vh, so it cannot use `NUM_WARPS / `NUM_THREADS macros. It takes the
// package localparams via `import VX_gpu_pkg::*` for PORT WIDTHS, and derives
// all bin ranges from $bits()/$size() of the connected signals so the bins are
// always correct regardless of config. The four package identifiers used for
// port widths — NUM_WARPS, NUM_THREADS, NUM_BARRIERS, NW_WIDTH — are the only
// thing to confirm on first compile (NW_WIDTH is already used package-plain in
// VX_warp_ctl_if.sv; the other three are expected to mirror it).
// =============================================================================

// Width macros come from the compile line (+define+NUM_WARPS=N, etc., present
// in the UVM vlog invocation). Fallbacks keep the file elaboratable if absent.
// NW_WIDTH / DV_STACK_SIZEW / NB_WIDTH remain package identifiers (valid in the
// UVM pass via import VX_gpu_pkg::*); only the NUM_* counts need macro form.
`ifndef NUM_WARPS
  `define NUM_WARPS 4
`endif
`ifndef NUM_THREADS
  `define NUM_THREADS 4
`endif
`ifndef NUM_BARRIERS
  `define NUM_BARRIERS 4
`endif

module vx_sched_probe import VX_gpu_pkg::*; #(
    parameter CORE_ID = 0
) (
    input wire clk,
    input wire reset,

    // Observe-only interface views (generic — no modport, never driven)
    VX_warp_ctl_if  warp_ctl_if,
    VX_schedule_if  schedule_if,

    // Internal scheduler state (connected by bind from VX_schedule's scope)
    input wire [`NUM_WARPS-1:0]                  active_warps,
    input wire [`NUM_WARPS-1:0]                  stalled_warps,
    input wire [`NUM_BARRIERS-1:0][NW_WIDTH-1:0] barrier_ctrs,

    // Internal join (reconvergence) event wires
    input wire                  join_valid,
    input wire                  join_is_dvg,
    input wire                  join_is_else,
    input wire [`NUM_THREADS-1:0] join_tmask
);

    // ---- Config-derived widths (robust, no macros) --------------------------
    localparam int NT = $bits(schedule_if.data.tmask);   // threads per warp
    localparam int NW = $bits(active_warps);             // warps per core

    // =========================================================================
    // 1) SCHEDULER STATE — sampled when a warp actually issues (schedule fire)
    //    active-warp-count, stalled-warp-count, and per-warp occupancy (as a
    //    cross only; the bare occupancy coverpoint is weight=0 to avoid
    //    double-counting the instruction probe's per-class occupancy).
    // =========================================================================
    covergroup sched_state_cg with function sample(
        int                     active_cnt,
        int                     stalled_cnt,
        logic [NW_WIDTH-1:0]    wid,
        int                     occ
    );
        option.per_instance = 1;
        option.name = "warp_sched_state_cg";

        cp_active_warps : coverpoint active_cnt {
            bins none      = { 0 };          // scheduler idle (no resident warp)
            bins one       = { 1 };
            bins some[]    = { [2 : NW-1] };
            bins all       = { NW };
        }

        cp_stalled_warps : coverpoint stalled_cnt {
            bins none      = { 0 };
            bins some[]    = { [1 : NW-1] };
            bins all       = { NW };         // every warp stalled (barrier/branch)
        }

        cp_sched_wid : coverpoint wid;       // which warp issued (auto-binned)

        // Bare per-warp occupancy: weight 0 — exists only to feed the cross.
        // The authoritative occupancy histogram is the instruction probe's
        // per-class cp_active_threads.
        cp_occ : coverpoint occ {
            bins one       = { 1 };
            bins partial[] = { [2 : NT-1] };
            bins full      = { NT };
            option.weight  = 0;
        }

        // Per-warp thread-mask occupancy (the dimension you asked for).
        cross_wid_occ : cross cp_sched_wid, cp_occ;
    endgroup

    // =========================================================================
    // 2) DIVERGENCE (split) — sampled on a split control event
    // =========================================================================
    covergroup divergence_cg with function sample(
        logic                       is_dvg,
        int                         then_occ,
        logic [DV_STACK_SIZEW-1:0]  depth
    );
        option.per_instance = 1;
        option.name = "warp_divergence_cg";

        cp_is_dvg : coverpoint is_dvg {
            bins uniform   = { 1'b0 };       // split with no actual divergence
            bins divergent = { 1'b1 };       // real thread divergence
        }

        // Threads taking the 'then' path at the split.
        cp_then_occ : coverpoint then_occ {
            bins one       = { 1 };
            bins partial[] = { [2 : NT-1] };
            bins full      = { NT };
        }

        // Divergence-stack depth at the split (nesting level). Auto-binned.
        cp_split_depth : coverpoint depth;

        cross_dvg_depth : cross cp_is_dvg, cp_split_depth;
    endgroup

    // =========================================================================
    // 3) RECONVERGENCE (join) — sampled on a join event
    // =========================================================================
    covergroup reconverge_cg with function sample(
        logic                       is_dvg,
        logic                       is_else,
        int                         join_occ,
        logic [DV_STACK_SIZEW-1:0]  depth
    );
        option.per_instance = 1;
        option.name = "warp_reconverge_cg";

        cp_join_dvg  : coverpoint is_dvg {
            bins uniform   = { 1'b0 };
            bins divergent = { 1'b1 };
        }
        cp_join_else : coverpoint is_else {
            bins then_path = { 1'b0 };
            bins else_path = { 1'b1 };       // reconverge into the else side
        }
        cp_join_occ  : coverpoint join_occ {
            bins one       = { 1 };
            bins partial[] = { [2 : NT-1] };
            bins full      = { NT };
        }
        cp_join_depth : coverpoint depth;    // stack depth at reconverge

        cross_join : cross cp_join_dvg, cp_join_else;
    endgroup

    // =========================================================================
    // 4) BARRIER — hold vs release, id, scope, participant count
    // =========================================================================
    covergroup barrier_cg with function sample(
        logic [NB_WIDTH-1:0]    bar_id,
        logic                   is_global,
        int                     size_m1,
        logic                   is_release
    );
        option.per_instance = 1;
        option.name = "warp_barrier_cg";

        cp_bar_id    : coverpoint bar_id;            // which barrier (auto)
        cp_bar_scope : coverpoint is_global {
            bins local_bar  = { 1'b0 };
            bins global_bar = { 1'b1 };
        }
        // Participating warps minus 1. Range is [0 : NUM_WARPS-1]; auto-bins
        // the full NW_WIDTH bit-range creates structurally-unreachable bins.
        cp_bar_size : coverpoint size_m1 {
            bins size[]  = { [0 : `NUM_WARPS-1] };
        }
        cp_bar_event : coverpoint is_release {
            bins hold = { 1'b0 };                    // arrival, not last
            bins rel  = { 1'b1 };                    // last arrival → unlock ('release' is reserved)
        }

        cross_event_scope : cross cp_bar_event, cp_bar_scope;
    endgroup

    // =========================================================================
    // 5) TMC (thread-mask control) — incl. warp deactivation (tmask==0)
    // =========================================================================
    covergroup tmc_cg with function sample(int tmc_occ);
        option.per_instance = 1;
        option.name = "warp_tmc_cg";

        cp_tmc_occ : coverpoint tmc_occ {
            bins deactivate = { 0 };                 // tmask==0 disables the warp
            bins one        = { 1 };
            bins partial[]  = { [2 : NT-1] };
            bins full       = { NT };
        }
    endgroup

    // =========================================================================
    // 6) WSPAWN — number of warps spawned in one control op
    // =========================================================================
    covergroup wspawn_cg with function sample(int spawn_cnt);
        option.per_instance = 1;
        option.name = "warp_wspawn_cg";

        cp_spawn_cnt : coverpoint spawn_cnt {
            bins one     = { 1 };
            bins some[]  = { [2 : NW-1] };
            bins all     = { NW };
        }
    endgroup

    // ---- Construct ----------------------------------------------------------
    sched_state_cg  u_sched_state = new();
    divergence_cg   u_divergence  = new();
    reconverge_cg   u_reconverge  = new();
    barrier_cg      u_barrier     = new();
    tmc_cg          u_tmc         = new();
    wspawn_cg       u_wspawn      = new();

    // =========================================================================
    // Sampling — each covergroup on its own real event, never vacuously.
    // =========================================================================

    // 1) Scheduler state: when a warp actually issues out of the scheduler.
    always @(posedge clk) begin
        if (!reset && schedule_if.valid && schedule_if.ready) begin
            u_sched_state.sample(
                $countones(active_warps),
                $countones(stalled_warps),
                schedule_if.data.wid,
                $countones(schedule_if.data.tmask)
            );
        end
    end

    // 2) Split (divergence) control event.
    always @(posedge clk) begin
        if (!reset && warp_ctl_if.valid && warp_ctl_if.split.valid) begin
            u_divergence.sample(
                warp_ctl_if.split.is_dvg,
                $countones(warp_ctl_if.split.then_tmask),
                warp_ctl_if.dvstack_ptr
            );
        end
    end

    // 3) Join (reconvergence) event — internal wire, asserted on pop.
    always @(posedge clk) begin
        if (!reset && join_valid) begin
            u_reconverge.sample(
                join_is_dvg,
                join_is_else,
                $countones(join_tmask),
                warp_ctl_if.dvstack_ptr
            );
        end
    end

    // 4) Barrier arrival (skip no-ops). Release predicate mirrors the RTL
    //    exactly: ctr for this barrier id has reached size_m1 on this arrival.
    always @(posedge clk) begin
        if (!reset && warp_ctl_if.valid && warp_ctl_if.barrier.valid
                   && !warp_ctl_if.barrier.is_noop) begin
            u_barrier.sample(
                warp_ctl_if.barrier.id,
                warp_ctl_if.barrier.is_global,
                int'(warp_ctl_if.barrier.size_m1),
                (barrier_ctrs[warp_ctl_if.barrier.id] == warp_ctl_if.barrier.size_m1)
            );
        end
    end

    // 5) TMC control.
    always @(posedge clk) begin
        if (!reset && warp_ctl_if.valid && warp_ctl_if.tmc.valid) begin
            u_tmc.sample($countones(warp_ctl_if.tmc.tmask));
        end
    end

    // 6) WSPAWN control.
    always @(posedge clk) begin
        if (!reset && warp_ctl_if.valid && warp_ctl_if.wspawn.valid) begin
            u_wspawn.sample($countones(warp_ctl_if.wspawn.wmask));
        end
    end

endmodule