// tcu_mt — multi-warp WMMA kernel to spread INST_TCU_WMMA across warps.
//
// tcu_test issues ONE warp-collective WMMA (single warp), so instr_class_cg_tcu
// cp_warp only ever sampled one wis value (25%). This kernel issues one collective
// WMMA per warp (total = NUM_THREADS * NUM_WARPS spawned as a flat grid → the
// runtime packs NUM_THREADS consecutive tasks into each hardware warp, so every
// warp runs a full-mask collective WMMA), filling all cp_warp bins.
//
// blockIdx.x is the global task id; for the NUM_THREADS lanes of one warp it is a
// contiguous block whose base is a multiple of NUM_THREADS (vx_spawn.c task
// striding), so tile = blockIdx.x / NUM_THREADS is identical across a warp's lanes
// and unique per warp → each warp writes its own output tile (no races).
//
// Deterministic + EXACT like tcu_test: A=bf16(1.0), B=bf16(2.0), C=fp32(0) →
// D[i][j] = 2*tileK, an exact integer in fp32 → byte-exact DUT-vs-SimX compare.

#include <VX_config.h>     // NUM_THREADS, NUM_WARPS  (⚠ FROZEN — see OBS-028)
#include <vx_intrinsics.h>  // vx_num_cores/warps/threads — runtime device query
#include <vx_spawn.h>
#include <vx_tensor.h>

namespace vt = vortex::tensor;
using ctx = vt::wmma_context<NUM_THREADS, vt::bf16, vt::fp32>;

static constexpr int TM = ctx::tileM;
static constexpr int TN = ctx::tileN;

// OBS-028 — WHY THIS KERNEL IS ONLY PARTLY RUNTIME-ADAPTIVE.
// NUM_THREADS is a TEMPLATE ARGUMENT of wmma_context above, so the tile geometry
// (tileM/tileN, fragment layout) is baked at COMPILE time. Unlike the grid, that
// cannot be re-derived at runtime — the type itself depends on it. And because
// VX_config.h is frozen at 1/1/4/4 and kernels are never rebuilt per config, this
// kernel is only STRUCTURALLY VALID at the compiled NUM_WARPS/NUM_THREADS.
// So: the CORE dimension is scaled at runtime (it is just a count), while warps and
// threads stay compile-time and are CHECKED at runtime by the guard in main().
// Without that guard a mismatch is invisible: DUT and SimX run the SAME kernel, so
// both produce the same wrong answer and the scoreboard passes.
#define MAX_CORES 8                       // static bound for the core dimension
float out_buf[MAX_CORES * NUM_WARPS * TM * TN];   // one output tile per warp per core

typedef struct { float *out; } tcu_args_t;

void tcu_kernel(tcu_args_t *__UNIFORM__ args) {
  int tile = blockIdx.x / NUM_THREADS;      // which warp (constant across the warp's lanes)

  ctx::fragment_a   a;
  ctx::fragment_b   b;
  ctx::fragment_acc c, d;
  ctx::fill_fragment(a, 1.0f);              // bf16 1.0
  ctx::fill_fragment(b, 2.0f);              // bf16 2.0
  ctx::fill_fragment(c, 0.0f);              // fp32 0.0
  ctx::mma_sync(d, a, b, c);                // <-- INST_TCU_WMMA (per warp)
  ctx::store_matrix_sync(args->out + tile * (TM * TN), d, TN);
}

int main() {
  // STRUCTURAL GUARD (OBS-028). The WMMA context is compiled for NUM_THREADS lanes
  // and this kernel indexes tiles by NUM_WARPS. If the elaborated hardware differs,
  // the kernel is invalid — and the scoreboard CANNOT catch it, because DUT and SimX
  // execute the identical binary and agree on the identical wrong result. Refuse to
  // run instead, leaving out_buf at its .bss zeros so the divergence is obvious.
  if ((int)vx_num_threads() != NUM_THREADS || (int)vx_num_warps() != NUM_WARPS)
    return 1;   // rebuild with CONFIGS="-DNUM_WARPS=n -DNUM_THREADS=n" for this config

  // out_buf NOT zeroed here: it is .bss (already zero) and main() runs on EVERY
  // core, so a core still initialising would wipe another core's tile (OBS-026).
  tcu_args_t args; args.out = out_buf;
  // Scale the CORE dimension at runtime; warps/threads are structural (see above).
  uint32_t total = (uint32_t)vx_num_cores() * (uint32_t)NUM_WARPS * (uint32_t)NUM_THREADS;
  uint32_t cap   = (uint32_t)MAX_CORES * NUM_WARPS * NUM_THREADS;
  if (total > cap) total = cap;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)tcu_kernel, &args);
  return 0;   // scoreboard (DUT vs SimX out_buf) is the authority
}
