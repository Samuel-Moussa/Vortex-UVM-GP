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
// KEY = (cid, wid, per-warp LOAD ordinal). uuid is NOT usable: the DUT and SimX
// uuid schemes differ (a normal run shows them divergent on ~all pairs), so the
// lockstep scoreboard aligns by per-warp PROGRAM ORDER — and so must the feed.
// SimX retires strictly in program order, so a per-(cid,wid) load counter yields
// the same ordinal the scoreboard uses when it walks the per-warp gold FIFO. The
// cursor advances once per LOAD (fed or not) to stay aligned; loadfeed_rewind()
// resets all cursors before each SimX run.

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

// Register a DUT load override for the `ordinal`-th LOAD (0-based, program order)
// on warp (cid,wid).
void loadfeed_push(uint32_t cid, uint32_t wid, uint32_t ordinal,
                   uint32_t feed_mask, const uint64_t* data, uint32_t n);

// Consume the next LOAD slot on warp (cid,wid): advance that warp's cursor and
// return the override for the current ordinal, or nullptr if disabled / none.
// Call EXACTLY once per LOAD instruction (fed or not) to keep ordinals aligned.
const LoadFeedRec* loadfeed_next(uint32_t cid, uint32_t wid);

uint32_t loadfeed_pushed();                   // records pushed this pass
uint32_t loadfeed_consumed();                 // pushed records actually hit by a LOAD

} // namespace vortex
