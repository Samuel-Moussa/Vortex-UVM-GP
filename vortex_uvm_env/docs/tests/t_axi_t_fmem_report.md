# T-axi + T-fmem — Joint Implementation & Debug Report

**Author:** Steven
**Scope:** T-axi (`axi_memory_test`) + T-fmem (`functional_memory_test`)
**Date:** 2026-06-25
**Status:** ✅ Both tests passing on their respective interfaces; custom-mem path validated end-to-end for the first time.

---

## 1. Goal

Close out the two remaining Tier-1 memory tests in my scope:

- **T-axi** — `axi_memory_test`: drive the DUT through the AXI4 path, exercise R/W, end-state compare in the result window vs SimX. Last missing High-priority test.
- **T-fmem** — `functional_memory_test`: deterministic result-window compare on the **custom-mem** path, mirroring T-axi's structure on the alternate memory interface.

Both follow the project-wide black-box / end-state model: directed test drives DUT + SimX with the same program, waits for completion, scoreboard compares the result window and the DUT console stream against SimX.

---

## 2. Approach

Both tests reuse the `kernel_launch_test.sv` house style:
`customize_config()` → `load_program()` → `run_test_stimulus()` → `check_results()`, gated by the scoreboard.

The two test classes are kept thin — the only real difference is which interface is primary and which kernel program is loaded. All correctness logic lives in `vortex_scoreboard.sv` (two write callbacks: `write_axi` for the AXI agent's analysis port, `write_mem` for the custom-mem agent's analysis port).

**Two-gate check model (both tests):**
- **Gate 1** — DUT vs SimX equivalence: DUT console string match + end-state shadow comparison over `RAM_BASE..DATA_LIMIT` (skipping stack/MMIO).
- **Gate 2** — test-level sentinel at `RESULT_ADDR = 0x80010000 == 0x900DCAFE`.

Passive probes (e.g. `mem_monitor` when AXI is primary) are observability/coverage only — never a second pass/fail gate, per the project checker philosophy.

---

## 3. T-axi — AXI4 path

