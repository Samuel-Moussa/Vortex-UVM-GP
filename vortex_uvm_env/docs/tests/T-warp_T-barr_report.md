# Warp Scheduling and Barrier Synchronization Tests — Final Report

**Scope:** T-warp (`warp_scheduling_test`) and T-barr (`barrier_sync_test`)
**Owner:** Steven (tests + sequences + SVA + DPI scope)
**Date:** 2026-06-24
**RTL pin:** Vortex `7a52ee5`
**Configuration verified:** `clusters=1 cores=1 warps=4 threads=4`, AXI4 interface

---

## 1. Executive summary

Two new directed UVM tests were added to the Vortex UVM environment to exercise
the warp scheduler and the hardware barrier mechanism end-to-end against the
SimX golden reference. Both tests follow the project's black-box end-state
equivalence philosophy and reuse the existing `kernel_launch_test` framework.

During the first run the tests exposed a verdict gap in the equivalence-only
checking model: the scoreboard reported PASS while the kernel itself reported
internal failures. The DUT and SimX agreed on a wrong answer because both ran
the same buggy stimulus. The session resolved this by adding a second
correctness gate on top of the inherited equivalence gate, and by fixing two
real kernel-side races that the new gate exposed.

The final result is two clean, repeatable directed tests, plus a two-gate
checker pattern that every future directed test in this scope should follow.

---

## 2. Background — what are warp scheduling and barrier synchronization?

### 2.1 Vortex execution hierarchy

Vortex is a SIMT GPGPU. Its execution hierarchy is:

```
cluster → core → warp → thread
```

For the verified configuration:

- **1 cluster** containing 1 core.
- **1 core** with 4 hardware **warps** and 4 **threads per warp**.
- A **warp** is a group of threads that execute the same PC in lock-step under
  a per-warp **thread mask** (tmask). Up to 4 threads per warp execute the
  same instruction concurrently; threads can be individually masked off.
- The core's **warp scheduler** picks one ready warp per cycle and issues its
  next instruction. Warps make independent progress; the scheduler interleaves
  them to hide latency.

### 2.2 Warp scheduling — what is it?

The warp scheduler is the hardware unit that decides which warp issues next.
Its correctness requirements are:

1. **Fair dispatch.** Every spawned warp must eventually be scheduled. No warp
   can be starved.
2. **Mask correctness.** When the thread mask changes (`vx_tmc`,
   `vx_tmc_one`), only the unmasked threads in the warp must execute the
   following instructions.
3. **Divergence handling.** When threads within a warp take different paths
   of a conditional branch, the IPDOM (immediate post-dominator)
   reconvergence stack must serialize the paths and reconverge them at the
   correct join point. This is exposed via `vx_split` / `vx_join`.
4. **Warp spawning.** `vx_wspawn(N, fn)` activates `N` warps and starts them
   at function `fn`. Each spawned warp gets its own warp ID. The scheduler
   must place them into the ready queue and retire them when they call
   `vx_tmc(0)`.
5. **Per-warp context isolation.** Each warp has its own register file
   (including thread-local-storage `__thread` variables). Interleaved
   scheduling of multiple warps must not corrupt any warp's context.

The `warp_scheduling_test` (T-warp) drives one C++ kernel that exercises all
four of these properties in a single program.

### 2.3 Barrier synchronization — what is it?

A barrier is a hardware rendezvous: all participating warps must reach the
barrier before any of them is allowed to proceed past it. The Vortex barrier
intrinsic is:

```c
vx_barrier(int bar_id, int num_warps);
```

It blocks the calling warp until `num_warps` warps have called the same
barrier ID. Its correctness requirements are:

1. **Hold-until-all-arrive.** A warp that arrives first must wait for all
   slower warps. No early release.
2. **Atomic release.** When the last warp arrives, all blocked warps wake
   together on (or near) the same cycle.
