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

`include "VX_define.vh"

//==============================================================================
// vx_lsu_probe.sv  —  Passive LOAD-writeback observation probe (Phase A1(d))
//------------------------------------------------------------------------------
// Bound into EVERY VX_lsu_slice via:
//     bind VX_lsu_slice vx_lsu_probe u_lsu_probe ( .clk, .reset, .result_if );
// so it auto-scales across all cores/clusters (one copy per LSU slice).
//
// WHY
//   Load *data* is NOT observable at the commit-arb tap (OBS-002): loads finish
//   via the async LSU memory-response path and the commit `data` field carries a
//   stale/uniform value for `lw`. The lockstep scoreboard therefore had to SKIP
//   the per-lane data compare for loads (PC/rd/ordering only), leaving load
//   correctness to the end-state memory check. That blind spot is exactly what
//   hides an upstream diverging load until it surfaces downstream at a compute
//   op (OBS-009 mulhsu, OBS-010 div).
//
// WHAT IT TAPS
//   VX_lsu_slice.result_if — the slice's OUTPUT after the load-response buffer +
//   sign/zero extension (VX_lsu_slice.sv rsp_buf → rsp_arb → result_if). For a
//   load, result_if.data.wb==1 and result_if.data.data[] is the FINAL aligned
//   per-lane register value, tagged with the same uuid the commit stage retires.
//   The scoreboard overlays this real data onto the matching commit retirement
//   (by uuid) so loads get per-instruction DATA-compared.
//
// PASSIVE / GATED
//   Read-only (no modport → never drives result_if). Captures only when
//   `lockstep_en` (set from +LOCKSTEP by vx_commit_probe at time 0). Default off
//   ⇒ never pushes ⇒ a no-plusarg run is byte-identical.
//
// CONFIG-GENERIC
//   LS_LANES (= NUM_LSU_LANES) derived from the signal width, not a macro.
//   Thread of lane l = pid*LS_LANES + l (VX result packet layout); `sid`:=pid,
//   matching how the scoreboard places SIMD lanes (sid*SIMD_WIDTH+l). Valid for
//   any NUM_CLUSTERS/NUM_CORES/NUM_WARPS/NUM_THREADS and any SIMD_WIDTH.
//==============================================================================
// Ports are the individual result_if signals (bound as result_if.valid/.ready/
// .data) rather than the whole interface: a parameterized interface (#(.data_t))
// is not accepted in a module port header here, and passing the typed struct
// `lsu_res_t data` directly is cleaner and strictly read-only.
module vx_lsu_probe import VX_gpu_pkg::*; import lockstep_pkg::*; (
    input wire      clk,
    input wire      reset,
    input wire      valid,   // result_if.valid
    input wire      ready,   // result_if.ready
    input lsu_res_t data     // result_if.data (uuid/wid/tmask/PC/wb/rd/data[]/pid/sop/eop)
);
    // Per-lane count of the result `data` field, from the signal itself (no macro).
    localparam int LS_LANES = $bits(data.data) / $bits(data.data[0]);

    // A1(c) RVVI hand-off: this probe's own record channel (kind=KIND_LOAD),
    // discovered by the rvvi_monitor via the registry. Pushes stay gated by
    // lockstep_en → no-plusarg run byte-identical.
    rvvi_if u_rvvi (.clk(clk));
    initial rvvi_registry_pkg::rvvi_register(u_rvvi);

    // A load-writeback leaves the slice on a completed handshake with wb==1.
    // Stores go through the no-response path with wb==0 and are ignored.
    wire load_fire = valid && ready && data.wb;

    int unsigned dbg_n = 0;   // +LSU_DEBUG: dump first N raw captures to localise a 0-capture bug

    always @(posedge clk) begin
        if (lockstep_pkg::lockstep_en && !reset && load_fire) begin
            lockstep_pkg::dut_retire_s rec;
            if ($test$plusargs("LSU_DEBUG") && dbg_n < 60) begin
                $display("[LSU_DBG %m] #%0d uuid=%0h wid=%0d rd=%0d pid=%0d tmask=%0h data0=%0h data1=%0h data2=%0h data3=%0h",
                    dbg_n, data.uuid, data.wid, data.rd, data.pid, data.tmask,
                    data.data[0],
                    (LS_LANES>1 ? data.data[1] : '0),
                    (LS_LANES>2 ? data.data[2] : '0),
                    (LS_LANES>3 ? data.data[3] : '0));
                dbg_n = dbg_n + 1;
            end
            rec.kind  = lockstep_pkg::KIND_LOAD;
            rec.uuid  = data.uuid;
            rec.cid   = 0;                        // real cid derived from uuid in the SB
            rec.wid   = data.wid;
            rec.sid   = data.pid;                 // LSU packet id → lane base = pid*LS_LANES
            rec.pc    = to_fullPC(data.PC);
            rec.rd    = data.rd;
            rec.wb    = data.wb;
            rec.tmask = data.tmask;
            rec.sop   = data.sop;
            rec.eop   = data.eop;
            rec.data  = new[LS_LANES];
            for (int l = 0; l < LS_LANES; l++)
                rec.data[l] = data.data[l];
            u_rvvi.push(rec);
        end
    end

endmodule
