// =============================================================================
// vx_instr_probe.sv  —  White-box architectural instruction coverage (ARCH-COV)
//
// Plan item: instr_class_cg (Stage-2 functional coverage, design-intent layer).
// Samples decoded instructions at the DISPATCH stage — the first point where an
// instruction has been classified to an execution unit. This is GPU-intent
// coverage (instruction mix, divergence), NOT bus-traffic coverage.
//
// HOW IT BINDS (passive, no DUT edits):
//   bind VX_dispatch vx_instr_probe #(...) u_instr_probe (.*);
//   VX_dispatch owns `dispatch_if [NUM_EX_UNITS]` as its .master output array
//   (instantiated in VX_issue_slice.sv:83). The probe reads those interfaces;
//   it NEVER drives them (the real consumer drives .ready).
//
// KEY ENCODING FACTS (confirmed from RTL, not assumed):
//   - ex_type (instruction CLASS) is the ARRAY INDEX, not a payload field:
//       EX_ALU=0, EX_LSU=1, EX_SFU=2, EX_FPU=3, EX_TCU=4   (VX_gpu_pkg.sv:113-119)
//     dispatch_if[i].valid means "an EX_unit-i instruction issued this cycle".
//   - op_type (4-bit SUB-opcode within the class) IS a payload field:
//       dispatch_t.op_type  (VX_gpu_pkg.sv:638)
//       ALU ops: INST_ALU_*  (:184+),  LSU ops: INST_LSU_* (:317+)
//       SFU ops: INST_SFU_*  (:374+) — TMC/WSPAWN/SPLIT/JOIN/BAR/PRED/CSR*
//   - tmask width = `SIMD_WIDTH (dispatch_t.tmask, :636) → divergence signal
//   - wis = warp-in-schedule index (dispatch_t.wis, :634)
//
// SAMPLING: one .sample() per (dispatch_if[i].valid && dispatch_if[i].ready),
//   i.e. per instruction actually accepted into a unit. No vacuous samples.
//
// -----------------------------------------------------------------------------
// COVERAGE STRUCTURE  (revised — per-class covergroup variants)
// -----------------------------------------------------------------------------
// Previous revision used ONE covergroup type carrying every class's op
// coverpoint, gated by `iff (ex_class==N)`. That meant each of the 5 bound
// instances dragged in ~4 op-coverpoints it could never hit, plus a 5-way
// `cp_class` that could only ever reach 1 bin. Those structurally-unreachable
// bins inflated the denominator and pinned the reported % artificially low
// (e.g. the ALU instance capped at 40% despite hitting 12/14 real ALU ops).
//
// This revision uses ONE covergroup TYPE PER CLASS. Each instance carries only
// the coverpoints that can actually fire for its unit. Nothing reachable is
// removed — only impossible-per-instance bins are gone. Genuine holes (e.g.
// czeq/czne Zicond ops, or an LSU/SFU class a given program never exercises)
// remain fully visible and simply read ZERO until a program exercises them.
//
//   - cp_class       : DROPPED. It was a per-instance constant; the class is now
//                      encoded in the instance name (instr_class_cg_alu, _lsu…),
//                      and "did this class issue" is visible from its coverpoints.
//   - cross_class_threads : DROPPED. Degenerated to cp_active_threads per
//                      instance (class is constant), which is still present.
//   - cross_sfu_threads   : KEPT (SFU only). Genuinely meaningful: do the
//                      divergence-control ops fire under partial masks?
//
// Coverage lands in the SAME merged UCDB as everything else — a covergroup in a
// bound RTL module merges identically to the collector's covergroups.
// =============================================================================

// Note: no `include of VX_define.vh — this module compiles in the UVM vlog pass
// which lacks the RTL incdir. All needed constants come from VX_gpu_pkg (imported
// below) and from the dispatch_if field widths. No RTL macros are referenced.