3. **Rearming.** After a barrier release, the barrier returns to an unarmed
   state so the same `bar_id` can be reused immediately by the same warps.
4. **Phase ordering.** All memory operations issued by any warp before the
   barrier are observable by every warp after the barrier. (Barriers provide
   ordering between phases; they do **not** provide atomicity within a
   phase — see §6.2.)

The `barrier_sync_test` (T-barr) drives one C++ kernel that exercises all four
of these properties in a single program.

---

## 3. Verification philosophy — black-box end-state equivalence

The whole project uses one checker model: drive the DUT and SimX with the same
program, wait for completion, then compare end-state. End-state means:

- **Memory window.** A configured `[result_base_addr, result_base_addr +
  result_size_bytes)` region is byte-compared between DUT and SimX after
  completion.
- **Console stream.** All bytes the kernel emits via `vx_printf` (i.e.
  writes to the IO_COUT MMIO port) are captured on both sides and
  compared exactly.

There is no per-instruction co-simulation, no commit-log compare, and no
hardware probe is used as a second pass/fail gate. Probes exist only for
coverage/observability. The scoreboard is the sole equivalence judge.

This is intentional. End-state equivalence is the simplest and most
robust contract a verification environment can make: if the DUT and the
reference model are given the same input and produce the same final state,
they are functionally equivalent for that program. Equivalence-only checking
trades implementation visibility for stability against microarchitectural
churn.

The tradeoff is the **verdict gap** that this session uncovered (see §5).

---

## 4. Test design

### 4.1 Design choice — one shared SV class per scenario, two kernels

The planning question was: should warp-divergence and barrier-sync share a
single SV test class (re-used with different `PROGRAM_NAME`s), or should each
be a separate SV class with its own scenario-specific overrides?

**Decision:** separate SV classes. Reasons:

1. Each scenario has different minimum-config requirements that the test
   should enforce as fatal-and-refuse, not silently bump. Warp scheduling
   needs `warps >= 4 && threads >= 4`; barrier sync needs `warps >= 4`.
2. The two-gate check (added later — see §6) is the same for both, but each
   class still owns its own scenario banner, its own default ELF path, and
   its own minimum-config fatal messages. Reusing one SV class would have
   blurred those.
3. Both classes are short — ~110 lines each — so the duplication cost is
   low.

Both classes extend `kernel_launch_test` directly and override only the
methods they need to customize:

- `customize_config()` — set default program path, scenario result window,
  minimum-config fatals.
- `end_of_elaboration_phase()` — print scenario banner.
- `check_results()` — added later: extend the inherited equivalence gate
  with an absolute-correctness sentinel check (see §6.3).

Everything else — `load_program`, `run_test_stimulus`, the virtual sequence,
the scoreboard, the SimX bridge — is inherited unchanged. This is the house
style established by `kernel_launch_test.sv`; T-warp/T-barr respect it.

### 4.2 White-box stimulus, black-box checking

The C++ kernel programs are **white-box-informed stimulus**: their internal
structure is designed with knowledge of how the scheduler and barrier are
supposed to behave (e.g. unique per-warp sentinels, IPDOM-stack-aware nested
divergence, two-phase barrier accumulation). But the test classes never reach
into the DUT to verify intermediate state — they let the kernel write its
findings into a memory region (`RESULT_ADDR = 0x80010000`) and console
stream, then let the scoreboard compare those two streams against SimX.

The slogan: **the kernel encodes the scenario; the scoreboard judges the
outcome.**

### 4.3 T-warp: `warp_scheduling_test`

**Files:**

- SV: `uvm_tests/warp_scheduling_test.sv`
- C++ kernel: `vortex/tests/kernel/warp_test/warp_test.cpp`
- Kernel Makefile: `vortex/tests/kernel/warp_test/Makefile`

**Minimum config:** `num_warps >= 4`, `num_threads >= 4` (fatal-and-refuse
on violation).

**Four sub-tests in one binary:**

