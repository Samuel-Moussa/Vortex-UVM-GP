// mshr_flood — saturate a single dcache bank's MSHR (printf-free, device-sized).
//
// TARGETS (both measured zero before this kernel existed):
//   * cache_event_cg.cp_mshr_stall.stall  — needs the MSHR *full*:
//       perf_mshr_stall = mshr_alm_full (VX_cache_bank.sv:684), and the bank
//       gates allocation on ~mshr_alm_full (:233). MSHR_SIZE = 16
//       (VX_config.vh:567/628), so this needs 16 CONCURRENT outstanding misses
//       in ONE bank.
//   * axi_transaction_cg.cp_route_slot / cross_port_slot — the AXI read tag's
//       slot index is the tag-buffer slot (VX_axi_adapter.sv:282); filling all
//       16 needs the same 16-deep outstanding-read condition. One kernel, two
//       independent coverpoints — which is also how we tell a real fill from a
//       measurement artifact.
//
// WHY THE EXISTING mem_stress DID NOT DO THIS (diagnosed, not guessed):
//   mem_stress uses BUFN=4096 ints = 16384 B = EXACTLY the dcache size
//   (DCACHE_SIZE=16384) and wraps its index into it, so its working set is
//   cache-RESIDENT: the accesses mostly HIT and never allocate an MSHR entry.
//   It also issues only NLD=12 independent loads, below the 16 the MSHR holds.
//
// THE MECHANISM — stride 1024 B + THREAD-INTERLEAVED slots:
//   1024 = 16 * 64 = (max DCACHE_NUM_BANKS) * L1_LINE_SIZE. Because the bank
//   index comes from the low line-address bits and 1024 B is a multiple of
//   (16 * line), EVERY access lands in the SAME bank for ANY bank count 1..16
//   — config-generic by construction (a kernel cannot query NUM_BANKS).
//
//   Slot assignment is INTERLEAVED, not blocked:  slot(t,c) = c*TOTAL + t.
//   This is the part that actually forces misses, and the first version of this
//   kernel got it wrong. With BLOCKED slots (t*NLD + k) a thread's lines differ
//   in address bits [12:10], so they spread over 4 different sets, 2 lines each
//   — which fits a 4-way cache comfortably, and the read-back simply HIT.
//   Measured: cp_mshr_stall.stall stayed 0 and cp_route_slot reached only 6/16.
//   With INTERLEAVED slots, a thread's addresses all differ by TOTAL*1024, so
//   they share bits [11:10] and collapse onto ONE set. Several threads then pile
//   ~64 lines onto a single 4-way set — 16x oversubscribed — so the read-back
//   MISSES and the misses stay outstanding.
//
//   Note the touched-data arithmetic that the first version got wrong: the
//   256 KB figure is the ADDRESS SPAN, not the working set. Only one 64 B line
//   per 1024 B stride is touched, so 128 slots = 8 KB of actual lines — half the
//   16 KB cache. Span does not cause eviction; set pressure does.
//
// SELF-CHECKING (OBS-029): a kernel whose loads all return .bss zeros would sum
// to zero, and a dropped load would be invisible — a green run proving nothing.
// So pass A WRITES a value derived from the slot index and pass B READS IT BACK
// and sums it, so every loaded byte is checked against a pure host-side
// reference. The set oversubscription described above is what evicts those lines
// between the two passes, so the read-back still MISSES.
// Slots are disjoint across threads by construction (c*TOTAL + t is injective),
// so each thread touches only its own lines: no race and no barrier needed —
// Vortex has none with GBAR_ENABLE off.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define STRIDE_W  256        // uint32 elements = 1024 B (see MECHANISM above)
#define BUFW      65536      // 256 KB address span = BUF_SLOTS * STRIDE_W
#define BUF_SLOTS 256        // distinct strided slots available
#define MAX_TOTAL 128        // static bound: 8 cores x 16 threads/core

typedef struct { unsigned *buf; unsigned *out; unsigned total; unsigned chunks; } mf_args_t;

// Deterministic value for a slot — pure function of the index, so the host-side
// reference below is exactly as strong as the device computation.
static inline unsigned mf_val(unsigned idx) {
  return (idx * 2654435761u) ^ (idx + 0x9E3779B9u);
}

