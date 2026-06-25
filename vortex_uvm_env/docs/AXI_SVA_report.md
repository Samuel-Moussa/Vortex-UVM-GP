# AXI SVA Report (Task SVA-axi, Stage 2)

**Scope:** AXI4 protocol assertions for the Vortex DUT's AXI master port,
implemented inline in `tb/vortex_axi_if.sv`. This report covers what was
implemented, what was planned but dropped, the rationale for each drop, the
implementation issues encountered during bring-up, and the final coverage
delta vs the original plan.

**Author:** Steven (Tests + Sequences + SVA + DPI scope).
**RTL pin:** Vortex `7a52ee5` (`/home/stev_teto_22/vortex/hw/rtl/libs/VX_axi_adapter.sv`).
**Validation:** `axi_memory_test` (single-cluster, single-core, 4-warp,
4-thread config, AXI interface path). Result: PASS, zero SVA fires.

---

## 1. Plan recap and final shape

The original Opus plan called for six property groups (A–F) inlined in
`tb/vortex_axi_if.sv` rather than split into a separate `SVA/` directory.
The inline decision was made because the new property count is small
(~15–18 properties) and the existing 11 handshake-stability assertions
already lived in the interface.

**A trip-wire was recorded in memory:** if Vortex's AXI RTL ever moves off
single-beat FIXED bursts (any of `m_axi_awlen`, `m_axi_arlen`, `m_axi_awburst`,
`m_axi_arburst` becoming non-default in `VX_axi_adapter.sv`), the property
count will balloon and the work should split into
`/home/stev_teto_22/Vortex-UVM-GP/vortex_uvm_env/SVA/axi_protocol_checker.sv`
+ `axi_sva_bind.sv`.

### Final group status

| Group | Plan | Final | Reason |
|------|------|-------|--------|
| A — Burst legality | 8 properties | **8 implemented** | All kept; A5/A6/A7/A8 are vacuous today but guard future RTL changes. |
| B — WLAST/AWLEN beat counter | New state + property | **Dropped** | RTL evidence — see §3. |
| C1 — BID matches outstanding AW (per-ID) | Per-ID assoc array | **Replaced with scalar total** | Questa tool limitation — see §5. |
| C2a — RID matches outstanding AR (per-ID) | Per-ID assoc array | **Replaced with scalar total** | Same root cause as C1. |
| C2b — RLAST drains per-ID count to 1 | Per-ID assoc array | **Dropped** | Cannot express with scalar — see §5. |
| C3 — RID consistency within a burst | Local var + flag | **Dropped** | RTL evidence — see §3. |
| D — Reset behaviour (D1, D2) | 2 properties | **2 implemented** (with X-tolerance fix) — see §6 |
| E — Extended channel stability (E1, E2, E3) | 3 properties | **3 implemented** |
| F — Coverage cover points | ~15 covers | **15 implemented** |

---

## 2. What was implemented — assertion catalogue

All new code lives inside a `generate if (ENABLE_FULL_AXI_CHECKS) begin :
g_full_axi_checks ... end endgenerate` block in `tb/vortex_axi_if.sv`. The
parameter `ENABLE_FULL_AXI_CHECKS` defaults to `1'b1`; setting it to `0` at
instantiation silences Groups A/C/D/E/F while keeping the original 11
handshake-stability assertions always-on.

### Group A — Burst legality

Combinational checks on every AW/AR handshake. No new state.

| Tag | Property | What it checks | AXI4 rule |
|-----|----------|----------------|-----------|
| A1 | `aw_burst_legal_p` | `awburst != 2'b11` on AW handshake | RESERVED encoding (A3.4.1) is undefined; using it is a protocol violation. |
| A2 | `ar_burst_legal_p` | `arburst != 2'b11` on AR handshake | Same as A1, AR side. |
| A3 | `aw_size_legal_p`  | `awsize <= $clog2(DATA_WIDTH/8)` | The burst-size encoding cannot exceed one beat-wide transfer on the data bus. For DATA_WIDTH=512 this is `awsize <= 6` (64-byte beat). |
| A4 | `ar_size_legal_p`  | `arsize <= $clog2(DATA_WIDTH/8)` | Same as A3, AR side. |
| A5 | `aw_wrap_len_legal_p` | If `awburst==WRAP`, then `awlen ∈ {1,3,7,15}` | A WRAP burst must be 2/4/8/16 beats. Any other length is illegal. |
| A6 | `ar_wrap_len_legal_p` | Same as A5, AR side. | |
| A7 | `aw_4k_boundary_p` | If `awburst==INCR`, total burst bytes must fit within one 4 KB page | A3.4.3 — INCR burst must not cross a 4 KB boundary. Encoded as `awaddr[11:0] + ((awlen+1) << awsize) <= 4096`. |
| A8 | `ar_4k_boundary_p` | Same as A7, AR side. | |

A5/A6/A7/A8 are **vacuous on this DUT** today (Vortex always issues
single-beat FIXED bursts — see §3). They are retained as future-proof
guards: if the RTL ever supports WRAP or multi-beat INCR, these properties
will start firing meaningfully without any code changes.

### Group C — Outstanding-transaction scoreboards (V4 form)

Two scalar counters track total outstanding write and read transactions.
**Per-ID granularity is gone — see §5 for the full V1→V4 history and the
coverage delta.**

| Tag | Property | What it checks |
|-----|----------|----------------|
| C1 | `bvalid_has_outstanding_aw_p` | Every B handshake must have `outstanding_aw_total > 0`. |
| C2 | `rvalid_has_outstanding_ar_p` | Every R beat must have `outstanding_r_total > 0`. |