| # | Scenario | What it stresses | Pass criterion |
|---|---|---|---|
| T1 | Thread Mask Control (TMC) | `vx_tmc(full_mask)` activates all threads; each thread writes a position-unique sentinel `0x10 + tid` | `tmc_result[0..nt-1] == {0x10, 0x11, 0x12, 0x13}` |
| T2 | Nested divergence — Split/Join (IPDOM stack) | Two nested `vx_split` / `vx_join` levels across 4 threads; four paths each write a distinct sentinel `0x2A..0x2D` | `dvg_result == {0x2A, 0x2B, 0x2C, 0x2D}` |
| T3 | Warp Spawn + Scheduling | `vx_wspawn(N, fn)` activates 4 warps; each writes `0x30 + wid` then rendezvous on a barrier | `wspawn_result[0..nw-1] == {0x30, 0x31, 0x32, 0x33}` |
| T4 | Thread Local Storage (warp context isolation) | Each warp writes its `wid` into a `__thread` variable, reads it back, writes `0x40 + tls_var`; barrier before exit | `tls_result[0..nw-1] == {0x40, 0x41, 0x42, 0x43}` |

The kernel sums per-sub-test error counts and writes the total to
`*((volatile int*)0x80010000)`. Zero errors → magic `0x900DCAFE`. Any other
value → the literal error count.

### 4.4 T-barr: `barrier_sync_test`

**Files:**

- SV: `uvm_tests/barrier_sync_test.sv`
- C++ kernel: `vortex/tests/kernel/barrier_test/barrier_test.cpp`
- Kernel Makefile: `vortex/tests/kernel/barrier_test/Makefile`

**Minimum config:** `num_warps >= 4` (fatal-and-refuse on violation).

**Four sub-tests in one binary:**

| # | Scenario | What it stresses | Pass criterion |
|---|---|---|---|
| T1 | Basic barrier | Pre-barrier write → `vx_barrier` → post-barrier write; verifies all pre + post sentinels survive | `bar1_pre[w] == 0x10+w`, `bar1_post[w] == 0x20+w` |
| T2 | Staggered arrival | Warp `w` stalls `w×256` iterations before the barrier; after release, each warp reads all other warps' pre-barrier writes; missing entries prove early release | `bar2_data[w] == 0x30+w` for all w |
| T3 | Shared accumulator | Two-phase accumulation separated by a barrier; phase 1: each warp writes a unique contribution slot; phase 2: warp 0 reduces; second barrier; phase 3: all warps confirm `sum == nw*(nw+1)/2` | `accumulator == 10` and `bar3_confirm[w] == 0x50+w` |
| T4 | Double barrier (rearm) | Same `bar_id` used twice in sequence; a one-shot (non-rearming) barrier would deadlock on the second call (caught by UVM timeout) | `bar4_r1[w] == 0x60+w`, `bar4_r2[w] == 0x70+w` |

Same RESULT_ADDR sentinel convention as T-warp.

---

## 5. The problem — the verdict gap (first-run discovery)

### 5.1 What happened on the first run

First run, 2026-06-24 20:42 and 20:49:

- `run_204220_warp_scheduling_test` — scoreboard reported PASS. 26 memory
  comparisons passed, 1 console comparison passed. UVM_ERROR count: 0.
  Status: **PASSED**.
- `run_204952_barrier_sync_test` — scoreboard reported PASS. 33 memory
  comparisons passed, 1 console comparison passed. UVM_ERROR count: 0.
  Status: **PASSED**.

But the kernel's own `vx_printf` output (captured in the simulation log) told
a different story:

```
#0:   FAIL wspawn_result[1]=0x0 expected 0x31
#0:   FAIL wspawn_result[3]=0x0 expected 0x33
#0: warp_test: FAILED (2 errors)

#0:   FAIL accumulator=4 expected 10
#0:   FAIL bar3_confirm[0..3]=0xBAD00000..0xBAD00003
#0: barrier_test: FAILED (5 errors)
```

