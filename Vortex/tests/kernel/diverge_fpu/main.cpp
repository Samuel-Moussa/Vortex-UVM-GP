// diverge_fpu — partial-thread-mask FPU + SFU coverage.
//
// diverge_peel proved partial thread masks for INTEGER ALU ops. The per-class
// occupancy coverpoints for the FPU and SFU units (instr_class_cg_fpu /
// instr_class_cg_sfu cp_active_threads partial[2]/partial[3], and cross_sfu_threads)
// stay uncovered because our kernels only execute FP / CSR ops under a FULL warp
// mask. This kernel peels threads exactly like diverge_peel but executes an FP op
// (EX_FPU) and a CSR read (EX_SFU, VX_CSR_THREAD_ID via the safe csr_read intrinsic —
// a known Vortex core CSR, not an arbitrary privileged one) INSIDE each peeled
// region, so those ops dispatch under a partial thread mask.
//
// Scoreboard safety: FP inputs are small exact integers so `f` is exactly
// representable and (int)f is bit-exact between the DUT FPU and the SimX FP model
// (no tolerance needed). The CSR value is folded as `(s & 0)` == 0, so the divergent
// per-thread CSR result never changes the stored data — out_buf is a deterministic
// function of (in, tid), identical on host recompute and device. printf-free (INV-1).

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N 64                     // 16 warps x 4 threads

typedef struct { int *in; int *out; } df_args_t;

#define OPQ(x) __asm__ volatile("" : "+r"(x))   // optimization barrier (real control flow)

// tid = intra-warp thread position (0..NT-1). Strictly-decreasing thresholds peel
// one thread per nested level; FP + CSR ops execute inside each partial-mask region.
static inline int dfp(int r, int tid) {
  float f = (float)(r & 0x3ff);            // small & exactly representable in float
  if (tid < 3) { OPQ(r);                   // active {0,1,2} -> partial[3]
    f = f * 2.0f + 3.0f;                    // EX_FPU op under partial[3]
    int s = csr_read(VX_CSR_THREAD_ID); OPQ(s);   // EX_SFU op under partial[3]
    r += (int)f + (s & 0);                  // (s & 0) == 0: deterministic, coverage-only
    if (tid < 2) { OPQ(r);                 // active {0,1} -> partial[2]
      f = f * 1.5f - 1.0f;                  // EX_FPU op under partial[2]
      int s2 = csr_read(VX_CSR_THREAD_ID); OPQ(s2); // EX_SFU op under partial[2]
      r += (int)f + (s2 & 0);
      OPQ(r);
    }
    OPQ(r);
  }
  OPQ(r);
  return r;
}

int in_buf[N];
volatile int out_buf[N];

void dfp_kernel(df_args_t *__UNIFORM__ args) {
  int i   = blockIdx.x;
  int tid = i & 3;                         // low bits = thread position within the warp
  args->out[i] = dfp(args->in[i], tid);
}

int main() {
  for (int i = 0; i < N; i++) { in_buf[i] = i * 7 + 1; out_buf[i] = 0; }

  df_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)dfp_kernel, &args);

  int errors = 0;
  for (int i = 0; i < N; i++)
    if (out_buf[i] != dfp(in_buf[i], i & 3)) errors++;
  return errors;   // out_buf[] is the DUT-vs-SimX scoreboard check
}
