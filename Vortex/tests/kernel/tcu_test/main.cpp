// tcu_test — minimal directed TCU (WMMA) kernel to VERIFY the Tensor Core Unit.
//
// The suite never issued a TCU op, so VX_tcu_unit (+ the BHF bf16 datapath) was
// compiled but 0% covered and instr_class_cg_tcu had 0 samples. This kernel issues
// exactly one warp-collective WMMA (INST_TCU_WMMA) and stores the result to memory,
// where the scoreboard compares it against SimX's tensor_unit model.
//
// Deterministic + printf-free + EXACT: A = bf16(1.0), B = bf16(2.0), C = fp32(0) are
// all exactly representable, so D[i][j] = sum_k(1*2) = 2*tileK is an exact integer in
// fp32 -> byte-exact DUT-vs-SimX compare (no FP tolerance needed). Single warp
// (spawn total = NUM_THREADS) -> no multi-warp spawn distribution.

#include <VX_config.h>
#include <vx_intrinsics.h>     // NUM_THREADS
#include <vx_spawn.h>
#include <vx_tensor.h>

namespace vt = vortex::tensor;
using ctx = vt::wmma_context<NUM_THREADS, vt::bf16, vt::fp32>;

static constexpr int TM = ctx::tileM;
static constexpr int TN = ctx::tileN;

float out_buf[TM * TN];

typedef struct { float *out; } tcu_args_t;

void tcu_kernel(tcu_args_t *__UNIFORM__ args) {
  ctx::fragment_a   a;
  ctx::fragment_b   b;
  ctx::fragment_acc c, d;
  ctx::fill_fragment(a, 1.0f);              // bf16 1.0
  ctx::fill_fragment(b, 2.0f);              // bf16 2.0
  ctx::fill_fragment(c, 0.0f);              // fp32 0.0
  ctx::mma_sync(d, a, b, c);                // <-- INST_TCU_WMMA
  ctx::store_matrix_sync(args->out, d, TN); // row-major, ldm = TN
}

int main() {
  // STRUCTURAL GUARD (OBS-028): the WMMA context is a TEMPLATE on NUM_THREADS, so
  // the tile geometry is fixed at compile time, and VX_config.h is frozen at 4
  // because kernels are never rebuilt per config. If the elaborated hardware has a
  // different warp width this kernel is invalid — and the scoreboard cannot detect
  // it, since DUT and SimX run the same binary and agree on the same wrong answer.
  if ((int)vx_num_threads() != NUM_THREADS)
    return 1;   // rebuild with CONFIGS="-DNUM_THREADS=n" for this config

  for (int i = 0; i < TM * TN; i++) out_buf[i] = 0.0f;
  tcu_args_t args; args.out = out_buf;
  uint32_t total = NUM_THREADS;             // exactly one warp
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)tcu_kernel, &args);
  return 0;   // scoreboard (DUT vs SimX out_buf) is the authority
}
