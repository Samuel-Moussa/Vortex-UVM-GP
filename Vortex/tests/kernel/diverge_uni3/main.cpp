// diverge_uni3 — UNIFORM split at divergence-stack depth 3.
//
// cross_dvg_depth shows every <divergent, d0..d3> and <uniform, d0..d2> covered,
// but NEVER <uniform, d3>: a split that FIRES BUT DOES NOT DIVERGE (all active
// threads agree -> is_dvg=0) while the IPDOM stack is already 3 deep. diverge_deep
// reaches depth 3 only via genuinely divergent splits, and its uniform splits sit
// at shallow depth. This kernel manufactures the missing tuple.
//
// Mechanism (4 threads/warp, DV_DEPTH_MAX = NUM_THREADS-1 = 3):
//   Three nested ASYMMETRIC real divergences peel the warp 3v1 -> 2v1 -> 1v1, so
//   each split has both sides non-empty (real divergence, pushes the stack) and
//   the stack reaches depth 3 with exactly ONE thread still active:
//       L1  if (tid != 3)   {0,1,2} | {3}     -> push, depth 1
//       L2  if (tid != 2)   {0,1}   | {2}      -> push, depth 2
//       L3  if (tid != 1)   {0}     | {1}      -> push, depth 3   (only tid0 active)
//   At depth 3 a FOURTH data-dependent branch executes with a single active thread,
//   so its then/else masks cannot both be non-empty -> is_dvg=0 (uniform), sampled
//   at depth 3 -> fills <uniform, d3>.
//
// The uniform branch is data-dependent (OPQ-barriered, non-constant) so the compiler
// emits a real split micro-op rather than if-converting it to predication.
//
// Deterministic + printf-free (INV-1): out_buf is a pure function of (v, tid),
// identical on host recompute and device -> DUT-vs-SimX scoreboard-safe.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N 64

typedef struct { int *in; int *out; } div_args_t;

#define OPQ(x) __asm__ volatile("" : "+r"(x))   // optimization barrier (real control flow)

// tid = intra-warp thread position (0..3). Asymmetric peel to depth 3, then a
// single-active-thread (=> uniform) split at that depth.
static inline int uni3(int v, int tid) {
  int r = v;
  if (tid != 3) { OPQ(r); r += 1;              // L1 divergent 3v1 -> depth 1
    if (tid != 2) { OPQ(r); r += 2;            // L2 divergent 2v1 -> depth 2
      if (tid != 1) { OPQ(r); r += 4;          // L3 divergent 1v1 -> depth 3 (only tid0)
        // depth 3, ONE active thread: a data-dependent branch here cannot diverge
        // (one side empty) -> is_dvg=0 UNIFORM split sampled at depth 3.
        if (v & 1) { OPQ(r); r = v * 3 + 1; }  // uniform split @ d3 (then)
        else       { OPQ(r); r = v * 5 + 2; }  // uniform split @ d3 (else)
        OPQ(r);
      } else       { OPQ(r); r -= 7; }         // tid1 else-side @ depth 2
    } else         { OPQ(r); r ^= 0x33; }      // tid2 else-side @ depth 1
  } else           { OPQ(r); r <<= 1; }        // tid3 else-side @ depth 0
  OPQ(r);
  return r;
}

int in_buf[N];
volatile int out_buf[N];

void div_kernel(div_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;
  args->out[i] = uni3(args->in[i], i & 3);   // low bits = thread position in warp
}

int main() {
  for (int i = 0; i < N; i++) { in_buf[i] = i * 7 + 1; out_buf[i] = 0; }

  div_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)div_kernel, &args);

  int errors = 0;
  for (int i = 0; i < N; i++)
    if (out_buf[i] != uni3(in_buf[i], i & 3)) errors++;
  return errors;   // out_buf[] is the DUT-vs-SimX scoreboard check
}
