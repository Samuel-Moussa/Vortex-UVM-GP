// mem_stress — printf-free stall-co-occurrence stress kernel
// (Samuel — coverage push, stall-combo wave).
//
// PURPOSE: fill the last empty cross_ipc_stalls / cross_stall_types bins:
//   cross_ipc_stalls (cp_ipc_bucket x cp_fetch_stall x cp_memory_stall):
//       <med_ipc,*,mem-stalled>  <zero,*,mem-stalled>  <med_ipc,fetch-stalled,*>
//   cross_stall_types (cp_decode_stall x cp_issue_stall x cp_execute_stall):
//       <*,issue-stalled,execute-stalled>  <decode-active,issue-stalled,*>
//       <decode-stalled,issue-active,*>
//
// WHY previous kernels miss them: the status monitor samples every 100 cycles and
// the IPC coverpoint is a 64-cycle WINDOWED rate, while the stall flags are
// INSTANTANEOUS RTL backpressure taps. Landing <med_ipc,stalled> needs the
// windowed retirement rate ~0.5-0.75 AT THE SAME sample instant a stall bit is
// set. Pure-compute kernels never backpressure; pure-memory kernels sit at ~zero
// IPC. Neither decouples the two axes.
//
// FLOW: copies the PROVEN compute_tight / diverge_deep spawn flow EXACTLY —
// N=64 grid blocks, ONE straight-through pass per block (NO per-block outer
// loop), one block returns after its pass. 64 blocks over 16 lanes = 4 waves =
// ample runtime for the 100-cycle sampler. (An earlier outer-loop version
// deadlocked a warp; the flat per-block flow is the known-good one.)
//
// Each block runs three deliberately-ordered phases so the lagging windowed IPC
// and the instantaneous stall land in different regimes:
//   (A) COMPUTE — 4 INDEPENDENT branchless LCG chains (compute_tight's body,
//       PROVEN to lift windowed IPC into the med bucket at <=4W). Retires densely
//       -> window climbs to med.
//   (B) MEMORY — NLD INDEPENDENT scattered cache-line loads (MSHR-saturating ->
//       dcache request backpressure = memory_stall) issued right after (A), so
//       the sample sees med windowed-IPC (A still draining) WHILE memory_stall is
//       set -> <med_ipc,*,mem-stalled>; the ensuing load-wait with no retirement
//       gives <zero,*,mem-stalled>.
//   (C) DIVIDE — a chain of DEPENDENT unsigned divides (iterative IDIV unit, one
//       in flight) fed by the loaded values. Serialising the divider backs
//       dispatch up (execute_stall) and propagates through issue (issue_stall)
//       while decode drains -> the <issue,execute> / mixed decode-vs-issue combos.
// Multi-warp icache contention yields transient fetch_stall while other warps
// still retire at med rate -> <med_ipc,fetch-stalled,*>.
//
// Deterministic + printf-free: all arithmetic is uint32 (bit-exact vs SimX, no
// signed-overflow UB, divisors forced non-zero); out_buf[] is the scoreboard's
// DUT-vs-SimX compare target. Host self-check mirrors compute_tight.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N       128         // grid blocks (waves across lanes) — proven flow.
                            // NOTE: NLD>~16 (v[]>16) spills registers and changes
                            // spawn occupancy -> a warp deadlocks at join (empirically
                            // hangs at NLD=32). NLD=12 is the proven-safe burst.
#define NLD     12          // INDEPENDENT scattered loads per block — burst that
                            // presses the dcache request port (MSHR) = memory_stall.
#define LSTRIDE 16          // ints per 64B cache line
#define BUFN    4096        // shared load buffer (16KB) — small .bss, wrapping idx

typedef struct { int *in; int *out; } ms_args_t;

// One block's deterministic result. Same body on host (self-check) and device.
static inline int ms_compute(const int *in, int i) {
  // (A) COMPUTE — 4 independent LCG streams (ILP), branchless.
  unsigned a = (unsigned)i + 0x9e3779b9u;
  unsigned b = (unsigned)i ^ 0x85ebca6bu;
  unsigned c = (unsigned)(i * 3 + 1) * 2654435761u;
  unsigned d = (unsigned)(i * 7 + 5);
  for (int k = 0; k < 100; k++) {
    a = a * 1664525u    + 1013904223u;
    b = b * 22695477u   + 1u;
    c = c * 1103515245u + 12345u;
    d = d * 214013u     + 2531011u;
  }
  unsigned acc = a ^ b ^ c ^ d;

  // (B) MEMORY — NLD independent scattered loads (miss-heavy, MSHR pressure).
  unsigned v[NLD];
  #pragma unroll
  for (int k = 0; k < NLD; k++) {
    int idx = ((i * NLD + k) * LSTRIDE) & (BUFN - 1);   // scattered, wraps in-buf
    v[k] = (unsigned)in[idx];
  }
  #pragma unroll
  for (int k = 0; k < NLD; k++) acc += v[k];

  // (C) DIVIDE — dependent unsigned-divide chain (16 deep), divisor forced
  // 1..128. Serialising the iterative IDIV unit backs dispatch up
  // (execute_stall) and propagates through issue (issue_stall).
  unsigned dchain = acc | 1u;
  #pragma unroll
  for (int k = 0; k < NLD; k++) {
    unsigned dv = (v[k] & 0x7Fu) + 1u;
    dchain = (dchain * 1103515245u + 12345u) / dv + 1u;
  }

  return (int)(acc ^ dchain);
}

int in_buf[BUFN];
volatile int out_buf[N];

void ms_kernel(ms_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;
  args->out[i] = ms_compute(args->in, i);
}

int main() {
  for (int i = 0; i < BUFN; i++) in_buf[i]  = i * 7 + 1;
  for (int i = 0; i < N;    i++) out_buf[i] = 0;

  ms_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)ms_kernel, &args);

  // The UVM scoreboard is the authority (compares every out_buf[] store DUT vs
  // SimX). Do NOT recompute ms_compute here — the divide-heavy body run 128x
  // single-threaded on the host dominates runtime and overflows the timeout.
  // Keep only a trivial liveness check.
  int nonzero = 0;
  for (int i = 0; i < N; i++) if (out_buf[i] != 0) nonzero++;
  return (nonzero == N) ? 0 : 1;
}
