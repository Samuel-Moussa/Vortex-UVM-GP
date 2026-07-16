# Reference Model Integration — SimX as Golden Model via DPI-C

*Consolidated technical report on how the SimX instruction-set simulator is bridged into the Vortex UVM verification environment through the DPI-C shared-library mechanism.*

---

## 1. Introduction

### 1.1 What SimX is

SimX is the functional / cycle-approximate C++ instruction-set simulator that ships as part of the Vortex GPGPU project. It lives in the upstream Vortex tree at `vortex/sim/simx/` and is built as a standalone executable (`simx`) that can consume a Vortex kernel binary, execute it on a software model of the Vortex processor, and report the resulting architectural state, console output, and performance counters. Architecturally, SimX models the pieces of the Vortex GPU that matter for correctness of the ISA and the SIMT execution model: the cores, warps, threads, the register files, the memory subsystem (with a lazily-allocated RAM object), and the device configuration registers (DCRs) that the host uses to launch a kernel. It does *not* model the exact micro-architectural timing of the RTL — no pipeline stages, no cache-line replacement policies at cycle granularity — but it does model everything an ISA-compliant program would observe: memory contents, register values, MMIO writes, and console output.

For verification purposes, SimX plays the role of a **golden reference model** — a second, independently developed implementation of the same specification that the RTL is supposed to implement. Whenever the RTL DUT executes a program, SimX executes the same program in software; at the end of the run, the two end-states are compared. Any divergence between what the RTL wrote to memory and what SimX wrote to memory, for the same input program, is a suspected DUT bug.

### 1.2 Why a golden model at all

In an ISA-heavy design like Vortex, checking correctness cell-by-cell or wave-by-wave is intractable. Even for a single kernel like `vecadd`, thousands of instructions execute across multiple warps, each writing to hundreds of memory locations. Hand-writing expected output for each test is fragile and does not scale. Instead, the verification methodology adopted here is **black-box end-state equivalence**:

- Load the same program into both the DUT and the golden model.
- Let each of them run to completion independently.
- At the end, compare the observable state (memory window + console output) between the two.

The scoreboard becomes the arbiter: it never inspects the DUT's internal signals, only its externally observable effects, and it uses SimX as the ground truth for what those effects *should* have been. The advantage is that we do not have to encode expected behaviour per test — the reference model derives it automatically from the program itself. The disadvantage is that we now depend on the correctness of that reference model, which is why the Vortex team has invested in SimX as the canonical golden implementation.

### 1.3 Alternatives considered

Before choosing SimX, the following alternatives were considered:

- **Spike** — the reference RISC-V ISS from the RISC-V International consortium. It is open source, mature, and widely used for scalar RISC-V verification. However, Spike models only scalar RISC-V and has no native concept of Vortex's SIMT execution, warps, tmask propagation, or Vortex-specific extensions (`vx_tmc`, `vx_bar`, `vx_split`, `vx_join`, etc.). Integrating Spike would have required substantial modification to teach it about warps and thread-masks, effectively duplicating what SimX already does. It was therefore judged not to be a drop-in golden model for a GPGPU.
- **Commercial ISS platforms** — several vendors offer high-fidelity commercial instruction-set simulators (for example the Imperas / OVP models, some of which are marketed as paid products with restrictive licensing). These would in principle have offered a well-supported reference, but the licensing cost and the lack of native Vortex support made them impractical for an academic project on a fixed budget.
- **rtlsim** — Vortex ships an in-tree RTL-based simulator (`vortex/sim/rtlsim/`) that runs the same RTL as the DUT, wrapped in a lightweight C++ harness. It is useful for sanity-checking RTL runs in isolation, but it is *not* an independent reference — it *is* the DUT. Comparing rtlsim to the UVM DUT would only detect harness/interface issues, not RTL bugs, because both sides share the same underlying RTL. It cannot serve as the golden model.
- **Verilator on the RTL** — same objection as rtlsim: it is the DUT re-simulated in another simulator, not an independent implementation.
- **Hand-written expected outputs per test** — brittle, does not scale beyond a handful of tests, and defeats the purpose of automated regression.

Given all of the above, SimX was the only realistic candidate: it is open source, ships with Vortex, natively understands the SIMT model, is written and maintained by the same team that authored the RTL specification, and already implements the DCR interface used to launch kernels. Its main drawback — that it is a C++ program with global state and internal `abort()` paths, not a library designed for embedding into another simulator — is what motivated the engineering work described in the rest of this report.

### 1.4 The integration problem in one sentence

SimX is a standalone C++ program; the Vortex UVM environment is SystemVerilog running inside Questa's `vsim`. To use SimX as a golden model during a UVM run, we need a way to call SimX's C++ functions directly from SystemVerilog, share memory between the two, and get results back — all in a single process. The mechanism that makes this possible is **SystemVerilog's Direct Programming Interface for C (DPI-C)**, packaged as a runtime-loadable **shared library**. Every other piece of the reference-model integration exists to support that single idea.

---

## 2. The DPI-C Bridge — Concept

### 2.1 What DPI-C is

DPI-C is a standardised part of SystemVerilog (defined by IEEE 1800) that lets a SystemVerilog design declare functions and tasks whose implementation is written in C or C++ instead of SV. To the SV code, a DPI-imported function looks like an ordinary function — you call it, you get a return value. Under the hood, however, the SV simulator does not compile that function; it links against a native function of the same name exported from a shared library. When the SV code calls the function, the simulator marshals the arguments onto the standard C calling convention (the platform ABI), jumps into the native code, and copies the return value back into SV data types on the way out.

