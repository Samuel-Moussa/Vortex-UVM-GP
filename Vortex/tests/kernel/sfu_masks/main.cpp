// sfu_masks — partial/uniform-thread-mask CSR-write (csrrw / csrrc) coverage.
//
// cross_sfu_threads shows csrrs (CSR READ), split, join, pred, tmc firing under
// every thread mask (one_divergent / partial[2] / partial[3] / uniform), but the
// CSR-WRITE ops csrrw and csrrc fire ONLY single-threaded (one_divergent) across
// the whole 34-run suite — because the only csrrw/csrrc in normal programs are the
// single-thread FP-CSR setup emitted by crt0 before the SIMT region spreads. No
// kernel writes a CSR from inside a multi-thread region.
//
// This kernel does exactly that: peels threads like diverge_fpu and issues a
// register-form csrrw (csr_swap) and csrrc (csr_read_clear) on the standard FP CSRs
// (FRM=0x002, FFLAGS=0x001 — SimX handles these in emulator.cpp set_csr/get_csr)
// INSIDE the uniform, partial[3] and partial[2] regions, so those ops dispatch to
// EX_SFU under a partial thread mask. Non-constant operands force the register form
// (csrrw/csrrc, not csrrwi/csrrci).
//
// Scoreboard safety: the CSR return values are folded as `(x & 0) == 0`, so out_buf
// NEVER depends on fcsr. This is important — fcsr is per-warp, so a multi-thread CSR
// write has HW-defined conflict resolution that need not match SimX; folding to 0
// makes the compared memory state independent of it. No FP arithmetic -> no rounding
// / exception-flag nondeterminism. out_buf is a deterministic function of (in, tid),
// identical on host recompute and device. printf-free (INV-1).

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N 64                     // 16 warps x 4 threads
#define CSR_FFLAGS 0x001
#define CSR_FRM    0x002

typedef struct { int *in; int *out; } sm_args_t;

#define OPQ(x) __asm__ volatile("" : "+r"(x))   // optimization barrier (real control flow)

// tid = intra-warp thread position (0..NT-1). Strictly-decreasing thresholds peel
// one thread per nested level; a register-form csrrw + csrrc execute inside each
// partial-mask region (and at the uniform top level).
static inline int sfm(int r, int tid) {
  // UNIFORM region — all NT threads active.
  unsigned w = csr_swap(CSR_FRM, (unsigned)(r & 0x3));          OPQ(w);  // csrrw uniform
  unsigned c = csr_read_clear(CSR_FFLAGS, (unsigned)((r & 0x1f) | 1)); OPQ(c);  // csrrc uniform
  r += (int)((w & 0) + (c & 0)) + 1;                            OPQ(r);

  if (tid < 3) { OPQ(r);                                        // active {0,1,2} -> partial[3]
    unsigned w3 = csr_swap(CSR_FRM, (unsigned)(r & 0x3));           OPQ(w3);  // csrrw partial[3]
    unsigned c3 = csr_read_clear(CSR_FFLAGS, (unsigned)((r & 0x1f) | 2)); OPQ(c3);  // csrrc partial[3]
    r += (int)((w3 & 0) + (c3 & 0)) + 2;

    if (tid < 2) { OPQ(r);                                      // active {0,1} -> partial[2]
      unsigned w2 = csr_swap(CSR_FRM, (unsigned)(r & 0x3));           OPQ(w2);  // csrrw partial[2]
      unsigned c2 = csr_read_clear(CSR_FFLAGS, (unsigned)((r & 0x1f) | 4)); OPQ(c2);  // csrrc partial[2]
      r += (int)((w2 & 0) + (c2 & 0)) + 4;
      OPQ(r);
    }
    OPQ(r);
  }
  OPQ(r);
  return r;
}

int in_buf[N];
volatile int out_buf[N];

void sfm_kernel(sm_args_t *__UNIFORM__ args) {
  int i   = blockIdx.x;
  int tid = i & 3;                         // low bits = thread position within the warp
  args->out[i] = sfm(args->in[i], tid);
}

int main() {
  for (int i = 0; i < N; i++) { in_buf[i] = i * 7 + 1; out_buf[i] = 0; }

  sm_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)sfm_kernel, &args);

  int errors = 0;
  for (int i = 0; i < N; i++)
    if (out_buf[i] != sfm(in_buf[i], i & 3)) errors++;
  return errors;   // out_buf[] is the DUT-vs-SimX scoreboard check
}
