// wide_stress — MAX-address-span toggle kernel.
//
// The toggle ceiling is dominated by two things: (1) write-through dead write-data
// fields (structural, excluded), and (2) constant HIGH bits of addresses/PC because
// prior programs used small (<=32 KB) working sets. This kernel attacks (2) on the
// DATA side — the only honestly reachable part: PC high bits cannot move (code cannot
// span GB), but DATA-ADDRESS high bits DO toggle if the working set is large.
//
// Strategy — WIDE + SPARSE (so address bits flip without runaway dense traffic):
//   - g_buf spans 1 MB (WSPAN bytes) -> data addresses flip up to ~bit 20
//     (toggle_stress' 32 KB only reached ~bit 15: +5 real address bits per bus).
//   - Touch ONE word per 64B cache line across the whole span -> every line is a
//     miss/fill (drives the 512-bit line-data bus + wide address) but total op count
//     stays ~= toggle_stress (no O(span^2) blow-up).
//   - 8 COMPLEMENTARY high-entropy patterns XORed with the address so both the data
//     bits AND the low/mid address bits flip 0<->1 and 1<->0.
//
// Multi-core aware: TOTAL threads, each owns a strided disjoint set of lines.
// Deterministic + printf-free: each touched word's final value = PAT[last]^idx and
// out[tid] is a pure XOR reduction -> DUT-vs-SimX end-state compare is byte-exact.

#include <stdint.h>
#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <VX_config.h>      // NUM_CLUSTERS, NUM_CORES, NUM_WARPS, NUM_THREADS, MEM_BLOCK_SIZE

#define LINE_WORDS (MEM_BLOCK_SIZE / 4)                   // words per 64B cache line
#define WSPAN      (1u << 18)                             // 256 KB address span
#define NLINES     (WSPAN / MEM_BLOCK_SIZE)               // 4096 cache lines
#define BUFW       (NLINES * LINE_WORDS)                  // words backing the span
#define NPAT       8
#define TOTAL      (NUM_CLUSTERS * NUM_CORES * NUM_WARPS * NUM_THREADS)

// Consecutive patterns flip every bit; XOR with index adds per-word entropy.
static const uint32_t PAT[NPAT] = {
  0x00000000u, 0xFFFFFFFFu, 0xAAAAAAAAu, 0x55555555u,
  0xCCCCCCCCu, 0x33333333u, 0xF0F0F0F0u, 0x0F0F0F0Fu
};

typedef struct { uint32_t *buf; uint32_t *out; } ws_args_t;

volatile uint32_t g_buf[BUFW];
volatile uint32_t g_out[TOTAL];

static inline uint32_t sweep(uint32_t *buf, int tid, int total) {
  uint32_t acc = 0;
  for (int p = 0; p < NPAT; p++) {
    // write: this thread's strided lines get PAT[p] at the line's FIRST word
    // (one word per line = sparse; the address stride is what walks the high bits).
    for (int L = tid; L < NLINES; L += total) {
      int idx = L * LINE_WORDS;                 // first word of line L
      buf[idx] = PAT[p] ^ (uint32_t)idx;
    }
    // read-back: reload (miss after eviction across the 1 MB span) and XOR-reduce
    for (int L = tid; L < NLINES; L += total) {
      int idx = L * LINE_WORDS;
      acc ^= buf[idx];
    }
  }
  return acc;
}

void ws_kernel(ws_args_t *__UNIFORM__ args) {
  int tid = blockIdx.x;
  args->out[tid] = sweep(args->buf, tid, TOTAL);
}

int main() {
  ws_args_t args; args.buf = (uint32_t *)g_buf; args.out = (uint32_t *)g_out;
  uint32_t total = TOTAL;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)ws_kernel, &args);
  return 0;   // scoreboard (DUT vs SimX: g_buf touched words + g_out) is the authority
}
