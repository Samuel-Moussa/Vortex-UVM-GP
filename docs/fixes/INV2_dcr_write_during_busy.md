# INV-2 — `assert_dcr_write_timing` fires on every run (DCR write while busy)

**Status:** root-caused. Change-1 (assertion scoping) applied + **validated in sim** (vecadd_lite
recompile: `assert_dcr_write_timing` fires 0× — was 2×/run — armed at 4535 ns after the config
writes drained; TEST PASSED, 0 err). Change-3 (docs) applied. Change-2 (reset-sync robustness)
**applied + validated** (vecadd_lite: DCR driver signals `dcr_bootstrap_done`; reset release now
gated on it; TEST PASSED, 0 err; behavior-preserving in the current config).
**Not an RTL bug** — correct Vortex boot behavior; the finding is in the verification env + a latent ordering fragility.

## Symptom
`assert_dcr_write_timing` (tb/vortex_if.sv) fires at ~3915 ns and ~3975 ns on **every** run
(e.g. vecadd, axi_drain), each adding a `$warning` to the run's warning count. The property is:

```systemverilog
dcr_if.wr_valid |-> !status_if.busy;   // "no DCR write while the core is busy"
```

## Root cause
Three facts combine:

1. **The core self-starts from reset.** `Vortex/hw/rtl/core/VX_schedule.sv:215-231`, *inside* `if (reset)`:
   ```systemverilog
   warp_pcs[0]     <= from_fullPC(base_dcrs.startup_addr);
   active_warps[0] <= 1;
   ```
   Warp 0 is armed and its PC latched **during** reset. `busy = active_warps!=0 || ~no_pending_instr`
   (VX_schedule.sv:390), so `status_if.busy` asserts the instant `reset_n` deasserts.

2. **Startup DCR config is programmed around the reset edge and drains past it.** The TB drives DCR
   during reset on purpose (tb/vortex_tb_top.sv:62). Reset is held `RESET_CYCLES=400`; the DCR
   write sequence (~4 cycles each × several writes) drains its tail a few cycles *after* reset
   release (release ~cy 385; the two late writes at ~cy 391/397 = 3915/3975 ns).

3. So the late (legitimate) config writes occur while `busy` is already 1 → the assertion trips.

## Is it an RTL bug?
No. Auto-starting from reset with `startup_addr` latched during reset is standard, correct Vortex
boot. Kernels execute from 0x80000000 and pass DUT-vs-SimX. The finding is:
- **Mis-scoped assertion** (`!busy` can't hold given the core self-starts) — noise every run.
- **Latent ordering fragility** (see Change-2).

## Change-1 (applied) — scope the assertion to genuine execution
`$assertoff` `assert_dcr_write_timing` during the startup-config window and `$asserton` it 64
cycles after "System ready" (tb/vortex_tb_top.sv), mirroring the existing `$assertoff` of the
sibling `assert_reset_clears_valids` at line 63. Removes the every-run warning while still
catching a DCR write during actual kernel execution (a real corruption). Inline note added at the
property in tb/vortex_if.sv.

## Change-2 (specced, not applied) — the real robustness fix
`Vortex/hw/rtl/core/VX_dcr_data.sv:27` marks the base-DCR register block `` `UNUSED_VAR(reset) `` —
**the base DCRs have no reset.** `startup_addr`/`startup_arg`/`mpm_class` are X until a DCR write
sets them, and `warp_pcs[0]` latches `startup_addr` during reset. Therefore the STARTUP_ADDR DCR
write **must complete before reset deassertion** or the core boots from an undefined PC. Today that
holds only because `RESET_CYCLES`(400) happens to exceed the DCR sequence length — a timing
coincidence, not a guarantee. Shrinking the reset window or adding config writes would break it.

**Fix:** make the reset release event-driven — hold `reset_n` low until the DCR startup sequence
raises a `dcr_config_done` handshake (with `RESET_CYCLES` as a floor/timeout), so config always
precedes reset release. This also makes Change-1's gating unnecessary (the assertion then never
overlaps busy and passes naturally). Touches the tb_top reset block + the host/DCR launch vseq.
Low urgency (nothing fails today) but the correct methodology; deferred pending sign-off.

## Impact today
Low. `startup_addr` lands in time (kernels boot correctly); `argv`/`mpm` writes land ~cy 391 but are
not read by the kernel until crt0 runs (thousands of cycles later), so no functional race is
exercised. The value of the finding is (a) killing per-run warning noise and (b) recording the
reset-ordering fragility before it bites a config-sensitive kernel.
