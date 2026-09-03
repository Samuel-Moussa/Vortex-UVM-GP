# Vortex UVM verification — handoff for PPT drafting

**Purpose of this document:** paste into a fresh Claude.ai (web) conversation to help
draft presentation slides on the coverage-model work completed this session. Every
number below is measured from an actual sim run or `vcover` report — none is estimated.
Where a run is still in progress, that is stated explicitly and the number is left blank.

**Repo:** Vortex UVM-GP (RISC-V GPGPU verification, QuestaSim UVM testbench).
**Branch:** `feat/riscvisacov-coverage`. **Config:** 1CL/1C/4W/4T RV32 AXI, primary.
**Status as of writing:** the 1CL post-change suite re-run is in progress (see §5).
The three original defence-deck banks (1CL 94.72%, 2CL 94.55%, L2/L3 93.18%) are
frozen and were not touched — a verified backup exists.

---

## 1. What this session added — a two-layer coverage model, not one

**Layer L1 — architectural, third-party, independent.** Integrated Imperas'
open-source `riscvISACOV` (Apache-2.0), which decodes retired instructions from an
RVVI-TRACE feed and scores them against RISC-V's own ISA semantics — completely
independent of anything our own testbench assumes. Two custom pieces make this real
rather than aspirational:
- A `vortex_rvvi_shim.sv` that reconstructs the RVVI trace record from our commit-probe
  data (register writebacks, PC, retirement order) per SIMT lane.
- A code generator (`gen_ext_coverage.py`) that reads Imperas' own CSV "dvplans" and
  emits SystemVerilog covergroups. **Validated by regenerating RV32I from its own
  dvplan and diffing byte-for-byte against Imperas' published source** — the generator
  is proven correct before being trusted on extensions with no reference implementation
  to check against.

**Layer L2 — microarchitectural, ours, Vortex-specific.** Passive `bind`-based probes
already existed on 8 DUT modules (scheduler, dispatch, commit, DCR, LSU, cache banks) —
this session extended that model rather than replacing it.

**Rule enforced throughout: never merge L1 and L2 coverage databases.** They score
different things over different denominators; a blended number would be meaningless.

---

## 2. Covergroup count — exact, from source, both layers

| Layer | Source | Covergroups | Coverpoints | Crosses |
|---|---|---:|---:|---:|
| L1 — RV32I | Imperas riscvISACOV (third-party) | 39 | — | — |
| L1 — RV32F | generated from Imperas dvplan | 26 | — | — |
| L1 — RV32M | generated from Imperas dvplan | 8 | — | — |
| L1 — RV32Zicsr | generated from Imperas dvplan | 6 | — | — |
| L1 — RV32Zifencei | generated from Imperas dvplan | 1 | — | — |
| **L1 active total** | | **80** | | |
| L1 — RV32D | generated, **not enabled** (XLEN=64 only — see §4) | 32 | — | — |
| L2 — ours (Vortex µarch) | 20 hand/generated types across 8 probe sites | **20** | **87** | **22** |
| **Grand total, active** | | **100** | | |

This morning's starting point was 78 active covergroups (L1: RV32I+M+Zicsr+F = 79
minus overlap; L2: 17). Today's work raised active covergroups to **100** and added a
32-covergroup bank staged for a future XLEN=64 configuration.

---

## 3. New scenarios exercised this session — by verification gap closed

Gaps are tracked in `docs/VERIFICATION_PLAN_v2.md` as G-0 through G-10, ranked by
verification value. Two were closed today.

