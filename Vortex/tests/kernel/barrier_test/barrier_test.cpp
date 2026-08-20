////////////////////////////////////////////////////////////////////////////////
// barrier_test.cpp — Barrier Synchronization Verification Kernel
//
// Covers four barrier scenarios. Each scenario is designed so that a broken
// barrier (early release, missing hold, or non-rearmable) produces a wrong
// value in the result arrays, creating a memory or console divergence between
// DUT and SimX that the scoreboard will catch.
//
// Sub-tests:
//   1. Basic barrier      — N warps: pre-barrier write, sync, post-barrier write.
//                           Verifies all pre + post sentinels are correct.
//   2. Staggered arrival  — Warp w stalls w×256 iterations before the barrier.
//                           After the barrier, each warp verifies ALL other
//                           warps' pre-barrier writes are present. Proves the
//                           barrier held fast warps until the slowest arrived.
//   3. Shared accumulator — Warps accumulate into a shared counter in two
//                           phases separated by a barrier. Without the barrier,
//                           phase-2 reads would race against phase-1 writes.
//   4. Double barrier     — Same barrier used twice in sequence. Verifies the
//                           barrier mechanism rearms after first release.
//
// Result sentinel at RESULT_ADDR (0x80010000): total error count so the UVM
// scoreboard can compare a 4-byte memory window in addition to console output.
////////////////////////////////////////////////////////////////////////////////

#include <stdio.h>
#include <algorithm>
#include <VX_config.h>
#include <vx_intrinsics.h>
#include <vx_print.h>
#include <vx_spawn.h>

#define PRINTF      vx_printf
#define RESULT_ADDR 0x80010000
#define BAR_ID      0

// Hard bound on every bar*_ array below. main() clamps the warp count to it, so
// the bound is stated ONCE instead of repeated as a literal in each declaration.
// vx_num_warps() is warps PER CORE, and wspawn starts each warp with thread 0
// only (VX_schedule.sv:130), so wid is the sole index and NT cannot alias.
#define MAX_TEST_WARPS 8

////////////////////////////////////////////////////////////////////////////////
// Test 1: Basic Barrier — pre/post sentinel pattern
//
// Each warp writes a pre-barrier sentinel, synchronizes, then writes a
// post-barrier sentinel. If any warp skips or exits before the barrier,
// its post sentinel will be missing.
// Expected: bar1_pre[w] = 0x10+w,  bar1_post[w] = 0x20+w
////////////////////////////////////////////////////////////////////////////////

int bar1_pre[MAX_TEST_WARPS];
int bar1_post[MAX_TEST_WARPS];
volatile int bar1_num_warps;

void bar1_kernel() {
    int wid = vx_warp_id();
    bar1_pre[wid] = 0x10 + wid;
    vx_barrier(BAR_ID, bar1_num_warps);
    bar1_post[wid] = 0x20 + wid;
    vx_tmc(wid == 0);
}

