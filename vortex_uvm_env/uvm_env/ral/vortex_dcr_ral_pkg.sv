// ============================================================================
// File: uvm_env/ral/vortex_dcr_ral_pkg.sv
// Description: B1 — UVM RAL for the Vortex DCR base registers.
//
// SCOPE (decided from the RTL, not from the plan text — see
// docs/INDUSTRIAL_TRANSFORMATION_PLAN.md Phase B, which is corrected in place):
//   * DCR only. CSR is OUT OF SCOPE for two reasons: (1) there is no host-side
//     CSR bus anywhere in hw/rtl (no VX_csr_bus_if; only VX_commit_csr_if /
//     VX_sched_csr_if, both internal core plumbing) so there is no protocol for
//     a frontdoor to model; (2) more decisively, there is no verification
//     content — architectural CSRs are already covered by the end-state compare
//     vs SimX AND by per-instruction lockstep (a strictly stronger check), while
//     the volatile MPM CSRs are hardware performance counts whose RTL cycle
//     behaviour legitimately differs from SimX (hence is_volatile), so a mirror
//     would have no reference to compare against.
//
// WHAT THIS ADDS THAT DID NOT EXIST
//   The DCR bus is write-only, so this RAL pairs a WRITE FRONTDOOR (through the
//   existing dcr_agent, so the waveform is unchanged and the scoreboard keeps
//   feeding SimX) with a BACKDOOR READ supplied by vx_dcr_probe. That makes
//   "did this DCR write actually land in the RTL register?" a checked property
//   for the first time. It matters most for MPM_CLASS, the one DCR whose effect
//   is NOT architecturally observable — STARTUP_ADDR0/ARG0 are already caught
//   indirectly (get them wrong and the kernel boots at the wrong PC and the
//   end-state compare goes red), so for those the value added is a NAMED,
//   IMMEDIATE failure instead of a downstream mystery.
//
// PER-CORE BY CONSTRUCTION
//   vx_dcr_probe is `bind`-ed into VX_dcr_data, which VX_core.sv:82 instantiates
//   once per core. So checking is per-core automatically, with no config
//   conditional anywhere: one probe at 1CL/1C, NUM_CLUSTERS*NUM_CORES at scale.
//   That is where the only genuinely new bug class lives — at >=2 sockets or
//   clusters the broadcast tree gains DEPTH=1 pipe stages (Vortex.sv:138,
//   VX_cluster.sv:129), so a deep core can observe a DCR later than core 0.
//   Combined with cores self-starting from reset (VX_schedule.sv:230) and
//   unreset DCR state, that is the INV-2 race widened at scale — see OBS-025.
// ============================================================================

`ifndef VORTEX_DCR_RAL_PKG_SV
`define VORTEX_DCR_RAL_PKG_SV

