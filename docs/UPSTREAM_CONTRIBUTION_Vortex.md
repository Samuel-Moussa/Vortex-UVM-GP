# Upstream contribution to Vortex — findings from an independent UVM verification effort

**Status: READY TO SEND.** Intended channel: **GitHub issues on
[`vortexgpgpu/vortex`](https://github.com/vortexgpgpu/vortex)** — one issue per finding, using
the per-finding sections below verbatim. A public issue is citable, triageable and searchable;
e-mail is not. (Project page: <https://vortex.cc.gatech.edu>.)

> **Before sending, do the two SENDER CHECKS at the bottom.** Every claim here is reproducible
> from our tree, but each was found at **RTL pin `7a52ee5`** — confirm the finding still applies
> to upstream `master` before filing, and adjust the wording if it has since been fixed.

---

## 0. Cover note (use as the intro of the first issue, or a Discussion post)

> We are an independent team that built a UVM verification environment for Vortex, using SimX as
> a golden reference through a DPI co-simulation layer, with **per-instruction lockstep**
> checking (RVVI-style: PC, destination register, per-lane writeback data, load data) in addition
> to end-state memory equivalence.
>
> In the course of that work we found a small number of issues we believe are worth reporting
> upstream. We want to be clear about two things:
>
> 1. **Vortex has been an excellent design to verify against.** SimX being cleanly decoupled from
>    the timing model (`core.cpp` consuming `emulator_.step()`) is what made per-instruction
>    lockstep practical at all — that is a genuinely good architectural decision, and it is rarer
>    than it should be.
> 2. **We are reporting these as observations, not defect claims against the project.** Several
>    are guard/verification-infrastructure issues rather than datapath bugs, and we say so
>    explicitly in each. Where we worked around something on our side rather than patching the
>    RTL, we say that too.
>
> Each finding below carries: what we saw, the exact `file:line`, how to reproduce, and our
> assessment of severity. We are happy to submit PRs for any of them.

---

## FINDING 1 — `JALR` does not clear the target address LSB (RISC-V spec deviation)

**Severity: HIGH — this is an ISA conformance issue, and it silently corrupts results.**

**Spec.** RISC-V unprivileged spec, `JALR`: the target address is computed by adding the
sign-extended 12-bit immediate to `rs1`, **"then setting the least-significant bit of the result
to zero."**

**What Vortex does.** `hw/rtl/VX_alu_int.sv:222`:
```
cbr_dest = from_fullPC(add_result[0])
```
The `jalr` destination is the raw `rs1 + imm`. There is no `& ~1`.

**Why it is not benign.** In a build where `PC_BITS == XLEN` (`VX_gpu_pkg.sv:75-82`, where
`to_fullPC`/`from_fullPC` are the identity), the odd bit survives as the **architectural PC**.
Fetch then silently word-aligns the access (`VX_fetch.sv:101`), so the core keeps executing the
*correct instruction words* — but the PC itself stays skewed. Consequences:

- every `auipc` / `la` result (`rd = PC + imm`) inherits the skew;
- through chained jumps and link-register writes (`rd = PC + 4`) the skew **accumulates**
  (we observed +1 growing to +3);
- downstream loads/stores then go misaligned, which on Vortex is silently retargeted/torn
  (see Finding 4) and produces LSU assertion storms.

Additionally, a target with `bits[1:0] != 0` on a non-C core should raise
`instruction-address-misaligned`; Vortex has no trap for this.

**How we hit it (spec-legal stimulus, not a synthetic corner).** riscv-dv deliberately exercises
the spec's LSB-clear requirement — `riscv-dv/src/riscv_directed_instr_lib.sv:162-165` adds
`offset = $urandom_range(0,1)` to the `jalr` base register, with the comment *"JALR is expected
to set lsb to 0"*. So roughly half of all generated jumps target `label+1`.

**Evidence.** In a 2026-07-10 suite run, **12 of 12 riscv-dv profiles** fired misaligned-access
assertions (30–7616 per run). In `riscv_jump_stress_test`, assertion PCs
`0x80001887..0x800018fb` (stride 4, each = `instr_addr + 3`) fall inside riscv-dv's register-dump
routine (the `sw rX, off(t6)` block before `_vortex_done`, objdump-verified); store addresses
`0x80008083..` correspond to an `auipc`-derived `t6` = base + 3.

**Release-build note (why this may have gone unnoticed).** A release build with
`PC_BITS = XLEN-2` drops PC bits `[1:0]` in representation, so a `label+1` target lands
spec-correct **by accident**. The deviation is architecturally visible in the debug build. Note a
`label+2` target would silently word-align in release, where the spec demands a trap.

**Suggested fix.** Clear the LSB at the destination adder in `VX_alu_int.sv:222`. Note that
`sim/simx/execute.cpp:469` currently **mirrors** the no-clear behaviour, so SimX must be
un-mirrored in the same change or the models will disagree.

**What we did on our side.** Sanitized the stimulus (patched the riscv-dv `jalr` offset to 0) and
left the RTL untouched, precisely so we could report it rather than paper over it.

---

## FINDING 2 — `fsqrt.s` result is 1 ULP off the correctly-rounded IEEE-754 value

**Severity: MEDIUM — a documented accuracy limitation would be fine; being undocumented is the issue.**

**Spec.** IEEE-754 §5.4.1 requires `sqrt` to be correctly rounded.

**What we measured.** At `fsqrt.s fa0, fs0` (PC `0x800000e8` in our `fpu_test`), per-instruction
lockstep reports lane 0 `DUT = 0x3fef7750` vs reference `0x3fef7751` — **adjacent float32 values,
exactly 1 ULP apart**. The same signature appears on other inputs in a multi-threaded variant
(`0x3fef7750` vs `…7751`, `0x402f456e` vs `…456f`).

**Why we are confident the deviation is on the hardware side.**
- The reference is SimX, which computes `fsqrt` via **Berkeley SoftFloat**
  (`third_party/softfloat`) — the canonical correctly-rounded implementation.
- The `fdiv.s` at the *adjacent* PC `0x800000e0`, same operand class, **matched exactly**. So the
  hardware divider is correctly rounded and the **sqrt unit specifically is not** — this is not a
  general FP-compare or NaN-boxing artifact on our side.
- Most likely an area-optimized, non-correctly-rounded sqrt configuration in the cvfpu/FPnew
  instance.

**Why it had not surfaced.** An end-state memory comparison with any FP tolerance absorbs a
1-ULP difference and passes. Only per-instruction comparison exposes it. In our `fpu_test` the
rounded value then feeds downstream FP ops and a compare/branch, so it cascades.

**What would resolve it for downstream users:** either configure the sqrt unit for correct
rounding, or **document the accuracy guarantee** (e.g. "fsqrt is accurate to ≤1 ULP, not
correctly rounded"). Either is fine; the current situation — an undocumented deviation from a
spec that mandates exactness — is what causes downstream verification effort.

---

## FINDING 3 — `STALL_TIMEOUT` never scales: `1 ** N` ≡ 1 (one-character bug)

**Severity: LOW as written, but see Finding 3b — in combination it makes L2/L3 configs unusable.**

`hw/rtl/VX_config.vh:246`:
```verilog
`define STALL_TIMEOUT (100000 * (1 ** (`L2_ENABLED + `L3_ENABLED)))
```
The evident intent is to widen the stall watchdog as cache-hierarchy depth grows. But `1 ** N` is
always `1` in Verilog, so the timeout is a constant `100000` regardless of L2/L3. The intended
expression is almost certainly `10 ** (...)`.

Consumer: the `STALL_TIMEOUT` runtime assert in `VX_schedule.sv`.

### FINDING 3b — `VX_mem_scheduler` shadows the global timeout with a hardcoded ~1000-cycle budget

**Severity: HIGH for anyone enabling L2/L3 — it makes correct runs look broken.**

`hw/rtl/libs/VX_mem_scheduler.sv:91` declares its own:
```verilog
localparam STALL_TIMEOUT = 10000000;
```
which **shadows** the configurable global. The assert at `:580` is
`($time - pending_reqs_time[i]) < STALL_TIMEOUT`.

**The units are the trap.** This one is in **simulation time**, not cycles. At `timescale 1ns/1ps`
with a 10 ns clock, one cycle = 10,000 time units, so the budget is
`10,000,000 ps = 1,000 cycles`. A full L1→L2→L3→DRAM miss chain under multi-core contention
exceeds that routinely.

**What we observed.** With `L2_ENABLE` + `L3_ENABLE` at 2 clusters / 2 cores / 4 warps /
4 threads, **every** kernel emitted a flood of
`*** <core>-execute-lsu0-memsched response timeout: tag=0x...` — one kernel produced **22,187**
of them.

**It is a false alarm, not a hang.** The same run reached EBREAK at 21,968 cycles with
per-instruction lockstep **matching 2789/2789** (0 PC, 0 rd, 0 data, 0 orphan mismatches) and
zero functional errors. The memory responses did return; they simply took longer than the guard
allows. **The guard fails, not the design.**

Two compounding problems: it is hardcoded (a `+define+STALL_TIMEOUT=…` cannot reach it, because
the localparam shadows the global), and it does not scale with cache depth — which is exactly
what the global in Finding 3 was written to do, and that global is itself a no-op.

**Suggested fix.** Fix `1 ** N` → `10 ** N`, remove the shadowing localparam, and scale the
memory-scheduler budget from the global — being careful that the two timeouts are in **different
units** (the global counts cycles; this one is a `$time` delta), so they cannot simply share a
value.

---

## FINDING 4 — misaligned data accesses: no trap, silently retargeted or torn

**Severity: informational — reporting the hazard, not asking for a feature.**

Misaligned data access is documented-unsupported (`VX_lsu_slice.sv` carries a
"memory misalignment not supported!" assertion, and the halfword byte-enable drops address
bit 0). Our concern is the **failure mode**, not the limitation: there is no
`load/store-address-misaligned` exception, so in a build where the assertion is not active the
access is silently retargeted or torn rather than trapping. Combined with Finding 1 — which
*generates* misaligned addresses from spec-legal code — this converts a spec deviation into
silent data corruption.

This is a reasonable design choice for a GPGPU; it would be valuable to have it stated explicitly
in the documentation, since the RISC-V default expectation is a trap.

---

## What we are offering

1. **PRs for any of the above.** Findings 3/3b are small and self-contained; we have already
   implemented and validated an equivalent guard fix locally.
2. **An independent base-ISA cross-check.** We are integrating **Spike** (`--log-commits`) as a
   second, *independent* reference for the scalar RV32IMF subset, cross-checked against SimX and
   the RTL. Because SimX and the RTL share authorship, a bug class where both are wrong the same
   way is structurally invisible; an independent scalar reference closes that for the base ISA.
   If useful to the project, we would contribute this back.
   *(To be explicit: we are **not** proposing SIMT support in Spike. Vortex's warp/tmask/IPDOM
   state model is not something Spike's single-hart `processor_t` can host without
   re-architecting it — and the result would be a second SimX, not an independent check. Scoping
   Spike to the base ISA is deliberate.)*
3. **Our RTL observation log**, which contains further items we classified as
   expected-behaviour or observability limits rather than bugs, if the project wants them.

---

## SENDER CHECKS — do these two things before filing

1. **Re-verify against upstream `master`.** All findings were made at RTL pin **`7a52ee5`**.
   For each, confirm the cited `file:line` still reads as quoted and the issue is unfixed.
   Adjust or drop anything already addressed — filing a stale bug costs the maintainers' time and
   costs us credibility.
2. **Attach a reproducer to Findings 1 and 2.** For Finding 1, the riscv-dv profile plus the
   `jalr` offset behaviour is enough. For Finding 2, a minimal `fsqrt.s` kernel with the exact
   input operand and the two result words is the strongest possible evidence — include the input,
   not just the outputs.

Optional but worth it: file Finding 3 + 3b together as one issue (they are the same mechanism),
and Findings 1 and 2 separately, since they will need different reviewers.