The important consequence is that DPI-C is not inter-process communication. There are no sockets, no shared-memory segments, no serialisation formats. The C code runs *inside* the simulator's own process, in the same address space, on the same thread. A pointer passed from SV to C is a real pointer into the simulator's memory; a global variable in the C code is a global variable in vsim's `.bss` section. This is what makes DPI-C fast enough for cycle-by-cycle use, but also what makes a bug in the C code capable of crashing the entire simulation.

### 2.2 The core challenge with SimX

SimX was not written with DPI in mind. It is a full C++ application, with a `main()` function, its own signal handlers, its own lifecycle. It uses `abort()` inside its `Emulator::decode` path when it hits an instruction or memory access it cannot model. It manages global singletons via `SimPlatform::instance()`. It expects to own the process. None of that is compatible, out of the box, with being called as a subroutine from vsim.

Adapting SimX for DPI-C use therefore required a wrapping layer — a translation membrane whose job is to make SimX behave like a stateless-looking C library, at least from vsim's perspective. That membrane is the `simx_dpi.cpp` file. Everything it does can be understood as answering one of four questions:

1. How do we expose SimX's C++ objects (`Processor`, `Arch`, `RAM`) as a small, C-callable API that SystemVerilog can import?
2. How do we shuttle data — bytes of memory, addresses, DCR values — across the language boundary without corrupting types or losing information?
3. How do we survive SimX's assumption that it owns the process — in particular, how do we prevent an internal `abort()` from taking vsim down with it?
4. How do we reconcile SimX's assumption that memory is initialised lazily (with poison sentinels) with the fact that the UVM environment has already staged program bytes and kernel arguments before SimX was even asked to run?

The three files at the centre of the answer — `simx_dpi.cpp`, `simx_pkg.sv`, and `Makefile` — each own one third of the solution. The C++ side implements the wrapper, the SV side declares the wrapper's function signatures so SV code can call them, and the Makefile compiles and links the whole thing into a single shared object that vsim can load at startup.

---

## 3. Anatomy of the Reference-Model Files

### 3.1 `simx_dpi.cpp` — the C++ wrapper

**Role.** `simx_dpi.cpp` is the DPI-C wrapper around SimX. Its purpose is to expose a small, C-callable, stable API that SystemVerilog can import, and to hide behind that API all the messiness of SimX's C++ object model, lifecycle, and failure modes. Every function that SV can call ends up implemented here; every piece of global state that the wrapper needs to survive between calls also lives here.

The file's headline design decisions are:

- Everything the SV side calls is placed inside a single `extern "C" { ... }` block, so the C++ compiler emits unmangled symbol names that `dlsym("simx_init")` can find in the shared library.
- All persistent SimX state (the `Processor`, `Arch`, and `RAM` objects, cycle counters, execution completion flags, captured console output) is kept in a small set of file-static globals. The DPI functions themselves are effectively stateless — they read and write those globals but do not hold state of their own between invocations.
- The wrapper installs its own signal handlers around the SimX step loop, so that a `SIGABRT` or `SIGSEGV` originating inside SimX gets converted into a sentinel return code instead of tearing the process down.
- Every write into SimX's RAM is silently duplicated into a private cache, so that when SimX performs its post-reset page-poisoning inside `run()`, the wrapper can replay the cached writes and the program image is not lost.

The rest of this section walks through the wrapper's functional groups — not line by line, but by intent and by the responsibility each group carries.

**Global state.** At the top of the file lives the shared C++ state: pointers to the SimX `Processor`, `Arch`, and `RAM` objects; boolean flags recording whether initialisation has completed and whether the RAM has been attached; a running cycle counter; the startup address that will be programmed into the DCR; the current exit code and "done" flag; a captured console string; a `sigjmp_buf` used by the crash guard; and a map keyed by address containing every write that has ever been staged into SimX's RAM. All of these are `static`, meaning they are not exposed as symbols in the shared library — only the wrapper functions themselves are visible from outside. This is deliberate: SV code should have no way to reach around the wrapper and manipulate SimX's state directly; every interaction has to go through a named DPI function so that invariants (initialisation ordering, memory caching, crash handling) can be enforced.

**Initialisation group.** The `simx_init` function is the entry point that constructs a fresh SimX instance. It takes the topology parameters (`num_cores`, `num_warps`, `num_threads`) as SV integers, validates them against the compile-time defines baked into the shared library at build time, and — if they match — constructs an `Arch` object, a `RAM` object sized appropriately for the target XLEN (a flat 4 GB space for RV32, a sparse unbounded space for RV64), and a `Processor` bound to that Arch. It then attaches the RAM to the processor and runs a small self-test that writes and reads a four-byte pattern (0xDEADBEEF) at the reset vector to prove the memory hierarchy is functional before any real workload touches it. The mismatch check between requested topology and compiled topology is the mechanism that catches the common error where SimX has been rebuilt for a 2×4×4 configuration but the UVM run tries to instantiate it with 4×4×4 — a mismatch that would otherwise produce cryptic segfaults deep inside SimX.

Companion to `simx_init` is `simx_cleanup`, which tears everything down: it drains any pending co-simulation retire records, deletes the `Processor`, `RAM`, and `Arch` objects, and resets every global flag. Between the two, they define the SimX lifecycle bracket that must surround every UVM test.

**Program-loading group.** There are three loaders, each covering a different program-image format that appears in the Vortex ecosystem:

