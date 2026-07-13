// diverge_peel — LINEAR thread-peeling divergence to fill the IPDOM stack.
//
// The SIMT reconvergence (IPDOM) stack is sized NUM_THREADS-1 (VX_gpu_pkg:
// DV_STACK_SIZE = `UP(NUM_THREADS-1)`) because a warp can nest that many divergent
// splits by peeling ONE thread off at a time:
//     NT active -> (NT-1)+1 -> (NT-2)+1 -> ... -> 1+1     (NT-1 nested splits)
// Balanced splitting (4->2->1, as in diverge_deep) only reaches depth clog2(NT),
// so it CANNOT exercise the deepest stack slots. This kernel branches on the
// intra-warp thread position (blockIdx.x & (NT-1)) with strictly-decreasing
// thresholds so each nested branch removes exactly one thread -> divergence-stack
// depth reaches NUM_THREADS-1. asm-volatile barriers defeat -O3 if-conversion so
// the splits are real control flow (not predication). printf-free (INV-1).
// Result to memory for the DUT-vs-SimX scoreboard.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N  64          // 16 warps x 4 threads (multiple warps, each peels)

typedef struct {
  int *in;
  int *out;
} peel_args_t;

#define OPQ(x) __asm__ volatile("" : "+r"(x))   // optimization barrier

// tid = intra-warp thread position (0..NT-1). Strictly-decreasing thresholds
// peel one thread per nested level -> NT-1 nested divergent splits.
static inline int peel(int r, int tid) {
  if (tid < 3) { OPQ(r); r += 0x11;            // active: {0,1,2}   (thread 3 peeled)
    if (tid < 2) { OPQ(r); r += 0x22;          // active: {0,1}     (thread 2 peeled)
      if (tid < 1) { OPQ(r); r += 0x33; }      // active: {0}       (thread 1 peeled)
      OPQ(r);
    }
    OPQ(r);
  }
  OPQ(r);
  // trailing data-dependent loop -> varied active-thread counts over time
  for (int k = 0; k < (tid + 1); k++) r += (k * 7 + 1);
  return r;
}

int in_buf[N];
volatile int out_buf[N];

void peel_kernel(peel_args_t *__UNIFORM__ args) {
  int i   = blockIdx.x;
  int tid = i & 3;               // low bits = thread position within the warp
  args->out[i] = peel(args->in[i], tid);
}

int main() {
  for (int i = 0; i < N; i++) { in_buf[i] = i * 7 + 1; out_buf[i] = 0; }

  peel_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)peel_kernel, &args);

  int errors = 0;
  for (int i = 0; i < N; i++)
    if (out_buf[i] != peel(in_buf[i], i & 3)) errors++;
  return errors;   // out_buf[] is the DUT-vs-SimX scoreboard check
}
