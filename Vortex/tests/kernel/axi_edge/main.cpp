// axi_edge — minimal directed kernel for the system_axi_cross idle<->busy EDGE bins.
//
// Targets the 6 uncovered system_axi_cross tuples:
//   <idle_to_busy, read_only>   : an icache-fetch AXI read at the launch edge (busy 0->1)
//   <busy_to_idle, write_only>  : the final store's AXI write beat draining as busy 1->0
//   <idle,        write_only>   : that write beat still on the bus after busy has dropped
//   (+ read/write symmetric variants)
//
// These are TIMING-coincidence bins (system_cg samples @(posedge clk) every cycle, so it
// is not a sampling gap) — the AXI transaction must land in the exact cycle the busy
// signal toggles. A TINY kernel makes the idle<->busy edges dominate the (few) executed
// cycles and keeps a store in flight right at the busy->idle drain, maximising the overlap
// probability. No compute, no loops: literally store constants and exit.
//
// Deterministic + printf-free (INV-1): out_buf holds fixed constants, identical on host
// recompute and device -> DUT-vs-SimX scoreboard-safe.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define N 4                       // one warp's worth of lanes -> clean single launch edge

volatile int out_buf[N];

// The whole kernel body: a single store per lane (x = 5-family constant). The store's
// AXI write beat is the last bus activity before the core idles -> busy->idle edge write.
void ae_kernel(void *__UNIFORM__ /*unused*/) {
  int i = blockIdx.x;
  out_buf[i] = 5 + i;             // x = 5  (deterministic constant)
}

int main() {
  for (int i = 0; i < N; i++) out_buf[i] = 0;

  uint32_t total = N;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)ae_kernel, nullptr);
  return 0;   // scoreboard (DUT vs SimX out_buf) is the authority
}
