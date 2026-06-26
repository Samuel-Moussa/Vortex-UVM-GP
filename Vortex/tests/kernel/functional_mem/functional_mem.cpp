////////////////////////////////////////////////////////////////////////////////
// functional_mem.cpp — Functional Memory Verification Kernel
//
// Covers four memory-subsystem scenarios on the custom-mem (and AXI) path.
// Each sub-test writes unique per-thread sentinels so any LSU width, alignment,
// RAW-hazard, or cross-warp visibility bug manifests as a memory or console
// divergence between DUT and SimX that the scoreboard will catch.
//
// Sub-tests:
//   1. Width access   — all 4 threads issue word, halfword, and byte stores
//                       then read them back; catches data-path width bugs.
//   2. Strided access — each thread writes buf[tid*4] = 0x40+tid; catches
//                       per-lane address computation bugs.
//   3. Read-after-write — tight store/load pair per thread; catches LSU
//                       bypass and write-through failures.
//   4. Cross-warp visibility — warp 0 writes a shared buffer, vx_barrier,
//                       all warps confirm every entry is visible; catches
//                       cache coherence and barrier ordering bugs.
//
// Result sentinel at RESULT_ADDR (0x80010000): 0x900DCAFE on success, else
// the literal error count. The UVM Gate-2 check reads this word.
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
// Test 1: Word / Halfword / Byte Stores and Reads
//
// All 4 threads write 3 different access widths to their own slot, then
// the driver thread reads back and verifies each. A data-path width bug
// (e.g. halfword truncation, sign-extension error) shows here.
//
// Expected: t1_word[t]=0x100+t,  t1_hword[t]=0x20+t,  t1_byte[t]=0x30+t
////////////////////////////////////////////////////////////////////////////////

int   t1_word [4];
short t1_hword[4];
char  t1_byte [4];

void __attribute__((noinline)) do_width_write() {
    int tid       = vx_thread_id();
    t1_word [tid] = 0x100 + tid;
    t1_hword[tid] = (short)(0x20 + tid);
    t1_byte [tid] = (char) (0x30 + tid);
}

