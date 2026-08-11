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
  exactly the class `compare_all_written` skips (`vortex_scoreboard.sv:647-656`: region
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
  `mem_addr[]` open-array out-param; `lockstep_scoreboard.sv` pops it and compares a
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
  `Vortex/sim/simx/cosim_loadfeed.h`, `emulator.cpp`, `execute.cpp`; `lockstep_scoreboard.sv`;
  `vortex_scoreboard.sv` (deferred end-state). Full writeup: `docs/investigations/SimX_2CL_no_fence_divergence.md`.
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
  (1CL/2CL small programs). Fix is `10 ** (...)` per the original intent. Left as an
  upstream-reportable RTL observation; no waiver needed (assertion category unaffected in
  our banks).

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
  `vortex_uvm_env/uvm_env/lockstep_scoreboard.sv:16` states *"DOMAIN: writeback retirements
  only (wb==1). Non-wb instructions (stores, branches…)"*, and the filter is enforced at
  `vortex_uvm_env/tb/vx_commit_probe.sv:99` (`retire_fire && commit_arb_if[i].data.wb`) and
  again on the golden side at `lockstep_scoreboard.sv:311` (`if (wb == 0) continue;`).
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
    (`vortex_uvm_env/uvm_env/vortex_scoreboard.sv`, byte-valid gate in `compare_all_written`).
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