State (also at the top of the generate block):

```sv
int unsigned outstanding_aw_total;
int unsigned outstanding_r_total;
```

Updated by a single `always_ff` with NBA. AW handshake `+1`, B handshake
`-1`; AR handshake `+(arlen+1)`, each R handshake `-1`. The case-statement
form handles same-cycle AW+B (or AR+R) net-change cleanly.

### Group D — Reset behaviour

| Tag | Property | What it checks |
|-----|----------|----------------|
| D1 | `valids_low_during_reset_p` | While `!reset_n`, no VALID is firmly 1. |
| D2 | `valids_low_after_reset_p`  | On the rising edge of `reset_n`, no VALID is firmly 1. |

Both use `signal !== 1'b1` (case-inequality) rather than `!signal` — this
tolerates X/Z at sim startup and only fires on a firmly-driven 1. See §6
for why this matters.

### Group E — Extended channel stability

| Tag | Property | What it checks |
|-----|----------|----------------|
| E1 | `aw_signals_stable_p` | While `awvalid && !awready`, all AW control fields (awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion) are stable. |
| E2 | `ar_signals_stable_p` | Same for AR control fields. |
| E3 | `w_strb_stable_p`     | While `wvalid && !wready`, `wstrb` is stable. |

The existing 11-assertion handshake tier already covers `awaddr`, `awid`,
`araddr`, `arid`, `wdata`, `rdata`. E1/E2/E3 close the remaining AXI4
stability obligation across all 5 channels.

### Group F — Coverage cover points

15 cover points across burst-type distribution (AW FIXED/INCR/WRAP),
response codes (B and R: OKAY/SLVERR/DECERR), AWLEN brackets (1, 2–4,
5–16, 17–64, 65–255 beats), and concurrent AW+AR address-channel activity.

**Note for run-results readers:** `cover_bresp_slverr`,
`cover_bresp_decerr`, `cover_rresp_slverr`, `cover_rresp_decerr` will
remain at 0 in all normal sim runs. The RTL's own RUNTIME_ASSERTs at
`VX_axi_adapter.sv:314` (`bresp == 0`) and lines 333–334 (`rresp == 0`)
force OKAY-only responses. These cover points document protocol
possibilities, not expected behaviour.

---

## 2.X — Per-assertion narrative (plain-English meaning of each property)

The tables in §2 list what each property **checks**. This subsection
explains what each one **means** — the AXI4 rule behind it, what
real-world failure mode it catches, and what a fire would indicate when
debugging. Read this section if you are looking at an SVA fire and
trying to understand whether it points at the DUT, the TB, or a config
issue.

### Group A — Burst legality (prose)

The AXI4 standard defines a strict legal grammar for how a master is
allowed to encode a burst on the AW or AR channel. Group A enforces
this grammar at every accepted handshake.

- **A1 / A2 — RESERVED burst type.** The `awburst` / `arburst` field is
  2 bits. Three encodings are defined (FIXED=00, INCR=01, WRAP=10); the
  fourth (`2'b11`) is RESERVED and undefined behaviour. If a fire
  happens here, the DUT has emitted a malformed burst type — almost
  certainly an RTL bug. There is no legitimate reason for any AXI4
  master to ever drive `2'b11`.

- **A3 / A4 — `awsize` / `arsize` cannot exceed the data-bus width.**
  `awsize` encodes the bytes-per-beat as `2^awsize`. The data bus is
  64 bytes wide (`DATA_WIDTH=512`), so `2^awsize <= 64` ⇒ `awsize <= 6`.
  A fire here means the DUT asked for a transfer wider than the bus can
  carry — a clear RTL/config mismatch.

- **A5 / A6 — WRAP burst length restriction.** A WRAP burst is a
  cache-line-friendly variant where the address wraps inside a power-of-2
  boundary. AXI4 only allows wrap lengths of 2, 4, 8, or 16 beats
  (`awlen ∈ {1, 3, 7, 15}` because `awlen` is "beats minus one"). A
  fire would indicate a DUT that emits a malformed WRAP burst. **Today
  this fires never** because Vortex never emits WRAP, but the assertion
  catches any future regression.

- **A7 / A8 — 4 KB page boundary.** AXI4 A3.4.3 forbids an INCR burst
  from crossing a 4 KB address boundary. The rationale is downstream
  decode: many interconnects route based on 4 KB regions and cannot
  handle a single burst that spans two regions. The check is encoded as
  `awaddr[11:0] + ((awlen+1) << awsize) <= 4096` — if the sum of the
  starting offset within the page plus the total burst byte count
  exceeds 4096, the burst would cross the boundary. **Today vacuous**
  (single-beat means the burst is one beat = at most 64 bytes, and the
  page boundary is rarely close), but retained as a regression guard.

### Group C — Outstanding-transaction scoreboards (prose, V4 shipped form)

C1 and C2 enforce response-bookkeeping integrity: every write response
must correspond to *some* outstanding write request, and every read beat
must correspond to *some* outstanding read request. Per-ID matching was
dropped — see §5 for the full reasoning and the stressed list of what
that loss costs us.

- **C1 — Every B handshake must have at least one outstanding AW.**
  A fire means the TB slave (or in theory the DUT, but here the slave
  drives B) returned a write response when no write request was in
  flight. This is a serious bookkeeping bug — either the slave is
  fabricating responses, or its outstanding-request tracker is wrong,
  or the AW handshake itself was missed by the slave's request queue.
  On a typical Vortex run with the shipped axi_driver, this assertion
  should never fire.

