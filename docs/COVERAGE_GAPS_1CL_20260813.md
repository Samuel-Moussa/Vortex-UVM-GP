# 1CL COVERAGE BANK — 2026-08-13 — RESULT AND EXACT REMAINING GAPS

**Config:** 1CL / 1C / 4W / 4T RV32 AXI (primary) · **44 distinct programs, 44 staged, 0 FAILED**
**Bank:** `vortex_uvm_env/cov/bank_1CL_1C_4W_4T/` (merged.ucdb + merged_raw.ucdb + report/ + 44 staging UCDBs)
**Predecessor preserved as:** `cov/bank_1CL_1C_4W_4T_prefix_20260812/`

This is the first bank taken AFTER the four fixes (`3d0ec30`, `47d6e7a`, `eb8a630`), i.e. the first
one where every riscv-dv and `barrier_test` result is architecturally DEFINED.

## Result

| category | bins | hits | misses | coverage |
|---|---|---|---|---|
| Assertions | 128 | 123 | 5 | 96.09% |
| Branches | 2831 | 2578 | 253 | 91.06% |
| Conditions | 313 | 238 | **75** | **76.03%** |
| Covergroup bins | 403 | 398 | 5 | 98.75% (99.12% weighted) |
| Directives | 5 | 5 | 0 | 100.00% |
| Statements | 4443 | 4302 | 141 | 96.82% |
| Toggles | 425444 | 333662 | 91782 | 78.42% |
| **Total** | | | | **91.08%** |

Instances: 2256.

**Questa's "Total" is the UNWEIGHTED MEAN of the 7 categories**, each 1/7 regardless of bin count.
So the LOWEST category is the biggest lever on the total, not the one with the most missing bins:
**conditions (76.03%) moves the total more than toggles (78.42%) despite having 91,707 fewer misses.**

## ⚠ Identical to the pre-fix bank — and that is the finding

Every one of the seven categories, the total, the bin counts and the instance count are
**bit-identical** to the 2026-08-12 bank. Two conclusions:
1. **The four fixes are coverage-neutral at 1CL.** They removed undefined behaviour without
   removing stimulus — expected, since at 1CL every core gate is a fall-through.
2. **It re-proves FW-1b from a second, independent direction.** The suite went from 45 runs to 44
   by dropping `riscv_pmp_test`, and **not one bin moved**. A genuinely distinct program cannot
   contribute zero new coverage. This corroborates the md5 evidence by a completely different route.

## THE 5 UNCOVERED COVERGROUP BINS (exact)

Extracted from the bank's own `report/functional.txt`. Everything else reported ZERO is an
`ignore_bin` — deliberately waived, structural, and NOT in the denominator.

### Genuinely targetable — 2 bins, THE ONLY REAL FUNCTIONAL GAP

| bin | instance |
|---|---|
| `cache_event_cg.cp_mshr_stall.stall` | `…/socket/dcache/…/g_banks[0]/bank/u_cache_probe` |
| `cache_event_cg.cp_mshr_stall.stall` | `…/socket/icache/…/g_banks[0]/bank/u_cache_probe` |

Both read `no_stall = 4,634,935` hits and `stall = 0`. **Left honestly uncovered — never waived.**
To close them the stimulus must fill the MSHR so a new miss cannot allocate:
- **dcache:** more SIMULTANEOUS outstanding independent misses than the MSHR has entries.
  `mem_stress` issues 12-load bursts (NLD=12, the proven-safe depth — NLD=32 spills registers and
  deadlocks a warp at spawn-join). Closing this needs the burst depth raised toward/past the MSHR
  size, or several warps bursting at once, WITHOUT reintroducing the register-spill deadlock.
- **icache:** simultaneous instruction misses from multiple warps at DIFFERENT cache lines. Needs
  a large resident `.text` (`text_big` is 232 KB) combined with warps at widely-separated PCs —
  i.e. divergent control flow across warps, not the single-warp sweep `text_big` does today.

### Weight-0 red herrings — 3, NOT closable and NOT defects

| bin(s) | why |
|---|---|
| `system_cg.mem_usage_cp` {idle, read, write} | the MEM interface is IDLE on AXI runs (`USE_AXI_WRAPPER`); the DUT drives AXI instead |
| `system_cg.system_mem_cross <*,*>` | cross built on `mem_usage_cp`, so it cannot fill either |
| `sched_state_cg.cp_occ` | probe is not wired |

These carry weight 0, which is why weighted covergroup coverage reads **99.12%** against the raw
**98.75%**. Do not chase them; do not waive them either — they are documented as-is.

## CODE-COVERAGE GAPS, by lever size

**1. Conditions — 75 misses / 313 (76.03%). Biggest total-mover.** Lowest category ⇒ largest
effect on the unweighted mean. Historically unexamined; known contributors are idle-path
`stream_buffers`, host-only `cache_flush`, and arbiter backpressure. **This is the least-explored
category and the highest-yield next audit.**

**2. Branches — 253 misses / 2831 (91.06%).** Known classes: M-mode CSR paths (SimX-divergent),
decode forms never emitted by our toolchain, `cache_flush`/`cache_init` paths.

**3. Statements — 141 misses / 4443 (96.82%).** Largely the same paths as the branch misses.

**4. Assertions — 5 misses / 128 (96.09%).** Documented as the hard residue: master-side `r`/`b`
backpressure (`assert_r_valid_stable`, `assert_r_data_stable` — reachable but the DUT read buffer
is deep enough that even `+AXI_FLOOD` never forces `rready` low), reset-window sampling, and
outstanding-transaction corners.

**5. Toggles — 91,782 misses / 425,444 (78.42%). STRUCTURAL, do not chase.** Root-caused
2026-07-10: `DCACHE_WRITEBACK=0` (write-through) plus a read-only icache leave the 512-bit
full-line write-data fields permanently undriven, and `pc[18:30]`/addr/tag high bits are constant
for small aligned programs. A max-entropy `toggle_stress` kernel moved aggregate toggle **+0.02%**.
Realism-limited, NOT honestly excludable, and NOT worth further stimulus effort.

## Ordered plan to push coverage higher

1. **Multi-core kernels with per-core data regions** (index `vx_core_id()*nw + wid`). The four
   fixes made every result defined, but they did so by REMOVING concurrency from the stimulus:
   riscv-dv and `barrier_test` are now single-core at every config. Nothing in the suite currently
   exercises multiple cores against shared data with correct synchronisation. This is both the
   largest 2CL functional gap and the most defensible thing to add (also addresses FW-3 / FW-7).
2. **Close the 2 `cp_mshr_stall.stall` bins** — the only real functional gap at 1CL, per above.
3. **Audit conditions (76.03%)** — biggest lever on the total, and never systematically examined.
4. Branches / statements — same paths, smaller yield.
5. **Stop at toggles.** Structural; chasing them means gaming realism.

## Cross-references

- Bin dispositions and waiver rationale: `docs/Coverage_Model_Reference.md`
- The four fixes and their measured acceptance: `docs/INDUSTRIAL_TRANSFORMATION_PLAN.md`
- OBS-026 / OBS-027 (why the pre-fix multi-core results were undefined): `docs/RTL_OBSERVATIONS.md`
- ⚠ Never blend 1CL and 2CL UCDBs — a cross-config merge is invalid (vcover-6821 width toggles
  plus per-core instance inflation).
