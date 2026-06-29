// spawn_tmc_sweep — directed warp-control kernel (printf-free).
//
// Closes the two warp-control coverage holes the saturated riscv-dv stream and
// the data-parallel kernels (vecadd_lite/diverge_lite) could not reach:
//   - wspawn_cg.cp_spawn_cnt  (was 25% = only "all" hit by a full-grid spawn)
//   - tmc_cg.cp_tmc_occ       (was 60% = "deactivate"/one partial occupancy missing)
//
// It drives vx_wspawn with EVERY spawn count {1,2,3,4=NUM_WARPS} and vx_tmc with
// EVERY thread-mask occupancy {0,1,2,3,4=NUM_THREADS}, following the exact
// wspawn/tmc handshake the Vortex runtime uses in vx_spawn.c (process_threads_stub
// + the `vx_wspawn(1,0)` "wait for spawned warps" collapse between batches), so no
// warp is left running across a re-spawn (the undefined-behaviour case).
//
// tmc occupancy bins are sourced safely:
//   - warp 0 only ever does partial(2)=0x3, partial(3)=0x7, full(4)=-1, one(1) —
//     it NEVER deactivates itself (vx_tmc(0) on the lone running warp = hang).
//   - the "deactivate"(0) and a second "full"(4) bin come from the worker warps
//     (vx_tmc(-1) on entry, vx_tmc_zero() on exit) — exactly process_threads_stub.
//
// End-state is deterministic (each warp writes only its own slot) so the
// black-box DUT-vs-SimX scoreboard stays exact.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define NW 4            // NUM_WARPS  (primary config 1CL/1C/4W/4T)

volatile int g_out[NW];

// Worker: activates the full warp, stamps its own slot, then deactivates.
// Mirrors process_threads_stub (vx_tmc(-1) ... vx_tmc_zero()) so the spawned
// warp terminates cleanly and is free for the next batch.
static void __attribute__((noinline)) worker_stub() {
  vx_tmc(-1);                          // tmc_occ: full (NT) on a worker warp
  int w = vx_warp_id();
  g_out[w] = 100 + w;                  // own slot only -> race-free, deterministic
  vx_tmc_zero();                       // tmc_occ: deactivate (0)
}

int main() {
  for (int i = 0; i < NW; i++) g_out[i] = 0;

  // ---- spawn count sweep: 2, 3, 4 (some_2, some_3, all) ----------------------
  // Each batch waits for its workers via vx_wspawn(1,0) before the next, so warps
  // 1..K-1 have all hit vx_tmc_zero() and are idle again.
  vx_wspawn(2, worker_stub);   // cp_spawn_cnt: some (2)
  vx_tmc(0x3);                 // cp_tmc_occ:   partial (2)  -- warp 0 stays alive
  g_out[0] = 100;             // warp 0's slot
  vx_tmc_one();
  vx_wspawn(1, 0);             // cp_spawn_cnt: one (1) + wait for batch

  vx_wspawn(3, worker_stub);   // cp_spawn_cnt: some (3)
  vx_tmc(0x7);                 // cp_tmc_occ:   partial (3)
  g_out[0] = 100;
  vx_tmc_one();
  vx_wspawn(1, 0);

  vx_wspawn(NW, worker_stub);  // cp_spawn_cnt: all (NW=4)
  vx_tmc(-1);                  // cp_tmc_occ:   full (NT) on warp 0
  g_out[0] = 100;
  vx_tmc_one();
  vx_wspawn(1, 0);

  // ---- verify (single-thread, result to memory; no printf) -------------------
  int errors = 0;
  for (int w = 0; w < NW; w++)
    if (g_out[w] != 100 + w) errors++;
  return errors;
}
