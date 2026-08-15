// multicore_isa — ISA surface that ONLY riscv-dv used to reach, run SAFELY on every core.
//
// WHY THIS EXISTS.
// FIX 1 (OBS-027) core-gates riscv-dv to core 0, because riscv-dv emits a
// SINGLE-HART program whose result on >1 core is architecturally undefined.
// FIX 2 (OBS-026) core-scopes barrier_test for the same reason. Both gates are
// correct and must stay. But they cost coverage: measured at 2CL, cores 1-3 each
// miss exactly 8 bins that core 0 covers, and every one of them traces to a
// construct whose only producer was one of those two gated programs:
//     instr_class_cg_alu.cp_alu_op.czeq / .czne          (Zicond)
//     instr_class_cg_lsu.cp_lsu_op.lb                    (sub-word load)
//     instr_class_cg_sfu.cross_sfu_threads.<bar,uniform>
//                                        .<bar,partial[2]> / .<bar,partial[3]>
//                                        .<pred,partial[2]> / .<pred,partial[3]>
// The honest fix is NOT to remove the gates — coverage collected from a program
// with no defined result is a bin ticked by an undefined value. It is to emit the
// same instructions from a program that IS well-defined on every core. That is
// this kernel.
//
// WHY THE COMPILER CANNOT PRODUCE THE ZICOND OPS.
// Kernels build with -march=rv32imaf (tests/kernel/common.mk:6) — no Zicond in
// the arch string — so the compiler can NEVER emit czero.eqz/czero.nez. Verified
// empirically: 0 occurrences across the mem_stress / wide_stress / cache_stress
// ELFs. The hardware does implement them (VX_config.vh:52 EXT_ZICOND_ENABLE,
// decoded at VX_decode.sv:186-190), so they are reachable only via inline asm.
// Encoding from the RTL, not from memory: INST_R_F7_ZICOND = 7'b0000111 = 0x07
// (VX_gpu_pkg.sv:168) on opcode OP (0x33), and VX_decode.sv:189 selects
// CZNE when funct3[1] is set -> funct3 5 = czero.eqz, funct3 7 = czero.nez.
//
// MULTI-CORE SAFETY (the whole point):
//   * every thread writes ONLY its own out_buf[i], and vx_spawn distributes tasks
//     CONTIGUOUSLY (vx_spawn.c:299), so no core touches another's slice and no
//     barrier is needed — Vortex has none with GBAR_ENABLE off;
//   * barriers use num_warps=1, i.e. warp-local, so they are independent per core
//     (barriers are per-core anyway: VX_wctl_unit.sv:138 ties is_global low);
//   * vx_pred is called with a UNIFORMLY-TRUE condition, so the resulting mask is
//     exactly the currently-active set — the SFU op dispatches under the peeled
//     mask (which is what fills the cross bin) without perturbing control flow;
//   * out_buf is NOT zeroed here: it is .bss and already zero, and a whole-array
//     init would wipe another core's results once every core is active (OBS-026);
//   * the result is a PURE function of (tid, i), recomputed identically on the
//     host side, so the scoreboard compare is exactly as strong as the device run.

#include <vx_intrinsics.h>
#include <vx_spawn.h>

#define MAX_TOTAL 128        // 8 cores x 16 threads/core
#define OPQ(x) __asm__ volatile("" : "+r"(x))   // keep the control flow real

