// diverge_lite — printf-free multi-warp kernel that DIVERGES threads.
//
// Purpose: drive the warp-state covergroups (divergence_cg / reconverge_cg /
// sched_state_cg / tmc_cg / wspawn_cg) and the partial/uniform thread-mask bins,
// which need data-dependent control flow across threads (SIMT divergence +
// reconvergence). printf-free so it completes fast (INV-1 lesson). Results to
// memory for the DUT-vs-SimX scoreboard.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N 32

typedef struct {
  int *in;
  int *out;
} div_args_t;

// Per-thread data-dependent branches => threads in the same warp take different
// paths => SIMT split/reconverge. Nested branch gives split-depth > 1.
void diverge_kernel(div_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;
  int v = args->in[i];
  int r;
  if (v & 1) {                 // odd/even split
    if (v & 2) r = v * 3 + 1;  // nested split (depth 2)
    else       r = v * 5;
  } else {
    if (v & 4) r = v - 7;      // nested split on the else side
    else       r = v + 100;
  }
  // a small data-dependent loop => variable active-thread counts over time
  for (int k = 0; k < (i & 3); k++) r += k;
  args->out[i] = r;            // reconverge, then store
}

int in_buf[N];
volatile int out_buf[N];

static int ref(int v, int i) {
  int r;
  if (v & 1) { if (v & 2) r = v*3+1; else r = v*5; }
  else       { if (v & 4) r = v-7;   else r = v+100; }
  for (int k = 0; k < (i & 3); k++) r += k;
  return r;
}

int main() {
  for (int i = 0; i < N; i++) { in_buf[i] = i * 7 + 1; out_buf[i] = 0; }

  div_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)diverge_kernel, &args);

  int errors = 0;
  for (int i = 0; i < N; i++)
    if (out_buf[i] != ref(in_buf[i], i)) errors++;
  return errors;   // out_buf[] is the DUT-vs-SimX scoreboard check (no late sentinel store)
}
