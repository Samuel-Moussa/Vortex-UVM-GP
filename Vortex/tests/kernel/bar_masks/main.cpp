// bar_masks — partial/uniform-thread-mask BARRIER (bar SFU op) coverage.
//
// cross_sfu_threads shows the BAR op firing ONLY single-threaded (<bar,one_divergent>)
// across the whole suite: the barriers that occur are issued from single-thread runtime
// contexts. This kernel issues vx_barrier INSIDE peeled thread-mask regions so the BAR
// SFU op dispatches under partial[2]/partial[3]/uniform masks.
//
// Deadlock-safe by construction: the kernel spawns exactly ONE warp (N = threads/warp)
// and every barrier uses num_warps == 1, so each barrier is satisfied by this warp's own
// arrival and releases immediately — issuing it under a divergent (partial) thread mask
// cannot hang (no other warp is expected). The barrier is warp-level, so the diverged
// inactive lanes do not participate and reconvergence (vx_join) is unaffected.
//
// Deterministic + printf-free: the barrier has no data effect; out_buf is a plain
// function of (in, tid), identical on host recompute and device. (INV-1)

#include <vx_intrinsics.h>
#include <vx_spawn.h>

typedef struct { int *in; int *out; int nt; } bm_args_t;

#define OPQ(x) __asm__ volatile("" : "+r"(x))   // optimization barrier (real control flow)

// tid = intra-warp thread position. Peel one thread per nested level; a warp-local
// barrier (num_warps=1) fires inside each partial-mask region and at the uniform top.
static inline int bm(int r, int tid) {
  vx_barrier(0, 1);            OPQ(r);   // bar uniform  (all NT threads active)
  r += 1;

  if (tid < 3) { OPQ(r);                 // active {0,1,2} -> partial[3]
    vx_barrier(1, 1);          OPQ(r);   // bar partial[3]
    r += 2;
    if (tid < 2) { OPQ(r);               // active {0,1} -> partial[2]
      vx_barrier(2, 1);        OPQ(r);   // bar partial[2]
      r += 4;
      OPQ(r);
    }
    OPQ(r);
  }
  OPQ(r);
  return r;
}

// ONE warp only: the grid = threads-per-warp, so all lanes live in a single warp and
// every barrier's participant set is exactly this one warp (num_warps==1).
#define MAXNT 32
int in_buf[MAXNT];
volatile int out_buf[MAXNT];

void bm_kernel(bm_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;
  args->out[i] = bm(args->in[i], i & 3);
}

int main() {
  int nt = vx_num_threads();          // threads per warp -> exactly one warp spawned
  if (nt < 1)     nt = 1;
  if (nt > MAXNT) nt = MAXNT;
  for (int i = 0; i < nt; i++) { in_buf[i] = i * 7 + 1; out_buf[i] = 0; }

  bm_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;
  args.nt  = nt;

  uint32_t total = nt;                 // one warp's worth of threads
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)bm_kernel, &args);

  int errors = 0;
  for (int i = 0; i < nt; i++)
    if (out_buf[i] != bm(in_buf[i], i & 3)) errors++;
  return errors;   // out_buf[] is the DUT-vs-SimX scoreboard check
}
