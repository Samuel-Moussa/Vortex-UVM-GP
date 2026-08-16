# What the total-coverage ceiling actually is, and why — 1CL, 2026-08-16

Baseline: **93.43%** (1CL/1C/4W/4T, post-toggle-waiver bank). Every number below is MEASURED from
`cov/bank_1CL_1C_4W_4T/merged.ucdb`, not estimated. No simulation was run.

## 0. The arithmetic that governs everything

Questa's "Total" is the **unweighted mean of 7 categories**, each 1/7 regardless of bin count.
Verified exactly: `(96.09+93.14+85.30+99.79+100+97.54+82.16)/7 = 93.4314` vs 93.43 reported.

| category | bins | now | gap | **Total pts if driven to 100%** |
|---|---|---|---|---|
| Toggles | 413,172 | 82.16% | 17.84 | **2.549** |
| Conditions | 313 | 85.30% | 14.70 | **2.100** |
| Branches | 2,831 | 93.14% | 6.86 | 0.980 |
| Assertions | 128 | 96.09% | 3.91 | 0.559 |
| Statements | 4,443 | 97.54% | 2.46 | 0.351 |
| Covergroups | 377 | 99.79% | 0.21 | 0.030 |
| Directives | 5 | 100.00% | 0 | 0 |

**⚠ THE METRIC IS WILDLY NON-UNIFORM: one Directive bin is worth 82,634 Toggle bins.** Optimising
"Total" and optimising verification quality are different activities, and past a point they diverge.
**313 condition bins carry 82% as much weight as 413,172 toggle bins.** Conditions are therefore the
best real target; toggle is the biggest number and the worst value per unit of effort.

## 1. Where every miss actually is (measured)

### Statements — 109 misses, 60 distinct source lines
| lines | file | class |
|---|---|---|
| 23 | `VX_decode.sv` | mixed (see §2) |
| 11 + 5 | `VX_cache_init.sv` / `VX_cache_flush.sv` | **STRUCTURAL — icache flush FSM** |
| 8 | `VX_csr_data.sv` | M-mode CSRs — **REACHABLE** |
| 6 | `VX_gpu_pkg.sv` | FCLASS/FMV.X.W helpers — **REACHABLE** |
| 5 | `VX_pending_size.sv` | almost-full/empty thresholds |
| 2 | `VX_stream_xbar.sv` | arbitration edge |

### Branches — 194 misses, 67 distinct
`VX_csr_data.sv` 28 · `VX_decode.sv` 10 · `VX_cache_flush.sv` 8 · `VX_cache_init.sv` 8 ·
`VX_pending_size.sv` 5 · `VX_gpu_pkg.sv` 4 · misc 4.

### Conditions — 46 missing input terms (the 2.1-point category)
| terms | expression | class |
|---|---|---|
| **24** | `VX_stream_buffer (valid_in \|\| flow_out)` | idle-path buffers never back-pressure |
| 7 | `VX_cache_flush` state/counter terms | **STRUCTURAL — icache** |
| 6 + 4 | `VX_priority_arbiter` / `VX_rr_arbiter` `(grant_valid && grant_ready)` | needs grant-with-consumer-not-ready |
| 2 | `VX_cache_bank (init_valid \| flush_valid)` | **STRUCTURAL — icache** |
| 2 | `VX_lsu_slice` fence terms | reachable |
| 1 | `decode` | reachable |

**One expression in one module is 52% of the entire condition gap.**

### Assertions — 5 misses
`assert_r_valid_stable` + `assert_r_data_stable` (`vortex_axi_if.sv:383,386`) — reachable, but the
DUT read buffer is deep enough that even `+AXI_FLOOD` never forced it (session 10 finding, still
true). `assert_rlast_on_last_beat` (`:507`) — **STRUCTURAL**: `arlen` is hardwired 0, so every beat
is the last and the antecedent never arms; same citation as the existing `awlen` waivers.
`assert_reset_clears_valids` (`vortex_if.sv:180`) x2 — reset-window sampling, TB infrastructure.

### Toggles — 73,685 missing bins / 44,726 dead nodes
| share | bucket | class |
|---|---|---|
| 51.1% | core datapath (`execute` 10,046 nodes, `issue` 4,721) | operand/result high bits — realism-limited |
| 15.8% | icache remainder (buffer aliases) | **OPEN** — see OBS-033 |
| 12.7% | local memory | partly reachable |
| 10.7% | dcache write-through payload | structural-ish |
| **7.3%** | **uuid counter bits [18:31]** | **ARITHMETICALLY UNREACHABLE** |
| 2.4% | PC bits | `PC[1:0]` structural (4-byte align); high bits realism-limited |

