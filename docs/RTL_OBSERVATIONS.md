# RTL Observations — Vortex UVM (single running report)

**Purpose:** the ONE consolidated place for every RTL behaviour we notice while
verifying — weird/unexpected behaviour, suspected or confirmed RTL bugs,
observability limits, micro-architectural quirks, and possible enhancements.
Updated continuously **as findings appear** (CLAUDE.md rule 9), not deferred and
not scattered across per-fix docs.

**Rules for this file**
- One entry per observation. Update an existing entry rather than duplicating.
- Always cite evidence: `file:line` in the RTL and/or the sim run/log that showed it.
- Classify: **BUG** (RTL is wrong) · **QUIRK/EXPECTED** (correct but non-obvious) ·
  **OBSERVABILITY** (real but not visible at our tap) · **ENHANCEMENT** (RTL could be improved) ·
  **REF-MODEL** (SimX golden, not the RTL — kept here because it couples tightly).
- Disposition: `open` · `waived (cited)` · `worked-around` · `needs-RTL-fix` · `wontfix/expected`.
- RTL pin: `7a52ee5`. Primary config 1CL/1C/4W/4T RV32 AXI.

> Pre-existing RTL-cited **coverage waiver** facts (MSHR route, write-through dead
> write-data toggle, high_ipc ceiling, wspawn single-warp bootstrap, is_global
> barrier, weak-coherence 2CL no_fence) live in
> `docs/INDUSTRIAL_TRANSFORMATION_PLAN.md` → "RTL-cited waiver facts". Migrate them
> here over time; for now that section remains authoritative for those.

---

## Log

### OBS-001 — DUT commits out of program order (per warp)
- **Class:** QUIRK/EXPECTED · **Disposition:** worked-around · **Found:** Phase A0 (2026-07-14)
- **What:** Within one warp, retirements reach the commit interface out of issue
  order. Observed uuid `0x59` (an earlier-issued instruction) committing *after*
  `0x5a`/`0x5c`. The core issues in order, but execution units have different
  latencies and the commit arbiter (`VX_stream_arb`, priority) retires whichever
  unit is ready first.
- **Evidence:** `Vortex/hw/rtl/core/VX_commit.sv:56-71` (per-issue commit arb over
  `commit_if[NUM_EX_UNITS*ISSUE_WIDTH]`, `OUT_BUF=1`). Lockstep run
  `scratchpad/a0_dbg3.log` (DUT retire seq vs uuid).
- **Impact / handling:** `uuid` is the per-warp issue counter = program order.
  Lockstep sorts each per-`(cid,wid)` DUT FIFO by uuid before aligning against
  SimX (which retires in strict program order). Not a bug.

### OBS-002 — Load writeback data not observable at the commit-arb probe
- **Class:** OBSERVABILITY · **Disposition:** CLOSED (`97c4e30`, region-filtered load-compare, default-on) · **Found:** Phase A0 (2026-07-14)
- **What:** For `lw`, the `commit_arb_if.data` field carries a stale/address-like
  or uniform-across-lanes value, not the loaded data. 100% of lockstep DATA
  mismatches on a known-good program were loads. Loads complete asynchronously via
  the LSU memory-response path and write the regfile on that path; the commit
  arbitration tap does not carry the final per-lane load value.
- **Evidence:** `Vortex/hw/rtl/core/VX_commit.sv:44-71` (commit arb); lockstep run
  `scratchpad/a0_fix.log` (all DATA mismatches at `lw` PCs, e.g. `0x800006e4`
  `lw s0,0x28(sp)`); DUT uniform `8000770c` vs SimX per-lane `800076b8+28*lane`.
- **Impact / handling:** Load *data* is verified by the end-state memory-equivalence
  check (passes). Lockstep scopes loads out of the per-lane DATA compare (still
  checks PC/rd/ordering), identified by SimX `fu_type==LSU`.
- **UPDATE 2026-07-15 (A1(d)) — LSU probe BUILT; load data IS observable, but a raw
  compare is NOT sound.** `vortex_uvm_env/tb/vx_lsu_probe.sv` binds `VX_lsu_slice` and
  taps `result_if` (post sign/zero-extension, `VX_lsu_slice.sv` rsp_buf→rsp_arb). It
  captures TRUE per-lane DUT load values — verified: uuid 0x56 shows real distinct
  per-lane values. Two RTL facts learned:
  1. A load commits **one lane per beat** (tmask 1,2,4,8 — consistent with OBS-003), and
  2. `result_if.data.data` **broadcasts the active lane's value across ALL lane
     positions** in each beat (it is not a per-lane vector). Reading `data[active_lane]`
     per beat reconstructs the correct vector.
  **Why a raw compare is unsound:** loads of **uninitialised / stack / lmem** memory
  legitimately differ (DUT reads 0, SimX reads its own init pattern) — e.g. vecadd_lite
  uuid 0x57 `DUT=0 vs SimX=0x64355e8a` while the END-STATE **passes** (252/252). That is
  exactly the class `compare_all_written` skips (`vortex_scoreboard.svh:647-656`: region
  gate `[RAM_BASE, DATA_LIMIT=0x8800_0000)` excluding stack `0xffff_xxxx`/MMIO/lmem, plus
  a POISON `0xbaadf00d` check). A naive load-compare therefore FALSE-POSITIVES on clean
  programs (vecadd: 429 false LOAD mismatches).
  **Status:** probe + scoreboard overlay committed, but load-compare is **gated OFF**
  behind `+LOCKSTEP_LOADS` (default = prior OBS-002 behaviour, no regression).
  **To close OBS-002 (next step):** export SimX `LsuTraceData::mem_addrs` (per-thread
  load address) through the cosim record — same additive pattern already used for
  `fu_type`/`is_volatile` (`simx_cosim_record.h` + `core.cpp` + `simx_dpi.cpp` +
  `simx_pkg.sv`) — then in `compare_pair` skip a load lane whose address is outside
  `[RAM_BASE, DATA_LIMIT)` or whose SimX value is POISON. Then enable by default.
  No RTL request-tap needed (avoids the `full_addr` port-width/macro-visibility risk).
- **CLOSED 2026-07-15 (`97c4e30`).** Done exactly as planned: `simx_cosim_record.h`
  gains `mem_addr[SIMX_COSIM_MAX_THREADS]`; `core.cpp` fills it from
  `LsuTraceData::mem_addrs` for LSU traces; `simx_dpi.cpp`/`simx_pkg.sv` add a
  `mem_addr[]` open-array out-param; `lockstep_scoreboard.svh` pops it and compares a
  load lane ONLY when the SimX effective address is in `[RAM_BASE,DATA_LIMIT)` and the
  gold value != POISON, else defers to the end-state check. Load-compare is now sound
  and **ON by default** (`+NO_LOCKSTEP_LOADS` escapes). Validation: `vecadd_lite`
  lockstep PASSED — **1035/1035 matched, LOAD mismatch = 0, 74 in-region load lanes
  data-compared, 113 out-of-region/uninit filtered** (was 429 false mismatches before
  the filter). Config-generic across NC/NCL/NW/NT (all sizings `cfg.num_threads` /
  `nw_bits=clog2(num_warps)`; NT≤32 caveat inherited from the pre-existing `result[]`).

### OBS-003 — One load emits MULTIPLE commit records with the same uuid (partial masks)
- **Class:** QUIRK/EXPECTED · **Disposition:** worked-around · **Found:** Phase A0 (2026-07-14)
- **What:** A single load instruction can appear on the commit interface as several
  records sharing one `uuid`, each with a partial (and overlapping) `tmask` — the
  LSU commits lanes as their per-thread memory responses arrive. Observed uuid
  `0x2000000ee` (PC `0x6e8`) as two records with masks `0xd` (1101) then `0xe`
  (1110). This is distinct from clean SIMD-beat (`sop..eop`, `sid`) splitting.
- **Evidence:** lockstep debug `scratchpad/a0_dbg4.log` s=150/151 (same uuid/pc/rd,
  masks `0xd`/`0xe`). Config here: `LS_LANES=4` (`SIMD_WIDTH`), `ISSUE_WIDTH=1`.
- **Impact / handling:** DUT-side aggregation must group commit records by `uuid`
  (union tmask, place each active lane), NOT by `sop/eop` (a single in-progress
  slot corrupts on interleave). SimX emits exactly one record per uuid → merged
  DUT retirement aligns 1:1.

### OBS-004 — Performance-counter CSR reads diverge from the functional golden
- **Class:** QUIRK/EXPECTED · **Disposition:** waived (cited) · **Found:** Phase A0 (2026-07-14)
- **What:** `csrr mcycle` / `minstret` (and `mhpmcounter*`, `_h` mirrors) read
  values that differ between the timing-accurate DUT and the functional SimX model
  (e.g. `minstret` `0x1167` vs `0x1166`). This is definitional, not a bug — the two
  models count cycles/retirements differently.
- **Evidence:** `vecadd_lite.dump` `0x80000d3c csrr a3,mcycle`, `0x80000d4c
  csrr a4,minstret`; lockstep run `scratchpad/a0_load.log`. CSR range
  `VX_types.vh:63-75` (`VX_CSR_MPM_BASE 0xB00` … `0xB1F`, `_H 0xB80`…`0xB9F`).
- **Impact / handling:** SimX flags these `is_volatile` (set in
  `Vortex/sim/simx/execute.cpp` for the MPM range); lockstep excludes them from the
  DATA compare (PC/rd still checked). Standard RVVI / core-v-verif exclusion class.

### OBS-006 — DUT `uuid` encodes the flat global core id + local warp id
- **Class:** QUIRK/EXPECTED · **Disposition:** worked-around (depended on) · **Found:** Phase A1 (2026-07-14)
- **What:** The commit `uuid` is `{ g_wid, counter[31:0] }` where
  `g_wid = (CORE_ID << NW_BITS) + wid` (`NW_BITS = log2(NUM_WARPS)`). So
  `uuid[31:0]` is a per-warp issue counter, and `uuid>>32` holds
  `(CORE_ID<<NW_BITS)+wid`. `CORE_ID` is the FLAT global core index (matches
  SimX: `core.cpp` asserts `trace->cid == core_id_`). Verified: wid=2, CORE_ID=0
  → `uuid=0x2_000000xx`.
- **Evidence:** `Vortex/hw/rtl/core/VX_uuid_gen.sv:25,40-41`
  (`GNW_WIDTH=UUID_WIDTH-32`, `g_wid=(CORE_ID<<NW_BITS)+wid`, `uuid={g_wid,cntr}`);
  `VX_schedule.sv:330-341`. `UUID_WIDTH=44` (`VX_gpu_pkg.sv:66`).
- **Impact / handling:** Multi-core lockstep derives the real `(cid,wid)` from the
  uuid (`cid=(uuid>>32)>>NW_BITS`, `wid=(uuid>>32)&(NUM_WARPS-1)`) — no probe param
  or RTL change needed; the probe's hardcoded `cid=0` is superseded. Requires
  `UUID_ENABLE` (on here); with it off, `uuid=0` and this + all uuid-alignment
  breaks (see OBS-005 for the golden-side uuid=0 case).

### OBS-008 (REF-MODEL BUG — confirmed & FIXED) — SimX fetches at the exact (misaligned) byte PC instead of word-aligning
- **Class:** REF-MODEL (golden-model correctness bug) · **Disposition:** needs-fix→**FIXED** · **Found:** Phase A1(d) (2026-07-15)
- **What (corrected root cause):** SimX's instruction fetch read at the exact byte
  `warp.PC` (`Vortex/sim/simx/emulator.cpp:145`, `icache_read(&code, warp.PC, 4)`).
  In the DUT's **debug** build `PC_BITS=`XLEN` and `to/from_fullPC` are IDENTITY
  (`VX_gpu_pkg.sv:75-82`), so the architectural PC keeps its **full low bits**: a
  `jalr` to an odd target (riscv-dv random programs produce these — e.g. `jalr a3,a3`
  with `a3` holding a label|1) yields an **odd committed PC** (0x8000c4dd), and the DUT
  keeps it — but the DUT's icache request is **word-aligned** (`VX_fetch.sv:101`
  `icache_req_addr = PC[2 +: ...]`, "4-byte aligned"), so the DUT fetches the correct
  word and runs on. SimX kept the same odd PC (correct — mirrors the DUT) but read the
  instruction at the **exact odd byte address** → misaligned bytes → undecodable
  `0xb3018cd0` → `std::abort()` → run wrongly classified UNVERIFIABLE.
- **NOT a JALR-LSB bug (first hypothesis, retracted):** RISC-V's `& ~1` would make the
  PC *even*, but the DUT's debug PC is *odd*; masking the JALR target in SimX de-synced
  it from the DUT (21968 phantom PC mismatches). The DUT and SimX agree on the odd PC;
  the only defect is the misaligned *fetch*.
- **How found:** the decode-abort observability probe (built this session, KEPT)
  printed `[SimX-DECODE-ABORT] cannot decode instr=0xb3018cd0 at PC=0x8000c4dd` — odd
  PC + a misaligned byte-read of real `.text` (bytes d0,8c,01,b3 straddling
  `srl ra,s9,0x18`@0x8000c4dc and the next word). Evidence: `scratchpad/simx_dpi_decode_abort.log`.
- **Fix:** `emulator.cpp:145` → `icache_read(&instr_code, warp.PC & ~Word(3), 4)`
  (word-align the fetch, leave the architectural `warp.PC` odd to match the DUT).
  JALR left unmasked (`execute.cpp:469`).
- **Impact:** every riscv-dv program with an odd-target JALR was silently UNVERIFIABLE
  on SimX; this recovers real DUT-vs-SimX coverage. Companion to OBS-007 (the decoder's
  `default: std::abort()` is the *mechanism* that surfaced it; the observability print
  is what made the root cause visible).
- **Minor RTL note (debug-only) — CORRECTED 2026-07-16, see OBS-012:** the DUT's debug
  build (PC_BITS=XLEN, identity fullPC) retains an odd architectural PC after a
  jalr-to-odd-target; release (PC_BITS=XLEN-2, `>>2`/`<<2`) word-aligns it away.
  ~~Benign (fetch aligns; low bits never reach an architectural result on this path)~~
  **DISPROVEN:** the odd PC DOES reach architectural results — `auipc`/`la` compute
  rd = PC + imm, so every PC-relative address inherits the skew, cascading into
  misaligned data accesses and silently-corrupted stores (OBS-013). Full root-cause
  and evidence in OBS-012.