int test_width_access() {
    PRINTF("=== T1: Word/Halfword/Byte Access ===\n");
    int nt = std::min(vx_num_threads(), 4);
    vx_tmc(make_full_tmask(nt));
    do_width_write();
    vx_tmc_one();
    int errors = 0;
    for (int t = 0; t < nt; t++) {
        if (t1_word[t]  != (0x100 + t)) {
            PRINTF("  FAIL t1_word[%d]=0x%x expected 0x%x\n",  t, t1_word[t],  0x100 + t);
            errors++;
        }
        if (t1_hword[t] != (short)(0x20 + t)) {
            PRINTF("  FAIL t1_hword[%d]=0x%x expected 0x%x\n", t, (int)(unsigned short)t1_hword[t], 0x20 + t);
            errors++;
        }
        if (t1_byte[t]  != (char)(0x30 + t)) {
            PRINTF("  FAIL t1_byte[%d]=0x%x expected 0x%x\n",  t, (int)(unsigned char)t1_byte[t], 0x30 + t);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d threads, word+half+byte)\n", nt);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 2: Per-Thread Strided Access
//
// Each thread writes buf[tid*STRIDE] = 0x40+tid then reads back. Stride=4
// ensures each thread touches a distinct word in the same cache region, so
// any per-lane address calculation bug shows as an unexpected value or as
// a cross-thread slot collision.
//
// Expected: t2_buf[t*4] = 0x40+t for t in 0..nt-1
////////////////////////////////////////////////////////////////////////////////

#define T2_STRIDE 4
int t2_buf[16]; // 4 threads * stride 4 = entries at indices 0, 4, 8, 12

void __attribute__((noinline)) do_strided_write() {
    int tid = vx_thread_id();
    t2_buf[tid * T2_STRIDE] = 0x40 + tid;
}

int test_strided_access() {
    PRINTF("=== T2: Per-Thread Strided Access ===\n");
    int nt = std::min(vx_num_threads(), 4);
    for (int i = 0; i < 16; i++) t2_buf[i] = 0;
    vx_tmc(make_full_tmask(nt));
    do_strided_write();
    vx_tmc_one();
    int errors = 0;
    for (int t = 0; t < nt; t++) {
        if (t2_buf[t * T2_STRIDE] != (0x40 + t)) {
            PRINTF("  FAIL t2_buf[%d]=0x%x expected 0x%x\n",
                   t * T2_STRIDE, t2_buf[t * T2_STRIDE], 0x40 + t);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d threads stride-%d)\n", nt, T2_STRIDE);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 3: Tight Read-After-Write (RAW)
//
// Each thread stores a value to its slot, then immediately loads from the
// same address and writes the readback result as a confirmation. No barrier
// or delay between the store and load — this is the minimal RAW hazard.
// A cache write-through or bypass failure shows as wrong readback.
//
// Expected: t3_confirm[t] = 0x60+t (means readback matched 0x50+t)
////////////////////////////////////////////////////////////////////////////////

int t3_confirm[4];

void __attribute__((noinline)) do_raw_rw() {
    int tid = vx_thread_id();
    volatile int slot;
    slot = 0x50 + tid;              // store
    int rb = slot;                  // load immediately after
    t3_confirm[tid] = (rb == (0x50 + tid)) ? (0x60 + tid) : (0xBAD00000 + tid);
}

int test_read_after_write() {
    PRINTF("=== T3: Tight Read-After-Write ===\n");
    int nt = std::min(vx_num_threads(), 4);
    vx_tmc(make_full_tmask(nt));
    do_raw_rw();
    vx_tmc_one();
    int errors = 0;
    for (int t = 0; t < nt; t++) {
        if (t3_confirm[t] != (0x60 + t)) {
            PRINTF("  FAIL t3_confirm[%d]=0x%x expected 0x%x\n",
                   t, t3_confirm[t], 0x60 + t);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d threads RAW)\n", nt);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// Test 4: Cross-Warp Memory Visibility via Barrier
//
// Warp 0 fills t4_shared[0..nw-1] with (0x70+i). All warps then hit a
// barrier. After release, every warp independently reads the entire
// t4_shared[] array and confirms all entries are visible. A barrier ordering
// bug or cache-coherence issue shows as a stale (pre-barrier) value.
//
// Expected: t4_confirm[w] = 0x80+w for all w (means all nw entries visible)
////////////////////////////////////////////////////////////////////////////////

int t4_shared [8];
int t4_confirm[8];
volatile int t4_num_warps;

void t4_kernel() {
    int wid = vx_warp_id();
    int nw  = t4_num_warps;
    if (wid == 0) {
        for (int i = 0; i < nw; i++) t4_shared[i] = 0x70 + i;
    }
    vx_barrier(0, nw);
    int bad = 0;
    for (int i = 0; i < nw; i++) {
        if (t4_shared[i] != (0x70 + i)) bad++;
    }
    t4_confirm[wid] = (bad == 0) ? (0x80 + wid) : (0xBAD00000 + wid);
    vx_barrier(0, nw);          // rendezvous before warp 0 exits
    vx_tmc(wid == 0);
}

int test_xwarp_visibility(int nw) {
    PRINTF("=== T4: Cross-Warp Memory Visibility ===\n");
    t4_num_warps = nw;
    for (int w = 0; w < nw; w++) t4_confirm[w] = 0;
    for (int i = 0; i < nw; i++) t4_shared[i]  = 0;
    vx_wspawn(nw, t4_kernel);
    t4_kernel();
    int errors = 0;
    for (int w = 0; w < nw; w++) {
        if (t4_confirm[w] != (0x80 + w)) {
            PRINTF("  FAIL t4_confirm[%d]=0x%x expected 0x%x\n",
                   w, t4_confirm[w], 0x80 + w);
            errors++;
        }
    }
    if (!errors) PRINTF("  PASS (%d warps confirmed cross-warp visibility)\n", nw);
    return errors;
}

////////////////////////////////////////////////////////////////////////////////
// main
////////////////////////////////////////////////////////////////////////////////

int main() {
    int nw     = std::min(vx_num_warps(), 4);
    int errors = 0;

    errors += test_width_access();
    errors += test_strided_access();
    errors += test_read_after_write();
    errors += test_xwarp_visibility(nw);

    if (errors == 0) PRINTF("functional_mem: ALL PASSED\n");
    else             PRINTF("functional_mem: FAILED (%d errors)\n", errors);

    // Pass/fail sentinel for UVM Gate-2 absolute-correctness check.
    *((volatile int*)RESULT_ADDR) = (errors == 0) ? 0x900DCAFE : errors;

    return errors;
}
