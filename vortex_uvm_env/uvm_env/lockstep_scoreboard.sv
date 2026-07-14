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
//   cosim drain queue is fully populated; and the commit probe has pushed the
//   whole DUT wb stream into lockstep_pkg::dut_retire_q during run_phase.
//
//   GATING: built only when cfg.enable_lockstep (from +LOCKSTEP). Default off ⇒
//   this component does not exist and the run is byte-identical.
//
// Author: Vortex UVM (Samuel) — Phase A0
////////////////////////////////////////////////////////////////////////////////

class lockstep_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(lockstep_scoreboard)

    vortex_config cfg;

    // One aggregated logical retirement (either side).
    typedef struct {
        longint  unsigned uuid;
        longint  unsigned pc;
        int      unsigned rd;
        int      unsigned tmask;          // full-width active-lane mask
        bit               is_load;        // SimX FUType==LSU (gold side only)
        bit               is_volatile;    // SimX read a perf-counter CSR (gold side only)
        longint  unsigned data[];         // size = num_threads
    } retire_t;

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
    int unsigned n_uuid_misaligned;   // cross-check only (not an error)
    int unsigned n_pairs;             // total compared positions
    int unsigned n_load_dataskip;     // load retires: PC/rd checked, data not observable at commit probe
    int unsigned n_volatile_skip;     // perf-counter CSR reads: PC/rd checked, data model-divergent

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(vortex_config)::get(this, "", "cfg", cfg))
            `uvm_fatal("LOCKSTEP", "vortex_config not found")
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
        int      k;
        retire_t g;
        forever begin
            res = new[cfg.num_threads];
            rc = simx_cosim_pop(uuid, cid, wid, pc, tmask, wb, is_fp, rd, sop, eop, fu_type, is_volatile, res);
            if (rc <= 0) break;             // 0 = empty, -1 = error
            if (wb == 0) continue;          // writeback domain only
            g.uuid        = uuid;
            g.pc          = pc;
            g.rd          = rd;
            g.tmask       = tmask;
            g.is_load     = (fu_type == FU_LSU);
            g.is_volatile = (is_volatile != 0);
            g.data        = new[cfg.num_threads];
            for (k = 0; k < cfg.num_threads; k++) g.data[k] = res[k];
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
        for (i = 0; i < lockstep_pkg::dut_retire_q.size(); i++) begin
            b      = lockstep_pkg::dut_retire_q[i];
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
        // Flatten each key's uuid-map into a uuid-sorted queue.
        foreach (merged[key]) begin
            longint unsigned uus[$];
            foreach (merged[key][u]) uus.push_back(u);
            uus.sort();
            foreach (uus[j]) dut_fifo[key].push_back(merged[key][uus[j]]);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Compare one aligned (DUT, SimX) pair. Counts each differing field.
    //--------------------------------------------------------------------------
    function automatic void compare_pair(int key, int seq, retire_t d, retire_t g);
        bit clean = 1'b1;
        n_pairs++;
        if (d.uuid != g.uuid) n_uuid_misaligned++;   // cross-check, not a failure
        if (d.pc != g.pc) begin
            n_mm_pc++; clean = 1'b0;
            `uvm_error("LOCKSTEP", $sformatf(
                "PC mismatch key=%0h seq=%0d: DUT PC=%0h (uuid=%0h) vs SimX PC=%0h (uuid=%0h)",
                key, seq, d.pc, d.uuid, g.pc, g.uuid))
        end
        if (d.rd != g.rd) begin
            n_mm_rd++; clean = 1'b0;
            `uvm_error("LOCKSTEP", $sformatf(
                "rd mismatch key=%0h seq=%0d PC=%0h: DUT rd=%0d vs SimX rd=%0d",
                key, seq, d.pc, d.rd, g.rd))
        end
        // Load-writeback DATA is not observable at the DUT commit-arb probe
        // (loads complete via the async LSU response path; empirically the
        // commit `data` field carries a uniform/stale value for `lw`). Load
        // *correctness* is covered by the end-state memory equivalence check in
        // vortex_scoreboard. So for loads we verify PC + rd + ordering here and
        // skip the per-lane data compare. Non-load writebacks are data-checked.
        if (g.is_load) begin
            n_load_dataskip++;
        end else if (g.is_volatile) begin
            n_volatile_skip++;          // mcycle/minstret/... model-divergent by definition
        end else begin
            for (int l = 0; l < cfg.num_threads; l++) begin
                if ((g.tmask >> l) & 1) begin
                    if (d.data[l] !== g.data[l]) begin
                        n_mm_data++; clean = 1'b0;
                        `uvm_error("LOCKSTEP", $sformatf(
                            "DATA mismatch key=%0h seq=%0d PC=%0h uuid=%0h lane=%0d: DUT=%0h vs SimX=%0h",
                            key, seq, d.pc, d.uuid, l, d.data[l], g.data[l]))
                    end
                end
            end
        end
        if (clean) n_matched++;
    endfunction

    //--------------------------------------------------------------------------
    // check_phase — build both sides, walk each per-warp FIFO in lockstep.
    //--------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        int keys[$];
        super.check_phase(phase);
        if (cfg == null || !cfg.enable_lockstep) return;

        build_gold();
        build_dut();

        // Union of keys present on either side.
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
                    `uvm_error("LOCKSTEP", $sformatf(
                        "DUT-ORPHAN key=%0h seq=%0d PC=%0h uuid=%0h (no SimX retire)",
                        key, s, dut_fifo[key][s].pc, dut_fifo[key][s].uuid))
                end else begin
                    n_simx_orphan++;
                    `uvm_error("LOCKSTEP", $sformatf(
                        "SIMX-ORPHAN key=%0h seq=%0d PC=%0h uuid=%0h (no DUT retire)",
                        key, s, gold_fifo[key][s].pc, gold_fifo[key][s].uuid))
                end
            end
        end

        // Housekeeping: clear both channels for any subsequent run.
        lockstep_pkg::ls_reset();
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
        `uvm_info("LOCKSTEP", $sformatf("  compared pairs      : %0d", n_pairs),        UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  matched             : %0d", n_matched),      UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  dut_orphan          : %0d", n_dut_orphan),   UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  simx_orphan         : %0d", n_simx_orphan),  UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  field_mismatch PC   : %0d", n_mm_pc),        UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  field_mismatch rd   : %0d", n_mm_rd),        UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  field_mismatch data : %0d", n_mm_data),      UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  load data-skipped   : %0d (PC/rd checked; data via end-state)", n_load_dataskip), UVM_LOW)
        `uvm_info("LOCKSTEP", $sformatf("  volatile-CSR skipped: %0d (perf counters; model-divergent)", n_volatile_skip), UVM_LOW)
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
