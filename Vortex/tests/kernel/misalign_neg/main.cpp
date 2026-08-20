// misalign_neg — NEGATIVE test for the A5 RTL-assertion gate (keep OUT of run_suite).
//
// Deliberately issues ONE misaligned halfword load (odd address). Vortex does not
// support misaligned data access: VX_lsu_slice.sv:189 RUNTIME_ASSERT fires and there
// is NO trap — the access is silently retargeted/torn (OBS-013 in
// docs/RTL_OBSERVATIONS.md). This run MUST therefore be reported
// "TEST FAILED — RTL assertion error(s)" (exit code 2) by the verdict gate.
//
// The loaded value is DISCARDED and the stored end-state is a constant, so the
// scoreboard itself PASSES (SimX performs the load byte-accurately; both sides
// store the same constant) — the ONLY failure path is the RTL-assert gate. That
// isolates the gate: if this test ever reports PASSED, the gate is broken.
//
// Regression guard alongside negative_result_test / negative_dropped_store_test:
// re-run after any change to simulate.sh verdict logic or the run_suite staging.

#include <stdint.h>
#include <vx_intrinsics.h>

volatile uint32_t g_src[2] = {0x11223344, 0x55667788};
volatile uint32_t g_out[1];

int main() {
  // Misaligned lhu at byte offset 1 of g_src (odd, in-region, initialized data).
  uintptr_t p = (uintptr_t)g_src + 1;
  uint32_t v;
  __asm__ volatile("lhu %0, 0(%1)" : "=r"(v) : "r"(p) : "memory");
  (void)v;                 // discarded — end-state independent of the DUT's torn load
  g_out[0] = 0x600DF00D;   // constant store -> byte-exact vs SimX
  return 0;
}
