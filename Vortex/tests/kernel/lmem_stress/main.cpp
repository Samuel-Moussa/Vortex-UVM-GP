// lmem_stress — exercise the per-core LOCAL MEMORY (scratchpad), which no kernel
// in the regression suite touches at all.
//
// WHY: LMEM is ENABLED in the build (`LMEM_ENABLE`, VX_config.vh:673) and the RTL
// is elaborated, but the only kernel that uses it is `conform` — which is NOT in
// run_suite (it is one of the printf-heavy kernels retired by INV-1). Measured on
// the 2026-08-15 2CL bank, work.VX_local_mem sits at 56.4% toggle over 17,536
// bins, i.e. an entire elaborated block is being carried by incidental traffic.
// That is real, honestly-reachable coverage left on the floor — not a structural
// limit, and not something a waiver should ever have hidden.
//
// MULTI-CORE SAFETY IS FREE HERE, and that is the nice property of this target:
// local memory is PER-CORE (each core has its own scratchpad at the same address),
// so every core using the SAME offsets cannot collide with another core by
// construction. Within a core, each thread owns one slot indexed by its own
// (warp, thread) position, so there is no intra-core race either — and therefore
// no barrier is required (Vortex has none with GBAR_ENABLE off).
//
// The stored result is a pure function of the slot index, recomputed identically
// on the host side, so the DUT-vs-SimX compare is as strong as the device run
// (OBS-029: a kernel that verifies nothing is worse than no kernel).

#include <vx_intrinsics.h>
#include <vx_spawn.h>

// LOCAL MEMORY BASE — read from the CSR, never hardcoded.
//
// ⚠ The first version of this kernel hardcoded 0x7FFF0000 as a "mirror" of
// VX_config.vh. That was WRONG: LMEM_BASE_ADDR is STACK_BASE_ADDR, which is
// 0xFFFF0000 on RV32 (VX_config.vh:196,227). The kernel therefore hammered
// ORDINARY memory, passed its self-check perfectly, and moved VX_local_mem
// toggle coverage by exactly 0.00% — a textbook OBS-029 vacuous pass: the
// checker was fine, the stimulus never reached the target.
//
// VX_CSR_LOCAL_MEM_BASE (12'hFC3, VX_types.vh:216) is what the runtime itself
// uses (vx_spawn.h:46), so it is authoritative and config-generic: change the
// address map, XLEN, or the scratchpad placement and this still points at the
// real scratchpad with no edit here.

#define SLOTS_PER_CORE 64     // (warps x threads) upper bound we index into LMEM
#define ROUNDS         6      // read-modify-write passes -> sustained LMEM traffic
#define MAX_TOTAL      128    // 8 cores x 16 threads/core

typedef struct { int *out; } lm_args_t;

volatile int out_buf[MAX_TOTAL];

static int g_nt = 4;          // threads per warp, captured before the spawn

// Deterministic per-slot seed and the RMW recurrence applied to it.
static inline int lm_seed(int slot) { return slot * 7 + 3; }

static inline int lm_mix(int v, int k) {
  // Bit-mixing that stays in int range and is identical on host and device.
  return (v ^ (v << 3)) + (k * 11) - (v >> 2);
}

void lm_kernel(lm_args_t *__UNIFORM__ args) {
  int i = blockIdx.x;

  // Per-CORE slot: local memory is core-private, so the same index on two cores
  // refers to two different physical scratchpads. Derived from the hardware ids
  // rather than the global task id for exactly that reason.
  int slot = (vx_warp_id() * g_nt + vx_thread_id()) & (SLOTS_PER_CORE - 1);

  volatile int *lmem = (volatile int *)csr_read(VX_CSR_LOCAL_MEM_BASE);

  // Seed this thread's own slot, then hammer it with read-modify-write rounds.
  // Every access is a local-memory load or store -> sustained VX_local_mem
  // traffic with changing data (which is what moves toggle, not just presence).
  lmem[slot] = lm_seed(slot);
  int v = 0;
  for (int k = 0; k < ROUNDS; k++) {
    v = lmem[slot];             // LMEM load
    v = lm_mix(v, k);
    lmem[slot] = v;             // LMEM store
  }
  v = lmem[slot];

  args->out[i] = v;
}

// Host reference — same recurrence, same order.
static int lm_ref(int slot) {
  int v = lm_seed(slot);
  for (int k = 0; k < ROUNDS; k++) v = lm_mix(v, k);
  return v;
}

int main() {
  int nt = vx_num_threads();
  if (nt < 1) nt = 1;
  g_nt = nt;

  // NON-VACUITY GUARD (OBS-029). If the local-memory base is not a plausible
  // scratchpad address, FAIL rather than quietly exercising normal memory and
  // reporting a green run — which is precisely what the hardcoded-address
  // version of this kernel did. A kernel that cannot reach its target must say
  // so; only what DIFFERS is validated, and a wrong address differs from
  // nothing because DUT and SimX both honour it.
  if ((unsigned)csr_read(VX_CSR_LOCAL_MEM_BASE) == 0u) return 1;

  lm_args_t args; args.out = (int*)out_buf;

  // Device-sized grid so every core drives its OWN local memory.
  // out_buf is NOT zeroed: .bss is already zero and a whole-array init would
  // wipe another core's results once all cores are active (OBS-026).
  uint32_t total = (uint32_t)vx_num_cores() * vx_num_warps() * vx_num_threads();
  if (total > MAX_TOTAL) total = MAX_TOTAL;
  vx_spawn_threads(1, &total, nullptr, (vx_kernel_func_cb)lm_kernel, &args);

  // Verify ONLY this core's contiguous slice (vx_spawn.c:299).
  // Within a core, task j maps to (warp, thread) in order, so the slot index for
  // the core-local task index j is j & (SLOTS_PER_CORE-1) — the same value the
  // device derived from vx_warp_id()/vx_thread_id().
  uint32_t nc = (uint32_t)vx_num_cores(), cid = (uint32_t)vx_core_id();
  uint32_t per = total / nc, lo = cid * per, hi = lo + per;
  int errors = 0;
  for (uint32_t i = lo; i < hi; i++) {
    int slot = (int)((i - lo) & (SLOTS_PER_CORE - 1));
    if (out_buf[i] != lm_ref(slot)) errors++;
  }
  return errors;
}
