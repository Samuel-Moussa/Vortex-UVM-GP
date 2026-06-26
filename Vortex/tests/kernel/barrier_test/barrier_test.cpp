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

////////////////////////////////////////////////////////////////////////////////
// Test 1: Basic Barrier — pre/post sentinel pattern
//
// Each warp writes a pre-barrier sentinel, synchronizes, then writes a
// post-barrier sentinel. If any warp skips or exits before the barrier,
// its post sentinel will be missing.
// Expected: bar1_pre[w] = 0x10+w,  bar1_post[w] = 0x20+w
////////////////////////////////////////////////////////////////////////////////

int bar1_pre[8];
int bar1_post[8];
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

int bar2_data[8];
volatile int bar2_stall;
volatile int bar2_num_warps;

void bar2_kernel() {
    int wid = vx_warp_id();
    int nw  = bar2_num_warps;
    for (int i = 0; i < wid * 256; i++) bar2_stall++;
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
    bar2_stall     = 0;
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

int bar3_contrib[8];
volatile int bar3_accumulator;
int bar3_confirm[8];
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

int bar4_r1[8];
int bar4_r2[8];
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
    int nw     = std::min(vx_num_warps(), 4);   // cap at 4; matches UVM minimum
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