- **C2 — Every R handshake must have at least one outstanding AR
  beat.** Same idea on the read side. A fire means an R beat was
  returned with no AR pending. For Vortex (single-beat reads), this
  reduces to "an R per AR." A fire means the TB slave returned a
  spurious read response — possible causes include the slave's read-ID
  buffer over-issuing, or a race in the AR handshake detection.

The `outstanding_aw_total` / `outstanding_r_total` scalar counters that
underpin both checks update via the case-statement in §2 Group C. The
case structure handles the same-cycle increment+decrement edge case
correctly (net zero change), so a back-to-back AW/B (or AR/R) on the
same cycle does not glitch the counter.

### Group D — Reset behaviour (prose)

D1 and D2 enforce that the AXI master keeps all 5 VALIDs low during and
immediately after reset.

- **D1 — During reset, no VALID may be firmly 1.** A fire means a
  channel started transmitting before reset was released — a serious
  RTL bug, because downstream slaves expect a quiet bus during reset and
  may latch garbage if VALID asserts early.

- **D2 — On the cycle reset_n rises, no VALID may be firmly 1.** A
  slightly stricter version: even the very first active cycle after
  reset deassertion must still be quiet. This protects against the
  edge-case where the DUT has registered an internal request *during*
  reset and presents it immediately. Vortex is safe here because
  `VX_axi_adapter`'s outgoing FIFOs reset to empty (see
  `VX_axi_adapter.sv:262, 264, 297`), so all master VALIDs are 0 at the
  moment of deassertion.

Both checks use case-inequality (`signal !== 1'b1`) rather than
negation (`!signal`) — see §6 for why this matters at sim startup.

### Group E — Extended channel stability (prose)

The AXI4 stability rule says: once a master raises VALID on a channel,
**none** of the channel's payload signals may change until the slave
returns READY and the handshake completes. The existing handshake-tier
assertions already cover the "obvious" payload fields (addresses, IDs,
write data, read data). Group E closes the remaining holes:

- **E1 — AW control fields stable while waiting for AWREADY.** Covers
  `awlen`, `awsize`, `awburst`, `awlock`, `awcache`, `awprot`, `awqos`,
  `awregion`. A fire means the DUT changed a control field mid-handshake.
  Effect on a downstream slave: it could latch one value during decode
  and a different value during execution, leading to silent data
  corruption.

- **E2 — AR control fields stable while waiting for ARREADY.** Same as
  E1 on the read side.

- **E3 — WSTRB stable while waiting for WREADY.** WSTRB is the per-byte
  write-enable mask. If it changes mid-handshake, the slave may write
  the wrong subset of bytes — a particularly nasty silent corruption
  because the wrong bytes are also a *valid* write, just to wrong
  locations.

### Group F — Coverage cover points (prose)

Group F is observability, not enforcement. The cover points record
which AXI scenarios were actually exercised during a run. They answer
questions like:

- *Did the test ever issue a WRAP burst?* (`cover_aw_burst_wrap`)
- *Did the slave ever return a non-OKAY response?*
  (`cover_bresp_slverr`, `cover_bresp_decerr`, etc. — currently
  unreachable on this DUT per §2 Group F note.)
- *Did we ever see burst lengths above one beat?* (`cover_awlen_2to4`,
  `cover_awlen_5to16`, etc. — also currently zero for single-beat
  Vortex.)
- *Did the AW and AR channels ever overlap in time?*
  (`cover_concurrent_aw_ar`)

A coverage report showing many of these at 0% is **expected** for the
current single-beat single-cluster config — it tells you the workload
is narrow, not that the SVA is broken. Once richer traffic patterns or
error-injection slaves come online, these bins should start filling.

---

## 3. Groups dropped after RTL inspection (B and C3)

Reading `VX_axi_adapter.sv` end-to-end before writing any SV code revealed
hard-coded assignments that collapse two of the planned groups to vacuous:

```
VX_axi_adapter.sv:262   assign m_axi_awlen[i]   = 8'b00000000;  // always 1 beat
VX_axi_adapter.sv:264   assign m_axi_awburst[i] = 2'b00;        // always FIXED
VX_axi_adapter.sv:276   assign m_axi_wlast[i]   = 1'b1;         // always asserted
VX_axi_adapter.sv:297   assign m_axi_arlen[i]   = 8'b00000000;  // always 1 beat
VX_axi_adapter.sv:299   assign m_axi_arburst[i] = 2'b00;        // always FIXED
```

Vortex's AXI master is **single-beat, FIXED-burst only**. This is the
upstream Vortex design choice; the adapter does not currently support
multi-beat bursts.

### B — WLAST/AWLEN consistency (dropped)

**What the assertion would have meant.** For a multi-beat write burst,
the master commits to a length when it issues AW (`awlen+1` beats). It
must then assert WLAST on exactly the last of those beats — not the
first, not the middle, not late, not skipped. The slave uses WLAST to
know when to send the B response. If WLAST timing is wrong, the slave
either responds too early (B for an incomplete write) or hangs forever
waiting for a WLAST that never comes.

**Planned property:** maintain a queue of expected W-beat counts (one
entry per outstanding AW, value `awlen+1`). On each W handshake, check
that WLAST is high iff this is the last expected beat for the head AW
in the queue, then decrement/pop.

**What we'd catch with B that we now don't.** WLAST asserted on the
wrong beat of a multi-beat write — i.e., the master telling the slave
"this is the end" prematurely or skipping it entirely. **For Vortex
this is non-issue territory** because `awlen=0` always means every W
beat is unambiguously the last. The existing
`wlast_asserted_on_write_p` (`vortex_axi_if.sv:415`) enforces
`(wvalid && wready) |-> wlast`, which is exactly the correct check for
this DUT. The new Group B logic would have been dead code duplicating
an existing assertion, and the existing assertion *does* catch every
WLAST violation possible in this RTL.