The kernel reported failure, the testbench reported pass.

### 5.2 Root cause

The inherited `check_results()` in `kernel_launch_test` enforces six gates:

1. `bytes_loaded > 0` (kernel ELF was loaded)
2. `vif.status_if.ebreak_detected` (kernel reached `ebreak`)
3. `launch_count == 1` (exactly one launch observed)
4. `completion_count == 1` (exactly one completion observed)
5. `num_comparisons || num_console_checks > 0` (at least one real check ran)
6. `num_mem_failed + num_console_failed == 0` (every check that ran passed)

Gate 6 is the equivalence gate: it says "every byte the DUT wrote that we
also have a SimX reference for matched." It does **not** say "the answer is
correct" — only that "the DUT and SimX agree."

Both runs hit the failure mode this gate cannot catch: the kernel had a
stimulus-side bug, and **both DUT and SimX executed the buggy kernel
identically**, producing the same wrong output. From the scoreboard's
perspective, every comparison matched. Gate 6 returned PASS.

### 5.3 Why this is the cleanest possible demonstration

This first run was accidentally the most pedagogically valuable failure mode
the project will probably ever see. It is the textbook case of
equivalence-only checking being insufficient:

> Two implementations that share a stimulus bug both produce the same wrong
> answer; equivalence holds; the scoreboard passes.

No synthetic example would be this convincing. It justifies the two-gate
design (§6) being applied across all four directed tests in this scope
(T-warp, T-barr, T-axi, T-fmem).

---

## 6. Solutions

Three problems were identified and three fixes applied. Two were real kernel
races; one was the verdict-gap hole.

### 6.1 Kernel race #1 — wspawn synchronization (T-warp, sub-test 3)

**Original code:**

```c
void wspawn_warp_func() {
    int wid = vx_warp_id();
    volatile int stall = 0;
    for (int i = 0; i < wid * 64; i++) stall++;  // BUG: warp 0 has zero stall
    wspawn_result[wid] = 0x30 + wid;
    vx_tmc(wid == 0);                            // warp 0 exits; others may not be done
}
```

**Failure mode:** `wid * 64` evaluates to zero for warp 0. Warp 0 skipped the
stall entirely and rushed past the write to the check loop in `test_wspawn()`
before warps 1 and 3 had finished writing `wspawn_result[1]` and
`wspawn_result[3]`. The check loop read uninitialized zeros for those slots
and reported `wspawn_result[1]=0x0` and `wspawn_result[3]=0x0`. Additionally,
the `volatile int stall` is a stack-local that clang likely eliminated even
when `wid != 0` — the original race-protection was never going to work.

**Fix:** remove the stall entirely (it was the wrong synchronization
mechanism anyway) and add a real rendezvous:

```c
volatile int wspawn_num_warps;

void wspawn_warp_func() {
    int wid = vx_warp_id();
    wspawn_result[wid] = 0x30 + wid;
    vx_barrier(0, wspawn_num_warps);    // rendezvous: all warps must reach this point
    vx_tmc(wid == 0);
}

int test_wspawn() {
    int nw = std::min(vx_num_warps(), 8);
    wspawn_num_warps = nw;              // make nw visible to spawned warps
    vx_wspawn(nw, wspawn_warp_func);
    wspawn_warp_func();                  // warp 0 entry
    ...
}
```

The same fix pattern was applied to T4 (TLS test), which had the same
exit-race shape (constant `for (i=0; i<32; i++) stall` was not a barrier).

### 6.2 Kernel race #2 — non-atomic accumulator (T-barr, sub-test 3)

**Original code:**