// Zicond, encoded from the RTL decode (see header).
#define CZERO_EQZ(rd, rs1, rs2) \
  __asm__ volatile(".insn r 0x33, 0x5, 0x07, %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2))
#define CZERO_NEZ(rd, rs1, rs2) \
  __asm__ volatile(".insn r 0x33, 0x7, 0x07, %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2))

// Small .rodata tables so the sub-word loads have real, deterministic data.
static const signed char   s8_tab[8]  = { 3, -7, 11, -1, 0, 127, -128, 5 };
static const signed short s16_tab[8]  = { 1000, -2000, 30000, -1, 0, 32767, -32768, 7 };

typedef struct { int *out; } mi_args_t;

// Per-thread scratch for the sub-word STORES (sb/sh). Each thread uses its own
// 8-byte lane, so the stores are race-free across cores.
static volatile unsigned char  sb_scratch[MAX_TOTAL * 4];
static volatile unsigned short sh_scratch[MAX_TOTAL * 2];

// The device body. `tid` is the intra-warp lane (mask peeling is per-warp);
// `i` is the global task id (selects data). Pure function of both.
static inline int mi_body(int i, int tid) {
  int r = i * 3 + 1;

  // ---- Zicond, UNIFORM mask (all threads active here) ----
  unsigned a = (unsigned)r, c = (unsigned)(tid & 1), z1, z2;
  CZERO_EQZ(z1, a, c);          // czeq: rd = (rs2==0) ? 0 : rs1
  CZERO_NEZ(z2, a, c);          // czne: rd = (rs2!=0) ? 0 : rs1
  // Exactly one of z1/z2 is 0 for a given c, so the sum is r either way —
  // deterministic and independent of which side the hardware takes.
  r += (int)(z1 + z2) - (int)a;

  // ---- sub-word LOADS: lb (signed byte) and lh (signed half) ----
  r += (int)s8_tab[tid & 7];
  r += (int)s16_tab[(tid + 1) & 7];

  // ---- sub-word STORES: sb / sh into this thread's own lane ----
  sb_scratch[i & (MAX_TOTAL * 4 - 1)] = (unsigned char)(r & 0xFF);
  sh_scratch[i & (MAX_TOTAL * 2 - 1)] = (unsigned short)(r & 0xFFFF);

  // ---- SFU under peeled thread masks (mirrors the proven bar_masks shape) ----
  vx_barrier(0, 1);  vx_pred(1, 0xF);  OPQ(r);   // <bar,uniform> / <pred,uniform>
  r += 1;

  if (tid < 3) { OPQ(r);                         // active {0,1,2} -> partial[3]
    vx_barrier(1, 1);  vx_pred(1, 0xF);  OPQ(r); // <bar,partial[3]> <pred,partial[3]>
    r += 2;
    if (tid < 2) { OPQ(r);                       // active {0,1}  -> partial[2]
      vx_barrier(2, 1);  vx_pred(1, 0xF);  OPQ(r);// <bar,partial[2]> <pred,partial[2]>
      r += 4;
      OPQ(r);
    }
    OPQ(r);
  }
  OPQ(r);
  return r;
}

// Host-side reference — same arithmetic, no SFU/Zicond needed because both are
// value-neutral by construction above.
static int mi_ref(int i, int tid) {
  int r = i * 3 + 1;
  r += (int)s8_tab[tid & 7];
  r += (int)s16_tab[(tid + 1) & 7];
  r += 1;
  if (tid < 3) { r += 2; if (tid < 2) r += 4; }
  return r;
}

volatile int out_buf[MAX_TOTAL];

static int g_nt = 4;   // threads per warp, captured before the spawn

void mi_kernel(mi_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;
  args->out[i] = mi_body(i, i % g_nt);
}

int main() {
  int nt = vx_num_threads();
  if (nt < 1) nt = 1;
  g_nt = nt;

  mi_args_t args; args.out = (int*)out_buf;

  // Device-sized grid: EVERY core must run this, which is the entire purpose.
  uint32_t total = (uint32_t)vx_num_cores() * vx_num_warps() * vx_num_threads();
  if (total > MAX_TOTAL) total = MAX_TOTAL;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)mi_kernel, &args);

  // Check ONLY this core's contiguous slice (vx_spawn.c:299) — no barrier needed.
  uint32_t nc = (uint32_t)vx_num_cores(), cid = (uint32_t)vx_core_id();
  uint32_t per = total / nc, lo = cid * per, hi = lo + per;
  int errors = 0;
  for (uint32_t i = lo; i < hi; i++)
    if (out_buf[i] != mi_ref((int)i, (int)(i % (uint32_t)nt))) errors++;
  return errors;
}