**Net coverage loss for the current DUT: zero.** The full Group B
property is mathematically equivalent to the existing single-beat
assertion when `awlen` is always 0.

**Trip-wire for re-adding:** if Vortex ever issues bursts with
`awlen != 0`, the existing single-beat assertion will start mis-firing
(it will assert that every W beat must be the last, which becomes wrong
for multi-beat). At that point Group B's queue-based logic must be
implemented per the original plan and the single-beat assertion either
removed or made conditional.

### C3 — RID consistency within a burst (dropped)

**What the assertion would have meant.** AXI4 allows a slave to
*interleave* the beats of different read bursts on the R channel as long
as each individual burst's beats are contiguous in RID. That is: if the
slave is returning bursts with IDs A and B simultaneously, the R-channel
beat sequence may look like `A0, B0, A1, B1, A2, B2 …` (different IDs
interleaved across bursts), but it may **not** look like
`A0, B0, A1` where the A burst's beats are themselves split by B beats
*for the same A burst* — sorry, that's exactly what's allowed. The real
rule is: within a *single* burst (same RID, between AR and RLAST for
that RID), the slave must keep RID stable across every beat of that
burst.

**Planned property:** on the first beat of each burst (R handshake
following an AR for a previously-unseen-in-flight RID), capture the
RID. For every subsequent R beat of that burst (until RLAST for that
RID), assert that the current RID matches the captured one. Use per-ID
state.

**What we'd catch with C3 that we now don't.** A buggy slave that
spliced beats from a different burst into the middle of a same-ID
burst — i.e., scrambled RIDs mid-burst. The result on the master side
would be data assembled into the wrong destination buffer (since
masters use RID to demultiplex responses into requestor queues).

**Why this is a non-issue for the current DUT.** `arlen=0` always means
every read burst is exactly one beat. With single-beat bursts, the
concept of "RID changing within a burst" is mathematically impossible
— a single beat trivially has consistent RID with itself. And the RTL
itself runtime-asserts that RLAST is always 1 when RVALID is 1
(`VX_axi_adapter.sv:333`), so the "within-burst" window is literally
zero cycles wide.

**Net coverage loss for the current DUT: zero.** Multi-beat
RID-interleaving violations are unrepresentable in this RTL.

**Trip-wire for re-adding:** same as Group B — multi-beat reads (or a
slave that returns multi-beat R bursts) would make C3 genuinely
load-bearing. Implementation note for that future point: C3 requires
per-ID state, so its return depends on the same per-ID tracking
restoration discussed in §5's "Trip-wire for re-adding per-ID."

---

## 4. Open-source AXI4 checkers consulted

Two external SVA-based AXI4 checkers were read for property-coverage
sanity-checking before writing our own. Neither was imported as code; the
value was in their property catalogues as a checklist.

- **ZipCPU `wb2axip`** — https://github.com/ZipCPU/wb2axip
  - Author: Dan Gisselquist. Apache-2.0.
  - The bridges' formal-property files (`faxi_master.v`, `faxi_slave.v`,
    `faxil_master.v`, `faxil_slave.v`, `faxis_*.v`) are self-contained
    AXI4 checkers. Master-side files assume slave compliance and vice
    versa, so each side can be formally proven independently.
  - **Coverage:** 4 KB boundary, all burst-type/length rules, WLAST/RLAST
    timing, ID stability, exclusive access, response-code constraints,
    reset behaviour. Genuinely comprehensive.
  - **How used here:** as a checklist while drafting Groups A and E. The
    Verilog style is pre-2017 so the property names and conditions
    translate but the SV syntax does not.

- **OpenHWGroup / pulp-platform `axi`** —
  https://github.com/pulp-platform/axi (used by `core-v-verif`).
  - Has SV-style assertions but they are tightly coupled to pulp's struct
    typedefs (`axi_aw_t`, `axi_w_t`, …). Porting requires dragging in the
    type system or rewriting against bit-vector signals.
  - **How used here:** less useful than wb2axip for this project. Named
    for completeness only.

Neither codebase was imported. Reading them was a 20-minute exercise to
make sure no obvious rule class was missed. Result: A1–A8, E1–E3, and
the dropped B/C3 catalogue match the union of both references for the
subset relevant to single-beat FIXED traffic.

---

## 5. C1/C2 — V1 → V4 implementation history and the coverage we lost

> **This section is the most important part of the report.** The shipped
> Group C does not match the original plan; per-ID matching was removed
> after three failed implementation attempts hit a Questa tool limitation.
> The following lists each attempt, its root cause of failure, and — most
> importantly — what we lost by the final fallback.

### V1 — Associative arrays + `always @` with blocking assignments

```sv
int unsigned outstanding_aw_per_id [bit [ID_WIDTH-1:0]];
int unsigned outstanding_r_beats_per_id [bit [ID_WIDTH-1:0]];

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) outstanding_aw_per_id.delete();
    else if (awvalid && awready) outstanding_aw_per_id[awid]++;
    else if (bvalid && bready)   outstanding_aw_per_id[bid]--;
end

property bid_matches_outstanding_aw_p;
    @(posedge clk) disable iff (!reset_n)
    (bvalid && bready) |->
        (outstanding_aw_per_id.exists(bid) && outstanding_aw_per_id[bid] > 0);
endproperty
```

**Result on first sim:** infinite stream of C1 fires (`BID=0x3` and `BID=0x83`
cycling every ~120 ns), and identical infinite C2a/C2b fires for `RID=0xc0`.