```c
volatile int bar3_accumulator;

void bar3_kernel() {
    int wid = vx_warp_id();
    bar3_accumulator += (wid + 1);   // BUG: non-atomic read-modify-write
    vx_barrier(BAR_ID, nw);
    int expected_sum = nw * (nw + 1) / 2;   // expects 1+2+3+4 = 10
    bar3_confirm[wid] = (bar3_accumulator == expected_sum) ? (0x50+wid) : 0xBAD00000+wid;
    vx_tmc(wid == 0);
}
```

**Failure mode:** `bar3_accumulator += (wid + 1)` is `load → add → store`.
Two warps that read `bar3_accumulator` simultaneously will both add to the
same stale value; one of the stores wins, the other is lost. The actual
measured result was `accumulator = 4 = 1 + 3` — only warps 0 and 2's updates
survived the race; warps 1 and 3 were stomped on.

**The conceptual point:** barriers enforce **ordering between phases**, not
**atomicity within a phase**. Putting the `+=` before a barrier does not make
the `+=` atomic. A barrier guarantees "all writes before me are visible to
all reads after me" — but if the writes themselves race, they were already
broken before the barrier got a chance to help.

**Fix:** make phase 1 race-free by giving each warp a unique slot, then do
the reduction in a single thread between two barriers:

```c
int bar3_contrib[8];   // unique slot per warp

void bar3_kernel() {
    int wid = vx_warp_id();
    int nw  = bar3_num_warps;

    bar3_contrib[wid] = wid + 1;          // phase 1: race-free unique-slot write
    vx_barrier(BAR_ID, nw);

    if (wid == 0) {                        // phase 2: single-thread reduction
        int sum = 0;
        for (int w = 0; w < nw; w++) sum += bar3_contrib[w];
        bar3_accumulator = sum;
    }
    vx_barrier(BAR_ID, nw);                // phase 3: make accumulator visible

    int expected_sum = nw * (nw + 1) / 2;
    bar3_confirm[wid] = (bar3_accumulator == expected_sum) ? (0x50+wid) : 0xBAD00000+wid;
    vx_tmc(wid == 0);
}
```

This is the canonical scatter-then-reduce pattern. It is race-free by
construction.

### 6.3 The verdict-gap fix — Gate 2 (absolute correctness sentinel)

Adding the kernel-race fixes alone would not have been enough. The real
hole was the checker: an equivalence gate cannot catch a stimulus-side
common-mode failure. The fix is to add a second gate that the kernel itself
seeds — an **absolute-correctness sentinel**.

The convention: every directed kernel in this scope writes
`0x900DCAFE` to a known address (`RESULT_ADDR = 0x80010000`) **if and only
if** every internal sub-test passed. Any other value (typically the literal
error count) means the kernel failed at least one sub-test.

The SV-side override calls `super.check_results()` first (Gate 1 —
DUT==SimX equivalence) and then peeks the sentinel out of the shared
`mem_model` (Gate 2 — absolute correctness):

```systemverilog
virtual function void check_results();
    mem_model mem;
    bit [31:0] sentinel;

    super.check_results();              // Gate 1
    if (!test_passed) return;           // don't pile errors if Gate 1 already failed

    void'(uvm_config_db#(mem_model)::get(null, "*", "mem_model", mem));
    sentinel = mem.read_word(64'h0000_0000_8001_0000);
    if (sentinel !== 32'h900DCAFE) begin
        `uvm_error(get_type_name(),
            $sformatf("FAIL — kernel reported errors: RESULT_ADDR=0x80010000=0x%08h (expected 0x900DCAFE); DUT==SimX equivalence held but the kernel itself failed",
                sentinel))
        test_passed = 0;
    end else begin
        `uvm_info(get_type_name(),
            "PASS — RESULT_ADDR=0x900DCAFE: kernel success sentinel confirmed",
            UVM_LOW)
    end
endfunction
```

Twelve lines per test class, no infrastructure changes, no scoreboard edits.
The `mem_model` was already shared by `kernel_launch_test.load_program()` via
the same `uvm_config_db` lookup; we reused that handle on the read side.

---

## 7. Evidence — three runs tell the story