**Status:** Passed early in the cycle with no surprises. The AXI agent (Ahmad's infra) and `write_axi` were already exercised by prior tests, so once the test class was written and the kernel was loaded through the `.elf → .hex → mem_model` path the result window matched SimX on first run.

The path used as the reference for every subsequent T-fmem fix:

- `write_axi` does per-byte R-M-W into byte-addressed 8-byte shadow slots
  (`waddr = {byte_addr[63:3], 3'b000}`, `lane = byte_addr[2:0]`).
- IO_COUT snoop inlined in the same per-byte loop (range `0x40..0x7F`).
- Result-region debug logs (`waddr >= cfg.result_base_addr && waddr < result_base_addr + result_size_bytes`).
- Reads compared against the shadow via `compare_axi_transaction`.

`compare_all_written` (end-state gate) walks `shadow_memory` keyed by byte address, skipping anything outside `RAM_BASE(0x80000000)..DATA_LIMIT(0x88000000)`. This is the only correct way to filter stack/MMIO out of the end-state compare, and it depends on the keys being **byte addresses**.

---

## 4. T-fmem — custom-mem path

This is where everything that was structurally broken in the custom-mem path surfaced. The path had never been exercised end-to-end before T-fmem; each fix uncovered the next layer.

### 4.1 The chain of bugs (in discovery order)

#### Bug 1 — `vortex_mem_if.sv` `master_cb` multi-drive (vsim-3839)

- **Symptom:** elaboration failed with vsim-3839 multiply-driven errors on `req_valid / req_rw / req_addr / req_data / req_byteen / req_tag / rsp_ready`.
- **Root cause:** `master_cb` declared those signals as `output`. The DUT is RTL with `output wire` ports driving the same interface signals via the direct port connection in `vortex_tb_top.sv`. Questa registers a continuous driver at elaboration time for any `output` in a clocking block, even if no UVM process ever writes to it — so the DUT's RTL driver and `master_cb`'s phantom driver collided.
- **Why AXI didn't hit this:** the AXI path uses intermediate `wire` arrays + explicit `assign` statements, which decouple the DUT outputs from the interface signals.
- **Fix:** deleted the `master_cb` block. `mem_responder_cb` (slave-side responder, drives `req_ready / rsp_valid / rsp_data / rsp_tag`) and `monitor_cb` (passive observation) preserved. Inline comment added explaining why `master_cb` is gone so it doesn't get reintroduced.

#### Bug 2 — `mem_agent` forced to PASSIVE (X-cascade in i-cache MSHR)

- **Symptom:** after fix 1, the DUT X-cascaded within 5 cycles of kernel start, originating in the i-cache MSHR. The earlier `master_cb` block had been silently hiding this by holding its phantom outputs at 0 — looked like benign idle bus behaviour.
- **Root cause:** `vortex_env.sv` was hardcoding `m_mem_agent.is_active = UVM_PASSIVE` unconditionally. PASSIVE = no `mem_driver` is built. With AXI also disabled (T-fmem custom-mem mode), nobody was driving `rsp_valid / rsp_data / rsp_tag / req_ready`, so they floated `x`, the DUT's i-cache MSHR latched `x`, and it propagated.
- **Fix:** make `mem_agent` ACTIVE when the custom-mem path is primary; PASSIVE only when the AXI agent is driving and `mem_agent` is observing the internal bus.
  ```systemverilog
  m_mem_agent.is_active = cfg.axi_agent_enable ? UVM_PASSIVE : UVM_ACTIVE;
  ```
  Banner updated to reflect dynamic ACTIVE/PASSIVE.

#### Bug 3 — `write_mem` missing IO_COUT snoop (`CONSOLE FAIL DUT=""`)

- **Symptom:** test ran, but Gate 1 console compare failed with empty DUT console.
- **Root cause:** `write_mem` had no IO_COUT range check at all — it just stored the cache line and moved on. The custom-mem path had never been used, so the snoop hadn't been ported over from `write_axi`.
- **Fix:** added a per-byte IO_COUT snoop in `write_mem`, mirroring `write_axi`. Per-byte enable check, append bytes landing in `0x40..0x7F` to `dut_console`.

#### Bug 4 — `mem_monitor` never forwarded writes (`CONSOLE FAIL DUT=""`, second time)

- **Symptom:** even after fix 3, DUT console was still empty.
- **Root cause:** `mem_monitor.collect_requests()` parked **every** request — read and write — in `outstanding_trans[tag]`, waiting for a response. The custom-mem write protocol is **fire-and-forget**: `mem_driver` commits the write to `mem_model` on the request handshake and generates no response. Writes sat in `outstanding_trans` forever, never reached the scoreboard, and the tag namespace reuse triggered spurious "overwriting outstanding transaction" warnings.
- **Why AXI was fine:** AXI has explicit `BVALID` write responses, so its monitor's matched req/rsp model works naturally.
- **Fix:** in `mem_monitor.collect_requests()`, split the path. Reads continue to park in `outstanding_trans` (need response matching for latency + data). Writes are forwarded to `ap` immediately, marked `completed`, `rsp_time = req_time`. Comment block added so this asymmetry doesn't look like a bug to the next reader.

#### Bug 5 — `compare_mem_transaction` 512-bit vs 64-bit truncation (109 spurious MEM RD FAIL)

- **Symptom:** 109 stack-read failures.
- **Root cause:** the live per-read compare in `write_mem` was comparing the DUT's 512-bit `tr.rsp_data` cache line against `shadow_memory[tr.addr]`, a 64-bit slot. Any write/read of a line with non-zero data above the low 64 bits looked like a mismatch. On top of that, there was no `RAM_BASE..DATA_LIMIT` gate in the per-read compare, so stack reads (legitimately uninitialized from the scoreboard's view) all reported failure.
- **Fix:** dropped the per-read live compare entirely. The end-state shadow gate + the test-level sentinel together verify correctness — a live per-read second gate isn't needed and structurally can't work against 512-bit cache lines without a per-byte expansion (which would duplicate `compare_all_written` for no benefit). Read branch is now a no-op with an explanatory comment.

#### Bug 6 — `shadow_memory[tr.addr] = tr.data` (vacuous `compare_all_written` pass)

- **Symptom:** Gate 1 console passed, but the end-state memory compare was "passing" by passing zero comparisons (`data_compared = 0`).
- **Root cause:** `write_mem` stored `shadow_memory[tr.addr] = tr.data`, where `tr.addr` is a **cache-line address** (26-bit) and `tr.data` is 512 bits truncated to a 64-bit slot. `compare_all_written` walks keys and gates on `addr >= RAM_BASE(0x80000000)`, but cache-line addresses are all `< 0x04000000` after the `<< 6` left-shift to byte addresses — so every entry was filtered out as "stack/MMIO" and the gate vacuously passed.
- **Fix (AXI parity):** rewrote `write_mem`'s write branch to do per-byte R-M-W into byte-addressed 8-byte shadow slots, exactly like `write_axi`. IO_COUT snoop inlined in the same per-byte loop. Result-region debug log added.
  ```systemverilog
  bit [63:0] base_byte_addr = 64'(tr.addr) << 6;
  for (int i = 0; i < 64; i++) begin
    if (tr.byteen[i]) begin
      bit [63:0] byte_addr = base_byte_addr + i;
      bit [63:0] waddr     = {byte_addr[63:3], 3'b000};
      bit [2:0]  lane      = byte_addr[2:0];
      // IO_COUT snoop
      // R-M-W: read existing 64-bit slot (or 0), overwrite lane, store back
      ...
      shadow_memory[waddr[31:0]] = wdata;
    end
  end
  ```
