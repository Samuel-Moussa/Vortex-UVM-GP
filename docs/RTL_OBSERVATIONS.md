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
- **Class:** OBSERVABILITY · **Disposition:** worked-around · **Found:** Phase A0 (2026-07-14)
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
  checks PC/rd/ordering), identified by SimX `fu_type==LSU`. A1 could add an
  LSU-writeback / regfile-write-port probe to observe load data directly.

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
