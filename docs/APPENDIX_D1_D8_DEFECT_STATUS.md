# D-1 through D-8 — current status, checked against the code

Every item below is grounded in a file, a `git log`/`git show`, or a real simulation run
executed this session. `VERIFICATION_PLAN_v1.md` itself remains unreachable from here (it
is a Claude-project doc, not a repo file) — everything below is independent verification
against the code, not a diff against that document's text.

---

## D-1 — likely the SAME defect, found in git history, and FIXED

`git log --all --oneline -- vortex_uvm_env/tb/vx_instr_probe.sv` (the file's pre-migration
path) returns its full history in the outer repo — 7 commits, oldest `04bb288`. `git show
04bb288 -- vortex_uvm_env/tb/vx_instr_probe.sv` shows the file's header, **at its very
first commit**, already documenting a prior defect it replaces:

> *"Previous revision used ONE covergroup type carrying every class's op coverpoint,
> gated by `iff (ex_class==N)`. That meant each of the 5 bound instances declared a
> `cp_class` that could only ever reach 1 bin. Those [bins are] structurally-unreachable
> … This revision uses ONE covergroup TYPE PER CLASS."*

This is not a word-for-word match for "BEQ and MUL score as add," but it is the same
**defect family**: a single shared covergroup gated by a runtime class check
(`iff (ex_class==N)`) rather than true structural separation — exactly the mechanism that
would let two different instruction classes collide in one coverpoint. The fix (one
covergroup **type** per class, sampled only from that class's own dispatch interface) is
what `tb/vx_instr_probe.sv` contains today, confirmed in the last round.

**I cannot produce the literal original D-1 sentence to diff against — that document is
outside this repo.** But this is strong, dated, citable evidence: **the class-selector
defect this file's own header describes was fixed before its first commit in this repo's
tracked history**, and no commit since has reverted it. Slide wording I'd support:
*"A class-selector coverage defect of this type was found and fixed (see `tb/vx_instr_probe.sv`
header, commit `04bb288`); current per-class instrumentation is structurally immune to it."*
Do not cite it as "D-1, closed" without the original document to confirm it's the same
finding — cite the mechanism and the commit instead.

---

## D-2 — CONFIRMED STILL TRUE, and still open

`uvm_env/vortex_coverage_collector.svh:160`: `cp_addr_align` lives inside
`mem_operation_cg`, exactly as claimed. The construction guard, `:727-734`:

```systemverilog
if (!$value$plusargs("USE_AXI_WRAPPER=%d", use_axi))
    use_axi = 1;                      // default to AXI
...
if (use_axi) axi_transaction_cg = new();
else         mem_operation_cg   = new();
```

**`mem_operation_cg` — and therefore `cp_addr_align` — is only constructed when
`USE_AXI_WRAPPER=0`.** The comment directly above it (`:730-732`) confirms this is
deliberate: *"Construct ONLY the active data-interface group, so the idle one never lands
in this run's UCDB at 0%."* Every regressed run in the project uses `--interface=axi`
(confirmed across every `config.txt` seen this session) — so `mem_operation_cg` has never
been constructed in any banked run, and `cp_addr_align` has never sampled once. **D-2 is
real and still open.**

---

## D-3 — CONFIRMED TRUE AS WRITTEN, but transparently a smoke test, and never staged

`uvm_tests/vortex_sanity_test.svh:68-77`:
```systemverilog
virtual task wait_for_completion();
    `uvm_info(get_type_name(), "Skipping EBREAK check (sanity test)", UVM_MEDIUM)
endtask
virtual function void check_results();
    test_passed = 1'b1;
    `uvm_info(get_type_name(), "✓ Sanity test PASSED - testbench is alive!", UVM_LOW)
endfunction
```
Confirmed: it overrides completion-wait to a no-op and always sets `test_passed = 1`.

**But this is not hidden.** The test's own banner literally prints *"SANITY TEST — Just
Survive"* and the pass message says *"testbench is alive."* It is explicitly an
infrastructure smoke test (compiles, elaborates, runs 100 cycles without crashing), not a
functional test dressed up as one. `grep -n vortex_sanity_test scripts/run_suite.sh` →
**no hits — it is never invoked by the suite**, so it does not inflate the 50/50 pass count
or any coverage number. Slide-safe wording: *"a deliberately unconditional smoke test,
correctly excluded from the regression."*

---

## D-4 — CONFIRMED TRUE, and this one matters

`uvm_tests/random_instruction_stress_test.svh:193-233` — the full `check_results()`:
```
Gate 1: bytes_loaded > 0
Gate 2: vif.status_if.ebreak_detected
Gate 3: UVM_ERROR count == 0
```
Three real gates — this is not vacuous in the sense of "always passes." But compare
`kernel_launch_test.svh:250-251`:
```systemverilog
if (env.m_scoreboard.num_comparisons == 0 &&
    env.m_scoreboard.num_console_checks == 0) begin
    // FAIL — nothing was actually compared
```
**`kernel_launch_test` has a genuine non-vacuity gate on the scoreboard's comparison
count; `random_instruction_stress_test` has no such check anywhere in its file.** It can
report PASS as long as the program loaded, reached EBREAK, and produced zero UVM_ERRORs —
even if the scoreboard made zero real DUT-vs-SimX comparisons. **This is confirmed still
open, and it is the test class that runs all 9 riscv-dv profiles** — meaning riscv-dv PASS
verdicts rest on liveness + zero-error, not on a confirmed non-zero compare count.