- Sanity greps after the fix:
  - `shadow_memory[tr.addr] =` as a live write: **0 matches** (only one comment + one unrelated read in `compare_mem_transaction`).
  - `shadow_memory[waddr[31:0]] =` write sites: **2** — one in `write_mem`, one in `write_axi`. Symmetric.

### 4.2 Verdict

After all six fixes T-fmem runs end-to-end on the custom-mem path with both gates green: console string match against SimX, and end-state shadow compare over the result window now non-vacuously equal to SimX. T-axi continues to pass — the `write_axi` path was not touched.

---

## 5. Files I generated (tests + kernel programs)

Two test classes (under `uvm_env/uvm_tests/`) plus two C++ kernel programs
(under `vortex/tests/kernel/`). Each test class is paired with the kernel it
loads — the test class is the UVM-side driver; the kernel is the workload
that actually exercises the DUT.

### 5.1 `uvm_tests/functional_memory_test.sv` (147 lines)

UVM test class for T-fmem. Extends `kernel_launch_test` and follows the
house pattern (`customize_config()` → `load_program()` →
`run_test_stimulus()` → `check_results()`, scoreboard-gated). What it adds
on top of `kernel_launch_test`:

- Defaults `cfg.program_path` to `vortex/tests/kernel/functional_mem/functional_mem.elf`
  (only when `+PROGRAM=` is not passed — user override always wins).
- Sets the result window to `RESULT_BASE_ADDR = 0x80010000`,
  `RESULT_SIZE_BYTES = 4` (single sentinel word). User `+RESULT_BASE_ADDR=`
  override still wins.
- Enforces a minimum hardware configuration of `num_warps ≥ 4` and
  `num_threads ≥ 4` — the kernel's cross-warp visibility sub-test
  structurally requires both. Fatal-and-refuse if violated; never silently
  bumps the operator's config.
- Primary interface: custom-mem (default). Runs cleanly under AXI as well
  via `INTERFACE=axi` — the kernel is interface-agnostic, so the same
  binary doubles as secondary AXI coverage.

### 5.2 `uvm_tests/axi_memory_test.sv` (164 lines)

UVM test class for T-axi. Same `kernel_launch_test` pattern. Differences
from `functional_memory_test.sv`:

- Defaults `cfg.program_path` to `vortex/tests/kernel/axi_traffic/axi_traffic.elf`.
- Forces `cfg.axi_agent_enable = 1` and the AXI wrapper as primary
  interface (`+USE_AXI_WRAPPER`).
- Same Gate-2 sentinel at `0x80010000`, same result-window setup.
- Same minimum-config policy as T-fmem (kernel uses 4 threads).

Both test classes are thin (~150 lines each) — all correctness logic lives
in `vortex_scoreboard.sv`. The test class only configures *which*
interface and *which* program; the scoreboard does the comparing.

### 5.3 `vortex/tests/kernel/functional_mem/functional_mem.cpp` (229 lines)

The kernel that T-fmem loads. Four sub-tests in a single binary, designed
so that any LSU/cache/coherence bug manifests as either a memory-window
divergence or a console-string divergence between DUT and SimX (both
caught by Gate 1 in the scoreboard):

| Sub-test | What it does | Class of bug it catches |
|---|---|---|
| T1 | All 4 threads issue word + halfword + byte stores, then readback | Data-path width / sign-ext bugs |
| T2 | Each thread writes `buf[tid*4] = 0x40 + tid` | Per-lane address-computation bugs |
| T3 | Tight per-thread store-then-load to same address | LSU bypass, write-through failures |
| T4 | Warp 0 fills a shared buffer, `vx_barrier`, all warps read back | Cache coherence, barrier ordering |

Result protocol (Gate 2): writes `0x900DCAFE` to `RESULT_ADDR = 0x80010000`
on full success; on failure writes the literal error count instead. The
sentinel is read by `check_results()` after EBREAK.

Built via the standard `common.mk` + per-kernel `Makefile` flow (no
toolchain changes). Companion files in the same directory
(`functional_mem.bin`, `functional_mem.elf`, `functional_mem.dump`) are
build artifacts, not hand-edited.

### 5.4 `vortex/tests/kernel/axi_traffic/axi_traffic.cpp` (253 lines)