- `simx_load_bin` reads a raw binary file — the flat kernel image produced by `llvm-objcopy` — and places it at the requested load address. It sets the startup address to that same load address, so a subsequent `simx_run` will begin execution there. This is the loader most commonly used by the UVM environment, because the kernel programs under `vortex/tests/kernel/` and `vortex/tests/regression/` are built into `.bin` form.
- `simx_load_hex` handles the Verilog memory-image format (`@ADDRESS` markers followed by byte or 32-bit word tokens). It auto-detects the token width, treats the base address of `0x80000000` as an implicit default when a `@0` marker appears, and writes the parsed bytes into RAM. This loader also programs the startup DCR at the end.
- `simx_load_hex_at` is a variant of the hex loader that takes an explicit base address and leaves the startup address alone. It exists for cases where the harness has already installed a bootstrap payload at a specific address (see below) and does not want the program-image loader to overwrite the startup DCR.

Every one of these loaders funnels its bytes through the small helper `ram_write_cached`, which does two things at once: it writes the bytes into SimX's live RAM, and it also stores a copy in the global staged-memory map keyed by address. The reason for this dual write is subtle and worth explaining now, because it drives design decisions in almost every other function.

SimX's `Processor::step` path, on the very first call, performs a hardware-style reset of the internal `SimPlatform` singleton. That reset causes SimX's lazily-allocated RAM pages to be dropped back to the `0xBAADF00D` poison pattern that indicates uninitialised memory. Any bytes that the wrapper wrote into RAM *before* the first step call — the program image itself, the exit-code bootstrap, the kernel-argument struct staged by the harness, any pre-populated buffers — are wiped by that reset. If the wrapper did not intervene, SimX would then begin executing at `0x80000000` and immediately fetch `0xBAADF00D`, decode it as an illegal instruction, and abort. To prevent this, every write is cached. The `simx_run` function, immediately after issuing the reset call, iterates over the entire cache and replays every stored write into RAM. The result is that SimX starts stepping with a RAM whose contents match exactly what the harness intended.

**Memory-access group.** The `simx_write_mem` and `simx_read_mem` functions are the byte-level entry points that SV code uses to move data across the boundary. Both accept a 64-bit address, a size in bytes, and a SystemVerilog open array of `byte` elements. On the C side, the open array is not received as a raw pointer — SV open arrays are opaque handles whose internal representation is chosen by the simulator vendor. Instead, the wrapper calls `svGetArrayPtr`, one of the helper functions declared in `svdpi.h`, to obtain the address of the array's underlying byte buffer, and then treats it as a normal `uint8_t*` for `size` bytes. This is the standard idiom for bulk-byte transfer across the DPI boundary and is markedly more efficient than passing bytes one at a time.

The write path has an additional behaviour worth highlighting: it always caches the write into the staged-memory map, even if SimX has not yet been initialised. This is because the UVM scoreboard may push writes into the wrapper very early in the run — before `simx_init` has been called — as part of staging the kernel-argument structure. If those writes were merely dropped, they would be lost forever. Instead, they land in the cache, and `simx_run` replays them into RAM after initialisation and reset. The write path also has a small heuristic: it only updates the "inferred startup address" for writes that fall inside the program-code region `[0x80000000, 0x90000000)`. Writes to the data region above `0x90000000` (where kernel arguments and I/O buffers live) do not shift the startup address. This prevents a subtle bug where the exit-code bootstrap would be built on top of a data buffer and SimX would begin execution at data, not code.

The read path is simpler: it validates its inputs, obtains the destination pointer via `svGetArrayPtr`, and delegates to `g_ram->read` to fill the buffer. The scoreboard uses this path during the final comparison phase to pull SimX's end-state RAM contents back into SystemVerilog for word-by-word compare against the DUT's shadow memory.

**DCR group.** The `simx_dcr_write` function forwards a device-configuration-register write into SimX. It also intercepts writes to the two startup-address DCRs so that the wrapper's `g_startup_addr` global tracks whatever the SV side asked for — this is what allows the scoreboard's DCR agent, which mirrors every DCR write the DUT observes, to keep SimX's notion of the startup address synchronised with the DUT's notion of it.

**Exit-code bootstrap.** A dedicated function, `simx_init_exit_code_register`, installs a small four-instruction RISC-V stub in memory sixteen bytes below the program's startup address, and reprograms the startup DCR to point to that stub. The stub does two things before jumping to the real program: it sets architectural register x3 to zero (Vortex uses x3 as the exit-code register), and it uses an `auipc/jalr` pair to jump forward to the original startup address. This mechanism guarantees that x3 has a well-defined initial value at kernel entry, so that if the kernel forgets to initialise it, the wrapper can still read a deterministic exit code afterwards. Historically, an off-by-one in the jump immediate (16 instead of 12) caused the first instruction of the user program to be skipped; the current code uses the corrected value of 12.

**Run group.** The `simx_run` function is the heart of the wrapper. It performs, in sequence: a call to `SimPlatform::instance().reset()` to force every core and cache into a defined post-reset state; a replay of every cached write into RAM (see the discussion above); a diagnostic dump of the arg-struct region so that if the harness has misconfigured kernel arguments, the log makes it visible; a redirection of `std::cout` into an `std::ostringstream` so that anything the program prints during execution is captured; the installation of `SIGABRT` and `SIGSEGV` handlers around a bounded step loop; and finally the loop itself, which repeatedly calls `Processor::step` in chunks of one hundred cycles until either `is_done()` returns true or a hard cap of two million cycles is reached.

The bounded step loop, together with the surrounding signal handlers, is the single most important defensive mechanism in the file. SimX's `Emulator::decode` can call `abort()` when it hits an instruction it does not know how to model. Without the signal handlers, that `abort()` would terminate vsim outright; the entire simulation would collapse with a stack trace and no useful diagnostic. With the handlers installed, the SIGABRT is caught, control jumps back out of the step loop via `siglongjmp`, and `simx_run` returns the sentinel value `-3`. The scoreboard sees the -3, classifies the run as UNVERIFIABLE (not as a DUT failure), and skips the memory comparison — because a crashed SimX has no valid end-state to compare against, and a false-fail against poisoned data would be misleading. Separately, if the loop hits the two-million-cycle cap without seeing an EBREAK, the function returns `-2` — the "capped, not crashed" sentinel — which typically indicates a kernel that never called `vx_tmc(0)` to terminate its warps.

