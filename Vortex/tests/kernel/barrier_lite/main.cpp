// barrier_lite — directed barrier kernel (printf-free).
//
// Closes barrier_cg (was 55%): drives vx_barrier across both barrier IDs and
// every reachable participant count, following the proven barrier_test pattern
// (vx_wspawn(nw,k); k(); kernel ends vx_tmc(wid==0)) but with NO vx_printf, so it
// completes in thousands of cycles instead of millions (INV-1: printf is fenced
// MMIO IO, not a hang).
//
// Reachable barrier coverage in the 1-core RV32 config:
//   - cp_bar_id    : {0,1}        (NUM_BARRIERS = NUM_WARPS/2 = 2)            -> 100%
//   - cp_bar_size  : size_m1 {1,2,3}  (size_m1=0 => 1-warp barrier is is_noop,
//                                      never sampled; structurally unreachable)  -> 100% of reachable
//   - cp_bar_event : {hold, rel}  (non-last arrivals + last arrival)         -> 100%
//   - cp_bar_scope : {local}      (global needs GBAR_ENABLE / multi-core; the
//                                  global_bar bin is unreachable here -> Ahmad ignore)
//
// End-state (g_post[]) is deterministic per warp -> black-box DUT==SimX exact.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define NW 4

// KNOWN BENIGN MISMATCH (infra -> Ahmad, not a barrier bug): the scoreboard
// reports one MEM MISMATCH at the .got tail word (e.g. 0x80001e98, DUT=0 vs
// SimX=pointer). Root cause: the DUT's .bss-clear writes the bss padding that
// shares the GOT's 64-byte cache line; that line is write-allocated with zero
// for the never-loaded GOT bytes, so the cache writeback clobbers the read-only
// GOT word to 0 in AXI memory. SimX models flat memory (no cache writeback) and
// keeps it. The scoreboard's shadow_memory is built from AXI writes only with
// NO image preload, so it can't reconcile. Fix belongs in the scoreboard (gate
// read-only .got/.rodata words the DUT zero-clobbers, like the existing
// stack/poison gates) or preload shadow_memory from the program image. The
// barrier itself is correct: kernel completes via ebreak, all warps sync.
volatile int g_bid;          // barrier id for the current phase
volatile int g_bn;           // participant count for the current phase
volatile int g_pre[NW];
volatile int g_post[NW];

// Each participating warp: pre-barrier stamp, sync, post-barrier stamp, then
// collapse to warp 0 (vx_tmc(wid==0) keeps only warp 0 -> single-threaded again).
static void __attribute__((noinline)) bar_kernel() {
  int wid = vx_warp_id();
  g_pre[wid]  = 0x10 + wid;
  vx_barrier(g_bid, g_bn);
  g_post[wid] = 0x20 + wid;
  vx_tmc(wid == 0);
}

// One barrier phase: spawn nw-1 worker warps + warp 0, all hit vx_barrier(bid,nw).
static int phase(int bid, int nw) {
  g_bid = bid;
  g_bn  = nw;
  for (int w = 0; w < NW; w++) { g_pre[w] = 0; g_post[w] = 0; }

  vx_wspawn(nw, bar_kernel);   // warps 1..nw-1 run bar_kernel
  bar_kernel();                // warp 0 participates too
  vx_wspawn(1, 0);             // wait for spawned warps / collapse

  int e = 0;
  for (int w = 0; w < nw; w++) {
    if (g_pre[w]  != 0x10 + w) e++;
    if (g_post[w] != 0x20 + w) e++;
  }
  return e;
}

volatile int g_result;

int main() {
  int errors = 0;
  errors += phase(0, 2);   // bar_id 0, size_m1=1 (2 warps)
  errors += phase(1, 3);   // bar_id 1, size_m1=2 (3 warps)
  errors += phase(0, 4);   // bar_id 0, size_m1=3 (all 4 warps)
  g_result = (errors == 0) ? 0x600DBA12 : 0xBADBA12;
  return errors;
}
