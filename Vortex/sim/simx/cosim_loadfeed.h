// RVVI-style DUT load-bus feed for lockstep cosim (Phase A1(e)).
//
// Purpose: an unsynchronized cross-core shared-memory LOAD has no single golden
// value (RVWMO). For such a *provably-racy* load, the RVVI-correct answer is to
// adopt the DUT-observed loaded value on the "load bus" and independently verify
// every other field (decode/ALU/FPU/SFU/control-flow/regfile/store addr+data).
// This module lets the SV lockstep scoreboard hand SimX the DUT's captured load
// writeback values (from the LSU probe) for a selected set of load retirements;
// SimX substitutes them at its single load site (execute.cpp LOAD case) so its
// downstream computation follows the DUT's memory-ordering resolution.
//
// Selectivity (two-pass): only the loads the pass-1 independent compare PROVED
// divergent (and in the verifiable region) are pushed. Everything else keeps
// SimX's own dcache_read value, so deterministic loads remain independently
// verified. Default OFF ⇒ no override, byte-identical to a normal run.
//
// KEY = (cid, wid, PC, occurrence-of-that-PC on this warp). uuid is NOT usable
// (DUT and SimX uuid schemes differ on ~all pairs). A raw per-warp LOAD ordinal
// works for data-only divergence but DRIFTS under asynchronous interrupts: the
// handler inserts instructions, shifting every later load's ordinal so the feed
// lands on the wrong load. Keying by (PC, n-th execution of that PC) is robust —
// interrupt-inserted instructions have DIFFERENT PCs, so a given load's occurrence
// count is unperturbed; it also tolerates x0-dest loads (per-PC counters don't
// cross-contaminate). SimX retires in program order, so its per-(cid,wid,PC)
// occurrence counter matches the scoreboard's when it walks the per-warp gold
// FIFO. The counter advances once per LOAD at that PC (fed or not);
// loadfeed_rewind() resets all counters before each SimX run.

#pragma once

#include <stdint.h>

#ifndef SIMX_COSIM_MAX_THREADS
#define SIMX_COSIM_MAX_THREADS 32
#endif

namespace vortex {

struct LoadFeedRec {
    uint32_t feed_mask;                       // bit l set => override lane l
    uint64_t data[SIMX_COSIM_MAX_THREADS];    // per-lane DUT writeback value
};

void loadfeed_reset();                        // clear all records + cursors + counters
void loadfeed_rewind();                       // reset per-(cid,wid) cursors (before each run)
void loadfeed_enable(bool en);                // arm/disarm the load-bus substitution
bool loadfeed_enabled();

// Register a DUT load override for the `occurrence`-th (0-based) execution of the
// LOAD at `pc` on warp (cid,wid).
void loadfeed_push(uint32_t cid, uint32_t wid, uint64_t pc, uint32_t occurrence,
                   uint32_t feed_mask, const uint64_t* data, uint32_t n);

// Consume the next execution of the LOAD at `pc` on warp (cid,wid): advance that
// (warp,pc) occurrence counter and return the override for the current occurrence,
// or nullptr if disabled / none. Call EXACTLY once per LOAD instruction (fed or
// not) to keep occurrence counts aligned.
const LoadFeedRec* loadfeed_next(uint32_t cid, uint32_t wid, uint64_t pc);

uint32_t loadfeed_pushed();                   // records pushed this pass
uint32_t loadfeed_consumed();                 // pushed records actually hit by a LOAD

// -----------------------------------------------------------------------------
// COMPUTE-writeback feed (OBS-014 reconvergence). Parallel to the load feed but
// applied at a COMPUTE writeback (currently FSQRT) instead of a load. The DUT
// hardware fsqrt.s rounds 1 ULP off the IEEE-correct SoftFloat result; once the
// scoreboard has independently certified that deviation is within the documented
// 1-ULP bound (and logged it), pass 2 forces SimX's sqrt destination register to
// the DUT value so SimX's REGISTER FILE reconverges — every downstream op (via
// registers OR a spill/reload) then follows the DUT, and any residual mismatch is
// a genuinely-independent bug still caught bit-exact. Same (cid,wid,PC,occurrence)
// key and semantics as the load feed; a SEPARATE cursor set (a sqrt and a load at
// the same PC cannot alias). Default OFF ⇒ byte-identical.
// -----------------------------------------------------------------------------
void compfeed_reset();
void compfeed_rewind();
void compfeed_enable(bool en);
bool compfeed_enabled();
void compfeed_push(uint32_t cid, uint32_t wid, uint64_t pc, uint32_t occurrence,
                   uint32_t feed_mask, const uint64_t* data, uint32_t n);
// Consume the next execution of the FED compute op at `pc` on warp (cid,wid).
// Call EXACTLY once per such instruction (fed or not) to keep occurrences aligned.
const LoadFeedRec* compfeed_next(uint32_t cid, uint32_t wid, uint64_t pc);
uint32_t compfeed_pushed();
uint32_t compfeed_consumed();

} // namespace vortex