**Status query group.** A handful of small functions — `simx_is_done`, `simx_get_exitcode`, `simx_get_console` — allow the SV side to poll completion state and pull captured console output back across the boundary as a null-terminated C string, which SV receives as an ordinary `string`.

**Co-simulation retire group.** The functions `simx_cosim_pop`, `simx_cosim_pending`, and `simx_cosim_clear` implement the cycle-by-cycle retire-record interface that the scoreboard's M1 co-simulation mode uses. Each retire record is a small structure describing one writeback event from SimX's back end (UUID, core ID, warp ID, PC, thread mask, writeback destination). The pop function is the only DPI function in the file that uses the per-element open-array helpers (`svLow`, `svHigh`, `svGetArrElemPtr1`) rather than the whole-array `svGetArrayPtr`. This is because the result vector is a per-thread array of 64-bit values, and the size is not known at compile time — it depends on how many threads SimX was configured with — so the pop function iterates one element at a time. The retire interface is important architecturally for enabling cycle-by-cycle equivalence checking, but is orthogonal to the end-state comparison flow that the scoreboard uses as its primary gate.

### 3.2 `Makefile` — the build

**Role.** The Makefile in `ref_model/` has a single primary job: produce `simx_model.so`, the runtime-loadable shared library that vsim will bind against. Every other target in the file — the standalone `test_bin_postmortem`, `test_simple_postmortem`, the `otf_*` on-the-fly hex tests, the GUI-mode helpers — is a leftover scaffold from the reference model's own local development flow and is not on the path used by the main UVM environment. When the main UVM `make sim` target runs, it invokes `scripts/simulate.sh`, which in turn depends on `simx_model.so` having already been built by this Makefile.

**How it produces the shared library.** The build rule is a single `g++` invocation. It takes `simx_dpi.cpp` as input, compiles it in one step (there is no intermediate object file for the wrapper), and links it against three groups of pre-built object code:

- The full set of SimX object files pulled from `sim/simx/obj/*.o` and `sim/simx/obj/common/*.o`. These are the compiled implementations of every SimX C++ class the wrapper references — `Processor`, `Arch`, `RAM`, `Emulator`, the memory coalescer, the cache simulator, the local-memory model, and so on. This glob is a design decision: rather than track each object file explicitly, the Makefile lets the file system decide, which makes rebuilding trivial when SimX changes but also means the DPI library silently inherits whatever object files happen to exist in `sim/simx/obj/` at build time. In particular, `main.o` from SimX's standalone executable gets pulled in too. This is harmless because `main` is never called from the shared library, but it does mean the `.so` contains a dead entry-point symbol.
- The softfloat archive at `third_party/softfloat/build/Linux-x86_64-GCC/softfloat.a`. This is statically linked — the softfloat implementation of IEEE-754 arithmetic ends up baked into the shared library itself. SimX uses softfloat to model the floating-point unit at bit-exact precision.
- The ramulator dynamic library, linked with `-lramulator` and given an `rpath` so that vsim can find `libramulator.so` at load time without needing `LD_LIBRARY_PATH` to be set on every run. Ramulator models the DRAM channel behaviour that SimX uses when memory-timing-approximate mode is enabled.

Before the link step, a `check_simx` prerequisite verifies that `sim/simx/obj/` actually exists. If it does not, the build stops with an instruction to run `make` inside `sim/simx` first. This prerequisite does *not* trigger the SimX build — it only checks that the user has already performed it. The rationale is that SimX and the DPI wrapper have independent build systems, and coupling them tightly would make the DPI Makefile fragile whenever the SimX Makefile changes.

The compiler is chosen deliberately: `g++-11` is preferred, with a fallback to `g++`. The reason is a well-known ABI issue with the older `libstdc++` that Questa's own build was compiled against; if the DPI shared library depends on newer `libstdc++` symbols (specifically `GLIBCXX_3.4.29`) that Questa's private copy does not export, then loading the library fails at vsim startup with a cryptic error. The Makefile's answer is to link with `-static-libstdc++` and `-static-libgcc`, which bake a copy of the C++ runtime directly into `simx_model.so`. This costs a few megabytes of on-disk size but completely severs the runtime dependency on whatever `libstdc++` Questa has in its private lib directory. The fix is described in more detail in `docs/GLIBCXX_FIX_SUMMARY.md`.

**Compile flags.** Beyond the language standard (`-std=c++17`) and the shared-library flags (`-fPIC -shared`), the Makefile passes a series of include-path (`-I`) options that tell the preprocessor where to look for header files. These are covered in detail in the next section, so this note only enumerates them at a high level: Questa's own `include/` directory for `svdpi.h`; the SimX source tree for the SimX class headers; the Vortex hardware directories for the VX_config and VX_types headers that define constants like `VX_DCR_BASE_STARTUP_ADDR0`; and the third-party directories for softfloat, ramulator, and cvfpu headers that SimX transitively depends on.

The Makefile also passes a group of `-D` architecture defines: `NUM_CLUSTERS`, `NUM_CORES`, `NUM_WARPS`, `NUM_THREADS`, and either `XLEN_32` or `XLEN_64`. These are baked into the resulting shared library at build time. Inside `simx_dpi.cpp`, the `simx_init` function reads these compile-time constants and compares them against the runtime request; a mismatch fails early with an explicit diagnostic. This is the mechanism that catches configuration drift between the SimX build and the UVM run's `+CORES=` plusarg.

