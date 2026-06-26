////////////////////////////////////////////////////////////////////////////////
// warp_test.cpp — Warp Scheduling Verification Kernel
//
// Covers four distinct warp/thread-management scenarios. Each sub-test writes
// unique per-warp or per-thread sentinels so any scheduling or divergence bug
// manifests as a memory or console divergence between DUT and SimX.
//
// Sub-tests:
//   1. TMC   — thread-mask control: activate all N threads, each writes a
//              position-unique sentinel (0x10+tid).
//   2. Split/Join — nested two-level divergence across 4 threads; each of the
//              four paths writes a distinct sentinel (0x2A..0x2D). Tests the
//              IPDOM reconvergence stack.
//   3. Wspawn — spawns up to 8 warps; each warp writes (0x30+wid) then all
//              warps rendezvous on a barrier before warp 0 exits. Tests the
//              warp scheduler without timing-dependent stall races.
//   4. TLS   — thread-local warp_id written and immediately read back per warp;
//              verifies per-warp context is not corrupted by concurrent warps.
//
// Result sentinel: the total error count is written to RESULT_ADDR (0x80010000)
// so the UVM scoreboard can compare a 4-byte memory window in addition to the
// console output stream.
////////////////////////////////////////////////////////////////////////////////

#include <stdio.h>
#include <algorithm>
#include <VX_config.h>
#include <vx_intrinsics.h>
#include <vx_print.h>
#include <vx_spawn.h>

#define PRINTF      vx_printf
#define RESULT_ADDR 0x80010000

static int make_full_tmask(int n) { return (1 << n) - 1; }

////////////////////////////////////////////////////////////////////////////////
// Test 1: Thread Mask Control
////////////////////////////////////////////////////////////////////////////////

int tmc_result[8];

void __attribute__((noinline)) do_tmc_write() {
    int tid = vx_thread_id();
    tmc_result[tid] = 0x10 + tid;
}

int test_tmc() {
    PRINTF("=== T1: Thread Mask Control ===\n");
    int nt = std::min(vx_num_threads(), 8);
    vx_tmc(make_full_tmask(nt));
    do_tmc_write();
    vx_tmc_one();
    int errors = 0;
    for (int t = 0; t < nt; t++) {
        if (tmc_result[t] != (0x10 + t)) {
            PRINTF("  FAIL tmc_result[%d]=0x%x expected 0x%x\n", t, tmc_result[t], 0x10 + t);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d threads)\n", nt);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 2: Warp Divergence via Split/Join
//
// 4-thread warp, two-level nested branch:
//   t0: cond1=T cond2=T  → 0x2A
//   t1: cond1=T cond2=F  → 0x2B
//   t2: cond1=F cond2=T  → 0x2C
//   t3: cond1=F cond2=F  → 0x2D
////////////////////////////////////////////////////////////////////////////////

int dvg_result[4];
static const int dvg_expected[4] = { 0x2A, 0x2B, 0x2C, 0x2D };

void __attribute__((noinline)) do_diverge() {
    int tid   = vx_thread_id();
    int cond1 = (tid < 2);
    int sp1   = vx_split(cond1);
    if (cond1) {
        int cond2 = (tid < 1);
        int sp2   = vx_split(cond2);
        if (cond2) dvg_result[tid] = 0x2A;
        else       dvg_result[tid] = 0x2B;
        vx_join(sp2);
    } else {
        int cond2 = (tid < 3);
        int sp2   = vx_split(cond2);
        if (cond2) dvg_result[tid] = 0x2C;
        else       dvg_result[tid] = 0x2D;
        vx_join(sp2);
    }
    vx_join(sp1);
}

int test_divergence() {
    PRINTF("=== T2: Warp Divergence (Split/Join) ===\n");
    int nt = std::min(vx_num_threads(), 4);
    vx_tmc(make_full_tmask(nt));
    do_diverge();
    vx_tmc_one();
    int errors = 0;
    for (int t = 0; t < nt; t++) {
        if (dvg_result[t] != dvg_expected[t]) {
            PRINTF("  FAIL dvg_result[%d]=0x%x expected 0x%x\n", t, dvg_result[t], dvg_expected[t]);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d threads diverged+reconverged)\n", nt);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 3: Warp Spawn and Scheduling
//
// Spawns up to 8 warps. Each warp writes sentinel 0x30+wid, then all warps
// rendezvous on a barrier before warp 0 exits via vx_tmc. The barrier
// guarantees every write is visible to the subsequent check loop — without it,
// warp 0 (zero stall by definition) would race ahead and read stale zeros for
// the other warps' slots.
////////////////////////////////////////////////////////////////////////////////

int wspawn_result[8];
volatile int wspawn_num_warps;

void wspawn_warp_func() {
    int wid = vx_warp_id();
    wspawn_result[wid] = 0x30 + wid;
    vx_barrier(0, wspawn_num_warps);    // rendezvous before warp 0 exits
    vx_tmc(wid == 0);
}

int test_wspawn() {
    PRINTF("=== T3: Warp Spawn and Scheduling ===\n");
    int nw = std::min(vx_num_warps(), 8);
    wspawn_num_warps = nw;
    vx_wspawn(nw, wspawn_warp_func);
    wspawn_warp_func();     // warp 0 entry
    int errors = 0;
    for (int w = 0; w < nw; w++) {
        if (wspawn_result[w] != (0x30 + w)) {
            PRINTF("  FAIL wspawn_result[%d]=0x%x expected 0x%x\n", w, wspawn_result[w], 0x30 + w);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d warps spawned+scheduled)\n", nw);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 4: Thread Local Storage (Warp Context Isolation)
//
// Each warp writes wid into a __thread (TLS) variable, then immediately reads
// it back. A corrupt result means another warp's execution overwrote this
// warp's register context. A barrier before vx_tmc ensures warp 0 cannot exit
// and kill the other warps before they have finished writing tls_result[].
////////////////////////////////////////////////////////////////////////////////

int tls_result[8];
__thread int tls_var;
volatile int tls_num_warps;

void tls_warp_func() {
    int wid = vx_warp_id();
    tls_var = wid;
    tls_result[wid] = 0x40 + tls_var;  // must equal 0x40 + wid
    vx_barrier(0, tls_num_warps);       // rendezvous before warp 0 exits
    vx_tmc(wid == 0);
}

int test_tls() {
    PRINTF("=== T4: Thread Local Storage (Context Isolation) ===\n");
    int nw = std::min(vx_num_warps(), 8);
    tls_num_warps = nw;
    vx_wspawn(nw, tls_warp_func);
    tls_warp_func();
    int errors = 0;
    for (int w = 0; w < nw; w++) {
        if (tls_result[w] != (0x40 + w)) {
            PRINTF("  FAIL tls_result[%d]=0x%x expected 0x%x\n", w, tls_result[w], 0x40 + w);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d warps context-isolated)\n", nw);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// main
////////////////////////////////////////////////////////////////////////////////

int main() {
    int errors = 0;
    errors += test_tmc();
    errors += test_divergence();
    errors += test_wspawn();
    errors += test_tls();

    if (errors == 0) PRINTF("warp_test: ALL PASSED\n");
    else             PRINTF("warp_test: FAILED (%d errors)\n", errors);

    // Pass/fail sentinel for scoreboard memory-window compare (4 bytes at RESULT_ADDR).
    // Both DUT and SimX run identical code, so both write the same value.
    // A DUT bug that corrupts any sub-test changes the error count → memory mismatch.
    *((volatile int*)RESULT_ADDR) = (errors == 0) ? 0x900DCAFE : errors;

    return errors;
}