### OBS-009 (RESOLVED — not a DUT bug) — no_fence@2CL divergence is single-hart-test-in-multihart race
- **Class:** REF-MODEL/methodology (single-hart random test on N shared-memory cores) · **Disposition:** resolved — real-fix options pending (see investigation doc) · **Found:** Phase A1(d) (2026-07-15)
- **ARCHITECTURAL GROUNDING (2026-08-06) — this class is the PUBLISHED memory model, not an
  unexplained failure.** Verified from the Vortex paper AND the RTL source, so the "race"
  classification rests on cited architecture rather than inference:
  1. **Paper (MICRO'21, "Vortex: Extending the RISC-V ISA for GPGPU and 3D-Graphics", §4.1.4):**
     *"Cores can be grouped into a cluster that can optionally be attached to a shared L2 cache.
     Clusters can share an optional L3 cache. **Flush operations among caches are provided as a
     means of providing weak coherent memory space.**"* And §3.1: *"For memory synchronization, we
     leveraged the RISC-V **fence** instruction."* ⇒ Vortex is a **weak coherent** space; coherence
     is the program's job via fence/flush, NOT a hardware protocol.
  2. **RTL — no coherence protocol exists.** A full scan of `hw/rtl/cache/*.sv` for
     `snoop|coheren|invalidat|MESI|MOESI|probe_req` returns **zero hits**. The only cross-cache
     mechanism is `flush` (`VX_cache.sv:118-137`) — exactly what the paper describes.
  3. **RTL — where the caches actually sit.** L1 dcache is instantiated **per SOCKET**, shared by
     `SOCKET_SIZE` cores (`VX_socket.sv:135-138`, `NUM_UNITS=NUM_DCACHES`, `NUM_INPUTS=SOCKET_SIZE`).
     L2 is per-cluster (`VX_cluster.sv:86`) and L3 per-GPU (`Vortex.sv:75`), each a `VX_cache_wrap`
     with `PASSTHRU = !L2_ENABLED` / `!L3_ENABLED` (`VX_cluster.sv:107`, `Vortex.sv:96`).
     `VX_cache_wrap.sv:160` instantiates the actual `VX_cache` storage **only** `if (PASSTHRU == 0)`.
  4. **Our build has NO L2/L3 storage.** `L2_ENABLED`/`L3_ENABLED` default 0 (`VX_config.vh:846-856`)
     and the compile emits **no** `+define+L2_ENABLE`/`L3_ENABLE` ⇒ both levels are pure bypass.
     `DCACHE_WRITEBACK=0` ⇒ write-through (`VX_config.vh:638`). At 2CL/2C:
     `SOCKET_SIZE=MIN(4,2)=2`, `NUM_DCACHES=UP(2/4)=1` ⇒ **2 cores share one L1 dcache per cluster,
     and the two clusters' L1s have no coherence point except main memory.**
  ⇒ Writes reach memory (write-through) but a remote L1 line is **never invalidated**, so a
  fenceless cross-cluster read can legitimately return stale data. This is precisely the observed
  fingerprint (cluster-0 cores match SimX exactly; cluster-1 cores diverge): the divergence sits
  exactly on the coherence boundary the architecture defines. A fenceless multi-core program has
  **no architecturally-defined single result**, so DUT≠SimX there is not a DUT bug.
- **EXTENDED (2026-07-16, INV-4): `riscv_rand_jump_test`@2CL is the same class, with a NEW
  method-boundary flavor.** Post-jalr-patch regen, plain 2CL run → 7 end-state MEM MISMATCHes.
  Load-feed classification: pass-1 = 45 racy in-region loads / 95 cascade / 3 warps; pass-2
  pushed=consumed=45 but **residual 15 (load=13)** — the residual loads are NEW racy loads at
  UNFED keys: in a *jump* test the racy loaded bytes steer control flow, so pass-2 SimX walks a
  different path and meets fresh racy loads the pass-1 trace never keyed. Two-pass replay has no
  fixed point when races feed branches (ENH-2 iterated-feed territory; same boundary class as
  OBS-010's interrupt drift). **Race evidence triangle:** (1) cid=0 matches SimX exactly, only
  cores 1–3 diverge (this entry's clincher signature); (2) every divergent value is a
  byte-granular `lb` of `.data` (racy sibling-core byte stores); (3) the post-feed DEFERRED
  end-state compare = **0 MEM MISMATCH** (plain run had 7) — memory converges once SimX sees the
  DUT's racy inputs. NOT a DUT bug; verdict left honestly RED at multi-core (do not force green).
- **CLINCHER (2026-07-15):** the first-divergence load `lw s3,0(s1)` reads fixed absolute
  `s1=0x80020618` in `.region_1` (PROGBITS). **ELF init there = 0x7aea0e77 = the DUT value**;
  SimX reads 0x7a000e77 (one byte zeroed) on cluster-1 only. Program reads no `mhartid` ⇒ single-hart;
  run on 4 shared-memory cores ⇒ genuine cross-core write-ordering race. DUT reads pristine init, SimX's
  fixed core-stepping zeroes the byte between cluster-0 and cluster-1 reads. Both are valid executions
  of an architecturally-undefined (fenceless) program. Full proof + real-fix options:
  `docs/investigations/SimX_2CL_no_fence_divergence.md` (DECISIVE section).
- **What:** After the OBS-008 fetch-align fix let SimX run the regen `no_fence`@2CL to
  completion, lockstep's first divergence is `seq=4632 PC=0x8000c8cd`
  (`8000c8cc: mulhsu a5,a3,a5`): **DUT a5=0 vs SimX a5=0xfffff9bf**, identical on ALL
  4 cores (both clusters) → DETERMINISTIC (not the per-cluster fenceless-ordering class
  of the pinned hex). Everything before seq 4632 matches (19008 retires); the 20576
  downstream PC mismatches are the control-flow cascade after this value forks a branch.
- **Context:** upstream chain feeds `a5` via `add`/`sra` from `s7`, which comes from
  `mulh`/`mulhu` over `t0 = csrrc/csrrs mscratch` reads (`0x8000c8b0..c8cc`). Candidates
  to check: (1) an upstream LOAD feeding a3/a5 whose data lockstep skips (OBS-002) —
  would make this a symptom, not a root; (2) `mscratch` CSR value differing DUT↔SimX;
  (3) a genuine `mulhsu` sign-handling difference in one model. `mulhsu` = signed(rs1) ×
  unsigned(rs2), high word; DUT=0 ⇒ treated as small/unsigned-ish, SimX=0xfffff9bf ⇒
  negative(rs1) — consistent with one model sign-extending rs1 and the other not, OR
  with a diverged negative input.
- **Evidence:** `scratchpad/no_fence_FETCHFIX.log` (LOCKSTEP FIRST-DIVERGENCE block);
  disasm `0x8000c8b0..c8cc`.
- **RESOLVED (root cause, 2026-07-15) — the divergence is LOAD-FED, not a compute bug.**
  With the LSU probe enabling load-data visibility, the first divergence **moves much
  earlier and becomes a LOAD**: cid=2/3 `seq=742 PC=0x80004c10... LOAD lane0 DUT=0x5e vs
  SimX=0x0`; cid=0/1 `seq=4441 PC=0x8000c535 LOAD DUT=0x495d vs SimX=0x4549`. The
  `mulhsu`@seq4632 was a **downstream symptom** of an already-diverged operand. So the
  root is a **memory-content difference** (DUT and SimX read different values), i.e. the
  fenceless shared-load ordering class — **NOT** a DUT ALU/CSR bug. `mulhsu`/`mscratch`
  hypotheses are retired.
- **Caveat CLOSED 2026-07-15 (`97c4e30`, region filter):** re-ran the **pinned** no_fence@2CL
  with the OBS-002 address region-filter ON. Result: **20 LOAD mismatches, 0 skipped —
  every survivor is IN-REGION** (`[RAM_BASE,DATA_LIMIT)`), so they are NOT the
  uninitialised/stack class. The per-warp first-divergence now points at the LOAD, not
  the compute op: cluster-1 (cid 2,3) first@`seq=231 PC=0x80000414 LOAD @0x80020618
  DUT=0x7aea0e77 vs SimX=0x7a000e77` (feeds the `mulhu @0x800004f4` at seq 278, 47
  retires later); cluster-0 (cid 0,1) first@`seq=294 PC=0x8000054c LOAD @0x80013e27
  DUT=0xc4 vs SimX=0`. The **non-zero-vs-non-zero** survivor (`0x7aea0e77` vs `0x7a000e77`)
  rules out a pure init/staging artifact → **genuine in-region cross-core shared-memory
  ordering divergence in the fenceless program, NOT a DUT bug**. OBS-009 fully root-caused
  to the load level. Evidence: `scratchpad/obs002_nofence_2CL.log`.
- **VERIFIED 2026-07-16 (Phase A1(e), RVVI load-bus, `+LOCKSTEP_LOADFEED`) — positive, non-waiver.**
  Implemented true RVVI load-bus as a two-pass trace-replay: pass 1 finds the racy in-region loads;
  the DUT's per-lane loaded values are fed into SimX (keyed by **(cid,wid,PC,occurrence)** — uuids
  differ, and PC-occurrence is robust to interrupt-inserted instructions) at the single load site;
  pass 2 re-runs SimX in-process following the DUT loads. On the pinned no_fence hex: pass-1 **20**
  racy loads → **138** cascaded mismatches; pass-2 **residual = 0** over **5432/5432** pairs. The
  end-state compare was deferred to `report_phase` (post-feed SimX) → the `0x80013dd8` racy word
  matches → **TEST PASSED, 0 UVM_ERROR**. So OBS-009 is not merely classified UNVERIFIABLE — the DUT
  is now POSITIVELY VERIFIED equivalent modulo the (architecturally-undefined) racy loads. Not
  suppression: any residual not explained by a fed racy load stays a hard error. Files:
  `Vortex/sim/simx/cosim_loadfeed.h`, `emulator.cpp`, `execute.cpp`; `lockstep_scoreboard.svh`;
  `vortex_scoreboard.svh` (deferred end-state). Full writeup: `docs/investigations/SimX_2CL_no_fence_divergence.md`.
  NOTE: the same feed only PARTIALLY collapses OBS-010 (`full_interrupt`) — 116→7 residual, a genuine
  interrupt-timing divergence (NOT fully verifiable this way); see OBS-010 closure below.

### OBS-010 (RESOLVED — not a DUT bug) — `full_interrupt`@2CL: single-hart-test-in-multihart, load-fed div divergences
- **Class:** REF-MODEL/methodology (same class as OBS-009; interrupt-timing amplifies it) · **Disposition:** PARTIALLY collapsed by RVVI load-bus (A1(e)); residual is interrupt-timing, NOT a DUT bug (end-state PASSES) — see closure below · **Found:** Phase A1(d) (2026-07-15)
- **What:** with the OBS-008 fetch-align fix, the pinned `full_interrupt`@2CL no longer
  aborts — runs to EBREAK. Lockstep: compared 19084, matched 19050, **only 34 data
  mismatches** (NOT a cascade), PC/rd=0, 0 orphans. **cid=0 byte-exact**; divergences
  are per-core: cid=1 has 1 (`seq=2309 PC=0x80002104 div a0,s4,a0` DUT=4 vs SimX=0),
  cid=2/3 have ~16 (`seq=1023 PC=0x80001344 divu t2,a0,a1` DUT=0 vs SimX=1).
- **Pattern = OBS-009:** both sites are DIVISIONS whose operand traces to an unobservable
  source — `a0 = lbu -41(sp)` (a **stack load**, data skipped per OBS-002) and nearby
  `csrrw/csrrs mscratch`. For an interrupt test, the DUT (timing-accurate) and SimX
  (functional) take interrupts at different instruction boundaries → different saved
  stack/CSR context → a loaded byte differs → the div result differs. Consistent with
  **interrupt-timing reference divergence, NOT a DUT bug** — but UNPROVABLE at the commit
  probe because load data isn't visible.
- **Evidence:** `scratchpad/full_interrupt_REPLAY.log`; disasm `0x80001330..1348`,
  `0x800020f0..210c`.
- **RESOLVED 2026-07-15 (`97c4e30`, region-filtered load-compare) — LOAD-fed, not a div bug.**
  Re-ran the pinned `full_interrupt`@2CL with OBS-002 load-compare ON. **82 in-region LOAD
  mismatches, 0 skipped**, feeding the 34 downstream div/divu data mismatches. Per-warp
  first divergence is now the LOAD, upstream of every div: cid=2/3 first@`seq=151
  PC=0x800002d4 LOAD @0x800190a8 DUT=0 vs SimX=0xbdee` (58/53 divergences); cid=1
  first@`seq=992 PC=0x800012b0 LOAD @0x80022ea0 DUT=0xff01 vs SimX=0` (5); **cid=0
  byte-exact** (0 divergences). Mixed polarities across cores (DUT-0/SimX-data on cid2/3,
  DUT-data/SimX-0 on cid1) are consistent with the DUT (timing-accurate) and SimX
  (functional) taking interrupts at different instruction boundaries → different in-flight
  memory content at the load → different loaded byte → different div result. **Interrupt-
  timing reference divergence, NOT a DUT bug** — now proven at the load level (the diverging
  operand is a load, per-instruction). Evidence: `scratchpad/obs002_fullint_2CL.log`.
- **RVVI LOAD-BUS RESULT 2026-07-16 (A1(e), `+LOCKSTEP_LOADFEED`) — PARTIALLY collapsed; residual is
  interrupt-timing, NOT a DUT bug and NOT a keying artifact.** Unlike no_fence (OBS-009, residual 0 →
  fully verified), the two-pass load-bus on `full_interrupt`@2CL collapses **116 cascaded mismatches
  → 7 residual** (data=1, load=6; consumed==pushed=82) but does NOT reach 0. Residual loads:
  `0x80022ea0` (PC 0x800012b0/…c4) on cid2/3, `0x800122df` (PC 0x80002044/…48) on cid3; in pass 2
  they read SimX's own value (e.g. `SimX=0`) — i.e. the feed **did not apply** at that execution.
- **DISPROVEN hypothesis (was "ordinal drift"):** re-keyed the feed from a raw per-warp LOAD ordinal
  to **(cid,wid,PC,occurrence)** — robust to interrupt-inserted (different-PC) instructions — and the
  residual is **IDENTICAL (7, same data=1/load=6)**. A keying/alignment artifact would have changed
  under a drift-robust key; it did not. So the residual is **keying-independent** = a genuine
  interrupt-timing divergence, not a mis-aligned feed. Mechanism (by elimination): **same-PC
  occurrence-count divergence and/or feed-exposed new divergence** — the DUT (timing-accurate) and
  SimX (functional) take the interrupt at different boundaries, so an interrupt-affected PC executes a
  different number of times (or feeding the pass-1 loads shifts SimX state enough to expose a load
  that agreed in pass 1). Neither is fixable by better *load* keying; both need interrupt-*delivery*
  alignment. The load-feed is therefore **not a fixed point** for interrupt tests.
- **NOT a DUT bug:** the end-state MEM compare (real `dut_mem` vs post-feed SimX) **PASSES** — final
  memory equivalent; only transient per-instruction interrupt-boundary ordering differs.
- **Disposition:** `full_interrupt`@multi-cluster = end-state VERIFIED, instruction-granularity
  UNVERIFIABLE (interrupt-timing class). A true fix needs single-pass step-follower lockstep with
  interrupt-delivery alignment, or a bounded fixed-point iterated feed (may not converge for
  interrupts). **Both are logged as deferred backlog items — see
  `docs/INDUSTRIAL_TRANSFORMATION_PLAN.md` → 🔮 DEFERRED ENHANCEMENTS: ENH-1 (step-follower),
  ENH-2 (iterated feed), ENH-3 (residual pinpoint).** **Not forced green.** The PC-occurrence key was
  kept (strictly more robust; no_fence stays residual 0). Evidence: `scratchpad/fullint_2CL.log`
  (ordinal) + `scratchpad/pcocc_fullint.log` (PC-occ, identical residual).

### OBS-005 (REF-MODEL) — SimX does not populate the retire `uuid` (always 0)
- **Class:** REF-MODEL · **Disposition:** worked-around · **Found:** Phase A0 (2026-07-14)
- **What:** The SimX golden's cosim retire record carries `uuid == 0` for every
  instruction, so DUT and SimX uuid schemes cannot be matched 1:1. (`trace->uuid`
  is 0 in this SimX build even though `UUID_WIDTH=44` in RTL.)
- **Evidence:** lockstep summary "uuid alignment: DIVERGENT on 1034/1035";
  `Vortex/sim/simx/core.cpp:235` copies `trace->uuid`.
- **Impact / handling:** uuid is used only as a *cross-check* (reported), never as
  the alignment key. Lockstep aligns by per-`(cid,wid)` program order instead. If a
  future SimX build populates uuid, the cross-check becomes a strict 1:1 assertion.

### OBS-007 (REF-MODEL) — SimX aborts (SIGABRT/SIGSEGV → exit −3) partway through some 2CL random programs
- **Class:** REF-MODEL · **Disposition:** worked-around (UNVERIFIABLE class) · **Found:** Phase A1(d) (2026-07-15)
- **What:** For a freshly regenerated `riscv_no_fence_test` at 2CL/2C/4W/4T, the SimX
  DPI golden **crashes via signal** during run-to-completion (the DPI SIGABRT/SIGSEGV
  handler returns the sentinel −3; scoreboard maps that to UNVERIFIABLE). SimX stops
  emitting retirements at ~seq 4416/core while the DUT runs on to EBREAK (~9900
  wb-retires/core). This is NOT an RTL value divergence — it is a SimX-model
  robustness gap on a random instruction/memory pattern the functional model can't
  handle. IMPORTANT: this is a *different program* from the pinned hex in
  `docs/investigations/SimX_2CL_no_fence_divergence.md` (which had SimX *complete*
  with a per-cluster value divergence) — same test class, different regenerated ELF,
  different failure mode.
- **Evidence:** lockstep run `scratchpad/a1d_no_fence_2CL.log`: `SimX done → exit
  code = -3`, `SimX aborted/crashed … UNVERIFIABLE`; LOCKSTEP SUMMARY compared
  pairs=17664, matched=17664, field_mismatch PC/rd/data=0/0/0, dut_orphan=21992,
  simx_orphan=0; first-divergence per warp = DUT-ORPHAN. DPI sentinel:
  `vortex_uvm_env/uvm_env/ref_model/simx_dpi.cpp:41-44`.
- **ROOT CAUSE (gdb backtrace on native `sim/simx/simx`, 2026-07-15):** SIGABRT (exit
  134) from `vortex::Emulator::decode() [.cold]` → `step()` → `Core::schedule()`.
  The SimX decoder is `default: std::abort();` for every unrecognized opcode/funct
  field (`Vortex/sim/simx/decode.cpp:116,126,136,151,…` — ~15 sites). The random
  `no_fence` program executes a **computed `jalr a3,a3`** (`a3` data-dependent) that
  jumps to an address landing on non-instruction bytes; the decoder can't model them
  and aborts. The DUT's RTL decoder handles unrecognized instructions gracefully
  (illegal-instr/NOP) and runs to EBREAK, so only SimX dies. This is SimX **failing
  loud on genuinely-undefined program behaviour** (wild jump), NOT an RTL fault.
- **ENHANCEMENT (recommended, low-risk):** the abort is arguably correct (a golden
  model should refuse rather than fabricate a result for garbage), so do NOT silence
  it. The real gap is **observability**: the DPI converts the abort to a bare −3 with
  no reason. Make `decode()`'s `default:` print the faulting **PC + instruction word**
  before aborting (or capture them in the DPI SIGABRT handler) → every
  UNVERIFIABLE-by-abort case becomes self-documenting. Only if a printed word turns
  out to be a REAL unimplemented RISC-V instruction (not garbage) is implementing it
  in SimX worthwhile (recovers coverage); the observability fix is the prerequisite
  that tells us which case each abort is.
- **NEW value from lockstep (vs end-state):** lockstep upgrades the verdict from
  "UNVERIFIABLE (nothing known)" to **"DUT ≡ SimX byte-exact for all 17664
  retirements SimX executed, up to the crash"** — the DUT is corroborated
  instruction-by-instruction across all 4 cores of both clusters until SimX dies.
- **Non-vacuity PROVEN (config-specific):** re-run with `+LOCKSTEP_INJECT` on the
  SAME 2CL program flips one bit in one DUT retire → lockstep catches exactly one
  DATA mismatch at seq=0 (`matched 17664→17663`, `field_mismatch data 0→1`,
  `DUT=1 vs SimX=0`), first-divergence on cid=0 only, other cores' orphan boundary
  unchanged. So the 12212 non-load per-lane data compares are live, not a pass.
  Evidence: `scratchpad/a1d_no_fence_2CL_INJECT.log`.

### OBS-011 (RTL BUG — latent, correctness of a guard macro) — `STALL_TIMEOUT` never scales: `1 ** N` ≡ 1
- **Class:** RTL BUG (latent; affects a watchdog threshold, not datapath) · **Disposition:** open — needs-RTL-fix (one-character change); harmless in our runs · **Found:** team bring-up phase (Issue 8 of the 43-issue report `Vortex_UVM_Issues_Report_Final.docx`); verified in-tree 2026-07-16
- **What:** `VX_config.vh:246` defines
  `` `define STALL_TIMEOUT (100000 * (1 ** (`L2_ENABLED + `L3_ENABLED))) `` —
  the intent is clearly to scale the pipeline stall-watchdog timeout with cache-hierarchy
  depth, but `1 ** N` is always 1 in Verilog, so the timeout is a constant 100000
  regardless of L2/L3 being enabled.
- **Evidence:** `Vortex/hw/rtl/VX_config.vh:245-246` (verified at RTL pin `7a52ee5`);
  consumer `VX_schedule.sv` `STALL_TIMEOUT` runtime assert.
- **Impact / handling:** deeper cache hierarchies legitimately lengthen worst-case stall
  latency; a non-scaling watchdog could fire spuriously on large configs (false STALL
  assert), or mask the intent of the guard. Not observed firing falsely in our configs
  (1CL/2CL small programs).
- **✅ DISPOSITION CORRECTED 2026-08-19 — this entry said "open / needs-RTL-fix / left as
  upstream-reportable" long after it had been FIXED TWICE. Do not quote it as open.**
  1. **Fixed in-tree** (found while diffing against upstream): `VX_config.vh` now defines
     `` `STALL_TIMEOUT_SCALE (4 ** (`L2_ENABLED + `L3_ENABLED)) `` with a comment citing this
     observation, and `STALL_TIMEOUT` uses it.
  2. **Fixed INDEPENDENTLY UPSTREAM**, which is external corroboration that the finding was real:
     at upstream HEAD (`d76b7f24e`) it lives at `VX_gpu_pkg.sv:224` as
     `(100000 * (1 << (`VX_CFG_L2_ENABLED + `VX_CFG_L3_ENABLED)))` — a SHIFT (2^N) where we used
     `4 **`. Same defect, same conclusion, arrived at separately.
  **Status: FIXED (locally and upstream).** Retained as a finding with a track record, not as
  open work.

### OBS-012 (RTL BUG — ISA spec deviation) — JALR does not clear the target's LSB; no misaligned-fetch exception; odd PC propagates into architectural results via AUIPC
- **Class:** RTL BUG (RISC-V unpriv spec, JALR: "target address … setting the
  least-significant bit of the result to zero" — Vortex omits the clear; and a
  bits[1:0]≠0 target on a non-C core should raise instruction-address-misaligned,
  which Vortex has no trap for) · **Disposition:** worked-around (stimulus
  sanitization, INV-4) — needs-RTL-fix upstream · **Found:** A5 gate investigation
  (2026-07-16); mechanism first surfaced in A1(d)/OBS-008 (2026-07-15).
- **What:** `VX_alu_int.sv:222` `cbr_dest = from_fullPC(add_result[0])` — the jalr
  destination is the raw `rs1+imm`, no `& ~1`. In the **debug** build
  (`PC_BITS=`XLEN``, `to/from_fullPC` identity, `VX_gpu_pkg.sv:75-82`) the odd bit
  survives as the **architectural PC**. Fetch silently word-aligns
  (`VX_fetch.sv:101`) so execution continues on the correct instruction words, but
  the PC stays skewed → every `auipc`/`la` result (`rd = PC + imm`) inherits the
  skew; through chained jumps/link-register writes (rd = PC+4) the offset
  accumulates (observed +1 → +3) → downstream loads/stores go misaligned →
  OBS-013 silent corruption + LSU RUNTIME_ASSERT storms.
- **Trigger (spec-legal stimulus):** riscv-dv deliberately exercises the spec's
  LSB-clear: `riscv-dv/src/riscv_directed_instr_lib.sv:162-165` adds
  `offset = $urandom_range(0,1)` to the jalr base register (comment: "JALR is
  expected to set lsb to 0") — ~half of generated jumps target `label+1`.
- **Evidence:** 2026-07-10 suite: **12/12 riscv-dv profiles** fire misaligned
  asserts (30–7616 per run). `run_104133` (`riscv_jump_stress_test`): assert PCs
  `0x80001887..0x800018fb` (stride 4, all = instr_addr+3) inside the riscv-dv
  register-dump routine (`sw rX, off(t6)` block before `_vortex_done`,
  objdump-verified), store addrs `0x80008083..` = auipc-derived `t6` = base+3.
  Post-OBS-008 lockstep run 2026-07-14 (`no_fence`): 18 lockstep UVM_ERRORs =
  the DUT/SimX divergence this causes, now detectable per-instruction.
- **Release-build note:** release `PC_BITS=XLEN-2` drops PC bits[1:0] in
  representation, so a `label+1` target lands spec-correct **by accident**; the
  deviation is architecturally visible in the debug build we verify (and a
  `label+2` target would silently word-align in release where spec demands a trap).
- **Impact / handling:** all riscv-dv random-jump programs derail on Vortex;
  pre-OBS-008 these runs were silently UNVERIFIABLE (SimX fetch-abort), post-fix
  they diverge detectably. SimX deliberately mirrors the no-clear behaviour
  (`execute.cpp:469`, OBS-008) — an RTL fix (`& ~1` at the dest adder) must
  un-mirror SimX in the same change. Chosen handling: sanitize stimulus
  (riscv-dv jalr offset → 0, INV-4) + report upstream; RTL left untouched at pin
  `7a52ee5`. Corrects OBS-008's "benign — low bits never reach an architectural
  result" note.

### OBS-013 (QUIRK/EXPECTED — hazardous failure mode) — misaligned data access: no trap, silently retargeted/torn access; RUNTIME_ASSERT is the only guard
- **Class:** QUIRK/EXPECTED (misaligned data access is documented-unsupported —
  the RTL asserts) with an ENHANCEMENT edge (no misaligned-address exception
  exists, so silicon has **zero** detection: sim-only assert) · **Disposition:**
  wontfix/expected (SW contract: aligned-only, Vortex toolchain/runtime always
  comply) — assert routed into the run verdict by the A5 gate · **Found:** A5
  investigation (2026-07-16); assert itself known since the riscv-dv misaligned
  episode (2026-07-03).
- **What (the silent-corruption mechanism):** `VX_lsu_slice.sv:159-184` — the
  byte-enable TRUNCATES the address low bits per size: 16-bit uses
  `{align[1],1'b0}`/`{align[1],1'b1}` (addr bit 0 discarded → a `sh/lh` at an odd
  address is retargeted to the aligned halfword slot); RV32 32-bit misaligned
  falls into `default` full-word byteen (reads/writes the containing aligned word
  only — never crosses into the next word as the ISA's byte-span semantics
  require). Store data is separately shifted by the full `req_align`
  (`VX_lsu_slice.sv:195-210`), so enable-set and data-shift disagree → **torn
  bytes at a wrong address, no error indication to software**. Detection is only
  `VX_lsu_slice.sv:189` `RUNTIME_ASSERT` (sim-only; compiled out under
  SYNTHESIS).
- **Golden-model contrast:** SimX performs the access byte-accurately at the
  exact address → any boundary-crossing misaligned access is a **guaranteed
  DUT≠SimX divergence** (proven: lockstep 2026-07-14 no_fence, 18 errors).
- **Same class, CSR flavor:** an invalid CSR write asserts
  (`VX_csr_data.sv:150`) instead of raising illegal-instruction (no trap
  architecture) — `riscv_illegal_instr_test` trips it (CSR `0x6f3`,
  `run_105050` 2026-07-10). Same disposition: stimulus must not send it.
- **Impact / handling:** aligned-only is the SW contract; violations are
  silent data corruption in silicon. Handling: (1) A5 gate makes any assert
  firing FAIL the run (defense in depth, catches contract violations in any
  stimulus); (2) INV-4 stimulus sanitization removes the riscv-dv source
  (OBS-012 cascade); (3) upstream ENHANCEMENT suggestion: misaligned-address
  trap or at least a sticky error CSR.

### OBS-014 (RTL BUG / accuracy limitation) — hardware `fsqrt.s` deviates 1 ULP from the IEEE-correct result
- **Class:** RTL FPU accuracy deviation (IEEE-754 §5.4.1 requires `sqrt` to be
  correctly rounded) · **Disposition:** DOCUMENTED + HANDLED (bounded 1-ULP tolerance
  for `fsqrt` writebacks + two-pass reconvergence feed; the deviation itself remains a
  real, cited RTL limitation) · **Found:** 2CL lockstep sweep FP investigation
  (2026-08-05), fpu_test / fpu_mt @1CL · **Handled:** 2026-08-06.
- **What:** at `fpu_test.dump` PC=`0x800000e8` `fsqrt.s fa0, fs0`, per-instruction
  lockstep reports lane0 `DUT=0x3fef7750` vs `SimX=0x3fef7751` — **adjacent float32
  values, 1 ULP apart**. fpu_mt shows the same signature on other inputs
  (`0x3fef7750` vs `…7751`, `0x402f456e` vs `…456f`). The `fdiv.s` at the adjacent
  PC=`0x800000e0` (same operands class) **matched exactly**, so the hardware divider
  is correctly rounded but the **sqrt unit is not**.
- **Why SimX is the reference:** SimX computes `fsqrt` via Berkeley SoftFloat
  (`Vortex/third_party/softfloat`), the canonical correctly-rounded IEEE
  implementation → the 1-ULP deviation is on the DUT side (cvfpu/FPnew sqrt unit,
  likely an area-optimized non-correctly-rounded configuration).
- **Why it was invisible until now:** the END-STATE scoreboard uses an FP-tolerant
  compare for fpu kernels (absorbs ≤1 ULP), so it PASSED — the per-instruction
  lockstep is what surfaced it. In fpu_test the rounded result then feeds downstream
  FP ops and a compare/branch, cascading (1488 divergences, 112 SimX-orphans from a
  control-flow split); fpu_mt is smaller (4 isolated 1-ULP writebacks).
- **Impact / handling (DONE — option (b), the industrial two-pass form):** the
  lockstep still flags the deviation (never silently tolerated), then handles it in
  two layers so `fpu_test`/`fpu_mt` verify without loosening any other op:
  1. **Bounded 1-ULP tolerance, `fsqrt`-ONLY.** SimX exports an `is_fsqrt` flag
     (`simx_cosim_record.h` / `core.cpp` via `std::get_if<FpuType>`). The comparator
     tolerates an `fsqrt` writeback iff DUT and SimX are same-sign, finite, ≤1 ULP
     apart (`fp32_within_ulp`); every toleranced op is LOGGED and tallied
     (`n_fp_ulp_tol`). `+ - * / fma cvt` stay bit-exact — a deviation there is still a
     hard failure; an `fsqrt` >1 ULP off, or a NaN/Inf mismatch, also still fails.
  2. **Two-pass sqrt reconvergence feed** (the accepted-divergence reconvergence
     technique; mirrors the OBS-009 load-bus feed). The 1-ULP `fsqrt` result
     propagates (spill/reload + dependent `fmul`), which would cascade as false
     downstream errors. Pass 1 records the certified-in-bound `fsqrt` result; pass 2
     forces it into SimX's FP regfile (`compfeed_*` in `emulator.cpp` / `execute.cpp`,
     re-NaN-boxed for the FLEN=32 build) so SimX continues with the DUT's accepted
     value and **every downstream op is re-checked bit-exact**. Residual 0 ⇒ the sqrt
     is the ONLY deviation. FP-dest loads are excluded from the (integer-only) load
     feed so they reconverge through the sqrt feed's store→flw, not an unboxed
     override.
  - **Result:** `fpu_test` GREEN (pass-2 residual 0, matched 1675). `fpu_mt` GREEN
    (pass-2 residual 0, 4 sqrt reconvergences). Gated on `+LOCKSTEP_LOADFEED` (arms
    both feeds); default single-pass is byte-identical and shows the tolerated direct
    sqrt only.
  - **Follow-on bug found + fixed (same session):** `fpu_mt` initially still reported 2
    UVM_ERRORs ("no functional verification performed"). Root cause was NOT a missing
    checker — it was a **phase-ordering false verdict** in the non-vacuity gate
    (`kernel_launch_test.check_results()`, run_phase): under `+LOCKSTEP_LOADFEED` the
    end-state MEM compare is deliberately deferred to the scoreboard's report_phase
    (post-feed SimX, `endstate_feed_mode`), and lockstep compares in check_phase — so
    both counters are legitimately 0 when the gate reads them. `fpu_mt` in fact performs
    **68** end-state comparisons + **1412** lockstep pairs. Fixed by deferring the
    non-vacuity verdict to the test's `report_phase` (after both). Non-vacuity is NOT
    weakened: a run where both are 0 still FAILS. Both Gate-0 negative guards re-verified
    green (`negative_result_test`, `negative_dropped_store_test` both still DETECT).
  - **The RTL itself is unchanged and still deviates** — this is a verification-side
    accommodation of a cited hardware limitation, not a fix. A bit-accurate reference
    sqrt matching cvfpu was rejected (it would degrade SoftFloat's independent IEEE
    correctness). FLEN=64 `fsqrt.d` is future work.

---

### OBS-015 (REF-MODEL BUG + RTL QUIRK) — SIMT-divergent CSR access: SimX serializes lanes over per-warp `fcsr`; RTL reads-broadcast / writes lane 0 unconditionally
- **Class:** REF-MODEL (golden-model correctness bug) **+** RTL quirk (unmasked lane-0
  write) · **Disposition:** REF-MODEL bug **FIXED** (read-once/write-once, lowest ACTIVE
  lane); RTL quirk left OPEN and deliberately VISIBLE (not mirrored into the reference) ·
  **Found:** `sfu_masks` @1CL per-instruction lockstep (2026-08-06) · **Fixed:** same day.
- **What we saw:** `sfu_masks` lockstep at 1CL/1C/4W/4T reports **109 `data`
  field-mismatches, 0 PC / 0 rd / 0 orphan** (matched 3129). Every divergence is on an
  FP-CSR access under a *peeled/divergent* thread mask, e.g.
  `PC=0x800000c0 fsrm a3,a3` → lane1 `DUT=0 vs SimX=1`, lane3 `DUT=0 vs SimX=3`; and
  `PC=0x800000ec fsrm a5,a5` → lane0/1 `DUT=1 vs SimX=2`
  (`Vortex/tests/kernel/sfu_masks/sfu_masks.dump:61,72`; `fsrm` = `csrrw rd, frm, rs1`,
  which must return the **OLD** CSR value).
- **Both sides agree the CSR is PER-WARP:** RTL `reg [`NUM_WARPS-1:0][...] fcsr`
  (`VX_csr_data.sv:81`, read/written by `read_wid`/`write_wid`); SimX `Byte fcsr` inside
  `struct warp_t` (`emulator.h:61`), read via `warps_.at(wid).fcsr`
  (`emulator.cpp:476-478`). So a per-LANE-varying result cannot be architectural state.
- **ROOT CAUSE (ref-model):** SimX's CSR ops loop lanes **sequentially over that shared
  per-warp state** (`execute.cpp:1318-1326` CSRRW, and the same shape for CSRRS/CSRRC):
  each active lane does `get_csr` → `set_csr` → return-old. Because the storage is
  per-warp, lane *t* reads **what lane *t−1* just wrote** — so the returned "old" value
  differs per lane and the committed CSR ends up as the **LAST active lane's** value.
  That is a simulation artifact of iterating lanes over shared state, not a defensible
  semantics: a warp-wide `csrrw` reads the CSR once.
- **RTL behaviour (self-consistent, and the sane SIMT semantics):**
  `csr_read_data = {NUM_LANES{csr_read_data_ro | csr_read_data_rw}}`
  (`VX_csr_unit.sv:134`) — the old value is read once and **broadcast to every lane**
  (matches the observed `DUT=0` on all lanes); the write happens once per warp.
- **RTL QUIRK (separate, real):** the written value is
  `csr_req_data = ... ? csr_imm : rs1_data[0]` (`VX_csr_unit.sv:142`) — **hardwired to
  lane 0 with NO tmask qualification**. If lane 0 is *inactive* under a divergent mask,
  the per-warp CSR is still written with lane 0's (stale//inactive) `rs1` value rather
  than a value from an active lane. `sfu_masks` exercises exactly this (peeled masks
  around `vx_split`, `sfu_masks.dump:69-72`). Not ISA-illegal (RISC-V does not define
  SIMT-divergent CSR writes) but it is a surprising, undocumented choice worth citing.
- **Why end-state missed it:** `sfu_masks` deliberately folds its CSR results to 0
  before storing (so `out_buf` ⊥ `fcsr`) — it was written as a *coverage* kernel for
  `cross_sfu_threads`. End-state therefore PASSES; only per-instruction lockstep sees
  the divergent `rd` writeback. Same payoff class as OBS-014.
- **Proposed fix (ref-model side, NOT the RTL):** make SimX model warp-wide CSR access
  the way the machine actually works — snapshot the CSR **once** before the lane loop,
  return that snapshot to **all** active lanes, and apply a **single** write. Deliberate
  question to settle first: whether the write should take lane 0 unconditionally (bit-
  matches the RTL, but bakes an RTL quirk into the reference) or the lowest **active**
  lane (architecturally cleaner — and any residual divergence would then be a genuine
  RTL finding, i.e. the quirk above).
- **APPLIED (2026-08-06): lowest ACTIVE lane** (user-selected). `execute.cpp` CsrType
  lambda is now two-phase: PHASE 1 reads every active lane BEFORE any write (kills the
  aliasing; genuinely per-thread CSRs such as THREAD_ID stay per-lane), PHASE 2 applies
  exactly ONE write sourced from the lowest ACTIVE lane (CSRRS/CSRRC skip it when the
  source operand is 0, matching `csr_wr_enable` and the ISA). The RTL's unconditional
  `rs1_data[0]` is deliberately NOT mirrored, so the reference stays independent and a
  future lane-0-masked-off divergence is still reported rather than silently agreed with.
- **Result:** `sfu_masks` @1CL RED→**GREEN** — `field_mismatch data` **109 → 0**, matched
  3129→**3178**, 0 PC / 0 rd / 0 orphan, 0 UVM_ERROR. The residual after choosing
  lowest-active-lane is **zero**, i.e. the RTL lane-0 quirk did not actually manifest in
  this kernel — so the pass required no accommodation of it. Regression (all @1CL,
  lockstep+loadfeed): vecadd_lite 1035, fpu_test 1675, tcu_test 785, diverge_fpu 2738 —
  all `data` mismatch 0, 0 UVM_ERROR; both Gate-0 negative guards still DETECT.

---

### OBS-016 (TB BUG — blocking) — the optional cache levels (L2/L3) were impossible to build: TB expands RTL *presence* guards as if they had values
- **Class:** TB/infrastructure bug (not RTL) · **Disposition:** **FIXED** ·
  **Found:** 2026-08-06, first attempt to build with `L2_ENABLE`/`L3_ENABLE` on.
- **What we saw:** rebuilding at 2CL with `+define+L2_ENABLE +define+L3_ENABLE` broke the
  build — `vortex_config.sv(571)/(577): near ";": syntax error, unexpected ';'`, and every
  subsequent run died at elaboration with
  `vortex_dcr_if.sv(106): (vopt-2730) Undefined variable: 'VX_DCR_BASE_STARTUP_ADDR0'`
  (a *downstream* symptom: the config package failed to compile, so everything that
  depended on it was undefined).
- **ROOT CAUSE:** in the Vortex RTL these are **presence guards defined with NO value** —
  `VX_config.vh:533` ``define ICACHE_ENABLE``, `:588` ``define DCACHE_ENABLE``, and L2/L3
  are consumed as ``ifdef L2_ENABLE -> `define L2_ENABLED 1`` (`:845-856`). The TB's
  `vortex_config.sv` instead expanded them **as if they carried a value**:
  ``l2_enable = `L2_ENABLE;`` → expands to ``l2_enable = ;`` → syntax error. The bug is
  latent while the macros are undefined (the `else` branches supply 0/1), so it never fired
  in any previous build — but it made the optional cache levels **unbuildable**.
- **Impact:** L2 and L3 are `PASSTHRU` by default (`VX_cluster.sv:107`, `Vortex.sv:96`;
  `VX_cache_wrap.sv:160` instantiates the real `VX_cache` storage only when `PASSTHRU==0`),
  so **those two cache levels have never been exercised or verified in this project** — and
  could not have been, because turning them on did not compile. The existing L2/L3
  "structural passthru" coverage waivers were therefore load-bearing in a way we had not
  realised: they waived RTL that was unreachable *by construction of the TB*, not only by
  configuration choice.
- **FIX:** mirror the RTL's presence semantics in `vortex_config.sv` (assign `1` inside the
  ``ifdef``, keep the existing `else` defaults). Tolerates an explicit `=1` form too.
  Default builds (macros undefined) are byte-identical — only the `else` branches run.
- **Also added:** `EXTRA_RTL_DEFINES` passthrough in `scripts/compile.sh` (empty by default
  ⇒ byte-identical) so non-default RTL configs can be built without editing the script:
  `EXTRA_RTL_DEFINES="+define+L2_ENABLE +define+L3_ENABLE" make sim ...`
- **Follow-up:** with the build fixed, re-run the 2CL lockstep sweep **with L2+L3 enabled**
  to (a) exercise the two previously-dead cache levels for the first time and (b) test
  whether the OBS-009 cross-cluster race class changes. Prediction on file BEFORE the run:
  it should **not** change — the staleness lives in the per-socket L1 dcaches, which have no
  invalidation (no `snoop|coheren|invalidat|MESI` anywhere in `hw/rtl/cache/*.sv`); L2/L3
  only back *misses*, and at `SOCKET_SIZE=2` both cores of a cluster already share one L1.

---

### OBS-017 (RTL BUG — verification guard, blocking for L2/L3 configs) — `VX_mem_scheduler` hardcodes a ~1000-cycle response timeout that ignores the configurable `STALL_TIMEOUT` and does not scale with cache depth
- **Class:** RTL BUG (runtime-assert guard; the datapath itself is correct) ·
  **Disposition:** **FIXED** (guard-only RTL change, validated) ·
  **Found:** 2026-08-06, first-ever build with `L2_ENABLE`+`L3_ENABLE` (unblocked by OBS-016).
- **What we saw:** with L2+L3 enabled at 2CL/2C/4W/4T, **every** tier-1 kernel emitted a flood
  of `*** <core>-execute-lsu0-memsched response timeout: tag=0x...` RTL errors — e.g.
  `tcu_test` produced **22,187** of them starting at t=148,095,000 ps. Because the A5
  RTL-assert gate counts `** Error:` lines, every run returned `make rc=2` (RED) — including
  kernels that are perfectly lane-exact.
- **IT IS A FALSE ALARM, NOT A HANG — the DUT is correct.** The same `tcu_test` run reached
  **EBREAK at 21,968 cycles**, lockstep **matched 2789/2789** (0 PC / 0 rd / 0 data / 0 orphan),
  `UVM_ERROR: 0`, `*** TEST PASSED ***`. The memory responses *did* return; they merely took
  longer than the guard allows. So the guard, not the design, is what fails.
- **ROOT CAUSE:** `libs/VX_mem_scheduler.sv:91` declares its own
  ``localparam STALL_TIMEOUT = 10000000;`` which **shadows** the configurable global
  (`VX_config.vh:246`, `VX_gpu_pkg.sv:109`). The assert at `:580` is
  ``($time - pending_reqs_time[i]) < STALL_TIMEOUT``. With the TB at ``timescale 1ns/1ps`` and
  `CLK_PERIOD=10` (`vortex_tb_top.sv:15,31`), `$time` is in ps and one cycle = 10,000 ps ⇒ the
  budget is **10,000,000 ps = 1,000 cycles**. A full L1→L2→L3→DRAM miss chain under 4-core
  contention exceeds that routinely, so the guard fires spuriously. Two consequences:
  1. It is **hardcoded** — `+define+STALL_TIMEOUT=...` cannot tune it, because the localparam
     shadows the global inside this module.
  2. It **does not scale with cache depth**, which is precisely what the global was written to
     do — and that global is itself broken, see next point.
- **RELATIONSHIP TO OBS-011 (which this run promotes from *latent* to *confirmed*):** the global
  is ``(100000 * (1 ** (`L2_ENABLED + `L3_ENABLED)))``. Since ``1 ** N ≡ 1``, it never scales.
  The clear intent was "widen the stall/response budget when extra cache levels are added" —
  exactly the configuration that now floods. So the one mechanism designed to prevent this is
  a no-op, AND the memory scheduler ignores it anyway. OBS-011 is no longer theoretical.
- **⚠️ CORRECTION to the first-draft fix (would have made things WORSE):** "delete the shadowing
  localparam and use the package value" is **wrong** — the two guards are in **different units**.
  The global is a CYCLE count (`timeout_ctr < STALL_TIMEOUT`, incremented once per clock,
  `VX_schedule.sv:409-415`); the mem-scheduler one is a **simulation-TIME** delta
  (`($time - pending_reqs_time[i]) < STALL_TIMEOUT`). At 1ns/1ps with a 10ns clock, 1 cycle =
  10,000 time units, so feeding the cycle-domain 100000 into the time-domain compare yields a
  **10-cycle** timeout — ~100x TIGHTER than the value that was already misfiring.
- **FIX APPLIED (2026-08-06):**
  1. `VX_config.vh:245-255` — new ``STALL_TIMEOUT_SCALE = (4 ** (`L2_ENABLED + `L3_ENABLED))``
     (was the no-op `1 ** N`), and `STALL_TIMEOUT = 100000 * STALL_TIMEOUT_SCALE`. Both are
     ``ifndef``-guarded ⇒ overridable from the terminal via `+define+`.
  2. `VX_gpu_pkg.sv:109` — was a second, independent copy of the same broken expression; now
     ``localparam STALL_TIMEOUT = `STALL_TIMEOUT;`` so the two cannot drift.
  3. `VX_mem_scheduler.sv` — keeps its TIME-domain semantics (correctly), but the hardcoded
     `10000000` becomes ``ifndef``-guarded ``MEM_STALL_TIMEOUT = 10000000 * `STALL_TIMEOUT_SCALE``,
     so it scales with cache depth and is terminal-overridable. Added ```include "VX_define.vh"``
     (include-guarded; same pattern as `VX_avs_adapter.sv`/`VX_stream_xbar.sv`) so the macro is
     deterministically visible rather than relying on cross-file macro leakage.
- **VALIDATION (guard-only ⇒ behaviour must not move):** `tcu_test` @2CL/2C/4W/4T —
  · **default build:** 12,215 cycles, matched 2789, **0** timeouts, `UVM_ERROR 0`, rc=0 —
    byte-identical to pre-fix (scale = 4^0 = 1 ⇒ same values, no regression).
  · **L2+L3 build:** 21,968 cycles, matched 2789, timeouts **22,187 → 0**, `UVM_ERROR 0`,
    **rc=2 → rc=0**. Cycle count and matched count unchanged from the pre-fix L2/L3 run,
    confirming only the false alarm was removed, not any DUT behaviour.

---

### OBS-018 (RESULT — architectural, confirms OBS-009) — enabling the shared L2+L3 caches does NOT remove the cross-cluster divergences
- **Class:** architectural result (verification evidence for OBS-009) · **Disposition:** closed —
  question answered · **Found:** 2026-08-06.
- **Experiment:** rebuilt at 2CL/2C/4W/4T with `L2_ENABLE`+`L3_ENABLE` (the optional levels are
  `PASSTHRU`/pure-bypass by default) and re-ran the full 15-kernel tier-1 lockstep sweep.
  **Prediction was recorded BEFORE the run** (see OBS-016 follow-up) that the races would persist.
- **L2/L3 were genuinely elaborated** — not merely defined. Verified from the run's coverage
  database: `vcover report -recursive <ucdb>` lists **`l2cache`** and **`l3cache`** instances
  alongside `dcache`/`icache`. (Grepping the sim log for the names is NOT sufficient evidence —
  `dcache` does not appear there either.)
- **L2/L3 measurably CHANGED TIMING — so the null result is not "the flags did nothing".**
  Same kernel, same 2CL config, `tcu_test`: **12,215 cycles** with L2/L3 passthru
  (`results/20260806/run_184629_*`) vs **21,968 cycles** with L2+L3 enabled
  (`run_191734_*`) — **+80% runtime**. (Extra levels add lookup/miss-traversal latency;
  these small directed kernels have too little reuse to earn hits back. This is also why
  the OBS-017 1,000-cycle response guard blows.) So memory timing shifted substantially
  while the architectural outcome did not move at all — see next point.
- **RESULT: bit-identical to the PASSTHRU baseline on all 15 kernels** (mechanically diffed:
  `compared=`, `matched=`, and `mm[PC,rd,data,LOAD]` all equal). 7 lane-exact
  (vecadd_lite, tcu_test, tcu_mt, vote_shfl, div_edge, spawn_tmc_sweep, bar_masks); the same 8
  kernels diverge by exactly the same amounts (e.g. diverge_fpu/uni3/sfu_masks `data=222 LOAD=32`).
- **WHY (and why this was predictable):** the staleness lives in the **per-socket L1 dcaches**,
  which have **no invalidation** — a scan of `hw/rtl/cache/*.sv` for
  `snoop|coheren|invalidat|MESI|MOESI|probe_req` returns **zero hits**; the only cross-cache
  mechanism is `flush` (`VX_cache.sv:118-137`). Adding L2/L3 provides a common backing store for
  *misses*, but a core whose L1 already holds a line still hits stale data. Additionally, at
  `SOCKET_SIZE=MIN(4,NUM_CORES)=2` both cores of a cluster already share ONE L1
  (`VX_socket.sv:135-138`), so intra-cluster traffic was never the issue.
- **The strongest form of the result:** timing changed by **+80%** yet **not one bit** of the
  architectural outcome moved. That rules out the "these are timing flukes / jitter" reading:
  whether a core reads stale data is decided by *whether its L1 already holds the line* — a
  property of the program's access pattern, not of latency. Adding levels changes WHEN things
  happen, not WHETHER a stale line is hit. The divergences are therefore structural, and
  reproduce deterministically.
- **Significance:** this is direct experimental confirmation that the OBS-009 divergences are the
  **published weak-coherence memory model** (MICRO'21 §4.1.4: *"Flush operations among caches are
  provided as a means of providing weak coherent memory space"*; §3.1 uses the RISC-V `fence` for
  memory synchronization) — NOT a missing-cache artifact and NOT a DUT bug. Coherence in Vortex is
  the program's responsibility via fence/flush; a fenceless cross-cluster kernel has no
  architecturally-defined single result, so DUT≠SimX there is expected.

---

### OBS-019 (TB BUG — silent config drift) — UVM `vortex_config.sv` duplicated the RTL cache geometry as hand-written fallbacks, and had drifted (L3 = 1 MB vs RTL 2 MB)
- **Class:** TB/infrastructure bug (config fidelity) · **Disposition:** **FIXED** ·
  **Found:** 2026-08-06, while auditing "is everything parametrized, nothing hardcoded".
- **What we found:** `vortex_config.sv` set the cache geometry with `` `ifdef X / `else <literal> ``
  pairs whose `else` branch **restated the RTL default by hand**:
  ```
  `ifdef L3_CACHE_SIZE  l3_cache_size = `L3_CACHE_SIZE;
  `else                 l3_cache_size = 1048576;   // "1MB"
  ```
  Two problems compounded:
  1. **The fallbacks were ALWAYS the values actually used.** The UVM `vlog` gets
     `$COMPILE_OPTS` (so command-line `+define+`s reach it) but does **not** include
     `VX_config.vh` — so `` `DCACHE_SIZE ``/`` `L3_CACHE_SIZE `` etc. are undefined there and
     every `` `ifdef `` took the `else` path.
  2. **They had drifted.** RTL `L3_CACHE_SIZE` is **2097152 (2 MB)** (`VX_config.vh:750`);
     the TB fallback said **1048576 (1 MB)** — a silent 2x mismatch between what the TB
     believed and what was elaborated. `cache_line_size` was likewise hardcoded to `64`
     instead of tracking `MEM_BLOCK_SIZE`.
  This is precisely the drift class the I2 topology assert exists to prevent for
  cores/warps/threads — but the cache geometry had no such guard.
- **FIX (single source of truth, no duplication possible):**
  1. `VX_gpu_pkg.sv` now **exports** the geometry the RTL actually elaborated with:
     `ICACHE_SIZE_BYTES`, `DCACHE_SIZE_BYTES`, `L2_CACHE_SIZE_BYTES`, `L3_CACHE_SIZE_BYTES`,
     `CACHE_LINE_SIZE_BYTES`, `L2_IS_ENABLED`, `L3_IS_ENABLED`.
  2. `vortex_config.sv` reads them directly (`VX_gpu_pkg::…`) — the same pattern already
     endorsed at the top of that file for `VX_MEM_TAG_WIDTH` (*"derived from RTL — never
     hardcode"*). All hand-written fallbacks and the hardcoded line size are gone.
  Because anything set from the terminal flows through the RTL macros into the package,
  a terminal override (`make sim … L2=1 L3=1`) is now reflected in the TB automatically —
  TB and RTL cannot disagree by construction rather than by manual sync.
- **Note:** this also means the TB's cache view was wrong for every previous run that
  consulted `l3_cache_size`/`cache_line_size`. Nothing in the current checkers keys off
  them (they are informational/randomization bounds), so no past result is invalidated —
  but the mismatch would have silently mis-shaped any future cache-aware stimulus.
- **RELATED HAZARD FOUND IN THE SAME AUDIT — runtime plusargs overriding STRUCTURAL config
  (FIXED).** `apply_plusargs()` let `+L2CACHE`/`+L3CACHE` do ``l2_enable = 1`` and
  `+XLEN_64` do ``xlen = 64`` **at runtime**. These are all fixed at ELABORATION
  (`VX_cache_wrap.sv:160` instantiates `VX_cache` only when `PASSTHRU==0`; XLEN and the
  AXI wrapper are compile-time), so such a plusarg cannot reconfigure hardware — it can
  only make the TB *believe* something the DUT does not implement, after which every
  downstream check is measured against a fiction. The project already had the right
  pattern for topology (I2 elaboration asserts); it simply was not applied to the rest.
  **Fix:** the I2 gate in `vortex_tb_top.sv` now also covers XLEN, L2, L3 and the memory
  interface, and `vortex_config.sv` turns the cache plusargs from an OVERRIDE into a
  CHECK. Each failure names the fix, e.g.
  `+L2CACHE requested but the RTL was elaborated WITHOUT L2 (PASSTHRU/bypass) -- rebuild with make sim ... L2=1`.
  Two different remedies, chosen deliberately: **sizes/geometry → single source of truth**
  (drift impossible by construction, no assert needed), **enables/topology → assert**
  (legitimately terminal-settable, so verify the request matches the build).
- **GUARDS PROVEN NON-VACUOUS (an assert never seen to fire is worthless):**
  `EXTRA_PLUSARGS="+L2CACHE"` on an L2-less build → **rc=2**, `[I2-ASSERT] +L2CACHE
  requested but the RTL was elaborated WITHOUT L2 …`; `EXTRA_PLUSARGS="+XLEN_64"` on the
  RV32 build → **rc=2**, `[I2-ASSERT] +XLEN_64 requested but the RTL was compiled XLEN_32 …`.
  (`EXTRA_PLUSARGS` was added to `simulate.sh` as the sim-time counterpart of
  `EXTRA_RTL_DEFINES`; empty by default ⇒ byte-identical.)
- **VALIDATION of the whole change:** clean 1CL rebuild, **0 compile errors**; new gate line
  `[I2-ASSERT] Structural config OK: XLEN=32 L2=0 L3=0 icache=1 dcache=1 (RTL == UVM)`;
  lockstep regression all `data`-mismatch 0 / `UVM_ERROR 0` — vecadd_lite **1035**,
  tcu_test **785**, fpu_test **1675**, sfu_masks **3178**; both Gate-0 negative guards
  still DETECT their injected faults.

---

### OBS-020 (REF-MODEL ROBUSTNESS — observability limit) — most of SimX's `std::abort()` surface is in the **disassembly pretty-printer**, not the decoder: a run can be classified UNVERIFIABLE because the golden could not *name* an instruction
- **Class:** golden-model robustness / observability limit · **Disposition:** **FIXED (A3 closed)** ·
  **Found:** 2026-08-06, while scoping how much of A3 remains and whether it depends on A6/Spike.
- **What we found.** The abort surface was being counted as one undifferentiated bucket
  ("69 `std::abort` in decode/execute"). Reading the source shows it is **two populations
  with completely different verification value**:

  | Site | Count | What it means | Verification value of aborting |
  |---|---|---|---|
  | `decode.cpp:53-496` `op_string()` | **~34** | `default:` over an enum sub-field of an **already-decoded** instruction, reached only when a trace line is formatted | **None** |
  | `decode.cpp:523-1146` `Emulator::decode()` — `DECODE_ABORT()` | **13** | genuinely cannot decode the encoding | Legitimate (a golden must refuse, not fabricate) |
  | `execute.cpp` | **22** | `default:` over funct3/funct7/rm of an already-decoded op — real semantic gap | Legitimate |
  | `emulator.cpp` | **5** | infrastructure (`size != 1` @:425; CSR @:588/593/640) | Mixed |

- **Evidence that the `op_string()` population is disassembly-only:** `op_string` is
  `static` (`decode.cpp:53`) and its **only** consumer is
  `operator<<(std::ostream&, const Instr&)` at `decode.cpp:500`. It is not on the
  execution path — it cannot affect an architectural result. Yet it calls `std::abort()`,
  so an instruction that *executed correctly* can still kill the process, and the harness
  maps SIGABRT → exit `-3` → **UNVERIFIABLE**. A whole program then yields **no verdict**
  for a cosmetic reason.
- **Why this matters for A3.** A3 ("retire the UNVERIFIABLE bucket") was sized at ~69
  sites. The real *semantic* surface is **13 decode + 22 execute + ~4 emulator ≈ 39**;
  the ~34 disassembly sites are a one-line fix each (return `"UNKNOWN"` / the raw hex
  instead of aborting) and remove a failure mode that has **zero** correctness value.
- **Fix direction (not yet applied):** (1) `op_string()` → never abort; emit
  `{"UNKNOWN.<hex>", ""}` so a trace stays readable and the run survives. (2) the 13
  `DECODE_ABORT()` + 22 `execute.cpp` sites → either implement the encoding, or return a
  graceful *unsupported* sentinel that marks **that instruction** UNVERIFIABLE while the
  rest of the run still produces a verdict. Principle: **one exotic instruction must not
  void an entire program's result.**
- **A3 does NOT depend on A6/Spike.** Spike is a *scalar* base-RISC-V ISS with no SIMT
  model (no `wspawn/tmc/split/join/bar`, no warps/tmask) — plan §A.3 — so it cannot execute
  a Vortex kernel and can never be the golden that produces the missing verdict; it is
  scoped as a per-thread base-ISA cross-check only (plan A6, line 425). The one class where
  "Spike decodes it, SimX aborts" is literally true is **RVC**, and RVC is already excluded
  upstream at the toolchain level (`prepare.sh:321` `--target=rv32im`, `:492`
  `-march=rv32im_zicsr_zifencei`) — no compressed instruction is ever generated. A6's value
  is **independence** (SimX shares authorship, hence blind spots, with the DUT), which is an
  orthogonal axis to A3's "the golden must not crash".

- **FIX APPLIED (2026-08-06) — three tiers.**
  1. **Disassembler never aborts (33 sites).** Every `default:` in `op_string()` now
     returns `UNKNOWN(<sub-field>=<value>)`. A run can no longer be voided because the
     golden could not spell an instruction. Transformed with brace-depth tracking, not
     textual matching — a sibling inner `switch` sits closer to an outer `default:` than
     its own `switch` does, so naive matching mislabels it (verified at `decode.cpp:199-203`,
     where the inner default correctly got `brArgs.offset` and the outer got `br_type`).
  2. **Semantic refusals are RECORDED, not silent (39 sites).** New `golden_halt.h` holds a
     process-wide first-refusal record. `DECODE_ABORT()` (13), `EXEC_UNSUPPORTED()` (22,
     `execute.cpp`) and `EMU_HALT()` (4, `emulator.cpp` — the CSR/console-MMIO gaps that
     historically killed riscv-dv runs) all fill it before aborting. **The abort is kept
     deliberately**: a golden model that guessed a writeback here would corrupt every later
     comparison while still reporting "pass". The DPI reads the record after its existing
     `siglongjmp` and returns **-4 GOLDEN_HALT** (refused at a named point) instead of
     **-3 CRASH** (unknown). Keeping -3 alive and distinct is what prevents an unconverted
     site from masquerading as a clean halt.
  3. **The verified prefix is no longer thrown away.** Previously one exotic instruction at
     cycle 88,000 voided all 88,000 good retirements. Now the scoreboard names the gap and
     the lockstep verdict **excludes the truncated tail** (orphans after the halt have no
     golden to compare against) while still failing on any real field mismatch *before* it.
  Sites were classified, not lumped: `execute.cpp:1415` is an **IPDOM stack overflow**
  (a model CAPACITY limit, fixable by raising `ipdom_size_`), `:448` and `:1439` are model
  **invariant** violations — none of them are missing encodings, and each now says so.
- **MEASURED RESULT — the UNVERIFIABLE bucket is EMPTY.** The plan's standing claim of
  "~10 riscv-dv programs still abort" is **STALE**. All 10 retained riscv-dv tests were
  re-run: **zero SimX aborts**, and the passes are real byte-exact DUT-vs-SimX compares,
  not liveness — `data_compared` = 15 / 436 / 490 / 880 / 1414 / 18 / 19 / 574. 8/10 pass;
  the 2 failures (`riscv_non_compressed_instr_test`, `riscv_rand_jump_test`) are **RTL
  assertion errors** on random-jump programs (the OBS-012/OBS-013 class), i.e. DUT-side and
  not golden-model aborts. Earlier SimX fixes had already retired the bucket; nobody had
  re-measured it.
- **NON-VACUITY PROVEN (a path never seen to fire is worth nothing).** Because nothing in
  the suite makes the golden refuse any more, the GOLDEN_HALT path would otherwise have
  shipped completely unexercised. `SIMX_FORCE_HALT=<n>` (env var, **default OFF**) makes the
  golden refuse at the n-th decoded instruction — same discipline as the Gate-0
  `+INJECT_FAULT` / `+DROP_STORE` guards. Armed run on `vecadd_lite`:
  `GOLDEN_HALT … 'unrecognized instruction encoding' at PC=0x80003550 instr=0x00363713
  (wid=2, decode.cpp:597)`; **273 pairs verified before the halt**, 762 tail orphans
  excluded, **UVM_ERROR 0**, classified `UNVERIFIABLE (END-STATE)` with *"The DUT is NOT
  implicated"*. Default (unset) run is byte-identical: 1035/1035.
- **REGRESSION-CLEAN:** vecadd_lite 1035/1035 · tcu_test 785/785 · fpu_test 1675/1675 ·
  sfu_masks 3178/3178 — all `data`/`LOAD` mismatch 0, `UVM_ERROR` 0; both Gate-0 negative
  guards still DETECT their injected faults.
- **A6/Spike remains unnecessary for this**, as argued above — and the measured result
  settles it: the bucket emptied without Spike ever being involved.

---

### OBS-021 (TB BUILD-INTEGRITY hazard) — `prepare.sh` silently SKIPS building the SimX DPI when `sim/simx/obj` is missing, leaving every DPI import a null pointer
- **Class:** TB/infrastructure · **Disposition:** **OPEN (low severity — fails loud, but for the wrong reason)** ·
  **Found:** 2026-08-06, after a `make clean` in `Vortex/sim/simx` during A3 work.
- **What happens:** `prepare.sh:98-100` tests for `$VORTEX_HOME/sim/simx/obj` and, if absent,
  prints `⚠ WARNING: SimX not built` and **continues** — it never builds the DPI, never sets
  `SIMX_ENABLED`, and the run proceeds. vsim then reports
  `Failed to find user specified function 'simx_init' …` for every import and dies with
  `Null foreign function pointer encountered`. The diagnostic points at `simx_pkg.sv:13`,
  which is the innocent party; nothing in the output says "your golden model was never built".
- **Why it is worth fixing:** the recovery command is already known to the script — it is the
  very `make -C sim/simx CONFIGS="$ARCH_FLAGS"` invocation ten lines below. Warning-and-
  continuing when the REFERENCE MODEL is absent is the wrong default for a verification flow:
  a run with no golden can only produce a vacuous or confusing result. It should either build
  it or hard-fail naming the command.
- **Note (ruled out during the same investigation):** the sibling worry — that a bare
  `make` in `sim/simx` (without `CONFIGS`) silently poisons `obj/` with wrong-config objects —
  is **NOT** a real hazard. `sim/simx/Makefile:101` keys a `CONFIG_FILE` stamp off the full
  `CXXFLAGS` and rewrites it whenever they change, forcing a rebuild. Verified directly.

---

### OBS-022 (VERIFICATION OBSERVABILITY LIMIT) — per-instruction lockstep compares the **writeback domain only**: branches, stores and `jalr x0` are never directly checked
- **Class:** observability limit (testbench, not RTL) · **Disposition:** **OPEN — bounded and quantified; accepted for now**
- **What we saw:** during the A6 Spike audit, the DUT/SimX retirement stream for
  `riscv_arithmetic_basic_test_0.elf` contained **11,076** records while Spike retired
  **11,487** instructions from the same entry PC. The 411-instruction difference is not a
  divergence: every missing instruction is one with **no register writeback** — `nop`
  (`0x00000013`), `beq` (`0x00628263` @ `0x80000008`), `jalr x0,s6,0` (`0x000b0067`
  @ `0x80000014`).
- **Evidence / mechanism:** this is by construction and already documented in-tree —
  `vortex_uvm_env/uvm_env/lockstep_scoreboard.svh:16` states *"DOMAIN: writeback retirements
  only (wb==1). Non-wb instructions (stores, branches…)"*, and the filter is enforced at
  `vortex_uvm_env/tb/vx_commit_probe.sv:99` (`retire_fire && commit_arb_if[i].data.wb`) and
  again on the golden side at `lockstep_scoreboard.svh:311` (`if (wb == 0) continue;`).
  Filtering Spike identically made the streams **exactly equal in length (11,076 = 11,076)**.
- **Why it matters:** a control-transfer instruction is never compared *as an instruction*.
  A branch that resolves the wrong way is caught only **indirectly**, via the PC of the next
  writeback retirement — so it is detected, but the reported first-divergence PC points at the
  *successor*, not at the faulty branch. **Stores are not covered by lockstep at all**; they
  are covered by the separate end-state memory compare. This bounds what "per-instruction
  lockstep" may be claimed to mean.
- **Not a defect:** the DUT and SimX agree with an independent model (Spike) on both the
  count and the values of every architectural writeback. Nothing here suggests an RTL bug.
- **Enhancement if closed:** extend the commit probe to capture non-wb retirements
  (`wb==0`) with their PC only, giving direct branch/store-order comparison. Cost is a wider
  probe and a larger trace; benefit is exact first-divergence attribution on control flow.

---

### OBS-023 (VERIFICATION OBSERVABILITY LIMIT) — a dropped **sub-word** store into a partially-written dword is invisible to the end-state compare

- **Class:** observability limit of the testbench (**not** an RTL defect). Found while tracing
  the B2 scoreboard refactor; the gap is **pre-existing**, not introduced by it.
- **What we saw:** the end-state DUT-vs-SimX compare has two passes, and a specific case falls
  between them:
  - The **forward** pass iterates the DUT write-set and, for each dword, zeroes the lanes the
    DUT did not write **on both sides** before comparing
    (`vortex_uvm_env/uvm_env/vortex_scoreboard.svh`, byte-valid gate in `compare_all_written`).
    So unwritten lanes inside a written dword are never compared.
  - The **reverse** (dropped-store) pass deliberately skips any dword the DUT wrote at least
    one byte of (`if (dut_write_mask.exists(waddr)) continue;` — "forward handled it").
  - Therefore: if the DUT correctly stores byte 0 of a dword but **drops** a store to byte 4 of
    that *same* dword, the forward pass masks byte 4 away and the reverse pass declines to look
    at that address at all. The lost store is silently uncompared.
- **Why the mask exists anyway (do not just delete it):** it makes the SimX-poison gate
  byte-granular. SimX fills untouched memory with `BAADF00D`; without masking first, a dword
  where the DUT wrote bytes 0..3 and SimX left poison in 4..7 is discarded **whole** as
  "SimX uninitialised", losing the four lanes that *are* valid and comparable. The mask trades
  the OBS-023 blind spot for that coverage — a deliberate trade, now written down.
- **Scope in practice:** requires a dropped store that is (a) sub-dword and (b) lands in a dword
  the DUT otherwise wrote. Full-dword drops **are** caught — proven live by
  `negative_dropped_store_test`, which still reports `DROPPED STORE addr=0x800075d8` after the
  B2 refactor. Measured `skipped_poison=0` on every 1CL run inspected, so the poison gate is
  not currently firing on these programs; the mask's protective value here is structural
  rather than presently active.
- **Disposition:** OPEN, bounded and quantified. Not fixed in B2 — closing it changes verdict
  semantics (which lanes are authoritative) and needs its own non-vacuity proof, i.e. a
  negative test that drops exactly one sub-word store into a partially-written dword.
- **Enhancement if closed:** make the poison gate byte-granular directly (test each lane's
  containing 32-bit half for `BAADF00D`) instead of using the write-mask as a proxy, then
  compare **all** lanes of a written dword. That removes the blind spot without losing the
  poison protection the mask was introduced for.

---

### OBS-024 (TB/ARCHITECTURE MISMATCH + golden-vs-DUT asymmetry) — `ebreak` is **not** Vortex's termination mechanism; the RTL decodes it and does nothing, while SimX halts on it

- **Class:** testbench design mismatch (**not** an RTL defect) + a real DUT-vs-golden behavioural
  asymmetry. Found while root-causing the `text_big` suite timeout.
- **What Vortex actually does.** A kernel ends in `_Exit`
  (`Vortex/kernel/src/vx_start.S:69-75`): store the exit code to `IO_MPM_EXITCODE`, `fence`,
  then `.insn r RISCV_CUSTOM0, 0, 0, x0, x0, x0` — i.e. **`tmc x0`**. That zeroes the thread
  mask, which clears `active_warps` (`hw/rtl/core/VX_schedule.sv:139`
  `active_warps_n[wid] = (tmc.tmask != 0)`), which deasserts `busy`
  (`VX_schedule.sv:390` `busy = (active_warps != 0 || ~no_pending_instr)`).
  **`busy` deassertion IS the architectural end-of-program signal.**
- **The RTL never executes `ebreak`.** `INST_BR_EBREAK` occurs in exactly three places in all of
  `hw/rtl/`: the decoder (`core/VX_decode.sv:119`), the package constant
  (`VX_gpu_pkg.sv:238`) and the trace printer (`VX_trace_pkg.sv:141`). There is **no
  execute-side consumer** — in hardware it is effectively a no-op.
- **SimX DOES halt on it.** `Emulator::trigger_ebreak()` (`sim/simx/emulator.cpp:682`) calls
  `active_warps_.reset()`, and `Emulator::running()` (`:242`) is `active_warps_.any()`. The
  in-tree comment is explicit that this is a testing convenience: *"For now, we need these
  instructions to trap for testing the riscv-vector isa"*. `trigger_ecall()` is identical.
- **In the Vortex runtime `ebreak` signals a FAULT, not completion** — its only occurrence is
  `_sbrk` (`kernel/src/vx_syscalls.c:38`), i.e. heap exhaustion. riscv-dv programs reach an
  `ebreak` only because `prepare.sh` rewrites `ecall`→`ebreak` for this bench.
- **Consequences for our TB.** `vortex_tb_top.sv:479` makes decoded `ebreak` the PRIMARY
  completion trigger, and comments the sustained-`busy=0` path (`:486-493`) as *"should not
  happen in a correct run"*, emitting `** Warning:`. For **every real Vortex kernel this is
  inverted**: `ebreak` never fires, and the warned-about "fallback" is the architecturally
  correct signal. This is why the busy=0 warning has always been "expected" for kernel ELFs
  (see CLAUDE.md C3 note) — the run is correct and the warning is noise.
- **Asymmetry that matters for equivalence:** on a riscv-dv program the golden STOPS at the
  `ebreak` while the DUT keeps fetching past it; only the TB probe ends the run. The two models
  therefore terminate for *different reasons* on the same program. Nothing has mis-compared
  because of this (the end-state compare runs after the TB stops the DUT), but any future
  claim of the form "both models ran the same program to the same end" must account for it.
- **Disposition:** OPEN (documented, not yet changed). Deliberately NOT fixed inside B2 —
  reordering the completion hierarchy changes when every test ends and would invalidate the
  differential baselines B2 was validated against.
- **Enhancement if closed:** make `tmc`-driven `busy` deassertion the PRIMARY completion trigger
  for kernel ELFs and demote `ebreak` to the riscv-dv/fault path, so the normal case stops
  emitting a warning and a real `_sbrk` fault stops being indistinguishable from a clean exit.

**OBS-024 UPDATE (2026-08-07) — confirmed empirically, not just by code reading.** `text_big`
run to completion at an adequate cycle budget ended with
`EXECUTION COMPLETE via sustained busy=0 fallback (100 cyc) — ebreak not decoded`
(490,468 cycles, 56,537 instructions, `data_compared=64`, 0 errors, TEST PASSED). The kernel
exits through `tmc x0` → `active_warps=0` → `busy` deassert and **never decodes an `ebreak`**,
exactly as `vx_start.S:69-75` and `VX_schedule.sv:139/390` predict. The `** Warning:` on the
architecturally-correct path is therefore emitted on a fully passing run — which is the concrete
cost of the inverted hierarchy described above.

---

### OBS-025 (RESET-DOMAIN hazard, multi-cluster/multi-socket only) — the DCR broadcast tree stacks **three** unreset elements in exactly the window where a core self-starts

- **Class:** reset-domain / X-propagation hazard. Benign in practice today, but it compounds
  INV-2 and is present **only** at `NUM_CLUSTERS > 1` or `NUM_SOCKETS > 1`. Found while scoping
  the B1 DCR RAL. **OPEN.**
- **What we saw — three unreset elements in series:**
  1. **The DCR pipe register is doubly unreset.** `BUFFER_DCR_BUS_IF`
     (`Vortex/hw/rtl/VX_define.vh:373-388`) instantiates `VX_pipe_register` with
     `.reset (1'b0)` hardwired (`:381`) **and** without passing `RESETW`, which defaults to `0`
     (`Vortex/hw/rtl/libs/VX_pipe_register.sv:19`). So the stage has no reset by two independent
     mechanisms, and `dst.write_valid` is **X out of reset** until the first write propagates.
  2. **The DCR storage has no reset.** `VX_dcr_data.sv:27` `UNUSED_VAR (reset)`; `dcrs` holds X
     until written (this is the INV-2 root cause).
  3. **Cores self-start from reset.** `VX_schedule.sv:230` — a core begins fetching without
     waiting for any DCR handshake.
- **Why it is benign *today*:** the X only reaches `if (dcr_bus_if.write_valid)`
  (`VX_dcr_data.sv:32`), and an X condition takes the false branch in simulation, so no bogus
  write is latched. That is a *simulation semantics* rescue, not an architectural guarantee —
  it would not survive X-pessimism analysis, gate-level simulation, or synthesis inference.
- **Why it matters and why it is config-specific:** the pipe stages exist only at
  `NUM_CLUSTERS > 1` (`Vortex.sv:138`) and `NUM_SOCKETS > 1` (`VX_cluster.sv:129`), each
  `DEPTH=1`. At ≥2 clusters/sockets a DCR write therefore reaches a deep core **later** than
  core 0, widening the INV-2 race window (core already running before its `STARTUP_ADDR`
  arrives) for precisely the cores that are hardest to observe. At 1CL/1C the tree is degenerate
  and none of this is reachable — which is why it has never been seen.
- **Direct consequence for the B1 RAL (recorded so it is not rediscovered):** a per-core DCR
  mirror check must **NOT** be armed off the global TB `dcr_bootstrap_done` handshake. That
  signal says the TB finished driving, not that the write traversed up to two pipeline stages
  to a deep core; arming on it would sample a deep core's `dcrs` too early and report a **false
  mismatch that is pure tree latency**. The check must be **event-driven per probe instance** —
  each bound probe compares only after it observes its own `write_valid` retire into `dcrs`.
  That derives no latency constant and stays correct if the tree ever gets deeper.
- **Disposition:** OPEN. Not a defect we can demonstrate failing today; it is a latent
  X/reset-domain hazard plus a real widening of the INV-2 window at scale.
- **Enhancement if closed:** give `BUFFER_DCR_BUS_IF` a real reset (pass `reset` and a
  `RESETW`/`INIT_VALUE` that clears `write_valid`), and/or reset `dcrs` in `VX_dcr_data`. Either
  removes an unreset element from the startup path; doing both plus the INV-2 reset-hold makes
  DCR bootstrap deterministic at any topology.

---

### OBS-026 (BARRIER SCOPE — expected behaviour; the DEFECT IS IN OUR TEST, not the DUT) — `barrier_test` is not multi-core safe, and its 2CL "failure" is a data race plus a transient visibility difference

**What we saw.** `barrier_sync_test` (program `barrier_test`) failed at 2CL/2C with **exactly 2**
`MEM MISMATCH`es out of 32 words compared, after the DUT `+TIMEOUT` was raised from 150,000 to a
measured 164,602 cycles (the old budget was 10% short and had been *masking* this).

| addr | symbol | DUT | SimX |
|---|---|---|---|
| `0x8000778c` | `bar2_stall` | `0x300` (768) | `0x600` (1536 = nominal) |
| `0x80010000` | `RESULT_ADDR` | `0x900DCAFE` (= errors==0) | `0x1` (= 1 error) |

**Root cause — the DUT is right, and the test is racy by construction.**
1. `bar2_stall` is a **shared `volatile int` incremented NON-ATOMICALLY** by every warp:
   `for (int i = 0; i < wid*256; i++) bar2_stall++;` (`barrier_test.cpp`, `bar2_kernel`). It is a
   pure busy-wait delay — **nothing ever reads it for correctness**. At 2CL/2C, 4 cores x 4 warps
   perform unsynchronised read-modify-write on one location, so it has **no architecturally
   -defined value**. DUT=3 and SimX=6 are BOTH legitimate outcomes of the same racy program.
2. The DUT's own sentinel says the DUT PASSED: the kernel is self-checking and writes
   `0x900DCAFE` only when `errors == 0`. **Every CHECKED array matches** between DUT and SimX —
   `bar1_pre`, `bar1_post`, `bar2_data`, `bar3_contrib`, `bar3_confirm`, `bar4_*`. The only two
   differing words are the race variable and the sentinel it fed.
3. ~~SimX's single error came from a **transient** cross-warp visibility difference.~~
   **CORRECTED 2026-08-13 — that was a hypothesis, and the console output disproves it.** The
   error is concrete, cross-CORE, and fully explained. `run_183422` console (prefixes are gtid =
   `core_id<<4` at 4W/4T, so `#0/#16/#32/#48` are the four cores):
   ```
   #0:   FAIL accumulator=2 expected 10
   #16:  FAIL accumulator=2 expected 10
   #48:  PASS (accumulator=10, 4 warps confirmed)
   #32:  PASS (accumulator=10, 4 warps confirmed)
   ```
   `bar3_contrib[]` should hold `[1,2,3,4]` (sum 10). **A sum of 2 means only slot 1 survived and
   slots 0/2/3 read as 0** — i.e. they were zeroed AFTER being written. The culprit is
   `test_accumulator_barrier()`'s own init loop `for (w) bar3_contrib[w] = 0;`, which runs on
   **every core's main thread**: a later core wipes the array while an earlier core's warps have
   already written it, so that core's warp-0 reduction sums a partially-zeroed array.
   **The barrier cannot prevent this**, and that is the real lesson of OBS-026:
   `vx_barrier(BAR_ID, nw)` is PER-CORE (`GBAR_ENABLE` undefined ⇒ `VX_wctl_unit.sv:138` ties
   `is_global` to `1'b0`), so it orders only the 4 warps of ONE core. **The test's synchronisation
   scope is a core; the data it protects is GPU-wide.** Every symptom follows from that one
   mismatch: the `bar3` race (errors==1 on cores 0,1), the `RESULT_ADDR` divergence (4 cores write
   DIFFERENT values — `0x900DCAFE` from the passing cores, `1` from the failing ones — so
   last-writer-wins decides, and DUT and SimX order it differently), the `bar2_stall` mismatch, and
   the console-interleave mismatch.
   ⚠ Point 2 above ("every CHECKED array matches") is still true **of the final image only** —
   the arrays are eventually rewritten by all cores. The failing read happened mid-race.
   ⚠ Note `bar2_stall`'s values: SimX `0x600` = 1536 = `0+256+512+768`, the exact serial total for
   ONE core, i.e. SimX lost NO updates; DUT `0x300` = half. Confirmed symbol
   (`nm barrier_test.elf`): `8000778c B bar2_stall`.

**✅ FIXED 2026-08-13 (commit `47d6e7a`) — MEASURED.** `barrier_test.cpp` now (a) core-gates
`main()` on `vx_core_id() != 0` and (b) gives `bar2_stall` per-warp slots so its finals are
deterministic (`w*256`) instead of a raced scalar. Acceptance at 2CL/2C/4W/4T
(`results/20260813/run_195900`): **`MEM MISMATCH` 2 → 0, `CONSOLE FAIL` 1 → 0**, the kernel prints
`ALL PASSED` from **core 0 only** (was `#0`/`#16`/`#32`/`#48`), 0 UVM_ERROR, 164,394 cycles,
`data_compared` 32 → 36. `per_cluster_busy=01` for the whole run confirms the gate in the DUT.
Config-generic on all four axes — see the commit message. Gating costs no coverage *because*
barriers are per-core; genuinely multi-core barrier stimulus would need per-core data regions and
is only worth building if `GBAR_ENABLE` is turned on.

**The race is LATENT at 1CL, not absent — measured:**

| run | clusters | words compared | mismatches |
|---|---|---|---|
| `run_235024_barrier_sync_test` | **1** | 32 | **0** |
| `run_183422_barrier_sync_test` | **2** | 32 | **2** |

At 1CL, DUT and SimX agree on `bar2_stall` exactly: within ONE core both resolve warp
interleaving the same way, so the same sequence of lost updates happens on both sides. Add cores
and that stops holding — SimX interleaves CORES at a coarser granularity than the timing-accurate
RTL (same mechanism as `docs/investigations/SimX_2CL_no_fence_divergence.md`, where SimX's
cluster-0 cores tracked the DUT exactly while cluster-1 diverged). **A latent race that only
surfaces at higher core counts is exactly what a config sweep should expose — it simply surfaced
in our test rather than in the DUT.**

⚠ **CORRECTED 2026-08-13 — the earlier "3 and 6 / three orders of magnitude below nominal" reading
was a HEX MISPARSE of the 64-bit dump and its conclusion was wrong.** `DUT=0x0000030000000004`
splits into the word at `0x8000778c` (= `bar2_stall`, per `nm`) = **`0x300` = 768** and the word at
`0x80007788` = 4; SimX's is **`0x600` = 1536**. Nominal is `(0+1+2+3)*256 = 1536` per core.
So the true signature is **SimX = EXACTLY nominal (zero lost updates) and DUT = EXACTLY half** — a
clean 2:1, not a three-orders-of-magnitude collapse. That is a sharper and different result: the
functional model serialises the RMW perfectly, while the timing-accurate RTL loses precisely every
other update, which is what genuine concurrent read-modify-write on one line looks like. The
concurrency layers named below are still the right mechanism; only the magnitude claim was wrong.

**Why this is expected, from the RTL AND the publication (they agree):**
- `VX_wctl_unit.sv:136` `assign barrier.is_global = rs1_data[31];` — barrier scope is selected by
  the **MSB of the barrier ID**. The MICRO'21 paper states the same: *"a similar table is also
  used for global barriers in multi-core configurations where the MSB of the barrier ID indicates
  global scope"*, and describes barriers as synchronising *"between software warps"* (wavefront
  scope), citing Mellor-Crummey & Scott.
- **`GBAR_ENABLE` is NOT defined in this build**, so `VX_wctl_unit.sv:138` hardwires
  `barrier.is_global = 1'b0` — **all barriers are per-core**. `VX_schedule.sv:168` implements the
  local release from per-core `barrier_ctrs`; the global path (`:252-268`) is `ifdef`-ed out.
- `barrier_test` calls `vx_barrier(BAR_ID, nw)` with a small `BAR_ID`, i.e. **MSB=0 ⇒ local scope
  by design**, even if `GBAR_ENABLE` were turned on.
- The paper is explicit that cross-core *memory* synchronisation uses the RISC-V **`fence`**
  instruction. `bar2_stall++` uses none. This is the OBS-009 weak-coherency class again.
⇒ At 2CL/2C four cores each execute `main()` concurrently against the SAME global arrays, with a
per-core barrier and no fence. The test was written for one core's warps.

**Disposition: NOT A DUT BUG — TEST DEFECT, OPEN.** Do **not** "fix" the barrier RTL for this.
*Fix options, in preference order:*
1. **Core-scope the kernel** — have every core except core 0 exit immediately (`vx_core_id() != 0`
   ⇒ `vx_tmc(0)`). Preserves the test's actual intent (barrier between WARPS) and stays valid at
   any NCL/NC. Cheapest and most honest.
2. Make it genuinely multi-core: global barrier (needs `GBAR_ENABLE` + MSB set in the barrier id)
   plus `fence` around the shared arrays. Bigger change; also then tests a different feature.
3. Exclude `barrier_test` from the 2CL suite and say so explicitly.
Whatever is chosen, `bar2_stall` should stop being a shared non-atomic counter — a per-warp local
delay loop achieves the same staggering with no race.

**Wider lesson (same as OBS-024 and the B1 DCR bugs): a firing checker is not evidence of a DUT
defect.** Here the raised timeout did not "fix" the test — it *revealed* a race the timeout had
been hiding, and the mismatching value turned out to be the one variable in the program with no
defined value.

---

### OBS-027 (MULTI-CORE STORE ORDERING — expected; the DEFECT IS THE METHODOLOGY, not the DUT) — riscv-dv programs are SINGLE-HART and Vortex runs them on EVERY core, so the shared `.data` section is resolved in a different order by the DUT than by SimX

**What we saw.** `riscv_rand_instr_test` at 2CL/2C: 6 `MEM MISMATCH`es out of 780 words compared,
one value propagated — DUT `0xfff8` (x5) / `0xfff4` (x1) vs SimX `0x1a33` / `0x1af4`. Passed at 1CL.

**It is DETERMINISTIC, which kills the obvious explanation.** The run was repeated and produced a
**byte-identical** mismatch set (same 6 addresses, same values). Memory-ordering *races* do not
reproduce byte-for-byte, so this is NOT the chaotic-race class and must not be filed as one.

**Lockstep located it at instruction granularity** (`+LOCKSTEP`, trace via `LOCKSTEP_TRACE`):

| seq | PC | addr | DUT | SimX | flag |
|---|---|---|---|---|---|
| 1319 | `800016d0` | `800130fa` | `fffffff8` | `1a33` | L |
| 1329 | `80001704` | `80012ae2` | `fffffff8` | `fffffff4` | L |
| 1330 | `80001708` | `80012ae2` | `fffffff8` | `33` | L |
| 6851 | `80009af0` | `80012513` | `ffffffff` | `1a` | L |

All are **LOAD-DATA** mismatches: `dut_pc == simx_pc` and `dut_rd == simx_rd` on every record —
control flow and register allocation agree exactly, **only the loaded DATA differs**.

**NOT misalignment.** `VX_lsu_slice.sv:186-192` asserts *"memory misalignment not supported!"*, but
it checks alignment **to the ACCESS SIZE**: `0x…fa`/`0x…e2` are even (legal `lh`) and `0x…13` is odd
but legal `lb`. The assertion correctly did NOT fire (0 occurrences). Do not chase this as a
misaligned-access bug.

**The proof that memory is concurrently modified:** seq 1329 and 1330 are ADJACENT retirements
(PCs 4 bytes apart, no store between them in this warp) reading the **same address** `0x80012ae2`,
yet SimX returns `fffffff4` then `33`. Something outside this warp wrote that location between two
consecutive instructions.

**The proof it is not a race:** the trace contains the same divergence for `cid=0` AND `cid=1` at
the same seq with identical values (`key=0` and `key=10000` rows). **Each model is internally
self-consistent across cores; the two models simply disagree with each other.**

**ROOT CAUSE.** riscv-dv emits a **single-hart** program. Its hart dispatch is a structural no-op —
`csrr x5,0xf14; li x6,0; beq x5,x6,0f` where the branch target falls through to the same
`h0_start`, so **every core runs the identical stream regardless of `mhartid`**. Vortex cores all
self-start from reset (`VX_schedule.sv:230`), so at 2CL/2C **four cores concurrently execute the
same single-hart program against the same `.data` addresses**, with no fences (`fence` is what the
MICRO'21 paper specifies for cross-core memory ordering) and no core gating. The surviving value at
each address is therefore decided by store ORDER. Both simulators are deterministic, so each
produces a repeatable order — but the timing-accurate RTL and the functional SimX produce
DIFFERENT orders. Hence: deterministic, self-consistent per model, divergent between models, and
absent at 1CL where only one core stores.

**Why lockstep reports a LOAD as the first divergence:** stores are outside the lockstep writeback
domain (OBS-022), so the actual originating event — a store landing in a different order — is
structurally invisible. The load is the first *observable* symptom, not the cause. This is a
concrete instance of the OBS-022 limitation, and worth remembering before reading any lockstep
"first divergence" as the true first divergence.

**Disposition: NOT A DUT BUG — METHODOLOGY. ✅ FIXED 2026-08-13 (option 1, MEASURED).**
`prepare.sh:460-500` now injects a real core gate (`csrr x5,0xCC2; beqz x5,_vortex_core0;
vx_tmc 0`) into every riscv-dv program after the sed stage, with a hard `exit 1` if the `^_start:`
anchor is ever absent — a silent miss would restore undefined multi-core results.
**Acceptance (2CL/2C/4W/4T, `riscv_rand_instr_test`, `results/20260813/run_194404`):
`MEM MISMATCH` 6 → 0, with `data_compared=780` UNCHANGED** — the divergence disappeared without
the comparison shrinking, so the fix is not vacuous. 0 UVM_ERROR, 0 RTL errors, 18,080 instructions.
**Live DUT proof of the gate:** the probe trace reads `per_cluster_busy=01` for the whole run —
cluster 1's cores retired at `_start` and never executed the body.
**Side effect worth carrying:** the run now takes **194,966** cycles vs the **205,982** measured
pre-fix, because gated cores no longer contend for memory. Any riscv-dv cycle budget measured
BEFORE this fix is stale.
Historical context follows. Same family as OBS-009 /
`docs/investigations/SimX_2CL_no_fence_divergence.md`, but this is the first time the class has
been pinned down with instruction-level evidence and a determinism control rather than inferred.
*Options:*
1. **Core-gate riscv-dv programs** — patch `prepare.sh`'s post-processing so all cores except core 0
   exit immediately (read `VX_CSR_MHARTID`/gtid, `vx_tmc(0)` if non-zero). Makes every riscv-dv
   result meaningful at ANY config and preserves the existing programs. Preferred.
2. Accept riscv-dv as a 1CL-only signal and exclude it from multi-core banks — honest, but throws
   away the random stimulus exactly where concurrency bugs live.
3. Give each core a private `.data` region (needs generator/linker work).
⚠ Until one is chosen, **every riscv-dv result at ≥2 cores is architecturally undefined** and must
not be quoted as a pass OR a failure of the DUT.

**MACHINE-CODE CONFIRMATION (2026-08-13).** The dead hart gate was confirmed in the linked binary,
not merely in the source. Assembling the post-sed program shows:
`80000014: 00628263  beq t0,t1,80000018` — **the branch target IS the next instruction.** Both arms
fall through. Verified present, and identically dead, in **all 10** cached riscv-dv profiles
(`_start:` ×1 and `csrr x5,0xf14` ×1 in each). Note our own sed (`prepare.sh:454`) rewrites that
`csrr` to `nop`, so by the time the DUT sees it even the vestigial hart read is gone.

**⚠ USE `VX_CSR_CORE_ID` (`0xCC2`), NOT `VX_CSR_MHARTID` (`0xF14`), FOR THE FIX.** Three reasons:
1. **`0xF14` is stripped by our own sed** (`prepare.sh:454` matches `csrr …, 0xf14`), so a gate
   written with it depends on injection order relative to that sed. `0xCC2` is outside both the
   `0x300–0x3FF` and `0xf14` patterns and cannot be eaten.
2. **`0xCC2` needs no config arithmetic.** `VX_CSR_MHARTID` returns
   `gtid = (CORE_ID<<(NW_BITS+NT_BITS)) + (wid<<NT_BITS) + tid` (`VX_csr_unit.sv:125,132`), so a
   `!=0` test on it is only valid because reset leaves warp0/thread0 alone
   (`VX_schedule.sv:230-233`). `VX_CSR_CORE_ID` (`VX_csr_data.sv:179`) returns `CORE_ID` directly —
   no dependence on the reset mask at all.
3. **Both models agree on it by construction.** RTL composes
   `CLUSTER_ID*NUM_SOCKETS + socket_id` (`VX_cluster.sv:132`) → `SOCKET_ID*SOCKET_SIZE + core_id`
   (`VX_socket.sv:227`); SimX composes it identically (`processor.cpp:37` → `cluster.cpp:39` →
   `socket.cpp:100`) and returns `core_->id()` for `VX_CSR_CORE_ID` (`emulator.cpp:501`). Globally
   unique and equal on both sides at any NCL/NC/NW/NT.
**Retire semantics match too:** `vx_tmc 0` (`.insn r 0x0B,0,0,x0,x0,x0`, encodes `0000000b`) gives an
empty tmask, and SimX then executes `active_warps_.reset(wid)` (`execute.cpp:1638-1640`) — the same
deactivation the RTL performs. `ebreak` would NOT work here (OBS-024: no execute-side consumer).

---

### OBS-028 (CONFIG FIDELITY — TESTBENCH/KERNEL DEFECT, not RTL) — kernels compute their grid from `VX_config.h` macros that are FROZEN at 1/1/4/4, so "multi-core aware" kernels silently run on ONE core

**What we saw.** At 2CL/2C/4W/4T, `wide_stress` reported `per_cluster_busy=01` for its entire
~2.4M-cycle run — cluster 1 never executed a single instruction. The same held for `cache_stress`,
`fpu_mt`, `tcu_mt`, `text_big` and others. The 2CL bank shows `cluster0_core0` missing **0**
`instr_probe` bins while the other three cores are each missing **28**.

**Root cause.** `Vortex/hw/VX_config.h:99-111` hardcodes the DEFAULTS
`NUM_CLUSTERS 1 · NUM_CORES 1 · NUM_WARPS 4 · NUM_THREADS 4`.
Kernel Makefiles pass **no** config defines and `prepare.sh` **never rebuilds kernels per config**
(it rebuilds only the RTL and the SimX objects). So every kernel macro is pinned to the default
regardless of `CLUSTERS=n CORES=n WARPS=n THREADS=n` on the command line.

**The kernels are not naive — they are misinformed.** `wide_stress:18` is commented
*"Multi-core aware: TOTAL threads, each owns a strided disjoint set of lines"* and computes
```c
#define TOTAL (NUM_CLUSTERS * NUM_CORES * NUM_WARPS * NUM_THREADS)   // = 1*1*4*4 = 16
```
The scaling arithmetic is CORRECT; its INPUTS are frozen. The kernel asks for one core's worth of
work, and `vx_spawn_threads` then does exactly the right thing with it:
```c
needed_cores = ceil(num_tasks / threads_per_core);      // 16/16 = 1
active_cores = MIN(needed_cores, num_cores);            // 1
if (core_id >= active_cores) return 0;                  // vx_spawn.c:274-279
```
⇒ **the parallelism was never broken; we were launching a 1-core problem on an N-core machine.**

**13 kernels use the frozen macros** — `wide_stress`, `cache_tier`, `div_edge`, `vote_shfl`,
`toggle_stress` (all four of `NUM_CLUSTERS/NUM_CORES/NUM_WARPS/NUM_THREADS`), plus `tcu_mt`,
`tcu_test`, `diverge_deep/peel/uni3`, `compute_flat`, `barrier_lite`, `spawn_tmc_sweep`.
⚠ Several also SIZE STATIC ARRAYS from them (`g_out[TOTAL]`, `out_buf[NUM_WARPS*TM*TN]`), so a
compile-time fix that raised the macros without raising the bounds would **overflow** them.

**Fix: query the DEVICE at RUNTIME, not the build.**
`vx_num_cores()/vx_num_warps()/vx_num_threads()` read the real CSRs
(`VX_CSR_NUM_CORES` etc.), so ONE ELF is correct at every config and cannot drift from the
elaborated hardware. Compile-time defines are the wrong instrument twice over: kernels are not
rebuilt per config today, and even if they were, a build-time constant can disagree with the RTL —
exactly the drift class `I2`/OBS-019 exists to prevent. The only thing that must stay compile-time
is the STATIC ARRAY BOUND, which should be a documented worst case, not a silent default.

**Applied so far:** `cache_stress` (`81ffa24`) and `fpu_mt` (`49b19ba`) — both measured
`per_cluster_busy` `01 → 11` at 2CL, byte-exact vs SimX, 0 mismatches.
⚠ Scaling the grid ALSO ARMS a latent race: `main()` runs on every core, so a whole-array init or
self-check that was harmless while one core did all the work becomes destructive once every core
has work (a late core wipes an earlier core's results — the OBS-026 failure mode). Both fixes drop
the redundant `.bss` zeroing and scope any self-check to the core's own slice, which is safe
because `vx_spawn` distributes tasks CONTIGUOUSLY (`all_tasks_offset = core_id * tasks_per_core`,
`vx_spawn.c:299`) — no global barrier needed, and Vortex has none with `GBAR_ENABLE` off.

**Disposition: OPEN — TB defect, no DUT implication.** It does not invalidate any PASS/FAIL result
(every kernel ran a correct, defined program); it means multi-core STIMULUS was far weaker than the
kernel comments claim, and the per-core coverage deficit at 2CL is ours, not the design's.

---

### OBS-029 (METHODOLOGY LIMIT — READ BEFORE WRITING ANY "VERIFIED BY GOLDEN-MODEL EQUIVALENCE" CLAIM) — differential testing is STRUCTURALLY BLIND to a fault in the stimulus itself

**The claim this bounds.** Our central evidence is *"the DUT's end state is byte-exact against
SimX."* That is strong evidence about the DUT's **response** to a stimulus. It says **nothing**
about whether the stimulus was the one we intended.

**Concrete instance (found 2026-08-15 while auditing the execution units).**
`tcu_mt`/`tcu_test` build their tensor-core operation from a C++ template whose argument is the
COMPILE-TIME warp width:
```cpp
using ctx = vt::wmma_context<NUM_THREADS, vt::bf16, vt::fp32>;   // tileM/tileN are part of the TYPE
```
`NUM_THREADS` comes from `VX_config.h`, which is frozen at 4 (OBS-028), and kernels are never
rebuilt per config. Run the suite at `THREADS=2` or `THREADS=8` and the kernel issues a **4-lane**
WMMA against different-width hardware.

**Why no checker in the environment can catch it.** The DUT and the golden model execute the
**same binary**. A mis-compiled kernel is therefore mis-executed *identically* by both:
- the end-state scoreboard compares DUT memory to SimX memory — **both wrong, both equal ⇒ PASS**;
- per-instruction lockstep compares DUT retirements to SimX retirements — **same, ⇒ PASS**;
- the coverage model samples what executed, not what SHOULD have executed ⇒ bins fill, happily.
⇒ **A green run with 0 mismatches is fully compatible with the kernel having verified nothing.**
This is not a hole in the scoreboard; it is a property of differential testing. Both sides share
the stimulus, so a fault in the stimulus is **common-mode** and cancels exactly.

**The general rule.** Equivalence checking can only validate what DIFFERS between the two models.
Anything SHARED — the program binary, the memory image, the launch geometry, the DCR
configuration — is outside the comparison by construction, and needs an INDEPENDENT assertion.

**What closes it: assert on the STIMULUS, not the response.** Both TCU kernels now check the
elaborated geometry at runtime and refuse to run on a mismatch (`9674de0`):
```c
if ((int)vx_num_threads() != NUM_THREADS || (int)vx_num_warps() != NUM_WARPS)
  return 1;    // compiled for a different machine
```
Same principle as the `I2` elaboration asserts (UVM params vs DUT params) and the `C1` width
assert, applied one level up — to the PROGRAM rather than the testbench. Proven non-vacuous:
`tcu_test` still passes at the compiled geometry (`data_compared=244`).

**Other members of this class already in-tree** (all shared inputs, all outside the compare):
| shared input | what protects it | status |
|---|---|---|
| launch geometry (warps/threads) | the TCU runtime guard above | ✅ `9674de0` |
| UVM params vs RTL params | `I2` elaboration asserts | ✅ |
| `VX_MEM_TAG_WIDTH` | `C1` elaboration assert | ✅ |
| SimX build config vs RTL config | `simx_config.stamp` | ✅ (I3) |
| **kernel build config vs RTL config** | **nothing** | ⚠ **OPEN — OBS-028** |
| the program image itself | nothing (a wrong ELF is run faithfully by both) | ⚠ OPEN |

**⇒ CLAIM DISCIPLINE.** Defensible: *"for the stimulus we ran, the DUT's end state and its
per-instruction retirements match an independent-ish golden model byte-exactly, with
proven-non-vacuous checkers."* **NOT defensible:** *"equivalence against the golden model proves
the DUT executed the intended program."* Nothing in an equivalence-based environment can prove
that; only an assertion on the stimulus can, and we now have one for exactly one shared input.
**Disposition: OPEN (methodology).** Every remaining row of the table above is a place where a
green run could still mean nothing. Add to the FW list and to the paper's limitations section.

---

## OBS-030 — the AXI route waivers are keyed to a field layout that only exists at ONE requester; three of four fire on real traffic at 2CL

**What we saw.** In the 2026-08-15 post-scaling banks, `axi_transaction_cg.cp_id_route` reports its
`ignore_bins` as **Occurred**, i.e. the "structurally unreachable" values are being produced by the
DUT and then discarded by the waiver:

| ignore_bin | stated premise | 1CL hits | **2CL hits** |
|---|---|---|---|
| `route_msb_unreachable = {[32:63]}` | "bit5 never set @1 requester" | 0 | **4,488** |
| `route_emergent_read = {4,6,8,10,12,14}` | suite "NEVER emitted" these | **3** | **10,605** |
| `route_high_write_tag = {23,27,31}` | write ids, "non-targetable" | 0 | **88** |
| `route_even_ge16 = {16,18,…,30}` | "reads<=15, writes odd" | 0 | 0 |

Evidence: `cov/bank_{1CL_1C_4W_4T,2CL_2C_4W_4T}/merged.ucdb`, `vcover report -cvg -details`.

**Root cause (RTL, not stimulus).** `Vortex/hw/rtl/libs/VX_axi_adapter.sv:282`:
```systemverilog
assign xbar_tag_r_out = READ_FULL_TAG_WIDTH'({xbar_tag_out, req_xbar_sel_out[i]});
```
For **reads**, `arid` = `{tbuf_waddr, req_xbar_sel}` — the requester-port select occupies the
**LOW** `NUM_PORTS_IN_BITS` bits (`:104-109`), so the MSHR slot index is **shifted up** by that
many bits as soon as there is more than one input port. For **writes** (`:261`) `awid` is
`mem_req_tag` with no port select appended, so reads and writes do not even share a layout.

Consequences, measured:
* `AXI_TID_W` 50 → **51** and `ROUTE_W = AXI_ID_W - UUID_W` 6 → **7** between 1CL and 2CL.
* At 1CL a read route *is* `tbuf_waddr` (0..15). At 2CL it is `{tbuf_waddr, port}` (0..31), so the
  old parity argument ("reads ≤15, writes odd") describes a field that no longer exists.
* Every waiver is a **numeric literal set**, so at 2CL each one lands on a different physical
  meaning than the one its evidence was gathered for.
* At 128 values the coverpoint also exceeds Questa's default `auto_bin_max` (64), so 2CL is
  measured in **range bins** (`auto[0:1]`, …) while 1CL is measured in **singletons** — the two
  configs are not measuring the same thing.

**This was predicted in-tree and never discharged.** `vortex_coverage_collector.svh:299-305` carries
the trip-wire verbatim: *"validated for ROUTE_W==6 (1CL/1C/4W/4T). A wider config grows
VX_MEM_TAG_WIDTH and the slot space -> re-derive before trusting these"* and *"at multi-core the AXI
ID's requester-port bits make these routes reachable, so these ignores must be re-derived per config
— DEFERRED to the Cores>1 phase."* The `SINGLE_CORE` localparam (`:213`) was declared for exactly
this gate and **is never used by `cp_id_route`** (`:306-311`) — the ignores apply unconditionally.

**Bug vs expected:** **TB / methodology defect.** The RTL is correct and is behaving as designed;
the coverage model's reachability claims are wrong for any config with >1 requester.

**Why it matters beyond a percentage.** An `ignore_bins` is an assertion that hardware *cannot*
produce a value. Three of these are now demonstrably false, so the banked 2CL number rests in part
on claims the same UCDB disproves. It does not inflate the hit-rate arithmetically (an ignored bin
leaves both numerator and denominator), but it *discards real coverage* and, if repeated in the
paper, would be an unsupportable structural-unreachability claim (rule 1 / the FW claim-discipline
list). The genuine gap it hides is also real: `auto[64:127]` — the entire upper half of the 2CL
route field — has **zero** hits, 32 bins.

**Disposition: ✅ FIXED 2026-08-15.** The flat `cp_id_route`/`cross_type_route` and all four
literal `ignore_bins` are withdrawn, replaced by a layout-derived decode in
`vortex_coverage_collector.svh`: `cp_route_port` (requester port, reads), `cp_route_slot` (MSHR
slot, reads), `cp_write_tag` (writes — coarse buckets, since the write tag genuinely IS a
non-architectural counter id), and `cross_port_slot`. Every bound comes from
`VX_gpu_pkg::VX_MEM_PORTS` and the adapter's `TAG_BUFFER_SIZE`, so no per-config maintenance
exists to go stale. The prose trip-wire is now a `uvm_fatal` on
`ROUTE_W < PORT_SEL_W + SLOT_W` plus a UVM_INFO banner printing the decode.

**Verified config-generic by compiling the SAME source at both configs** — the derived layout
tracks the hardware exactly:

| | 1CL/1C | 2CL/2C |
|---|---|---|
| `AXI_ID_W` / `ROUTE_W` | 50 / **6** | 51 / **7** |
| `MEM_PORTS` / `PORT_SEL_W` | 1 / **0** | 2 / **1** |

`ROUTE_W` grows by exactly `PORT_SEL_W`, which confirms `VX_axi_adapter.sv:282` numerically rather
than by argument. First 2CL run (`vecadd_lite`): `cp_route_port` **100%** (both requester ports
reach AXI — previously invisible), `cp_route_slot` **25%** (slots 0-3 only), `cp_write_tag` 2/8.
That 25% is the honest signal the waivers were destroying: the design has 16 MSHR entries and this
stimulus reaches 4. Both Gate-0 guards re-proven RED at `0x800075d8` after the change.

**FOLLOW-UP (same session) — the first replacement was itself config-blind, and the DUT said so.**
`cp_route_slot` was written as "which tag-buffer slot", but the tag buffer is **not always
elaborated**. Verified from the UCDB hierarchy (`vcover report -recursive`), not by inference:

| config | `g_tag_buf` instance | read `id` actually carries |
|---|---|---|
| 1CL/1C | **absent** | raw `mem_req_tag` (`VX_axi_adapter.sv:170`, `g_none`) |
| 2CL/2C | **present**, one per port, each with its own `allocator/free_slots_sel` | `{tbuf_waddr, req_xbar_sel}` (`:282`) |

The RTL gate is `NEEDED_TAG_WIDTH > TAG_WIDTH_OUT` (`:149`), i.e.
`MAX(SUB_LDATAW,0) + NUM_PORTS_IN_BITS > 0`; with `SUB_LDATAW <= 0` for this AXI configuration it
reduces to `MEM_PORTS > 1`.

**How the mistake surfaced — the measurement contradicted the model.** The allocator is strictly
lowest-free (`VX_allocator.sv:49`, a `VX_priority_encoder` over `free_slots_n`), so slot 15 can only
be issued when slots 0..14 are ALL occupied. The 1CL run reported `{0,2,3,7,11,15}` covered with
1,4,5,6 at **zero** — impossible for a genuine slot index, and therefore proof the field was being
mis-decoded rather than under-stimulated. `cp_route_slot`/`cross_port_slot` are now gated on
`TAG_BUF_PRESENT`, and the build logs which branch it took.

**MEASURED ANSWER (2026-08-15, `mshr_flood` at 2CL) — the slot decode is CORRECT and the depth is
REAL.** With the tag buffer present, the covered slots are **{0,1,2} — perfectly CONTIGUOUS** — and
3..15 are zero:

| config | covered slots | verdict |
|---|---|---|
| 1CL (no tag buffer) | {0,2,3,7,11,15} — non-contiguous | decode was meaningless (raw tag) |
| 2CL (tag buffer present) | **{0,1,2} contiguous** | decode correct; max 3 concurrent reads/port |

Contiguity is the self-check: a strictly lowest-free allocator can only ever produce a contiguous
prefix, so a contiguous result means the field is being read correctly, and a gappy one means it is
not. That single property distinguishes "under-stimulated" from "mis-decoded" without any extra
instrumentation, and it is worth reusing on any allocator-indexed coverpoint.

**⇒ The 13 unhit slots share OBS-031's root cause: the requester side is narrower than the
resource.** `LSUQ_OUT_SIZE` is 4 at `NUM_THREADS=4`, and the measured per-port concurrency is 3.
`mshr_flood` is the strongest outstanding-read stimulus in the suite (67k dcache misses at 1CL,
33,060 words compared at 2CL) and it reaches 3 of 16.

**Disposition: LEFT HONESTLY UNCOVERED — deliberately NOT waived.** A waiver asserts hardware
*cannot* produce the value, and while the mechanism is clear, the exact concurrency bound has not
been derived from the RTL parameters (measured 3 < the naive `LSUQ_OUT_SIZE * cores_per_port` = 8,
so the naive formula would be wrong). Waiving on an unproven bound is precisely the OBS-030 mistake.
These bins therefore stay in the denominator and lower the reported number — which is the correct
outcome until someone derives the bound properly. Same for `cross_port_slot` (2 ports x 16 slots):
it is kept even though ~26 of its 32 bins are unreachable in practice, because deleting a coverpoint
because it reads low is tuning the metric, not verifying the design.

**Lesson, third instance of the same class in one session:** a coverage bin is a CLAIM about what a
signal means. Here the claim was true at 2CL and false at 1CL — the same trap as the original
waivers, committed while fixing them. When bins appear in a pattern the hardware could not
produce, suspect the decode before suspecting the stimulus.

⚠ **The banked 2026-08-15 AXI numbers are not comparable across this change** (the denominator and
the questions both changed). The banks are preserved; re-measure before quoting the AXI block.

---

## OBS-031 — `cp_mshr_stall.stall` is STRUCTURALLY UNREACHABLE at ≤8 threads: the LSU can never present MSHR_SIZE concurrent misses

**Status of the old claim.** Every prior doc called this bin "a genuine stimulus gap, left honestly
uncovered" and the 2026-08-15 resume block predicted four contending cores might move it. **That
was wrong, and it was wrong for a checkable reason.** It is not a stimulus gap; the bin cannot be
hit at this cache/LSU configuration no matter what a program does.

**What we did.** Built `tests/kernel/mshr_flood`, a kernel designed specifically for this bin:
stride 1024 B (= 16 x 64 B, so every access lands in the SAME bank for any `DCACHE_NUM_BANKS` 1..16),
thread-INTERLEAVED slots (`slot(t,c) = c*TOTAL + t`) so each thread's lines share address bits
[11:10] and collapse onto ONE set, piling ~64 lines onto a single 4-way set (16x oversubscribed).

**It worked as stimulus and still did not hit the bin:**

| measure | result |
|---|---|
| dcache `cp_hit` | **774 hits vs 67,207 misses** — the thrash is real |
| `cp_mshr_stall.stall` | **0** (both icache and dcache) |
| `cp_route_slot` (AXI tag buffer, 16 slots) | **6/16** — independent confirmation |

Two independent coverpoints agreeing on "~6 outstanding" is what turned this from "try harder" into
"find the cap".

**Root cause — the request path is narrower than the MSHR, by construction:**
```
SIMD_WIDTH     = NUM_THREADS                       (VX_config.vh:349)
NUM_LSU_LANES  = SIMD_WIDTH                        (:388)
LSUQ_IN_SIZE   = 2 * (SIMD_WIDTH / NUM_LSU_LANES)  (:426)  == 2 for EVERY config
LSU_LINE_SIZE  = MIN(NUM_LSU_LANES * XLEN/8, 64)   (:421)
LSUQ_OUT_SIZE  = MAX(LSUQ_IN_SIZE, LSU_LINE_SIZE / (XLEN/8))   (:431)
DCACHE_MREQ_SIZE = 4  (:633)   DCACHE_MSHR_SIZE = 16  (:628)
```
`VX_cache_bank.sv:231-234` accepts a new core request only when **both** queues have room:
```systemverilog
assign core_req_ready = creq_grant
                     && ~mreq_queue_alm_full   // needed for fill requests
                     && ~mshr_alm_full         // needed for mshr allocation
                     && ~pipe_stall;
```
⚠ **CORRECTION (same session).** An earlier draft of this entry argued that the FILL queue is the
binding throttle, asserting almost-full at `MREQ_SIZE - PIPELINE_STAGES` = 4 - 2 = 2 entries. **That
is wrong for the configuration we actually build:** `scripts/compile.sh:70-73` overrides the cache
queue depths on every compile —
`+define+ICACHE_MREQ_SIZE=16 +define+DCACHE_MREQ_SIZE=16` (and the MSHR sizes to 16) — so
`MREQ_SIZE` is **16, not the RTL default 4**, and its almost-full threshold is 14. The fill queue
is therefore NOT the throttle here. See OBS-032 for the override itself.

The argument that survives, and the one the measurements support, is the REQUESTER width:
`LSUQ_OUT_SIZE` caps what the LSU can have in flight at all, and it is not overridden anywhere:

| NUM_THREADS | LSU_LINE_SIZE | **LSUQ_OUT_SIZE** | vs MSHR_SIZE=16 |
|---|---|---|---|
| 4 (primary) | 16 | **4** | 4 << 16 → unreachable |
| 8 | 32 | **8** | 8 < 16 → unreachable |
| 16 | 64 | **16** | reachable in principle |

Even summing over a shared socket dcache (`SOCKET_SIZE` cores), 2 x 4 = 8 at 2CL — still below 16.
The icache side is bounded the same way by outstanding fetches (one per warp): 4, or 8 at 2CL.
This bound is independent of the compile.sh queue-depth override, which is why the conclusion is
unchanged by the correction above — but the *reason* had to be narrowed to the one that is true.

**⇒ The bin is unreachable for the same reason `cp_ipc_bucket.high_ipc` was: a structural width,
not a missing test.** It becomes reachable only at `NUM_THREADS>=16` (or with `LSUQ_*`/`MSHR_SIZE`
overridden), which is exactly the shape of a CONFIG-AWARE waiver this project already uses.

**Bug vs expected:** **expected behaviour / coverage-model over-specification.** The RTL is
consistent — a 16-entry MSHR simply is not the binding constraint in this configuration.

**Disposition: waive CONFIG-AWARELY (not unconditionally).** Waiving it unconditionally would
repeat the OBS-030 mistake of baking a one-config claim into a literal. The waiver must be keyed on
the derived bound so it auto-REACTIVATES when a wider config could reach it.

**Lesson (third time this class has appeared):** the previous two were OBS-030 (route waivers keyed
to a single-requester layout) and the `high_ipc` bucket. In all three, a bin was called a stimulus
gap when the real answer was a structural width — and in all three the honest resolution came from
reading the RTL parameter chain rather than writing a better test. Check the width before writing
the kernel.


---

## OBS-032 — the testbench silently overrides the cache queue depths, so the banked coverage is NOT the RTL's default cache configuration

**What we saw.** Every compile passes, unconditionally and with no comment
(`vortex_uvm_env/scripts/compile.sh:70-73`):
```
+define+ICACHE_MSHR_SIZE=16  +define+DCACHE_MSHR_SIZE=16
+define+ICACHE_MREQ_SIZE=16  +define+DCACHE_MREQ_SIZE=16
```
Against the RTL defaults (`Vortex/hw/rtl/VX_config.vh`):

| define | RTL default | **what we build** |
|---|---|---|
| `ICACHE_MSHR_SIZE` / `DCACHE_MSHR_SIZE` | 16 (`:567`, `:628`) | 16 — no change |
| `ICACHE_MREQ_SIZE` / `DCACHE_MREQ_SIZE` | **4** (`:633`) | **16 — 4x deeper** |

Found while root-causing OBS-031: the compile transcript disagreed with the header file, and the
header is what the analysis had been based on.

**Why it matters.**
1. **It changes cache behaviour.** `MREQ_SIZE` sets the fill-request queue depth and its almost-full
   threshold is `MREQ_SIZE - PIPELINE_STAGES` (`VX_cache_bank.sv:659`): 2 at the default, **14** as
   we build it. That gate is one of the two terms in `core_req_ready` (`:232`), i.e. it directly
   controls when a bank stops accepting misses. A back-pressure path that engages at 2 outstanding
   fills is a materially different design from one that engages at 14 — and back-pressure is
   precisely what several of our coverage bins are trying to observe.
2. **Coverage claims inherit it.** Every banked number describes a machine with 4x-deeper cache
   fill queues than a default Vortex build. Nothing in the plan, the paper, or the bank metadata
   says so.
3. **It nearly produced a false structural waiver.** OBS-031 was one edit away from justifying an
   `ignore_bins` with "the fill queue throttles at 2 entries" — true of the RTL default, false of
   the binary we run. Reading the compile transcript rather than the header is what caught it.
4. **No provenance.** `git log -S` traces it to the initial `Add files via upload` commit, with no
   message, comment, or doc explaining the intent. It may well be deliberate (a deeper queue hides a
   performance cliff and speeds simulation), but nothing records that.

**Bug vs expected:** **TB configuration defect (undocumented divergence from the DUT defaults).**
Not an RTL bug — the RTL honours the override exactly as designed.

**✅ RESOLVED 2026-08-16 (LATE) — THE HYPOTHESIS BELOW IS MEASURED AND FALSIFIED. READ THIS FIRST.**
`compile.sh` is now terminal-controlled (`CACHE_MREQ_SIZE` / `CACHE_MSHR_SIZE`, default unchanged at
16 so every bank stays reproducible), and the experiment was run: `mshr_flood` @1CL, rebuilt at
`CACHE_MREQ_SIZE=4` (the RTL default), TEST PASSED, compared against the same kernel's run in the
50-run 1CL bank.

| mshr_flood @1CL | MREQ=16 (banked) | MREQ=4 (RTL default) |
|---|---|---|
| Branches | 12565 / 18913 | **12565 / 18913 — identical** |
| Conditions | 524 / 1707 | **524 / 1707 — identical** |
| Statements | 20428 / 23461 | **20428 / 23461 — identical** |
| Toggles | 379395 | 378859 (**fewer**: 32 fewer bins exist in a shallower FIFO) |
| Total | 56.22% | 56.21% |

**`cp_mshr_stall.stall` did NOT fire at either depth** (`no_stall` is the only bin with hits in both).

**⚠ WHY THE HYPOTHESIS WAS WRONG — a mechanism error worth not repeating.** It conflated two
different structures. `cp_mshr_stall` samples `perf_mshr_stall = mshr_alm_full`
(`VX_cache_bank.sv:684`), and that signal is wired to the **MSHR's `.full` port**
(`VX_cache_bank.sv:494`) — sized by `MSHR_SIZE`. `MSHR_SIZE` is **16, which IS the RTL default**, so
that coverpoint was never affected by the override at all. `MREQ_SIZE` sizes a *different* queue (the
fill-request FIFO, `:658`). Note also that despite its name, `mshr_alm_full` is driven by `.full`,
not an almost-full threshold — the bin needs the MSHR **completely** full, which is harder still.
⇒ **`cp_mshr_stall.stall` is a genuine stimulus gap exactly as originally documented.** The claim
that "part of it is a configuration gap" is withdrawn.

**Scope of the result, stated honestly:** one kernel, one config. But it is the kernel purpose-built
to flood the MSHR (67,207 dcache misses) — the single most likely place for the override to show —
and it moved *nothing* in branches, conditions or statements. That is strong, cheap evidence.

**Disposition: RESOLVED as option (b).** Keep the depth at 16, now terminal-controlled and
documented; **state it in the paper's configuration table**. A full re-bank at the RTL default is
NOT justified — it would cost ~17h of simulation and invalidate comparison with every bank on disk,
to chase an effect measured at ~0.01% on the most sensitive kernel available.

**The original hypothesis is preserved below for the record.**

**UPDATE 2026-08-16 — the override is actively SUPPRESSING the coverage we spent a session chasing.**
The maximisation push (`unit_storm`, `storm_big`) targeted condition terms that only evaluate when two
requests are live at one port in the same cycle. The almost-full gate this override moves from **2 to
14** (`VX_cache_bank.sv:659`) is one of the two terms in `core_req_ready` (`:232`) — i.e. the exact
back-pressure signal those bins observe. We built a machine 4x less likely to back-pressure and then
wrote kernels to force it to back-pressure. That also reframes `cp_mshr_stall.stall`, which has **0
hits against 5,131,366 `no_stall`** across every bank: it has been reported as a stimulus gap, but
part of it is a *configuration* gap. ⚠ This is a HYPOTHESIS with a mechanism, not a measurement — the
experiment (drop to the RTL default 4, re-run, diff) has NOT been run. Do not quote it as a result.

**Disposition: OPEN.** Options, in preference order: (a) delete the override and re-measure, so we
verify the default configuration; (b) keep it, but make it terminal-controlled like `L2`/`L3` and
state it in the bank metadata and the paper's configuration table. What must NOT continue is an
unexplained silent override that analysis keeps tripping over. Until resolved, any statement of the
form "Vortex's L1 does X under back-pressure" must be qualified with the queue depths we built.

---

## OBS-033 — 26% of the entire toggle gap is ONE read-only cache: the icache's write-data path is elaborated but structurally undrivable

**Status of the old claim.** Since session 10 (2026-07-10) every doc has explained the toggle
ceiling as *"`DCACHE_WRITEBACK=0` (write-through) => 512-bit full-line write-data fields never
driven, plus constant PC high bits"*. That explanation named the **dcache**. Measured on the clean
1CL bank of 2026-08-15, **it points at the wrong cache**:

| subtree | toggle bins | missing | coverage |
|---|---|---|---|
| `socket/icache` | 51,340 | **22,730** | **55.7%** |
| `socket/dcache` | 86,604 | 9,524 | 89.0% |

The icache is **half the size and carries 2.4x the misses**. It is **22,730 of the design's 85,957
missing toggle bins = 26.4% of the entire toggle gap, from one subtree.**

**Root cause — `VX_socket.sv:106` instantiates the icache with `.WRITE_ENABLE (0)`.** The cache
generic is fully parameterised, so the write-data payload, its byte-enables and every buffer stage
that carries them are still *elaborated*; they are simply never driven. Zero-toggle nodes inside
the icache, by signal:

```
   3232  req_data.data          <- 512-bit write payload, replicated per interface hop
   1241  data_out               \
    732  data_in                 |  the elastic buffers / stream arbiters that
    697  req_data_in[0]          |  carry that same payload through the hierarchy
    697  req_data_out[0]         |
    620  mem_req_pdata[0]        |
    620  per_bank_mem_req_pdata[0]
    512  per_bank_mem_req_data[0]/
    404  req_data.byteen        <- byte-enables for a write that cannot happen
```
Counter-check that this is the write path and not "the icache is under-stimulated": on the same
interface, `rsp_data.data` (the fill payload) toggles **45-46 times per bit across all 512 bits**.
The read path is fully exercised; only the write direction is dead.

**This is the SAME citation we already accepted for functional coverage and never applied to code
coverage.** Commit `5c4b70f` waived the icache `cp_rw.wr` covergroup bin as structural on exactly
`VX_socket.sv:106`. The toggle bins produced by that same tie-off were left in the denominator, so
the bank has been reporting a structural impossibility as an uncovered feature for every bank we
have ever taken.

**Amplified by the metric's own shape: Questa toggle coverage is BY INSTANCE.** `VX_mem_bus_if`
merged by design unit is **2,456 bins at 96.49%**; counted by instance it is **98,160 bins with
15,951 missing**. The identical dead field is re-counted at every hop it passes through
(`arb_core_bus_if` -> `mem_bus_tmp_if` -> `mem_bus_cache_if` -> `cache_mem_bus_if` -> per-bank), and
eight distinct parameterisations of that interface sit at *exactly* 46.96% each. One tie-off in the
RTL therefore costs the metric roughly an order of magnitude more than it costs the design.

**Disposition: OPEN — a config-aware structural exclusion is justified and is NOT gaming.** The
waiver must be keyed off the instantiation parameter (`WRITE_ENABLE == 0`), exactly like the
existing `vx_cache_probe` bind, so that it evaporates automatically if a future config enables
icache writes. Waiving by hardcoded instance path would be wrong for the same reason OBS-030 was
wrong. **Do NOT waive the dcache write-data path on this observation** — it is a different
mechanism (write-through, OBS pending) and its numbers do not support a blanket waiver.

---

## OBS-034 — the design carries a 44-bit UUID counter that NO simulation can ever toggle, and the verification infrastructure itself depends on it

**What we saw.** `uuid` fields are the second-largest toggle hole after the icache: **9,300 uuid
toggle nodes design-wide, 5,103 of them dead (54.9%)**. Measured per bit on
`socket/icache/cache_mem_bus_if[0]/req_data.tag.uuid`:

```
bit :  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 | 18..31 | 32 33 | 34..43
tog : 46 46 46 46 46 46 46 46 46 45 33 27 19 17  7  7  2  1 |   all 0 | 37  1 |  all 0
```

This is the unmistakable signature of a **binary counter**, not a stimulus gap. Each successive bit
toggles at half the rate of its predecessor (46, 46, ..., 33, 27, 19, 17, 7, 7, 2, 1, 0), and the
break at bit 32 (37 toggles) is a packed sub-field boundary, not a counter bit.

**Root cause — `VX_gpu_pkg.sv:66`:**
```systemverilog
`ifndef NDEBUG
    localparam UUID_WIDTH = 44;      // <- our build lands here
`else
`ifdef SCOPE
    localparam UUID_WIDTH = 44;
`else
    localparam UUID_WIDTH = 1;
`endif
`endif
```
**Toggling bit 18 requires 2^18 = 262,144 requests on that path; bit 43 requires 2^43 ~ 8.8e12.**
No simulation reaches that, at any stimulus quality, ever. **4,542 of the 5,103 dead uuid nodes are
bit index >= 18** — i.e. ~89% of the uuid gap is arithmetically unreachable rather than
under-stimulated. This is a strictly stronger claim than "hard to hit": it is provable from the
counter width and the run length, with no appeal to stimulus.

**The obvious fix is CLOSED to us, and that is the point of this entry.** Building with `NDEBUG`
sets `UUID_WIDTH = 1` and deletes these bins outright. **We cannot do that:** `uuid` is the
correlation key our own verification stack is built on — `lockstep_scoreboard.svh`,
`vx_commit_probe.sv`, `vx_lsu_probe.sv`, `rvvi_txn.svh`, `lockstep_pkg.sv`, `simx_pkg.sv` and
`simx_dpi.cpp` all consume it. Narrowing it to 1 bit would silently destroy per-instruction
lockstep, which is the strongest checker in the project.

⚠ **Therefore the toggle metric is permanently penalised by the very instrumentation that makes the
functional claims defensible.** That trade is worth making, but it must be *stated* rather than
absorbed into a headline percentage — a reader comparing our 79.79% toggle against a published
figure has no way to know that a debug counter no run can exercise sits in the denominator.

**Related, same class, smaller:** `PC[0]` and `PC[1]` are dead on 64 nodes each — instructions are
4-byte aligned, so the low two PC bits are constant 0 by ISA construction (RVC is excluded upstream,
`prepare.sh:321 --target=rv32im`). PC high bits are constant because the programs are small; that
part IS realism-limited rather than structural and must NOT be waived.

**Disposition: OPEN.** Recommended: exclude uuid bits at or above the run-length bound with the
bound *derived* (from retired-instruction count), never hardcoded, and state the residual in the
paper. Do NOT set `NDEBUG`.

**RESOLUTION of the OBS-033 open item — the `mem_req_buf` / `mem_rsp_queue` "100% dead" buffers
(2026-08-16). They are NOT a coverage hole, and they are NOT waivable. Both halves matter.**

*Why they are not a hole.* `VX_elastic_buffer.sv:34-41` — when `SIZE == 0` the module degenerates to
```systemverilog
assign valid_out = valid_in;
assign data_out  = data_in;
assign ready_in  = ready_out;
```
The icache takes that branch because `MEM_REQ_BUF_ENABLE = (NUM_BANKS != 1)` (`VX_cache.sv:105`) and
`VX_socket.sv:96` hardcodes `.NUM_BANKS(1)`. The ports are therefore electrically identical to their
source. **Measured proof that the activity IS counted, just under a different name:** on the same
instance, `mem_req_addr`/`mem_req_addr_w` have **12 of 26 bits live** and `mem_req_tag`/`mem_req_tag_w`
have **22 of 48 live**, while the 654-bit `data_in`/`data_out` — which are precisely the
concatenation of those nets plus the (structurally dead, OBS-033) write payload — report zero.
Even more directly: `assign valid_out = valid_in` *guarantees* identical toggling, and Questa reports
**valid_in = 0, valid_out = 47**. That asymmetry is impossible physically and is the tool's alias
attribution.

*Scale.* Design-wide at 1CL there are **116 `SIZE == 0` elastic-buffer instances carrying 4,667 dead
port nodes = 9,334 toggle bins = 12.7% of the entire remaining toggle gap.**

*Why we still do NOT waive it.* **97 nodes on those same ports ARE live** — Questa's attribution is
inconsistent, landing on the port in some instances and on the source net in others. So:
* a UNIFORM rule ("all `SIZE==0` buffer ports") removes 97 covered nodes and trips the
  hits-invariant gate in `merge_coverage.sh`;
* an OUTCOME-based rule ("the dead ones") is exclusion-by-result — precisely the dishonest pattern
  this project forbids, and the thing that made OBS-030 wrong.
Bit-range exclusions derived from the `DATAW` concatenation would be exact but hardcode offsets into
a packing that can change — the OBS-030 failure mode again.

**⇒ Left in the denominator, deliberately, and STATED instead.** The correct reading of our toggle
number is: *~12.7% of the reported toggle gap is the by-instance metric counting the same physical
activity twice.* That belongs in the paper as a caveat on the metric, not as a waiver on the design.
This is also the cleanest available measurement of how much Questa's by-instance toggle model
inflates a design that passes wide payloads through many zero-size buffers.

---

## OBS-035 — the icache FLUSH FSM is elaborated but can never be entered, at any config

**What we saw.** `VX_cache_init.sv` and `VX_cache_flush.sv` account for 16 statement and 16 branch
misses plus 7 condition terms in the 1CL bank — and every one of them is in the **icache**.

**Proof chain, all three links read in the RTL:**
1. `VX_cache_init.sv:91` — a flush can only start via
   `core_bus_in_if[i].req_data.flags[MEM_REQ_FLAG_FLUSH]`.
2. `VX_lsu_slice.sv:73` — that flag has **exactly one producer in the entire design**,
   `req_is_fence`, and it sits on the LSU (dcache) path.
3. `VX_fetch.sv` contains the string `flush` **zero times** — the icache's only requester has no
   flush logic to drive it with.

**Positive control — this is what makes it a proof rather than an excuse.** The *identical source*
is **fully covered on the dcache in the same run**: `VX_cache_init` 25/25, `VX_cache_flush` 16/17;
and dead on the icache: 14/25, 12/17. Same RTL, same suite, same stimulus — the only variable is
which cache instantiates it.

**Disposition: WAIVED, config-aware** (`gen_coverage_exclude.sh` §4d), emitted per socket over the
real topology. **Only the state BODIES are waived, not the `if` lines** (`VX_cache_init.sv:133`,
`VX_cache_flush.sv:60`) — those conditions are evaluated every cycle and their false arm is
legitimately covered; excluding them was measured to drop 3 real hits.

**Two Questa traps found here, both silent — record them, they will recur:**
* `coverage exclude -scope … -recursive -srcfile …` **does nothing and reports no error.** The scope
  must name the FSM instance directly.
* Excluding a whole `-linerange` across an FSM drops covered bins, because reachable and unreachable
  lines interleave. Nothing in the tool warns you.
⇒ this is why `merge_coverage.sh` now has a **blocking hits-invariant gate**: a structural waiver may
shrink the denominator only, never the covered count.

---

## OBS-036 — SimX does not model the machine-identification CSRs, so four RTL lines are unreachable *under our methodology* rather than merely untested

**What we saw.** Four `VX_csr_data.sv` read arms stay uncovered even with a directed CSR kernel:
`MVENDORID`, `MARCHID`, `MIMPID` (`:189,190,…`) and `MISA` (`:181`).

**Root cause — the two models return different values, by construction:**
| CSR | RTL | SimX |
|---|---|---|
| `MISA` | `{2'(CLOG2(XLEN/16)), 30'(MISA_STD)}` (`VX_csr_data.sv:182`) | **0** (`emulator.cpp:484`) |
| `MVENDORID`/`MARCHID`/`MIMPID` | `VENDOR_ID`/`ARCHITECTURE_ID`/`IMPLEMENTATION_ID` | **0** — no case at all; the default silently returns 0 for the whole `0xF00-0xFFF` hw-id range (`emulator.cpp:518-522`) |

⇒ any instruction that reads them writes back a value the golden model provably cannot reproduce.
Under end-state compare that only matters if the value is stored; **under `LOCKSTEP=1` it is a
guaranteed per-instruction mismatch**. So covering these lines requires shipping a kernel that
cannot run under the strongest checker in the project.

**This is a distinct and important class.** They are not structurally dead — the hardware genuinely
executes them — so waiving them would be dishonest. They are not a stimulus gap either — we know
exactly how to hit them. They are **unreachable while end-state/lockstep equivalence is the
verification contract.** That distinction belongs in the paper: it is a property of the METHOD, not
of the DUT or of our effort. `tests/kernel/isa_probe` therefore deliberately does not read them.

**⚠ ASYMMETRY WITH A BITE — `csrw misa` (0x301):** SimX *ignores* the write (`emulator.cpp:638`)
but the RTL does **not** list MISA among its accepted write addresses, so it falls through to
`VX_csr_data.sv:149 ASSERT(0, "invalid CSR write address")` and kills the run. This is exactly the
`csrw 0x301` that `prepare.sh` sed-strips from every riscv-dv program — the same defect rediscovered
from the RTL side, and confirmation that the strip is load-bearing rather than cosmetic.
**Disposition: OPEN** (golden-model fidelity gap; harmless today because we route around it).

---

## OBS-037 — `VX_gpu_pkg` ships functions with no reachable caller

While chasing the last `VX_gpu_pkg.sv` statement misses:
* `inst_fpu_is_class` (`:367`) and `inst_fpu_is_mvxw` (`:371`) — the **only** callers are
  `VX_fpu_dsp.sv:339,340,343`. The build selects **`FPU_FPNEW`** (cvfpu), so `VX_fpu_dsp` is never
  elaborated and these bodies can never execute. **Structurally dead, keyed to the FPU choice.**
* `inst_alu_is_czero` (`:223`) and `inst_sfu_is_wctl` (`:392`) — **no caller anywhere in the RTL.**
  Verified by grepping every `.sv`/`.vh`; the only occurrence is the definition itself.

Not a functional bug — dead code in a package costs nothing at synthesis. Worth recording because
(a) it explains statement misses that look like a stimulus gap and would otherwise soak up effort,
and (b) `inst_alu_is_czero` existing-but-unused is mildly suspicious given Zicond IS implemented and
decoded (`VX_decode.sv:186-190`) — someone may have intended a Zicond fast-path that never landed.
**Disposition: OPEN (informational).** Not waived yet: 8 statement items, and a waiver keyed to
"nothing calls it" is one refactor away from being wrong.

---

## OBS-038 — `assert_r_valid_stable` / `assert_r_data_stable` survive the strongest stimulus we can build; left uncovered, NOT waived

**What we saw.** These two AXI read-channel stability assertions (`vortex_axi_if.sv:383,386`) have
never passed in any bank. Session 10 attributed it to the DUT read buffer being deep enough that
`+AXI_FLOOD` alone never forces `rready` low, and left them "honestly uncovered".

**2026-08-16: retried with a strictly stronger stimulus and they still do not arm.**
`unit_storm` under `+AXI_FLOOD` at 2CL — i.e. the slave streaming read responses back-to-back
*while* the core's response path is genuinely congested (that kernel is the first one that provably
back-pressures the internal buffers, +81 condition terms at 2CL). Measured on that run:
`assert_r_valid_stable` **pass=0**, `assert_r_data_stable` **pass=0**. Test PASSED, 0 errors.

**Why this is not yet a waiver.** `m_axi_rready[i] = rsp_xbar_ready_in[i]`
(`libs/VX_axi_adapter.sv:332`) — unlike `m_axi_bready`, which is hardwired to 1 (`:313`, already
waived on that basis), `rready` is a real net that CAN drop. To waive these honestly we would have
to prove the read-response buffer depth is >= the maximum number of concurrent outstanding reads,
making the drop structurally impossible. That is the same shape of argument as OBS-031 (requester
width < MSHR depth) and is plausible — `cp_route_slot` measures only 3 concurrent reads per port —
but it has NOT been derived from RTL parameters, and waiving on an unproven bound is exactly the
mistake OBS-030 records.

**Disposition: OPEN, left uncovered.** Worth 2 assertion bins (~0.11 Total each at 1CL, where there
are only 127 assertion bins — the highest per-bin value in the whole metric). Next step if pursued:
derive the read-response buffer depth and the true outstanding-read bound, then either waive
config-awarely or build a stimulus that exceeds the depth. **Do not waive on "we could not hit it".**

---

## OBS-039 — the suite's "N staged" is a RUN count, not a distinct-program count, and 4 runs merge under one test-record name

**What we saw.** Every merge emits 5 suppressible errors:
```
** Error (suppressible): (vcover-6854) Multiple test data records with the same name
Test data records named 'regression_test_kernel'        are from different simulations.   (x3)
Test data records named 'kernel_launch_test_vecadd_lite' are from different simulations.
Test data records named 'kernel_launch_test_mem_stress'  are from different simulations.
```
Measured on the 2CL bank of 2026-08-16 (`results/run_suite_logs_2CL_storm_20260816/merge.log`).

**Cause — three distinct mechanisms, all in `scripts/run_suite.sh`:**
1. `runr` (`:81`) runs `regression_test` **four times** with four different `PROGRAM_KIND`s, but the
   UCDB test record is keyed on `PROGRAM_NAME`, which is left at its default `kernel` for all four
   ⇒ 4 runs → 1 name → 3 collisions.
2. `runthr vecadd_lite` (`:62`) re-runs a program `runk` already ran, under `+AXI_THROTTLE`.
3. `runflood mem_stress` (`:65`) does the same under `+AXI_FLOOD`.
   In (2) and (3) the *program* is identical and only the TB mode differs, so the name collides.

**Does it corrupt the bank? No — and this was checked, not assumed.** `vcover merge` unions the
coverage regardless; the warning is about **test-record identity**, not coverage data. The staged
files themselves are uniquely named (`<date>_run_<hhmmss>_<test>.ucdb`, 50 files for 50 runs) and
all 50 are consumed. Every banked number stands.

**What it DOES cost — per-test attribution.** `-testextract` / per-test hit data cannot separate the
throttled `vecadd_lite` from the plain one, the flooded `mem_stress` from the plain one, or the four
`regression_test` kinds from each other. Anything of the form *"which test covered this bin"* is
ambiguous for those 6 runs.

**⚠ CONSEQUENCE FOR THE PAPER — do not write "50 programs".** The suite's `SUITE VERDICT: 50 staged`
counts **runs**. Of those, 2 are re-runs of an existing program under a different TB mode and 4 are
one test entry under 4 program kinds. State it as *"50 simulation runs"* and count distinct programs
separately — the same class of error as FW-1b, where `riscv_pmp_test` and
`riscv_non_compressed_instr_test` were counted as 2 results for 1 byte-identical program.

**Bug vs expected:** **TB bookkeeping defect (cosmetic for coverage, material for claims).**

**Disposition: OPEN.** Cheap fix: pass a distinguishing `-testname` suffix for the throttle/flood
variants and the `PROGRAM_KIND` for regression runs. Until then, the errors are expected output and
their ABSENCE would be the surprising result. Do not "fix" by suppressing the message — it is the
only signal that the run count and the program count differ.

---

## OBS-040 — THE DUT RTL IS LOCALLY MODIFIED IN 18 FILES, INCLUDING X-MASKING INITIALIZERS AND TWO WEAKENED ASSERTIONS

**Class:** VERIFICATION-INTEGRITY (DUT modified by us) · **Disposition: OPEN — must be
disclosed in any paper or report** · **Found:** 2026-08-17, cross-checking the bring-up issue
report against this register.

**What we saw.** `Vortex/hw/rtl/libs/VX_pending_size.sv` differs from upstream. The change was
made in **`ee11d66`** ("Add GLIBCXX fix documentation and enhance memory model integration") —
i.e. it rode in on an unrelated bring-up commit and was never logged here. Two edits:

```
-        reg empty_r, alm_empty_r;            -- no initializer (X until reset)
+        reg empty_r     = 1'b1;              -- declaration initializer
+        reg alm_empty_r = 1'b1;
+        logic [SIZEW-1:0] size_r = '0;

-  `ASSERT((DELTAW'(incr) <= DELTAW'(decr)) || (size_n >= size_r), ("counter overflow"));
+  `ASSERT((!$isunknown(incr) && !$isunknown(decr)) ? (...) : 1, ("counter overflow"));
```
(The original lines are retained in-file as a commented "REVERT lines 85-86 back to:" block.)

**Why it matters — three separate problems.**
1. **The assertions are WEAKENED, not fixed.** They now evaluate to `1` (pass) whenever `incr`
   or `decr` is unknown. The reset window where they were firing is exactly the window where
   the inputs are X, so the checks are disabled precisely where they used to fire. A real
   overflow occurring while any input is X is now invisible.
2. **The declaration initializers MASK X-STATE.** Initializing state at declaration is a
   simulation-only convenience with no synthesis meaning; it hides uninitialized-state
   behaviour. This is the same class of bug that X-propagation analysis exists to find, and
   we have already recorded X-prop as ABSENT from this campaign — so this is worse than a
   gap, it is an active suppression in the DUT.
3. **It contradicts the stated provenance.** Every document, including the papers, describes
   the design under verification as "RTL pin `7a52ee5`". The RTL we simulate is that pin
   **plus an undisclosed local patch to a checker**. A verification result must state what
   was verified; "upstream Vortex" is currently not an accurate description of the DUT.

**The correct fix** (the bring-up report's own recommendation, ISSUE 3) is to gate the
assertion on reset — `&& !reset` — which suppresses the spurious reset-window firing WITHOUT
disabling the check under X during normal operation, and without touching register
initialization at all. That is a strictly narrower change than the one in the tree.

**⚠ WIDENED 2026-08-17 — IT IS NOT ONE FILE, IT IS EIGHTEEN.** A full read-only diff of the local
tree against upstream `7a52ee5` (clone in scratch, nothing modified) shows **18 modified RTL files**,
introduced by `e840370` "RTL modifications for DPI issue with questa21" and `9662521` "Converted
Vortex to local folder". Classified by real code lines vs commented-out dead blocks:

| file | code | note |
|---|---|---|
| `tcu/VX_tcu_fedp_bhf.sv` | 193 | substantial, unreviewed in this register |
| `tcu/VX_tcu_fedp_dpi.sv` | 111 | substantial |
| `tcu/VX_tcu_fedp_dsp.sv` | 32 | |
| `libs/VX_pending_size.sv` | 17 | **the assertion weakening, below** |
| `tcu/VX_tcu_fp.sv` | 16 | |
| `tcu/VX_tcu_pkg.sv` | 11 | |
| `VX_gpu_pkg.sv` | 9 | |
| `VX_config.vh` | 7 | **`STALL_TIMEOUT` fix + `SIMD_WIDTH` change** |
| `libs/VX_mem_scheduler.sv` | 6 | |
| `cache/VX_cache_bypass.sv` | 6 | |
| `tcu/VX_tcu_top.sv`, `tcu/VX_tcu_uops.sv`, `fpu/VX_fpu_pkg.sv`, `core/VX_operands.sv` | 1–2 each | |
| `fpu/VX_fpu_{sqrt,fma,div}.sv`, `fpu/VX_fpu_define.vh` | **0** | ~300 lines of COMMENTED-OUT dead code only |

**Two further undisclosed changes found by the same diff:**
* **`SIMD_WIDTH` was changed** from `` `MIN(`NUM_THREADS, 16) `` to `` `NUM_THREADS ``
  (`VX_config.vh`). This alters a structural datapath parameter. No entry exists for it anywhere;
  it is recorded here for the first time.
* **OBS-011 IS ALREADY FIXED IN-TREE and its own disposition is STALE.** `VX_config.vh` now defines
  `STALL_TIMEOUT_SCALE (4 ** (L2_ENABLED + L3_ENABLED))`, with a comment citing OBS-011 — yet
  OBS-011 still reads *"open — needs-RTL-fix … left as an upstream-reportable RTL observation"*.
  **Upstream fixed the same bug independently** (`VX_gpu_pkg.sv:224` at HEAD:
  `100000 * (1 << (L2+L3))` — a shift rather than our `4 **`), which is external corroboration that
  the finding was real. OBS-011's disposition line is left untouched pending a decision; do not
  quote it as open.

**PRECISE STATEMENT OF WHY THE `VX_pending_size` CHANGE IS WEAKER** (upstream text verified at both
`7a52ee5` and HEAD — they are identical there, so this divergence is entirely ours):
1. **The X-guard disables the check where it matters most.** BOTH versions already sit in the
   `else` branch of `if (reset)`, so the reset window is *already* excluded upstream. The actual
   ISSUE-3 trigger is that `reset` itself is X at time 0: `if (X)` takes the ELSE path, the assert
   evaluates with X operands, and X is not true, so it fires. Our guard suppresses that — but it
   also means `incr`/`decr` going X **during normal operation** (undriven control, disconnected
   port, mis-parameterised instance — i.e. a REAL defect) now evaluates to literal `1` and PASSES.
   Upstream would have caught it. The narrower correct fix is to gate on reset/X-on-reset, not on
   the data inputs.
2. **The declaration initializers hide reset failures and diverge sim from silicon.** Upstream
   leaves `empty_r`/`full_r`/`size_r` X until reset assigns them, so a broken or absent reset shows
   as X propagating out — visible. Ours forces `empty=1, full=0, size=0` at time 0: a plausible,
   healthy-looking idle state. A module never reached by reset would look CORRECT in our simulation
   and wrong in upstream's. Declaration initializers are also a simulation construct — ASIC flops
   power up unknown regardless — so the bench is blind to a class of bug that is real in hardware.
   This matters more than usual because X-propagation analysis is already ABSENT from this campaign.

Neither change is unreasonable as bring-up engineering. What is wrong is that they were undisclosed,
and that they weaken checkers in a project whose central claim is that its checkers can fail.

**✅ MEASURED 2026-08-18 — THE UPSTREAM ORIGINAL WAS TRIED AND IT FAILS. OUR VERSION IS KEPT.**
The upstream HEAD file (`d76b7f24e`; byte-identical to the pin in this module — upstream has NOT
changed it) was swapped in, rebuilt at 1CL, and run on `vecadd_lite`:

| result | value |
|---|---|
| UVM verdict | `*** TEST PASSED ***`, `UVM_ERROR: 0` |
| RTL assertions | **12 firings** |
| Harness verdict | **`TEST FAILED — 12 RTL assertion error(s)`, exit code 2** |

**All 12 fire at 5 ns, 15 ns and 25 ns**, on `icache…bank.mshr_pending_size.g_size_gt1.g_wide_step`
and the dcache equivalent, lines 85/86. That is the ISSUE-3 signature EXACTLY as reported during
bring-up, unchanged.

**⚠ A PREDICTION OF MINE WAS WRONG, RECORDED SO IT IS NOT REPEATED:** I expected INV-2 (reset now
held until the DCR bootstrap handshake, `e8ca365`) to have removed the X-on-reset window that makes
these fire. **It did not.** The firings are identical in time and location to the original report.
Do not re-run this experiment expecting a different answer without first changing something about
the reset or X behaviour at time 0.

**What this changes about the entry above.** Our modification is **not gratuitous** — with the
upstream file the A5 gate fails EVERY run, so the bench could not operate at all. That is a real
justification, and it was missing from this entry. What remains true is that our fix is **broader
than necessary**: it guards on `incr`/`decr` being unknown, which also disables the check during
normal operation, when an X on those inputs would indicate a genuine defect. The narrower fix — gate
on `reset` / X-on-`reset`, leaving the data-path check armed — is identified but **NOT tested**, and
must not be described as validated.

**Decision (2026-08-18): KEEP OURS.** Tried, measured, failed, reverted; `git status` clean, md5
verified against the pre-swap backup. The full-suite trial was not run because the single smoke test
already failed the acceptance rule.

**✅ RTL FROZEN — FINAL DECISION 2026-08-19.** The tree keeps its current state and **no further
RTL review or change is planned**. Specifically:
* `libs/VX_pending_size.sv` — **upstream, unmodified** (our weakened version retired; assertions
  armed and silent because the underlying defect is fixed).
* `libs/VX_reset_relay.sv` — **our async-assert/sync-deassert fix** (OBS-045). A defect fix, and
  upstream-reportable.
* The remaining **16 files stay as they are and will NOT be reviewed** — including
  `tcu/VX_tcu_fedp_bhf.sv` (193 code lines), `tcu/VX_tcu_fedp_dpi.sv` (111), the other TCU files,
  and the FPU files (whose diffs are ~300 lines of COMMENTED-OUT dead code and 0 code lines).
**Still 18 files differ from upstream `7a52ee5`** — the COUNT is unchanged from before this session;
what improved is the COMPOSITION (a defect fix replaced a checker workaround). The papers' provenance
disclosure must keep saying 18.
⚠ **Open risk accepted knowingly:** the TCU changes are substantial and undocumented, so any claim
about TCU verification rests on RTL this register has never described. State that limit if the TCU
is discussed.

**⚠ RTL IS TO BE LEFT AS IS (decision, 2026-08-17).** No revert, no re-fix. This entry is the
disclosure, not a work item. Consequently the papers and any report MUST describe the DUT as
"Vortex `7a52ee5` with 18 locally modified RTL files (see OBS-040)", never as unmodified upstream,
and the X-propagation future-work item must state that this module currently masks X.

**Disposition: OPEN (DISCLOSURE REQUIRED, RTL UNCHANGED BY DECISION).** Required actions: (a) disclose in the paper's methodology
that the DUT is patched, naming the 18 files; (b) NOT a code change — the RTL stays as
is by decision; (c) ensure the X-prop future-work item notes that this module masks X. No claim of
the form "we verified unmodified upstream Vortex" is accurate.

---

## OBS-041 — REFUTED: changing `MREQ_SIZE` does NOT cascade into cache banks or memory port width

**Class:** DOCUMENTATION CORRECTION (an inherited claim, measured false) · **Disposition:
CLOSED — refuted with citations** · **Found:** 2026-08-17.

**The claim.** The bring-up issue report (§P1, "Queue Size Changes: The RTL Cascade You
Haven't Tested") states that raising `ICACHE_MREQ_SIZE`/`DCACHE_MREQ_SIZE`/`DCACHE_MRSQ_SIZE`
from 4 to 16 "cascaded through arbitration logic … `DCACHE_NUM_REQS` scales based on
`DCACHE_MREQ_SIZE`, which ultimately redefines `DCACHE_NUM_BANKS` and subsequently
`L1_MEM_PORTS`", changing top-level port array widths. If true, every bank taken with our
`MREQ_SIZE=16` override would describe a structurally different machine.

**It is false. Two independent lines of evidence.**

*Static, by citation:*
```
VX_gpu_pkg.sv:818   DCACHE_NUM_REQS  = `NUM_LSU_BLOCKS * DCACHE_CHANNELS
VX_config.vh:618    DCACHE_NUM_BANKS = `MIN(DCACHE_NUM_REQS, 16)
VX_config.vh:664/666 L1_MEM_PORTS    = `MIN(DCACHE_NUM_REQS | DCACHE_NUM_BANKS,
                                            `PLATFORM_MEMORY_NUM_BANKS)
```
`DCACHE_NUM_REQS` is a function of LSU blocks and cache channels. **No definition of
`DCACHE_NUM_REQS`, `DCACHE_NUM_BANKS` or `L1_MEM_PORTS` references `MREQ_SIZE` anywhere in the
RTL.** The dependency chain the claim describes does not exist.

*Dynamic, by measurement (the OBS-032 experiment):* `mshr_flood` rebuilt at
`CACHE_MREQ_SIZE=4` versus the banked 16 produced **bit-identical branch (12565/18913),
condition (524/1707) and statement (20428/23461) counts**. A change in memory port width
could not leave those identical.

**⚠ The nearby claim that IS true, and should not be lost with the refuted one:**
`DCACHE_MSHR_SIZE` *does* feed `DCACHE_MEM_TAG_WIDTH` (`VX_gpu_pkg.sv:833`), so **MSHR** depth
genuinely does affect a top-level width. It is harmless here only because we set it to 16,
which is already the RTL default (`VX_config.vh:628`) — i.e. that override is a no-op. Anyone
changing `MSHR_SIZE` must expect real structural consequences. See OBS-032.

---

## OBS-042 — the suite reports a TESTBENCH TIMEOUT as "FAILED (RTL assertion)", pointing the blame at the DUT

**Class:** TB REPORTING DEFECT (methodology) · **Disposition: OPEN** · **Found:** 2026-08-18, first
L2/L3 bank attempt.

**What we saw.** The 2CL + L2 + L3 suite reported `SUITE VERDICT: 45 staged, 6 FAILED`, and every
one of the six printed:
```
  -> FAILED (RTL assertion) — UCDB NOT staged
```
All six are riscv-dv (`jump_stress`, `non_compressed_instr`, `loop`, `rand_instr`, `mmu_stress`,
`full_interrupt`). **Not one is an RTL assertion.** Every one is:
```
** Error: [TB_TOP @ 6003845000] TIMEOUT after 600000 cycles!
```

**Mechanism.** `scripts/run_suite.sh:48` classifies a non-zero make result by grepping the
transcript:
```bash
grep -q "^# \*\* Error" results/latest/logs/simulation.log && why="RTL assertion"
```
The TB's own timeout error is printed with the same `# ** Error:` prefix Questa uses for RTL
assertion failures, so the classifier cannot tell them apart and defaults to blaming the RTL.

**Why this is serious rather than cosmetic.** "FAILED (RTL assertion)" is a DUT accusation. The
truth here is that OUR cycle budget was too small for a deeper cache hierarchy. Had this line been
taken at face value in a report or a paper, it would have claimed six design failures that do not
exist. This is the same class as OBS-027, where a methodology defect masqueraded as four DUT
divergences and was believed for weeks — and it is the reason that entry insists on reading the
transcript rather than the verdict label.

**The underlying (benign) cause.** With L2 and L3 enabled, every L1 miss traverses two additional
cache levels, so the same program needs materially more cycles. The riscv-dv budget is
`TIMEOUT=600000` (`run_suite.sh`, riscv-dv runners), which sufficed at 2CL with both levels in
passthrough and does not with them enabled. Same family as the measured budget shortfalls already
on record (`text_big` 490,468; `barrier_sync_test` 164,602; `wide_stress`).

**Consequence for the bank.** The resulting `93.04%` at 45/51 staged is **NOT a valid bank** and
must not be quoted: an incomplete merge is not a bank with known exclusions, and the six missing
runs are exactly the random-stimulus half of the suite.

**Disposition: OPEN.** Fixes, in order: (a) classify the transcript properly — match the TB's
timeout signature *before* the generic `# ** Error` test, and label it `TIMEOUT (budget)`, never
"RTL assertion"; (b) measure what the riscv-dv profiles actually need with L2+L3 on and set the
budget to ≥3x that, rather than guessing; (c) only then re-run the L2/L3 bank. Do NOT raise the
budget blindly — a budget chosen without measurement is what produced this entry.

---

## OBS-043 — `results/run_suite_logs/` is never cleared, so logs from tests that did NOT run in this suite read as current results

**Class:** TB REPORTING HAZARD · **Disposition: OPEN** · **Found:** 2026-08-18, while analysing the
L2/L3 re-runs — it produced a false finding that had to be retracted.

**What happened.** `rv_riscv_pmp_test.log` sits in `results/run_suite_logs/` and reports a clean run
of 158,461 cycles. It looks like part of the current bank. It is not: `riscv_pmp_test` was **dropped
from the suite** as the FW-1b byte-identical duplicate (`eb8a630`), so it has not run since
**2026-08-12** — the log's mtime. Comparing it against `riscv_non_compressed_instr_test` from the
2026-08-18 L2/L3 run (1,767,248 cycles) appeared to show an 11x discrepancy between two programs
FW-1b records as byte-identical, i.e. an apparent refutation of FW-1b. **There is no discrepancy.**
Two different suites, six days and one whole cache configuration apart.

**Mechanism.** `run_suite.sh` writes each run's transcript to a FIXED filename
(`$LOGDIR/rv_<test>.log`, `k_<kernel>.log`, ...) and `$LOGDIR` is created with `mkdir -p` but never
emptied. A file is therefore overwritten only if that same test runs again. Any test removed from
the suite, renamed, or skipped leaves its last transcript behind indefinitely, indistinguishable by
name from the current run's output.

**Why it matters.** The banked UCDBs are unaffected — staging is rebuilt per suite with
`merge_coverage.sh --fresh`, so no stale coverage can enter a bank. The damage is to ANALYSIS: the
log directory is what we read when root-causing, and it silently mixes runs from different
configurations. Here it nearly produced a documented "FW-1b refuted" claim from a file that predates
the configuration under discussion.

**Positive result found by the same check (worth keeping):** `riscv_non_compressed_instr_test`
regenerated to hash `732adb3a` in **three separate runs on three different days**. Seed control
(FW-1) is reproducible in practice, not just in principle.

**✅ FIXED 2026-08-19** (`run_suite.sh`): `$LOGDIR` is now `rm -rf`'d and recreated at suite start,
so what is in it is what ran. The per-run archive copies the banking convention already makes
(`results/run_suite_logs_<config>_<date>/`) remain the historical record.
**Standing habit regardless: check the mtime of any log before drawing a conclusion from it.**

---

## OBS-044 — runs staged TWICE under two different keys when a test is run outside the suite and then collected

**Class:** TB BOOKKEEPING · **Disposition: OPEN (numbers unaffected)** · **Found:** 2026-08-18,
merging the targeted L2/L3 re-runs.

**What we saw.** After re-running 6 riscv-dv profiles standalone and then calling
`merge_coverage.sh --collect` on their run directories, `cov/staging/` held **57** UCDBs where 51
were expected — with **6 exact md5 duplicate pairs**.

**Mechanism — two staging keys for the same run:**
* `simulate.sh` auto-stages every passing run as `<test>_<program>.ucdb`
  (e.g. `random_instruction_stress_test_riscv_loop_test.ucdb`).
* `run_suite.sh` / `merge_coverage.sh --collect` stage by run directory as
  `<date>_<run>_<test>.ucdb` (e.g. `20260818_run_161951_random_instruction_stress_test.ucdb`).
Inside the suite this is invisible, because `--fresh` clears staging first and every run arrives by
one path. Run a test by hand and then collect it, and it is staged under BOTH names.

**Impact: none on coverage, real on bookkeeping.** Coverage is a set union, so merging identical
data twice cannot change a covered-bin count — verified directly here: the 57-UCDB merge and the
deduplicated 51-UCDB merge produce **identical** results (total 93.18%, bins 1042/1092). What it
does corrupt is the run inventory (a bank appearing to contain 57 runs when 51 were executed) and
it adds `vcover-6854` duplicate-test-record noise (see OBS-039).

**Handling this time:** the 6 auto-staged copies were deleted by name, staging re-verified at 51
with 0 md5 duplicates, and the bank re-merged from the clean set.

**✅ FIXED 2026-08-19** (`merge_coverage.sh`): `--collect` now md5-compares each incoming UCDB
against everything already staged and SKIPS an exact duplicate, printing
`Skipped (already staged as <name>)`. Content-based, so it works regardless of which key the other
path used. **Standing habit regardless: check `ls cov/staging/*.ucdb | wc -l` against the expected
count before banking.**

---

## OBS-045 — THE DISTRIBUTED RESET IS X FOR ONE CLOCK: `VX_reset_relay` registers reset in a flop that nothing resets

**Class:** RTL BUG (X-generating reset distribution) · **Disposition: open — needs-RTL-fix** ·
**Found:** 2026-08-18, root-causing why upstream's `VX_pending_size` assertions fire (OBS-040).

**What we saw.** With upstream's unmodified `VX_pending_size.sv`, 12 assertions fire at **5 ns,
15 ns and 25 ns** on `icache…bank.mshr_pending_size` and the dcache equivalent. Top-level reset is
asserted from time 0 (`vortex_tb_top.sv:54` `logic reset_n = 1'b0;` → `.reset(!reset_n)` = 1), so the
`if (reset)` in the counter should have taken the reset branch and never evaluated the assertions.

**Root cause.** The cache does not receive the top-level reset directly. `VX_socket.sv:87`:
```systemverilog
`RESET_RELAY (icache_reset, reset);      // -> VX_reset_relay #(.N(1), .MAX_FANOUT(0))
```
and `VX_reset_relay.sv:25-33` takes the `g_relay` branch (the guard
`MAX_FANOUT >= 0 && N > (MAX_FANOUT + MAX_FANOUT/2)` is `0>=0 && 1>0` = TRUE, F=1, R=1), which
**registers** the reset:
```systemverilog
`PRESERVE_NET reg [R-1:0] reset_r;        // no initial value
always @(posedge clk) begin
    reset_r[i] <= reset;                  // nothing resets THIS flop
end
assign reset_o[i] = reset_r[i / F];
```
`reset_r` is a flop with **no initializer and no reset**, so `reset_o` is **X from time 0 until the
first posedge propagates the real reset**. Every module behind a relay therefore sees an UNKNOWN
reset for at least one clock. `if (X)` takes the ELSE branch, the counter's assertions evaluate with
X operands, the comparison yields X, and X is not true — so they fire. The 5/15/25 ns pattern is
successive posedges while the relay chain fills.

**⚠ THIS CORRECTS OBS-040's FRAMING.** That entry treated our `$isunknown` guard as suppressing a
testbench nuisance. It is not: **upstream's assertion was reporting a real property of the design.**
Our guard silenced a correct report. The guard is still the reason the bench can run at all
(measured: upstream's file fails every run), but the thing it silences is a genuine X window, not
noise.

**Why it matters beyond the assertion.**
1. **Simulation/silicon divergence.** In simulation the window is X. In silicon the flop powers up
   at some definite value — possibly the DEASSERTED one, in which case a module behind a relay is
   briefly NOT held in reset while the rest of the design is. Nothing in this campaign would see it:
   X-propagation analysis is absent (and our `VX_pending_size` initializers actively mask X).
2. **It is the OBS-025 pattern again.** OBS-025 already records unreset elements in the DCR
   broadcast tree, benign only because a condition is false. This is the same class on the CACHE
   reset path, and it is not benign — it demonstrably produces X.
3. **Scope.** Every `` `RESET_RELAY `` / `` `RESET_RELAY_EX `` site is affected, not just the icache.

**Fix options.**
* **(a) Declaration initializer** `reg [R-1:0] reset_r = {R{1'b1}};` — removes the X in simulation
  only; ASIC flops still power up unknown. This MASKS rather than fixes, and is the same criticism
  levelled at our `VX_pending_size` change.
* **(b) Async-assert / sync-deassert synchroniser** (textbook, chosen):
  ```systemverilog
  always @(posedge clk or posedge reset)
      if (reset) reset_r <= '1; else reset_r <= '0;
  ```
  `reset_o` asserts immediately whenever `reset` asserts, regardless of flop state, and deasserts
  synchronously. No X window in simulation OR silicon. Reset asserts one cycle EARLIER than before
  (strictly more reset, not less).

**✅ FIX (b) APPLIED AND VALIDATED 2026-08-18.**

| check | result |
|---|---|
| Smoke test (`vecadd_lite`, upstream UNMODIFIED `VX_pending_size`) | **12 counter assertions -> 0**, TEST PASSED |
| Gate-0 `negative_result_test` `+INJECT_FAULT` | **RED — "checker DETECTED the injected fault at addr=0x800075d8 … Verdicts are not vacuous"** |
| Gate-0 `negative_dropped_store_test` `+DROP_STORE` | **RED — "DROPPED STORE addr=0x800075d8 DUT(mem)=0x0 SimX=0x600dc0de"** |
| Full 1CL suite | **51 staged, 0 FAILED**, total **94.72%**, hits-invariant held |
| Counter assertions across the whole suite | **0** |

The assertions are now ARMED (upstream's own, unguarded) and SILENT, which is a different statement
from guarded and silent. **Our local `VX_pending_size` modification has been retired** — that file
now matches upstream byte-for-byte. The modification moved from the CHECKER to the DEFECT.

**⚠ AN UNEXPECTED AND INSTRUCTIVE COVERAGE EFFECT — BRANCH COVERAGE WENT DOWN.**

| | relay fixed (51 runs) | previous (50 runs, X window) |
|---|---|---|
| Branches | **2663 / 2817 = 94.53%** | 2673 / 2811 = 95.09% |
| Toggles | 344,353 = 83.34% | 342,268 = 82.83% |
| Total | 94.72% | 94.72% |

The +6 branch denominator is this fix's own `if (reset)/else`. The **−10 COVERED branches** is the
interesting part: during the X-reset cycle, `if (X)` took the ELSE branch, so modules behind a relay
were executing their NORMAL-OPERATION paths during what should have been reset — and those
executions were **counted as covered branches**. With reset correct, they are not taken, and that
coverage disappears. ⇒ **A small part of the previously-banked branch coverage was obtained from a
state that cannot legitimately occur. 94.53% is the more honest number.**

**⚠ ATTRIBUTION CAVEAT — do not quote these deltas as pure relay-fix effects.** Two variables
changed between the two banks: the relay fix AND `cache_tier` newly running at 1CL (51 vs 50 runs).
The toggle rise in particular is more plausibly `cache_tier`'s ~1.5 MB of traffic. A controlled
one-variable re-run was NOT done.

Bank: `cov/bank_1CL_1C_4W_4T_relayfix_20260818/` · logs `results/run_suite_logs_1CL_relayfix_20260818/`.

**⚠ THE OTHER TWO BANKS (2CL, 2CL+L2/L3) WERE TAKEN ON THE X-WINDOW DESIGN** and have NOT been
re-run. They remain valid as measurements of that design; they are not comparable to this one on
branches. Decide before the paper whether to re-bank.

**Disposition: FIXED (local); still present upstream — reportable.** Original text follows.

**Disposition: open — trying (b) 2026-08-18.** Acceptance: with (b) applied, upstream's UNMODIFIED
`VX_pending_size.sv` must run clean (0 counter assertions) — i.e. the assertions pass for the RIGHT
reason rather than being guarded off. If that holds, our local `VX_pending_size` modification can be
retired and the provenance problem in OBS-040 shrinks accordingly.

---

## OBS-046 — FW-1 SEED FARM: 90 additional distinct random programs bought ZERO coverage. Seed volume was not the gap.

**Class:** METHODOLOGY RESULT (negative, and the most useful kind) · **Disposition: closed —
measured** · **Found:** 2026-08-19.

**What was run.** The committed suite pins `RV_SEED=1`. This swept **seeds 2–11 across all 9
riscv-dv profiles = 90 additional runs**, taking the campaign from 1 seed per profile to 10.
Config 1CL/1C/4W/4T on the reset-fixed design.

| | result |
|---|---|
| Runs | **90 / 90 PASS, 0 failures** |
| Distinct programs | **90 / 90**, verified by content hash — no collisions |
| Cycle range | 4,432 … 857,190 (≈190x spread; 4x within a single profile) |

**Non-vacuity was checked, not assumed.** Per profile, the seed-2 program hash was compared against
the seed-1 program from the suite: all 9 differ. A seed farm where the seed silently does not take
effect looks exactly like a successful one — 90 green runs either way.

**⚠ THE COVERAGE RESULT — 90 NEW PROGRAMS MOVED ALMOST NOTHING.**

| metric | suite (51 runs) | suite + seed farm (141 runs) |
|---|---|---|
| Assertions | 96.85% | 96.85% |
| Branches | 94.53% | 94.53% |
| Conditions | 90.41% | 90.41% |
| Covergroup bins | 370/377 = 98.14% | 370/377 = 98.14% |
| Statements | 98.10% | 98.10% |
| Toggles | 83.34% | **83.40%** |
| **Total** | **94.72%** | **94.72%** |

Every category is bit-identical except toggle, +0.06%.

**Interpretation — and this corrects a recommendation made in this same session.** Seed volume was
argued (by me) as "the single highest-return item" for strengthening the campaign. In **coverage**
terms that was WRONG: the return is ~zero. In **confidence** terms it was right, and that is a
different and still-valuable claim: 90 programs the DUT had never executed all pass end-state
equivalence against the golden model, so the design is demonstrably not tuned to the committed seed.

The mechanism is that **the generator's REACH, not its sample count, is the binding constraint.**
riscv-dv here emits `rv32im` user-mode code with M-mode CSR writes stripped
(`prepare.sh --target=rv32im` + sed), so every seed explores the same region of the state space.
Coverage saturated inside that region long before seed 10. **No number of seeds reaches the
exception paths, error responses, or privileged behaviour that remain uncovered** — those need
different STIMULUS KINDS, not more samples of the same kind.

**Consequence for claims (use this wording):** *"10 seeds per profile, 90 additional distinct
programs, 0 failures"* is a defensible constrained-random statement about ROBUSTNESS. It is NOT
evidence of thoroughness, and it must not be offered as coverage progress — measured, it produced
none. The remaining stimulus gap is diversity (error/exception axes), not volume.

**Bank:** `cov/bank_1CL_1C_4W_4T_seedfarm_20260819/` (141 staged) · farm log
`results/seed_farm_logs/seed_farm_results.txt`.

**⚠ SECONDARY DEFECT FOUND — OBS-044 WAS ONLY HALF FIXED.** `simulate.sh` auto-stages under
`<test>_<program>.ucdb`, a key that is **not unique across seeds**: all ten seeds of a profile write
the SAME filename, so 81 of the 90 UCDBs were silently overwritten and staging held 60 where 141 was
expected. Caught only by checking the staged count before merging. Had it gone unnoticed, the merge
would have run over 60 files, produced a plausible number, and understated the farm — no error, no
warning. Worked around here by collecting all 90 run directories explicitly (`--collect` uses unique
`<date>_<run>` keys; the 9 auto-staged ones were correctly skipped as content-duplicates by the
OBS-044 fix). **The auto-stage key itself still needs a run-unique component.**

---

## OBS-047 — `run_vortex_uvm_enhanced.sh`'s generic "custom ELF" path double-offsets hex load addresses by `0x80000000`

**Class:** TB TOOLING DEFECT (not RTL) · **Disposition: OPEN, low priority (documented workaround
exists)** · **Found:** 2026-08-20, while proving the Vortex submodule conversion (OBS-048-adjacent
session, see `docs/INDUSTRIAL_TRANSFORMATION_PLAN.md` → ▶▶ RESUME HERE 2026-08-20) actually builds
and runs a kernel end-to-end on a fresh checkout.

**What we saw.** Invoking `scripts/run_vortex_uvm_enhanced.sh --test=kernel_launch_test
--program=<full path to tests/kernel/vecadd_lite/vecadd_lite.elf>` compiled the RTL cleanly (0
errors), built and initialised SimX successfully (`RAM verification PASSED`), then crashed
immediately on load with `** Fatal: (SIGABRT) Bad handle or reference` inside
`uvm_env/ref_model/simx_pkg.sv:39`, called from `vortex_scoreboard.svh:275`
(`simx_load_hex_at`).

**Root cause, traced through the actual crash backtrace** (`RAM::get` → `RAM::write` →
`ram_write_cached` → `simx_load_hex_at`): `RAM::get()` throws `OutOfRange()` when
`address >= capacity_` (`Vortex/sim/common/mem.cpp:450-451`). The generated `.hex` file's `@`
address markers read `@0000000100000000` = `0x100000000` — exactly the RAM's configured capacity,
and exactly `0x80000000` (2 GiB) higher than the kernel's real link address of `0x80000000`. The
ELF's own program headers already encode an absolute load address; the script's generic ELF→hex
conversion path (Case 6, `scripts/run_vortex_uvm_enhanced.sh` around line 617) adds `base_addr` a
**second time** on top of that, producing an address that lands exactly on the capacity boundary
and throws. The C++ exception then crosses the DPI/SV boundary uncaught, which QuestaSim reports
as a generic `SIGABRT` — the real cause is two call-frames away from what the simulator log shows.

**Confirmed NOT present on the documented entry point.** `make sim TEST=kernel_launch_test
PROGRAM_NAME=vecadd_lite CLUSTERS=1 CORES=1 WARPS=4 THREADS=4 TIMEOUT=50000` — which resolves to
the exact same `.elf`, through the Makefile's own hex-generation step rather than the raw script's
Case 6 — ran clean: `SIMULATION PASSED — all checks matched!`, 0 UVM errors, 0 RTL errors, 9,905
cycles, 1,881 instructions. The bug is specific to driving a `tests/kernel/*.elf` by raw full path
through the generic script; every documented invocation in this project's history goes through the
Makefile, so this had apparently never been exercised against a `tests/kernel/*` binary before.

**Disposition: OPEN, workaround is simply "use the documented entry point."** A real fix (stop
adding `base_addr` when the ELF's own address is already absolute, mirroring the logic
`simx_load_hex_at` itself already applies for `@`-marker parsing) is cheap but not urgent — nobody
in this project's actual test flow uses the affected path.

---

## OBS-049 — `op_type` is overloaded across ALU sub-types, and our `cp_alu_op` does not qualify on `xtype` (real coverage defect, found 2026-09-03)

**What we saw.** While auditing which parts of the Vortex ISA the third-party riscvISACOV
model can and cannot score, the `EX_ALU` dispatch turned out to carry **four disjoint
opcode namespaces in the same `op_type` field**, selected by `op_args.alu.xtype`
(`VX_gpu_pkg.sv:205-209`):

| `xtype` | `op_type` means | decode site |
|---|---|---|
| `ALU_TYPE_ARITH` | `INST_ALU_*` (14 codes, `VX_gpu_pkg.sv:187-202`) | — |
| `ALU_TYPE_BRANCH` | `INST_BR_*` (`:229-242`) | `VX_decode.sv:258,269,282,314` |
| `ALU_TYPE_MULDIV` | `INST_M_*` (`:280-287`) | `VX_decode.sv:183,225` |
| `ALU_TYPE_OTHER` | `funct3` = VOTE/SHFL (`:265-273`) | `VX_decode.sv:507-517` |

**Evidence of the defect.** `tb/vx_instr_probe.sv:288-306` samples `alu_class_cg` on
**every** accepted `EX_ALU` dispatch, and `cp_alu_op` (`:108-123`) bins on `op_type`
alone with **no `xtype` qualifier**. The namespaces collide numerically, so:

* `vote.all` (`funct3=3'b000`), `mul` (`INST_M_MUL=3'b000`) and `beq`
  (`INST_BR_BEQ=4'b0000`) all increment the **`add`** bin.
* `sub` (`INST_ALU_SUB=4'b0111`) shares its value with `INST_M_REMU` and `INST_BR_BGE`.
* Similar collisions exist across `lui`/`auipc`/`slt`/`sltu`.

**Two consequences, both real:**
1. **`instr_class_cg_alu` hit counts are contaminated.** The bin percentages are still
   valid as "this bin was reached", but the counts are not attributable to the named
   instruction. No bin is falsely *covered* by this alone (every colliding code has a real
   arithmetic producer in these workloads), so **no previously reported coverage number is
   invalidated** — but the counts must not be quoted per-instruction.
2. **VOTE and SHFL have no coverage of their own.** These are Vortex-specific warp-level
   primitives (`vote.all/any/uni/bal`, `shfl.up/down/bfly/idx` — 8 operations) that no
   third-party model will ever cover, and our own model does not distinguish them either.
   The `vote_shfl` kernel stimulates them (session 11) and they were credited only with
   moving an `ALU_TYPE_OTHER` *condition*, never a functional bin.

**Classification: TB coverage-model defect, exposed by an RTL encoding quirk.** The RTL is
not wrong — reusing the field is a sensible area optimisation and `xtype` disambiguates it
correctly for execution (`VX_alu_int.sv:193`). The defect is that the probe read one half
of a two-part key.

**Disposition: OPEN.** Fix = pass `dispatch_if[gi].data.op_args.alu.xtype` into
`alu_class_cg` and either (a) qualify `cp_alu_op` with `iff (xtype == ALU_TYPE_ARITH)`, or
(b) better, split into four coverpoints — `cp_alu_op`, `cp_br_op`, `cp_muldiv_op`,
`cp_vote_shfl_op` — which additionally *creates* the missing VOTE/SHFL and branch-opcode
coverage rather than only cleaning up the existing bins. Option (b) changes the denominator
of `instr_class_cg_alu`, so it must be banked as its own measurement and never compared
across the change.

---

## OBS-049 ADDENDUM — FIXED 2026-09-03, and the fix proves the old `cp_alu_op 100%` was not attributable

**Fix applied (option (b) above):** `tb/vx_instr_probe.sv` — `alu_class_cg` now takes
`op_args.alu.xtype`, `cp_alu_op` is qualified `iff (xtype == ALU_TYPE_ARITH)`, and three new
coverpoints were added: `cp_branch_op`, `cp_muldiv_op`, `cp_vote_shfl_op`, plus `cp_xtype`.

**Measured, `kernel_launch_test`/`vecadd_lite`, 1CL/1C/4W/4T (run_152018):**
TEST PASSED, 9,915 cycles, 1,881 instructions — byte-identical to the documented baseline,
so the change is non-perturbing.

| coverpoint | result |
|---|---|
| `cp_xtype` | 3/4 (OTHER absent — vecadd_lite has no VOTE/SHFL) |
| `cp_alu_op` (now qualified) | **11/14** — `slt`, `czeq`, `czne` correctly ZERO |
| `cp_branch_op` (new) | 6/10 |
| `cp_muldiv_op` (new) | 3/8 |
| `cp_vote_shfl_op` (new) | 0/8 — needs the `vote_shfl` kernel |

**The integrity finding.** The frozen 1CL bank reports `cp_alu_op` = **100.00%, 14/14
COVERED**. That number cannot be attributed, because the encodings alias EXACTLY:

```
INST_ALU_ADD  = 4'b0000  ==  INST_BR_BEQ    = 4'b0000  ==  INST_M_MUL = 3'b000  ==  VOTE_ALL
INST_ALU_CZEQ = 4'b1010  ==  INST_BR_ECALL  = 4'b1010
INST_ALU_CZNE = 4'b1011  ==  INST_BR_EBREAK = 4'b1011
```
(`VX_gpu_pkg.sv:187-201`, `:229-242`, `:280-287`.)

So the bank's `czeq`/`czne` bins are hit by **`ecall`/`ebreak`**, which every riscv-dv program
executes (`prepare.sh` rewrites `ecall`→`ebreak`, OBS-024) — regardless of whether any Zicond
instruction ever ran. The probe's own inline comment said `czeq`/`czne` were *"ZERO until a
Zicond build runs"*, while the bank simultaneously reported them covered; that contradiction
was the tell. Likewise `bins add`'s count included every `beq` (81 on vecadd_lite alone) and
every `mul`.

**This does not mean the bins were never legitimately hit** — `multicore_isa` does emit real
`czeq`/`czne` via inline `.insn`, so in a full-suite bank some hits are genuine. The defect is
that the unqualified coverpoint **cannot distinguish the two**, so no attribution claim built
on it is sound.

**Disposition: FIXED in the collector; the affected banks are NOT regenerated.** The three
frozen banks retain the unqualified coverpoint. Any future statement about ALU-op coverage
must come from a post-fix bank, and pre/post banks must never be compared on
`instr_class_cg_alu` — the denominator moved from 14 to 44 bins (14+4+10+8+8).

---

## OBS-050 — `fence.i` is decoded as a plain data `fence`: `funct3` is never read, and `INST_FENCE_I` is dead

**What we saw.** `VX_gpu_pkg.sv:334-336` declares the discriminator:
```systemverilog
localparam INST_FENCE_BITS = 1;
localparam INST_FENCE_D =    1'h0;
localparam INST_FENCE_I =    1'h1;
```
but grep across **all** of `Vortex/hw/rtl/` and `Vortex/sim/simx/` finds **no reference to
either `INST_FENCE_D` or `INST_FENCE_I` outside their own declarations.** They are dead
localparams.

The decoder confirms it — `VX_decode.sv:291-297` matches the opcode and never inspects
`funct3`:
```systemverilog
INST_FENCE: begin
    ex_type = EX_LSU;
    op_type = INST_LSU_FENCE;
    op_args.lsu.is_store = 0;
    op_args.lsu.is_float = 0;
    op_args.lsu.offset = 0;
end
```
`INST_FENCE = 7'b0001111` (`VX_gpu_pkg.sv:145`) is the opcode shared by `fence` (funct3=000)
and `fence.i` (funct3=001). **Both therefore produce the identical `INST_LSU_FENCE` op**, which
drives the *data* path (`VX_lsu_slice.sv:73 req_is_fence` → dcache, per the icache waiver
evidence). `Zifencei`'s architectural purpose — making stores visible to the *instruction*
fetch stream — is not implemented. On a machine whose icache is `.WRITE_ENABLE(0)`
(`VX_socket.sv:106`) with no coherence, self-modifying or JIT-generated code would not become
visible after a `fence.i`.

**Evidence from coverage.** Generated the `RV32Zifencei` bank (16-row dvplan → 1 covergroup)
and ran it: `RV32Zifencei::fence_i_cg` = **0.00%, bin `count[1]` ZERO** on `vecadd_lite`. So
the path is not exercised by current stimulus — the finding rests on the code reading, not on
an observed failure.

**Classification: latent RTL gap, not a live bug.** Nothing in the current software stack
emits `fence.i` (the compiler emits it only for `__builtin___clear_cache`), and Vortex has no
self-modifying-code use case, so the aliasing is harmless *today*. It is an unimplemented
architectural guarantee that the MISA/decoder surface does not advertise either way.

**Disposition: OPEN, documented, NOT waived.** The `RV32Zifencei` covergroup is retained
precisely so the zero bin is visible rather than assumed. Closing it properly would require
either (a) implementing an icache invalidate on `funct3==1`, or (b) an explicit statement that
Vortex does not implement Zifencei. Note Vortex does **not** claim Zifencei in MISA, so (b) is
defensible; this is a documentation gap more than a correctness one.

## OBS-051 — Gap G-0 closed: `VX_mem_coalescer` had zero functional coverage; `misses` is a cumulative run-total, not a per-request measure

**What we saw.** No coverpoint anywhere in the collector or the probe set observed
`VX_mem_coalescer` (`Vortex/hw/rtl/libs/VX_mem_coalescer.sv`) — the module that merges per-lane
LSU requests into wider dcache-line transactions, i.e. the entire reason a GPU memory path is
faster on coalesced access patterns than scattered ones. Whether a warp's accesses actually
coalesced, partially coalesced, or fully scattered was invisible to the coverage model.

**`misses` semantics, read from the RTL (not assumed).** The module's own performance-counter
output, `misses` (`VX_mem_coalescer.sv:41`), is fed by:
```systemverilog
wire partial_transfer = (out_req_fire && req_rem_mask_r != '1);
always @(posedge clk) misses_r <= misses_r + PERF_CTR_BITS'(partial_transfer);
```
(`:332-344`). This is a **free-running, wrapping counter accumulated across the whole
simulation** — it counts every output batch that was NOT the first batch of its input request,
with no per-request reset. It cannot be binned per-transaction directly; a coverpoint sampling
its raw value would just be watching a monotonic-ish counter climb, which has no per-bin
meaning. `VX_mem_unit.sv:143` leaves the `misses` port as `` `UNUSED_PIN `` when
`` `ifndef PERF_ENABLE `` is not defined at the instantiation site — but `misses_r` itself is
computed **unconditionally** inside the module, with no `` `ifdef `` around it, so a `bind`
(which attaches to the module's internal scope, not through its external port connections)
sees the real accumulating value regardless of how the surrounding design wired the port.
Confirmed by reading `VX_mem_unit.sv:160-200` in full: the `PERF_ENABLE` split is entirely
about the port, never the internal logic.

**Fix / new coverage (`Vortex/sim/uvmsim/tb/vx_coalescer_probe.sv`, bound in
`vortex_tb_top.sv` alongside the other passive probes, registered in
`Vortex/sim/uvmsim/flists/uvm_env.flist`).** Instead of binning the running counter, the probe
re-derives the identical `partial_transfer` event **per input request** — a local
`batch_count_r` increments once per `(req_sent && !is_last_batch)` cycle (`req_sent` =
`VX_mem_coalescer.sv:243`'s `state_r == STATE_SEND`; `is_last_batch` = `:184`) and is read at
the `in_req_valid && in_req_ready` handshake, where it still holds its pre-clear value (NBA
semantics) — i.e. the exact per-request analogue of what `misses_r` accumulates. `cp_misses`
bins that value 0 (`fully_coalesced`) through `DATA_RATIO-1` (worst case). A second
coverpoint, `cp_coalesce_kind`, classifies each request as `full_coalesced` (1 output batch),
`partial` (more than 1 batch but fewer than active-lane-count), or `full_scatter` (batches ==
active lanes, i.e. zero coalescing benefit) — the actual GPU-relevant behaviour G-0 exists to
close. Both `NUM_REQS`/`DATA_RATIO`/`OUT_REQS` are the bound instance's own elaborated
parameters (bind inherits them), never hardcoded; the probe elaborates only where
`VX_mem_unit.sv:160`'s `` (`NUM_LSU_LANES > 1) && (LSU_WORD_SIZE != DCACHE_WORD_SIZE) ``
guard instantiates a coalescer at all — config-aware by construction, same principle as
`vx_cache_probe`.

**Directed kernel (`Vortex/tests/kernel/coalesce_probe/`).** Drives three lane→address layouts
per warp-group of `NUM_THREADS` lanes at the primary config (1CL/1C/4W/4T, DATA_RATIO=4
words/line): stride-1-word (full coalesce), stride-2-words (partial: pairs of lanes share a
line), stride-4-words (full scatter: every lane its own line) — for both a store phase and a
load phase (two separate `vx_spawn_threads` calls, identical geometry, so task `i` lands on the
same core both times per `vx_spawn.c:299`'s contiguous distribution; OBS-026-safe, no barrier).
**Note the briefing's literal "stride 4 words (lanes span 2+ lines)" for the PARTIAL pattern
does not hold at this config** — a 4-word/16-byte stride puts every lane on its own line (that
is the SCATTER case), verified by hand-tracing the coalescer's `addr_matches`/batch logic. The
kernel uses a 2-word/8-byte stride for partial instead, which is what actually produces "lanes
span 2+ lines" at `NUM_REQS=4`/`DATA_RATIO=4`. Flagging this because the repo/RTL geometry
should always win over a literal number in a briefing, per project convention.

**Measured result** (`kernel_launch_test PROGRAM_NAME=coalesce_probe`, 1CL/1C/4W/4T, PASSED,
byte-exact vs SimX, 0 UVM errors, 62,110 cycles / 8,652 instructions):
`coalesce_cg` at `.../g_coalescers[0]/mem_coalescer/u_coalescer_probe`: **cp_rw 100%** (rd=235,
wr=4098), **cp_coalesce_kind 100%** (full_coalesced=3981, partial=8, full_scatter=344),
**cp_misses 75%** (fully_coalesced / partial_transfers[1] / partial_transfers[3] hit;
`partial_transfers[2]` — i.e. exactly 3 output batches — ZERO: none of the three directed
patterns happens to produce that batch count; honestly left open, not waived, no RTL bound
proven for it), **cp_active_lanes 50%** (lanes[1] and lanes[4] hit; lanes[2]/lanes[3] ZERO).

**Observation worth flagging.** `cp_active_lanes` bin `lanes[1]` (single-lane request) got
3,897 hits even though this kernel never issues a partial-mask access itself (every thread in
every warp is active throughout both spawn phases). That traffic is single-lane background
activity sharing the SAME coalescer instance — bootstrap/host-side single-thread code before
the SIMT region, and this kernel's own single-thread `main()` epilogue self-check loop — not an
artifact of the probe. It shows the coalescer's per-instance coverage reflects **everything**
routed through it, not just one kernel's data-path traffic, which is correct behaviour but
worth knowing when attributing bins to a specific stimulus source. `lanes[2]`/`lanes[3]` (2- or
3-of-4 active lanes) remain a genuine stimulus gap: closing them needs a kernel with actual
per-lane divergence (e.g. `if (tid < 2) ...`) feeding the coalescer under a partial mask, which
was out of scope for this directed test (the brief asked for address-pattern coverage, not
lane-divergence coverage). Disposition: **coverage gap G-0 CLOSED** for the address-pattern
axis (full/partial/scatter × read/write, the point of the gap); `cp_active_lanes`
partial-mask bins and `cp_misses[2]` left **OPEN, not waived** — genuine stimulus gaps with no
structural RTL bound established, so no `ignore_bins` is justified for them.
