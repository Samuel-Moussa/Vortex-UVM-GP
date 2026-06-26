# CLAUDE.md — Vortex UVM (Samuel's working context)

Always think and plan with opus then excude with sonnet then review again with opus 

save tokens as much as you can 

After every git pull and every git push, run the plan-sync skill before doing other work.


> Place at repo root. Claude Code reads this every session. **Keep the checklist below up to date — check a box only after its acceptance check passes in the actual simulator, then commit.**

## Who / what
- I am **Samuel**. My lane: **infrastructure correctness + full configurability**. Coverage & scoreboard belong to **Ahmad**; directed/random tests, AXI SVA, SimX/DPI belong to **Steven**. Do not silently do their work — if a shared file needs a change in their lane, flag it.
- Repo: `Samuel-Moussa/Vortex-UVM-GP` · branch `Sudky_scoreboard_and_coverage_collector` · RTL pin `7a52ee5`.
- Stack: QuestaSim 2021.2_1, Ubuntu 22.04. Primary config **1CL/1C/4W/4T RV32 AXI**. SimX = golden reference (DPI). AXI memory interface.
- Verification method is **black-box**: end-state equivalence vs SimX. No white-box per-unit scoreboards in this plan (that's Future Work).

## Non-negotiable rules
1. **Never hallucinate.** If data is missing/unclear, say so. No guessing, no inventing file contents.
2. **Read the real file before editing.** Cite `file:line`. Confirm build/run invocation from the actual scripts (`scripts/`), don't assume flags.
3. **Problem-first, direct, technical.** No filler.
4. **One checklist box at a time.** Propose → show diff → I confirm → run the acceptance check in sim → update the box → commit. Never mark done on assumption.
5. **Gate 0 is blocking.** No coverage/regression number means anything until all Gate-0 boxes pass. The negative fault-injection test must stay RED on injection — treat it as the regression guard after every Gate-0 change.

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

**Synced-to:** `4c36bd82` (2026-06-26) — C1 + ISS-01 fixed, hello kernel PASS

## CHECKLIST — Samuel's tasks (finish top-down)

### 🔴 GATE 0 — trust the bench (blocking; do first)
- [x] **C1 — derive tag/ID width.** `vortex_config.sv`: `VX_MEM_TAG_WIDTH` is hardcoded `50` while comments claim `8`. Derive from RTL's real `VX_MEM_TAG_WIDTH`; fix the false `// 8` comments; add an **elaboration assert** that the UVM param == the DUT param.
  *Accept:* elaboration asserts pass; reported ID width = the true derived value; clean kernel run still passes.
  *[DONE 4c36bd82 2026-06-26]:* `vortex_config.sv` references `VX_gpu_pkg::VX_MEM_TAG_WIDTH`; elaboration assert in `vortex_tb_top.sv`; `hello.elf` kernel_launch_test → PASS, Errors: 0, AXI_TID_W=50, no [C1-ASSERT] fatal. ISS-01 (hex load address overflow) also fixed in `prepare.sh` as part of same commit.
- [x] **C3 — decoded EBREAK completion.** `vortex_tb_top.sv`: completion currently fires on `!busy`/idle threshold. Decode real ebreak (`0x00100073`) and drive the completion event from it; idle path → `UVM_WARNING` fallback only.
  *Accept:* completion fires on real ebreak; `kernel_launch_test` still passes.
  *[DONE 7764ba14 2026-06-26]:* Hardcoded PC removed (was binary-specific); tb_ebreak_fetch combinational wire + tb_probe_ebreak_seen registered latch both wired as primary trigger in main always_ff. Busy=0 and idle-threshold demoted to `** Warning:` fallbacks. hello.elf → PASS, Errors: 0. Note: current kernel ELFs exit via MMIO write (not ebreak); busy=0 fallback warning is expected for them.
- [x] **C2 — real instruction count.** Remove the `tb_mem_ops % 3` fabrication; wire the **real retired count** from the P1 commit probe into `status_if`/`status_transaction`; restore real IPC. *(Couples with Ahmad's P1 sampling — coordinate.)*
  *Accept:* `instr_count` ≠ mem_ops/3; IPC derived from real count.
  *[DONE pending commit 2026-06-26]:* Direct hierarchy tap `VX_commit.commit.commit_arb_if[0].valid&&ready` → `tb_commit_fire` → `tb_instr_count`. Fabrication removed. vecadd 100k cycles: Instructions=12798, IPC=0.128 (real, scales linearly). SimX RAM verification PASSED. P1-bind (commit probe module for Ahmad) remains a separate Tier-1 item.
  *Known limitation (multi-core):* Tap hardcoded to cluster[0]/core[0]/lane[0]. Under-counts by `NUM_CLUSTERS×NUM_CORES` for >1 core; misses lanes 1+ when `ISSUE_WIDTH>1` (NUM_WARPS>16). Correct for primary Gate-0 config (1CL/1C/4W/4T). Fix requires P1-bind generate loop.
- [ ] **T4 — honest error gate.** `simulate.sh` (~line 117): reclassify banner lines to `UVM_INFO`; gate on the true `UVM_ERROR` count; remove the `-2` subtraction.
  *Accept:* a deliberately injected error fails the run; clean run = 0 errors with no subtraction.
  *[sync 0d5bd080]:* OPEN — `simulate.sh:118` `-2` subtraction still present.
- [ ] **GATE 0 sign-off:** negative test RED on injection · dropped-store fails (Ahmad's SB-DIR) · no hardcoded subtraction · width assert matches DUT · instr count real.

### 🟠 TIER 1 — configurability + probe bind
- [ ] **I1 — param→DUT→SimX consistency.** Config's cores/clusters/warps/threads must reliably drive RTL elaboration **and** SimX; purge remaining hardcodes (script plumbing already exists).
  *Accept:* changing `--warps`/`--cores` changes both DUT and SimX; primary config runs clean.
- [ ] **I2 — elaboration asserts.** UVM params == DUT params (widths, counts) fail loud at elaboration with a clear message.
- [ ] **I3 — SimX param-match.** Coordinate config → SimX build/runtime *(with Steven's D-simx)*. *Accept:* SimX instantiated with same cores/clusters as DUT.
- [ ] **I5 — hygiene.** Remove dead files; fix the stale scoreboard header comment.
- [ ] **P1-bind — passive commit probe.** `bind` a passive monitor on `commit_arb_if[*]` (observability only, never a checker); add `initial assert ($bits(uuid) > 1)`. *(I build the bind + interface; Ahmad samples it for coverage + the C2 count.)*
  *[sync 0d5bd080]:* PARTIAL — `vx_instr_probe` bound on `VX_dispatch` and `vx_sched_probe` on `VX_schedule` (both in `vortex_tb_top.sv` lines 641-661). The specified `commit_arb_if[*]` bind is NOT present. UUID assert missing. IMPLEMENTED-UNVERIFIED on the dispatch/sched probes (no sim log).

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

### INV-1 — vecadd `busy` never goes low (completion blocked)
- **Symptom:** Every vecadd run ends via TIMEOUT, never via `busy=0` fallback or ebreak. `Total Cycles` always equals `TIMEOUT-1`. Doubling the timeout just doubles the cycle count — the program runs indefinitely.
- **Evidence:** `assert_busy_eventually_idles` fires at `Started: 3895ns + 100000ns window`. `** Error: TIMEOUT after N cycles!` is the only completion path.
- **Candidates:**
  1. `vif.status_if.busy` is not properly wired to the DUT `busy` output (check `vortex_if.sv` binding vs. DUT port).
  2. vecadd genuinely never halts — the kernel loop or MMIO exit sequence hangs in DUT.
  3. The `busy` signal stays high because a warp is stuck (X-prop, infinite loop, wrong hex load).
- **Impact:** Blocks all completion testing for vecadd; T4 negative-injection test also meaningless until completion is reliable.

### INV-3 — riscv-dv program termination incompatible with stress test Gate 2
- **Symptom:** `random_instruction_stress_test.sv` Gate 2 checks `vif.status_if.ebreak_detected`. riscv-dv generated programs exit via `write_tohost` + `j write_tohost` (infinite loop) — no `ebreak` is emitted. Gate 2 will always FAIL.
- **Root cause:** riscv-dv's `user_extension/user_init.s` is empty. The standard riscv-dv exit calls `_exit → write_tohost` (a trap-based convention). Vortex expects EBREAK or MMIO write to `0x00000088`.
- **Fix options (coordinate with Steven — riscv-dv tests are his lane):**
  1. Add `ebreak` to `~/riscv-dv/user_extension/user_init.s` as a post-exit epilogue.
  2. Change Gate 2 in `random_instruction_stress_test.sv` to check `busy=0` (fallback path) instead of `ebreak_detected`.
  3. Override the riscv-dv link script to add a Vortex MMIO exit before the `j _exit` infinite loop.
- **Impact:** stress test pipeline (prepare.sh + Makefile) is now fixed; test will compile and load. Blocked on this termination fix before it can PASS.

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
