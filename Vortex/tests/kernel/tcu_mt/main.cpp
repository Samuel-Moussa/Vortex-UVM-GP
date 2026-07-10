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

#include <VX_config.h>     // NUM_THREADS, NUM_WARPS
#include <vx_spawn.h>
#include <vx_tensor.h>

namespace vt = vortex::tensor;
using ctx = vt::wmma_context<NUM_THREADS, vt::bf16, vt::fp32>;

static constexpr int TM = ctx::tileM;
static constexpr int TN = ctx::tileN;

// one output tile per warp
float out_buf[NUM_WARPS * TM * TN];

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
  for (int i = 0; i < NUM_WARPS * TM * TN; i++) out_buf[i] = 0.0f;
  tcu_args_t args; args.out = out_buf;
  uint32_t total = (uint32_t)NUM_THREADS * (uint32_t)NUM_WARPS;   // one warp-collective WMMA per warp
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)tcu_kernel, &args);
  return 0;   // scoreboard (DUT vs SimX out_buf) is the authority
}