int test_basic_barrier(int nw) {
    PRINTF("=== T1: Basic Barrier ===\n");
    bar1_num_warps = nw;
    vx_wspawn(nw, bar1_kernel);
    bar1_kernel();
    int errors = 0;
    for (int w = 0; w < nw; w++) {
        if (bar1_pre[w]  != (0x10 + w)) { PRINTF("  FAIL bar1_pre[%d]=0x%x\n",  w, bar1_pre[w]);  errors++; }
        if (bar1_post[w] != (0x20 + w)) { PRINTF("  FAIL bar1_post[%d]=0x%x\n", w, bar1_post[w]); errors++; }
    }
    if (!errors) PRINTF("  PASS (%d warps pre+post sync)\n", nw);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 2: Staggered Arrival — proves hold-until-all-arrive
//
// Warp w executes w×256 stall iterations before writing its sentinel and
// calling the barrier. After release, each warp reads all other warps'
// sentinels. Any missing entry means a fast warp was released before a
// slow warp finished writing its sentinel.
// Expected after barrier: bar2_data[w] = 0x30+w for all w
////////////////////////////////////////////////////////////////////////////////

int bar2_data[MAX_TEST_WARPS];
// PER-WARP delay counters. This was a single shared `volatile int` incremented
// non-atomically by every warp (and, before the core gate in main(), by every
// core). Nothing reads it for correctness — it exists only to stagger arrival —
// but it lives in .data, so the end-state scoreboard compared a value that had
// no architecturally defined result. Measured at 2CL: DUT 0x300 vs SimX 0x600
// (OBS-026, symbol 8000778c). Giving each warp its own slot makes the final
// values deterministic — bar2_stall[w] == w*256 — so the scoreboard now checks a
// real outcome instead of comparing a race.
volatile int bar2_stall[MAX_TEST_WARPS];
volatile int bar2_num_warps;

void bar2_kernel() {
    int wid = vx_warp_id();
    int nw  = bar2_num_warps;
    for (int i = 0; i < wid * 256; i++) bar2_stall[wid]++;
    bar2_data[wid] = 0x30 + wid;
    vx_barrier(BAR_ID, nw);
    // Each warp independently verifies that all pre-barrier writes landed.
    // If the barrier held correctly, all nw sentinels must be present here.
    for (int w = 0; w < nw; w++) {
        if (bar2_data[w] != (0x30 + w)) {
            // Mark this warp's slot as bad so the main thread can detect it.
            bar2_data[wid] = 0xDEAD0000 | wid;
        }
    }
    vx_tmc(wid == 0);
}

int test_staggered_arrival(int nw) {
    PRINTF("=== T2: Staggered Arrival Barrier ===\n");
    bar2_num_warps = nw;
    for (int w = 0; w < nw; w++) bar2_stall[w] = 0;
    vx_wspawn(nw, bar2_kernel);
    bar2_kernel();
    int errors = 0;
    for (int w = 0; w < nw; w++) {
        if (bar2_data[w] != (0x30 + w)) {
            PRINTF("  FAIL bar2_data[%d]=0x%x (barrier released before all warps wrote)\n", w, bar2_data[w]);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d warps staggered+synced)\n", nw);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 3: Shared Accumulator — phase separation via barrier
//
// Phase 1: each warp writes its contribution (wid+1) to a UNIQUE slot in
//          bar3_contrib[]. Unique slots eliminate the non-atomic RMW race that
//          plagued the += approach (warps racing on a single volatile int).
// Barrier 1: ensures all phase-1 writes complete before warp 0 sums.
// Phase 2: warp 0 only — single-thread reduction into bar3_accumulator.
// Barrier 2: ensures bar3_accumulator is visible before all warps read it.
// Phase 3: all warps write a confirmation sentinel.
// Expected sum = 1+2+...+nw = nw*(nw+1)/2
////////////////////////////////////////////////////////////////////////////////

int bar3_contrib[MAX_TEST_WARPS];
volatile int bar3_accumulator;
int bar3_confirm[MAX_TEST_WARPS];
volatile int bar3_num_warps;

void bar3_kernel() {
    int wid = vx_warp_id();
    int nw  = bar3_num_warps;
    // Phase 1: each warp contributes to its own unique slot (race-free)
    bar3_contrib[wid] = wid + 1;
    vx_barrier(BAR_ID, nw);
    // Phase 2: warp 0 reduces all contributions into bar3_accumulator
    if (wid == 0) {
        int sum = 0;
        for (int w = 0; w < nw; w++) sum += bar3_contrib[w];
        bar3_accumulator = sum;
    }
    vx_barrier(BAR_ID, nw);
    // Phase 3: all warps check the sum and write a confirmation sentinel
    int expected_sum = nw * (nw + 1) / 2;
    bar3_confirm[wid] = (bar3_accumulator == expected_sum) ? (0x50 + wid) : 0xBAD00000 + wid;
    vx_tmc(wid == 0);
}

int test_accumulator_barrier(int nw) {
    PRINTF("=== T3: Shared Accumulator Barrier ===\n");
    bar3_accumulator = 0;
    bar3_num_warps   = nw;
    for (int w = 0; w < nw; w++) bar3_contrib[w] = 0;
    vx_wspawn(nw, bar3_kernel);
    bar3_kernel();
    int expected_sum = nw * (nw + 1) / 2;
    int errors = 0;
    if (bar3_accumulator != expected_sum) {
        PRINTF("  FAIL accumulator=%d expected %d\n", bar3_accumulator, expected_sum);
        errors++;
    }
    for (int w = 0; w < nw; w++) {
        if (bar3_confirm[w] != (0x50 + w)) {
            PRINTF("  FAIL bar3_confirm[%d]=0x%x\n", w, bar3_confirm[w]);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (accumulator=%d, %d warps confirmed)\n", bar3_accumulator, nw);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 4: Double Barrier — verifies barrier rearms after first release
//
// Warps pass through the barrier TWICE. If the barrier is one-shot (does not
// rearm), the second call will deadlock (caught by the UVM timeout) or corrupt
// results.
// Expected: bar4_r1[w] = 0x60+w,  bar4_r2[w] = 0x70+w
////////////////////////////////////////////////////////////////////////////////

int bar4_r1[MAX_TEST_WARPS];
int bar4_r2[MAX_TEST_WARPS];
volatile int bar4_num_warps;

void bar4_kernel() {
    int wid = vx_warp_id();
    int nw  = bar4_num_warps;
    bar4_r1[wid] = 0x60 + wid;
    vx_barrier(BAR_ID, nw);        // first barrier
    bar4_r2[wid] = 0x70 + wid;
    vx_barrier(BAR_ID, nw);        // second barrier — must rearm
    vx_tmc(wid == 0);
}

int test_double_barrier(int nw) {
    PRINTF("=== T4: Double Barrier (Rearm) ===\n");
    bar4_num_warps = nw;
    vx_wspawn(nw, bar4_kernel);
    bar4_kernel();
    int errors = 0;
    for (int w = 0; w < nw; w++) {
        if (bar4_r1[w] != (0x60 + w)) { PRINTF("  FAIL bar4_r1[%d]=0x%x\n", w, bar4_r1[w]); errors++; }
        if (bar4_r2[w] != (0x70 + w)) { PRINTF("  FAIL bar4_r2[%d]=0x%x\n", w, bar4_r2[w]); errors++; }
    }
    if (!errors) PRINTF("  PASS (%d warps double-barrier OK)\n", nw);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// main
////////////////////////////////////////////////////////////////////////////////

int main() {
    // OBS-026 — CORE GATE. Every Vortex core self-starts from reset
    // (VX_schedule.sv:230), so without this every core ran this kernel against
    // the SAME shared .data. All state here is a single global indexed by WARP
    // id, which is not unique across cores, and vx_barrier() is PER-CORE
    // (GBAR_ENABLE undefined => VX_wctl_unit.sv:138 ties is_global to 1'b0).
    // The test's synchronisation scope is one core; the data it protects is
    // GPU-wide. Measured at 2CL/2C: test_accumulator_barrier()'s own
    // `bar3_contrib[w] = 0` init loop, running on a LATER core's main thread,
    // wiped slots an EARLIER core's warps had already written, so that core
    // summed 2 instead of 10 ("FAIL accumulator=2 expected 10" on cores 0 and 1
    // while cores 2 and 3 passed). RESULT_ADDR then diverged because the four
    // cores wrote DIFFERENT values to it and last-writer-wins was ordered
    // differently by the DUT than by SimX.
    // Gating costs no coverage: because barriers are per-core, the extra cores
    // were re-running an identical independent test, not a multi-core one.
    // Genuinely multi-core barrier stimulus would need per-core data regions
    // (index by vx_core_id()*nw + wid) and is only worth building if
    // GBAR_ENABLE is turned on — see docs/RTL_OBSERVATIONS.md OBS-026.
    if (vx_core_id() != 0) return 0;

    int nw = std::min(vx_num_warps(), 4);   // cap at 4; matches UVM minimum
    if (nw > MAX_TEST_WARPS) nw = MAX_TEST_WARPS;   // arrays are the hard bound
    int errors = 0;

    errors += test_basic_barrier(nw);
    errors += test_staggered_arrival(nw);
    errors += test_accumulator_barrier(nw);
    errors += test_double_barrier(nw);

    if (errors == 0) PRINTF("barrier_test: ALL PASSED\n");
    else             PRINTF("barrier_test: FAILED (%d errors)\n", errors);

    // Pass/fail sentinel for scoreboard memory-window compare.
    *((volatile int*)RESULT_ADDR) = (errors == 0) ? 0x900DCAFE : errors;

    return errors;
}
