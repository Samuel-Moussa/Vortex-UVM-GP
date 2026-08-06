# Coverage traceability matrix (FW-6)

**Purpose.** "100% functional coverage" on its own means *100% of the bins we chose to write*.
It measures the completeness of the **coverage model**, not of the **design**. This document
supplies the missing direction of traceability: from a **design feature** to the covergroup that
observes it — and, more importantly, it names the features that **no covergroup observes at all**.

**Scope note.** This is the *functional* coverage model. Code coverage (statement/branch/
condition/toggle) is measured separately and is instrumented over the whole Vortex RTL, so it
does not depend on this matrix. The two answer different questions: code coverage asks "was this
line executed", this matrix asks "did we ever intend to check this feature".

**Configuration this matrix describes:** RV32IMF, `EXT_TCU_ENABLE`, AXI memory interface. Two
banked configurations (1 cluster / 1 core and 2 clusters / 2 cores, both 4 warps × 4 threads).

---

## A. Features WITH coverage

| # | Design feature | Source of the requirement | Covergroup | Where |
|---|---|---|---|---|
| F1 | Integer ALU ops (RV32I) | RISC-V unprivileged ISA | `alu_class_cg` (`instr_class_cg_alu`) | `tb/vx_instr_probe.sv` |
| F2 | Load/store ops + widths | RISC-V unprivileged ISA | `lsu_class_cg` | `tb/vx_instr_probe.sv` |
| F3 | Floating-point ops (F) | RISC-V F extension | `fpu_class_cg` (13 `INST_FPU_*` codes) | `tb/vx_instr_probe.sv` |
| F4 | CSR / warp-control (SFU) | Vortex ISA extension | `sfu_class_cg` | `tb/vx_instr_probe.sv` |
| F5 | Tensor core (WMMA) | Vortex TCU extension | `tcu_class_cg` | `tb/vx_instr_probe.sv` |
| F6 | Warp spawn (`wspawn`) | Vortex SIMT extension | `wspawn_cg` | `uvm_env/vortex_coverage_collector.sv` |
| F7 | Thread-mask control (`tmc`) | Vortex SIMT extension | `tmc_cg` | collector |
| F8 | Divergence (`split`) | Vortex SIMT + IPDOM stack | `divergence_cg` | collector |
| F9 | Reconvergence (`join`) | Vortex SIMT + IPDOM stack | `reconverge_cg` | collector |
| F10 | Barriers (`bar`) | Vortex SIMT extension | `barrier_cg` | collector |
| F11 | Warp scheduling / stall state | Vortex microarchitecture | `sched_state_cg` | `tb/vx_sched_probe.sv` |
| F12 | AXI transaction attributes | AMBA AXI4 | `axi_transaction_cg` | collector |
| F13 | Memory operation mix | Vortex memory subsystem | `mem_operation_cg` | collector |
| F14 | DCR configuration space | Vortex host/device control | `dcr_config_cg`, `dcr_write_cg` | collector, `tb/vortex_dcr_if.sv` |
| F15 | Host launch/completion protocol | Vortex host interface | `host_operation_cg` | collector |
| F16 | System-level state transitions | TB observability | `system_cg` | `tb/vortex_if.sv` |
| F17 | Performance / stall correlation | Vortex microarchitecture | `status_performance_cg` | collector |

18 covergroup types in total (F14 contributes two).

---

## B. Features with NO functional coverage — the honest gaps

These are the output of this exercise. Each is a real design feature of the configuration under
test for which **no covergroup exists**, so no percentage anywhere in our reports speaks to it.

| # | Uncovered feature | Evidence | Assessment |
|---|---|---|---|
| ~~**G1**~~ **CLOSED 2026-08-07** | ~~Cache behaviour: hit/miss/eviction/writeback/MSHR/flush at every level~~ — **now covered** by `tb/vx_cache_probe.sv` (`cache_event_cg`), bound into `VX_cache_bank`. Validated @2CL L2+L3: **8 instances** — `cluster0/1-l2cache-bank0`, `l3cache-bank0/1`, `cluster0/1-socket0-{d,i}cache0`. Config-aware by construction (no bank exists when PASSTHRU, so no bins). | No `cp_*` matching `hit\|miss\|evict\|writeback\|mshr\|flush` exists in the collector or any probe. The only cache-adjacent coverpoints are `cp_id_route` / `cross_type_route`, which sample **routing tag bits**, not cache events. | **The most significant gap.** The cache hierarchy is a major part of the design and one of the likeliest places for real bugs (arbitration, MSHR reuse, eviction races). Today its verification rests entirely on *code* coverage plus end-state/lockstep equivalence — i.e. "a correct program produced a correct answer", which a cache can achieve while still having latent corner-case bugs. |
| **G2** | **Exception / error behaviour** | Only `cp_ebreak` (a status-bit observation) exists. No coverage of illegal instruction, misaligned access, or bus error response. | Partly structural — Vortex has no trap architecture (OBS-013) — but the *absence of a trap* is itself a behaviour worth observing, and AXI error responses are not modelled at all (FW-4). |
| **G3** | **Double-precision FP (D extension)** | `EXT_D_ENABLE` **is** present in `flists/vortex_rtl.flist`, so the hardware is built; kernels are compiled `-march=rv32imaf` (no D) and riscv-dv targets `rv32im`. | **Hardware that is built but never stimulated by any path.** Not a coverage-model defect so much as a stimulus gap, but it means D-precision logic is dead weight in every coverage number we report. Either stimulate it or exclude the extension from the build. |
| **G4** | Reset / initialisation sequencing | No covergroup; reset is a single deterministic sequence. | Tracked as FW-5. Relevant given INV-2 (base DCRs have no reset). |
| **G5** | Multi-cluster interconnect / cross-cluster arbitration | Per-core probe instances exist, but no covergroup targets inter-cluster arbitration or fairness. | Related to FW-7 (no arbitration/starvation stimulus). |

**Explicitly NOT a gap:** atomics (A extension). `EXT_A_ENABLE` is absent from
`flists/vortex_rtl.flist`, so atomic instructions are not built into the DUT in this
configuration. They are out of scope by configuration, not untested.

---

## C. What this changes about our claims

**Before:** *"100% functional coverage."*

**After, and defensible:** *"100% of a coverage model spanning 17 design features
(instruction classes, SIMT control, memory interface, host/DCR, scheduling). The model does not
currently observe cache-level events, exception behaviour, or double-precision FP; those are
named gaps, not passing results."*

The second statement is strictly more useful, and it is the one that survives review. A reviewer
who discovers G1 unaided concludes the number was oversold; a reviewer who is handed G1 concludes
the analysis was thorough.

## D. Recommended closure order

1. **G1 (cache events)** — highest value. Add hit/miss/eviction/writeback/MSHR coverpoints per
   cache level, keyed on the `VX_cache` interfaces. This is also what would let us answer
   "did the L2/L3 hit path actually get exercised?" from *functional* coverage rather than by
   inferring it from code coverage, which is the only instrument available today.
2. **G3 (D-precision)** — cheapest decision: either add a D-precision kernel, or drop
   `EXT_D_ENABLE` from the build so the coverage denominator stops including logic no stimulus
   can reach.
3. **G2 (exceptions)** — couples with FW-4 (AXI error injection); do them together.
4. **G4 / G5** — with FW-5 and FW-7 respectively.
