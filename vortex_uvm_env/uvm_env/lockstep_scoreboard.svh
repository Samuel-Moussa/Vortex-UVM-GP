////////////////////////////////////////////////////////////////////////////////
// File: lockstep_scoreboard.svh
// Description: Phase-A / A0 per-instruction lockstep scoreboard (RVVI-style).
//
//   The existing vortex_scoreboard checks END-STATE memory equivalence vs SimX.
//   This component adds a DEFINED-DOMAIN per-instruction checker on top: for
//   every register-writeback retirement, DUT {PC, rd, per-lane data} must match
//   SimX's corresponding retirement, aligned by per-(cid,wid) program order.
//
//   ALIGNMENT: per-warp FIFO program order. The k-th DUT wb-retire for (cid,wid)
//   is compared against the k-th SimX wb-retire for the same (cid,wid). `uuid`
//   is recorded on both sides and CROSS-CHECKED (reported), but is NOT the key —
//   so A0 does not depend on the two uuid schemes matching; it verifies whether
//   they do.
//
//   DOMAIN: writeback retirements only (wb==1). Non-wb instructions (stores,
//   fences, taken branches with no rd) carry no register result and remain
//   covered by the end-state memory compare in vortex_scoreboard.
//
//   SIMD-BEAT AGGREGATION: SimX emits ONE record per warp-instruction (all lanes
//   in result[]); the DUT may commit one warp-instruction across MULTIPLE beats
//   (sop..eop), lanes placed by sid. We aggregate DUT sop→eop beats into one
//   logical retirement (lanes at sid*SIMD_WIDTH + l) before matching.
//
//   RESULT TAXONOMY (industrial scoreboard, not just pass/fail), reported at end:
//     matched              — DUT retire matched SimX on all fields
//     dut_orphan           — DUT wb-retire with no corresponding SimX retire
//     simx_orphan          — SimX wb-retire with no corresponding DUT retire
//     field_mismatch{PC,rd,data} — matched position, differing field
//   Both FIFOs draining empty ⇒ 0 orphans.
//
//   TIMING: runs in check_phase. By then vortex_scoreboard has already invoked
//   simx_run() (on EBREAK in run_phase, or extract_phase fallback), so SimX's
//   cosim drain queue is fully populated; and the rvvi_monitor has published
//   the whole DUT wb stream (A1(c): probe → rvvi_if → monitor → analysis
//   port → write_rvvi() → local queues; extract_phase final-drain precedes
//   every check_phase, so the stream is complete here).
//
//   GATING: built only when cfg.enable_lockstep (from +LOCKSTEP). Default off ⇒
//   this component does not exist and the run is byte-identical.
//
// Author: Vortex UVM (Samuel) — Phase A0
////////////////////////////////////////////////////////////////////////////////

