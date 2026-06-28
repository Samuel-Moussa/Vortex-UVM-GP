// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "VX_define.vh"   // for `ISSUE_WIDTH (derived in VX_config.vh, not a cmdline define)

//==============================================================================
// vx_commit_probe.sv  —  Passive commit/retire observation probe (plan item P1)
//------------------------------------------------------------------------------
// Bound into EVERY VX_commit instance via:
//     bind VX_commit vx_commit_probe u_commit_probe ( ... );
// so it auto-scales across all cores/clusters/sockets — one copy per core,
// regardless of NUM_CLUSTERS x NUM_SOCKETS x SOCKET_SIZE.
//
// PURPOSE
//   Observability ONLY. This probe reads the post-arbitration commit interface
//   (commit_arb_if), it NEVER drives it and is NEVER a checker. The only gate
//   in this bench is end-state equivalence vs SimX; coverage probes like this
//   one observe what was actually retired so functional coverage can close.
//
// WHAT IT EXPOSES (Ahmad samples these for coverage — count + warp activity)
//   per lane i in [0, ISSUE_WIDTH):
//     retire_fire[i]                = commit_arb_if[i].valid && commit_arb_if[i].ready
//     commit_arb_if[i].data.{uuid,wid,sid,tmask,PC,wb,rd,data,sop,eop}
//
// PARAMETRIZATION
//   - ISSUE_WIDTH : commit_arb_if array + the genvar loop (no hardcode).
//   - warps/threads : carried in commit_t (NW_WIDTH / SIMD_WIDTH), macro-driven.
//   - cores/clusters : handled by bind-to-module-type (no parameter needed).
//   No CORE_ID parameter: per-core attribution comes from the UCDB hierarchy
//   path (...core[N].u_commit_probe), not from a bind-time constant.
//==============================================================================
module vx_commit_probe import VX_gpu_pkg::*; (
    input wire clk,
    input wire reset,
    // No modport -> read-only by discipline. Using .slave would drive ready and
    // make the probe an active participant; this stays strictly passive.
    VX_commit_if commit_arb_if [`ISSUE_WIDTH]
);
    // Elaboration sanity: uuid must be a real multi-bit field. A width <= 1 means
    // a degenerate UUID config that would defeat per-instruction tracking.
    initial assert ($bits(commit_arb_if[0].data.uuid) > 1)
        else $fatal(1, "[P1-PROBE] uuid width=%0d <= 1 -- degenerate UUID config",
                    $bits(commit_arb_if[0].data.uuid));

    // Per-lane passive retire observation. Exposed for bound covergroups (Ahmad).
    // Liveness self-check: per-lane counter proves the bind elaborated + observes
    // real retires. Passive only — never drives the DUT. commit_arb_if must be
    // indexed by the constant genvar (interface instance arrays forbid runtime idx).
    longint unsigned p1_lane_count [`ISSUE_WIDTH];
    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin : g_commit_lanes
        wire retire_fire = commit_arb_if[i].valid && commit_arb_if[i].ready;
        initial p1_lane_count[i] = 0;
        always @(posedge clk)
            if (!reset && retire_fire)
                p1_lane_count[i] <= p1_lane_count[i] + 1;
    end

    final begin
        automatic longint unsigned p1_total = 0;
        for (int j = 0; j < `ISSUE_WIDTH; j++) p1_total += p1_lane_count[j];
        $display("[P1-PROBE %m] retired instructions observed = %0d", p1_total);
    end

endmodule