### 3.3 `simx_pkg.sv` — the SystemVerilog side

**Role.** `simx_pkg.sv` is the SystemVerilog counterpart of `simx_dpi.cpp`. Its purpose is threefold: to declare the DPI-C function signatures so that SV code can call them; to provide a SystemVerilog mirror of the C `simx_retire_t` struct so that the scoreboard can carry a popped retire record around as a first-class value; and to package the whole thing as a UVM-friendly SystemVerilog `package` that the environment can import.

**The import declarations.** The bulk of the file — every line beginning with `import "DPI-C"` — is nothing more than a set of function-signature declarations. Each one tells the SystemVerilog compiler two things: first, that a function of the given name and signature exists somewhere outside SV; second, that when SV code invokes that function, the simulator should resolve the call by looking inside a shared library that was loaded at startup via the `-sv_lib` flag. There is no code in these lines. They are pure declarations, exactly analogous to an `extern` prototype in a C header file. The corresponding *implementation* lives in `simx_dpi.cpp` and is compiled into `simx_model.so`.

The keyword `context` appears at the beginning of most of these declarations. Its formal meaning is that the declared function is permitted to call *back* into SV — for example, via `svGetScope` or `svCall...` helpers — during its execution. In this codebase, none of the wrapper's C++ functions actually use those callback helpers, so the `context` keyword here is defensive style rather than a load-bearing feature; it costs a tiny amount of per-call bookkeeping and does not change behaviour. One import (`simx_load_hex_at`) inconsistently omits `context`. This is inconsistent but harmless.

The set of imports is exhaustively enumerated below, grouped by function:

- **Lifecycle:** `simx_init`, `simx_cleanup`.
- **Memory transfer:** `simx_write_mem`, `simx_read_mem`.
- **Program loading:** `simx_load_bin`, `simx_load_hex`, `simx_load_hex_at`.
- **DCR:** `simx_dcr_write`, `simx_init_exit_code_register`.
- **Execution:** `simx_run`, `simx_step`.
- **Status:** `simx_is_done`, `simx_get_exitcode`, `simx_get_console`.
- **Cycle-by-cycle retire records:** `simx_cosim_pop`, `simx_cosim_pending`, `simx_cosim_clear`.

Data-type mapping across the boundary follows the SV LRM: SV `int` becomes C `int32_t`; SV `longint` becomes C `uint64_t` (with a signedness dance the wrapper handles by casting on the way in); SV `byte` becomes C `unsigned char`; SV `string` becomes C `const char*`; SV open arrays (`byte data[]`, `longint unsigned result[]`) become C `svOpenArrayHandle`, an opaque token that the wrapper unpacks with `svGetArrayPtr` (for whole-buffer access) or `svLow`/`svHigh`/`svGetArrElemPtr1` (for element-by-element access when the size is not known at compile time).

**The `simx_retire_s` struct.** Alongside the imports, the package declares a SystemVerilog struct that mirrors the layout of SimX's C `simx_retire_t`. This is a matter of convenience: rather than pass ten separate scalars around whenever a retire record needs to be handled inside SV, the scoreboard can copy them into an `simx_retire_s` instance immediately after popping. The struct is not itself passed across the DPI boundary — the boundary uses individual output arguments — but it is the natural SV-side representation once a record has been unpacked.

**The `simx_golden_model` UVM component.** The file ends with a full `uvm_component` declaration named `simx_golden_model`. In its `run_phase`, this component calls `simx_init`, then `simx_dcr_write`, then `simx_load_bin`, then `simx_run`, and finally `simx_read_mem` on a result region, and pushes the result bytes onto an analysis port. This class is a self-contained golden-model driver that could, in principle, sit inside a UVM environment and act as the scoreboard's reference. In practice, however, it is **not** the integration path used by the main UVM environment. The real environment imports `simx_pkg::*` in `vortex_env_pkg.sv` only for the DPI function symbols and the retire-record struct; the `simx_golden_model` class itself is not instantiated. The real caller is `vortex_scoreboard.sv`, which owns the SimX lifecycle directly. `simx_golden_model` appears to be an early prototype or a scaffold for standalone ref-model testing; it is not on the critical path for the current UVM flow.

---

## 4. What the Shared Library Actually Is

### 4.1 File format and contents

A `.so` file — the extension stands for "shared object" — is a compiled, linked chunk of native CPU instructions stored on disk in the ELF format (Executable and Linkable Format) on Linux. Structurally, it is not fundamentally different from a normal executable: both are ELF files, both contain code sections, data sections, symbol tables, and relocation records. What distinguishes a shared object from an executable is a set of flags in the ELF header (the file type is `ET_DYN`, not `ET_EXEC`) and the fact that the code inside was compiled with the `-fPIC` (position-independent code) flag, meaning that every jump, branch, and data access uses relative addressing instead of hard-coded absolute addresses. That property is what lets the operating system's dynamic loader map the same `.so` into different virtual addresses in different processes without needing to patch every internal reference.

Inside `simx_model.so`, the reader would find several sections, each with a specific role:

- The **`.text` section** holds the actual CPU instructions that implement every function in the library. Every SimX function that the wrapper calls transitively — `Processor::run`, `Emulator::step`, `Emulator::decode`, the softfloat arithmetic routines, the memory coalescer, the cache simulator, everything reachable from any exported symbol — has its compiled machine code sitting here. The wrapper functions themselves (`simx_init`, `simx_run`, `simx_write_mem`, etc.) are also in `.text`; they are what `dlsym` will find when vsim asks for their addresses. This section is mapped read-only and executable when the library is loaded, so the CPU can fetch instructions from it but no code can accidentally overwrite it.
- The **`.rodata` section** holds read-only data — string literals like the diagnostic messages the wrapper prints (`"[SimX-DPI] Initializing SimX Golden Model"`), lookup tables inside softfloat, constant configuration data, and so on. Also mapped read-only.
- The **`.data` section** holds initialised writable globals. This is where the wrapper's global pointers (`g_processor`, `g_ram`, `g_arch`) live, along with the initialised parts of any other globals. When the shared library is loaded, this section is copied from the file into a fresh, per-process, writable memory region — so each process that loads `simx_model.so` gets its own private copy. This is what makes it safe for two independent vsim runs on the same machine to load the same `.so`: they see the same code but do not share the writable globals.
- The **`.bss` section** holds uninitialised writable globals — anything declared without an initialiser gets zeroed on load and lives here. The staged-memory map, the captured console string, the crash-guard `sigjmp_buf`, and various boolean flags all end up here. Like `.data`, this is per-process.
- The **dynamic symbol table** is the name-to-address map that `dlsym` consults. When vsim calls `dlsym("simx_init")`, the loader walks this table, finds the entry for `simx_init`, and returns the pointer to where that function's code begins inside the mapped `.text` section. Only symbols marked as exported end up in this table; anything declared `static` in the C++ source, and anything C++ would mangle in a way `dlsym` cannot reproduce, stays private. The `extern "C"` wrapper around the DPI functions in `simx_dpi.cpp` is what forces the compiler to leave those particular symbol names un-mangled, so that `dlsym("simx_init")` finds `simx_init` and not `_Z9simx_initiii`.
- The **needed-libraries list** — a set of `DT_NEEDED` entries in the ELF's dynamic section — records every other shared library that `simx_model.so` itself depends on. On this project, the list includes `libramulator.so` (linked with `-lramulator`), `libc.so.6`, `libm.so.6`, and typically `libpthread.so.0` and `libdl.so.2`. When vsim loads `simx_model.so`, the loader recursively loads every one of these dependencies too, resolving symbols across the whole graph. `libstdc++` and `libgcc_s`, which would normally appear in this list, do *not* appear here because the Makefile passed `-static-libstdc++ -static-libgcc` at link time, which caused the compiler to bake copies of those runtimes directly into `.text` and `.data` rather than record a dependency on them.
- The **relocation records** are a list of "patches" that the dynamic loader applies when the library is mapped into a process. They exist because position-independent code, while mostly self-relocating, still has some references (particularly to external symbols in other shared libraries) that cannot be resolved until the actual addresses of those libraries in the current process are known. The loader walks the relocation records and updates each affected reference in place.

### 4.2 The runtime picture

The lifecycle of `simx_model.so` inside a running simulation looks like this. When vsim is invoked with `-sv_lib simx_model`, one of the first things it does after parsing its command line is to call `dlopen("simx_model.so", RTLD_NOW)`. The dynamic loader inside libc responds by finding the file on disk (using the search path controlled by `LD_LIBRARY_PATH` plus any `rpath` embedded in vsim's own binary), reading its ELF header, allocating virtual address ranges for each section, mapping the file's contents into those ranges, resolving every dependency listed in the needed-libraries list (recursively `dlopen`ing `libramulator.so`, and so on), and finally applying every relocation record. When all of that completes successfully, `dlopen` returns a handle that identifies the loaded library.

Vsim then iterates over every `import "DPI-C"` declaration it collected during SV elaboration. For each one, it calls `dlsym(handle, "simx_init")` — passing the SV-declared function name — and stores the resulting function pointer in an internal table. When, later during simulation, an SV statement calls `status = simx_init(2,4,4);`, vsim's compiled-SV code looks up the stored function pointer, marshals the three integer arguments into CPU registers (following the platform's ABI — on x86-64 Linux, the first three integer arguments go into `rdi`, `rsi`, `rdx`), and issues a plain machine-level `call` instruction to jump into the wrapper's code. When the wrapper returns, vsim reads the return value out of the ABI-designated register (`rax` on x86-64), converts it into an SV `int`, and stores it in the `status` variable. No IPC, no serialisation, no context switch — the entire round trip is a native function call and a couple of type-narrowing casts.

Because the entire library runs in vsim's own address space, there are consequences that a designer coming from a process-level view might not expect:

- A pointer created by SimX code (for instance, the pointer returned by `g_ram->read()` internally) is valid across DPI calls — the memory it points into is vsim's memory. Nothing about the DPI boundary corrupts pointers.
- A segfault or uncatchable abort inside SimX code lands in vsim's own signal-handling table, and the default behaviour is to terminate the process. This is why the wrapper installs its own `SIGABRT`/`SIGSEGV` handlers around the step loop and uses `sigsetjmp`/`siglongjmp` to escape. Without that guard, a SimX decode failure would take the entire simulation down with no useful diagnostic.
- Multi-threaded issues, if any, are shared between vsim and the DPI library. Currently the wrapper is not thread-aware, which is fine because Questa's SV execution is effectively single-threaded from the DPI's perspective.
- The wrapper's globals persist across DPI calls — that is the whole point — but they also persist across UVM tests unless `simx_cleanup` is called between them. In practice, each test does its own `simx_init`, which internally calls `simx_cleanup` first if a previous instance is still live; this pattern makes back-to-back tests safe.

### 4.3 Why a shared library and not a static library

An alternative to a `.so` would be a static archive (`.a`) that is linked directly into an executable. That is not viable in the DPI context because vsim is a fixed binary that we cannot relink. Vsim is shipped by the tool vendor and expects to load DPI code dynamically. Attempting to link SimX statically into vsim would require rebuilding vsim from source, which we neither have nor are entitled to. The shared-library form of DPI is precisely the mechanism the SV LRM specifies for extending a pre-built simulator with user-written native code.

