// vote_shfl — directed kernel for the VOTE/SHFL warp intrinsics (ALU_TYPE_OTHER).
//
// Coverage target: VX_alu_int.sv:193 `xtype == ALU_TYPE_OTHER` is the ONLY ALU
// condition term left uncovered on the 1CL bank — it decodes exclusively from the
// warp-collective VOTE (vx_vote_all/any/uni/ballot) and SHFL (vx_shfl_up/down/
// bfly/idx) custom-0 ops (VX_decode.sv:507 funct7=1 => ALU_TYPE_OTHER). No prior
// test in the staged suite issues them, so the term never fired. This kernel does,
// and also exercises the vote-reduce / shuffle datapath (extra toggle).
//
// Correctness: every intrinsic is a well-defined SIMT op that BOTH the DUT and SimX
// implement from the same ISA (SimX execute.cpp Vote/Shfl). Predicates and values
// are pure functions of the lane index, so the per-thread result is deterministic;
// the DUT-vs-SimX end-state compare of g_out[] is byte-exact (scoreboard-safe).
// printf-free -> completes in a few k cycles (INV-1 clean).
//
// Multi-core aware: total = NUM_CLUSTERS*NUM_CORES*NUM_WARPS*NUM_THREADS so every
// hardware warp runs a full active mask (vote/shfl are meaningful only with the
// whole warp participating) and every per-core probe instance fires.

#include <stdint.h>
#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <VX_config.h>      // NUM_CLUSTERS, NUM_CORES, NUM_WARPS, NUM_THREADS

#define TOTAL (NUM_CLUSTERS * NUM_CORES * NUM_WARPS * NUM_THREADS)

typedef struct { uint32_t *out; } vs_args_t;

volatile uint32_t g_out[TOTAL];

void vs_kernel(vs_args_t *__UNIFORM__ args) {
  int tid  = blockIdx.x;
  int lane = tid % NUM_THREADS;          // lane within this warp
  int value = 65 + lane;                 // per-lane distinct payload (as in conform)

  // Three predicate shapes so the vote logic sees all/any/uniform cases.
  // Derived from `lane` (runtime) so the compiler cannot fold the ops away.
  int p_all = (value >= 0);              // uniformly true  -> vote_all = 1
  int p_par = lane & 1;                  // mixed           -> vote_any=1, vote_all=0
  int p_uni = (value < 100000);          // uniformly true  -> vote_uni = 1

  int va = vx_vote_all   (p_all);
  int vy = vx_vote_any   (p_par);
  int vu = vx_vote_uni   (p_uni);
  int vb = vx_vote_ballot(p_par);

  // Single subgroup spanning the whole warp (same convention as conform/tests.cpp).
  int mask  = 0;
  int clamp = NUM_THREADS - 1;
  int su = vx_shfl_up  (value, 1, clamp, mask);
  int sd = vx_shfl_down(value, 1, clamp, mask);
  int sf = vx_shfl_bfly(value, 1, clamp, mask);
  int si = vx_shfl_idx (value, 1, clamp, mask);

  args->out[tid] = (uint32_t)(va ^ vy ^ vu ^ vb ^ su ^ sd ^ sf ^ si ^ value);
}

int main() {
  for (int i = 0; i < TOTAL; i++) g_out[i] = 0;
  vs_args_t args; args.out = (uint32_t *)g_out;
  uint32_t total = TOTAL;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)vs_kernel, &args);
  return 0;   // scoreboard (DUT vs SimX end-state of g_out) is the authority
}