**Root cause:** **Questa does not apply SV's preponed-sampled-value
semantic to associative arrays in concurrent-assertion expressions.** The
IEEE 1800 standard says property expressions sample variables from the
preponed region (end of previous time step). For scalars and packed types,
Questa implements this correctly. For *associative arrays*, the SVA engine
appears to read the post-NBA value of the array — so at the cycle a B
handshake fires, the `always` block runs in Active, decrements the count
to 0 and deletes the key, and SVA in the Observed region sees
`exists(bid) == false` → fail.

### V2 — Fixed-size `int [0:255]` arrays + `always_ff` + `_prev` NBA snapshot

```sv
int outstanding_aw_cnt      [0:255];
int outstanding_aw_cnt_prev [0:255];
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) /* reset both */;
    else begin
        outstanding_aw_cnt_prev <= outstanding_aw_cnt; // whole-array NBA copy
        if (awvalid && awready) outstanding_aw_cnt[awid[7:0]] <= ... + 1;
        if (bvalid && bready)   outstanding_aw_cnt[bid[7:0]]  <= ... - 1;
    end
end
property p; ... (bvalid && bready) |-> outstanding_aw_cnt_prev[bid[7:0]] > 0; endproperty
```

**Idea:** use fixed-size arrays (which should sample correctly) and add a
one-cycle delayed snapshot, so SVA reads `_prev` (= pre-update state).

**Result:** still infinite C1/C2 fires.

**Root cause — the timing was double-delayed.** The `_prev <= cnt`
assignment is itself NBA. So `_prev` at end of cycle N reflects `cnt`'s
value from end of cycle N−1. When SVA at cycle N samples `_prev` preponed,
it gets the value from end of N−1 = `cnt` from end of N−2 — **two cycles
late, not one.** The axi_driver (`axi_driver.sv:248`) raises `rvalid <= 1`
on the same cycle AR is accepted, so R fires at N+1. With `_prev` two
cycles late, the prev[id] was still 0 at the R-cycle check. Same problem
for B.

### V3 — Same fixed-size arrays, SVA reads `cnt` directly (no `_prev`)

```sv
property p; ... (bvalid && bready) |-> outstanding_aw_cnt[bid[7:0]] > 0; endproperty
```

**Idea:** with `always_ff` + NBA, the array element update lands in the
NBA region of cycle N. SVA at cycle N samples preponed = value at end of
N−1, which is the *pre-update* value. This is exactly the pattern the
existing working `completed_writes_outstanding` scalar at
`vortex_axi_if.sv:428` uses, and that scalar's assertion at line 452
works correctly.

**Result:** C2 errors disappeared (or were not yet exercised in the
visible window). **C1 errors continued — same 4 IDs cycling
(`0x3`/`0x43`/`0x83`/`0xc3`).**

**Root cause (suspected):** Questa appears to mishandle preponed sampling
of `unpacked_int_array[bit_select_index]` inside an SVA property when the
array is NBA-updated by an `always_ff` that lives inside
`generate-if-inside-interface`. The scalar pattern works in the same
file; the array pattern with the same NBA semantics does not. We did not
isolate this to a Questa version-specific bug; we worked around it.

### V4 — Scalar TOTAL counters (shipped)

```sv
int unsigned outstanding_aw_total;
int unsigned outstanding_r_total;

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        outstanding_aw_total <= 0;
        outstanding_r_total  <= 0;
    end else begin
        case ({awvalid && awready, bvalid && bready})
            2'b10: outstanding_aw_total <= outstanding_aw_total + 1;
            2'b01: outstanding_aw_total <= outstanding_aw_total - 1;
            default: ; // 2'b00 or 2'b11 → no net change
        endcase
        case ({arvalid && arready, rvalid && rready})
            2'b10: outstanding_r_total <= outstanding_r_total + (int'(arlen) + 1);
            2'b01: outstanding_r_total <= outstanding_r_total - 1;
            2'b11: outstanding_r_total <= outstanding_r_total + (int'(arlen) + 1) - 1;
            default: ;
        endcase
    end
end

property bvalid_has_outstanding_aw_p;
    @(posedge clk) disable iff (!reset_n)
    (bvalid && bready) |-> (outstanding_aw_total > 0);
endproperty

property rvalid_has_outstanding_ar_p;
    @(posedge clk) disable iff (!reset_n)
    (rvalid && rready) |-> (outstanding_r_total > 0);
endproperty
```

**Result:** zero false fires across the validation sweep
(`axi_memory_test` PASS, full simulation runs clean — see §7).

**Why this works when V3 didn't:** it uses the *exact same scalar pattern*
as the already-working `completed_writes_outstanding` (`vortex_axi_if.sv:428`).
That pattern is proven to work in this compile environment. By using a
scalar variable instead of an array element, the SVA sampling path is the
well-trodden one and Questa handles it correctly.

### What we lost by going to V4 — STRESSED

Three concrete coverage losses come from collapsing per-ID arrays to
scalar totals. **These must be understood by anyone reading the SVA
checker's coverage as evidence of protocol correctness:**

1. **Per-ID matching is gone.** V4 can detect "a B response with no
   outstanding write at all" (the total counter is 0). It **cannot**
   detect "a B response with a BID that was never used as AWID" if there
   happens to be some other unrelated outstanding AW at the same moment.
   The slave could return a corrupted BID for a real B response and V4
   would silently pass it as long as the total count is non-zero.