## 2. A NEW proven-structural waiver, MEASURED

**The icache flush FSM cannot be entered by any program, at any config.**
* `VX_cache_init.sv:91` — the only way to raise flush is `req_data.flags[MEM_REQ_FLAG_FLUSH]`.
* `VX_lsu_slice.sv:73` — the **only producer of that flag in the entire design**, on the LSU/dcache path.
* `VX_fetch.sv` contains the string "flush" **zero times**.
* **Positive control:** the identical code is **fully covered on the dcache** — `VX_cache_init` 25/25,
  `VX_cache_flush` 16/17 — and dead on the icache (14/25, 12/17). Same RTL, same run: the difference
  is the instantiation, not the stimulus.

Applied to the icache instances only, excluding the state BODIES but **not** the `if` lines (which
have a legitimately-covered false arm):

| | before | after |
|---|---|---|
| Statements | 97.54% | **97.89%** |
| Branches | 93.14% | **93.81%** |
| Conditions | 85.30% | **85.85%** |
| **Total** | **93.43%** | **93.65%** |

Hits: stmt 4334→4334, branch 2637→2637, cond 267→267 — **not one covered bin lost**, 0 "had no effect".

⚠ **Two Questa traps found while doing this**, both silent:
1. `coverage exclude -scope … -recursive -srcfile …` **does nothing and reports no error.** Use a
   scope that names the FSM instance directly.
2. Excluding a whole `-linerange` over an FSM drops covered bins, because reachable and unreachable
   lines interleave. The hits-unchanged check is the only thing that catches it — it caught 3.

## 3. The realistic path, in value order

| step | action | Total | cumulative |
|---|---|---|---|
| 0 | now | — | **93.43%** |
| 1 | icache flush FSM waiver (**measured above**) | +0.22 | **93.65%** |
| 2 | `rlast` + `cache_bank` flush terms (same citation) | ~+0.30 | ~93.95% |
| 3 | **M-mode CSR read kernel** (`csrr` on MVENDORID/MARCHID/MIMPID/MISA/SATP/MSTATUS/…) — reads return constants, so it is scoreboard-safe; recovers 28 branch + 8 stmt | ~+0.17 | ~94.1% |
| 4 | FCLASS / FMV.X.W / FMSUB / FNMSUB kernel | ~+0.08 | ~94.2% |
| 5 | **back-pressure campaign on conditions** (stream buffers + arbiters) — the highest-value work per bin in the whole project | +0.9 … +2.0 | 95.1 – 96.2% |
| 6 | AXI read back-pressure deep enough to arm `r_valid`/`r_data_stable` | +0.23 | ~95.3 – 96.4% |
| 7 | toggle push (local memory, datapath entropy) to ~88% | +0.83 | **~96 – 97%** |

**Honest ceiling: ~96–97%.** Step 5 is where the real leverage is and it is genuine verification
work (making buffers and arbiters back-pressure is exercising the design, not gaming the metric).

## 4. Why 100% is not reachable — three provable reasons

1. **The uuid counter is arithmetically out of reach.** `VX_uuid_gen.sv:40-41` gives each warp a
   32-bit instruction counter. Bits [18:31] measure 0; bit 31 needs 2^31 ≈ 2.1e9 retired
   instructions **on a single warp**. Those 6,486 bins are **1.57% of the toggle denominator**, so
   even with everything else at 100%, **toggle ≤ 98.43% and Total ≤ 99.78%**. Not "hard" — impossible.
   And it cannot be removed: `NDEBUG` would set `UUID_WIDTH=1` and destroy the key that
   `lockstep_scoreboard.svh` / `vx_commit_probe.sv` / `simx_dpi.cpp` correlate on (OBS-034).
2. **Realism-limited datapath bits (51% of the toggle residual).** High bits of 32-bit operands,
   FP mantissa bits, address tags — constant for programs that compute meaningful results. This is
   not speculation: `wide_stress` (256 KB sparse high-entropy) moved aggregate toggle **+0.6%**, and
   `toggle_stress` (max-entropy, multi-core, complementary cache-line patterns) moved **+0.02%**.
   Two purpose-built kernels; that is the measured return.
