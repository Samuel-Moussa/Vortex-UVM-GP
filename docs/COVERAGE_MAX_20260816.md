# Maximising total coverage — 2026-08-16

Two new kernels, three structural waivers, and a blocking correctness gate on the merge.
**Every number below is measured; every kernel was verified against its target BEFORE the suite ran.**

## Result — 1CL/1C/4W/4T, 49 programs, 0 FAILED

| category | 2026-08-15 | **now** | Δ |
|---|---|---|---|
| **TOTAL** | 93.09% | **94.71%** | **+1.62** |
| Conditions | 85.30% | **90.41%** | +5.11 |
| Branches | 93.14% | **95.09%** | +1.95 |
| Toggles | 79.79% | **82.76%** | +2.97 |
| Statements | 97.54% | **98.10%** | +0.56 |
| Assertions | 96.09% | **96.85%** | +0.76 |
| Covergroup bins | 370/377 = 98.14% | 370/377 = 98.14% | — |

Suite grew 47 -> **49 programs**. Conditions went from 268 to **283 covered terms**.

## The two new kernels

### `isa_probe` — the CSR read/write path and FP misc decode
Standalone: PASSED, 188 words byte-exact, 0 errors. Closed **19 of 28** missing
`VX_csr_data.sv` branch items (`:104,132,135-143,196-203`) plus the FCLASS/FMV.X.W decode
(`VX_decode.sv:447-455`).

**Every CSR was checked in BOTH models before being touched**, which is how OBS-036 was found:
* SAFE (both return 0): SATP MSTATUS MEDELEG MIDELEG MIE MTVEC MEPC PMPCFG0 PMPADDR0 MNSTATUS.
* **NOT touched**: `MISA`/`MVENDORID`/`MARCHID`/`MIMPID` — the RTL returns real IDs, SimX returns 0.
  Reading them is a guaranteed LOCKSTEP mismatch.
* **`csrw misa` is a trap**: SimX ignores it, the RTL asserts on it. That is exactly the
  `csrw 0x301` `prepare.sh` sed-strips — the same defect rediscovered from the RTL side.

### `unit_storm` — the first kernel that produces real internal BACK-PRESSURE
Standalone: PASSED, 188 words byte-exact, 0 errors, **13 of 24 condition terms** (reproduced
exactly on a repeat run). In the full suite the figure is **+15**, because other programs
co-congest additional buffers.

Target: `VX_stream_buffer.sv:59 (valid_in || flow_out)` where
`flow_out = ready_out || ~valid_out`. The `valid_in` term can ONLY decide the result when
`ready_out == 0 && valid_out == 1` — a buffer holding data the consumer will not take.
**Nothing covers it until the design is genuinely congested**, which is why running longer never
helped. Mechanism: 4 INDEPENDENT local-memory loads to consecutive words (LMEM_NUM_BANKS =
NUM_LSU_LANES, so 4 banks respond to one requester and contend at one output arbiter), 2 global
loads, 2 `vx_pred` WCTL ops, a `csrr` and FP work — all independent, so the single commit port
(ISSUE_WIDTH=1) becomes the bottleneck and congestion propagates backwards.

Covered: `lmem_arb/g_rsp_arb/req_arb/out_buf`, all four `local_mem/rsp_xbar/g_xbar_arbs[0..3]`,
`lmem_adapter/stream_pack/priority_arbiter`, `sfu_unit/wctl_unit/rsp_buf`.

**⚠ A NEGATIVE RESULT WORTH MORE THAN THE POSITIVE ONE.** A variant with a 64 KB table (4x the
dcache, prime strides, real misses) aimed at `mem_arb/rsp_switch` and `dcache/core_rsp_queue`
scored **WORSE — 11 terms instead of 13** — gaining nothing and LOSING `wctl_unit/rsp_buf`. Heavy
memory stalls did not add congestion, they **shifted the timing balance**: warps waited on memory
instead of issuing densely. **For flow-control coverage, ISSUE DENSITY beats memory volume.**
Reverted, and the finding is recorded in the kernel and the suite entry so it is not "improved" back.

**Also caught before it could mislead:** an earlier revision used `(void)vx_warp_id();` and the
compiler DELETED it — zero `csrr` in the loop. A green run driving nothing (OBS-029 in miniature).
The value is now data-dependent and the loop body is disassembly-verified.

## The merge now polices itself

`merge_coverage.sh` applies exclusions in **two stages** and enforces a **blocking hits-invariant**:
* EOTH (third-party IP that IS executed) may drop covered bins — that is intended;
* EUR (structurally dead) **must change the denominator ONLY**.
If covered counts change across the structural stage, the merge FAILS.

**It immediately caught three real defects**, all of which reported "0 had no effect" and looked fine:
1. a `-linerange` spanning an FSM (reachable and dead lines interleave) — **-3 branch hits**;
2. a `-code c` waiver of `(init_valid | flush_valid)` — Questa cannot waive ONE FEC input term,
   only the whole condition — **-2 cond hits at 1CL, -4 at 2CL**;
3. **a pre-existing waiver**: the single-core global-barrier exclusion had been silently discarding
   a covered condition term since it was added. Withdrawn — it bought +0.03 Total by hiding a hit.

Verified on the final 1CL merge: covered counts byte-identical across the structural stage, 0 "had
no effect".

## 1CL residual — 30 condition terms, all accounted for

| terms | what | why it resists |
|---|---|---|
| 10 | `VX_stream_buffer (valid_in \|\| flow_out)` | needs congestion at buffers `unit_storm` does not reach: `mem_arb/rsp_switch` (simultaneous icache+dcache responses), `dcache/core_rsp_queue`, `alu/pe_switch`, `sfu dispatch buf_out` |
| 9 | arbiter `(grant_valid && grant_ready)` | same class — grant while consumer not ready |
| 4 | `VX_cache_flush:102` | **partly structural, NOT waivable**: `(state==STATE_INIT)` IS reachable (icache init runs) while `(state==STATE_FLUSH)` is not, and Questa cannot waive one FEC term |
| 2 | `VX_cache_bank (init_valid \| flush_valid)` | identical limitation |
| 2 | `issue/dispatch/g_buffers[4]` | **EX_TCU=4** — the TCU dispatch buffer; needs back-to-back WMMA. Deliberately not attempted: TCU tile geometry is a TEMPLATE argument (OBS-029) and getting it wrong yields a green run that verifies nothing |
| 1 + 1 + 1 | `VX_schedule` global barrier · `VX_decode funct3[1:0]!=0` · `VX_lsu_slice` fence | see below |

`VX_decode.sv` `funct3[1:0] != 0` and its `:311-320` body (ECALL/EBREAK/MRET/WFI) are unreachable
for a METHODOLOGY reason: `prepare.sh` rewrites `ecall`->`ebreak` and strips `mret`, `ebreak` is the
TB's primary completion trigger so fetching one ends the run, and kernels exit via `tmc x0`
(OBS-024). Covering it means terminating before the exit code is written — trading a valid
end-state compare for ~0.04 Total points. Same class as OBS-036.
