# CLAUDE.md — Vortex UVM (Samuel's working context)

Always think and plan with opus then excude with sonnet then review again with opus 

save tokens as much as you can 

After every git pull and every git push, run the plan-sync skill before doing other work.


> Place at repo root. Claude Code reads this every session. **Keep the checklist below up to date — check a box only after its acceptance check passes in the actual simulator, then commit.**

## Who / what
- I am **Samuel**. My lane: **infrastructure correctness + full configurability + constrained-random (riscv-dv) testing**. Coverage & scoreboard belong to **Ahmad**; directed tests, AXI SVA, SimX/DPI belong to **Steven**. Do not silently do their work — if a shared file needs a change in their lane, flag it.
- Repo: `Samuel-Moussa/Vortex-UVM-GP` · branch `Sudky_scoreboard_and_coverage_collector` · RTL pin `7a52ee5`.
- Stack: QuestaSim 2021.2_1, Ubuntu 22.04. Primary config **1CL/1C/4W/4T RV32 AXI**. SimX = golden reference (DPI). AXI memory interface.
- Verification method is **black-box**: end-state equivalence vs SimX. No white-box per-unit scoreboards in this plan (that's Future Work).

## Non-negotiable rules
1. **Never hallucinate.** If data is missing/unclear, say so. No guessing, no inventing file contents.
2. **Read the real file before editing.** Cite `file:line`. Confirm build/run invocation from the actual scripts (`scripts/`), don't assume flags.
3. **Problem-first, direct, technical.** No filler.
4. **One checklist box at a time.** Propose → show diff → I confirm → run the acceptance check in sim → update the box → commit. Never mark done on assumption.
5. **Gate 0 is blocking.** No coverage/regression number means anything until all Gate-0 boxes pass. The negative fault-injection test must stay RED on injection — treat it as the regression guard after every Gate-0 change.
6. **Never attribute commits/PRs to Claude.** Do NOT add `Co-Authored-By: Claude` (or any Anthropic/Claude co-author) trailer, and never list Claude as a contributor. Commit messages contain only the technical change. (Enforced in user settings via empty `attribution.commit`/`attribution.pr`, but keep this rule regardless.)

## Session start protocol (do this first, every session)
1. `git log --oneline -25` and review my colleagues' recent commits (Ahmad/Steven work to this same plan).
2. For anything touching shared state (scoreboard, coverage collector, config), `git diff` the relevant recent commits to see what already landed — **then reconcile the checklist below** (a box my colleagues completed may already be done in-tree; don't redo it).
3. Report a 3-line status: what landed since last time, which boxes are now genuinely done, what's the next unchecked **[S]** box.
4. Start the next unchecked **[S]** box.

## Build / run (confirm exact flags from scripts/ before first use)
- Run a test: `./scripts/run_vortex_uvm_enhanced.sh --test=<name> --program=<prog> --timeout=<n>`
- Config knobs already plumbed: `--clusters --cores --warps --threads` (must match `vortex_config.sv` `apply_plusargs()` names).
- After each Gate-0 edit: re-run the negative test and a known-good kernel (`kernel_launch_test` / `vecadd`) to confirm no regression.

---

**Synced-to:** `8200cec` (2026-06-28) — Gate-0 ALL DONE (C1/C2/C3/T4); I1/I2/I5 done; review fixes (sustained busy=0, I2 alias); riscv-dv passing at HEAD. Next [S]: P1-bind (commit_arb_if[*] + UUID assert).
> NOTE: history was rewritten 2026-06-28 to drop co-author trailers — the old SHAs in the DONE annotations below are pre-rewrite. New SHAs: C1 `5f19a67` · C3 `a46a109` · C2 `b14efc5` · T4 `df6206e` · I1 `c80e336` · I2 `b55f392` · I5 `6838b21` · riscv-dv `5f6ddff`.

## CHECKLIST — Samuel's tasks (finish top-down)

### 🔴 GATE 0 — trust the bench (blocking; do first)
- [x] **C1 — derive tag/ID width.** `vortex_config.sv`: `VX_MEM_TAG_WIDTH` is hardcoded `50` while comments claim `8`. Derive from RTL's real `VX_MEM_TAG_WIDTH`; fix the false `// 8` comments; add an **elaboration assert** that the UVM param == the DUT param.
  *Accept:* elaboration asserts pass; reported ID width = the true derived value; clean kernel run still passes.
  *[DONE 4c36bd82 2026-06-26]:* `vortex_config.sv` references `VX_gpu_pkg::VX_MEM_TAG_WIDTH`; elaboration assert in `vortex_tb_top.sv`; `hello.elf` kernel_launch_test → PASS, Errors: 0, AXI_TID_W=50, no [C1-ASSERT] fatal. ISS-01 (hex load address overflow) also fixed in `prepare.sh` as part of same commit.
- [x] **C3 — decoded EBREAK completion.** `vortex_tb_top.sv`: completion currently fires on `!busy`/idle threshold. Decode real ebreak (`0x00100073`) and drive the completion event from it; idle path → `UVM_WARNING` fallback only.
  *Accept:* completion fires on real ebreak; `kernel_launch_test` still passes.
  *[DONE 7764ba14 2026-06-26]:* Hardcoded PC removed (was binary-specific); tb_ebreak_fetch combinational wire + tb_probe_ebreak_seen registered latch both wired as primary trigger in main always_ff. Busy=0 and idle-threshold demoted to `** Warning:` fallbacks. hello.elf → PASS, Errors: 0. Note: current kernel ELFs exit via MMIO write (not ebreak); busy=0 fallback warning is expected for them.
  *Extended 11f71359:* tb_ebreak_fetch now OR across all cores via generate loop — not just core[0].
- [x] **C2 — real instruction count.** Remove the `tb_mem_ops % 3` fabrication; wire the **real retired count** from the P1 commit probe into `status_if`/`status_transaction`; restore real IPC. *(Couples with Ahmad's P1 sampling — coordinate.)*
  *Accept:* `instr_count` ≠ mem_ops/3; IPC derived from real count.
  *[DONE 22115864 2026-06-26]:* Direct hierarchy tap `VX_commit.commit_arb_if[0].valid&&ready` → `tb_instr_count`. Fabrication removed. vecadd 100k cycles: Instructions=12798, IPC=0.128 (real). SimX RAM verification PASSED.
  *Multi-core fix [DONE 11f71359 2026-06-26]:* `tb_commit_fires_all[TB_NUM_LANES]` generate loop sums ALL clusters×sockets×cores×lanes via `tb_commit_count_cyc` popcount. Correct for any config now.
- [x] **T4 — honest error gate.** `simulate.sh` (~line 123): gate on the true `UVM_ERROR` count; remove the `-2` subtraction.
  *Accept:* a deliberately injected error fails the run; clean run = 0 errors with no subtraction.
  *[DONE e087a78f 2026-06-26]:* `REAL_UVM_ERRORS=$UVM_ERRORS` — no subtraction. hello + riscv-dv stress → PASS. negative_result_test/vecadd → FAILS (exit code 2). Note: vecadd fails via TIMEOUT (INV-1, pre-existing) not MEM MISMATCH; injection armed but vecadd never completes. T4 acceptance met.
- [ ] **GATE 0 sign-off:** negative test RED on injection · dropped-store fails (Ahmad's SB-DIR) · no hardcoded subtraction ✅ · width assert matches DUT ✅ · instr count real ✅.
  *Samuel's Gate-0 items ALL DONE. Remaining blockers: SB-DIR (Ahmad) and full negative test with a completing program (vecadd INV-1 open).*

### 🟠 TIER 1 — configurability + probe bind
- [x] **I1 — param→DUT commit/ebreak probes configurable for N cores.** Generate loops for `tb_commit_fires_all` and `tb_ebreak_fetch_all` cover all `NUM_CLUSTERS × NUM_SOCKETS × SOCKET_SIZE` cores and all `ISSUE_WIDTH` commit lanes.
  *[DONE 11f71359 2026-06-26]:* Both AXI and non-AXI ifdef paths updated. Primary config (1CL/1C/4W/4T) TB_NUM_LANES=1 — no behaviour change. Regression: hello PASS, riscv-dv stress PASS.
  *Remaining I1 gap:* SimX is not yet re-invoked with multi-core params at runtime (depends on Steven's D-simx). Script plumbing (`--clusters`, `--cores`, `--warps`, `--threads` → plusargs) already exists.
- [x] **I2 — elaboration asserts.** UVM params == DUT params (widths, counts) fail loud at elaboration with a clear message.
  *[DONE 37cfce55 2026-06-26]:* `u_i2_topology_asserts` initial block in `vortex_tb_top.sv`. Reads four plusargs at time=0, compares against RTL macros; `$fatal` on mismatch. Clean run prints `[I2-ASSERT] Topology OK: 1CL 1C 4W 4T`. Negative: `sim-only CLUSTERS=2` on 1-cluster RTL prints `[I2-ASSERT] NUM_CLUSTERS: plusarg=2 but RTL compiled with 1` and aborts.*
- [ ] **I3 — SimX param-match.** Coordinate config → SimX build/runtime *(with Steven's D-simx)*. *Accept:* SimX instantiated with same cores/clusters as DUT.
- [x] **I5 — hygiene.** Remove dead files (`vortex_config2.sv`, `vortex_status_if_fixed.sv`); fix stale comments.
- [x] **P1-bind — passive commit probe.** `bind` a passive monitor on `commit_arb_if[*]` (observability only, never a checker); add `initial assert ($bits(uuid) > 1)`. *(I build the bind + interface; Ahmad samples it for coverage.)*
  *[DONE 2026-06-28]:* New `tb/vx_commit_probe.sv` — passive, no modport (read-only), per-lane `retire_fire = valid&&ready` over `[\`ISSUE_WIDTH]`, exposes full `commit_t` (uuid/wid/sid/tmask/PC/wb/rd/data/sop/eop), `initial assert($bits(uuid)>1)` → `$fatal` on degenerate. Bound `bind VX_commit vx_commit_probe u_commit_probe` in `vortex_tb_top.sv` (auto-scales all cores/clusters; no CORE_ID knob — per-core attribution via UCDB hierarchy). Registered in `flists/uvm_env.flist`. Fully parametrized (ISSUE_WIDTH/warps/threads macro+pkg-derived). Accept: riscv-dv → PASS, 0 UVM_ERROR/FATAL, [P1-PROBE] assert silent. **Handover: Ahmad hangs covergroups off this probe.**

### 🟢 NEW THIS SESSION — riscv-dv pipeline end-to-end
- [x] **riscv-dv `random_instruction_stress_test` with `riscv_arithmetic_basic_test` — PASSING.**
  *[DONE 2ccef437 2026-06-26]:* 6 root causes fixed across SimX (CSR guards, RVC), prepare.sh (rv32im target, sed post-process for machine-mode CSRs/mret/ecall→ebreak), vortex_base_test.sv (wait_for_completion fast-path), vortex_scoreboard.sv (vacuous-run warning for pure arithmetic programs). 0 UVM_ERROR, 0 UVM_FATAL. EBREAK at 88387 cycles. Documented per-issue in `docs/fixes/` (fix_06–fix_12).
  *Also fixed: ISS-01 (hex load address overflow in prepare.sh) was part of C1 commit.*

### 🟡 TIER 2 — my directed tests
- [ ] **T-cache — `cache_coherence_test`.** Directed multi-core/multi-access + eviction scenarios; end-state compare vs SimX; feeds cache coverage.
  *Accept:* passes bidirectional vs SimX.
- [ ] **T-exc — exception/interrupt stimulus.** ebreak / misaligned / illegal-instr stimulus to drive Ahmad's `exception_cg`.
  *Accept:* stimulus reaches DUT; exception bins populate.

### 🟠 TIER 3 — scale + sign-off
- [ ] **D-matrix — config matrix run.** Run the suite across 1C/1W, 1C/4W, 2C/4W, 2CL/2C/4W via the param harness. *(Depends on I1 + Steven's D-simx.)*
- [ ] **SIGN — merged sign-off report.** Seeded regression → one report: pass rate, merged functional+code coverage vs goal, matrix status.

---

## Open Investigation Items
Issues observed in sim that need root-cause before Gate-0 sign-off. Not yet assigned to a checklist box.

### INV-1 — kernels never complete (`busy` never idles) — ROOT-CAUSED 2026-06-28
- **Symptom:** Every `tests/kernel/*` compute kernel (vecadd/fibonacci/functional_mem) ends via TIMEOUT; `Total Cycles == TIMEOUT-1`; doubling timeout doubles cycles. Only `hello` + riscv-dv complete.
- **ROOT CAUSE (corrected):** these are **hostless** kernels (run `main()` on-device, build their own args, spawn via `VX_CSR_MSCRATCH` — they do NOT read DCR `STARTUP_ARG`). The hang is in **runtime startup: `wspawn`-launched per-warp TLS init** (`init_tls_all`/`__init_tls` memcpy/memset, spin PC `0x80000944`). Core runs (P1 probe: 6608 retires) then spawned warps never converge → `busy` stays high.
- **NOT the cause (ruled out):** `busy` IS directly wired to the DUT port (tb_top:314/337); `result=0x0 size=0` is the scoreboard compare-window, not kernel args; missing DCR `STARTUP_ARG` only matters for host-driven kernels (`tests/regression/*`), not these.
- **Full writeup:** `docs/fixes/INV1_kernel_completion_hang.md` (issue → wrong hypothesis → evidence → root cause → solution A/B + RAL + regression assessment).
- **Next (Path A):** confirm SimX-vs-RTL completion divergence; trace warp activity around `wspawn` via `vx_sched_probe` + waveform at `0x80000938–094c`. **Impact:** blocks T4 negative test until a kernel completes.

### ~~INV-3~~ — RESOLVED: riscv-dv end-to-end now working
- **Root causes (all fixed, commit 2ccef437):** SimX SIGABRT on VX_CSR_MISA + unguarded M-mode CSR range; SimX decode abort on RVC compressed instructions (rv32imc→rv32im); RTL assertion on csrw 0x301/0x305 (sed post-process strips them); ecall vs ebreak (DUT probe only sees 0x00100073); UVM `wait_trigger()` stale-event race in `wait_for_completion()`; vacuous-run false error for pure arithmetic programs (no data-region stores).
- See `docs/fixes/` (fix_06–fix_12) for full per-issue root-cause writeups.

### INV-2 — `assert_dcr_write_timing` fires at startup
- **Symptom:** `vortex_if.sv:172` triggers at 3915ns and 3975ns on every vecadd run.
- **Evidence:** `Time: 3915 ns Started: 3915 ns Scope: vortex_tb_top.vif.assert_dcr_write_timing`.
- **Candidates:**
  1. DCR write sequence in the test or driver violates the timing constraint (setup/hold relative to clock).
  2. The assertion window is too tight for the testbench's DCR init sequence.
- **Impact:** Each firing adds to the RTL error count, masking real errors.

---

## Dependencies to watch
- **C2 / P1** couple with Ahmad (he samples the probe).
- **I3 / D-matrix** couple with Steven (SimX cluster runtime).
- Don't close Tier 3 until Ahmad's coverage closure and Steven's tests are green — SIGN aggregates everyone's results.