This does not contradict the earlier project finding that "A3 is closed, the riscv-dv
UNVERIFIABLE bucket was measured empty" — that was established by manually checking
`data_compared` counts in the logs, not by an automated gate in the test itself. D-4 says
the automation to make that check *itself* isn't there; it does not mean the historical
manual check was wrong.

---

## D-5 — CONFIRMED TRUE, and this is architecture, not a defect

`grep -n 'get_next_item\|seq_item_port' uvm_env/agents/{axi_agent/axi_driver,mem_agent/mem_driver}.svh`
→ zero hits in both files, confirmed. Both drivers instead run `forever @(posedge
vif.clk)` loops (`axi_driver.svh:157,173,193,237,274`) reacting directly to bus signals.

**This is the correct pattern for what these UVCs are.** They are slave-side memory
**responders** — the DUT is the AXI/MEM master, so there is no upstream sequence to pull
transactions from; the driver's job is to react to the DUT's requests on the bus, not
originate its own. This matches the project's own prior description of these agents as
"active responders (slaves to DUT master)." Flag it as an architectural fact for the
slide, not list it alongside D-1/D-2/D-4 as an open defect — it would be a defect only if
these agents were meant to be active initiators, and they are not.

---

## D-6 — CONFIRMED TRUE, and it is a real, currently-inert bug

`uvm_env/ref_model/Makefile:74-79`:
```makefile
ifeq ($(XLEN),64)
ARCH_CONFIGS += -DXLEN_64
else
ARCH_CONFIGS += -DXLEN_32
endif
...
ARCH_CONFIGS += -DXLEN_32          # line 83 — appended unconditionally, outside the if/else
```
Confirmed exactly as claimed: if `XLEN=64` is ever requested, the golden model's build
gets **both** `-DXLEN_64` and `-DXLEN_32` defined simultaneously — a genuine latent defect,
the same class as the already-documented `NUM_CLUSTERS` redefinition hazard in the SimX
DPI wrapper (I3's "latent hazard" note).

**Currently inert:** `grep -rn 'XLEN=64\|XLEN_64' scripts/*.sh Makefile` across the whole
`uvmsim` tree → zero hits. **`XLEN=64` has never been invoked anywhere in this project** —
every regressed run is RV32. So this cannot have corrupted any banked result to date, but
it would silently corrupt a future 64-bit build. Worth one line on the slide as a known,
scoped, currently-dormant defect — do not present it as affecting any current number.

---

## D-7 — CONFIRMED TRUE, and it is WORSE than described: the path is now stale

`scripts/gen_coverage_exclude.sh:42-43`:
```bash
RTL="/home/samuel_ubuntu22/Vortex_UVM_GP/Vortex/hw/rtl"
TB="/home/samuel_ubuntu22/Vortex_UVM_GP/vortex_uvm_env/tb"
```
Both are hardcoded absolute paths, confirmed not portable — a straightforward finding.

**New, more serious finding this session: `${TB}` is used in ~40+ `-srcfile` exclusion
lines throughout the script, and the directory it points at no longer exists.**
`vortex_uvm_env/tb/` was moved to `Vortex/sim/uvmsim/tb/` on 2026-08-20 (the CLAUDE.md
resume block documents this migration explicitly). `ls -d vortex_uvm_env/tb` → **does not
exist.**

**The banked headline results (94.72%/94.55%, dated 2026-08-16) predate this migration and
are unaffected** — `TB` pointed at a real directory when those banks were generated.
**But if `gen_coverage_exclude.sh` were run today, every `-srcfile ${TB}/vortex_axi_if.sv`
line would reference a path that does not exist**, which would very likely make Questa's
`coverage exclude -srcfile` silently fail to match anything (I have not re-run the
generator to confirm the exact failure mode — say so rather than guess). If it does fail
silently, the merge's own "hits-invariant" gate (documented as catching exactly this class
of defect before) should catch it on the next fresh bank — but that has not been tested
since the migration. **Recommend fixing the two paths before anyone regenerates a bank**,
not just before the next presentation.

---

## D-8 — REFUTED, and now proven live end-to-end (I ran it this session)

