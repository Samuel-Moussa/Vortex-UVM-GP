---
handover: dead-but-useful stimulus sequences → Ahmad (coverage lane)
from: Samuel Moussa
date: 2026-06-28
status: OPPORTUNITY — sequences already written, just not wired into any test
related: dead-sequence audit (this session); coverage rows "instruction opcodes" / AXI bins
---

# Handover — Ahmad: wire the unused AXI/DCR stimulus into a test (cheap coverage)

## TL;DR
The AXI and DCR agents already ship a **rich stimulus library that no test starts**.
Wiring a couple of these into a directed test is a **cheap functional/AXI-coverage
win** that directly helps Gate-2 closure — no new sequence code needed, just a
vseq + a test that starts them.

## Background — the dead-sequence audit (2026-06-28)
A sweep of `.start()` usage across the env found only **6 of 23** agent sequence
classes are actually started. The unused ones split into three buckets; **this
handover is Bucket (c): unused-but-useful stimulus** (Bucket (a) mem_* = dormant
by config; Bucket (b) host load/read = Path B, handed to Steven).

## The unused stimulus you can turn into coverage

### AXI (`uvm_env/agents/axi_agent/axi_sequences.sv`)
Currently only `axi_burst_read_seq` is used (by `vortex_axi_mem_vseq`). **Unused:**

| Sequence | Drives | Covergroup bins it would fill (`axi_transaction_cg`) |
|---|---|---|
| `axi_single_write_seq` | single AW/W/B | `cp_type` (WRITE), `cp_len`(0), `cp_bresp` |
| `axi_single_read_seq` | single AR/R | `cp_type` (READ), `cp_rresp0` |
| `axi_write_read_seq` | W then R | `cross_type_*`, RAW ordering |
| `axi_burst_write_seq` | burst AW/W | `cp_burst`, `cp_len`>0 on writes, `cross_type_burst_size` |
| `axi_random_seq` | randomized mix | `cp_size`, `cp_len`, `cp_addr_region`, the crosses broadly |
| `axi_stress_seq` | back-to-back high-rate | outstanding/interleave corners, `cross_len_addr` |

Today every AXI test rides one read sequence, so write/burst-write/size/len/bresp
bins are largely **empty**. `axi_random_seq` + `axi_stress_seq` alone would light
up most of `axi_transaction_cg`.

### DCR (`uvm_env/agents/dcr_agent/dcr_sequences.sv`)
`dcr_random_seq` is unused — would populate `dcr_config_cg` (`cp_addr`,
`cp_data_magnitude`, `cross_addr_data`) beyond the two fixed bootstrap writes.
(Note: `dcr_minimal_startup_sequence` was deleted 2026-06-28 as a redundant
subset — don't look for it.)

## How to wire it (pattern already in the repo)
Mirror `vortex_axi_mem_vseq` — a virtual sequence that starts the agent seq on
the agent sequencer via the virtual sequencer handle:

```systemverilog
class axi_coverage_vseq extends vortex_virtual_sequence;
  task body();
    axi_random_seq rnd = axi_random_seq::type_id::create("rnd");
    axi_stress_seq str = axi_stress_seq::type_id::create("str");
    rnd.start(p_sequencer.m_axi_sequencer);
    str.start(p_sequencer.m_axi_sequencer);
    // optional: dcr_random_seq on p_sequencer.m_dcr_sequencer
  endtask
endclass
```
Then either extend `axi_memory_test` or add a small `axi_coverage_test` that does
`vseq.start(env.m_virtual_sequencer)`.

> [!IMPORTANT]
> Scoreboard caveat: these synthetic AXI/DCR sequences are **stimulus for
> coverage**, not a program SimX executes. They drive the bus directly, so the
> end-state SimX comparison does not apply to them. Run them in a coverage-only
> test (no SimX result check), or gate the scoreboard compare off for that test —
> otherwise the scoreboard will flag a non-comparison. Coordinate with the
> scoreboard's compare-enable so this doesn't read as a failure.

## Why it's worth it
- **Zero new stimulus code** — the sequences are written and compile today.
- Directly fills `axi_transaction_cg` / `dcr_config_cg` bins that are currently
  empty → moves the AXI/DCR slice of functional + structural coverage.
- Complements the **P1 commit probe** (fix_17) work: P1 gives retired-instruction
  coverage; this gives bus-transaction coverage.

## Pointers
- Sequences: `uvm_env/agents/axi_agent/axi_sequences.sv`,
  `uvm_env/agents/dcr_agent/dcr_sequences.sv`
- Wiring pattern: `uvm_env/sequences/vortex_axi_mem_vseq.sv`
- Covergroups: `uvm_env/vortex_coverage_collector.sv` (`axi_transaction_cg`,
  `dcr_config_cg`)
- Audit context: plan "dead-sequence audit"; `docs/fixes/README.md`