package vortex_dcr_ral_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import vortex_config_pkg::*;
    import dcr_agent_pkg::*;

    // ------------------------------------------------------------------------
    // Observation record published by vx_dcr_probe when a write RETIRES into the
    // RTL storage of one particular core.
    // ------------------------------------------------------------------------
    class vx_dcr_observation;
        string     path;      // full hierarchical path of the observing probe
        bit [31:0] addr;      // DCR address that retired
        bit [63:0] value;     // value actually held by the RTL after the write
        bit [63:0] wdata;     // data of the write that produced this observation
        time       t;
    endclass

    // ------------------------------------------------------------------------
    // Static sink. An RTL module cannot hold a UVM component handle, but it CAN
    // call a package static method, which is how the bound probe hands its
    // observations to the class world without any virtual-interface plumbing or
    // uvm_hdl_read (the latter would also require +acc, which we do not want to
    // depend on).
    // ------------------------------------------------------------------------
    class vx_dcr_observer;
        static vx_dcr_observation q[$];

        static function void note(string path, bit [31:0] addr, bit [63:0] value,
                                  bit [63:0] wdata);
            vx_dcr_observation o = new();
            o.path  = path;
            o.addr  = addr;
            o.value = value;
            o.wdata = wdata;
            o.t     = $time;
            q.push_back(o);
        endfunction

        static function int unsigned size();
            return q.size();
        endfunction
    endclass

    // ------------------------------------------------------------------------
    // One generic register type. The DCR registers differ only in width and
    // offset, so a parameterised single class is clearer than five near-identical
    // ones. WIDTH matters: MPM_CLASS is 8 bits in hardware
    // (VX_dcr_data.sv:42 captures write_data[7:0]) and modelling it as 32 would
    // make every write with high bits set look like a DUT failure.
    // ------------------------------------------------------------------------
    class vortex_dcr_reg extends uvm_reg;
        `uvm_object_utils(vortex_dcr_reg)
        rand uvm_reg_field value;
        int unsigned m_width;

        function new(string name = "vortex_dcr_reg");
            // 32-bit register container; the FIELD carries the real width.
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction

        virtual function void build_with(int unsigned width);
            m_width = width;
            value = uvm_reg_field::type_id::create("value");
            // Write-only in hardware. Reads are served by the backdoor checker,
            // never by a bus read, so the access policy is honestly "WO".
            value.configure(this, width, 0, "WO", 0, 0, 1, 1, 0);
        endfunction
    endclass

    // ------------------------------------------------------------------------
    // The register block. Registers that DO NOT EXIST in this build are not
    // created at all: STARTUP_ADDR1 / ARG1 are `ifdef XLEN_64` in the RTL
    // (VX_dcr_data.sv:35-41), so on RV32 a write to them falls to `default:;`
    // and is silently dropped. Modelling them anyway would mean checking storage
    // that was never built.
    // ------------------------------------------------------------------------
    class vortex_dcr_reg_block extends uvm_reg_block;
        `uvm_object_utils(vortex_dcr_reg_block)

        rand vortex_dcr_reg startup_addr0;
        rand vortex_dcr_reg startup_arg0;
        rand vortex_dcr_reg mpm_class;
    `ifdef XLEN_64
        rand vortex_dcr_reg startup_addr1;
        rand vortex_dcr_reg startup_arg1;
    `endif

        uvm_reg_map dcr_map;

        function new(string name = "vortex_dcr_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction

        protected function vortex_dcr_reg mk(string name, int unsigned width,
                                             uvm_reg_addr_t offset);
            vortex_dcr_reg r = vortex_dcr_reg::type_id::create(name);
            r.configure(this, null, "");
            // build_with() creates the field; uvm_reg has no base build() to call.
            r.build_with(width);
            dcr_map.add_reg(r, offset, "WO");
            return r;
        endfunction

        virtual function void build();
            dcr_map = create_map("dcr_map", 0, 4, UVM_LITTLE_ENDIAN, 0);

            // Offsets are the RAW DCR word addresses (VX_types.vh:23-27) — NOT
            // byte-shifted. dcr_transaction.sv:64-68 documents the same thing
            // with an explicit "NO << 2!".
            startup_addr0 = mk("startup_addr0", 32, VX_DCR_BASE_STARTUP_ADDR0);
            startup_arg0  = mk("startup_arg0",  32, VX_DCR_BASE_STARTUP_ARG0);
            mpm_class     = mk("mpm_class",      8, VX_DCR_BASE_MPM_CLASS);
        `ifdef XLEN_64
            startup_addr1 = mk("startup_addr1", 32, VX_DCR_BASE_STARTUP_ADDR1);
            startup_arg1  = mk("startup_arg1",  32, VX_DCR_BASE_STARTUP_ARG1);
        `endif

            // EXPLICIT prediction, via a uvm_reg_predictor on the DCR monitor —
            // NOT auto-predict. Auto-predict only updates the mirror for writes
            // issued THROUGH the reg model, but most DCR traffic in this bench
            // comes from legacy sequences driving the agent directly (the
            // bootstrap vseq, host_coverage_vseq). With auto-predict those writes
            // land in the RTL while the mirror stays at its initial value, so the
            // backdoor check reports a mismatch on every one of them — a
            // testbench artefact that looks exactly like a DUT bug (measured: 11
            // false errors on host_coverage_test before this was changed).
            // Predicting off the MONITOR means every observed write updates the
            // mirror regardless of who issued it, so the check covers legacy
            // stimulus too — strictly more valuable than RAL-only coverage.
            dcr_map.set_auto_predict(0);
            lock_model();
        endfunction

        // Map a retired DCR address back to its register, or null if this build
        // does not model it.
        virtual function uvm_reg reg_at(bit [31:0] addr);
            case (addr)
                VX_DCR_BASE_STARTUP_ADDR0 : return startup_addr0;
                VX_DCR_BASE_STARTUP_ARG0  : return startup_arg0;
                VX_DCR_BASE_MPM_CLASS     : return mpm_class;
            `ifdef XLEN_64
                VX_DCR_BASE_STARTUP_ADDR1 : return startup_addr1;
                VX_DCR_BASE_STARTUP_ARG1  : return startup_arg1;
            `endif
                default                    : return null;
            endcase
        endfunction
    endclass

    // ------------------------------------------------------------------------
    // Frontdoor adapter: uvm_reg write -> dcr_transaction on the EXISTING agent.
    // Deliberately no bus2reg read support — the bus has no read channel.
    // ------------------------------------------------------------------------
    class vortex_dcr_adapter extends uvm_reg_adapter;
        `uvm_object_utils(vortex_dcr_adapter)

        function new(string name = "vortex_dcr_adapter");
            super.new(name);
            supports_byte_enable = 0;
            provides_responses   = 0;
        endfunction

        virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
            dcr_transaction tr = dcr_transaction::type_id::create("tr");
            if (rw.kind != UVM_WRITE)
                `uvm_fatal("DCR_RAL",
                    "DCR bus is write-only (VX_dcr_bus_if has no read channel) — a frontdoor read is impossible. Use the backdoor checker instead.")
            tr.addr = rw.addr[VX_DCR_ADDR_WIDTH-1:0];
            tr.data = rw.data[VX_DCR_DATA_WIDTH-1:0];
            return tr;
        endfunction

        virtual function void bus2reg(uvm_sequence_item bus_item,
                                      ref uvm_reg_bus_op rw);
            dcr_transaction tr;
            if (!$cast(tr, bus_item)) begin
                `uvm_error("DCR_RAL", "bus2reg: item is not a dcr_transaction")
                return;
            end
            rw.kind   = UVM_WRITE;
            rw.addr   = tr.addr;
            rw.data   = tr.data;
            rw.status = UVM_IS_OK;
        endfunction
    endclass

    // ------------------------------------------------------------------------
    // The checker. Drains probe observations and compares each against the reg
    // model's mirrored value — i.e. "the value we asked for" vs "the value the
    // RTL of THAT core actually holds".
    //
    // Non-vacuity hook: +DCR_RAL_INJECT corrupts exactly one observation so the
    // check is forced to fail, proving the comparison can report. Same pattern
    // as the scoreboard's +INJECT_FAULT / +DROP_STORE guards.
    // ------------------------------------------------------------------------
    class vortex_dcr_ral_checker extends uvm_component;
        `uvm_component_utils(vortex_dcr_ral_checker)

        vortex_dcr_reg_block regs;

        int unsigned n_checked  = 0;
        int unsigned n_failed   = 0;
        int unsigned n_unmapped = 0;

        // How many probe instances SHOULD have reported, i.e. how many cores the
        // RTL elaborated. Set by the env from the config object; left 0 means
        // "unknown" and the completeness check is skipped rather than guessed.
        //
        // WHY THIS EXISTS: `bind` makes the probe per-core by construction, but
        // "by construction" is not the same as "verified". Every observation that
        // ARRIVES is checked, yet nothing noticed observations that never arrive —
        // so a probe that silently failed to bind on a deep core produced a green
        // result. That is the exact failure mode the per-core check is supposed to
        // catch (OBS-025 lives on the deep cores, not core 0), so a checker blind
        // to it would be worse than useless: it would look like evidence.
        int unsigned expected_instances = 0;
        bit          inject     = 0;
        bit          injected   = 0;
        bit          inject_seen_fail = 0;

        // Distinct hierarchical paths that reported at least once. Keyed by the
        // probe's own `%m`, so the count is the number of cores actually observed
        // — never a derived or assumed number.
        protected bit m_seen_paths[string];

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            inject = $test$plusargs("DCR_RAL_INJECT");
            if (inject)
                `uvm_info("DCR_RAL",
                    "[NEG] +DCR_RAL_INJECT armed — one observation will be corrupted to prove the check can fail", UVM_LOW)
        endfunction

        // Drain in check_phase: every DCR write has retired by then, and this
        // keeps the checker off the run-phase critical path entirely.
        virtual function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (regs == null) begin
                `uvm_warning("DCR_RAL", "no register block attached — DCR backdoor checking skipped")
                return;
            end

            foreach (vx_dcr_observer::q[i]) begin
                vx_dcr_observation o = vx_dcr_observer::q[i];
                uvm_reg            rg = regs.reg_at(o.addr);
                vortex_dcr_reg     vr_dbg;
                bit [63:0]         expected, actual;

                // Record liveness BEFORE the unmapped filter: an observation of
                // an address this build does not model still proves that probe
                // instance exists and is reporting.
                m_seen_paths[o.path] = 1'b1;

                if (rg == null) begin
                    // Not modelled in this build (e.g. an XLEN_64-only address on
                    // RV32). The RTL drops it too, so there is nothing to check.
                    n_unmapped++;
                    continue;
                end

                // Expected = the data of the write that produced THIS observation,
                // truncated to the field width the hardware actually implements.
                // The register model supplies that width, which is the modelling
                // value it adds: MPM_CLASS is 8 bits in RTL (VX_dcr_data.sv:42
                // captures write_data[7:0]), so a 32-bit compare would report a
                // testbench bug as a DUT failure.
                //
                // NOT rg.get_mirrored_value(): the mirror holds the LAST value
                // written, while observations are historical. Comparing every
                // observation against the final mirror produces a false mismatch
                // for each earlier write — measured as 10 false errors on
                // host_coverage_test, which sweeps DCR values.
                begin
                    vortex_dcr_reg vr;
                    int unsigned   w = 32;
                    if ($cast(vr, rg)) w = vr.m_width;
                    expected = (w >= 64) ? o.wdata : (o.wdata & ((64'h1 << w) - 64'h1));
                end
                actual   = o.value;

                if (inject && !injected) begin
                    actual   = actual ^ 64'h1;
                    injected = 1;
                    `uvm_info("DCR_RAL", $sformatf(
                        "[NEG] corrupted observation of %s at %s to force a mismatch",
                        rg.get_name(), o.path), UVM_LOW)
                end

                n_checked++;
                if (actual !== expected) begin
                    n_failed++;
                    if (inject && injected && n_failed == 1) inject_seen_fail = 1;
                    `uvm_error("DCR_RAL", $sformatf(
                        "DCR MISMATCH  reg=%s addr=0x%03h  wrote=0x%0h  expected(after %0d-bit truncation)=0x%0h  RTL(actual)=0x%0h  probe=%s  t=%0t",
                        rg.get_name(), o.addr, o.wdata,
                        ($cast(vr_dbg, rg) ? vr_dbg.m_width : 32), expected, actual, o.path, o.t))
                end
            end

            `uvm_info("DCR_RAL", $sformatf(
                "DCR backdoor check: observations=%0d checked=%0d failed=%0d unmapped(not built in this config)=%0d cores_observed=%0d",
                vx_dcr_observer::q.size(), n_checked, n_failed, n_unmapped,
                m_seen_paths.num()), UVM_LOW)

            // COMPLETENESS: did every core report? VX_dcr_data is instantiated
            // once per core (VX_core.sv:82, its only instantiation site), and
            // sockets SUBDIVIDE cores rather than multiplying them
            // (NUM_SOCKETS = UP(NUM_CORES/SOCKET_SIZE), VX_gpu_pkg.sv:99), so the
            // elaborated instance count is exactly NUM_CLUSTERS * NUM_CORES.
            // The DCR bus is broadcast, so every core sees every write and must
            // appear here. Fewer means a probe did not bind or a core never got
            // the write — both are real findings, and both would otherwise hide
            // behind a green per-observation result.
            if (expected_instances != 0) begin
                if (m_seen_paths.num() != expected_instances) begin
                    `uvm_error("DCR_RAL", $sformatf(
                        "DCR probe COMPLETENESS FAILED: %0d core(s) reported, expected %0d (NUM_CLUSTERS*NUM_CORES). Either a vx_dcr_probe did not bind, or a core never observed a DCR write.",
                        m_seen_paths.num(), expected_instances))
                    foreach (m_seen_paths[p])
                        `uvm_info("DCR_RAL", $sformatf("  reported: %s", p), UVM_LOW)
                end else begin
                    `uvm_info("DCR_RAL", $sformatf(
                        "DCR probe completeness OK: all %0d core(s) reported",
                        expected_instances), UVM_LOW)
                end
            end else begin
                `uvm_info("DCR_RAL",
                    "expected_instances not set — per-core completeness NOT checked (count above is informational only)", UVM_LOW)
            end

            // A silent checker is worthless. If nothing was ever observed the
            // probe is not wired, and saying so is better than reporting "0 fails".
            if (n_checked == 0)
                `uvm_warning("DCR_RAL",
                    "ZERO DCR observations checked — is vx_dcr_probe bound and is the DCR agent driving? A green result here proves nothing.")
        endfunction
    endclass

endpackage : vortex_dcr_ral_pkg

`endif // VORTEX_DCR_RAL_PKG_SV
