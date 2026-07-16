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
- **Minor RTL note (debug-only):** the DUT's debug build (PC_BITS=XLEN, identity
  fullPC) retains an odd architectural PC after a jalr-to-odd-target; release
  (PC_BITS=XLEN-2, `>>2`/`<<2`) word-aligns it away. Benign (fetch aligns; low bits
  never reach an architectural result on this path) — a debug-representation artifact,
  not a silicon bug. Noted for completeness.

### OBS-009 (RESOLVED — not a DUT bug) — no_fence@2CL divergence is single-hart-test-in-multihart race
- **Class:** REF-MODEL/methodology (single-hart random test on N shared-memory cores) · **Disposition:** resolved — real-fix options pending (see investigation doc) · **Found:** Phase A1(d) (2026-07-15)
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