Three runs together demonstrate the verdict gap and its closure. All three
ran in the same configuration: `clusters=1 cores=1 warps=4 threads=4`, AXI4
interface, timeout 10,000,000 cycles.

### Run 1 — buggy kernel, original equivalence-only checker

`results/20260624/run_204220_warp_scheduling_test/` and
`results/20260624/run_204952_barrier_sync_test/`

- Gate 1 (DUT==SimX equivalence): **PASS** for both tests.
- Kernel `vx_printf` output: `warp_test: FAILED (2 errors)`,
  `barrier_test: FAILED (5 errors)`.
- Final UVM verdict: **PASSED** for both. ← **the verdict gap**

This is the bug Gate 2 exists to catch.

### Run 2 — same buggy kernel, new two-gate checker

`results/20260624/run_212326_warp_scheduling_test/` and
`results/20260624/run_213435_barrier_sync_test/`

- Gate 1 (DUT==SimX equivalence): **PASS** for both tests
  (DUT and SimX still agreed on the wrong answer).
- Gate 2 (RESULT_ADDR == 0x900DCAFE): **FAIL** for both.
  - warp_scheduling_test: `RESULT_ADDR=0x00000002` (kernel saw 2 errors)
  - barrier_sync_test: `RESULT_ADDR=0x00000005` (kernel saw 5 errors)
- Final UVM verdict: **FAILED** for both. ← **Gate 2 catches what Gate 1
  cannot.**

The exact diagnostic line the testbench printed:

```
FAIL — kernel reported errors: RESULT_ADDR=0x80010000=0x00000002 (expected 0x900DCAFE);
       DUT==SimX equivalence held but the kernel itself failed
```

This wording is deliberate — it tells the operator immediately that the
problem is *not* a DUT-vs-SimX divergence (which would point at the RTL or
the SimX model) but a kernel-level failure that both implementations
correctly reproduced.

### Run 3 — fixed kernel + two-gate checker (final, clean)

`results/20260624/run_214515_warp_scheduling_test/` and
`results/20260624/run_215216_barrier_sync_test/`

- Kernel `vx_printf` output: `warp_test: ALL PASSED`,
  `barrier_test: ALL PASSED`.
- Gate 1: **PASS** (mem comparisons = 26 for warp, 37 for barrier; console
  check = 1 each).
- Gate 2: **PASS** — `RESULT_ADDR == 0x900DCAFE` for both.
- Final UVM verdict: **PASSED** for both. UVM_ERROR count: 0.

Side-effect observations from the cleanup:

| Metric | Buggy run | Fixed run | Comment |
|---|---|---|---|
| warp_test total cycles | 101,641 | 80,789 | ~20% reduction — stall loops removed |
| barrier_test total cycles | 186,005 | 142,582 | ~23% reduction — stall loops + cleaner phase structure |
| barrier_test mem comparisons | 33 | 37 | +4: `bar3_contrib[]` adds four newly-compared word slots |
| barrier_test accumulator value | 4 (race-lost) | 10 (correct: 1+2+3+4) | the bug we were measuring |

---

## 8. Files changed in this work

### New files

| Path | Purpose |
|---|---|
| `uvm_tests/warp_scheduling_test.sv` | T-warp SV test class (~110 LOC) |
| `uvm_tests/barrier_sync_test.sv` | T-barr SV test class (~110 LOC) |
| `vortex/tests/kernel/warp_test/warp_test.cpp` | T-warp kernel (4 sub-tests) |
| `vortex/tests/kernel/warp_test/Makefile` | Kernel build glue |
| `vortex/tests/kernel/barrier_test/barrier_test.cpp` | T-barr kernel (4 sub-tests) |
| `vortex/tests/kernel/barrier_test/Makefile` | Kernel build glue |

### Modified files

| Path | Change |
|---|---|
| `uvm_tests/vortex_test_pkg.sv` | Two `\`include` lines added for the new SV classes |