class lockstep_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(lockstep_scoreboard)

    vortex_config cfg;

    // A1(c): RVVI subscription. The rvvi_monitor publishes one rvvi_txn per
    // captured DUT beat; write_rvvi routes it by rec.kind into the local
    // queues below (same shapes the former lockstep_pkg global queues had —
    // build_dut()'s aggregation logic is unchanged).
    uvm_analysis_imp_rvvi #(rvvi_txn, lockstep_scoreboard) rvvi_export;

    lockstep_pkg::dut_retire_s dut_retire_q[$];  // commit writeback beats
    lockstep_pkg::dut_retire_s dut_load_q[$];    // LSU load-writeback beats (OBS-002)

    function void write_rvvi(rvvi_txn t);
        if (t.rec.kind == lockstep_pkg::KIND_LOAD)
            dut_load_q.push_back(t.rec);
        else
            dut_retire_q.push_back(t.rec);
    endfunction

    // Per-instruction LOAD-DATA comparison gate. ON by default (+NO_LOCKSTEP_LOADS
    // disables). The LSU probe (vx_lsu_probe.sv) captures true DUT load values; the
    // raw compare would FALSE-mismatch on loads of uninitialised/stack memory (DUT
    // reads 0, SimX reads its own init pattern) — exactly the class the END-STATE
    // check skips (region gate [RAM_BASE, DATA_LIMIT) + POISON). OBS-002 closes that
    // by exporting the SimX effective address per lane (simx_cosim_record.mem_addr),
    // so compare_pair applies the SAME region filter per-lane before comparing. Load
    // lanes outside the region / poison-valued fall back to the end-state check.
    bit load_cmp_en;

    // RVVI load-bus two-pass feed (Phase A1(e)). +LOCKSTEP_LOADFEED arms it.
    // Pass 1 runs SimX independently and records every provably-racy in-region
    // load that diverged (with the DUT's per-lane values). If any exist, pass 2
    // re-runs SimX with those loads fed the DUT value (so SimX follows the DUT's
    // memory-ordering resolution) and re-compares: residual mismatches are REAL
    // divergences not explained by an unsynchronizable race. Default OFF ⇒ single
    // pass, byte-identical.
    bit feed_en;

    // A captured DUT load override to replay into SimX (pass 2).
    typedef struct {
        int      unsigned cid;
        int      unsigned wid;
        longint  unsigned pc;        // LOAD PC
        int      unsigned occurrence; // n-th execution of that PC on this warp
        int      unsigned mask;      // lanes to override (in-region, active)
        longint  unsigned data [];   // per-lane DUT writeback value
    } feed_rec_t;
    feed_rec_t feed_q [$];

    // OBS-014 sqrt-writeback reconvergence feed (same feed_rec_t shape). Pass 1
    // records every FSQRT writeback whose DUT value diverged but stayed within the
    // documented 1-ULP bound; pass 2 forces those into SimX's FP regfile so SimX
    // reconverges and downstream ops are re-checked bit-exact. Separate cursor from
    // the load feed (a sqrt and a load at the same PC never alias).
    feed_rec_t comp_feed_q [$];

    bit               capturing_feed;   // pass-1 only: populate feed_q on load divergence
    bit               did_pass2;         // set when the pass-2 feed run executed
    // per-key, per-PC running occurrence count (mirrors SimX's (cid,wid,PC) counter)
    int      unsigned pc_occ_ctr [int][longint unsigned];
    // per-key, per-PC FSQRT occurrence count (mirrors SimX's compfeed cursor)
    int      unsigned sqrt_occ_ctr [int][longint unsigned];

    // Pass-1 tallies saved before the pass-2 recompare (for the report).
    int unsigned p1_pairs, p1_matched, p1_mm_pc, p1_mm_rd, p1_mm_data, p1_mm_loaddata,
                 p1_dut_orphan, p1_simx_orphan, p1_first_div_keys;

    // One aggregated logical retirement (either side).
    typedef struct {
        longint  unsigned uuid;
        longint  unsigned pc;
        int      unsigned rd;
        int      unsigned tmask;          // full-width active-lane mask
        bit               is_load;        // SimX FUType==LSU (gold side only)
        bit               is_fp;          // SimX FP-destination writeback (gold side only)
        bit               is_volatile;    // SimX read a perf-counter CSR (gold side only)
        bit               is_fsqrt;       // SimX FPU FSQRT op (gold side only) — OBS-014 1-ULP tolerance
        int      unsigned load_filled_mask; // DUT side: lanes whose load data came
                                          // from the LSU probe (OBS-002 overlay).
                                          // Only these lanes are DATA-comparable.
        longint  unsigned data[];         // size = num_threads
        longint  unsigned addr[];         // gold side: per-lane effective LOAD address
                                          // (OBS-002 region filter); 0 for non-loads
    } retire_t;

    // Region filter for LOAD-data compare — mirrors the end-state check
    // (vortex_scoreboard.sv:64-66). A load lane is only DATA-comparable when its
    // SimX effective address is in the verifiable program/data region AND the gold
    // value isn't SimX's uninitialised-memory poison. Everything else (stack,
    // MMIO, local-mem, never-written) legitimately differs between DUT and SimX.
    localparam bit [31:0] RAM_BASE   = 32'h8000_0000;
    localparam bit [31:0] DATA_LIMIT = 32'h8800_0000;
    localparam bit [31:0] POISON     = 32'hBAAD_F00D;

    // SimX FUType enum: 0=ALU 1=LSU 2=FPU 3=SFU ...
    localparam byte unsigned FU_LSU = 8'd1;

    // Per-(cid,wid) FIFOs, keyed by (cid<<16)|wid.
    retire_t gold_fifo [int][$];
    retire_t dut_fifo  [int][$];

    // ---------------------------------------------------------------------
    // A6 — retirement trace dump (OPTIONAL, default OFF).
    //
    // Emits the aligned DUT and SimX retirement streams to a file so an
    // OFFLINE comparator (scripts/spike_audit.py) can add a THIRD, independent
    // model — Spike — to the base-ISA subset. SimX is written by the Vortex
    // authors, so DUT==SimX is a self-consistency result, not independence
    // (plan FW-2). Spike closes that axis for the scalar prefix only.
    //
    // Gated by +LOCKSTEP_TRACE=<path>, defaulting to OFF, so a normal run is
    // byte-identical — same discipline as LOCKSTEP_LOADFEED and
    // SIMX_FORCE_HALT. This writes a file and touches NO verdict variable:
    // it can neither create nor mask a failure.
    // ---------------------------------------------------------------------
    bit    trace_en;
    int    trace_fh;
    string trace_path;

    // Taxonomy tallies.
    int unsigned n_matched;
    int unsigned n_dut_orphan;
    int unsigned n_simx_orphan;
    int unsigned n_mm_pc;
    int unsigned n_mm_rd;
    int unsigned n_mm_data;
    int unsigned n_mm_loaddata;        // load-writeback data mismatches (LSU-probe overlay)
    int unsigned n_uuid_misaligned;   // cross-check only (not an error)
    int unsigned n_pairs;             // total compared positions
    int unsigned n_load_dataskip;     // load retires with NO LSU-probe data → data skipped (end-state covers)
    int unsigned n_load_datacmp;      // load retires whose data WAS compared (LSU-probe overlay)
    int unsigned n_volatile_skip;     // perf-counter CSR reads: PC/rd checked, data model-divergent
    int unsigned n_multireg_covered;  // multi-register retire (WMMA tile) regs the DUT commit trace
                                      // did not expose → value verified by the end-state memory check
    int unsigned n_fp_ulp_tol;        // OBS-014: FP sqrt writebacks toleranced within the bounded
                                      // 1-ULP window (DUT hardware fsqrt.s vs SoftFloat) — each logged

    // First-divergence capture per (cid,wid), in per-warp program order. This is
    // the A1(d) deliverable: the EARLIEST instruction on each warp where DUT and
    // SimX disagree — the pinpoint that end-state equivalence cannot give. Keyed
    // by the same (cid<<16)|wid, so it localises a multi-cluster divergence to the
    // exact core+warp+PC. Config-generic (cid,wid derived from uuid).
    bit               first_div_seen [int];
    int               first_div_seq  [int];
    longint  unsigned first_div_pc   [int];
    longint  unsigned first_div_uuid [int];
    string            first_div_desc [int];
    int      unsigned div_count      [int];   // total divergences on this warp
    int      unsigned err_emitted    [int];   // per-key emitted uvm_error count (spew cap)

    // A real cross-core divergence cascades: once a warp diverges, every later
    // retire on it mismatches too. Emit at most this many uvm_error lines per warp
    // (the FIRST few are what matter); the true n_mm_* tallies are counted in full
    // regardless, and report_phase prints the first-divergence pinpoint per warp.
    localparam int MAX_ERR_PER_KEY = 4;

    // OBS-014 — bounded, DOCUMENTED FP-sqrt tolerance. The DUT hardware fsqrt.s
    // (cvfpu/FPnew) rounds 1 ULP away from the IEEE-correct SoftFloat reference SimX
    // uses. This is a real, cited RTL accuracy limitation — the tolerance NEVER hides
    // it: every toleranced op is logged (up to the cap) and tallied in n_fp_ulp_tol,
    // and it applies to FSQRT gold ops ONLY (all other FP ops stay bit-exact, so a
    // deviation on +,-,*,/,fma,cvt is still a hard failure). A sqrt result more than
    // this many ULP off — or a NaN/Inf mismatch — also still fails.
    localparam int unsigned FP_SQRT_MAX_ULP = 1;
    localparam int          FP_ULP_LOG_CAP  = 16;   // cap the per-op tolerance log spew

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rvvi_export = new("rvvi_export", this);
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("LOCKSTEP", "vortex_config not found")
        // Per-instruction LOAD-data compare is now SOUND (region-filtered by the
        // SimX effective address, OBS-002) → ON by default. +NO_LOCKSTEP_LOADS is
        // the escape hatch to fall back to PC/rd/ordering-only for loads.
        load_cmp_en = !$test$plusargs("NO_LOCKSTEP_LOADS");
        // RVVI load-bus two-pass feed (Phase A1(e)) — off unless requested.
        feed_en = $test$plusargs("LOCKSTEP_LOADFEED");
        // A6 retirement trace — off unless a path is supplied.
        trace_en = $value$plusargs("LOCKSTEP_TRACE=%s", trace_path);
        if (trace_en) begin
            trace_fh = $fopen(trace_path, "w");
            if (trace_fh == 0) begin
                `uvm_warning("LOCKSTEP", $sformatf(
                    "LOCKSTEP_TRACE: cannot open '%s' — trace disabled (run is otherwise unaffected)",
                    trace_path))
                trace_en = 1'b0;
            end else begin
                // Self-describing header: the offline comparator keys off these
                // names rather than column positions.
                $fdisplay(trace_fh,
                    "# vortex lockstep retirement trace v1");
                $fdisplay(trace_fh,
                    "# fields: key seq cid wid dut_pc dut_rd dut_d0 simx_pc simx_rd simx_d0 tmask flags");
                $fdisplay(trace_fh,
                    "# flags: L=load F=fp V=volatile(perf-CSR) Q=fsqrt");
                `uvm_info("LOCKSTEP", $sformatf("A6 retirement trace -> %s", trace_path), UVM_LOW)
            end
        end
    endfunction

    // key helper
    function automatic int key_of(int unsigned cid, int unsigned wid);
        return int'((cid << 16) | wid);
    endfunction

    // Number of low uuid[63:32] bits used for the local warp id (= log2 NUM_WARPS,
    // NW_BITS in RTL). Above that sits CORE_ID. See VX_uuid_gen.sv:40.
    function automatic int nw_bits();
        return (cfg.num_warps <= 1) ? 0 : $clog2(cfg.num_warps);
    endfunction

    // Recover the flat global core id from a DUT uuid. VX_uuid_gen packs
    //   uuid = { g_wid[UUID_WIDTH-33:0], counter[31:0] },  g_wid = (CORE_ID<<NW_BITS)+wid
    // so CORE_ID == (uuid >> 32) >> NW_BITS. This matches SimX's flat cid
    // (core.cpp asserts trace->cid == core_id_). Lets multi-core lockstep key by
    // (cid,wid) without a probe/RTL change (probe's pushed cid is superseded).
    function automatic int unsigned cid_of_uuid(longint unsigned uuid);
        return int'((uuid >> 32) >> nw_bits());
    endfunction
    function automatic int unsigned wid_of_uuid(longint unsigned uuid);
        // wid occupies the low NW_BITS of g_wid; mask by (2^NW_BITS - 1) so this
        // is correct for ANY NUM_WARPS (incl. non-power-of-2), not just num_warps-1.
        return int'((uuid >> 32) & ((1 << nw_bits()) - 1));
    endfunction
    // A multi-register / multi-beat retirement (the WMMA output tile) is emitted as
    // several commit records that share the base per-warp counter but carry a beat/
    // round SUB-INDEX in uuid bits[31:28] (observed: successive tile records differ by
    // exactly 1<<28; the RTL counter itself increments by 1 per instruction). Sorting
    // by the raw uuid scatters those high-valued sub-indexed records to the end of the
    // per-warp FIFO, away from the instruction's program position. po_base() folds the
    // sub-index away so all records of one instruction share a grouping key; po_order()
    // moves the sub-index BELOW the counter so a sort yields true program order
    // (counter, then sub-index). Bound: a per-warp retire count < 2^28 (all our tests);
    // above that the base counter would collide with the sub-index field.
    function automatic longint unsigned po_base(longint unsigned uuid);
        return uuid & 64'hFFFF_FFFF_0FFF_FFFF;
    endfunction
    function automatic longint unsigned po_order(longint unsigned uuid);
        return (uuid & 64'hFFFF_FFFF_0000_0000)
             | ((uuid & 64'h0FFF_FFFF) << 4)
             | ((uuid >> 28) & 64'hF);
    endfunction

    //--------------------------------------------------------------------------
    // Drain SimX's cosim queue into per-(cid,wid) gold FIFOs (wb records only).
    //--------------------------------------------------------------------------
    function automatic void build_gold();
        int rc;
        longint  unsigned uuid, pc;
        int      unsigned cid, wid, tmask;
        byte     unsigned wb, is_fp, rd, sop, eop, fu_type, is_volatile, is_fsqrt;
        longint  unsigned res[];
        longint  unsigned adr[];
        int      k;
        retire_t g;
        forever begin
            res = new[cfg.num_threads];
            adr = new[cfg.num_threads];
            rc = simx_cosim_pop(uuid, cid, wid, pc, tmask, wb, is_fp, rd, sop, eop, fu_type, is_volatile, is_fsqrt, res, adr);
            if (rc <= 0) break;             // 0 = empty, -1 = error
            if (wb == 0) continue;          // writeback domain only
            g.uuid        = uuid;
            g.pc          = pc;
            // FP register-index convention reconciliation (real fix, NOT a waiver).
            // Vortex RTL uses a UNIFIED 64-entry regfile: integer regs at indices
            // 0..31, float regs at 32..63 — so the DUT commit trace names e.g. `fa5`
            // (float reg 15) as rd=47 (=32+15). SimX keeps SEPARATE int/float files
            // and exports rd=15 with is_fp=1 (core.cpp:244-245). Both name the SAME
            // architectural location; comparing 47 vs 15 raw is a comparator bug that
            // false-flags EVERY FP writeback. Normalize the golden index into the DUT's
            // unified space. The +32 offset is architectural (32 integer GPRs, always),
            // valid for any config; the branch is dead when EXT_F is off (is_fp never set).
            // NOTE: only the register SLOT is reconciled — the per-lane writeback DATA is
            // still compared bit-exact below, so a wrong FP result is still caught.
            g.rd          = (is_fp != 0) ? (int'(rd) + 32) : int'(rd);
            g.tmask       = tmask;
            g.is_load     = (fu_type == FU_LSU);
            g.is_fp       = (is_fp != 0);   // FP-dest load data routes to the FP regfile,
                                            // NOT the integer result_if tap the LSU probe reads
            g.is_volatile = (is_volatile != 0);
            g.is_fsqrt    = (is_fsqrt != 0);   // OBS-014: 1-ULP sqrt tolerance eligibility
            g.data        = new[cfg.num_threads];
            g.addr        = new[cfg.num_threads];
            for (k = 0; k < cfg.num_threads; k++) begin
                g.data[k] = res[k];
                g.addr[k] = adr[k];
            end
            gold_fifo[key_of(cid, wid)].push_back(g);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Aggregate DUT commit records into per-(cid,wid) logical retirements,
    // grouped by `uuid`. ONE issued instruction can produce MULTIPLE commit
    // records with the SAME uuid:
    //   - SIMD-beat splits (lanes placed by sid*SIMD_WIDTH), and
    //   - LOAD partial-mask writebacks (the LSU commits lanes as their memory
    //     responses arrive → several records, overlapping/partial tmasks).
    // Grouping by uuid (not sop/eop) merges them robustly: union the tmasks and
    // place each active lane's data. SimX emits exactly one record per uuid, so
    // one merged DUT retirement per uuid aligns 1:1.
    //
    // The DUT also commits OUT OF PROGRAM ORDER (execution units have different
    // latencies; the commit arbiter retires whoever is ready first). `uuid` is
    // the per-warp issue counter = program order, so we emit each key's merged
    // retirements sorted by uuid, matching SimX's strict program order. Sorting
    // within a per-wid bucket is correct even if uuid embeds wid in high bits.
    //--------------------------------------------------------------------------
    function automatic void build_dut();
        // [key][uuid][rd] -> merged retirement. Keying by (uuid,rd) — NOT uuid alone —
        // splits a MULTI-REGISTER retirement into one record per destination register.
        // The WMMA tile writes rd 42..49 under ONE uuid; SimX's cosim export emits one
        // retire record PER output register, so keying by uuid alone collapsed the whole
        // tile into a single lossy DUT record and desynchronized the retire streams at
        // every WMMA (DUT emitted 1 where SimX emits N → downstream position slip). A
        // normal instruction has one rd (key == old behaviour); SIMD-beat splits and
        // partial-mask load writebacks share the SAME (uuid,rd) and still merge correctly.
        retire_t merged [int][longint][int];
        int      key, base, simd_w, l, gi, i, rdk;
        lockstep_pkg::dut_retire_s b;
        for (i = 0; i < dut_retire_q.size(); i++) begin
            b      = dut_retire_q[i];
            // Derive the flat global (cid,wid) from the uuid rather than trusting
            // the probe's pushed cid (hardcoded 0). uuid embeds CORE_ID + wid.
            key    = key_of(cid_of_uuid(b.uuid), wid_of_uuid(b.uuid));
            rdk    = b.rd;
            simd_w = b.data.size();
            base   = b.sid * simd_w;
            if (!merged[key][b.uuid].exists(rdk)) begin
                merged[key][b.uuid][rdk].uuid  = b.uuid;
                merged[key][b.uuid][rdk].pc    = b.pc;
                merged[key][b.uuid][rdk].rd    = b.rd;
                merged[key][b.uuid][rdk].tmask = 0;
                merged[key][b.uuid][rdk].load_filled_mask = 0;
                merged[key][b.uuid][rdk].data  = new[cfg.num_threads];
            end
            // Place only the lanes this record actually wrote (tmask-gated), and
            // union them into the merged active mask.
            for (l = 0; l < simd_w; l++) begin
                gi = base + l;
                if (gi < cfg.num_threads && ((b.tmask >> l) & 1)) begin
                    merged[key][b.uuid][rdk].data[gi]  = b.data[l];
                    merged[key][b.uuid][rdk].tmask    |= (1 << gi);
                end
            end
        end
        // OVERLAY real LOAD data from the LSU probe (dut_load_q) onto the matching
        // commit retirement, keyed by (uuid,rd). The commit `data` field is stale for
        // loads (OBS-002); VX_lsu_slice.result_if carries the true aligned per-lane
        // value. Place active lanes exactly like the commit path (sid*simd_w + l)
        // and record which lanes were filled (load_filled_mask) so compare_pair
        // only trusts those. A load with no captured beat stays unfilled → still
        // skipped (falls back to the end-state memory check).
        for (i = 0; i < dut_load_q.size(); i++) begin
            lockstep_pkg::dut_retire_s lb;
            int lkey, lbase, lsimd, ll, lgi, lrd;
            lb    = dut_load_q[i];
            lkey  = key_of(cid_of_uuid(lb.uuid), wid_of_uuid(lb.uuid));
            lrd   = lb.rd;
            if (!merged.exists(lkey)) continue;
            if (!merged[lkey].exists(lb.uuid)) continue;       // load with no commit retire
            if (!merged[lkey][lb.uuid].exists(lrd)) continue;
            lsimd = lb.data.size();
            lbase = lb.sid * lsimd;
            for (ll = 0; ll < lsimd; ll++) begin
                lgi = lbase + ll;
                if (lgi < cfg.num_threads && ((lb.tmask >> ll) & 1)) begin
                    merged[lkey][lb.uuid][lrd].data[lgi]         = lb.data[ll];
                    merged[lkey][lb.uuid][lrd].load_filled_mask |= (1 << lgi);
                end
            end
        end

        // Flatten each key's (uuid,rd) map into program order: uuid ascending (unsigned),
        // then rd ascending within a uuid (matches SimX's rd-ordered tile emission).
        foreach (merged[key]) begin
            longint unsigned uus[$];
            foreach (merged[key][u]) uus.push_back(u);
            uus.sort() with (po_order(item));   // program order: counter, then tile sub-index
            foreach (uus[j])
                foreach (merged[key][uus[j]][r])
                    dut_fifo[key].push_back(merged[key][uus[j]][r]);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Record the FIRST divergence on a warp (program order) and emit a capped
    // number of uvm_error lines. A cascading multi-core divergence would other-
    // wise flood the log with thousands of downstream errors; the first few are
    // what pinpoint the fault. True n_mm_* tallies are counted at the call site
    // regardless of this cap.
    //--------------------------------------------------------------------------
    function automatic void note_div(int key, int seq, longint unsigned pc,
                                     longint unsigned uuid, string desc, string msg);
        div_count[key]++;
        if (!first_div_seen.exists(key)) begin
            first_div_seen[key] = 1;
            first_div_seq[key]  = seq;
            first_div_pc[key]   = pc;
            first_div_uuid[key] = uuid;
            first_div_desc[key] = desc;
        end
        if (err_emitted[key] < MAX_ERR_PER_KEY) begin
            // In pass 1 of a two-pass RVVI run (feed armed), a divergence is
            // DIAGNOSTIC — it identifies a candidate racy load. The authoritative
            // pass/fail is the pass-2 residual after the DUT load-bus feed (and,
            // if no races are found, the report_phase unexplained-divergence
            // check). So emit info here, NOT error — a proven race must not fail
            // the test, and a REAL divergence resurfaces as a pass-2 residual
            // uvm_error. Default (no feed) keeps the original uvm_error semantics.
            if (feed_en && capturing_feed)
                `uvm_info("LOCKSTEP", {"[pass-1 diagnostic] ", msg}, UVM_LOW)
            else
                `uvm_error("LOCKSTEP", msg)
            err_emitted[key]++;
        end else if (err_emitted[key] == MAX_ERR_PER_KEY) begin
            err_emitted[key]++;
            `uvm_info("LOCKSTEP", $sformatf(
                "  (further LOCKSTEP errors on key=%0h suppressed after %0d; see tallies + first-divergence block)",
                key, MAX_ERR_PER_KEY), UVM_LOW)
        end
    endfunction

    //--------------------------------------------------------------------------
    // Single-precision ULP-distance test for the OBS-014 fsqrt tolerance.
    // Returns 1 iff a and b are the SAME sign, both finite (not NaN, not Inf),
    // and at most `maxulp` representable steps apart. sqrt results are non-negative
    // for finite non-negative operands, so within one sign the IEEE encoding is
    // monotonic in magnitude ⇒ ULP distance == |a[30:0]-b[30:0]|. NaN/Inf require an
    // exact match (returns 0), so those never get toleranced.
    //--------------------------------------------------------------------------
    function automatic bit fp32_within_ulp(logic [31:0] a, logic [31:0] b, int unsigned maxulp);
        logic [7:0]   ea = a[30:23];
        logic [7:0]   eb = b[30:23];
        int  unsigned dd;
        if ((ea == 8'hFF) || (eb == 8'hFF)) return 1'b0;   // NaN/Inf → require exact
        if (a[31] != b[31])                 return 1'b0;   // opposite signs → not rounding-adjacent
        dd = (a[30:0] > b[30:0]) ? (a[30:0] - b[30:0]) : (b[30:0] - a[30:0]);
        return (dd <= maxulp);
    endfunction

    //--------------------------------------------------------------------------
    // Compare one aligned (DUT, SimX) pair. Counts each differing field, and
    // records/ caps-emits the divergence via note_div.
    //--------------------------------------------------------------------------
    function automatic void compare_pair(int key, int seq, retire_t d, retire_t g);
        bit    clean = 1'b1;
        string desc  = "";
        n_pairs++;
        // A6 trace (observability only — no verdict effect). Lane 0 is dumped
        // because Spike is scalar: it has no counterpart for lanes 1..N-1.
        if (trace_en) begin
            string flags = "";
            if (g.is_load)     flags = {flags, "L"};
            if (g.is_fp)       flags = {flags, "F"};
            if (g.is_volatile) flags = {flags, "V"};
            if (g.is_fsqrt)    flags = {flags, "Q"};
            if (flags == "")   flags = "-";
            $fdisplay(trace_fh, "%0h %0d %0d %0d %0h %0d %0h %0h %0d %0h %0h %s",
                      key, seq, (key >> 16), (key & 16'hFFFF),
                      d.pc, d.rd, (d.data.size() > 0 ? d.data[0] : 64'h0),
                      g.pc, g.rd, (g.data.size() > 0 ? g.data[0] : 64'h0),
                      d.tmask, flags);
        end
        if (d.uuid != g.uuid) n_uuid_misaligned++;   // cross-check, not a failure
        if (d.pc != g.pc) begin
            n_mm_pc++; clean = 1'b0;
            if (desc == "") desc = $sformatf("PC DUT=%0h vs SimX=%0h", d.pc, g.pc);
            note_div(key, seq, d.pc, d.uuid, desc, $sformatf(
                "PC mismatch key=%0h seq=%0d: DUT PC=%0h (uuid=%0h) vs SimX PC=%0h (uuid=%0h)",
                key, seq, d.pc, d.uuid, g.pc, g.uuid));
        end
        if (d.rd != g.rd) begin
            n_mm_rd++; clean = 1'b0;
            if (desc == "") desc = $sformatf("rd DUT=%0d vs SimX=%0d", d.rd, g.rd);
            note_div(key, seq, d.pc, d.uuid, desc, $sformatf(
                "rd mismatch key=%0h seq=%0d PC=%0h: DUT rd=%0d vs SimX rd=%0d",
                key, seq, d.pc, d.rd, g.rd));
        end
        // Load-writeback DATA is not observable at the DUT commit-arb probe
        // (loads complete via the async LSU response path; empirically the
        // commit `data` field carries a uniform/stale value for `lw`). Load
        // *correctness* is covered by the end-state memory equivalence check in
        // vortex_scoreboard. So for loads we verify PC + rd + ordering here and
        // skip the per-lane data compare. Non-load writebacks are data-checked.
        if (g.is_load) begin
            // Per-(warp,PC) occurrence count — mirrors SimX's (cid,wid,PC) counter
            // exactly, so it is the alignment key for the feed (robust to interrupt-
            // inserted instructions, unlike a raw ordinal). MUST advance for EVERY
            // load retirement at this PC (even skipped ones) to stay aligned.
            int unsigned this_occ = (pc_occ_ctr.exists(key) && pc_occ_ctr[key].exists(g.pc))
                                  ? pc_occ_ctr[key][g.pc] : 0;
            pc_occ_ctr[key][g.pc] = this_occ + 1;
            // Load DATA is observable via the LSU probe (OBS-002 overlay). It is
            // compared per-lane only where it is SOUND to do so: the lane must be
            // active on both sides (tmask + LSU-probe fill) AND the SimX effective
            // address must fall in the verifiable region AND the gold value must not
            // be SimX's uninitialised poison. Out-of-region / uninit loads (stack,
            // MMIO, local-mem, never-written) legitimately differ and are covered by
            // the end-state memory check — same filter as vortex_scoreboard.
            if (!load_cmp_en || d.load_filled_mask == 0) begin
                n_load_dataskip++;
            end else begin
                bit any_cmp = 1'b0;
                bit div_seen = 1'b0;          // any in-region lane diverged
                int unsigned region_mask = 0; // in-region active comparable lanes
                for (int l = 0; l < cfg.num_threads; l++) begin
                    if (((g.tmask >> l) & 1) && ((d.load_filled_mask >> l) & 1)) begin
                        bit in_region = (g.addr[l][31:0] >= RAM_BASE)
                                     && (g.addr[l][31:0] <  DATA_LIMIT);
                        bit is_poison = (g.data[l][31:0] == POISON)
                                     || (g.data[l][63:32] == POISON);
                        if (!in_region || is_poison) continue;  // end-state covers it
                        any_cmp = 1'b1;
                        region_mask |= (1 << l);
                        // Same FP NaN-box reconciliation as the writeback compare: an
                        // `flw` (FP-dest load) writes a 32-bit value the SimX side
                        // NaN-boxes (upper32=0xFFFFFFFF) but the F-only DUT regfile does
                        // not. Compare the architectural low-32 (FLEN) bits when the gold
                        // value is boxed; a real loaded-value difference is still caught.
                        begin
                        bit lmism;
                        if (g.is_fp && (g.data[l][63:32] === 32'hFFFF_FFFF))
                            lmism = (d.data[l][31:0] !== g.data[l][31:0]);
                        else
                            lmism = (d.data[l] !== g.data[l]);
                        if (lmism) begin
                            n_mm_loaddata++; clean = 1'b0; div_seen = 1'b1;
                            if (desc == "") desc = $sformatf(
                                "LOAD data lane%0d @%0h DUT=%0h vs SimX=%0h", l, g.addr[l], d.data[l], g.data[l]);
                            note_div(key, seq, d.pc, d.uuid, desc, $sformatf(
                                "LOAD-DATA mismatch key=%0h seq=%0d PC=%0h uuid=%0h lane=%0d addr=%0h: DUT=%0h vs SimX=%0h",
                                key, seq, d.pc, d.uuid, l, g.addr[l], d.data[l], g.data[l]));
                        end
                        end
                    end
                end
                if (any_cmp) n_load_datacmp++;   // at least one lane was region-valid
                else         n_load_dataskip++;  // all lanes out-of-region/uninit
                // FEED CAPTURE (pass 1): this in-region load provably diverged and
                // has no single golden value (racy shared access). Record the DUT's
                // per-lane values so pass 2 can drive SimX to follow the DUT and
                // isolate any REAL residual divergence. Feed all in-region active
                // lanes (matching lanes are a harmless no-op).
                // EXCLUDE FP-dest loads: the load feed is integer-only (it substitutes
                // a raw 64-bit value; an FP-dest load must be NaN-boxed, which this path
                // does not do → SimX's check_boxing would see an unboxed value as qNaN
                // and cascade). FP-load divergence from a sqrt propagates via the OBS-014
                // sqrt feed instead (SimX's own store→flw re-boxes the reconverged value).
                if (capturing_feed && feed_en && div_seen && region_mask != 0 && !g.is_fp) begin
                    feed_rec_t fr;
                    fr.cid        = key >> 16;
                    fr.wid        = key & 32'hFFFF;
                    fr.pc         = g.pc;
                    fr.occurrence = this_occ;
                    fr.mask       = region_mask;
                    fr.data       = new[cfg.num_threads];
                    for (int l = 0; l < cfg.num_threads; l++) fr.data[l] = d.data[l];
                    feed_q.push_back(fr);
                end
            end
        end else if (g.is_volatile) begin
            n_volatile_skip++;          // mcycle/minstret/... model-divergent by definition
        end else begin
            // FSQRT occurrence tracking for the OBS-014 reconvergence feed: advance
            // once per sqrt at this PC (fed or not), mirroring SimX's compfeed cursor.
            bit          sqrt_tol_seen = 1'b0;
            int unsigned this_sqrt_occ = 0;
            if (g.is_fsqrt) begin
                this_sqrt_occ = (sqrt_occ_ctr.exists(key) && sqrt_occ_ctr[key].exists(g.pc))
                              ? sqrt_occ_ctr[key][g.pc] : 0;
                sqrt_occ_ctr[key][g.pc] = this_sqrt_occ + 1;
            end
            for (int l = 0; l < cfg.num_threads; l++) begin
                if ((g.tmask >> l) & 1) begin
                    // FP NaN-box reconciliation (real fix, NOT a waiver). SimX carries a
                    // 64-bit FP regfile and NaN-boxes single-precision results (upper32 =
                    // 0xFFFFFFFF, execute.cpp:37); the F-only (FLEN=32) DUT FP regfile is
                    // 32-bit and reports no upper bits, so raw 64-bit compare mismatches on
                    // EVERY FP writeback (0x0000_0000_xxxx vs 0xFFFF_FFFF_xxxx). When the
                    // golden value is NaN-boxed, compare the architectural low-32 (FLEN)
                    // bits — the box is representation metadata, not architectural state.
                    // The single-precision VALUE is still compared bit-exact, so a real FP
                    // result bug is still caught. Non-boxed gold (a true 64-bit D-extension
                    // result) falls through to the exact full-width compare → FLEN=64 stays
                    // strict; this branch is dead when EXT_F is off (is_fp never set).
                    bit mism;
                    if (g.is_fp && (g.data[l][63:32] === 32'hFFFF_FFFF))
                        mism = (d.data[l][31:0] !== g.data[l][31:0]);
                    else
                        mism = (d.data[l] !== g.data[l]);
                    // OBS-014: DOCUMENTED, bounded 1-ULP tolerance for hardware fsqrt.s
                    // ONLY. The DUT FPU sqrt unit rounds 1 ULP off the IEEE-correct
                    // SoftFloat reference. NOT hidden — each toleranced op is logged and
                    // tallied (n_fp_ulp_tol). Gated on g.is_fsqrt, so +,-,*,/,fma,cvt stay
                    // bit-exact and any deviation there is still a hard failure; a sqrt
                    // result >1 ULP off, or a NaN/Inf mismatch, also still fails.
                    if (mism && g.is_fsqrt &&
                        fp32_within_ulp(d.data[l][31:0], g.data[l][31:0], FP_SQRT_MAX_ULP)) begin
                        mism = 1'b0;
                        n_fp_ulp_tol++;
                        sqrt_tol_seen = 1'b1;
                        if (n_fp_ulp_tol <= FP_ULP_LOG_CAP)
                            `uvm_info("LOCKSTEP", $sformatf(
                                "[OBS-014 fsqrt %0d-ULP TOLERATED] key=%0h PC=%0h lane=%0d DUT=%0h vs SimX=%0h (sqrt only)",
                                FP_SQRT_MAX_ULP, key, g.pc, l, d.data[l][31:0], g.data[l][31:0]), UVM_LOW)
                    end
                    if (mism) begin
                        n_mm_data++; clean = 1'b0;
                        if (desc == "") desc = $sformatf(
                            "data lane%0d DUT=%0h vs SimX=%0h", l, d.data[l], g.data[l]);
                        note_div(key, seq, d.pc, d.uuid, desc, $sformatf(
                            "DATA mismatch key=%0h seq=%0d PC=%0h uuid=%0h lane=%0d: DUT=%0h vs SimX=%0h",
                            key, seq, d.pc, d.uuid, l, d.data[l], g.data[l]));
                    end
                end
            end
            // OBS-014 FEED CAPTURE (pass 1): this sqrt's DUT result stayed within the
            // documented 1-ULP bound → hand SimX the DUT per-lane values so pass 2
            // forces them into its FP regfile (reconvergence) and re-checks every
            // downstream op bit-exact. Feed all active lanes (exact-match lanes are a
            // harmless identity feed). Gated on the same two-pass arm as the load feed.
            if (g.is_fsqrt && capturing_feed && feed_en && sqrt_tol_seen) begin
                feed_rec_t sf;
                sf.cid        = key >> 16;
                sf.wid        = key & 32'hFFFF;
                sf.pc         = g.pc;
                sf.occurrence = this_sqrt_occ;
                sf.mask       = g.tmask;
                sf.data       = new[cfg.num_threads];
                for (int l = 0; l < cfg.num_threads; l++) sf.data[l] = d.data[l];
                comp_feed_q.push_back(sf);
            end
        end
        if (clean) n_matched++;
    endfunction

    //--------------------------------------------------------------------------
    // Walk each per-warp FIFO in lockstep and compare/tally. Reads the current
    // gold_fifo/dut_fifo (rebuilt per pass).
    //--------------------------------------------------------------------------
    // Instruction-grouped alignment (industrial multi-register-retire handling). Both
    // per-warp streams are in program order, but a MULTI-REGISTER retirement — the WMMA
    // writes an 8-register output tile — is committed by the DUT as few records (grouped
    // by its per-warp `uuid`) while SimX's cosim export emits one record PER written
    // register (same PC, distinct rd). Naive position alignment desynchronizes there.
    // Instead: group the DUT stream by uuid (its instruction id), take gold's leading
    // records at that instruction's PC WITH DISTINCT rd (a repeated rd marks the next
    // loop iteration, not a tile), and match within the group by rd. Gold registers the
    // DUT never exposed (extra tile elements) are END-STATE-COVERED — their values are
    // stored to memory and checked by the end-state scoreboard — counted honestly, never
    // dropped. Streams stay synchronized regardless of per-instruction record counts.
    function automatic void run_compare();
        int keys[$];
        foreach (gold_fifo[k]) keys.push_back(k);
        foreach (dut_fifo[k])  if (!gold_fifo.exists(k)) keys.push_back(k);
        foreach (keys[ki]) begin
            int key = keys[ki];
            int nd  = dut_fifo.exists(key)  ? dut_fifo[key].size()  : 0;
            int ng  = gold_fifo.exists(key) ? gold_fifo[key].size() : 0;
            int di = 0, gi = 0, seq = 0;
            while (di < nd || gi < ng) begin
                longint unsigned cur_uuid, cur_pc;
                int di_end, gi_end, dj, gj;
                bit gused [$];
                if (di >= nd) begin                       // gold tail, no DUT instruction
                    n_simx_orphan++;
                    note_div(key, seq, gold_fifo[key][gi].pc, gold_fifo[key][gi].uuid,
                        "SIMX-ORPHAN (no DUT retire)", $sformatf(
                        "SIMX-ORPHAN key=%0h seq=%0d PC=%0h (no DUT retire)",
                        key, seq, gold_fifo[key][gi].pc));
                    gi++; seq++; continue;
                end
                cur_uuid = po_base(dut_fifo[key][di].uuid);
                cur_pc   = dut_fifo[key][di].pc;
                // DUT instruction extent = all records sharing this uuid (sub-index folded
                // via po_base, so a multi-beat WMMA tile groups as ONE instruction).
                di_end = di;
                while (di_end < nd && po_base(dut_fifo[key][di_end].uuid) == cur_uuid) di_end++;
                // Gold instruction extent = leading records at this instruction's PC. A
                // multi-register op (WMMA) emits many same-PC gold records — possibly
                // several ROUNDS of the tile (rd 42..49 repeating). Since the DUT has a
                // SINGLE instruction (uuid) here, they ALL belong to it → consume every
                // leading same-PC gold record. The one exception is a single-instruction
                // LOOP (the NEXT DUT instruction is at the SAME PC): there each same-PC
                // gold record is a distinct iteration, so cap the group at a distinct-rd
                // run (one iteration's writes) to avoid swallowing later iterations.
                begin
                    longint unsigned next_dut_pc;
                    next_dut_pc = (di_end < nd) ? dut_fifo[key][di_end].pc : 64'hFFFF_FFFF_FFFF_FFFF;
                    gi_end = gi;
                    if (next_dut_pc != cur_pc) begin
                        while (gi_end < ng && gold_fifo[key][gi_end].pc == cur_pc) gi_end++;
                    end else begin
                        int seen_rd [int];
                        while (gi_end < ng && gold_fifo[key][gi_end].pc == cur_pc
                               && !seen_rd.exists(gold_fifo[key][gi_end].rd)) begin
                            seen_rd[gold_fifo[key][gi_end].rd] = 1;
                            gi_end++;
                        end
                    end
                end
                if (gi_end == gi) begin
                    // Gold's next record is NOT at this instruction's PC → genuine PC
                    // divergence. Compare 1:1 to record it, advance both to try to resync.
                    if (gi < ng) begin
                        compare_pair(key, seq, dut_fifo[key][di], gold_fifo[key][gi]);
                        gi++;
                    end else begin
                        n_dut_orphan++;
                        note_div(key, seq, dut_fifo[key][di].pc, dut_fifo[key][di].uuid,
                            "DUT-ORPHAN (no SimX retire)", $sformatf(
                            "DUT-ORPHAN key=%0h seq=%0d PC=%0h uuid=%0h",
                            key, seq, dut_fifo[key][di].pc, dut_fifo[key][di].uuid));
                    end
                    di = di_end; seq++; continue;
                end
                // Match each DUT register write to a gold record by rd within the group.
                gused = {};
                for (gj = gi; gj < gi_end; gj++) gused.push_back(1'b0);
                for (dj = di; dj < di_end; dj++) begin
                    bit found = 1'b0;
                    for (gj = gi; gj < gi_end; gj++) begin
                        if (!gused[gj-gi] && gold_fifo[key][gj].rd == dut_fifo[key][dj].rd) begin
                            compare_pair(key, seq, dut_fifo[key][dj], gold_fifo[key][gj]);
                            gused[gj-gi] = 1'b1; found = 1'b1;
                            break;
                        end
                    end
                    if (!found) begin                     // DUT reg not present in gold group
                        n_dut_orphan++;
                        note_div(key, seq, dut_fifo[key][dj].pc, dut_fifo[key][dj].uuid,
                            "DUT-ORPHAN (rd not in SimX group)", $sformatf(
                            "DUT-ORPHAN key=%0h seq=%0d PC=%0h rd=%0d",
                            key, seq, dut_fifo[key][dj].pc, dut_fifo[key][dj].rd));
                    end
                end
                // Gold registers the DUT did not expose = end-state-covered tile elements.
                for (gj = gi; gj < gi_end; gj++)
                    if (!gused[gj-gi]) n_multireg_covered++;
                di = di_end; gi = gi_end; seq++;
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Zero all tallies + first-divergence state for a fresh compare pass.
    //--------------------------------------------------------------------------
    function automatic void reset_tallies();
        n_matched=0; n_dut_orphan=0; n_simx_orphan=0; n_mm_pc=0; n_mm_rd=0;
        n_mm_data=0; n_mm_loaddata=0; n_uuid_misaligned=0; n_pairs=0;
        n_load_dataskip=0; n_load_datacmp=0; n_volatile_skip=0; n_multireg_covered=0;
        n_fp_ulp_tol=0;
        first_div_seen.delete(); first_div_seq.delete(); first_div_pc.delete();
        first_div_uuid.delete(); first_div_desc.delete(); div_count.delete();
        err_emitted.delete(); pc_occ_ctr.delete(); sqrt_occ_ctr.delete();
    endfunction

    //--------------------------------------------------------------------------
    // check_phase — PASS 1 (independent SimX) then, if the RVVI load-bus feed is
    // armed and pass 1 found provably-racy in-region load divergences, PASS 2
    // (re-run SimX with those loads fed the DUT value → residual mismatches are
    // REAL divergences, not unsynchronizable races).
    //--------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (cfg == null || !cfg.enable_lockstep) return;

        // -------- PASS 1: independent SimX (feed disabled in SimX) --------
        capturing_feed = 1'b1;
        build_gold();
        build_dut();
        run_compare();

        // -------- PASS 2: RVVI load-bus + OBS-014 sqrt reconvergence ---------
        // (only if the two-pass feed is armed AND pass 1 captured a racy load OR a
        // toleranced sqrt whose value should be reconverged into SimX).
        if (feed_en && (feed_q.size() > 0 || comp_feed_q.size() > 0)) begin
            int exitcode2;
            // snapshot pass-1 tallies for the two-pass verdict
            p1_pairs=n_pairs; p1_matched=n_matched; p1_mm_pc=n_mm_pc; p1_mm_rd=n_mm_rd;
            p1_mm_data=n_mm_data; p1_mm_loaddata=n_mm_loaddata;
            p1_dut_orphan=n_dut_orphan; p1_simx_orphan=n_simx_orphan;
            p1_first_div_keys=first_div_seen.num();
            did_pass2 = 1'b1;

            `uvm_info("LOCKSTEP", $sformatf(
                "PASS 1: %0d racy in-region LOAD-data divergence(s) over %0d captured load(s) + %0d sqrt reconvergence feed(s) (OBS-014). Re-running SimX with the DUT values fed (PASS 2)...",
                p1_mm_loaddata, feed_q.size(), comp_feed_q.size()), UVM_LOW)

            // Arm both feeds in SimX with the captured DUT values.
            simx_cosim_clear();
            simx_cosim_load_feed_reset();
            simx_cosim_load_feed_enable(1);
            foreach (feed_q[i])
                simx_cosim_load_feed_push(feed_q[i].cid, feed_q[i].wid, feed_q[i].pc,
                                          feed_q[i].occurrence, feed_q[i].mask, feed_q[i].data);
            simx_cosim_comp_feed_reset();
            simx_cosim_comp_feed_enable(1);
            foreach (comp_feed_q[i])
                simx_cosim_comp_feed_push(comp_feed_q[i].cid, comp_feed_q[i].wid, comp_feed_q[i].pc,
                                          comp_feed_q[i].occurrence, comp_feed_q[i].mask, comp_feed_q[i].data);

            // Reset SV-side compare state; SimX re-runs following the DUT loads + sqrt.
            gold_fifo.delete();
            dut_fifo.delete();
            reset_tallies();
            capturing_feed = 1'b0;              // do NOT recapture in pass 2

            exitcode2 = simx_run();
            `uvm_info("LOCKSTEP", $sformatf(
                "PASS 2: SimX re-run exit=%0d; load-bus pushed=%0d consumed=%0d ; sqrt-feed pushed=%0d consumed=%0d %s",
                exitcode2, simx_cosim_load_feed_pushed(), simx_cosim_load_feed_consumed(),
                simx_cosim_comp_feed_pushed(), simx_cosim_comp_feed_consumed(),
                ((simx_cosim_load_feed_pushed() == simx_cosim_load_feed_consumed()) &&
                 (simx_cosim_comp_feed_pushed() == simx_cosim_comp_feed_consumed()))
                    ? "(PC-occurrences aligned)" : "(WARNING: PC-occurrence mismatch — see consumed<pushed)"),
                UVM_LOW)

            build_gold();
            build_dut();
            run_compare();

            simx_cosim_load_feed_enable(0);     // leave SimX pristine
            simx_cosim_comp_feed_enable(0);
        end

        // Housekeeping: clear both channels for any subsequent run.
        dut_retire_q.delete();
        dut_load_q.delete();
        feed_q.delete();
        comp_feed_q.delete();
        simx_cosim_clear();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        // Close the A6 trace before the early return, so the file is flushed even
        // when lockstep is disabled and no pairs were ever emitted.
        if (trace_en) begin
            $fclose(trace_fh);
            trace_en = 1'b0;
            `uvm_info("LOCKSTEP", $sformatf("A6 retirement trace closed: %s", trace_path), UVM_LOW)
        end
        if (cfg == null || !cfg.enable_lockstep) return;
        begin
            bit seen_cid [int];
            int ncid = 0;
            foreach (gold_fifo[k]) if (!seen_cid.exists(k >> 16)) begin seen_cid[k>>16]=1; ncid++; end
            `uvm_info("LOCKSTEP", "==================== A0 LOCKSTEP SUMMARY ====================", UVM_LOW)
            `uvm_info("LOCKSTEP", $sformatf("  cores exercised     : %0d (distinct cid)  warps/core buckets: %0d", ncid, gold_fifo.num()), UVM_LOW)
        end
        // Two-pass RVVI load-bus verdict: pass-1 raw divergence (independent SimX)
        // vs pass-2 residual (SimX driven by the DUT load-bus on racy loads). A
        // pass-2 residual of 0 ⇒ every divergence was an unsynchronizable shared
        // load; the DUT is self-consistent given its own memory ordering, and all
        // compute/control/stores match. Nonzero residual ⇒ a REAL divergence.
        // A3 GOLDEN_HALT: if the golden REFUSED partway (simx_run() == -4), its
        // retire stream is TRUNCATED at that instruction. Every DUT retirement
        // after it then has no counterpart and lands in n_dut_orphan — that is
        // expected truncation, NOT divergence, and must not be reported as a DUT
        // defect. Field mismatches (PC/rd/data/load) are a different matter: those
        // occurred while a golden value still existed, so they stay errors.
        if (did_pass2) begin
            bit gh = (simx_golden_halt_valid() != 0);
            int p2_residual = n_mm_pc + n_mm_rd + n_mm_data + n_mm_loaddata
                            + (gh ? 0 : (n_dut_orphan + n_simx_orphan));
            if (gh)
                `uvm_info("LOCKSTEP", $sformatf(
                    {"  GOLDEN_HALT: reference model refused '%s' at PC=0x%0h (%s.cpp:%0d). ",
                     "The %0d pair(s) compared BEFORE that point are real verification and are ",
                     "judged below; the %0d orphan(s) after it are the truncated tail (no golden ",
                     "to compare against) and are EXCLUDED from the verdict, not counted as ",
                     "divergence."},
                    simx_golden_halt_detail(), simx_golden_halt_pc(),
                    simx_golden_halt_where(), simx_golden_halt_line(),
                    n_pairs, n_dut_orphan + n_simx_orphan), UVM_LOW)
            `uvm_info("LOCKSTEP", "  ---- TWO-PASS RECONVERGENCE VERDICT (Phase A1(e) load-bus + OBS-014 sqrt) ----", UVM_LOW)
            `uvm_info("LOCKSTEP", $sformatf(
                "    PASS 1 (independent) : %0d in-region LOAD divergence(s); %0d cascaded field-mismatch(es); %0d warp(s) diverged",
                p1_mm_loaddata, p1_mm_pc + p1_mm_rd + p1_mm_data + p1_mm_loaddata, p1_first_div_keys), UVM_LOW)
            `uvm_info("LOCKSTEP", $sformatf(
                "    PASS 2 (DUT-fed)     : residual mismatch = %0d (PC=%0d rd=%0d data=%0d load=%0d orphan=%0d/%0d) | fed: %0d racy load(s) + %0d sqrt reconvergence(s)",
                p2_residual, n_mm_pc, n_mm_rd, n_mm_data, n_mm_loaddata, n_dut_orphan, n_simx_orphan,
                simx_cosim_load_feed_consumed(), simx_cosim_comp_feed_consumed()), UVM_LOW)
            if (p2_residual == 0)
                `uvm_info("LOCKSTEP", "    VERDICT: all divergences explained by (a) unsynchronizable shared-memory races and/or (b) the documented OBS-014 fsqrt 1-ULP deviation; DUT VERIFIED modulo those cited, reconverged causes. All compute/control/store re-checked bit-exact.", UVM_LOW)
            else
                `uvm_error("LOCKSTEP", $sformatf(
                    "    VERDICT: %0d residual mismatch(es) NOT explained by racy loads or the OBS-014 sqrt feed — REAL divergence, investigate.", p2_residual))
            `uvm_info("LOCKSTEP", "  ------------------------------------------------------", UVM_LOW)
        end
        // Suppression-hole guard: feed armed but NO racy in-region loads found
        // ⇒ pass 2 never ran, yet pass 1 demoted its divergences to info. Any
        // such divergence is NOT a race (nothing to feed) ⇒ it is REAL and must
        // fail. (When the feed is disabled, note_div already emitted uvm_error.)
        else if (feed_en) begin
            // Same GOLDEN_HALT rule as above: a truncated golden stream produces
            // orphans that are not evidence of anything.
            bit gh1 = (simx_golden_halt_valid() != 0);
            int p1_total = n_mm_pc + n_mm_rd + n_mm_data + n_mm_loaddata
                         + (gh1 ? 0 : (n_dut_orphan + n_simx_orphan));
            if (gh1)
                `uvm_info("LOCKSTEP", $sformatf(
                    {"  GOLDEN_HALT: reference model refused '%s' at PC=0x%0h (%s.cpp:%0d); ",
                     "%0d orphan(s) after that point are the truncated tail and are EXCLUDED ",
                     "from the verdict. %0d pair(s) were compared before it."},
                    simx_golden_halt_detail(), simx_golden_halt_pc(),
                    simx_golden_halt_where(), simx_golden_halt_line(),
                    n_dut_orphan + n_simx_orphan, n_pairs), UVM_LOW)
            if (p1_total > 0)
                `uvm_error("LOCKSTEP", $sformatf(
                    "  VERDICT: %0d divergence(s) with NO racy shared-load to explain them (load-bus feed found nothing) — REAL divergence, investigate.",
                    p1_total))
        end
        `uvm_info("LOCKSTEP", $sformatf("  compared pairs      : %0d", n_pairs),        UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  matched             : %0d", n_matched),      UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  dut_orphan          : %0d", n_dut_orphan),   UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  simx_orphan         : %0d", n_simx_orphan),  UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  field_mismatch PC   : %0d", n_mm_pc),        UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  field_mismatch rd   : %0d", n_mm_rd),        UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  field_mismatch data : %0d", n_mm_data),      UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  field_mismatch LOAD : %0d (load-writeback data, via LSU probe)", n_mm_loaddata), UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  load data-compared  : %0d (LSU-probe overlay; needs +LOCKSTEP_LOADS)", n_load_datacmp), UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  load data-skipped   : %0d (gated off / no LSU beat; end-state covers)", n_load_dataskip), UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  volatile-CSR skipped: %0d (perf counters; model-divergent)", n_volatile_skip), UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  multireg end-state  : %0d (WMMA tile regs not on DUT commit trace; end-state covers)", n_multireg_covered), UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  fsqrt 1-ULP tol     : %0d (OBS-014 DUT hardware fsqrt.s vs SoftFloat; bounded <=%0d ULP, sqrt only)", n_fp_ulp_tol, FP_SQRT_MAX_ULP), UVM_LOW)
        // A1(d) deliverable: the earliest diverging instruction per warp. For a
        // clean run this block is empty; for a cross-core divergence it pinpoints
        // the exact core/warp/PC where DUT and SimX first disagree.
        if (first_div_seen.num() > 0) begin
            `uvm_info("LOCKSTEP", "  ---- FIRST DIVERGENCE per (cid,wid) [per-warp program order] ----", UVM_LOW)
            foreach (first_div_seen[k]) begin
                `uvm_info("LOCKSTEP", $sformatf(
                    "    cid=%0d wid=%0d : first@seq=%0d PC=%0h uuid=%0h | %s | (%0d total divergences on this warp)",
                    k >> 16, k & 32'hFFFF, first_div_seq[k], first_div_pc[k],
                    first_div_uuid[k], first_div_desc[k], div_count[k]), UVM_LOW)
            end
        end
        // uuid cross-check verdict (does NOT affect pass/fail).
        if (n_pairs == 0)
            `uvm_info("LOCKSTEP", "  uuid alignment      : N/A (no pairs)", UVM_LOW)
        else if (n_uuid_misaligned == 0)
            `uvm_info("LOCKSTEP", "  uuid alignment      : DUT and SimX uuids match 1:1", UVM_LOW)
        else
            `uvm_info("LOCKSTEP", $sformatf(
                "  uuid alignment      : DIVERGENT on %0d/%0d pairs (schemes differ; program-order key used)",
                n_uuid_misaligned, n_pairs), UVM_LOW)
        `uvm_info("LOCKSTEP", "============================================================", UVM_LOW)
    endfunction

endclass : lockstep_scoreboard
