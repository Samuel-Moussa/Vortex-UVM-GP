// cache_tier — exercise each level of the cache hierarchy, including the HIT path
// of the optional L2 / L3 caches.
//
// WHY THIS EXISTS
//   L2 and L3 are PASSTHRU (pure bypass — VX_cache_wrap.sv:160 instantiates the real
//   VX_cache storage only when PASSTHRU==0) unless built with L2=1 / L3=1, so until
//   now they were never exercised at all. Even with them enabled, the existing suite
//   does not reach them meaningfully: every other kernel's working set is <= L1 and so
//   never leaves the socket, and the one large kernel (wide_stress) is sparse
//   single-touch, which produces cache FILLS but barely exercises the HIT path
//   (tag match / way select / hit-under-miss).
//
//   The ingredient that turns fills into HITS is REUSE: touch a working set sized to a
//   given level, then RE-READ it. This kernel does that, once per level.
//
// EVERYTHING IS PARAMETRIZED — no magic numbers. Spans are expressed as a RATIO of the
// real cache geometry (DCACHE_SIZE / L2_CACHE_SIZE from VX_config.h), so the kernel
// stays correct if the geometry is reconfigured, and every ratio is overridable from
// the terminal. Defaults are chosen to sit safely inside/outside the target level:
//
//   PHASE  SPAN                                    TARGET        DEFAULT
//   P1     DCACHE_SIZE   * CT_L1_NUM / CT_L1_DEN   L1 hits       1/2  of L1
//   P2     DCACHE_SIZE   * CT_L2_NUM / CT_L2_DEN   L2 hits       8x   of L1
//   P3     L2_CACHE_SIZE * CT_L3_NUM / CT_L3_DEN   L3 hits       3/2  of L2
//
// PHASES ARE OPT-IN (all OFF by default) so the default build costs nothing; enable the
// ones you want from the terminal, e.g.
//   make -C tests/kernel/cache_tier CT_P1=1 CT_P2=1
//   make -C tests/kernel/cache_tier CT_P2=1 CT_P3=1 CT_L3_NUM=7 CT_L3_DEN=4
// P3 moves ~1.5 MB through Ramulator and needs a multi-million-cycle timeout, which is
// why it is never on by default.
//
// SCOREBOARD SAFETY (deliberate, learned from OBS-009):
//   Threads own DISJOINT strided line sets and never read another thread's slice, so
//   there is NO cross-core sharing and therefore NO fenceless race. Vortex is a weak
//   coherent memory space (MICRO'21 §4.1.4 — coherence is the program's job via
//   fence/flush), so a kernel sharing data across cores without a fence would have no
//   architecturally-defined result and would be UNVERIFIABLE rather than useful. The
//   point here is to exercise cache LEVELS, not to re-prove weak coherence.
//   Every value is a pure function of its index => DUT-vs-SimX end-state is byte-exact.
//   printf-free (INV-1: console IO is what made kernels look like hangs).

#include <stdint.h>
#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <VX_config.h>      // NUM_*, MEM_BLOCK_SIZE, DCACHE_SIZE, L2_CACHE_SIZE

// ---- phase enables (all default OFF; turn on from the terminal) --------------
#ifndef CT_P1
#define CT_P1 0
#endif
#ifndef CT_P2
#define CT_P2 0
#endif
#ifndef CT_P3
#define CT_P3 0
#endif

// ---- span ratios, relative to the REAL cache geometry -----------------------
#ifndef CT_L1_NUM
#define CT_L1_NUM 1
#endif
#ifndef CT_L1_DEN
#define CT_L1_DEN 2          // 1/2 of L1  -> comfortably resident
#endif
#ifndef CT_L2_NUM
#define CT_L2_NUM 8
#endif
#ifndef CT_L2_DEN
#define CT_L2_DEN 1          // 8x L1      -> spills L1, well inside L2
#endif
#ifndef CT_L3_NUM
#define CT_L3_NUM 3
#endif
#ifndef CT_L3_DEN
#define CT_L3_DEN 2          // 3/2 of L2  -> spills L2, inside L3
#endif

// ---- number of write/read-back repetitions per phase ------------------------
// >1 deepens reuse (more hits) at linear cost. 1 is enough to exercise the hit path.
#ifndef CT_ITERS
#define CT_ITERS 1
#endif

#define WORD_BYTES  ((uint32_t)sizeof(uint32_t))
#define LINE_WORDS  (MEM_BLOCK_SIZE / WORD_BYTES)
#define TOTAL       (NUM_CLUSTERS * NUM_CORES * NUM_WARPS * NUM_THREADS)

#define P1_SPAN (CT_P1 ? ((uint32_t)DCACHE_SIZE   * CT_L1_NUM / CT_L1_DEN) : 0u)
#define P2_SPAN (CT_P2 ? ((uint32_t)DCACHE_SIZE   * CT_L2_NUM / CT_L2_DEN) : 0u)
#define P3_SPAN (CT_P3 ? ((uint32_t)L2_CACHE_SIZE * CT_L3_NUM / CT_L3_DEN) : 0u)

#define MAX2(a,b)  ((a) > (b) ? (a) : (b))
#define MAX_SPAN   MAX2(P1_SPAN, MAX2(P2_SPAN, P3_SPAN))
// Always allocate at least one line so the array is well-formed when all phases are off.
#define BUFW       (MAX_SPAN ? (MAX_SPAN / WORD_BYTES) : LINE_WORDS)

typedef struct { uint32_t *buf; uint32_t *out; } ct_args_t;

volatile uint32_t g_buf[BUFW];
volatile uint32_t g_out[TOTAL];

// One tier pass: write this thread's strided lines across `span`, then RE-READ them.
// The re-read is what produces hits at whichever level holds `span`.
// Returns an XOR reduction so the result depends on every value written.
static inline uint32_t tier_pass(uint32_t *buf, uint32_t span, int tid, int total, uint32_t salt) {
  const int nlines = (int)(span / MEM_BLOCK_SIZE);
  uint32_t acc = 0;
  if (nlines <= 0)
    return 0;
  for (int it = 0; it < CT_ITERS; ++it) {
    const uint32_t s = salt + (uint32_t)it;
    // write pass — one word per line keeps op count proportional to LINES, not bytes
    for (int L = tid; L < nlines; L += total) {
      int idx = L * LINE_WORDS;
      buf[idx] = (uint32_t)idx ^ s;
    }
    // read-back pass — same lines. For span <= level size these HIT at that level.
    for (int L = tid; L < nlines; L += total) {
      int idx = L * LINE_WORDS;
      acc ^= buf[idx];
    }
  }
  return acc;
}

void ct_kernel(ct_args_t *__UNIFORM__ args) {
  int tid = blockIdx.x;
  uint32_t acc = 0;
  // Salts are derived from the phase index (not magic constants) so each phase writes
  // a distinct value pattern into the same buffer.
  acc ^= tier_pass(args->buf, P1_SPAN, tid, TOTAL, 0x10000000u * 1u);
  acc ^= tier_pass(args->buf, P2_SPAN, tid, TOTAL, 0x10000000u * 2u);
  acc ^= tier_pass(args->buf, P3_SPAN, tid, TOTAL, 0x10000000u * 3u);
  args->out[tid] = acc;
}

int main() {
  ct_args_t args; args.buf = (uint32_t *)g_buf; args.out = (uint32_t *)g_out;
  uint32_t total = TOTAL;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)ct_kernel, &args);
  return 0;   // scoreboard (DUT vs SimX end-state) is the authority
}