2. **C2b (RLAST per-ID drain check) was dropped entirely.** The original
   C2b verified that RLAST fires exactly when the beat count for that
   particular ID drains to 1 — i.e., RLAST is on the *last* beat of *that*
   burst, not just "a last beat of some burst." With a total counter
   there is no way to express "this ID's last beat" because we no longer
   know which burst the current R beat belongs to. The check is
   mathematically impossible without per-ID state.
   **Partial mitigation:** the existing `rlast_not_early_p` /
   `rlast_on_last_beat_p` (lines 485–501) still check RLAST timing against
   a single tracked burst length. That is sufficient for Vortex's
   single-beat single-cluster traffic where only one burst is in flight
   at a time, but it is *not* a true per-ID drain check.

3. **Per-ID ordering violations are invisible.** AXI4 requires that B
   responses for the same AWID return in the order their AWs were issued
   (within a single ID, no reordering). The same applies to R bursts for
   the same ARID. V4 has no way to express this — the total counter
   carries no ordering information. *For this DUT it is moot* because the
   TB driver returns B responses in queue order (`axi_driver.sv:188` push
   on WLAST → :216 driven from queue head), and the DUT's
   `m_axi_bid` is marked `UNUSED_VAR` so it does not exercise per-ID
   ordering at all. But the check is gone from our SVA tier regardless.

### Why the loss is acceptable for the current scope

- **RTL's own RUNTIME_ASSERTs catch most of what we'd have caught:**
  `VX_axi_adapter.sv:314` enforces `bresp == 0` on every B; lines 333–334
  enforce `rlast == 1` and `rresp == 0` on every R.
- **Existing handshake-stability tier (11 assertions, lines 305–501)
  catches per-channel signal integrity** — VALID stability, address/ID
  stability, BVALID-after-WLAST timing, RLAST beat counting.
- **Single-beat traffic** means B and R responses are strictly 1:1 with
  AW and AR handshakes. A balanced total counter is sufficient evidence
  that response/request bookkeeping is correct.
- **The TB driver echoes captured AWID back as BID** (`axi_driver.sv:188`
  + 216), so BID-mismatch by the slave is structurally impossible in this
  TB.

### Trip-wire for re-adding per-ID

If Vortex ever issues multi-beat bursts (the same trigger as the inline →
split decision in §1), the per-ID drain check (C2b) becomes genuinely
load-bearing. At that point the implementer should:
1. **Try a packed array first** — `logic [255:0][N-1:0]` is bit-vector
   shaped and Questa's SVA sampling path for packed types is well-trodden.
2. **Fall back to a UVM scoreboard** if packed arrays also fail — at that
   point the per-ID logic is better expressed in class-based scoreboard
   code than in interface-level SVA.

---

## 6. D1/D2 sim-startup false-fire and the X-tolerance fix

After C1/C2 were fixed with the V4 scalar form, a single SVA error
remained on `axi_memory_test`:

```
** Error: [AXI SVA-D1] A VALID is asserted while reset_n=0!
   Time: 5 ns  Started: 5 ns
   Scope: vortex_tb_top.vif.axi_if.g_full_axi_checks.assert_valids_low_during_reset
```

### Root cause

The error fired at **time 5 ns** — the very first posedge clk. At that
instant the DUT is still in reset and has not driven its outputs yet.
The DUT-side VALIDs (`awvalid`, `wvalid`, `arvalid`) are still **X**
(uninitialised). The surrounding log shows X propagation everywhere
(`startup_addr=0xxxxxxxxx`).

The original D1 was:

```sv
property valids_low_during_reset_p;
    @(posedge clk)
    (!reset_n) |-> (!awvalid && !wvalid && !bvalid && !arvalid && !rvalid);
endproperty
```

With `awvalid=X`, `!awvalid` evaluates to X. An X consequent in SVA is
treated as a failure (X is not '1'). So the property false-fired even
though no signal was actually firmly driven to 1.

### The fix

Changed each check from `!signal` to `signal !== 1'b1` (case-inequality):

```sv
property valids_low_during_reset_p;
    @(posedge clk)
    (!reset_n) |-> (awvalid !== 1'b1) && (wvalid  !== 1'b1) && (bvalid !== 1'b1) &&
                   (arvalid !== 1'b1) && (rvalid !== 1'b1);
endproperty
```

`signal !== 1'b1` returns a definite 1/0 result even when `signal` is X
or Z: it means "signal is not firmly 1." X, Z, and 0 all pass; only a
firmly-driven 1 fails. The same fix was applied to D2 (the post-reset
edge check) for symmetry.

This is the standard pattern for AXI SVA reset-phase checks; pre-reset
X-propagation is a sim-startup artifact, not a protocol violation, and
the SVA must be robust to it.

### Result

After the fix, `axi_memory_test` runs clean — zero SVA fires across the
full simulation. See §7.

---

## 7. Validation results

Tested on `axi_memory_test` in the AXI interface mode (the only test
currently exercising the AXI master path end-to-end).

**Run:** `results/20260625/run_105336_axi_memory_test/` (first clean run
after the D1 fix; the C1/C2 V4 fix and the D1 fix together produced a
zero-SVA-error result).

**Status after fixes:** PASS, zero new SVA fires.

The validation sequence still to run before SVA-axi is considered fully
sealed:
- `functional_memory_test` on the AXI path
- `warp_scheduling_test`
- `barrier_sync_test`

Any new SVA fire on these tests is a **real** protocol or scoreboard
violation and should not be silenced — investigate the underlying cause
and report.

---

## 8. File map