Full trace, all three files:
```
uvm_env/lockstep_pkg.sv:59   comment: "Negative-test hook (+LOCKSTEP_INJECT)..."
uvm_env/lockstep_pkg.sv:62   bit inject_en = 1'b0;
tb/vx_commit_probe.sv:60     initial if ($test$plusargs("LOCKSTEP_INJECT")) lockstep_pkg::inject_en = 1'b1;
tb/vx_commit_probe.sv:116-119
    if (lockstep_pkg::inject_en && !lockstep_pkg::inject_done) begin
        rec.data[0] = rec.data[0] ^ 64'h1;
        lockstep_pkg::inject_done = 1'b1;
        $display("[LOCKSTEP-INJECT %m] flipped bit0 of uuid=%0h wid=%0d lane0", ...);
    end
```
**The claim that the scoreboard "never references it" is imprecise.** The scoreboard
doesn't need to check `inject_en` directly — the injection corrupts the DUT-side record
*before* it's pushed into the compare stream, so it's caught by the scoreboard's ordinary
per-field mismatch counter, exactly the same mechanism that would catch a real DUT bug.
That is the architecturally correct design for this kind of guard (same pattern as
`+INJECT_FAULT`/`+DROP_STORE` in `vortex_scoreboard.svh`).

**But no stored log anywhere exercises `+LOCKSTEP_INJECT`** — `grep -rl 'LOCKSTEP-INJECT'
results/` found nothing before this session, so the wiring, while structurally sound by
inspection, had never been proven to fire. **I ran it:**
```
LOCKSTEP=1 EXTRA_PLUSARGS="+LOCKSTEP_INJECT" make sim TEST=kernel_launch_test \
  PROGRAM_NAME=vecadd_lite CLUSTERS=1 CORES=1 WARPS=4 THREADS=4 TIMEOUT=200000
```
```
[LOCKSTEP-INJECT ...commit_probe.g_commit_lanes[0]] flipped bit0 of uuid=0 wid=0 lane0
[LOCKSTEP]   compared pairs      : 1035
[LOCKSTEP]   matched             : 1034
[LOCKSTEP]   field_mismatch data : 1
*** TEST FAILED ***
UVM_ERROR :    2
```
**Exactly one injection, exactly one field mismatch, test correctly fails.** D-8 is
refuted — the guard is real, wired correctly, and now proven to fire live, with a stored
log to cite. **This makes it a fifth non-vacuity guard with direct evidence, on top of the
four already in the pack** — worth adding to the deck's guard count if you want it, though
the other four (`+INJECT_FAULT`, `+DROP_STORE`, `+DCR_RAL_INJECT`, plus this) already make
the point; I'd keep the headline at four and mention this as a fifth confirmed mechanism
in the appendix rather than complicate the main slide's count.

---

## Feature re-grade — 0 of 13 named areas gained a coverpoint

Searched for a coverpoint matching each of the 13 areas named as OPEN-with-no-coverage:
branch direction/taken, CSR address, `is_float`, FP `frm`/special values, LMEM bank
conflicts, MSHR occupancy, cache set/way/bank, cross-core behavior, operand-collector
conflicts, register hazards, trap cause. **All 13 searches returned zero matches** across
every `tb/*.sv` and `uvm_env/*.svh` file.

Two worth a specific note, since I checked their neighbourhoods directly rather than
trusting the keyword search alone:
- **M-extension ops (MUL/DIV/REM):** `alu_class_cg`'s `cp_alu_op` (`tb/vx_instr_probe.sv:108-121`)
  enumerates 14 named bins — none is `INST_ALU_MUL` or any div/rem opcode. Confirmed absent.
- **FP special values / rounding mode:** `fpu_class_cg`'s `cp_fpu_op` covers **opcode
  class** (fadd/fmul/fdiv/fsqrt/fcmp/fmisc — the session-9 fix) but has no coverpoint on
  `frm` or on operand values (NaN/Inf/denormal/±0). Confirmed absent — opcode coverage and
  data-value coverage are different axes, and only the first exists.

**Count for the slide: 0 changed, 18 still open** (assuming the doc's list of 18 is
otherwise accurate — I can't confirm the other 5 not named in your question without seeing
the full 18-item list).

---

## Exact regression count

```
$ cd Vortex/tests/regression && ls -d */ | wc -l
21
```
**21 directories total. 4 staged** (`basic diverge dogfood sgemm`, `run_suite.sh:293-296`).
**17 unused**: `conv3 cta demo dotproduct dropout fence io_addr madmax mstress printf relu
sgemm2 sgemm_tcu sgemv sort stencil3d vecadd`. (Earlier "14 other"/"13 further" phrasing in
my previous answer was informal counting from a partial list — 17 is the exact, counted
number.)

---

## Bottom line for slide 38 and the appendix

- **D-1**: cite the commit and the mechanism, not "closed" — the original document is
  unreachable, but the evidence strongly supports "found and fixed."
- **D-2, D-4, D-6, D-7 are real, confirmed, currently open** (D-6 and D-7 are dormant/latent
  — not affecting any current number, but real defects to disclose).
- **D-3 and D-5 are not defects** — D-3 is a transparent, unstaged smoke test; D-5 is
  correct architecture for a slave-responder UVC.
- **D-8 is refuted and now has a live proof run** — a genuine fifth injection guard,
  arguably stronger evidence than some already in the deck since it was proven this
  session with an exact 1-injection/1-mismatch count.
- **13 named OPEN features: 0 gained coverage.** State the count plainly; it's a clean,
  defensible negative result, not a gap in this answer.
- **Regression: 21 total, 4 staged, 17 unused** — exact, not approximate.
