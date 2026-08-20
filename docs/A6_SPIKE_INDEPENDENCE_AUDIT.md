# A6 — Spike base-ISA independence audit

**Status: DONE (2026-08-07). Result: three-way agreement, 0 mismatches, proven non-vacuous.**

## Why this exists

Our per-instruction lockstep proves **DUT == SimX**. SimX ships with Vortex and is written by
the same authors, so on its own that is a **self-consistency** result: a shared misreading of
the RISC-V specification is invisible to it. This is plan item **FW-2**.

Spike is the RISC-V reference simulator, developed independently of Vortex. Agreement
**DUT == SimX == Spike** on the base-ISA subset therefore closes an axis that no amount of
additional lockstep running could close.

## Scope — read before quoting any number from this document

Spike is a **scalar ISS with no SIMT model**. It cannot execute a Vortex kernel and has no
counterpart for lanes 1..N-1, warps, divergence, or reconvergence. This audit covers **only**:

- warp 0, lane 0
- the base-ISA (RV32IM) instruction subset
- up to the first Vortex custom instruction

It says **nothing** about SIMT behaviour, which remains SimX-only. A green result here must
not be reported as "the design was independently verified". It supports exactly one claim:

> *"The scalar base-ISA writeback stream of the DUT was checked against an independent
> reference model (Spike) as well as against SimX, and all three agree."*

**Zero Spike modification.** Extending Spike to SIMT was considered and deliberately rejected —
it would produce a second Vortex-specific model, which is precisely the dependence we are
trying to escape.

## Method

1. The DUT run dumps the aligned DUT and SimX retirement streams:
   `LOCKSTEP=1 LOCKSTEP_TRACE=<file> make sim TEST=random_instruction_stress_test PROGRAM=<elf>`
   The dump is plusarg-gated and **off by default** (`simulate.sh`, `lockstep_scoreboard.sv`
   `build_phase`), writes a file, and touches no verdict variable — an armed run and a bare
   run reach the same conclusion.
2. Spike runs **the identical ELF**:
   `spike --isa=rv32im --priv=m --log-commits -l <elf>`
3. `vortex_uvm_env/scripts/spike_audit.py` compares the three streams offline.

Running the *same binary* in both models matters: the program the DUT executes is not raw
riscv-dv output. `prepare.sh` seds out machine-mode CSRs and `mret`, converts `ecall`→`ebreak`,
and appends a signature epilogue. Feeding Spike that same linked ELF removes any question of
comparing two different programs.

## Domain alignment — the one substantive methodological point

Naive index-by-index comparison fails immediately: Spike retired **11,487** instructions where
our trace had **11,076**.

That gap is not divergence. Our lockstep is explicitly a **writeback-domain** check
(`lockstep_scoreboard.sv:16`, enforced at `vx_commit_probe.sv:99` and `lockstep_scoreboard.sv:311`),
so instructions with no register writeback — `nop`, `beq`, `jalr x0` — never enter the DUT or
SimX streams at all. Spike logs a register only when one is actually written, so applying the
same filter aligns the domains **exactly**:

| Stream | Writeback retirements |
|---|---|
| Spike (independent) | **11,076** |
| SimX (golden) | **11,076** |
| DUT (RTL) | **11,076** |

Equal lengths are themselves a result: Spike independently agrees on *how many* architectural
writebacks the program performs, before a single value is compared. The comparator reports any
length difference rather than absorbing it, so a dropped or extra retirement still shows up.

This limitation is logged as **OBS-022**.

### Two annotated skips (both verified, neither a defect)

1. **Spike bootrom.** Spike executes a reset vector at `0x1000..0x1010` and then jumps to the
   ELF entry; the DUT begins at the entry directly. The comparator aligns on the first Spike
   retirement at the entry PC and discards that prefix.
