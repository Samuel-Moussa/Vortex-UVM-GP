// vecadd_lite — printf-free multi-warp vector add.
//
// Same structure as tests/kernel/vecadd (hostless: builds args, vx_spawn_threads),
// but with NO per-thread / per-element vx_printf. The original vecadd spends
// ~millions of cycles in vx_printf console IO (each char is a fenced MMIO write),
// which is why it exceeds the UVM bench timeout (INV-1 was slowness, not a hang —
// native simx completes it in ~4.2M cycles). This variant does the same SIMT
// spawn + compute and writes results to memory for the DUT-vs-SimX scoreboard,
// so it completes in thousands of cycles AND exercises multi-warp/divergence
// coverage (vx_spawn worker warps).

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N 16

typedef struct {
  int *src0;
  int *src1;
  int *dst;
  int  num_elements;
} vecadd_args_t;

void vecadd_kernel(vecadd_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;
  args->dst[i] = args->src0[i] + args->src1[i];   // no printf — pure compute
}

// Static device buffers (no malloc/printf noise). Result region is what the
// scoreboard compares against SimX.
int g_src0[N];
int g_src1[N];
volatile int g_dst[N];
volatile int g_status;

int main() {
  for (int i = 0; i < N; i++) {
    g_src0[i] = i * 2;
    g_src1[i] = i * 3;
    g_dst[i]  = 0;
  }

  vecadd_args_t args;
  args.src0 = g_src0;
  args.src1 = g_src1;
  args.dst  = (int*)g_dst;
  args.num_elements = N;

  uint32_t total_threads = N;
  vx_spawn_threads(1, &total_threads, nullptr,
                   (vx_kernel_func_cb)vecadd_kernel, &args);

  // single-thread self-check, result to memory (no printf)
  int errors = 0;
  for (int i = 0; i < N; i++)
    if (g_dst[i] != g_src0[i] + g_src1[i]) errors++;
  g_status = (errors == 0) ? 0x600DC0DE : 0xBADC0DE;
  return errors;
}