3. **Some paths need a config we reject for cause.** `FCVT.S.D`/`FCVT.D.S` (`VX_decode.sv:405-409`)
   need the D extension in the *compiler target*; we build `rv32imaf`, so soft-double libcalls are
   emitted instead — the same rationale already accepted for the `instr_class_cg_fpu` F2F waiver.

**The blunt version: Total *can* be driven to 100% — by waiving the realism-limited bits. That would
raise the number without verifying one additional thing, and it violates this project's own rule
that only structurally-dead coverage is excluded. The gap between ~96% and 100% is the honest part
of the report, and it should be stated in the paper rather than closed.**

---

# Addendum — the 2CL picture, and where the remaining leverage really is

Measured from `cov/bank_2CL_2C_4W_4T/merged.ucdb` (total **93.07%**).

## 2CL conditions: 217 missing terms, and 84% of them are TWO expressions

| terms | expression | class |
|---|---|---|
| **128** | `VX_stream_buffer.sv:59 (valid_in \|\| flow_out)` | needs a consumer that will not accept |
| **55** | `VX_priority_arbiter` / `VX_rr_arbiter (grant_valid && grant_ready)` | needs a grant while the consumer is not ready |
| 10 | `VX_cache_flush` state/counter terms | structural (icache) |
| 8 | `VX_lsu_slice` fence terms | reachable |
| 4 + 4 + 4 | `VX_schedule` global barrier · `VX_decode funct3[1:0]!=0` · `VX_cache_bank` | mixed |

Compare 1CL (24 + 10). **The stream-buffer class scales with the topology** — more cores, more
sockets, more buffer instances, and every added instance is starved the same way.

**Both leading classes require the SAME physical condition: back-pressure.**
`flow_out = ready_out || ~valid_out` (`VX_stream_buffer.sv:54`), so the `valid_in` term can only be
the deciding input when `ready_out == 0 && valid_out == 1` — the buffer is holding data the consumer
will not take. Identically, `grant_valid` can only decide `(grant_valid && grant_ready)` when
`grant_ready == 0`. **Nothing in either class is covered until the design is genuinely congested.**

⇒ this is the opposite of a metric-chasing target. It is flow-control logic the suite has never
stressed, and covering it means actually exercising it.

**Potential:** 183 of 217 terms. If fully covered, 2CL conditions go 81.54% → ~97% and Total gains
**~+1.5 points**; 1CL gains ~+1.0. That makes it the single biggest honest lever remaining, larger
than everything else on the roadmap combined.

## Revised category ranking (2CL)

| category | now | pts if 100% | realistic |
|---|---|---|---|
| Toggles | 79.47% | 2.93 | hard — 51% is realism-limited datapath |
| **Conditions** | **81.54%** | **2.64** | **~1.5 reachable via back-pressure** |
| Branches | 94.05% | 0.85 | partly closed by `isa_probe` |
| Statements | 98.03% | 0.28 | partly closed by `isa_probe` |
| Assertions | 98.87% | 0.16 | 2 need deep AXI read back-pressure |
| Covergroups | 99.52% | 0.07 | 2 `cross_dvg_depth` bins |

## What "unreachable" means here — three distinct classes, do not conflate them

1. **Structurally dead** — the hardware cannot do it, at any config, under any program.
   *Icache `WRITE_ENABLE(0)` payload; icache flush FSM (one producer, on the dcache path);
   `rlast` under a single-beat master.* Proven, and proven with a positive control where possible
   (identical source fully covered on the dcache). **Waived.**
2. **Arithmetically unreachable** — reachable in principle, impossible in practice by a margin no
   engineering can close. *uuid counter bit 31 needs 2^31 instructions on one warp.* Caps toggle at
   98.43% and Total at 99.78%. **Not waived** — it is live logic, and "infeasible" is not "dead".
3. **Unreachable under the verification contract** (OBS-036) — the hardware executes it correctly,
   we know exactly how to hit it, but the golden model provably disagrees, so any test that covers
   it must abandon end-state/lockstep equivalence. *`MISA`/`MVENDORID`/`MARCHID`/`MIMPID` reads.*
   **Not waived.** This class is a property of the METHOD, not of the DUT or of our effort, and it
   is the one most worth stating explicitly in the paper.

Class 1 is a denominator correction. Classes 2 and 3 are the honest residual and should be reported,
not closed.
