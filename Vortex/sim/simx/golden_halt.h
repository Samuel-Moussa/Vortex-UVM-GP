// A3 / OBS-020 — GOLDEN HALT record
//
// SimX is a golden model. When it meets an instruction it cannot decode, or an
// operand sub-case it cannot compute, there are exactly two correct behaviours:
// (a) REFUSE, or (b) implement it. Fabricating a result would silently corrupt
// every downstream comparison, so refusing is right and stays right.
//
// What was wrong was not the refusal — it was that the refusal carried no
// information. The site called a bare std::abort(). The DPI shim catches SIGABRT
// (simx_dpi.cpp, sigsetjmp) so vsim survives, but the sentinel it returned (-3)
// said only "SimX died somewhere", and the scoreboard therefore discarded the
// ENTIRE run — including the thousands of instructions that had already been
// lockstep-verified bit-exact BEFORE the unsupported one. One exotic encoding at
// cycle 88,000 voided 88,000 good retirements.
//
// This record makes the refusal informative. The refusing site fills it in, then
// aborts exactly as before (same proven longjmp path — no new control flow in the
// model). The DPI reads the record after longjmp and returns:
//
//   -4  GOLDEN_HALT — the golden refused at a KNOWN point; PC, instruction word
//                     and the sub-field it could not handle are all recorded, so
//                     the verified prefix is reportable and the gap is nameable.
//   -3  CRASH       — record empty: SIGSEGV, or an abort from somewhere that has
//                     not been converted. Genuinely unknown; stays UNVERIFIABLE.
//
// Keeping -3 alive and distinct matters: it is what tells us a site still needs
// converting, instead of silently relabelling every crash as a tidy "halt".

#pragma once

#include <cstdint>

namespace vortex {

struct golden_halt_t {
  int      valid;       // 0 = nothing recorded => a genuine crash, not a halt
  uint64_t pc;          // PC of the offending instruction
  uint32_t code;        // raw instruction word (0 when not available)
  uint32_t wid;         // warp id
  int      line;        // source line of the refusing site
  char     where[16];   // "decode" | "execute"
  char     detail[96];  // the sub-field that could not be handled
};

// Single process-wide record: SimX runs single-threaded under the DPI, and the
// first refusal is the one that stops the run, so there is never a second.
golden_halt_t& golden_halt_record();

// Cleared by the DPI before each run, so a stale record from an earlier run can
// never mislabel a later crash as a halt.
void golden_halt_clear();

// Records the first refusal only (later calls are ignored — the first is the one
// that actually stopped the golden).
void golden_halt_set(const char* where, const char* detail, int line,
                     uint64_t pc, uint32_t code, uint32_t wid);

// ── Non-vacuity injection (default OFF) ─────────────────────────────────────
// A code path that has never been observed to fire is not evidence of anything.
// The retained riscv-dv suite no longer makes SimX refuse anywhere (measured:
// 10/10 runs, zero aborts), so the GOLDEN_HALT path would otherwise ship
// completely unexercised. Setting the environment variable
//
//     SIMX_FORCE_HALT=<n>
//
// makes the golden refuse at the n-th decoded instruction, driving the whole
// chain end-to-end: record -> abort -> DPI longjmp -> -4 -> scoreboard reports a
// NAMED halt and does NOT blame the DUT. Same discipline as the Gate-0
// +INJECT_FAULT / +DROP_STORE negative tests.
//
// Unset (the default) => returns false on every call => byte-identical behaviour.
bool golden_halt_force_pending();

} // namespace vortex