### 4.4 What the shared library is not

It is worth being explicit about what a shared library is *not*, because misunderstanding this leads to real design errors:

- It is not a running process. Nothing inside the `.so` executes until vsim calls into it. When SV code returns from a DPI function, the `.so` code stops executing — there is no background thread, no callback loop.
- It is not a separate memory space. Everything the `.so` allocates, and every pointer it holds, references memory inside vsim's address space. A bug in the `.so` can corrupt vsim's own data structures.
- It is not a sandbox. There is no protection between vsim and the shared library. This is the price paid for the low latency of a direct function call.
- It is not persistent across simulations. Each `vsim` invocation gets its own fresh mapping of the library, with a freshly zeroed `.bss` and a fresh copy of `.data`. Nothing carries over between runs unless the wrapper deliberately writes to disk (which this wrapper never does).

---

## 5. The Compile-Time Machinery — Includes and Search Paths (summary)

The `#include` directives at the top of `simx_dpi.cpp` and the `-I` flags in the Makefile are the machinery that lets the C++ compiler make sense of every type name and function name the wrapper uses. They are compile-time-only: after the build, the resulting `.so` contains no header files at all, only compiled machine code that was produced with the headers in scope.

Each `#include` is a textual paste — the preprocessor opens the named file and copies its contents into the compilation unit. `svdpi.h`, sourced from Questa's install directory, brings in the DPI helper types (`svOpenArrayHandle`) and function prototypes (`svGetArrayPtr`, `svLow`, `svHigh`, `svGetArrElemPtr1`) that the wrapper uses to access SV open arrays; the actual implementations of those helpers live inside vsim itself and are resolved at DPI call time. The standard C++ headers (`<iostream>`, `<vector>`, `<map>`, `<csetjmp>`, `<csignal>`, and so on) declare the runtime types the wrapper depends on; their implementations come from libstdc++ and libc, which the Makefile links statically to avoid version drift. The SimX headers (`processor.h`, `arch.h`, `mem.h`, `simobject.h`) declare the C++ classes the wrapper instantiates; their implementations come from `sim/simx/obj/*.o`, linked in at build time. The Vortex hardware headers (`VX_config.h`, `VX_types.h`) provide the DCR-address defines that both the wrapper and SimX need to speak the same language when programming device registers. `simx_cosim_record.h` supplies the layout of the retire-record struct.

The `-I` flags in the Makefile are pure search paths — they tell the preprocessor which directories to look in when resolving each `#include`. They have no effect at runtime. Once `simx_model.so` is built, the include directories could be deleted from the filesystem and the library would continue to function correctly, because everything the includes declared has already been baked into the compiled code.

---

## 6. The DPI Import Contract (SV Perspective)

Each line in `simx_pkg.sv` that begins with `import "DPI-C"` is a bidirectional contract. It tells the SV compiler what the function's name and signature are, and it commits the eventual `.so` to providing exactly that symbol with exactly that ABI. When vsim starts, it walks every one of these declarations and attempts to `dlsym` the corresponding native name from the loaded library. A missing symbol causes an immediate startup failure; a symbol with the wrong signature causes silent memory corruption at the first call, because the marshalling code trusts the SV declaration to be truthful about how many arguments to place on the stack and in registers.

The mapping between SV types and C types is fixed by the SV LRM: SV `int` becomes 32-bit signed integer on the C side, SV `longint` becomes 64-bit signed integer, SV `byte` becomes 8-bit signed integer, SV `string` becomes `const char*` (with the string bytes copied into a wrapper-owned buffer at call time), SV open arrays become opaque `svOpenArrayHandle` values. The wrapper is responsible for using the correct `svdpi.h` helper when it wants to read the underlying storage — `svGetArrayPtr` for a raw buffer pointer when the array is a byte buffer whose size is known from a companion argument, or `svLow`/`svHigh`/`svGetArrElemPtr1` when the size must be derived from the array's bounds.

The `context` keyword on most imports grants the C function permission to call back into SV — for instance, to look up an SV variable or invoke an SV task. The wrapper's implementations do not use any callback features, so the `context` marker is effectively cosmetic here, but it does no harm to leave it in place.

The `import` lines and the `extern "C"` block in `simx_dpi.cpp` are the two halves of a name-and-ABI handshake. Both halves must agree perfectly — same function name, same argument count, same argument types, same return type. A mismatch results either in a startup failure (if the symbol cannot be found because a name changed) or in undefined behaviour at runtime (if the argument types disagree). The compiler cannot catch this class of error because the two halves are in different languages compiled by different tools; the discipline of keeping them in sync falls entirely on the developer.

---

## 7. End-to-End Flow — Build to Runtime Comparison (summary)

This section pulls together the full path a Vortex UVM test travels through, from the moment the Makefile is invoked to the moment the scoreboard signs off on the run. It is intentionally brief; each individual phase has been explained in more depth above.

### 7.1 Build

The `ref_model/Makefile` compiles `simx_dpi.cpp` in a single `g++` invocation and links it against the pre-built SimX object files, the softfloat archive, and the ramulator shared library. The output is `simx_model.so`. The build fails fast if the SimX object tree is not present. Architecture defines and XLEN are baked into the resulting `.so`; at runtime, `simx_init` will refuse to proceed if the SV side asks for a mismatched configuration.

### 7.2 Elaboration

When `vsim -sv_lib simx_model` starts, it `dlopen`s `simx_model.so`, walks every `import "DPI-C"` declaration collected from `simx_pkg.sv`, and resolves each imported name to a function pointer inside the library via `dlsym`. If any symbol is missing, the simulation aborts before time 0. All subsequent DPI calls from SV code are direct native function calls into the resolved addresses.