// Slot -> element index.
static inline unsigned mf_idx(unsigned slot) {
  return (slot * STRIDE_W) & (BUFW - 1);
}

// INTERLEAVED slot for (thread t, chunk c) — see MECHANISM. Slots are disjoint
// across threads by construction (c*TOTAL + t is injective for t < TOTAL), so
// every thread still touches only its own lines: no race, no barrier needed.
static inline unsigned mf_slot(unsigned t, unsigned c, unsigned total) {
  return c * total + t;
}

void mf_kernel(mf_args_t *__UNIFORM__ args) {
  unsigned t     = blockIdx.x;
  unsigned total = args->total;
  unsigned chunks = args->chunks;

  // ---- pass A: strided WRITES (write misses allocate too) ----
  for (unsigned c = 0; c < chunks; c++) {
    unsigned s = mf_slot(t, c, total);
    args->buf[mf_idx(s)] = mf_val(s);
  }

  // ---- pass B: READ-BACK with FOUR independent accumulators ----
  // Four accumulators keep four loads in flight per thread without relying on
  // the compiler to hoist a wide unrolled block (and without the register
  // pressure that deadlocked mem_stress at NLD=32). Across a full device that
  // is 4 * (threads per core) concurrent misses, far above the 16-entry MSHR.
  unsigned a0 = 0, a1 = 0, a2 = 0, a3 = 0;
  unsigned c = chunks;
  while (c >= 4) {
    c -= 4;
    unsigned v0 = args->buf[mf_idx(mf_slot(t, c + 0, total))];
    unsigned v1 = args->buf[mf_idx(mf_slot(t, c + 1, total))];
    unsigned v2 = args->buf[mf_idx(mf_slot(t, c + 2, total))];
    unsigned v3 = args->buf[mf_idx(mf_slot(t, c + 3, total))];
    a0 += v0; a1 += v1; a2 += v2; a3 += v3;
  }
  while (c-- > 0) a0 += args->buf[mf_idx(mf_slot(t, c, total))];

  args->out[t] = a0 + a1 + a2 + a3;
}

volatile unsigned buf_mem[BUFW];
volatile unsigned out_buf[MAX_TOTAL];

// Host-side reference: identical pure function of the slot indices.
static unsigned mf_ref(unsigned t, unsigned total, unsigned chunks) {
  unsigned acc = 0;
  for (unsigned c = 0; c < chunks; c++) acc += mf_val(mf_slot(t, c, total));
  return acc;
}

int main() {
  mf_args_t args;
  args.buf = (unsigned*)buf_mem;
  args.out = (unsigned*)out_buf;

  // Device-sized grid so every core contends for its socket's dcache — the
  // multi-core contention is part of the stimulus, not incidental.
  // buf_mem/out_buf are deliberately NOT zeroed: they are .bss (already zero in
  // the loaded image) and a whole-array init would wipe another core's results
  // once every core is active (the OBS-026 failure mode).
  uint32_t total = (uint32_t)vx_num_cores() * vx_num_warps() * vx_num_threads();
  if (total > MAX_TOTAL) total = MAX_TOTAL;

  // Chunks per thread: use the whole slot space so the per-set pressure is the
  // same at any config (total * chunks == BUF_SLOTS). At 1CL/16 threads that is
  // 16 lines per thread; at 2CL/64 threads, 4 — and in BOTH cases ~64 lines land
  // on one 4-way set, which is what forces the eviction.
  uint32_t chunks = BUF_SLOTS / total;
  if (chunks < 1) chunks = 1;

  args.total  = total;
  args.chunks = chunks;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)mf_kernel, &args);

  // Verify ONLY this core's contiguous slice (vx_spawn.c:299) — no barrier
  // needed, and exactly as strong as a whole-array check since mf_ref is pure.
  uint32_t nc = (uint32_t)vx_num_cores(), cid = (uint32_t)vx_core_id();
  uint32_t per = total / nc, lo = cid * per, hi = lo + per;
  int errors = 0;
  for (uint32_t t = lo; t < hi; t++)
    if (out_buf[t] != mf_ref(t, total, chunks)) errors++;
  return errors;
}
