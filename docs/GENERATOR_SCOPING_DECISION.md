# Generator Scoping Decision — why we did not reuse FuzzGPU's generator

**Date:** 2026-09-07 · **Status:** decided, closed · **Supersedes:** the FuzzGPU-adaptation
line of work opened the same day.

## 1. What we evaluated

**FuzzGPU** — *"Fuzzing Open-Source GPU Hardware with SIMT Program Generation"* (Gao et al.,
Institute of Information Engineering, Chinese Academy of Sciences / UCAS), **USENIX Security
2026**. Repository: `github.com/cassuto/fuzzgpu`.

- Cloned to a local scratchpad, `--depth 1` from `main`.
- **Tree size at clone time: 8.7 GB, 575,934 files** — the repository vendors full forks of
  both target GPUs (Vortex and Ventus) plus Verilator and its own differential-testing
  framework, not a standalone generator.
- Commit/date: shallow clone of `main` as of 2026-09-07; no pinned SHA was recorded before
  the clone was discarded — if this line of work is revisited, re-clone and pin the SHA
  before citing line numbers again, since `main` can move.

We evaluated whether its program generator could be extracted and driven independently,
feeding programs into our existing UVM/lockstep checking stack in place of its own
Verilator-based differential-testing harness (which we had already ruled out as redundant —
see §2 below).

## 2. Why the checking harness was ruled out first (not evaluated further)

FuzzGPU's own oracle, `difftest-gpu/`, is a Chisel/Scala-lineage differential-testing
framework: DPI event-listener modules bound into the RTL (`WritebackRegEventListener.sv`,
`DecodeEventListener.sv`, `BarrierWritebackEventListener.sv`), a per-warp ROB
(`difftest-gpu/csrc/rob.hh`) that reorders out-of-order writebacks before comparing — solving
the same problem our lockstep Rule 1 solves, by a different mechanism — and a stepping
reference model (`Difftest::commit_()` calling into an `ISAEmulator`).

This is architecturally sound but built on **Verilator**, not QuestaSim/UVM, and it does not
carry an RVVI extension, a third-party ISA coverage VIP, or our four-guard non-vacuity
discipline. Standing up their checker alongside ours would have meant a second, weaker
verification stack in a second toolchain. Decision: **use our own checking stack; evaluate
only their generator as a possible stimulus source.**

## 3. The coupling evidence — why the generator could not be isolated

The generator (`src/generator.cc` + `src/gen_{warp,bcc,thread_ctrl,thread_merge,load_store,
barrier,csr,regext,tensor_core,refresh}.cc`, built into a static library `lib_fuzz_gpu`,
`CMakeLists.txt:382-421`) is **not** a batch/grammar-based text generator. It is
**execute-in-the-loop**: for every generated instruction it calls into a live emulator
instance to read register state, compute effective addresses, and decide the next legal
operand.

Verified, file:line:

- `include/fuzzer_state.hh:8` — `#include <difftest_gpu/isa_emulator.hh>`, and
  `fuzzer_state.hh:92` — `difftest::ISAEmulator isa_emu;` is a **member of the generator's
  live state**, not an optional post-hoc checker.
- `src/gen_warp.cc:249,251` — `isa_emu.schedulable(...)` / `isa_emu.execute_warp(...)`: each
  generated basic block is **actually executed** against the emulator as it is built.
- `src/gen_load_store.cc:432,463,470,475,483,509,964,1189` — address legality
  (`illegal_paddr`), effective-address computation, memory-scope tracking, and direct
  physical-memory writes (`pmem_write`) all route through `isa_emu`.
- `src/gen_bcc.cc:71-72,445,448` — branch-condition generation reads live register values
  from `isa_emu` and pokes emulator-internal SIMT-stack state.

That emulator, `difftest::ISAEmulator` (`difftest-gpu/csrc/include/difftest_gpu/
isa_emulator.hh:9`), is a wrapper whose Vortex implementation is
`libemulator_vortex.a`, built from **their own vendored Vortex fork**
(`targets/vortex/runtime/difftest/vortex.cpp`) via `CMakeLists.txt:180`.

**No generator-only build mode exists**, and the coupling is not incidental:

- `CMakeLists.txt:194-210` (`add_custom_target(vortex-emu ...)`) runs `configure`, builds
  Verilator from `thirdparty/verilator`, then builds **both** the ISA emulator and the
  Verilator/DPI RTL-DUT harness **in one shell command** — there is no target producing only
  the emulator half.
- `CMakeLists.txt:414` — `add_dependencies(lib_fuzz_gpu vortex-emu)`: the generator library
  itself depends on that combined target.
- `CMakeLists.txt:407-412` — `lib_fuzz_gpu`'s `ARCH_VORTEX` link line also pulls `ramulator`
  and `softfloat.a` from `targets/vortex/third_party/` directly, not only through the
  emulator.
- `./build.sh --help` confirms `--no-dft` disables the RTL-DUT side's differential-testing
  behaviour only; it does not skip building `vortex-emu` or drop the generator's link
  dependency on it.

## 4. The conclusion

Extracting the generator would require reimplementing `difftest::ISAEmulator`'s full API
(`bootstrap`, `execute_warp`, `reg_read`, `emulate_load_store`, `illegal_paddr`,
`get_mem_scope`, `translate_vaddr`, `pmem_write`, `schedulable`, `terminated`, plus
Ventus-specific SIMT-stack calls) closely enough for the generator's operand-legality logic
to hold — in effect, building a second Vortex ISA emulator behind a matching ABI.

**We already have that emulator: SimX.** But wiring SimX behind FuzzGPU's `ISAEmulator` ABI
(the option we call Option A) buys us their generation code in exchange for a real,
open-ended shim-engineering cost, against a payoff that is mostly aesthetic — the resulting
programs would not be meaningfully different from what a generator written directly against
our own DUT's configuration space produces. **Extraction cost exceeds reimplementation cost,
and our downstream-checking architecture (SimX + eleven probes + lockstep) does not need an
in-loop emulator at generation time at all** — correctness comes from the existing checking
stack after the fact, not from the generator proving legality as it writes.

**Decision: build our own generator (`sim/simtgen/`) against our own configuration space,
informed by FuzzGPU's published knob taxonomy, with no FuzzGPU source vendored or
transliterated.**

## 5. What we took anyway — cited, not copied

FuzzGPU's axis decomposition, as design guidance only:

| FuzzGPU source | Axis it establishes |
|---|---|
| `gen_bcc.cc` | control divergence as a first-class generation axis, with branch-condition shaping |
| `gen_load_store.cc` | memory access patterns — stride, scatter, alignment |
| `gen_barrier.cc` | synchronisation / barrier topology |

`sim/simtgen/`'s actual knobs are derived independently from our own DUT's configuration
space (`NUM_WARPS`, `NUM_THREADS`, the LSU coalescer window, the LMEM bank count, IPDOM stack
depth) — see `sim/simtgen/knobs.py`. No FuzzGPU constants, tables, or generation logic are
present in this repository.

**The citable sentence:** *informed by FuzzGPU's published knob taxonomy, implemented against
our own checking stack.*

## 6. Where this is used

- **Thesis** — a short subsection under generator design, stating the evaluation and the
  reasoning in §4, as engineering judgment on the record rather than an unexplained absence.
- **Defence Q&A** — answers "why didn't you use an existing tool?" with file:line evidence
  instead of a hand-wave.
