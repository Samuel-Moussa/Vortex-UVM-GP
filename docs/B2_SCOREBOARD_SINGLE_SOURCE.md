# B2 — end-state scoreboard collapsed to a single source of truth

**Status: DONE (2026-08-07), commit `f279357`. Validated by differential, not by assertion.**

## What was wrong

The end-state DUT-vs-SimX memory compare maintained **two** representations of DUT memory:

1. `shadow_memory` — a 64-bit-per-slot associative array reconstructed inside the scoreboard by
   re-assembling every snooped write transaction (`write_mem`, `write_axi`).
2. `dut_mem` (`mem_model`) — the DUT's **real** backing store, preloaded with the program image
   at `vortex_tb_top.sv:185` and written byte-accurately by the responders that actually serve
   the DUT (`axi_driver.sv:218`, `mem_driver.sv:129`).

Two representations of the same thing can disagree, and only one of them is what the DUT
actually read and wrote. A reconstruction that drifts — one mis-parsed beat, one missed
`byteen` — produces either a false failure or, worse, a false pass.

The drift risk was not hypothetical: the forward pass had **already** been switched to read
values from `dut_mem`, leaving `shadow_memory` as a maintained-but-unused data copy whose only
remaining job was to supply the *set* of addresses to iterate.

## What changed

| Before | After |
|---|---|
| `shadow_memory` (data) + `shadow_valid` (byte mask) | `dut_write_mask` (byte mask) only |
| DUT value from `dut_mem`, fallback to shadow | DUT value from `dut_mem`, **no fallback** |
| `mem_model` optional (absent ⇒ degrade quietly) | `mem_model` **mandatory** (absent ⇒ `uvm_fatal`) |
| `compare_result_region` defined, never called | deleted (53 lines) |

Net **−41 lines**, and one fewer thing that can be wrong.

`mem_model` was made mandatory deliberately. Previously its absence downgraded the check
silently; that is the worst possible failure mode for a checker, because the run still goes
green while comparing nothing. It now fails loud and names the fix.

## The part the plan got wrong

The original plan said *"delete `shadow_memory` + `shadow_valid`"*, reasoning that because
`mem_model` holds real init bytes, the sub-word byte-mask becomes unnecessary.

That is **half right, and the missing half is load-bearing.**

The mask's *original* purpose does dissolve: it was added (`4b7c55c`) because the sparse shadow
read back `0` on lanes the DUT never wrote, while SimX returned the merge of store + `.data`
init — a false mismatch. Once the value comes from `mem_model`, which *is* preloaded with
`.data`, those lanes agree naturally.

But the mask had acquired a second purpose:

1. **It makes the SimX-poison gate byte-granular.** SimX fills untouched memory with
   `BAADF00D`. Consider a dword where the DUT wrote bytes 0–3 via `sb`/`sh` and SimX left
   poison in bytes 4–7. Masking *before* the poison test zeroes the poisoned lanes on both
   sides, so the four valid lanes are still compared. Delete the mask and the poison gate sees
   `BAADF00D` in the upper half and discards the **whole dword** — a real check lost silently.
2. **It is the forward/reverse discriminator.** The reverse pass skips any address the DUT
   wrote (`if (dut_write_mask.exists(waddr)) continue;`). Without the write-set there is no way
   to say "SimX wrote here and the DUT never did", which is precisely the dropped-store guard
   from `fe10b83`.

So `shadow_valid` was kept and renamed `dut_write_mask` — the new name states what it is: a
**set of locations to check**, never a record of what they hold.

## Validation — differential against stored baselines

Every number below was compared against a **pre-B2 run of the same program at the same config**,
recovered from `vortex_uvm_env/results/`. No test was re-run to *establish* a baseline; the
baselines already existed. An equal count is the point: it proves the compare set did not
silently narrow.

| Test | Baseline `data_compared` | Post-B2 | |
|---|---|---|---|
| `cache_tier` | 16,452 | **16,452** | ✅ |
| `riscv_mmu_stress_test` | 1,414 | **1,414** | ✅ |
| `riscv_no_fence_test` | 490 | **490** | ✅ |
| `riscv_rand_instr_test` | 436 | **436** | ✅ |
| `sfu_masks` | 124 | **124** | ✅ |
| `vecadd_lite` | 84 | **84** | ✅ |
| `tcu_test` | 76 | **76** | ✅ |
| `riscv_arithmetic_basic_test` | 15 | **15** | ✅ |
| `fpu_test` | 8 | **8** | ✅ |
| | **18,749 total** | **18,749** | |

