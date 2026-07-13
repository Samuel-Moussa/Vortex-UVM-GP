// diverge_deep — printf-free multi-warp kernel with DEEP nested SIMT divergence.
//
// Purpose: push the warp-state covergroups past what diverge_lite reaches.
// diverge_lite only nests 2 deep, so cp_split_depth / cross_dvg_depth /
// cp_join_depth / cross_join stall at 62-75%. This kernel nests FOUR
// data-dependent branches (split-stack depth up to 4) and mixes:
//   * divergent splits (threads in a warp take different paths)  -> cp_is_dvg.divergent
//   * uniform splits (a data-dependent branch that all active threads
//     happen to take the same way at runtime)                    -> cp_is_dvg.uniform
//   * a data-dependent inner loop with varying trip count        -> varied active-thread
//     counts over time (cp_active_threads / cross_sfu_threads / partial tmask)
// printf-free so it completes fast (INV-1). Results to memory for DUT-vs-SimX.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N 64

typedef struct {
  int *in;
  int *out;
} div_args_t;

// THREE nested if/else that ALL genuinely diverge -> IPDOM split-stack depth 3
// (DV_STACK_SIZE = NUM_THREADS-1 = 3 for 4T; cp_split_depth.auto[3]). At -O3 the
// compiler if-converts small nested branches into predication (no real split),
// so each level carries an `asm volatile` optimization barrier on the live value
// to force the branch to survive as real control flow. Divergent loops don't
// help here: Vortex resolves data-dependent loops via thread-mask (tmc), not the
// split/join stack. Nested branches diverge on independent per-thread bits, and
// data drives every path -> uniform + divergent splits + reconverge at depth.
#define OPQ(x) __asm__ volatile("" : "+r"(x))   // optimization barrier
static inline int deep(int v, int i) {
  int r = v;
  if (v & 1) {                         // L1 split
    OPQ(r);
    if (v & 2) {                       // L2 split (nested, still divergent)
      OPQ(r);
      if (v & 4) { OPQ(r); r = v * 3 + 1; }   // L3 split -> depth 3
      else       { OPQ(r); r = v * 5 + 2; }
    } else       { OPQ(r); r = v - 7; }
  } else {
    OPQ(r);
    if (v & 2) {                       // L2 split (else side)
      OPQ(r);
      if (v & 4) { OPQ(r); r = v ^ 0x55; }    // L3 split -> depth 3
      else       { OPQ(r); r = v + 100; }
    } else       { OPQ(r); r = v << 1; }
  }
  // Data-dependent loop => varied active-thread counts over time (tmc / occ).
  for (int k = 0; k < (i & 7); k++) r += (k * 2 + 1);
  return r;
}

void diverge_kernel(div_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;
  int v = args->in[i];
  args->out[i] = deep(v, i);         // reconverge, then store
}

int in_buf[N];
volatile int out_buf[N];

int main() {
  for (int i = 0; i < N; i++) { in_buf[i] = i * 7 + 1; out_buf[i] = 0; }

  div_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)diverge_kernel, &args);

  int errors = 0;
  for (int i = 0; i < N; i++)
    if (out_buf[i] != deep(in_buf[i], i)) errors++;
  return errors;   // out_buf[] is the DUT-vs-SimX scoreboard check
}