2. **`x5` is uninitialised by design.** `prepare.sh` rewrites `csrr x5,0xf14` (mhartid) to
   `nop` because the Vortex RTL implements no machine-mode CSRs. Spike happens to leave
   `0x80000000` in `x5` from its bootrom `lw`; the DUT leaves its reset value. The following
   `beq x5,x6,0f` is harmless — its target *is* `pc+4`, so both directions land identically —
   but the `x5` value differs until overwritten. `x5` is therefore not value-compared until its
   first architectural write. PC is compared throughout.

A third, smaller point: both DUT **and** SimX begin their streams at `0x80000004`, not the
`0x80000000` entry `nop`. Since the two agree, this is a shared convention of our retirement
capture, not a divergence; the audit aligns at `0x80000004`.

## Result

```
==================== A6 SPIKE INDEPENDENCE AUDIT ====================
  spike retirements (from entry) : 11076
  trace retirements (warp 0)     : 11076
  compared (3-way DUT/SimX/Spike): 11076
  mismatches                     : 0
  SCOPE: warp 0 / lane 0 / base-ISA prefix only. Says nothing about SIMT.
====================================================================
```

Program: `riscv_arithmetic_basic_test_0.elf` · DUT run: `TEST PASSED`, 0 UVM errors,
11,076 lockstep pairs matched.

## Non-vacuity — measured, not assumed

A green checker is worthless until shown capable of failing. Both directions were established:

- **Coverage of the check.** All **11,076 of 11,076** records had PC **and** destination
  register **and** written value compared three-way. Zero were skipped: this program performs
  no loads, so the load-data exemption (values are region-filtered per OBS-002) never fired,
  and the `x5` skip applies to at most one record.
- **Fault injection.** Adding 1 to the DUT value of record 5000 in the trace produced:
  ```
  [4999] pc=0x800050fc x24 val spike=0x7ffee4c1 dut=0x7ffee4c2 simx=0x7ffee4c1
  mismatches : 1     (exit 1)
  ```
  The audit named the exact record, register and PC, and distinguished which model disagreed.

## Regression — the trace hook is inert when unarmed (measured, not assumed)

The "default OFF ⇒ armed and bare runs agree" claim was verified rather than argued from the
code. The same ELF was re-run with `LOCKSTEP=1` and **no** `LOCKSTEP_TRACE`:

| | armed | bare |
|---|---|---|
| lockstep pairs matched | 11,076 | **11,076** |
| sim end time | 886025000 | **886025000** |
| UVM errors | 0 | **0** |
| verdict | TEST PASSED | **TEST PASSED** |
| `A6 retirement trace` log line | present | **absent** |

Identical down to the simulation end-time, and the hook emits nothing when unarmed.

**Gate-0 guards re-run after the change (CLAUDE.md rule 5):**

- `negative_result_test` (vecadd_lite) — *"checker DETECTED the injected fault at
  addr=0x800075d8 (it matched before injection, mismatched after). Verdicts are not vacuous."*
- `negative_dropped_store_test` (vecadd_lite) — PASSED.

Both still catch their injected faults, so neither Gate-0 guard was weakened. This is expected
— the change is confined to `lockstep_scoreboard.sv` and `simulate.sh` and does not touch the
end-state scoreboard — but it was checked rather than assumed.

## Files

| File | Role |
|---|---|
| `vortex_uvm_env/uvm_env/lockstep_scoreboard.sv` | `+LOCKSTEP_TRACE=<path>` retirement dump (default OFF) |
| `vortex_uvm_env/scripts/simulate.sh` | `LOCKSTEP_TRACE` env → plusarg passthrough |
| `vortex_uvm_env/scripts/spike_audit.py` | offline three-way comparator |
| `docs/RTL_OBSERVATIONS.md` | OBS-022 (writeback-domain observability limit) |

## What is still open

- Only one program has been audited. Extending to the other retained riscv-dv tests is cheap
  (each is one armed run plus a free Spike run) and is the obvious next increment.
- Stores are outside the lockstep domain entirely and remain covered only by the end-state
  memory compare (OBS-022).
- SIMT behaviour has no independent reference and will not have one from Spike.
