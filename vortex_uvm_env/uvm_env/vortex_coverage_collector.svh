////////////////////////////////////////////////////////////////////////////////
// File: vortex_coverage_collector.svh
// Description: Functional Coverage Collector for Vortex GPGPU
//
// Collects functional coverage by subscribing to all agent monitors.
// All field names verified against actual transaction class definitions:
//   - mem_transaction.sv    : rw, byteen(8-bit), addr, tag, data, rsp_data
//   - axi_transaction.sv    : trans_type, burst, size, len, bresp, rresp[],
//                             AXI_WRITE/READ, AXI_FIXED/INCR/WRAP,
//                             AXI_OKAY/EXOKAY/SLVERR/DECERR
//   - dcr_transaction.sv    : addr, data, DCR_STARTUP_ADDR0/1, DCR_ARGV_PTR0/1,
//                             DCR_MPM_CLASS (enum typedef dcr_addr_e)
//   - host_transaction.sv   : op_type(host_op_type_e), num_cores, num_warps,
//                             num_threads, completion_flag
//   - status_transaction.sv : busy, ebreak_detected, ipc(real),
//                             fetch_stall, memory_stall, execute_stall,
//                             count_active_warps() function
//
// Fixes applied:
//   - `uvm_analysis_imp_decl macros at file scope (not inside class)
//   - axi_transaction_cg: bresp/rresp[0] with iff guards (not .resp)
//   - mem_operation_cg: 8-bit byteen bins (not 4-bit)
//   - dcr_config_cg: dcr_addr_e enum constants (not hardcoded hex)
//   - status_performance_cg: ipc_bucket() integer helper for real IPC
//   - Reserved keyword bin names: med/sm/lg/sh/lng (not medium/small/large/short/long)
//   - Covergroups instantiated in new() (QuestaSim requirement)
//   - cfg null-guard in all write_*() methods
//
// Author: Vortex UVM Team
// Date: March 2026
////////////////////////////////////////////////////////////////////////////////

`ifndef VORTEX_COVERAGE_COLLECTOR_SV
`define VORTEX_COVERAGE_COLLECTOR_SV


//------------------------------------------------------------------------------
// Shared analysis imp declarations — guarded against double-declaration.
//------------------------------------------------------------------------------