No infrastructure files were modified. No scoreboard, agent, or env file was
touched. The two-gate pattern is purely a derived-class addition.

---

## 9. Invocation

Build the kernel ELFs once after any C++ change:

```bash
make -C /home/stev_teto_22/vortex/tests/kernel/warp_test/
make -C /home/stev_teto_22/vortex/tests/kernel/barrier_test/
```

Run the tests from the UVM environment root:

```bash
scripts/run.sh \
  --test=warp_scheduling_test \
  --program=/home/stev_teto_22/vortex/tests/kernel/warp_test/warp_test.elf \
  --interface=axi --clusters=1 --cores=1 --warps=4 --threads=4 \
  --timeout=10000000 --startup-addr=0x80000000

scripts/run.sh \
  --test=barrier_sync_test \
  --program=/home/stev_teto_22/vortex/tests/kernel/barrier_test/barrier_test.elf \
  --interface=axi --clusters=1 --cores=1 --warps=4 --threads=4 \
  --timeout=10000000 --startup-addr=0x80000000
```

Minimum configuration is enforced by the test classes:
`warp_scheduling_test` fatals if `num_warps < 4 || num_threads < 4`;
`barrier_sync_test` fatals if `num_warps < 4`.

---

## 10. Lessons and standing recommendations

### 10.1 Adopt the two-gate pattern for every directed test in this scope

Every remaining directed test in scope — T-axi (`axi_memory_test`) and
T-fmem (`functional_memory_test`) — should follow the same two-gate pattern:

- **Gate 1:** inherit `kernel_launch_test::check_results()` for DUT-vs-SimX
  equivalence (no change needed — call `super.check_results()`).
- **Gate 2:** add a derived-class `check_results()` override that peeks an
  absolute-correctness sentinel out of the shared `mem_model`. The sentinel
  must be seeded by the stimulus itself (the C++ kernel, or the SV virtual
  sequence for non-kernel tests like T-axi).

Without Gate 2, any stimulus-side bug that affects both DUT and SimX
identically will pass undetected.

### 10.2 Use barriers for ordering, not for atomicity

The accumulator bug was a conceptual confusion: a barrier between phase 1 and
phase 2 cannot fix a race that lives entirely inside phase 1. When multiple
warps need to combine results, use the scatter-then-reduce idiom: each warp
writes its own unique slot, then a single thread (or, on real hardware, an
atomic) does the combination after a barrier.

### 10.3 Do not use timing stalls as synchronization

The original wspawn test used `for (i = 0; i < wid * 64; i++) stall++` as
"poor man's synchronization." This was wrong for three independent reasons:

1. Warp 0 had zero iterations and so was not stalled at all.
2. The `volatile int` was a stack-local that the compiler is allowed to
   eliminate.
3. Even if it had stalled, the right amount of stall depends on warp
   scheduling decisions, instruction latencies, and memory traffic — none of
   which are deterministic.

Use `vx_barrier` whenever the program requires "all warps reach this point."
That is what it is for.

### 10.4 Trust the kernel's own diagnostics

The kernel's `vx_printf` lines (`warp_test: FAILED (2 errors)`) were already
visible in the simulation log on the first run. The verdict gap was only a
**checker** gap, not a **detection** gap — the data needed to fail the test
was already in the log; the testbench just was not configured to act on it.
Future tests should always seed an in-kernel sentinel and gate the SV verdict
on it.

---

## 11. Status and next steps

- T-warp: **complete**, status PASSED, both gates green.
- T-barr: **complete**, status PASSED, both gates green.
- Next in scope: T-axi (`axi_memory_test`) and T-fmem
  (`functional_memory_test`), in that order. Both will adopt the two-gate
  pattern established by T-warp and T-barr.
- Out of scope for this session: SVA-axi, D-simx, A1, PATCH (all Stage 2,
  will be picked up only when explicitly requested).
