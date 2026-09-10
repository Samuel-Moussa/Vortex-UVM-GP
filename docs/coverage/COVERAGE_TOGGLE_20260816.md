# Toggle-coverage root cause and structural waivers — 2026-08-16

**No simulation was run for this result.** Both banks were RE-REPORTED from their own
`merged_raw.ucdb` with an extended exclusion set. The stimulus, the 47/47 pass results and every
functional number are byte-identical to the 2026-08-15 gap-push banks.

## Result

| bank | toggle before | toggle after | total before | total after | **hits** |
|---|---|---|---|---|---|
| 1CL/1C/4W/4T | 79.79% | **82.16%** (+2.37) | 93.09% | **93.43%** (+0.34) | 339,487 → 339,487 |
| 2CL/2C/4W/4T | 77.80% | **79.47%** (+1.67) | 92.67% | **92.91%** (+0.24) | 972,317 → 972,317 |

**Acceptance — both criteria met at BOTH configs:**
1. **Not one covered bin moved.** Hits are identical before and after; only the denominator shrank.
   This is the same non-vacuity check the icache covergroup waiver passed in `5c4b70f`.
2. **0 "had no effect".** Every emitted line matched a real RTL path at both topologies — the
   OBS-030 lesson (a waiver keyed to one config silently mis-firing at another) applied as a gate.

Covergroup coverage is unchanged (1CL 99.79% / 2CL 99.52%), as it must be — nothing functional was
touched.

## Why toggle was low — three causes, measured

### 1. The icache, not the dcache (OBS-033) — 26.4% of the entire gap

Every doc since 2026-07-10 attributed the toggle ceiling to *"write-through dcache => 512-bit
write-data fields never driven"*. **That named the wrong cache.** Measured on the clean 1CL bank:

| subtree | toggle bins | missing | coverage |
|---|---|---|---|
| `socket/icache` | 51,340 | **22,730** | **55.7%** |
| `socket/dcache` | 86,604 | 9,524 | 89.0% |

The icache is half the size and carries 2.4x the misses. Cause: `VX_socket.sv:106` instantiates it
`.WRITE_ENABLE (0)`, so the write payload, byte-enables and their per-bank copies are elaborated but
undrivable. **Counter-check that this is structural and not stimulus:** on the same interface
`rsp_data.data` toggles 45-46 times on every one of its 512 bits — the read path is fully exercised,
only the write direction is dead.

### 2. A 44-bit UUID counter (OBS-034)

`VX_uuid_gen.sv:40-41`: `uuid = { g_wid[11:0], counter[31:0] }`, `g_wid = (CORE_ID << NW_BITS) + wid`.
Measured per-bit at 1CL/1C/4W: `bit32=37, bit33=1, bits34-43=0` — exactly the formula's bound, since
g_wid maxes at 3. Those upper bits are tied to 0 **by the config**, so they are waived config-awarely.

**The counter bits [18:31] are NOT waived, deliberately.** They measure 0 and toggling bit 31 needs
~2.1e9 retired instructions on one warp, so no feasible run reaches them — but "infeasible" is not
"structurally dead", and this project's rule is that reachable-but-untested coverage is never
excluded. They remain in the denominator as the irreducible residual.

### 3. The metric's shape amplifies both

Questa toggle coverage is **BY INSTANCE**. `VX_mem_bus_if` merged by design unit is 2,456 bins at
**96.49%**; counted by instance it is 98,160 bins with **15,951 missing**. The same dead field is
recounted at every hop, and eight parameterisations of that interface sit at *exactly* 46.96% each.
One RTL tie-off costs the metric roughly an order of magnitude more than it costs the design.

## What was deliberately NOT waived

* **The dcache write-data path** — write-through is a different mechanism; the port is genuinely driven.
* **`mem_req_buf` / `mem_rsp_queue` internal `data_in`/`data_out`** (654+560 nodes, 100% dead). Those
  buffers degenerate to passthrough (`MEM_REQ_BUF_ENABLE = (NUM_BANKS != 1)`, `VX_cache.sv:105`;
  `ICACHE_MRSQ_SIZE 0`, `VX_config.vh:577`) and the passthru branch shows an alias signature
  (`genblk1/__unused = 47` vs `genblk2/__unused = 0`) — those nets may be ALIASES of live nets, and
  excluding an alias of a covered net would hide real coverage. **OPEN, pending investigation.**
* **Whole-scope `-code t` on the icache** — would drop covered bins. Every rule names a dead field.
* **PC high bits** — realism-limited (small programs), not structural. `PC[1:0]` are constant by
  4-byte alignment and could be waived; left in as negligible (128 nodes).

## Config-genericity

`gen_coverage_exclude.sh` derives both waivers from the topology, verified by inspection across four
configs:

| config | icache scopes | uuid waiver |
|---|---|---|
| 1CL/1C/4W/4T | 1 | `uuid[43:34]` (max g_wid 3, 2 bits) |
| 2CL/2C/4W/4T | 2 | `uuid[43:36]` (max g_wid 15, 4 bits) |
| 1CL/8C/8W/8T | 2 | `uuid[43:38]` (max g_wid 63, 6 bits) |
| 4CL/4C/16W/16T | 4 | `uuid[43:40]` (max g_wid 255, 8 bits) |

The uuid waiver **shrinks automatically as the topology grows**, and disappears entirely if a config
ever needs all 12 g_wid bits. The icache waiver is emitted per socket over the real topology.