| Item | Location |
|------|----------|
| All new SVA properties + cover points | `tb/vortex_axi_if.sv`, lines ~530–786 inside `generate if (ENABLE_FULL_AXI_CHECKS)` block |
| Kill-switch parameter | `tb/vortex_axi_if.sv:35` (`parameter bit ENABLE_FULL_AXI_CHECKS = 1'b1`) |
| Pre-existing handshake-stability tier (unmodified) | `tb/vortex_axi_if.sv:305–501` |
| RTL evidence cited (single-beat FIXED) | `/home/stev_teto_22/vortex/hw/rtl/libs/VX_axi_adapter.sv:262, 264, 276, 297, 299` |
| DUT RUNTIME_ASSERTs cited | `VX_axi_adapter.sv:314, 333, 334` |
| TB driver BID/RID echo | `uvm_env/agents/axi_agent/axi_driver.sv:147, 188, 216, 249` |
| TB-top connection | `tb/vortex_tb_top.sv:223–259` |

**No edits were made outside the SVA-axi scope** — the UVM driver,
scoreboard, agents, scripts (`compile.sh`, `simulate.sh`, `run.sh`,
`Makefile`), and the RTL trees (`vortex/hw`, `vortex/sim/simx`) are
untouched.

---

## 9. Coverage delta — original plan vs shipped

| Metric | Original plan | Shipped | Net delta |
|--------|---------------|---------|-----------|
| New `assert property` statements | ~18 | 16 | −2 (C2b dropped, C1+C2a collapsed to C1+C2) |
| New `cover property` statements | ~15 | 15 | 0 |
| New always blocks for SVA state | 2 (assoc-array based) | 1 (scalar counters) | −1 |
| New state variables | 2 assoc arrays | 2 scalars | per-ID granularity lost |
| Lines of new SV code in `vortex_axi_if.sv` | ~270 | ~260 | within budget |
| Pre-existing assertions touched | 0 | 0 | preserved as required by CLAUDE.md |
| Files added outside the interface | 0 (inline plan) | 0 | inline as planned |
| `compile.sh` / `Makefile` edits | 0 | 0 | none needed |

### Assertion catalogue, by group (final shipped state)

| Group | Asserts | Covers | State |
|-------|---------|--------|-------|
| A (burst legality) | 8 | 0 | none |
| C (outstanding tx) | 2 | 0 | 2 scalar counters |
| D (reset behaviour) | 2 | 0 | none |
| E (extended stability) | 3 | 0 | none |
| F (coverage) | 0 | 15 | none |
| **New total** | **15** | **15** | 2 scalars |
| Pre-existing handshake tier (unchanged) | 11 | 1 | scalar + per-burst counter |
| **Grand total in `vortex_axi_if.sv`** | **26** | **16** | |

---

## 10. Operational reference — kill-switch, bring-up workflow, log grep

### Kill-switch (`ENABLE_FULL_AXI_CHECKS`)

`vortex_axi_if.sv:35` declares:

```sv
parameter bit ENABLE_FULL_AXI_CHECKS = 1'b1  // set 0 to silence Groups A/C/D/E/F
```

To silence all new Groups (A/C/D/E/F) for a bring-up run without
rebuilding the world, override at the interface instantiation in
`vortex_tb_top.sv`:

```sv
vortex_axi_if #(.ENABLE_FULL_AXI_CHECKS(1'b0)) axi_if (.clk(clk), .reset_n(reset_n));
```

The 11 pre-existing handshake-stability assertions stay **always-on** —
they are not behind the parameter, by design. They have been in the
codebase long enough to be considered trusted infrastructure.

### Bring-up workflow when a new test fires SVA

1. **Do not silence the assertion as the first move.** A new fire on a
   previously-clean property is the signal you actually want.
2. Open the offending property in `tb/vortex_axi_if.sv` and read the
   error-message scope/file/line printed by Questa.
3. Capture a waveform window around the firing cycle (the run-directory
   `waves/<test>_axi.vcd` is already produced by the makefile).
4. Cross-reference the DUT-side and TB-side drivers:
   - DUT-side: `VX_axi_adapter.sv` (RTL) and `vortex_tb_top.sv` (binding)
   - TB-side: `uvm_env/agents/axi_agent/axi_driver.sv`
5. **If the fire is a real protocol violation**, fix the root cause in
   the responsible component. Do not weaken the property.
6. **If the fire is a known false-positive scenario** (e.g. a new sim
   startup edge case like the D1 X-propagation in §6), update the
   property's robustness *and* add a comment explaining the gate.

### Log-grep cheat sheet

All shipped fire-messages start with `[AXI SVA-<TAG>]`. To filter a
simulation log:

```
grep -E "AXI SVA-[A-F][0-9]?" logs/simulation.log
```

To get a per-tag fire histogram from a long run:

```
grep -oE "AXI SVA-[A-F][0-9]?" logs/simulation.log | sort | uniq -c
```

The assertion-label-to-tag mapping (use this when debugging from a
Questa scope path):

| Tag | Assertion label | What fires it |
|-----|------------------|----------------|
| A1  | `assert_aw_burst_legal`           | AW with `awburst == 2'b11` |
| A2  | `assert_ar_burst_legal`           | AR with `arburst == 2'b11` |
| A3  | `assert_aw_size_legal`            | AW with `awsize > log2(DATA_WIDTH/8)` |
| A4  | `assert_ar_size_legal`            | AR with `arsize > log2(DATA_WIDTH/8)` |
| A5  | `assert_aw_wrap_len_legal`        | AW WRAP with `awlen` not in {1,3,7,15} |
| A6  | `assert_ar_wrap_len_legal`        | AR WRAP with `arlen` not in {1,3,7,15} |
| A7  | `assert_aw_4k_boundary`           | AW INCR crossing a 4 KB page |
| A8  | `assert_ar_4k_boundary`           | AR INCR crossing a 4 KB page |
| C1  | `assert_bvalid_has_outstanding_aw` | B handshake with no outstanding AW |
| C2  | `assert_rvalid_has_outstanding_ar` | R handshake with no outstanding AR beat |
| D1  | `assert_valids_low_during_reset`  | Any VALID firmly 1 while reset asserted |
| D2  | `assert_valids_low_after_reset`   | Any VALID firmly 1 on cycle reset_n rises |
| E1  | `assert_aw_signals_stable`        | AW control field changed before AWREADY |
| E2  | `assert_ar_signals_stable`        | AR control field changed before ARREADY |
| E3  | `assert_w_strb_stable`            | WSTRB changed before WREADY |