### 7.3 UVM run phase — SimX initialisation

Inside the scoreboard's `run_phase`, before any UVM stimulus runs, the scoreboard calls `simx_init` with the topology parameters from the configuration object. This constructs the `Arch`, `RAM`, and `Processor` C++ objects, attaches the RAM, and runs a self-test. The scoreboard then calls one of the program loaders (`simx_load_bin` or `simx_load_hex_at`, chosen by file-extension sniffing) to load the kernel image into SimX's RAM. Finally it calls `simx_init_exit_code_register` to install the four-instruction bootstrap that zeroes x3 before jumping to the real program.

### 7.4 UVM stimulus and shadow memory

The base test's `run_phase` waits for reset, then runs the DCR startup and performance-configuration sequences, then waits for completion. While the DUT executes, transaction-level events flow into the scoreboard through its analysis exports: memory writes update an SV-side associative array called `shadow_memory`; AXI writes do the same via a separate export path; DCR writes are mirrored into SimX with `simx_dcr_write`; console I/O bytes are captured into a `dut_console` string. Memory writes are *not* mirrored into SimX during this phase — the SV shadow memory serves as the DUT-side reference, and SimX is compared to it once at the end.

### 7.5 EBREAK trigger and final comparison

When the status agent reports that EBREAK has been detected, the scoreboard's `write_status` handler triggers the `ebreak_event` (unblocking the test's `wait_for_completion`) and immediately calls `run_final_comparison`. That function calls `simx_run`, which internally resets SimX, replays every staged write into SimX's RAM, redirects `stdout` for capture, and steps SimX to completion under signal-guard protection. If SimX crashes, the return code is `-3` and the run is classified UNVERIFIABLE without comparison. Otherwise, the scoreboard runs `compare_all_written`, which iterates every address the DUT wrote to, applies a two-gate filter (scope check first, then a byte-valid mask, then a poison check), reads the corresponding SimX bytes via `simx_read_mem`, and compares. Mismatches trigger `uvm_error`, with two forgiveness paths for GOT/relocation pointers and floating-point rounding tolerance. A separate console comparison compares the DUT's captured console output against `simx_get_console`.

### 7.6 check_results and pass/fail reporting

The base test's `check_results` function performs only a lightweight EBREAK-observed check; the real verdict has already been produced by the scoreboard in the form of `uvm_error` calls. The overall pass/fail is determined in `report_phase` by reading the UVM report server's error and fatal counts. A "vacuous run" guard in the scoreboard catches the case where a result window was declared but no address inside it was ever compared, converting silent success into an explicit error.

---

## 8. Consolidated Flow Diagram

```
Compile time
   simx_dpi.cpp  ─┐
   simx headers ─┤  #include (textual paste)
   VX_config.h  ─┘
                        │
                        ▼
                 [ g++ -c ]
                        │
                        ▼
   simx/obj/*.o + softfloat.a + libramulator.so
                        │
                        ▼
                 [ g++ link ]
                        │
                        ▼
                 simx_model.so
                 (ELF, .text + .data + .bss + symtab + deps)

Elaboration time (vsim start)
   vsim -sv_lib simx_model
                        │
                        ▼
                 dlopen("simx_model.so")
                        │
                        ▼
   for each `import "DPI-C" ...` in simx_pkg.sv:
     dlsym(handle, name) → function pointer table
                        │
                        ▼
   simulation begins at time 0

Run time
   vortex_scoreboard.run_phase:
     simx_init         → construct Arch, RAM, Processor
     simx_load_bin/hex → stage program (also cached in g_staged_mem)
     simx_init_exit_code_register → bootstrap installed
                        │
                        ▼
   vortex_base_test.run_phase:
     load_program, wait_for_reset, run_test_stimulus,
     wait_for_completion (blocks on ebreak_event)
                        │
                        ▼
   During execution, agents push transactions into scoreboard:
     write_mem, write_axi   → update shadow_memory + dut_console
     write_dcr              → simx_dcr_write (mirror to SimX)
     write_status(ebreak=1) → trigger ebreak_event, run_final_comparison
                        │
                        ▼
   run_final_comparison:
     simx_run           → SimPlatform reset, replay g_staged_mem,
                          step (signal-guarded), capture console
     compare_all_written → Gate1 (scope) → byte-valid mask
                            → Gate2 (poison) → per-word compare
                            → simx_read_mem for each address
     compare_console    → dut_console vs simx_get_console
                        │
                        ▼
   check_results (base) → EBREAK check only
   report_phase         → pass/fail from UVM error count + vacuous-run guard
```

---

## 9. Closing Remarks

The reference-model integration described in this report exists to answer a very simple question — "did the DUT do what the ISA specification says it should have done?" — with a very concrete, checkable answer: "yes, because for the same input program, SimX and the DUT ended up in the same architectural state." Every piece of engineering complexity in the wrapper, the build system, and the scoreboard hookup exists to make that comparison robust against the real-world messiness of a C++ simulator that was not designed for embedding, an SV/C++ boundary that has to marshal every argument by hand, a memory model whose lazy allocation collides with the harness's early staging, and a device reset that would otherwise wipe out the program image before it runs. The result is a golden-model integration that runs inside the same vsim process as the DUT, compares end-states through a small stable API, and survives even a hard SimX crash without taking the whole simulation down. From the SV code's perspective, calling `simx_run()` is indistinguishable from calling any other function; from the C++ code's perspective, being called from vsim is indistinguishable from being called from any other C++ program. The DPI-C shared-library mechanism is what makes those two illusions consistent with each other.
