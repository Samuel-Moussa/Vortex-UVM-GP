// div_edge — directed kernel for the integer divide/remainder CORNER branches
// (VX_serial_div.sv sign-negation / div-by-zero / overflow paths, VX_alu_int muldiv).
//
// Covers every RISC-V M-extension divide corner, all of which are architecturally
// defined (so DUT and SimX agree byte-exact):
//   * signed div/rem with all sign combinations (+/+, +/-, -/+, -/-)
//   * div-by-zero: div => -1, rem => dividend; divu => all-ones, remu => dividend
//   * overflow: INT_MIN / -1 => INT_MIN (div), 0 (rem)
//   * unsigned div/rem with MSB-set (large) operands
//
// Operands come from a volatile global array so the compiler cannot constant-fold the
// divides away — real div/rem instructions reach the serial divider. Each thread takes
// a rotated slice of the operand table so all lanes exercise the divider. Result is a
// pure integer reduction -> byte-exact end-state vs SimX (scoreboard authority).

#include <stdint.h>
#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <VX_config.h>

// OBS-028: was `(NUM_CLUSTERS * NUM_CORES * NUM_WARPS * NUM_THREADS)`, but those
// VX_config.h macros are FROZEN at 1/1/4/4 (kernels are never rebuilt per config),
// so this evaluated to 16 = ONE core's capacity at every config and vx_spawn_threads
// correctly idled every other core. Query the DEVICE at runtime instead.
#define MAX_TOTAL 128            // static bound for g_out: 8 cores x 16 threads/core
#define NPAIR 16

// Emit the EXACT div/rem instruction (RISC-V div-by-zero and INT_MIN/-1 are defined,
// non-trapping — so we drive the divider corners directly; a C '/' would be guarded).
static inline int32_t  d_div (int32_t a,  int32_t b)  { int32_t  r; __asm__("div  %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static inline int32_t  d_rem (int32_t a,  int32_t b)  { int32_t  r; __asm__("rem  %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static inline uint32_t d_divu(uint32_t a, uint32_t b) { uint32_t r; __asm__("divu %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }
static inline uint32_t d_remu(uint32_t a, uint32_t b) { uint32_t r; __asm__("remu %0,%1,%2":"=r"(r):"r"(a),"r"(b)); return r; }

typedef struct { int32_t *a; int32_t *b; uint32_t *out; } de_args_t;

// Corner operand pairs (a, b). Include 0 divisors, INT_MIN, -1, large unsigned.
volatile int32_t g_a[NPAIR] = {
   7,  -7,   7,  -7,  100,  -100,  0x7fffffff, (int32_t)0x80000000,
  (int32_t)0x80000000, 123456, -123456, 1, (int32_t)0xdeadbeef, (int32_t)0xffffffff, 55, -55
};
volatile int32_t g_b[NPAIR] = {
   3,   3,  -3,  -3,    0,     0,          3,             -1,
   1, (int32_t)0xffff0000, 7, 0, 3, (int32_t)0x8000, 0, 0
};
volatile int32_t g_ain[NPAIR];
volatile int32_t g_bin[NPAIR];
volatile uint32_t g_out[MAX_TOTAL];

void de_kernel(de_args_t *__UNIFORM__ args) {
  int tid = blockIdx.x;
  uint32_t acc = 0;
  for (int k = 0; k < NPAIR; k++) {
    int idx = (k + tid) % NPAIR;             // rotate so lanes take different pairs
    int32_t  a = args->a[idx];
    int32_t  b = args->b[idx];
    uint32_t ua = (uint32_t)a, ub = (uint32_t)b;
    // raw divider corners (div-by-0 => -1/all-ones, INT_MIN/-1 => INT_MIN, all ISA-defined)
    acc += (uint32_t)d_div (a, b);               // div
    acc += (uint32_t)d_rem (a, b);               // rem
    acc += d_divu(ua, ub);                        // divu
    acc += d_remu(ua, ub);                        // remu
  }
  args->out[tid] = acc;
}

int main() {
  for (int i = 0; i < NPAIR; i++) { g_ain[i] = g_a[i]; g_bin[i] = g_b[i]; }
  // g_out NOT zeroed here: it is .bss (already zero in the loaded image) and with
  // every core active a core still initialising would wipe another core's results.
  de_args_t args;
  args.a = (int32_t *)g_ain; args.b = (int32_t *)g_bin; args.out = (uint32_t *)g_out;
  uint32_t total = (uint32_t)vx_num_cores() * vx_num_warps() * vx_num_threads();
  if (total > MAX_TOTAL) total = MAX_TOTAL;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)de_kernel, &args);
  return 0;
}