`skipped_stack/MMIO`, `skipped_poison` and `skipped_got` were identical on every run too, so
the skip classification did not shift either.

The riscv-dv tests were re-run against their **stored ELFs**, not regenerated. FW-1 (no seed
control) means `RISCV_DV_REGEN=1` produces a *different program*, which would have made the
comparison meaningless. These four are also the tests the byte mask was originally introduced
to recover, so they are the highest-risk cases for this refactor specifically.

`div_edge`, `vote_shfl` and `bar_masks` also pass at 1CL but are **not** in the table: no pre-B2
1CL baseline exists for them (they had only ever been run at 2CL), so there is nothing to diff
against and claiming otherwise would be dishonest.

`fpu_test` shows `fp_tol_passed` varying 0↔1 across runs. This is **pre-existing** and tracks
lockstep/`LOADFEED` arming — the two-pass feed writes SimX, changing the golden value — not B2;
pre-B2 1CL runs show both values at the same `data_compared=8`.

## Non-vacuity — both Gate-0 guards still fail on injection

| Guard | Result |
|---|---|
| `negative_result_test` | injected at `0x800075d8`, **detected**, "Verdicts are not vacuous" |
| `negative_dropped_store_test` | `DROPPED STORE addr=0x800075d8 DUT(mem)=0x0 SimX=0x600dc0de`, **caught** |

Both fired at the **same address** as pre-B2. That is not luck: the drop-injection candidate
search was tightened to require a fully-written dword (`dut_write_mask[a] !== 8'hFF → skip`),
which reproduces the pre-B2 selection exactly. The old code compared the raw shadow dword
against SimX, and a partially-written slot had zeros in its unwritten lanes, so it could never
match — the constraint was implicit. Making it explicit keeps the negative test deterministic
rather than letting the candidate set quietly widen.

## Full-suite gate

`scripts/run_suite.sh` @1CL/1C/4W/4T: **44 staged, 1 failed.** The single failure is `text_big`,
and it is **proven not to be B2** by direct A/B — the pre-B2 scoreboard was restored from backup
and the same program run at the same 400,000-cycle budget:

| | pre-B2 | post-B2 |
|---|---|---|
| verdict | TIMEOUT @400000 | TIMEOUT @400000 |
| Total Cycles | 399,999 | 399,999 |
| Instructions | **46,151** | **46,151** |

Identical to the digit. `text_big` is a fetch-bound kernel (232KB resident `.text`, 600
`noinline` functions in a runtime-indexed reverse sweep) retiring at ~0.12 IPC; the log shows
memory ops and retired instructions still climbing monotonically at cycle 399,999 with `busy=1`,
i.e. **forward progress, not a hang** — the INV-1 signature. `assert_busy_eventually_idles` fired
as a *consequence* of the timeout truncating the run, not as a cause. The `data_compared` field
is absent because completion never fired, so the end-state compare (the only thing B2 changed)
never executed at all.

Merged covergroup bins 398/407 (97.78% raw). The 9 residual are `mem_usage_cp` /
`system_mem_cross` (documented weight-0: idle MEM interface on AXI runs) and `cp_occ` on one
cache-probe instance from the G1 work. B2 defines no covergroups, so this is not a B2 metric.

## Known residual gap — OBS-023

Keeping the mask preserves the poison-granularity check but leaves one blind spot, now logged:
a dropped **sub-word** store into a dword the DUT otherwise wrote is invisible — the forward
pass masks that lane away, and the reverse pass declines to inspect an address the DUT wrote.
Full-dword drops **are** caught (proven live, above).

Not fixed here: closing it changes which lanes are authoritative, which needs its own negative
test to prove non-vacuity. The clean fix is to make the poison gate byte-granular *directly*
(test each lane's containing 32-bit half for `BAADF00D`) instead of using the write-mask as a
proxy, then compare all lanes of a written dword. See `docs/RTL_OBSERVATIONS.md` OBS-023.

## Files

| File | Change |
|---|---|
| `vortex_uvm_env/uvm_env/vortex_scoreboard.sv` | −114/+73 lines; `shadow_memory` and `compare_result_region` deleted, `shadow_valid`→`dut_write_mask`, `mem_model` mandatory |
| `docs/RTL_OBSERVATIONS.md` | OBS-023 |
| `docs/INDUSTRIAL_TRANSFORMATION_PLAN.md` | B2 closed; the "delete both" spec corrected in place |