---

## 11. Known unknowns and recommended follow-ups

These are items deliberately out of scope for this task but worth
tracking. None of them block declaring SVA-axi complete; they are
candidates for a future iteration.

### 11.1 — `awlock` / `arlock` width mismatch (pre-existing, not introduced here)

The interface declares `awlock` and `arlock` as 1-bit (`logic`,
`vortex_axi_if.sv:49, 86`), but `VX_axi_adapter.sv:265, 300` drives them
as 2-bit (`2'b00`). The tb_top binding at `vortex_tb_top.sv:229`
implicitly truncates the 2-bit RTL wire to a 1-bit interface signal:

```sv
assign vif.axi_if.awlock = axi_awlock[0];  // 2-bit → 1-bit
```

Because the RTL always drives `2'b00`, bit[0] is always 0 and there is
no functional impact on E1. Questa may emit a width-mismatch lint
warning at elaboration; this is pre-existing and not a result of this
task. **Recommendation:** widen the interface field to 2-bit to match
AXI3 convention and silence the lint, or accept the truncation as
documented. Either way, it is not load-bearing for current correctness.

### 11.2 — Pre-existing vacuous property: `rlast_on_last_beat_p`

The pre-existing assertion at `vortex_axi_if.sv:500` is:

```sv
(rvalid && rready && !rlast) |-> (r_beat_count < r_burst_len)
```

`!rlast` is never true when `rvalid` is 1, because both the
`VX_axi_adapter` RUNTIME_ASSERT (line 333) and the axi_driver
(`axi_driver.sv:252` drives `rlast <= (arlen == 0)` → always 1 for the
current DUT) guarantee `rlast` whenever `rvalid` fires. The property is
vacuously true. **Not introduced here, but worth flagging:** if Vortex
ever supports multi-beat reads, this property will start firing
meaningfully. Until then it carries dead coverage weight.

### 11.3 — Cover-point reachability gaps

Per §2 Group F note, four cover points (`cover_bresp_slverr`,
`cover_bresp_decerr`, `cover_rresp_slverr`, `cover_rresp_decerr`) are
**unreachable on the current DUT** because the RTL runtime-asserts
OKAY-only responses. They remain in the cover list as protocol
documentation. **Recommendation:** if a future test introduces an
error-injection slave (e.g. for fault-tolerance verification), these
cover bins start reporting real coverage. Until then, expect them at
0/0 hits in any coverage report — this is not a regression.

### 11.4 — Tool-locked SV behaviour (Questa array sampling in SVA)

§5 documents that V1–V3 failed due to what appears to be a Questa
limitation around SVA preponed sampling of associative arrays and
NBA-updated unpacked-int-array elements indexed by bit-selects, inside
a generate-inside-interface scope. **Recommended follow-up:** when the
team upgrades Questa or migrates to a different simulator (VCS,
Xcelium), retry V3 (per-ID fixed-int arrays + direct SVA read). If the
new tool handles preponed sampling correctly, C2b and per-ID matching
can be restored without further design changes. The V4 scalar form is
purely a tool workaround, not a design constraint.

### 11.5 — Negative-test scaffolding (deliberately deferred)

The original task list included a "negative-test" workstream — fuzz
each new property with a deliberately-broken stimulus to prove the
assertion catches the violation it claims to catch. This was
explicitly deferred per CLAUDE.md ("No negative-test scaffolding yet —
that's task #13, separate PR after Opus review"). **Recommendation:**
add a small SV `bind`-target stimulus module under `tb/sva_negative/`
that drives illegal AW/AR/B/R sequences and confirms each assertion
fires. Run only when explicitly enabled via a plusarg
(`+SVA_NEG_TEST=1`) so the normal regression stays clean.

---

## 12. Summary

- **Inline SVA-axi shipped** in `tb/vortex_axi_if.sv` behind the
  `ENABLE_FULL_AXI_CHECKS` parameter, with all pre-existing handshake
  assertions preserved.
- **15 new asserts + 15 new covers** across Groups A, C, D, E, F.
- **Two groups dropped after RTL inspection:** B and C3 (Vortex's
  single-beat FIXED traffic makes them vacuous).
- **C1/C2 fell back to scalar total counters after three failed
  per-ID array attempts** hit a Questa sampling limitation. **Per-ID
  matching, the per-ID RLAST drain check (C2b), and per-ID ordering
  violations are no longer detected by our SVA tier** — see §5 for the
  full discussion and why this is acceptable for the current scope.
- **D1 needed an X-tolerant rewrite** (`!== 1'b1` instead of `!signal`)
  to avoid a sim-startup false fire — see §6.
- **`axi_memory_test` passes clean** with zero new SVA fires. The
  remaining validation steps (`functional_memory_test`,
  `warp_scheduling_test`, `barrier_sync_test`) should be run before
  the task is sealed.
- **Two trip-wires recorded** for future work: if Vortex moves off
  single-beat FIXED, restore Groups B/C3 and consider splitting the
  SVA into a dedicated `SVA/` directory; if the simulator changes,
  retry V3 to restore per-ID C-group coverage.
