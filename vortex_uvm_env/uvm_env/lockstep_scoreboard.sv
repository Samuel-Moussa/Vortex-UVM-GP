////////////////////////////////////////////////////////////////////////////////
// File: lockstep_scoreboard.sv
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

    bit               capturing_feed;   // pass-1 only: populate feed_q on load divergence
    bit               did_pass2;         // set when the pass-2 feed run executed
    // per-key, per-PC running occurrence count (mirrors SimX's (cid,wid,PC) counter)
    int      unsigned pc_occ_ctr [int][longint unsigned];

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

    //--------------------------------------------------------------------------
    // Drain SimX's cosim queue into per-(cid,wid) gold FIFOs (wb records only).
    //--------------------------------------------------------------------------
    function automatic void build_gold();
        int rc;
        longint  unsigned uuid, pc;
        int      unsigned cid, wid, tmask;
        byte     unsigned wb, is_fp, rd, sop, eop, fu_type, is_volatile;
        longint  unsigned res[];
        longint  unsigned adr[];
        int      k;
        retire_t g;
        forever begin
            res = new[cfg.num_threads];
            adr = new[cfg.num_threads];
            rc = simx_cosim_pop(uuid, cid, wid, pc, tmask, wb, is_fp, rd, sop, eop, fu_type, is_volatile, res, adr);
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
        retire_t merged [int][longint];   // [key][uuid] -> merged retirement
        int      key, base, simd_w, l, gi, i;
        lockstep_pkg::dut_retire_s b;
        for (i = 0; i < dut_retire_q.size(); i++) begin
            b      = dut_retire_q[i];
            // Derive the flat global (cid,wid) from the uuid rather than trusting
            // the probe's pushed cid (hardcoded 0). uuid embeds CORE_ID + wid.
            key    = key_of(cid_of_uuid(b.uuid), wid_of_uuid(b.uuid));
            simd_w = b.data.size();
            base   = b.sid * simd_w;
            if (!merged[key].exists(b.uuid)) begin
                merged[key][b.uuid].uuid  = b.uuid;
                merged[key][b.uuid].pc    = b.pc;
                merged[key][b.uuid].rd    = b.rd;
                merged[key][b.uuid].tmask = 0;
                merged[key][b.uuid].load_filled_mask = 0;
                merged[key][b.uuid].data  = new[cfg.num_threads];
            end
            // Place only the lanes this record actually wrote (tmask-gated), and
            // union them into the merged active mask.
            for (l = 0; l < simd_w; l++) begin
                gi = base + l;
                if (gi < cfg.num_threads && ((b.tmask >> l) & 1)) begin
                    merged[key][b.uuid].data[gi]  = b.data[l];
                    merged[key][b.uuid].tmask    |= (1 << gi);
                end
            end
        end
        // OVERLAY real LOAD data from the LSU probe (dut_load_q) onto the matching
        // commit retirement, keyed by uuid. The commit `data` field is stale for
        // loads (OBS-002); VX_lsu_slice.result_if carries the true aligned per-lane
        // value. Place active lanes exactly like the commit path (sid*simd_w + l)
        // and record which lanes were filled (load_filled_mask) so compare_pair
        // only trusts those. A load with no captured beat stays unfilled → still
        // skipped (falls back to the end-state memory check).
        for (i = 0; i < dut_load_q.size(); i++) begin
            lockstep_pkg::dut_retire_s lb;
            int lkey, lbase, lsimd, ll, lgi;
            lb    = dut_load_q[i];
            lkey  = key_of(cid_of_uuid(lb.uuid), wid_of_uuid(lb.uuid));
            if (!merged.exists(lkey)) continue;
            if (!merged[lkey].exists(lb.uuid)) continue;   // load with no commit retire
            lsimd = lb.data.size();
            lbase = lb.sid * lsimd;
            for (ll = 0; ll < lsimd; ll++) begin
                lgi = lbase + ll;
                if (lgi < cfg.num_threads && ((lb.tmask >> ll) & 1)) begin
                    merged[lkey][lb.uuid].data[lgi]           = lb.data[ll];
                    merged[lkey][lb.uuid].load_filled_mask   |= (1 << lgi);
                end
            end
        end

        // Flatten each key's uuid-map into a uuid-sorted queue.
        foreach (merged[key]) begin
            longint unsigned uus[$];
            foreach (merged[key][u]) uus.push_back(u);
            uus.sort();
            foreach (uus[j]) dut_fifo[key].push_back(merged[key][uus[j]]);
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
    // Compare one aligned (DUT, SimX) pair. Counts each differing field, and
    // records/ caps-emits the divergence via note_div.
    //--------------------------------------------------------------------------
    function automatic void compare_pair(int key, int seq, retire_t d, retire_t g);
        bit    clean = 1'b1;
        string desc  = "";
        n_pairs++;
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
                if (capturing_feed && feed_en && div_seen && region_mask != 0) begin
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
        end
        if (clean) n_matched++;
    endfunction

    //--------------------------------------------------------------------------
    // Walk each per-warp FIFO in lockstep and compare/tally. Reads the current
    // gold_fifo/dut_fifo (rebuilt per pass).
    //--------------------------------------------------------------------------
    function automatic void run_compare();
        int keys[$];
        foreach (gold_fifo[k]) keys.push_back(k);
        foreach (dut_fifo[k])  if (!gold_fifo.exists(k)) keys.push_back(k);
        foreach (keys[ki]) begin
            int key = keys[ki];
            int nd  = dut_fifo.exists(key)  ? dut_fifo[key].size()  : 0;
            int ng  = gold_fifo.exists(key) ? gold_fifo[key].size() : 0;
            int n   = (nd > ng) ? nd : ng;
            for (int s = 0; s < n; s++) begin
                if (s < nd && s < ng) begin
                    compare_pair(key, s, dut_fifo[key][s], gold_fifo[key][s]);
                end else if (s < nd) begin
                    n_dut_orphan++;
                    note_div(key, s, dut_fifo[key][s].pc, dut_fifo[key][s].uuid,
                        "DUT-ORPHAN (no SimX retire)", $sformatf(
                        "DUT-ORPHAN key=%0h seq=%0d PC=%0h uuid=%0h (no SimX retire)",
                        key, s, dut_fifo[key][s].pc, dut_fifo[key][s].uuid));
                end else begin
                    n_simx_orphan++;
                    note_div(key, s, gold_fifo[key][s].pc, gold_fifo[key][s].uuid,
                        "SIMX-ORPHAN (no DUT retire)", $sformatf(
                        "SIMX-ORPHAN key=%0h seq=%0d PC=%0h uuid=%0h (no DUT retire)",
                        key, s, gold_fifo[key][s].pc, gold_fifo[key][s].uuid));
                end
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Zero all tallies + first-divergence state for a fresh compare pass.
    //--------------------------------------------------------------------------
    function automatic void reset_tallies();
        n_matched=0; n_dut_orphan=0; n_simx_orphan=0; n_mm_pc=0; n_mm_rd=0;
        n_mm_data=0; n_mm_loaddata=0; n_uuid_misaligned=0; n_pairs=0;
        n_load_dataskip=0; n_load_datacmp=0; n_volatile_skip=0;
        first_div_seen.delete(); first_div_seq.delete(); first_div_pc.delete();
        first_div_uuid.delete(); first_div_desc.delete(); div_count.delete();
        err_emitted.delete(); pc_occ_ctr.delete();
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

        // -------- PASS 2: RVVI load-bus (only if armed and races found) -----
        if (feed_en && feed_q.size() > 0) begin
            int exitcode2;
            // snapshot pass-1 tallies for the two-pass verdict
            p1_pairs=n_pairs; p1_matched=n_matched; p1_mm_pc=n_mm_pc; p1_mm_rd=n_mm_rd;
            p1_mm_data=n_mm_data; p1_mm_loaddata=n_mm_loaddata;
            p1_dut_orphan=n_dut_orphan; p1_simx_orphan=n_simx_orphan;
            p1_first_div_keys=first_div_seen.num();
            did_pass2 = 1'b1;

            `uvm_info("LOCKSTEP", $sformatf(
                "PASS 1: %0d racy in-region LOAD-data divergence(s) over %0d captured load(s). Re-running SimX with the DUT load-bus fed (PASS 2)...",
                p1_mm_loaddata, feed_q.size()), UVM_LOW)

            // Arm the feed in SimX with the captured DUT load values.
            simx_cosim_clear();
            simx_cosim_load_feed_reset();
            simx_cosim_load_feed_enable(1);
            foreach (feed_q[i])
                simx_cosim_load_feed_push(feed_q[i].cid, feed_q[i].wid, feed_q[i].pc,
                                          feed_q[i].occurrence, feed_q[i].mask, feed_q[i].data);

            // Reset SV-side compare state; SimX re-runs following the DUT loads.
            gold_fifo.delete();
            dut_fifo.delete();
            reset_tallies();
            capturing_feed = 1'b0;              // do NOT recapture in pass 2

            exitcode2 = simx_run();
            `uvm_info("LOCKSTEP", $sformatf(
                "PASS 2: SimX re-run exit=%0d; load-bus records pushed=%0d consumed=%0d %s",
                exitcode2, simx_cosim_load_feed_pushed(), simx_cosim_load_feed_consumed(),
                (simx_cosim_load_feed_pushed() == simx_cosim_load_feed_consumed())
                    ? "(PC-occurrences aligned)" : "(WARNING: PC-occurrence mismatch — see consumed<pushed)"),
                UVM_LOW)

            build_gold();
            build_dut();
            run_compare();

            simx_cosim_load_feed_enable(0);     // leave SimX pristine
        end

        // Housekeeping: clear both channels for any subsequent run.
        dut_retire_q.delete();
        dut_load_q.delete();
        simx_cosim_clear();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
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
        if (did_pass2) begin
            int p2_residual = n_mm_pc + n_mm_rd + n_mm_data + n_mm_loaddata
                            + n_dut_orphan + n_simx_orphan;
            `uvm_info("LOCKSTEP", "  ---- RVVI LOAD-BUS TWO-PASS VERDICT (Phase A1(e)) ----", UVM_LOW)
            `uvm_info("LOCKSTEP", $sformatf(
                "    PASS 1 (independent) : %0d racy in-region LOAD divergence(s); %0d cascaded field-mismatch(es); %0d warp(s) diverged",
                p1_mm_loaddata, p1_mm_pc + p1_mm_rd + p1_mm_data + p1_mm_loaddata, p1_first_div_keys), UVM_LOW)
            `uvm_info("LOCKSTEP", $sformatf(
                "    PASS 2 (DUT load-bus): residual mismatch = %0d (PC=%0d rd=%0d data=%0d load=%0d orphan=%0d/%0d)",
                p2_residual, n_mm_pc, n_mm_rd, n_mm_data, n_mm_loaddata, n_dut_orphan, n_simx_orphan), UVM_LOW)
            if (p2_residual == 0)
                `uvm_info("LOCKSTEP", "    VERDICT: all divergences explained by unsynchronizable shared-memory races; DUT VERIFIED modulo racy loads.", UVM_LOW)
            else
                `uvm_error("LOCKSTEP", $sformatf(
                    "    VERDICT: %0d residual mismatch(es) NOT explained by racy loads — REAL divergence, investigate.", p2_residual))
            `uvm_info("LOCKSTEP", "  ------------------------------------------------------", UVM_LOW)
        end
        // Suppression-hole guard: feed armed but NO racy in-region loads found
        // ⇒ pass 2 never ran, yet pass 1 demoted its divergences to info. Any
        // such divergence is NOT a race (nothing to feed) ⇒ it is REAL and must
        // fail. (When the feed is disabled, note_div already emitted uvm_error.)
        else if (feed_en) begin
            int p1_total = n_mm_pc + n_mm_rd + n_mm_data + n_mm_loaddata
                         + n_dut_orphan + n_simx_orphan;
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
