// ============================================================================
// File: tb/vx_dcr_probe.sv
// Description: Passive per-instance DCR register observer (B1 / RAL backdoor).
//
// WHY THIS EXISTS
//   VX_dcr_bus_if is WRITE-ONLY (interfaces/VX_dcr_bus_if.sv:18-31 — write_valid,
//   write_addr, write_data and nothing else), so a UVM RAL cannot read a DCR
//   through the frontdoor. This probe supplies the missing read side by peeking
//   at the RTL storage itself, which turns mirror(UVM_CHECK) into a REAL check
//   that a DCR write landed in the register — something nothing in the bench
//   verifies today.
//
// WHY `bind` AND NOT add_hdl_path_slice
//   `bind` instantiates exactly once per instance the RTL actually built, so the
//   probe is CONFIG-AWARE BY CONSTRUCTION: one at 1CL/1C, NUM_CLUSTERS*NUM_CORES
//   at scale, with no hierarchical path enumeration to keep in sync and nothing
//   to waive when a config shrinks. Same principle as vx_commit_probe (bound into
//   VX_commit) and vx_cache_probe (bound into VX_cache_bank, where
//   VX_cache_wrap.sv:160 only builds the bank when PASSTHRU==0).
//
// PEEK ONLY — NEVER POKE
//   The scoreboard mirrors DCR writes into SimX off the MONITORED interface
//   (vortex_scoreboard.sv:403 simx_dcr_write). A backdoor WRITE would bypass that
//   and silently desync the golden model, so this probe is strictly read-only and
//   the RAL frontdoor stays the existing dcr_agent path. The driven waveform is
//   byte-identical with or without this probe.
//
// EVENT-DRIVEN, NOT BOOTSTRAP-GATED (see OBS-025 — this is the subtle part)
//   A DCR write reaches a deep core through up to two DEPTH=1 pipeline stages
//   (Vortex.sv:138 when NUM_CLUSTERS>1, VX_cluster.sv:129 when NUM_SOCKETS>1).
//   Arming the comparison off the global TB `dcr_bootstrap_done` handshake would
//   therefore sample a deep core's `dcrs` BEFORE its write arrived and report a
//   FALSE mismatch that is pure tree latency. Instead each probe reports only
//   after observing ITS OWN write retire: no latency constant is derived, and it
//   stays correct if the broadcast tree ever gets deeper.
//
//   The one-cycle delay below is also what makes the sample correct w.r.t. NBA
//   ordering: VX_dcr_data latches `dcrs` on the same posedge that carries
//   write_valid, so reading `dcrs` at that edge would return the OLD value.
//   Reporting one cycle later reads the retired value.
//
// UNRESET STATE (OBS-025 / INV-2)
//   `dcrs` has no reset (VX_dcr_data.sv:27 UNUSED_VAR(reset)) and the DCR pipe
//   register is doubly unreset (VX_define.vh:381 ties reset low and omits RESETW,
//   which defaults to 0 at VX_pipe_register.sv:19). Reporting only on an observed
//   write means we never sample the X window at all — there is no need to special
//   case it, and no reset value is ever asserted.
// ============================================================================

`ifndef VX_DCR_PROBE_SV
`define VX_DCR_PROBE_SV

module vx_dcr_probe import VX_gpu_pkg::*; #(
    // Purely cosmetic: lets the observation name itself in a failure message.
    parameter string INSTANCE_ID = "dcr"
) (
    input wire                             clk,
    input wire                             reset,
    // Mirrored from the bound VX_dcr_data. `dcrs` is the module's internal
    // storage register; `bind` may connect to it directly.
    input wire                             write_valid,
    input wire [vortex_config_pkg::VX_DCR_ADDR_WIDTH-1:0]    write_addr,
    input wire [vortex_config_pkg::VX_DCR_DATA_WIDTH-1:0]    write_data,
    input base_dcrs_t                      dcrs
);

    // Staged write: what retired, and at which address.
    reg                                                pend;
    reg [vortex_config_pkg::VX_DCR_ADDR_WIDTH-1:0]     pend_addr;
    reg [vortex_config_pkg::VX_DCR_DATA_WIDTH-1:0]     pend_data;

    // Resolve the retired value for an address out of the storage struct. This
    // MUST mirror VX_dcr_data.sv:31-46 exactly, including its two config gates:
    //   * STARTUP_ADDR1 / STARTUP_ARG1 exist only under XLEN_64. On RV32 those
    //     writes fall through to `default:;` and are SILENTLY DROPPED, so there
    //     is no storage to compare and the probe must not invent one.
    //   * MPM_CLASS captures only write_data[7:0]; comparing 32 bits would report
    //     a testbench modelling bug as a DUT failure.
    function automatic bit [63:0] observed_value(input bit [vortex_config_pkg::VX_DCR_ADDR_WIDTH-1:0] a);
        case (a)
            vortex_config_pkg::VX_DCR_BASE_STARTUP_ADDR0 : return 64'(dcrs.startup_addr[31:0]);
            vortex_config_pkg::VX_DCR_BASE_STARTUP_ARG0  : return 64'(dcrs.startup_arg[31:0]);
            vortex_config_pkg::VX_DCR_BASE_MPM_CLASS     : return 64'(dcrs.mpm_class);
        `ifdef XLEN_64
            vortex_config_pkg::VX_DCR_BASE_STARTUP_ADDR1 : return 64'(dcrs.startup_addr[63:32]);
            vortex_config_pkg::VX_DCR_BASE_STARTUP_ARG1  : return 64'(dcrs.startup_arg[63:32]);
        `endif
            default                    : return 64'h0;
        endcase
    endfunction

    // Is this address actually backed by storage in THIS build? Anything else
    // hits `default:;` in the RTL, so there is nothing to check and reporting it
    // would manufacture a false failure.
    function automatic bit is_modelled(input bit [vortex_config_pkg::VX_DCR_ADDR_WIDTH-1:0] a);
        case (a)
            vortex_config_pkg::VX_DCR_BASE_STARTUP_ADDR0,
            vortex_config_pkg::VX_DCR_BASE_STARTUP_ARG0,
            vortex_config_pkg::VX_DCR_BASE_MPM_CLASS     : return 1'b1;
        `ifdef XLEN_64
            vortex_config_pkg::VX_DCR_BASE_STARTUP_ADDR1,
            vortex_config_pkg::VX_DCR_BASE_STARTUP_ARG1  : return 1'b1;
        `endif
            default                    : return 1'b0;
        endcase
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            pend <= 1'b0;
        end else begin
            // Report the PREVIOUS cycle's write, now that `dcrs` holds it.
            if (pend && is_modelled(pend_addr)) begin
                // Publish BOTH the value the RTL now holds and the data that was
                // written. The checker compares them against each other: the
                // register model supplies the field WIDTH (so hardware truncation
                // such as MPM_CLASS[7:0] is modelled), but the expected value must
                // come from the write that produced THIS observation. Comparing
                // against the register's end-of-test mirrored value instead would
                // be wrong whenever an address is written more than once — as
                // host_coverage_test does when it sweeps DCR values.
                vortex_dcr_ral_pkg::vx_dcr_observer::note(
                    $sformatf("%m"), pend_addr, observed_value(pend_addr), pend_data);
            end
            pend      <= write_valid;
            pend_addr <= write_addr;
            pend_data <= write_data;
        end
    end

endmodule

`endif // VX_DCR_PROBE_SV
