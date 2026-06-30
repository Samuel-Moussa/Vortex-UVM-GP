// axi_stress — printf-free, CONFIG-AWARE memory-latency stress kernel
// (Samuel — coverage push, gap-map item A1).
//
// PURPOSE: drive cp_id_route / cross_type_route to ~100%. The AXI master's read
// tag = tbuf_waddr = CLOG2(TAG_BUFFER_SIZE=16) slot index; with only a few
// outstanding reads the adapter reuses low slots (0..3), so route values
// 4,6,8,10,12,14 stay unhit. The write tag (awid=mem_req_tag) is odd and only
// 1,3,..21 had been seen — 23,27,31 stayed unhit. Reaching the high tbuf slots
// and high write tags needs MANY *simultaneously outstanding*, NON-COALESCING
// memory transactions.
//
// HOW: spawn one logical thread per HARDWARE thread (cores x warps x threads,
// read from CSRs -> config-aware, NOT hardcoded). Every thread issues K scattered
// loads and K scattered stores, each in a DISTINCT 64B cache line (STRIDE = one
// line). Nothing coalesces, so each access is its own L2->AXI request; with the
// whole machine's threads issuing at once there are >=16 reads/writes in flight,
// filling the tag buffer's high slots and advancing the write-tag counter.
//
// CONFIG-AWARE: thread count derives from vx_num_cores/warps/threads at runtime.
// Static buffers are sized to MAX_NT (a compile-time cap); only the active
// nt*K*STRIDE portion is initialised/used, so init cost scales with the real
// config rather than the cap. Buffer span is bounded by elaboration-safe MAX_*.
//
// Deterministic + printf-free: g_out is what the scoreboard compares DUT-vs-SimX.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

// Compile-time cap for static buffer sizing. Kept SMALL on purpose: the whole
// MAX_NT*K*STRIDE buffer lands in .bss and crt0 zeroes it ALL at startup before
// main (regardless of the runtime nt), so an oversized cap turns into a giant
// startup memset that dominates the run. 16 = the primary config; larger configs
// clamp nt to 16, which already over-saturates the 16-slot tag buffer when every
// thread keeps K independent loads in flight. Bump only with a timeout bump too.
#define MAX_NT   16
#define K        4           // INDEPENDENT loads per thread -> per-thread ILP
// STRIDE in ints. 32 ints = 128 bytes: with PLATFORM_MEMORY_NUM_BANKS=2 (bank
// select = addr[6] for a 64B line), every access offset is a multiple of 128B so
// addr[6]=0 -> ALL accesses land on the SAME memory bank's tag buffer, while
// still hitting distinct cache lines. Concentrating on one port is what lets the
// outstanding count climb past 3: the VX_allocator priority-encoder hands out the
// lowest free slot, so slot N is only reached when N+1 reads are simultaneously
// in flight on that one port. Spreading across banks (stride=1 line) caps it ~3.
#define STRIDE   32
#define MAX_SPAN (MAX_NT * K * STRIDE + STRIDE)
#define MAX_OUT  (MAX_NT * K * STRIDE)

typedef struct {
  int *in;
  int *out;
  int  nt;      // runtime thread count (uniform across the spawn)
} stress_args_t;

// Each thread issues K INDEPENDENT same-bank loads (no acc dependency chain, so
// all K can be outstanding at once), then writes K same-bank stores. With nt
// threads x K independent loads all funnelling to one memory port, the port's
// tag buffer fills its high slots (route 4,6,8,10,12,14) and the write-tag
// counter advances far enough to reach the high odd write IDs (23,27,31).
void stress_kernel(stress_args_t *__UNIFORM__ args) {
  int t  = blockIdx.x;
  int nt = args->nt;
  int v[K];
  #pragma unroll
  for (int k = 0; k < K; k++)
    v[k] = args->in[(k * nt + t) * STRIDE];   // K independent loads, same bank
  int acc = 0;
  #pragma unroll
  for (int k = 0; k < K; k++) {
    acc += v[k];
    args->out[(t * K + k) * STRIDE] = acc;     // K same-bank stores, varied tags
  }
}

int g_in [MAX_SPAN];
volatile int g_out[MAX_OUT];
volatile int g_status;

int main() {
  // Config-aware: one logical thread per HW thread on this build's topology.
  int nt = vx_num_cores() * vx_num_warps() * vx_num_threads();
  if (nt < 1)       nt = 1;
  if (nt > MAX_NT)  nt = MAX_NT;

  int span = nt * K * STRIDE + STRIDE;   // input lines actually touched
  int outn = nt * K * STRIDE;            // output lines actually touched

  for (int i = 0; i < span; i++) g_in[i]  = (i * 7 + 1);
  for (int i = 0; i < outn; i++) g_out[i] = 0;

  stress_args_t args;
  args.in  = g_in;
  args.out = (int*)g_out;
  args.nt  = nt;

  uint32_t total_threads = nt;
  vx_spawn_threads(1, &total_threads, nullptr,
                   (vx_kernel_func_cb)stress_kernel, &args);

  // single-thread self-check: recompute the per-thread prefix sums, compare mem.
  int errors = 0;
  for (int t = 0; t < nt; t++) {
    int acc = 0;
    for (int k = 0; k < K; k++) {
      acc += g_in[(k * nt + t) * STRIDE];
      if (g_out[(t * K + k) * STRIDE] != acc) errors++;
    }
  }
  g_status = (errors == 0) ? 0x600DC0DE : 0xBADC0DE;
  return errors;
}
