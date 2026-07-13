// mem_zero — compute-free memory-saturation kernel for the ZERO-IPC-during-mem-stall bin.
//
// Fills cross_ipc_stalls <zero,*,mem-stalled>: the windowed IPC bucket reads ZERO
// (<0.01, nothing retiring for a full window) AT THE SAME sample as memory_stall=1
// (dcache request backpressure). mem_stress deliberately adds a 100-iter LCG compute
// to lift IPC into the med bucket, so it never dips to zero while stalled; cache_stress
// runs big-text functions between bursts for the same reason. This kernel removes ALL
// masking compute so that during MSHR saturation there is genuinely nothing to retire.
//
// Mechanism: a LARGE grid (N=128 blocks) each issuing a wide INDEPENDENT scattered-load
// burst with NO arithmetic between/after beyond a bare dependent reduce. With many warps
// all requesting loads at once the MSHR stays full (memory_stall=1 across warps) while
// the long Ramulator return latency leaves the pipeline with no retirable instruction
// (windowed IPC -> 0). Dense status sampling (interval=10) lands inside those windows.
//
// NLD=12 is the proven-safe burst width (>~16 spills registers and deadlocks spawn-join).
// Deterministic + printf-free (INV-1): out_buf[i] is a pure function of the (deterministic)
// scattered input, identical on host recompute and device -> DUT-vs-SimX scoreboard-safe.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N     128           // grid blocks — many concurrent warps saturate the MSHR
#define NLD   12            // independent scattered loads per block (proven-safe burst)
#define BUFN  4096          // 16KB shared load buffer, prime-strided -> miss-heavy
#define DMASK (BUFN - 1)

#define OPQ(x) __asm__ volatile("" : "+r"(x))

typedef struct { int *in; int *out; } mz_args_t;

int  in_buf[BUFN];
volatile int out_buf[N];

void mz_kernel(mz_args_t *__UNIFORM__ args) {
  int  i   = blockIdx.x;
  int *in  = args->in;
  int  b   = (i * 40503) & DMASK;      // per-block scatter base

  // Independent burst: 12 loads with no inter-load dependency -> fill the MSHR.
  int a0  = in[(b +    0) & DMASK];
  int a1  = in[(b +  331) & DMASK];
  int a2  = in[(b +  662) & DMASK];
  int a3  = in[(b +  997) & DMASK];
  int a4  = in[(b + 1327) & DMASK];
  int a5  = in[(b + 1663) & DMASK];
  int a6  = in[(b + 1993) & DMASK];
  int a7  = in[(b + 2333) & DMASK];
  int a8  = in[(b + 2663) & DMASK];
  int a9  = in[(b + 3001) & DMASK];
  int a10 = in[(b + 3331) & DMASK];
  int a11 = in[(b + 3671) & DMASK];
  // Bare dependent reduce — no other work; the pipe waits on the returns with nothing
  // else queued to retire -> zero-IPC window co-sampled with the MSHR-full memory_stall.
  int s = a0+a1+a2+a3+a4+a5+a6+a7+a8+a9+a10+a11;
  OPQ(s);
  args->out[i] = s;                    // DUT-vs-SimX scoreboard check
}

int main() {
  for (int i = 0; i < BUFN; i++) in_buf[i]  = (i * 2654435761u) ^ (i << 3);
  for (int i = 0; i < N;    i++) out_buf[i] = 0;

  mz_args_t args;
  args.in  = in_buf;
  args.out = (int*)out_buf;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)mz_kernel, &args);
  return 0;   // scoreboard (DUT vs SimX out_buf) is the authority
}