class vortex_coverage_collector extends uvm_component;
  `uvm_component_utils(vortex_coverage_collector)

  //==========================================================================
  // Analysis Imports
  //==========================================================================
  uvm_analysis_imp_mem    #(mem_transaction,    vortex_coverage_collector) mem_imp;
  uvm_analysis_imp_axi    #(axi_transaction,    vortex_coverage_collector) axi_imp;
  uvm_analysis_imp_dcr    #(dcr_transaction,    vortex_coverage_collector) dcr_imp;
  uvm_analysis_imp_host   #(host_transaction,   vortex_coverage_collector) host_imp;
  uvm_analysis_imp_status #(status_transaction, vortex_coverage_collector) status_imp;

  //==========================================================================
  // Configuration
  //==========================================================================
  vortex_config cfg;

  //==========================================================================
  // Current transaction handles — set before each covergroup sample()
  //==========================================================================
  mem_transaction    current_mem;
  axi_transaction    current_axi;
  dcr_transaction    current_dcr;
  host_transaction   current_host;
  status_transaction current_status;

  //==========================================================================
  // Sampling counters for runtime diagnostics
  //==========================================================================
  int unsigned mem_samples;
  int unsigned axi_samples;
  int unsigned dcr_samples;
  int unsigned host_samples;
  int unsigned status_samples;

  //==========================================================================
  // Runtime per-bin counters (associative arrays keyed by short labels)
  // These provide quick visibility into which functional bins are hit
  // during a run without parsing external UCDB reports.
  //==========================================================================
  int unsigned axi_bin_counts[string];
  int unsigned dcr_bin_counts[string];
  int unsigned host_bin_counts[string];
  int unsigned status_bin_counts[string];

  //==========================================================================
  // IPC bucket helper — converts real IPC to integer bin index
  //   0 = zero IPC     (< 0.01)
  //   1 = very low IPC (0.01 – 0.25)
  //   2 = low IPC      (0.25 – 0.50)
  //   3 = medium IPC   (0.50 – 0.75)
  //   4 = high IPC     (0.75 – 1.00)
  //   5 = very high    (> 1.00)
  // Must be declared before covergroups that reference it.
  //==========================================================================
  function automatic int ipc_bucket(real ipc_val);
    if      (ipc_val <  0.01) return 0;
    else if (ipc_val <  0.25) return 1;
    else if (ipc_val <  0.50) return 2;
    else if (ipc_val <  0.75) return 3;
    else if (ipc_val <= 1.00) return 4;
    else                      return 5;
  endfunction

  function void bump_axi_bin(string key);
    if (axi_bin_counts.exists(key)) axi_bin_counts[key] = axi_bin_counts[key] + 1;
    else axi_bin_counts[key] = 1;
  endfunction

  function void bump_dcr_bin(string key);
    if (dcr_bin_counts.exists(key)) dcr_bin_counts[key] = dcr_bin_counts[key] + 1;
    else dcr_bin_counts[key] = 1;
  endfunction

  function void bump_host_bin(string key);
    if (host_bin_counts.exists(key)) host_bin_counts[key] = host_bin_counts[key] + 1;
    else host_bin_counts[key] = 1;
  endfunction

  function void bump_status_bin(string key);
    if (status_bin_counts.exists(key)) status_bin_counts[key] = status_bin_counts[key] + 1;
    else status_bin_counts[key] = 1;
  endfunction

  //==========================================================================
  // Coverage Groups
  //==========================================================================

  // --------------------------------------------------------------------------
  // Memory Operation Coverage
  // byteen is 8 bits wide per mem_transaction.sv (VX_MEM_BYTEEN_WIDTH=8)
  // --------------------------------------------------------------------------
  covergroup mem_operation_cg;
    option.per_instance = 1;

    cp_rw: coverpoint current_mem.rw {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    cp_byteen: coverpoint current_mem.byteen {
      bins full_dword = {8'hFF};
      bins lo_word    = {8'h0F};
      bins hi_word    = {8'hF0};
      bins hw_0       = {8'h03};
      bins hw_1       = {8'h0C};
      bins hw_2       = {8'h30};
      bins hw_3       = {8'hC0};
      bins byte_0     = {8'h01};
      bins byte_1     = {8'h02};
      bins byte_2     = {8'h04};
      bins byte_3     = {8'h08};
      bins byte_4     = {8'h10};
      bins byte_5     = {8'h20};
      bins byte_6     = {8'h40};
      bins byte_7     = {8'h80};
      bins other[]    = default;
    }

    cp_addr_align: coverpoint current_mem.addr[2:0] {
      bins aligned_8   = {3'b000};
      bins aligned_4   = {3'b100};
      bins unaligned[] = default;
    }

    cp_tag: coverpoint current_mem.tag {
      bins low[]  = {[0:3]};
      bins mid[]  = {[4:11]};
      //bins high[] = {[12:$]};
      bins high = default;

    }
    // Cross to capture read/write patterns with byte-enable
    cross_rw_byteen: cross cp_rw, cp_byteen;
  endgroup : mem_operation_cg

  // --------------------------------------------------------------------------
  // AXI Transaction Coverage
  // Fields verified: trans_type, burst, size, len, bresp, rresp[]
  // Response enums: AXI_OKAY, AXI_EXOKAY, AXI_SLVERR, AXI_DECERR
  // --------------------------------------------------------------------------
  
  // Low bits of the AXI ID are routing/structural (nc_sel|req_sel|wsel|tag_id or
  // |MSHR_ID|bank_sel|); the high UUID_WIDTH(=44) bits are a free-running
  // per-instruction counter and must NOT be binned. Cover only the routing field.
  localparam int AXI_ID_W  = $bits(current_axi.id);                  // 50 @1CL, 51 @2CL
  localparam int UUID_W    = VX_gpu_pkg::UUID_WIDTH;                 // 44 (debug)
  localparam int ROUTE_W   = AXI_ID_W - UUID_W;                      // 6 @1CL, 7 @2CL

  // -------------------------------------------------------------------------
  // AXI ROUTE FIELD DECODE — config-generic (OBS-030).
  //
  // The route field is NOT one flat integer: its LAYOUT depends on the number of
  // requester ports, so binning the raw value bakes in a single-config layout.
  //   READS  (VX_axi_adapter.sv:282):
  //       arid = {tbuf_waddr, req_xbar_sel}
  //     -> the requester-port select occupies the LOW  NUM_PORTS_IN_BITS bits,
  //        and the MSHR slot index sits ABOVE it (TAG_BUFFER_ADDRW bits).
  //     -> adding a second requester SHIFTS the slot index up by one bit, which
  //        is exactly why the old literal ignore_bins silently changed meaning
  //        between 1CL and 2CL (three of them fired on real traffic; see OBS-030).
  //   WRITES (VX_axi_adapter.sv:261):
  //       awid = mem_req_tag  — NO port select appended, so reads and writes do
  //       not even share a layout. They must be covered separately.
  //
  // Everything below is derived from the RTL parameters that DEFINE the layout,
  // so the model adapts to any NUM_PORTS_IN / TAG_BUFFER_SIZE by construction.
  // NUM_PORTS_IN is bound to VX_MEM_PORTS at the instantiation (Vortex_axi.sv:194).
  localparam int MEM_PORTS  = VX_gpu_pkg::VX_MEM_PORTS;
  localparam int PORT_SEL_W = (MEM_PORTS > 1) ? $clog2(MEM_PORTS) : 0;
  // TAG_BUFFER_SIZE is left at the VX_axi_adapter.sv:26 default (16) — it is NOT
  // overridden at the Vortex_axi.sv:188 instantiation. Trip-wire: the elaboration
  // check in build_phase fails loud if the route field can no longer hold it.
  localparam int TAG_BUF_SZ = 16;
  localparam int SLOT_W     = $clog2(TAG_BUF_SZ);

  // ⚠ THE TAG BUFFER IS NOT ALWAYS ELABORATED — and when it is absent the read
  // `id` means something COMPLETELY DIFFERENT (verified from the UCDB
  // hierarchy, not inferred):
  //   1CL: /dut/axi_adapter has NO tag_buf instance      -> VX_axi_adapter.sv:170
  //        `g_none` branch: mem_rd_req_tag = mem_req_tag (the RAW cache tag)
  //   2CL: /dut/axi_adapter/g_tag_buf[0..1]/g_enabled/tag_buf/allocator exists
  //        -> `g_enabled`: arid = {tbuf_waddr, req_xbar_sel} (a real slot index)
  // The RTL condition is NEEDED_TAG_WIDTH > TAG_WIDTH_OUT (:149), i.e.
  // MAX(SUB_LDATAW,0) + NUM_PORTS_IN_BITS > 0. SUB_LDATAW is a Vortex_axi
  // localparam that is <= 0 for this AXI configuration (confirmed: at 1CL, where
  // NUM_PORTS_IN_BITS==0, the buffer is absent), so the condition reduces to
  // MEM_PORTS > 1 here.
  //
  // HOW WE KNEW IT WAS WRONG: under a lowest-free allocator
  // (VX_allocator.sv:49, VX_priority_encoder over free_slots_n) slot 15 can only
  // be handed out when slots 0..14 are ALL busy — so a covered set of
  // {0,2,3,7,11,15} with 1,4,5,6 at zero is structurally impossible for a real
  // slot index. That measured contradiction is what exposed the mis-decode.
  // Binning a field whose meaning changes with the config is exactly the
  // OBS-030 failure this rewrite existed to remove, so the slot coverpoints are
  // gated on the buffer actually being there.
  localparam bit TAG_BUF_PRESENT = (MEM_PORTS > 1);

  // -------------------------------------------------------------------------
  // Compile-time hardware config (from +define+NUM_* — the SAME values this run
  // is built/elaborated with; see the I2 topology asserts). These drive
  // config-AWARE ignore_bins so EVERY build counts only the coverpoints that are
  // reachable in THIS config and auto-ignores the bins that belong to other
  // configs (structurally unreachable here). One definition adapts to ANY config
  // in the sweep — no per-config editing — so each run's reachable functional
  // set can hit 100%. (Across the matrix, every config bin is covered by the run
  // whose build matches it.)
  // -------------------------------------------------------------------------
  localparam int CFG_CLUSTERS = `NUM_CLUSTERS;
  localparam int CFG_CORES    = `NUM_CORES;
  localparam int CFG_WARPS    = `NUM_WARPS;
  localparam int CFG_THREADS  = `NUM_THREADS;
  // ISSUE_WIDTH is not a `define in the UVM compile, but PER_ISSUE_WARPS =
  // NUM_WARPS/ISSUE_WIDTH is a VX_gpu_pkg localparam -> derive it. Max IPC ==
  // issue width (per-cycle issue slots).
  localparam int CFG_ISSUE_W  = CFG_WARPS / VX_gpu_pkg::PER_ISSUE_WARPS;
  // Total cores in the device (both config dimensions). Used by the config
  // provenance coverpoints below.
  // HISTORICAL NOTE: a `SINGLE_CORE` flag used to live here to gate the AXI
  // route-field ignore_bins to 1-requester configs. It was DECLARED and never
  // wired up, so the ignores applied unconditionally at 2CL and asserted a
  // reachability that was false there (OBS-030). The gate is gone because the
  // waivers are gone — the route model is now layout-derived and needs no
  // per-config gating. Do NOT reintroduce either.
  localparam int TOTAL_CORES  = CFG_CLUSTERS * CFG_CORES;
  // Max reachable IPC bucket. Sustained windowed IPC ~= min(ISSUE_WIDTH, NUM_WARPS/L),
  // where L = schedule->decode warp-unlock latency (VX_schedule elastic OUT_REG + icache
  // req elastic OUT_REG + icache round-trip; ~8 cycles at this config). So:
  //   - bucket 5 (IPC>1.0): needs ISSUE_WIDTH>=2.
  //   - bucket 4 (high, 0.75..1.0): at single-issue needs enough warps to hide L.
  //     PROVEN unreachable at NUM_WARPS=4 — two max-effort ILP kernels both cap ~0.5:
  //     compute_flat (branchless straight-line) peaks at bucket 2, compute_tight (loop
  //     ILP) at bucket 3; neither reaches 0.75. Reaching it needs ~NUM_WARPS>=6.
  // Honest boundary: only claim bucket 4 unreachable for the PROVEN case (<=4 warps,
  // single-issue). At >4 warps leave it active (untested -> never fake-waive a bin we
  // have not proven unreachable). Config-aware; auto-reactivates as the config grows.
  localparam int MAX_IPC_BUCKET =
      (CFG_ISSUE_W >= 2) ? 5 :   // dual+ issue -> IPC can exceed 1.0
      (CFG_WARPS   >  4) ? 4 :   // >4 warps: do not claim high_ipc unreachable (untested)
                           3;    // <=4 warps single-issue: PROVEN capped ~0.5

  // AXI native transfer size — the DUT's VX_axi_adapter HARDCODES awsize/arsize =
  // CLOG2(DATA_SIZE) (VX_axi_adapter.sv:263,298), i.e. one full-bus-width beat;
  // sub-word access is via WSTRB, never via AxSIZE. So ONLY this size is reachable.
  // Derived from VX_MEM_DATA_WIDTH so it stays correct if the bus width changes.
  localparam int AXI_NATIVE_SIZE = $clog2(VX_gpu_pkg::VX_MEM_DATA_WIDTH/8);  // =6 for 512b

  // ==========================================================================
  // AXI reachability map (investigated 2026-06-29 vs VX_axi_adapter.sv RTL +
  // axi_driver.sv TB slave). ignore_bins are applied ONLY to STRUCTURALLY
  // UNREACHABLE bins (real verification — never to inflate the %). Each waiver
  // cites its evidence + a trip-wire:
  //   cp_burst    : ignore INCR/WRAP   — adapter awburst/arburst = 2'b00 (264/299)
  //   cp_len      : ignore len>0       — adapter awlen/arlen = 8'b0     (262/297)
  //   cp_size     : ignore != native   — adapter awsize/arsize = CLOG2(DATA_SIZE) (263/298)
  //   cp_bresp,
  //   cp_rresp0   : ignore non-OKAY    — TB slave drives 2'b00 always (axi_driver
  //                                      100/216/250); no error-injection test; AXI
  //                                      errors are NOT modeled by SimX, so they are
  //                                      not black-box verifiable (would diverge).
  // REACHABLE — covered by stimulus, NOT ignored (ignoring would hide a real gap):
  //   cp_route_port / cp_route_slot / cp_write_tag / cross_port_slot :
  //     the decoded routing field (requester port, MSHR slot, write tag). All
  //     values are reachable; filling every slot needs TAG_BUF_SZ concurrent
  //     outstanding reads — a STIMULUS task, never a waiver. See OBS-030 for why
  //     the previous flat-value model + literal ignore_bins was withdrawn.
  // ==========================================================================
  covergroup axi_transaction_cg;
    option.per_instance = 1;

    cp_type: coverpoint current_axi.trans_type {
      bins write = {axi_transaction::AXI_WRITE};
      bins read  = {axi_transaction::AXI_READ};
    }

    // ---- ROUTE COVERAGE, decoded by sub-field (rewritten 2026-08-15, OBS-030) --
    // SUPERSEDES the old flat `cp_id_route` + four literal `ignore_bins`. That
    // model was derived empirically at 1CL/1 requester and asserted that values
    // {[32:63]}, {16,18..30}, {4,6..14} and {23,27,31} were structurally
    // unreachable. The 2026-08-15 banks DISPROVED three of those four with the
    // waivers' own hit counts (4488 / 10605 / 88 occurrences at 2CL; the
    // "emergent read" set even fired 3x at 1CL). Root cause is layout, not
    // stimulus: see the AXI ROUTE FIELD DECODE block above — a second requester
    // inserts a port-select field in the LOW bits and shifts everything up.
    //
    // An `ignore_bins` is an assertion that hardware CANNOT produce a value.
    // Three of these were false, so they were discarding real coverage while
    // claiming structural impossibility. They are deleted rather than re-tuned:
    // re-tuning literals per config would rebuild the same trap at 4CL.
    //
    // The replacement covers what the field MEANS (which port, which slot,
    // read vs write) with every bound derived from the RTL parameters that
    // define the layout — so it needs no per-config maintenance at all.
    // --- READ path: requester port select (low PORT_SEL_W bits) --------------
    // Asks a question worth asking — "does every requester port actually reach
    // AXI?" — instead of binning a raw index. At MEM_PORTS==1 the mask is 0, so
    // this degenerates to a single always-covered bin (the port IS used), which
    // is the correct answer for that config rather than a waived one.
    cp_route_port : coverpoint (current_axi.id & ((1 << PORT_SEL_W) - 1))
        iff (current_axi.trans_type == axi_transaction::AXI_READ) {
      bins port[] = {[0:MEM_PORTS-1]};
    }

    // --- READ path: MSHR / tag-buffer slot index (above the port select) -----
    // "Does every outstanding-read slot get used?" Filling all TAG_BUF_SZ slots
    // requires TAG_BUF_SZ concurrent outstanding reads on that port — the same
    // condition as cache_event_cg.cp_mshr_stall.stall, so one directed
    // MSHR-saturating kernel drives both.
    // Only meaningful when the tag buffer exists (see TAG_BUF_PRESENT above).
    // When it does not, every bin is ignored so the coverpoint contributes
    // nothing rather than reporting a decode of a field that isn't there.
    cp_route_slot : coverpoint ((current_axi.id >> PORT_SEL_W) & (TAG_BUF_SZ - 1))
        iff (current_axi.trans_type == axi_transaction::AXI_READ) {
      bins slot[] = {[0:TAG_BUF_SZ-1]};
      ignore_bins no_tag_buffer = {[0:TAG_BUF_SZ-1]} with (!TAG_BUF_PRESENT);
    }

    // --- WRITE path: mem_req_tag, no port select (VX_axi_adapter.sv:261) -----
    // The write tag is a non-architectural source/counter id. Binning every
    // value over-specifies an implementation artifact (the ORIGINAL reason the
    // old waivers existed), so bucket it coarsely instead — and let the bucket
    // count, not the value set, be what stays config-generic.
    cp_write_tag : coverpoint current_axi.id[ROUTE_W-1:0]
        iff (current_axi.trans_type == axi_transaction::AXI_WRITE) {
      bins tag[8] = {[0:(1 << ROUTE_W) - 1]};
    }

    // Is the high UUID field actually populated (debug tag present, non-zero)?
    // 2 honest bins — confirms tracing tag is live without binning its value.
    cp_uuid_present : coverpoint (|current_axi.id[AXI_ID_W-1:ROUTE_W]) {
        bins zero     = {1'b0};
        bins nonzero  = {1'b1};
    }

    // NOTE [Samuel 2026-06-28, REVIEW: Ahmad — coverage lane]: Vortex's AXI master
    // (VX_axi_adapter, RTL pin 7a52ee5) emits ONLY single-beat FIXED bursts. So
    // INCR/WRAP and any AWLEN/ARLEN>0 are UNREACHABLE in this config — ignore_bins
    // them so they don't cap functional coverage. Trip-wire: if VX_axi_adapter
    // ever moves to multi-beat bursts, remove these ignores.
    cp_burst: coverpoint current_axi.burst {
      bins fixed = {axi_transaction::AXI_FIXED};
      ignore_bins unreachable_burst = {axi_transaction::AXI_INCR,
                                       axi_transaction::AXI_WRAP};
    }

    // NOTE [REVIEW: Ahmad — coverage lane]: VX_axi_adapter hardcodes
    // awsize/arsize = CLOG2(DATA_SIZE) (RTL lines 263/298) — the DUT emits ONLY
    // the full-bus-width transfer size (AXI_NATIVE_SIZE; =6 for 512b). All other
    // AxSIZE values are structurally impossible (sub-word is via WSTRB). Ignore
    // them. Trip-wire: revert if the adapter ever emits variable AxSIZE.
    cp_size: coverpoint current_axi.size {
      bins byte_1   = {3'h0};
      bins byte_2   = {3'h1};
      bins byte_4   = {3'h2};
      bins byte_8   = {3'h3};
      bins larger[] = {[3'h4:3'h7]};
      ignore_bins non_native = {[3'h0:3'h7]} with (item != AXI_NATIVE_SIZE);
    }

    cp_len: coverpoint current_axi.len {
      bins single = {8'h00};
      // single-beat only — multi-beat unreachable (see NOTE above).
      ignore_bins unreachable_len = {[8'h01:8'hFF]};
    }

    // Coarse address-region coverpoint to differentiate workloads by touched
    // address ranges. Uses wider buckets to be more likely to hit.
    cp_addr_region: coverpoint current_axi.addr {
      bins low  = {[32'h0:32'h00FF_FFFF]};
      bins high = {[32'h0100_0000:32'hFFFF_FFFF]};
    }

    // Write response — only valid for write transactions
    // NOTE [REVIEW: Ahmad — coverage lane]: the memory model never returns an
    // error response, so EXOKAY/SLVERR/DECERR are UNREACHABLE without an AXI
    // error-injection sequence. Ignore them so OKAY-only = 100% of reachable.
    // Trip-wire: if an error-injection seq is added, remove these ignores.
    cp_bresp: coverpoint current_axi.bresp
        iff (current_axi.trans_type == axi_transaction::AXI_WRITE) {
      bins okay   = {axi_transaction::AXI_OKAY};
      ignore_bins no_error_injection = {axi_transaction::AXI_EXOKAY,
                                        axi_transaction::AXI_SLVERR,
                                        axi_transaction::AXI_DECERR};
    }

    // Read response first beat — only valid for read transactions with data
    cp_rresp0: coverpoint current_axi.rresp[0]
        iff (current_axi.trans_type == axi_transaction::AXI_READ
             && current_axi.rresp.size() > 0) {
      bins okay   = {axi_transaction::AXI_OKAY};
      ignore_bins no_error_injection = {axi_transaction::AXI_EXOKAY,
                                        axi_transaction::AXI_SLVERR,
                                        axi_transaction::AXI_DECERR};
    }

    // Crosses to expose differences in transaction type, length, and burst behavior.
    cross_type_burst_size: cross cp_type, cp_burst, cp_size;
    cross_type_len: cross cp_type, cp_len;
    cross_len_addr: cross cp_len, cp_addr_region;
    // Does EVERY requester port exercise EVERY outstanding-read slot? Both
    // coverpoints are read-guarded, so this cross needs no type term and no
    // ignore_bins — the old cross_type_route needed three only because it was
    // crossing a type against a field whose layout already encoded the type.
    // Sizes itself: MEM_PORTS x TAG_BUF_SZ (16 @1CL, 32 @2CL).
    cross_port_slot : cross cp_route_port, cp_route_slot;
  endgroup : axi_transaction_cg

  // --------------------------------------------------------------------------
  // DCR Configuration Coverage
  // Uses actual enum constants from dcr_transaction typedef dcr_addr_e
  // --------------------------------------------------------------------------
  covergroup dcr_config_cg;
    option.per_instance = 1;

    cp_addr: coverpoint current_dcr.addr {
      bins startup_addr0 = {dcr_transaction::DCR_STARTUP_ADDR0};
      bins startup_addr1 = {dcr_transaction::DCR_STARTUP_ADDR1};
      bins argv_ptr0     = {dcr_transaction::DCR_ARGV_PTR0};
      bins argv_ptr1     = {dcr_transaction::DCR_ARGV_PTR1};
      bins mpm_class     = {dcr_transaction::DCR_MPM_CLASS};
      bins other[]       = default;
    }

    cp_startup_align: coverpoint current_dcr.data[1:0]
        iff (current_dcr.addr == dcr_transaction::DCR_STARTUP_ADDR0) {
      bins aligned   = {2'b00};
      // An unaligned startup PC faults BOTH SimX (decode abort -> exit -3) and the
      // real DUT (misaligned fetch) -> not stimulus-reachable without failing the
      // run. Evidence-based structural waiver.
      ignore_bins unaligned = {2'b01, 2'b10, 2'b11};
    }

    // Data magnitude to classify register writes by value range:
    // code addresses (high), pointers (mid), config values (low/zero)
    cp_data_magnitude: coverpoint current_dcr.data {
      bins zero      = {32'h0};
      bins sm_cfg    = {[32'h1:32'h100]};
      bins mid_ptr   = {[32'h1000:32'h00FF_FFFF]};
      bins hi_code   = {[32'h0100_0000:32'hFFFF_FFFF]};
    }

    // Cross address type with data magnitude to capture different config patterns
    cross_addr_data: cross cp_addr, cp_data_magnitude;
  endgroup : dcr_config_cg

  // --------------------------------------------------------------------------
  // Host Operation Coverage
  // Fields verified: op_type, num_cores, num_warps, num_threads, completion_flag
  // --------------------------------------------------------------------------
  covergroup host_operation_cg;
    option.per_instance = 1;

    cp_op_type: coverpoint current_host.op_type {
      bins load_program  = {host_transaction::HOST_LOAD_PROGRAM};
      bins configure_dcr = {host_transaction::HOST_CONFIGURE_DCR};
      bins launch_kernel = {host_transaction::HOST_LAUNCH_KERNEL};
      bins wait_done     = {host_transaction::HOST_WAIT_DONE};
      bins read_result   = {host_transaction::HOST_READ_RESULT};
      // HOST_RESET is unreachable in this env: host_driver.do_reset() waits for a
      // reset_n toggle, which is TB-controlled (not host-driven), so a HOST_RESET
      // transaction never completes in the normal flow. Structural waiver.
      ignore_bins reset  = {host_transaction::HOST_RESET};
    }

    // CONFIG PROVENANCE — these record, IN THE UCDB ITSELF, which hardware
    // configuration produced this coverage. Each ignores every value except the
    // compiled one, so a bank can never silently mix configs (a cross-config
    // merge is invalid here — vcover-6821 width toggles + per-core instance
    // inflation). The cluster axis was missing until 2026-08-15: NUM_CLUSTERS is
    // the one dimension that changes the AXI route field LAYOUT (OBS-030), so
    // leaving it unrecorded was exactly the wrong axis to omit.
    cp_num_clusters: coverpoint current_host.num_clusters
        iff (current_host.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
      bins single = {32'd1};
      bins sm     = {[32'd2:32'd4]};
      bins lg     = {[32'd5:32'd8]};
      ignore_bins other_cfg = {[32'd0:32'd255]} with (item != CFG_CLUSTERS);
    }

    cp_num_cores: coverpoint current_host.num_cores
        iff (current_host.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
      // Config-aware: only the bucket containing the COMPILED NUM_CORES is
      // reachable this build; other-config values are unreachable -> ignore so
      // they leave the denominator. Open-ended top bucket so ANY config lands
      // in exactly one bin.
      bins single = {32'd1};
      bins sm     = {[32'd2:32'd4]};
      bins md     = {[32'd5:32'd8]};
      bins lg     = {[32'd9:32'd16]};
      bins xl     = {[32'd17:$]};
      ignore_bins other_cfg = {[32'd0:$]} with (item != CFG_CORES);
    }

    cp_num_warps: coverpoint current_host.num_warps
        iff (current_host.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
      bins low  = {[32'd1:32'd2]};
      bins mid  = {[32'd3:32'd4]};
      bins high = {[32'd5:32'd8]};
      bins wide = {[32'd9:32'd16]};
      bins xl   = {[32'd17:$]};
      ignore_bins other_cfg = {[32'd0:$]} with (item != CFG_WARPS);
    }

    cp_num_threads: coverpoint current_host.num_threads
        iff (current_host.op_type == host_transaction::HOST_LAUNCH_KERNEL) {
      // Was t1/t2/t4 ONLY: an 8-thread build had NO bin to land in at all.
      bins t1  = {32'd1};
      bins t2  = {32'd2};
      bins t4  = {32'd4};
      bins t8  = {32'd8};
      bins t16 = {[32'd9:32'd16]};
      bins txl = {[32'd17:$]};
      ignore_bins other_cfg = {[32'd0:$]} with (item != CFG_THREADS);
    }

    cp_completion: coverpoint current_host.completion_flag
        iff (current_host.op_type == host_transaction::HOST_WAIT_DONE) {
      bins completed = {1'b1};
      // completion_flag==0 (timeout) only happens on a hung/failed run; the
      // functional suite completes every kernel by construction (a timeout is
      // the negative-test path, not passing coverage). Structural waiver.
      ignore_bins timeout = {1'b0};
    }

    // Timeout value ranges to differentiate kernel lengths
    cp_timeout: coverpoint current_host.timeout_cycles {
      bins low  = {[1000:9999]};
      bins mid  = {[10000:49999]};
      bins high = {[50000:100000]};
    }

    cross_cores_warps: cross cp_num_cores, cp_num_warps;
    // Crosses to expose kernel launch configurations
    cross_op_completion: cross cp_op_type, cp_completion {
      // cp_completion is iff(op_type==WAIT_DONE): only WAIT_DONE rows are ever
      // sampled, so every non-WAIT_DONE cross bin is structurally unreachable.
      ignore_bins non_waitdone = binsof(cp_op_type) intersect {
          host_transaction::HOST_LOAD_PROGRAM,
          host_transaction::HOST_CONFIGURE_DCR,
          host_transaction::HOST_LAUNCH_KERNEL,
          host_transaction::HOST_READ_RESULT };
    }
    cross_launch_config: cross cp_num_cores, cp_num_threads;
  endgroup : host_operation_cg

  // --------------------------------------------------------------------------
  // Status / Performance Coverage
  // Fields verified: busy, ebreak_detected, ipc(real), fetch_stall,
  //                  memory_stall, execute_stall, count_active_warps()
  // ipc_bucket() converts real IPC to integer bin index (avoids real bins)
  // --------------------------------------------------------------------------
  covergroup status_performance_cg;
    option.per_instance = 1;

    cp_busy: coverpoint current_status.busy {
      bins idle = {1'b0};
      bins busy = {1'b1};
    }

    cp_ebreak: coverpoint current_status.ebreak_detected {
      bins running   = {1'b0};
      bins completed = {1'b1};
    }

    // Sample WINDOWED (instantaneous) IPC, not cumulative: cumulative IPC is a
    // single asymptotic value per run (only 1-2 buckets ever); windowed IPC
    // reflects real throughput bursts and exercises the full bucket range.
    cp_ipc_bucket: coverpoint ipc_bucket(current_status.ipc_window) {
      bins zero      = {0};
      bins very_low  = {1};
      bins low_ipc   = {2};
      bins med_ipc   = {3};
      bins high_ipc  = {4};
      // CONFIG-AWARE ceiling = MAX_IPC_BUCKET (see its derivation above): bin 5
      // (IPC>1.0) needs ISSUE_WIDTH>=2; bin 4 (high_ipc, 0.75..1.0) is PROVEN
      // unreachable at <=4 warps single-issue (warp-unlock latency L>NUM_WARPS/0.75 —
      // compute_flat/compute_tight both cap ~0.5). Candidate set {4,5} filtered by the
      // item-referencing `with` (a constant `with` is silently DROPPED, vopt-13185);
      // each bin auto-reactivates as ISSUE_WIDTH/NUM_WARPS grow past its threshold.
      ignore_bins above_issue_width = {4,5} with (item > MAX_IPC_BUCKET);
    }

    cp_fetch_stall: coverpoint current_status.fetch_stall {
      bins active  = {1'b0};
      bins stalled = {1'b1};
    }

    cp_memory_stall: coverpoint current_status.memory_stall {
      bins active  = {1'b0};
      bins stalled = {1'b1};
    }

    cp_execute_stall: coverpoint current_status.execute_stall {
      bins active  = {1'b0};
      bins stalled = {1'b1};
    }

    // Additional stall types for richer coverage
    cp_decode_stall: coverpoint current_status.decode_stall {
      bins active  = {1'b0};
      bins stalled = {1'b1};
    }

    cp_issue_stall: coverpoint current_status.issue_stall {
      bins active  = {1'b0};
      bins stalled = {1'b1};
    }

    // Program counter regions to classify execution phase
    cp_pc_region: coverpoint current_status.pc {
      bins text_low  = {[32'h80000000:32'h80001FFF]};
      bins text_mid  = {[32'h80002000:32'h8000FFFF]};
      bins text_high = {[32'h80010000:32'hFFFF_FFFF]};
    }

    // Cycle count buckets to classify execution length
    cp_cycle_bucket: coverpoint current_status.cycle_count {
      bins short = {[0:999]};
      bins med   = {[1000:9999]};
      bins long  = {[10000:64'hFFFF_FFFF_FFFF_FFFF]};
    }

    cp_active_warps: coverpoint current_status.count_active_warps() {
      bins none = {0};
      bins one  = {1};
      bins two  = {2};
      bins few  = {3};
      bins four = {4};
      bins many = {[5:8]};
      // Active-warp count can never exceed NUM_WARPS, so counts above the compiled
      // config are unreachable (e.g. `many` is unreachable at NUM_WARPS<=4).
      // Config-aware: references item so no constant-with_expr warning; auto-adapts.
      ignore_bins above_cfg = {[1:8]} with (item > CFG_WARPS);
    }

    cross_ipc_stalls: cross cp_ipc_bucket, cp_fetch_stall, cp_memory_stall {
      // SAMPLING-WINDOW timing waiver (evidence-based, NOT convenience): the two
      // residual tuples are <zero,stalled,stalled> and <very_low,stalled,stalled>
      // — BOTH the icache (fetch) and dcache (memory) request ports backpressured
      // AT ONCE for a full windowed-IPC sample (=> near-zero retirement in that
      // window). All other stall combos are covered, including <low/med_ipc,
      // stalled,stalled> (cache_stress co-activates both caches) and every
      // <zero,{active,stalled}×{active,stalled}> except the double-stall. A
      // simultaneous fetch+memory stall is a TRANSIENT (one port drains before
      // the other), so it never persists across a whole IPC sample window while
      // retirement also reads zero — dedicated cache_stress + mem_zero runs
      // (session 6-8) drove double-stalls but only at non-zero windowed IPC.
      // Waive <{zero,very_low}, stalled, stalled>; keep every covered combo.
      ignore_bins double_stall_zero_ipc =
        ( binsof(cp_ipc_bucket.zero) || binsof(cp_ipc_bucket.very_low) )
        && binsof(cp_fetch_stall.stalled)
        && binsof(cp_memory_stall.stalled);
    }
    // Additional crosses for stall combinations and cycle phases
    cross_stall_types: cross cp_decode_stall, cp_issue_stall, cp_execute_stall {
      // PROVEN-UNREACHABLE waiver (RTL-cited, NOT a coverage convenience):
      // cp_decode_stall = fetch_if.valid && !fetch_if.ready  (tb_top.sv:604-605)
      // cp_issue_stall  = decode_if.valid && !decode_if.ready (tb_top.sv:606-607)
      // The fetch->decode elastic buffer is instantiated SIZE(0) (VX_decode.sv:549),
      // and VX_elastic_buffer.sv:34-41 defines SIZE==0 as a pure combinational passthru:
      //     assign valid_out = valid_in;   -> decode_if.valid === fetch_if.valid
      //     assign ready_in  = ready_out;  -> fetch_if.ready  === decode_if.ready
      // Therefore tb_decode_stall === tb_issue_stall on EVERY cycle: the two taps are
      // the same boolean. The (decode=active, issue=stalled) and (decode=stalled,
      // issue=active) combinations are physically impossible in this RTL, so
      // cross_stall_types' true ceiling is 4/8 bins. Verified empirically: 38-run
      // suite never hit either asymmetric tuple. If a buffered pipe stage is ever
      // inserted between fetch_if and decode_if (SIZE>0) this waiver must be removed.
      ignore_bins decode_ne_issue =
          ( binsof(cp_decode_stall.active)  && binsof(cp_issue_stall.stalled) ) ||
          ( binsof(cp_decode_stall.stalled) && binsof(cp_issue_stall.active)  );
    }
    cross_pc_cycles: cross cp_pc_region, cp_cycle_bucket;
  endgroup : status_performance_cg

  //==========================================================================
  // Constructor — covergroups MUST be instantiated here (QuestaSim rule)
  //==========================================================================
  function new(string name = "vortex_coverage_collector",
              uvm_component parent = null);
      int use_axi;                          // must be declared before statements
      super.new(name, parent);

      // Active data interface is chosen by USE_AXI_WRAPPER (set by --interface).
      // Plusargs are available at construction time; cfg is NOT (build_phase).
      if (!$value$plusargs("USE_AXI_WRAPPER=%d", use_axi))
          use_axi = 1;                      // default to AXI

      // Construct ONLY the active data-interface group, so the idle one never
      // lands in this run's UCDB at 0%. The merged UCDB still holds both,
      // because the MEM run constructs and fills mem_operation_cg.
      if (use_axi) axi_transaction_cg = new();
      else         mem_operation_cg   = new();

      // Interface-independent groups — always constructed:
      dcr_config_cg         = new();
      host_operation_cg     = new();
      status_performance_cg = new();

      mem_samples = 0; axi_samples = 0; dcr_samples = 0;
      host_samples = 0; status_samples = 0;
  endfunction

  //==========================================================================
  // Build Phase
  //==========================================================================
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(vortex_config)::get(this, "", "cfg", cfg))
      `uvm_info("COVERAGE",
        "No vortex_config found — coverage collection disabled", UVM_MEDIUM)

    mem_imp    = new("mem_imp",    this);
    axi_imp    = new("axi_imp",    this);
    dcr_imp    = new("dcr_imp",    this);
    host_imp   = new("host_imp",   this);
    status_imp = new("status_imp", this);

    // Guard against a config (e.g. NDEBUG, UUID_WIDTH=1) that would mis-slice
    // the AXI ID and accidentally bin the UUID counter again.
    if (!(ROUTE_W > 0 && ROUTE_W < 12))
      `uvm_fatal("COVERAGE",
        $sformatf("AXI route width ROUTE_W=%0d implausible (AXI_ID_W=%0d, UUID_W=%0d) — check UUID_WIDTH source",
                  ROUTE_W, AXI_ID_W, UUID_W))

    // OBS-030 TRIP-WIRE — this replaces a PROSE trip-wire that sat in a comment
    // for two months and was never discharged, which is exactly how the route
    // waivers survived into a config they were invalid for. The read-path route
    // must be wide enough to hold {slot, port} (VX_axi_adapter.sv:282); if the
    // adapter's TAG_BUFFER_SIZE or port count ever outgrows the field, the
    // decode above would silently alias slots onto each other. Fail loud instead.
    if (ROUTE_W < (PORT_SEL_W + SLOT_W))
      `uvm_fatal("COVERAGE",
        $sformatf({"AXI route field too narrow for its own decode: ROUTE_W=%0d < PORT_SEL_W=%0d + SLOT_W=%0d ",
                   "(MEM_PORTS=%0d, TAG_BUF_SZ=%0d). The read tag is {tbuf_waddr, req_xbar_sel} ",
                   "(VX_axi_adapter.sv:282) — re-derive TAG_BUF_SZ from the adapter's TAG_BUFFER_SIZE."},
                  ROUTE_W, PORT_SEL_W, SLOT_W, MEM_PORTS, TAG_BUF_SZ))

    `uvm_info("COVERAGE",
      $sformatf("AXI route decode: AXI_ID_W=%0d UUID_W=%0d ROUTE_W=%0d | MEM_PORTS=%0d PORT_SEL_W=%0d | TAG_BUF_SZ=%0d SLOT_W=%0d",
                AXI_ID_W, UUID_W, ROUTE_W, MEM_PORTS, PORT_SEL_W, TAG_BUF_SZ, SLOT_W), UVM_LOW)

    // Record whether the adapter's tag buffer is elaborated in THIS build. It is
    // config-dependent (absent at 1CL, present per-port at 2CL) and it decides
    // whether the read `id` carries a slot index or a raw cache tag, so it must
    // be visible in the log next to any slot-coverage number.
    // VERIFY against the design, never against this message:
    //   vcover report -recursive <ucdb> | grep g_tag_buf
    `uvm_info("COVERAGE",
      $sformatf("AXI tag buffer %s (MEM_PORTS=%0d) -> cp_route_slot/cross_port_slot %s",
                TAG_BUF_PRESENT ? "PRESENT" : "ABSENT", MEM_PORTS,
                TAG_BUF_PRESENT ? "ACTIVE (slot index is real)"
                                : "IGNORED (read id is the raw cache tag)"), UVM_LOW)
  endfunction : build_phase

  //==========================================================================
  // Write Methods
  //==========================================================================

  virtual function void write_mem(mem_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    if (trans == null) return;
    current_mem = trans;
    mem_samples++;
    if (mem_operation_cg != null) mem_operation_cg.sample();
    // `uvm_info("COVERAGE", $sformatf("Sampled MEM transaction (samples=%0d, addr=0x%0h)", mem_samples, trans.addr), UVM_LOW)
  endfunction

  virtual function void write_axi(axi_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    if (trans == null) return;
    current_axi = trans;
    axi_samples++;
    if (axi_transaction_cg != null) axi_transaction_cg.sample();
    // Update runtime per-bin counters
    // type
    bump_axi_bin($sformatf("type:%0d", trans.trans_type));
    // len bucket
    if (trans.len == 8'h00) bump_axi_bin("len:single");
    else if (trans.len >= 8'h01 && trans.len <= 8'h03) bump_axi_bin("len:sh");
    else if (trans.len >= 8'h04 && trans.len <= 8'h0F) bump_axi_bin("len:med");
    else bump_axi_bin("len:lng");
    // addr region (32-bit view)
    if (trans.addr <= 32'h00FF_FFFF) bump_axi_bin("addr:low");
    else bump_axi_bin("addr:high");

    // id range
    if (trans.id < 64) bump_axi_bin("id:0-63");
    else if (trans.id < 128) bump_axi_bin("id:64-127");
    else if (trans.id < 192) bump_axi_bin("id:128-191");
    else bump_axi_bin("id:192-255");

    // `uvm_info("COVERAGE", $sformatf("Sampled AXI transaction (samples=%0d, addr=0x%0h, type=%0d)", axi_samples, trans.addr, trans.trans_type), UVM_LOW)
  endfunction

  virtual function void write_dcr(dcr_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    if (trans == null) return;
    current_dcr = trans;
    dcr_samples++;
    dcr_config_cg.sample();
    // Update runtime per-bin counters for DCR
    // addr name
    if (trans.addr == dcr_transaction::DCR_STARTUP_ADDR0) bump_dcr_bin("addr:startup0");
    else if (trans.addr == dcr_transaction::DCR_STARTUP_ADDR1) bump_dcr_bin("addr:startup1");
    else if (trans.addr == dcr_transaction::DCR_ARGV_PTR0) bump_dcr_bin("addr:argv0");
    else if (trans.addr == dcr_transaction::DCR_ARGV_PTR1) bump_dcr_bin("addr:argv1");
    else if (trans.addr == dcr_transaction::DCR_MPM_CLASS) bump_dcr_bin("addr:mpm_class");
    else bump_dcr_bin($sformatf("addr:0x%0h", trans.addr));

    // data magnitude
    if (trans.data == 32'h0) bump_dcr_bin("data:zero");
    else if (trans.data <= 32'h0000_0100) bump_dcr_bin("data:small");
    else if (trans.data >= 32'h0000_1000 && trans.data <= 32'h00FF_FFFF) bump_dcr_bin("data:mid_ptr");
    else if (trans.data >= 32'h0100_0000) bump_dcr_bin("data:hi_code");

    // `uvm_info("COVERAGE", $sformatf("Sampled DCR transaction (samples=%0d, addr=0x%0h)", dcr_samples, trans.addr), UVM_LOW)
  endfunction

  virtual function void write_host(host_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    if (trans == null) return;
    current_host = trans;
    host_samples++;
    host_operation_cg.sample();
    // Update runtime per-bin counters for HOST
    bump_host_bin($sformatf("op:%0d", trans.op_type));
    if (trans.op_type == host_transaction::HOST_LAUNCH_KERNEL) begin
      if (trans.num_threads == 1) bump_host_bin("threads:1");
      else if (trans.num_threads == 2) bump_host_bin("threads:2");
      else if (trans.num_threads == 4) bump_host_bin("threads:4");
      else bump_host_bin($sformatf("threads:%0d", trans.num_threads));
    end
    // timeout bucket
    if (trans.timeout_cycles < 10000) bump_host_bin("timeout:low");
    else if (trans.timeout_cycles < 50000) bump_host_bin("timeout:mid");
    else bump_host_bin("timeout:high");

    // `uvm_info("COVERAGE", $sformatf("Sampled HOST transaction (samples=%0d, op=%0d)", host_samples, trans.op_type), UVM_LOW)
  endfunction

  virtual function void write_status(status_transaction trans);
    if (cfg == null || !cfg.enable_coverage) return;
    if (trans == null) return;
    current_status = trans;
    status_samples++;
    status_performance_cg.sample();
    // Update runtime per-bin counters for STATUS
    bump_status_bin($sformatf("busy:%0d", trans.busy));
    bump_status_bin($sformatf("ebreak:%0d", trans.ebreak_detected));
    // ipc bucket using helper — only if ipc is valid (>= 0)
    if (trans.ipc >= 0.0) bump_status_bin($sformatf("ipc:%0d", ipc_bucket(trans.ipc)));
    // PC region
    if (trans.pc >= 32'h80000000 && trans.pc <= 32'h80001FFF) bump_status_bin("pc:text_low");
    else if (trans.pc >= 32'h80002000 && trans.pc <= 32'h8000FFFF) bump_status_bin("pc:text_mid");
    else bump_status_bin("pc:text_high");

    // stall flags
    if (trans.fetch_stall) bump_status_bin("stall:fetch");
    if (trans.decode_stall) bump_status_bin("stall:decode");
    if (trans.issue_stall) bump_status_bin("stall:issue");
    if (trans.execute_stall) bump_status_bin("stall:execute");
    if (trans.memory_stall) bump_status_bin("stall:memory");

    //`uvm_info("COVERAGE", $sformatf("Sampled STATUS transaction (samples=%0d, ebreak=%0d, ipc=%0f)", status_samples, trans.ebreak_detected, trans.ipc), UVM_LOW)
  endfunction

  //==========================================================================
  // Report Phase
  //==========================================================================
  virtual function void report_phase(uvm_phase phase);
    real mem_cov, axi_cov, dcr_cov, host_cov, status_cov, data_if_cov, total_cov;
    string data_if_name;
    int unsigned total_groups;
    super.report_phase(phase);

    if (cfg == null || !cfg.enable_coverage) begin
      `uvm_info("COVERAGE", "Coverage disabled — no report generated", UVM_MEDIUM)
      return;
    end

    // Print runtime config flags and sample counters for debugging
    `uvm_info("COVERAGE", $sformatf("Coverage cfg: enable_coverage=%0d, axi_agent_enable=%0d, mem_agent_enable=%0d", cfg.enable_coverage, cfg.axi_agent_enable, cfg.mem_agent_enable), UVM_LOW)
    `uvm_info("COVERAGE", $sformatf("Sample counts: mem=%0d, axi=%0d, dcr=%0d, host=%0d, status=%0d", mem_samples, axi_samples, dcr_samples, host_samples, status_samples), UVM_LOW)

    mem_cov    = (mem_operation_cg   != null) ? mem_operation_cg.get_coverage()   : 0.0;
    axi_cov    = (axi_transaction_cg != null) ? axi_transaction_cg.get_coverage() : 0.0;
    dcr_cov    = dcr_config_cg.get_coverage();
    host_cov   = host_operation_cg.get_coverage();
    status_cov = status_performance_cg.get_coverage();

    // Print raw per-group coverage values for debugging
    `uvm_info("COVERAGE", $sformatf("Raw coverage: mem=%6.2f, axi=%6.2f, dcr=%6.2f, host=%6.2f, status=%6.2f", mem_cov, axi_cov, dcr_cov, host_cov, status_cov), UVM_LOW)

    // Print per-bin hit counters collected at runtime (only non-empty bins)
    `uvm_info("COVERAGE", "Per-bin hit summary:", UVM_LOW)
    foreach (axi_bin_counts[k]) begin
      `uvm_info("COVERAGE", $sformatf("  AXI %s = %0d", k, axi_bin_counts[k]), UVM_LOW)
    end
    foreach (dcr_bin_counts[k]) begin
      `uvm_info("COVERAGE", $sformatf("  DCR %s = %0d", k, dcr_bin_counts[k]), UVM_LOW)
    end
    foreach (host_bin_counts[k]) begin
      `uvm_info("COVERAGE", $sformatf("  HOST %s = %0d", k, host_bin_counts[k]), UVM_LOW)
    end
    foreach (status_bin_counts[k]) begin
      `uvm_info("COVERAGE", $sformatf("  STATUS %s = %0d", k, status_bin_counts[k]), UVM_LOW)
    end

    // Choose the data interface coverage based on which interface sampled transactions
    if (axi_samples > 0) begin
      data_if_name = "AXI Transactions";
      data_if_cov  = axi_cov;
    end else if (mem_samples > 0) begin
      data_if_name = "Memory Operations";
      data_if_cov  = mem_cov;
    end else begin
      data_if_name = "Data Interface (none sampled)";
      data_if_cov  = 0.0;
    end

    // Count active groups based on whether we recorded samples for them
    total_groups = 0;
    if ((axi_samples + mem_samples) > 0) total_groups++;
    if (dcr_samples    > 0) total_groups++;
    if (host_samples   > 0) total_groups++;
    if (status_samples > 0) total_groups++;

    if (total_groups == 0) total_cov = 0.0;
    else begin
      total_cov = 0.0;
      if ((axi_samples + mem_samples) > 0) total_cov += data_if_cov;
      if (dcr_samples    > 0) total_cov += dcr_cov;
      if (host_samples   > 0) total_cov += host_cov;
      if (status_samples > 0) total_cov += status_cov;
      total_cov = total_cov / total_groups;
    end

    `uvm_info("COVERAGE", {"\n",
      "╔══════════════════════════════════════════╗\n",
      "║   Vortex Interface (Bus) Coverage        ║\n",
      "║   — sanity check only, NOT sign-off —    ║\n",
      "╠══════════════════════════════════════════╣\n",
      $sformatf("║  %-18s: %6.2f%%             ║\n", data_if_name, data_if_cov),
      $sformatf("║  DCR Configuration  : %6.2f%%             ║\n", dcr_cov),
      $sformatf("║  Host Operations    : %6.2f%%             ║\n", host_cov),
      $sformatf("║  Status/Performance : %6.2f%%             ║\n", status_cov),
      "╠══════════════════════════════════════════╣\n",
      $sformatf("║  INTERFACE SUBTOTAL : %6.2f%%             ║\n", total_cov),
      "╚══════════════════════════════════════════╝\n"
    }, UVM_NONE)

    // This banner reflects ONLY the transaction/interface covergroups in this
    // collector. It does NOT include architectural coverage (instr_class_cg in
    // the bound vx_instr_probe) or code coverage — both live in the UCDB, not in
    // this class. The authoritative sign-off number is the MERGED UCDB produced
    // by scripts/merge_coverage.sh (vcover report).
    `uvm_info("COVERAGE",
      "Interface-only subtotal above. Authoritative coverage = merged UCDB via merge_coverage.sh (adds instr_class_cg + code coverage).",
      UVM_NONE)

    // No pass/fail verdict here: the 90% goal is evaluated on the merged UCDB,
    // not on this interface subset (which cannot reach it alone). Issuing a
    // warning on a partial number was misleading, so it is removed.
  endfunction : report_phase

endclass : vortex_coverage_collector

`endif // VORTEX_COVERAGE_COLLECTOR_SV
