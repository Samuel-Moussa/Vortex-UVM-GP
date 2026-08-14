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
// Static bound for out_buf now that the grid scales with the device.
#define MAX_TOTAL 128            // 8 cores x 16 threads/core

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

volatile int out_buf[MAX_TOTAL];

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
  // CONFIG-ADAPTIVE GRID (was `total = N` = 16 = exactly ONE core's capacity, so
  // vx_spawn_threads computed needed_cores=1 and idled every other core —
  // vx_spawn.c:274-279). Size it from the DEVICE so every core participates at
  // any NCL/NC/NW/NT.
  // out_buf is DELIBERATELY NOT zeroed here: it is .bss and already zero in the
  // loaded image, and once every core has work a core still in its init loop
  // would wipe results another core had already written (the OBS-026 failure).
  fpu_args_t args; args.out = (int*)out_buf;
  uint32_t total = (uint32_t)vx_num_cores() * vx_num_warps() * vx_num_threads();
  if (total > MAX_TOTAL) total = MAX_TOTAL;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)fpu_kernel, &args);
  // Verify ONLY this core's slice. vx_spawn distributes tasks CONTIGUOUSLY
  // (all_tasks_offset = core_id * tasks_per_core, vx_spawn.c:299), so core c
  // owns [lo,hi) and never reads a slice another core is still writing. That is
  // what makes this safe with no global barrier - Vortex has none with
  // GBAR_ENABLE off (VX_wctl_unit.sv:138). ref(i) is a pure function of i, so a
  // per-core check is exactly as strong as the whole-array one used to be.
  uint32_t nc = (uint32_t)vx_num_cores(), cid = (uint32_t)vx_core_id();
  uint32_t per = total / nc, lo = cid * per, hi = lo + per;
  int errors = 0;
  for (uint32_t i = lo; i < hi; i++) if (out_buf[i] != ref((int)i)) errors++;
  return errors;
}