module vx_instr_probe import VX_gpu_pkg::*; #(
    parameter CORE_ID = 0
) (
    input wire clk,
    input wire reset,
    VX_dispatch_if.slave dispatch_if [NUM_EX_UNITS]   // OBSERVE ONLY — never drive .ready
);

    // EX-unit class indices. These mirror the dispatch array index the original
    // probe already relied on (it binned cp_class as {0..4} and constructed with
    // new(gi)). Kept as explicit local params — proven mapping, no dependency on
    // package enum identifier spelling.
    localparam int C_ALU = 0;
    localparam int C_LSU = 1;
    localparam int C_SFU = 2;
    localparam int C_FPU = 3;
    localparam int C_TCU = 4;

    // SIMD width WITHOUT the `SIMD_WIDTH macro: this module compiles in the UVM
    // vlog pass, which does NOT include VX_config.vh, so the macro is undefined
    // here. Derive the width from the actual tmask field of dispatch_t instead —
    // always correct, never macro-dependent.
    localparam int SIMD_W = $bits(dispatch_if[0].data.tmask);

    // =========================================================================
    // Per-class covergroup TYPES. Each carries only the coverpoints reachable
    // for its EX unit. The shared cp_active_threads / cp_warp definitions are
    // repeated rather than factored out, so each type is self-contained and the
    // sample signature is explicit per class.
    //
    // NOTE on divergence bins: cp_active_threads edges are written for the actual
    // SIMD width (derived as SIMD_W). `partial` spans [2 : SIMD_W-1]; if SIMD_W
    // is small (<=2) that range may be empty, which is correct.
    // =========================================================================

    // ---- ALU ----------------------------------------------------------------
    covergroup alu_class_cg with function sample(
        logic [INST_ALU_BITS-1:0] op_type,
        int                       active_thr,
        logic [ISSUE_WIS_W-1:0]   wis
    );
        option.per_instance = 1;
        option.name         = "instr_class_cg_alu";

        cp_alu_op : coverpoint op_type {
            bins add   = { INST_ALU_ADD };
            bins sub   = { INST_ALU_SUB };
            bins and_  = { INST_ALU_AND };
            bins or_   = { INST_ALU_OR  };
            bins xor_  = { INST_ALU_XOR };
            bins sll   = { INST_ALU_SLL };
            bins srl   = { INST_ALU_SRL };
            bins sra   = { INST_ALU_SRA };
            bins slt   = { INST_ALU_SLT };
            bins sltu  = { INST_ALU_SLTU };
            bins lui   = { INST_ALU_LUI };
            bins auipc = { INST_ALU_AUIPC };
            bins czeq  = { INST_ALU_CZEQ };   // Zicond — ZERO until a Zicond build runs
            bins czne  = { INST_ALU_CZNE };   // Zicond — ZERO until a Zicond build runs
        }

        cp_active_threads : coverpoint active_thr {
            bins one_divergent = { 1 };
            bins partial[]     = { [2 : SIMD_W-1] };
            bins uniform       = { SIMD_W };
        }

        cp_warp : coverpoint wis;
    endgroup

    // ---- LSU ----------------------------------------------------------------
    covergroup lsu_class_cg with function sample(
        logic [INST_ALU_BITS-1:0] op_type,   // op_type is one shared-width field across classes
        int                       active_thr,
        logic [ISSUE_WIS_W-1:0]   wis
    );
        option.per_instance = 1;
        option.name         = "instr_class_cg_lsu";

        cp_lsu_op : coverpoint op_type {
            bins lb = { INST_LSU_LB };
            bins lh = { INST_LSU_LH };
            bins lw = { INST_LSU_LW };
            bins ld = { INST_LSU_LD };
            bins sb = { INST_LSU_SB };
            bins sh = { INST_LSU_SH };
            bins sw = { INST_LSU_SW };
            bins sd = { INST_LSU_SD };
        }

        cp_active_threads : coverpoint active_thr {
            bins one_divergent = { 1 };
            bins partial[]     = { [2 : SIMD_W-1] };
            bins uniform       = { SIMD_W };
        }

        cp_warp : coverpoint wis;
    endgroup

    // ---- SFU (richest: SIMT control + barriers + CSR) -----------------------
    covergroup sfu_class_cg with function sample(
        logic [INST_ALU_BITS-1:0] op_type,
        int                       active_thr,
        logic [ISSUE_WIS_W-1:0]   wis
    );
        option.per_instance = 1;
        option.name         = "instr_class_cg_sfu";

        cp_sfu_op : coverpoint op_type {
            bins tmc    = { INST_SFU_TMC };      // thread-mask control
            bins wspawn = { INST_SFU_WSPAWN };   // spawn warps
            bins split  = { INST_SFU_SPLIT };    // divergence split
            bins join_  = { INST_SFU_JOIN };     // reconverge
            bins bar    = { INST_SFU_BAR };      // barrier
            bins pred   = { INST_SFU_PRED };     // predicate
            bins csrrw  = { INST_SFU_CSRRW };
            bins csrrs  = { INST_SFU_CSRRS };
            bins csrrc  = { INST_SFU_CSRRC };
        }

        cp_active_threads : coverpoint active_thr {
            bins one_divergent = { 1 };
            bins partial[]     = { [2 : SIMD_W-1] };
            bins uniform       = { SIMD_W };
        }

        cp_warp : coverpoint wis;

        // The one genuinely meaningful cross: do divergence-control ops
        // (split/join/etc.) themselves fire under partial masks? = real SIMT.
        cross_sfu_threads : cross cp_sfu_op, cp_active_threads;
    endgroup

    // ---- FPU / TCU (no op-decode in this probe) -----------------------------
    // Shared type: divergence + warp distribution only. The class name is set
    // per instance via the constructor argument. Adding an INST_FPU_* / INST_TCU_*
    // op coverpoint later is a clean extension if you want sub-opcode detail.
    covergroup noop_class_cg (string cls) with function sample(
        int                     active_thr,
        logic [ISSUE_WIS_W-1:0] wis
    );
        option.per_instance = 1;
        option.name         = $sformatf("instr_class_cg_%s", cls);

        cp_active_threads : coverpoint active_thr {
            bins one_divergent = { 1 };
            bins partial[]     = { [2 : SIMD_W-1] };
            bins uniform       = { SIMD_W };
        }

        cp_warp : coverpoint wis;
    endgroup

    // =========================================================================
    // Instantiate the correct covergroup per EX-unit dispatch interface and
    // sample on that interface's accepted handshake. The genvar index IS the
    // ex_type, so a generate-if selects the matching class covergroup.
    // =========================================================================
    genvar gi;
    generate
        for (gi = 0; gi < NUM_EX_UNITS; gi++) begin : g_cov

            if (gi == C_ALU) begin : g_alu
                alu_class_cg cg = new();
                always @(posedge clk) begin
                    if (!reset && dispatch_if[gi].valid && dispatch_if[gi].ready) begin
                        cg.sample(
                            dispatch_if[gi].data.op_type,
                            $countones(dispatch_if[gi].data.tmask),
                            dispatch_if[gi].data.wis
                        );
                    end
                end
            end

            else if (gi == C_LSU) begin : g_lsu
                lsu_class_cg cg = new();
                always @(posedge clk) begin
                    if (!reset && dispatch_if[gi].valid && dispatch_if[gi].ready) begin
                        cg.sample(
                            dispatch_if[gi].data.op_type,
                            $countones(dispatch_if[gi].data.tmask),
                            dispatch_if[gi].data.wis
                        );
                    end
                end
            end

            else if (gi == C_SFU) begin : g_sfu
                sfu_class_cg cg = new();
                always @(posedge clk) begin
                    if (!reset && dispatch_if[gi].valid && dispatch_if[gi].ready) begin
                        cg.sample(
                            dispatch_if[gi].data.op_type,
                            $countones(dispatch_if[gi].data.tmask),
                            dispatch_if[gi].data.wis
                        );
                    end
                end
            end

            else if (gi == C_FPU) begin : g_fpu
                noop_class_cg cg = new("fpu");
                always @(posedge clk) begin
                    if (!reset && dispatch_if[gi].valid && dispatch_if[gi].ready) begin
                        cg.sample(
                            $countones(dispatch_if[gi].data.tmask),
                            dispatch_if[gi].data.wis
                        );
                    end
                end
            end

            else if (gi == C_TCU) begin : g_tcu
                noop_class_cg cg = new("tcu");
                always @(posedge clk) begin
                    if (!reset && dispatch_if[gi].valid && dispatch_if[gi].ready) begin
                        cg.sample(
                            $countones(dispatch_if[gi].data.tmask),
                            dispatch_if[gi].data.wis
                        );
                    end
                end
            end

        end
    endgenerate

endmodule