The kernel that T-axi loads. Four sub-tests designed specifically to
stress the AXI wrapper (not the LSU's logical behaviour, which T-fmem
already covers):

| Sub-test | What it stresses on AXI |
|---|---|
| T1 | Multiple sequential AW/W + AR/R transactions and B-channel pipeline (4 cache-line R/W) |
| T2 | Non-trivial `wstrb` patterns in the W channel (byte-granularity writes) |
| T3 | AXI write-response (B) before read (AR/R) ordering |
| T4 | AW/W pipeline depth and B-channel ID matching (dense back-to-back writes) |

Cache-line geometry matches this config (`DATA_WIDTH=512 b`,
`LINE_INTS=16`, `NUM_LINES=4`). Same sentinel protocol as
`functional_mem.cpp` (`0x900DCAFE` to `0x80010000`).

The two kernels intentionally cover **different concerns** — `functional_mem`
checks LSU/cache logical correctness across any memory interface;
`axi_traffic` checks that the AXI wrapper itself routes those operations
correctly. Running both gives the project end-state coverage of both
memory-interface paths.

### 5.5 What I did **not** add

- No new sequences. Both tests reuse `kernel_launch_test`'s existing
  sequence and `run_test_stimulus()`.
- No scoreboard changes that are test-specific. Every fix in
  `vortex_scoreboard.sv` (§4.1) brought the custom-mem path to parity with
  the AXI path — it is not T-fmem-specific.
- No new RTL, no new SimX changes, no new agents.

---

## 6. Files touched (and why)

| File | Change | Reason |
|------|--------|--------|
| `tb/vortex_mem_if.sv` | Removed `master_cb` block; kept `mem_responder_cb` + `monitor_cb`; added explanatory comment | vsim-3839 multi-drive — Bug 1 |
| `uvm_env/vortex_env.sv` | `mem_agent.is_active` now `cfg.axi_agent_enable ? UVM_PASSIVE : UVM_ACTIVE`; banner updated | X-cascade from undriven response bus — Bug 2 |
| `uvm_env/agents/mem_agent/mem_monitor.sv` | `collect_requests()` splits reads (park) from writes (forward immediately, `completed=1`) | Custom-mem writes are fire-and-forget — Bug 4 |
| `uvm_env/vortex_scoreboard.sv` (`write_mem`) | IO_COUT snoop added; per-read live compare dropped; per-byte R-M-W shadow store with byte-addressed keys; result-region debug log | Bugs 3, 5, 6 |
| `uvm_tests/functional_memory_test.sv` | New test class following `kernel_launch_test.sv` pattern | T-fmem deliverable |
| `uvm_tests/axi_memory_test.sv` | New test class following `kernel_launch_test.sv` pattern | T-axi deliverable |

All edits to out-of-scope files (`vortex_env.sv`, `mem_monitor.sv`, `vortex_mem_if.sv`, `vortex_scoreboard.sv`) were authorized step-by-step as each bug was discovered. No bulk cleanup. No edits to `vortex/sim/simx` or `vortex/hw`.

---

## 7. Process lessons

- **The custom-mem path had never been exercised end-to-end.** Every bug listed in §4.1 had been latent — invisible until a test class actually drove a kernel through to completion on this interface. T-fmem's real value to the project isn't the test alone; it's having forced the custom-mem path to actually work.
- **`master_cb` was masking the PASSIVE-agent bug.** Questa's elaboration-time driver on clocking-block outputs held the response bus at 0 instead of `x`. Removing dead code exposed a deeper bug, which is the right outcome but worth flagging: clocking-block `output` lists are not free of side effects, even when no process writes to them.
- **Asymmetric protocols need asymmetric monitors.** AXI's BVALID write-ack let `mem_monitor`'s symmetric req/rsp-matching design work by accident on the AXI side; the custom-mem path's fire-and-forget writes broke it. The asymmetry now lives explicitly in the monitor, with comments.
- **`write_axi` was the right reference all along.** Every fix in `write_mem` ended up mirroring the AXI sibling. Keeping the two functions structurally identical (per-byte loop, byte-addressed keys, inline IO_COUT snoop, result-region debug log) makes future changes easier — a fix to one half belongs in the other half.

---

## 8. What this enables next

- **Coverage of both memory interfaces** for the full directed-test suite. Tests that previously ran only on AXI (or only on custom-mem, where they would have silently lied via the vacuous shadow gate) can now be regressed across both.
- **SVA-axi (Stage 2)** can now safely treat the AXI path as the de-facto primary memory interface for protocol checking, while custom-mem has parity for functional verification.
- **D-simx `NUM_CLUSTERS` (Stage 2)** unblocks the config matrix; with both interfaces working, that matrix is now meaningful on both dimensions.