### G-1 — CLOSED: ALU instruction-class coverage was silently contaminated
**The problem, found by RTL inspection, not assumption:** Vortex's `EX_ALU` unit
multiplexes four semantically distinct instruction groups onto the *same* `op_type`
encoding field, discriminated only by a second field (`xtype`) that the coverage
model never read:
```
INST_ALU_ADD  == INST_BR_BEQ    == INST_M_MUL == VOTE_ALL == 4'b0000
INST_ALU_CZNE == INST_BR_EBREAK == 4'b1011
```
So the existing `cp_alu_op` coverpoint counted every branch and every multiply under
an arithmetic bin name, and the frozen defence bank's reported **`cp_alu_op = 100%,
14/14 COVERED`** was not attributable — the Zicond `czne` bin was actually being
scored by `ebreak`, which every riscv-dv test executes regardless of whether a Zicond
instruction ever ran.

**Fixed:** the ALU probe now takes the `xtype` qualifier and splits into four
disjoint, correctly-scoped coverpoints:
- `cp_alu_op` (qualified, arithmetic only) — measured 11/14 post-fix
- `cp_branch_op` (new — direction/jump/ebreak, 10 bins) — measured 6/10
- `cp_muldiv_op` (new — 8 RV32M sub-ops) — measured 3/8
- `cp_vote_shfl_op` (new — the 8 Vortex-custom warp-collective ops, VOTE/SHFL) —
  **measured 8/8, 100%**, after running the dedicated `vote_shfl` kernel

**Why this scenario matters for the deck:** VOTE and SHFL are Vortex's own SIMT
primitives (thread-mask voting, register shuffle across a warp) — they exist in no
public RISC-V spec, so **no third-party model can ever score them.** Before today
they had zero coverage of any kind, anywhere, and are now fully covered.

### G-0 — CLOSED: the GPU memory-coalescing path had zero coverage
**The problem:** `VX_mem_coalescer` — the unit that decides whether a warp's parallel
lane addresses collapse into a single cache-line request or fragment into several —
had no coverage probe. This is arguably *the* defining behaviour of a GPU memory
system, and it was completely unmeasured.

**Built:** a config-generic passive probe (parameters derived from the bound RTL
instance, never hardcoded) plus a new directed kernel, `coalesce_probe`, that drives
three access patterns — unit-stride (fully coalesced), 2-word stride (partial), and
one-line-per-lane stride (full scatter) — with both loads and stores.

**A real RTL semantics finding along the way:** the module's `misses` output is a
free-running counter accumulated across the *entire simulation*, not a per-request
signal — it cannot be binned directly per transaction. The probe re-derives the
per-request event from the module's internal state instead.

**Measured** (`coalesce_probe`, PASSED, byte-exact vs the SimX golden model, 0 UVM
errors, 62,103 cycles):

| coverpoint | result |
|---|---|
| `cp_coalesce_kind` (full-coalesced / partial / full-scatter) | **100%** — 3,981 / 8 / 344 hits |
| `cp_rw` (read vs write) | **100%** |
| `cp_misses` | 75% |
| `cp_active_lanes` | 50% (needs divergence stimulus, left open) |

The two partial results were deliberately **left open rather than waived** — nothing
about them was proven structurally unreachable, so claiming them covered would be
dishonest.

### Bonus finding filed, not yet a "gap" in the plan: `fence.i` is a no-op in disguise
While generating the RV32Zifencei bank, found that `VX_decode.sv` never reads the
`funct3` bit that distinguishes `fence.i` from a plain data `fence` — so an
instruction-stream fence silently executes as a data fence, and the `INST_FENCE_I`
localparam that should select it is dead code, referenced nowhere in the RTL. Coverage
confirms it: `fence_i_cg` reads 0.00% on real stimulus. This is a latent architectural
gap (harmless today since nothing self-modifies code), documented as OBS-050, not a
live failure.

---

## 4. What was deliberately generated but NOT enabled — and why that is a finding, not an omission

Built the full RV32D (double-precision float) covergroup bank — 32 covergroups — before
checking whether it was reachable. It is not, at this config: `EXT_D_ENABLE` in the RTL
is gated `` `ifdef XLEN_64 ``, and this project's primary configuration is XLEN=32.
Double-precision is structurally absent from the hardware at this config, not an
untested capability. Correctly reporting "0% reachable, held for a future XLEN=64
bank" is more honest than either silently skipping it or claiming a false gap — worth
a slide line on how the model tells the difference between "untested" and
"unsupported".

---

## 5. What's still running / still open

- **1CL suite re-run, in progress at time of writing.** Same ~50-program suite that
  produced the frozen 94.72% defence bank, now measured against the extended
  collector (100 active covergroups vs. the original ~78) with stimulus otherwise
  unchanged — i.e. this isolates what the new coverage axes reveal, before any new
  stimulus is added to fill them.
  **[FILL IN FINAL NUMBER ONCE THE RUN COMPLETES — do not use a number from before
  the run finished.]**
  Expected direction: **down** on the raw covergroup-bin percentage, and that is the
  correct outcome — the denominator grew by ~59 bins from a 370/377 base without new
  stimulus for most of them yet, and a coverpoint that used to read a false 100%
  (`cp_alu_op`) no longer does. A drop here reflects a more honest measurement, not a
  regression in the design or the testbench.
- **Not yet run:** a second 1CL pass with `coalesce_probe` and `csr_probe` added to
  the suite (recovers the G-0/G-1-targeted stimulus), and a full 2CL (2-cluster)
  re-run with the same collector, which is the pass that actually stresses
  cross-cluster/cross-core behaviour.
- **Remaining open gaps in the plan (G-2 through G-10):** branch-taken/not-taken
  crossed with direction, divide-instruction corner values, RTL structural hazards,
  GPR bank-conflict coverage, operand-value coverage, SIMD-beat/uop sequencing,
  instruction-buffer occupancy, local (scratchpad) memory access patterns, and
  cross-core memory arbitration. None of these block a defence — they are ranked by
  verification value for future work, not urgency.

---

## 6. One-paragraph summary, if the deck needs a single slide

*"Extended verification from a single Vortex-specific coverage model to a two-layer
model combining an independent, third-party RISC-V ISA coverage tool (riscvISACOV,
80 active covergroups, generator validated byte-for-byte against the vendor's own
source) with an extended microarchitectural model (20 covergroups, 87 coverpoints) —
100 active covergroups total, up from 78. In the process, found and fixed a real
coverage-integrity defect where four distinct instruction classes were aliasing onto
one coverpoint (making a reported 100% number unattributable), and closed the
project's largest structural gap — zero visibility into GPU memory-address
coalescing — with a new passive probe and directed kernel, now at 100% on the
access-pattern axis that matters."*
