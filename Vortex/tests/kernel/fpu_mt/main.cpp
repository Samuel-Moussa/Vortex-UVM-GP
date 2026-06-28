// fpu_mt — multi-threaded FP kernel (printf-free).
//
// Drives the FPU covergroup's UNIFORM / PARTIAL thread-mask bins (instr_class_cg_fpu),
// which fpu_test (single-thread) could not reach. Threads run FP ops across the
// full warp (vx_spawn_threads) so the FPU EX unit dispatches with all threads
// active (uniform) and, via a data-dependent branch, with subsets active (partial).
//
// Rounding-SAFE result: each thread reduces its FP work to an integer via FP
// COMPARES (feq/flt produce exact 0/1, no rounding) so the stored result matches
// DUT vs SimX exactly — avoiding the 1-ULP/denormal FP-compare divergence that
// fpu_test surfaced. Coverage comes from the FP *dispatch*, not the stored value.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N 16

typedef struct { int *out; } fpu_args_t;

void fpu_kernel(fpu_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;
  float a = (float)i + 0.5f;
  float b = 1.25f;

  float s  = a + b;            // fadd.s  (uniform: all threads)
  float p  = a * b;            // fmul.s
  float q  = a / b;            // fdiv.s
  float r  = __builtin_sqrtf(a + 1.0f);   // fsqrt.s
  float m  = __builtin_fmaf(a, b, b);     // fmadd.s

  // data-dependent FP branch => PARTIAL thread masks on the FP path
  int flag;
  if (a < 4.0f) {             // fcmp (flt) — exact
    flag = (s > p) ? 1 : 0;   // more fcmp
  } else {
    flag = (q < m) ? 2 : 3;   // fcmp on the other path
  }
  // round-safe reduction: only integer comparisons stored
  args->out[i] = flag + (int)(r > 1.0f);   // fcmp -> exact 0/1
}

volatile int out_buf[N];

static int ref(int i) {
  float a = (float)i + 0.5f, b = 1.25f;
  float s = a + b, p = a * b, q = a / b;
  float r = __builtin_sqrtf(a + 1.0f), m = __builtin_fmaf(a, b, b);
  int flag;
  if (a < 4.0f) flag = (s > p) ? 1 : 0;
  else          flag = (q < m) ? 2 : 3;
  return flag + (int)(r > 1.0f);
}

int main() {
  for (int i = 0; i < N; i++) out_buf[i] = 0;
  fpu_args_t args; args.out = (int*)out_buf;
  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)fpu_kernel, &args);
  int errors = 0;
  for (int i = 0; i < N; i++) if (out_buf[i] != ref(i)) errors++;
  return errors;
}
