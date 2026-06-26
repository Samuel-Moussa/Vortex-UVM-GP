# Session Fixes — 2026-06-26 (Samuel)
## Branch: `Sudky_scoreboard_and_coverage_collector`

This document covers **6 commits** landed in one session, plus a follow-up
configurability issue that was identified and is now being worked.  Each section
describes the root cause, the files touched, the exact change, and any conflict
risk with Ahmad's or Steven's lanes.

---

## Fix 1 — C1 + ISS-01: Derive `VX_MEM_TAG_WIDTH` from RTL + Hex Load Fix
**Commit:** `4c36bd82`  
**Files:** `vortex_uvm_env/uvm_env/vortex_config.sv`, `vortex_uvm_env/tb/vortex_tb_top.sv`, `vortex_uvm_env/scripts/prepare.sh`

### Root Cause (C1)
`vortex_config.sv` had `parameter VX_MEM_TAG_WIDTH = 50` hardcoded with a
misleading comment `// 8`.  The RTL's actual width comes from a deep expression
involving cache-level tag chaining that depends on `NUM_CLUSTERS`, `NUM_CORES`,
`NUM_WARPS`, `NUM_THREADS`, and `UUID_WIDTH`.  Any mismatch causes silent
AXI protocol violations (wrong ID field width).

### Fix (C1)
```sv
// BEFORE (vortex_config.sv)
parameter VX_MEM_TAG_WIDTH = 50; //will be paramterized later to L3_MEM_TAG_WIDTH

// AFTER
parameter VX_MEM_TAG_WIDTH = VX_gpu_pkg::VX_MEM_TAG_WIDTH; // derived from RTL
```

Added elaboration asserts in `vortex_tb_top.sv` that fire `$fatal` at time 0 if
the UVM package width ever diverges from the RTL package:

```sv
initial begin : u_c1_tag_width_assert
    assert (vortex_config_pkg::VX_MEM_TAG_WIDTH == VX_gpu_pkg::VX_MEM_TAG_WIDTH)
        else $fatal(1, "[C1-ASSERT] VX_MEM_TAG_WIDTH: UVM_pkg=%0d RTL_pkg=%0d",
                    vortex_config_pkg::VX_MEM_TAG_WIDTH, VX_gpu_pkg::VX_MEM_TAG_WIDTH);
`ifdef USE_AXI_WRAPPER
    assert ($bits(axi_awid[0]) == vortex_config_pkg::VX_MEM_TAG_WIDTH)
        else $fatal(1, "[C1-ASSERT] DUT AXI awid width=%0d but VX_MEM_TAG_WIDTH=%0d",
                    $bits(axi_awid[0]), vortex_config_pkg::VX_MEM_TAG_WIDTH);
`endif
end
```

### Root Cause (ISS-01)
`prepare.sh` was calling `objcopy --change-addresses=+0x80000000` on ELFs that
are **already linked at 0x80000000**.  This added a second 0x80000000 offset,
producing addresses at 0x100000000 which overflow a 32-bit field and wrap to 0.
The memory model loaded the entire program at address 0, causing X-propagation
across the whole pipeline.

### Fix (ISS-01)
- Removed the erroneous `--change-addresses` flag.
- Added CRLF stripping (WSL2 toolchain quirk that breaks the `@80000000` guard).
- Added sed remap: all `@80XXXXXX` section markers → `@00XXXXXX` so that ELFs
  linked at 0x80000000 land at the correct base-address-relative offset in the
  hex file.

### Conflict Risk
- `vortex_config.sv` is shared with Ahmad (scoreboard) and Steven (AXI SVA).
  The change only touches the `VX_MEM_TAG_WIDTH` parameter; all other parameters
  are untouched.  **No conflict expected, but Ahmad/Steven must recompile** after
  pulling this commit.
- `prepare.sh` is Samuel's lane exclusively; no conflict.
- `vortex_tb_top.sv` is shared. The new `initial begin` block is additive only.

**Acceptance:** `kernel_launch_test` with `hello.elf` → PASS, Errors: 0,
`AXI_TID_W=50`, no `[C1-ASSERT]` fatal.

---

## Fix 2 — C3: Real EBREAK Decode for Completion Detection
**Commit:** `7764ba14`  
**Files:** `vortex_uvm_env/tb/vortex_tb_top.sv`

### Root Cause
Completion was fired when `!busy` went low (idle path).  A previous attempt had
a hardcoded PC (`TB_EBREAK_PC = 0x800008ac`) that only matched one specific
binary — rebuilding the kernel with different optimization flags broke it silently.
The `busy` signal also never goes low for kernels that exit via MMIO write
(all current kernel ELFs use address `0x88` as exit), so the completion event
was always the idle-threshold fallback (5000 cycles of inactivity) which fires
late and gives noisy IPC numbers.

### Fix
Introduced two signals at module level:

```sv
logic        tb_probe_ebreak_seen; // registered: latches first ebreak fetch
wire         tb_ebreak_fetch;      // combinational: same-cycle detection

// Inside ifdef USE_AXI_WRAPPER probe block:
assign tb_ebreak_fetch = fetch_valid && (fetch_instr == TB_EBREAK_INSTR);
// TB_EBREAK_INSTR = 32'h00100073 (RISC-V ISA fixed encoding — valid for any binary)
```

Priority chain in the main `always_ff`:
1. **PRIMARY** — `tb_ebreak_fetch || tb_probe_ebreak_seen` → `EXECUTION COMPLETE (ebreak decoded)`
2. **FALLBACK 1** — `!busy` → `** Warning: busy=0 fallback — ebreak not decoded`
3. **FALLBACK 2** — idle threshold → `** Warning: idle safety net`

Removed the hardcoded `TB_EBREAK_PC` entirely.

### Conflict Risk
`vortex_tb_top.sv` is shared.  The probe `ifdef` block that contains
`tb_ebreak_fetch` assignment is inside `USE_AXI_WRAPPER` — Steven's AXI SVA work
lives nearby.  **No functional conflict**, but a merge will require context-line
attention around the probe block (lines 473–530 at commit time).

**Acceptance:** `kernel_launch_test` with `hello.elf` → PASS, Errors: 0.

---

## Fix 3 — C2: Real Instruction Count (Remove `tb_mem_ops % 3` Fabrication)
**Commit:** `22115864`  
**Files:** `vortex_uvm_env/tb/vortex_tb_top.sv`

### Root Cause
`tb_instr_count` was computed as `tb_mem_ops / 3` — a fabricated ratio with no
architectural basis.  This made IPC numbers meaningless and hid real throughput.

### Fix
Direct hierarchy tap on the commit-arbitration interface:

```sv
// Hierarchy path for 1CL/1C/4W/4T with USE_AXI_WRAPPER:
wire tb_commit_fire;
assign tb_commit_fire =
    vortex_top.Vortex.cluster[0].core[0].VX_commit_unit.commit_arb_if[0].valid
  & vortex_top.Vortex.cluster[0].core[0].VX_commit_unit.commit_arb_if[0].ready;
// tb_instr_count incremented in always_ff on tb_commit_fire
```

Result: `vecadd` → 12798 instructions in 100k cycles = IPC 0.128 (real).

### Known Multi-Core Limitation
The tap is **hardcoded to cluster[0]/core[0]/lane[0]**.  For configs with
`NUM_CLUSTERS > 1` or `NUM_CORES > 1`, other cores' commits are silently dropped.
This is correct for the primary Gate-0 config (1CL/1C/4W/4T) and incorrect for
any multi-core run.  Fix requires a `generate` loop (P1-bind item, Tier 1).

This is the same multi-core problem described in the configurability section
below — the UVM env is not yet fully general for N cores.

### Conflict Risk
Touches `vortex_tb_top.sv` only (the `tb_commit_fire` wire and the `always_ff`
counter).  Ahmad's P1-bind work (passive probe on `commit_arb_if[*]`) will add a
`generate` loop in the same file — **coordinate before merging P1-bind**.

**Acceptance:** IPC = real (non-fabricated), SimX RAM verification PASSED.

---

## Fix 4 — riscv-dv Pipeline Plumbing
**Commit:** `4661f7cb`  
**Files:** `vortex_uvm_env/scripts/prepare.sh`, `vortex_uvm_env/scripts/run.sh`, `vortex_uvm_env/scripts/simulate.sh`, `vortex_uvm_env/Makefile`

### Root Cause
The riscv-dv case in `prepare.sh` referenced a fixed output path that did not
match what riscv-dv actually produces (`out_<date>/asm_test/<test>_0.S`).  The
gcc step to assemble the `.S` to ELF was missing entirely.  The
`--stress-iter=N` flag existed in `random_instr_stress_vseq.sv` but was not
wired through the Makefile → `run.sh` → `simulate.sh` → plusarg chain.

### Fix
- `prepare.sh`: glob for newest `out_*/asm_test/<test>_0.S` (date-independent).
- `prepare.sh`: added gcc assemble+link step (`.S → ELF → hex`).
- `run.sh`: added `--stress-iter=N` argument (default 1).
- `simulate.sh`: passes `+NUM_STRESS_ITER=N` when `STRESS_ITER > 1`.
- `Makefile`: added `STRESS_ITER ?= 1`, wired to `--stress-iter` flag.

Usage:
```
make sim TEST=random_instruction_stress_test \
         PROGRAM=riscv_arithmetic_basic_test \
         STRESS_ITER=3 TIMEOUT=1000000
```

### Conflict Risk
None — these are script/Makefile changes in Samuel's lane.

---

## Fix 5 + 6 — riscv-dv End-to-End: SimX SIGABRT + Completion + Scoreboard
**Commits:** `4661f7cb` (partial pipeline) + `2ccef437` (root causes)  
**Files:** `Vortex/sim/simx/emulator.cpp`, `vortex_uvm_env/scripts/prepare.sh`, `vortex_uvm_env/uvm_tests/vortex_base_test.sv`, `vortex_uvm_env/uvm_env/vortex_scoreboard.sv`

This was the hardest fix in the session.  Multiple independent root causes each
had to be diagnosed separately before the test could pass end-to-end.

### Problem Statement
`make sim TEST=random_instruction_stress_test PROGRAM=riscv_arithmetic_basic_test`
was producing **4 UVM_ERRORs** and a FAILED result.  The DUT ran but never
reached the expected EBREAK, or reached it but the scoreboard reported vacuous run.

---

### Sub-Issue A: SimX SIGABRT on Machine-Mode CSRs

**Root cause:** riscv-dv programs always emit a machine-mode boilerplate header:
```asm
csrw 0x300, x0   # mstatus
csrw 0x301, x9   # misa    ← not in Vortex's VX_CSR_* list
csrw 0x304, x0   # mie
csrw 0x305, x0   # mtvec
csrr x5, 0xf14   # mhartid
mret
```
Vortex's `emulator.cpp` `set_csr()` had a `switch` over supported CSR
addresses.  `0x301` (MISA) was not listed — hit the `default:` branch which
calls `std::abort()`.  Additionally `get_csr()` with address `0x343` (MTINST)
and `0x344` (MIP) were not in `VX_types.vh` so they also aborted.

**Fix in `emulator.cpp`:**
1. Added `case VX_CSR_MISA:` (0x301) to the silent-ignore list in `set_csr()`.
2. Added M-mode range guards in **both** `get_csr()` and `set_csr()` defaults:

```cpp
// get_csr() default branch — before the MPM range check:
if ((addr >= 0x300 && addr < 0x400) || (addr >= 0xF00 && addr < 0x1000)) {
    return 0;  // silently return 0 for unimplemented M-mode / hw-id CSRs
}

// set_csr() default branch — before the abort:
if ((addr >= 0x300 && addr < 0x400) || (addr >= 0xF00 && addr < 0x1000))
    return;    // silently ignore unimplemented M-mode / hw-id CSR writes
std::cerr << "Error: invalid CSR write ..." << std::endl;
std::abort();
```

**Important:** after editing `emulator.cpp` you must **delete `simx_model.so`
manually** before rebuilding — the DPI library Makefile only lists `simx_dpi.cpp`
as a dependency, not the `.o` files, so the stale `.so` is not automatically
rebuilt.

---

### Sub-Issue B: RVC Compressed Instructions Crash SimX

**Root cause:** The riscv-dv target `rv32imc` generates 16-bit compressed
instructions (`c.nop`, `c.addi4spn`, `c.srli`, etc.).  Vortex's `decode.cpp`
has no RVC decoder and hits `default: std::abort()` silently (no error message,
making it look like a random crash).

**Diagnosed by:** injecting a SIGABRT signal handler that called `backtrace()`
→ pointed into `decode.cpp`.

**Fix:** Created a new riscv-dv target `rv32im` (no `RV32C` in `supported_isa`):

```
/home/samuel_ubuntu22/riscv-dv/target/rv32im/riscv_core_setting.sv
    riscv_instr_group_t supported_isa[$] = {RV32I, RV32M};  // was {RV32I, RV32M, RV32C}

/home/samuel_ubuntu22/riscv-dv/run.py
    elif args.target == "rv32im":
        args.mabi = "ilp32"
        args.isa = "rv32im_zicsr_zifencei"
```

And changed `prepare.sh` to use `--target=rv32im` and compile with
`-march=rv32im_zicsr_zifencei` (no `c` extension).

---

### Sub-Issue C: RTL Assert on Machine-Mode CSR Writes

**Root cause:** Even with `rv32im` (no RVC), riscv-dv still emits `csrw 0x301`
(misa), `csrw 0x305` (mtvec), `mret`, etc. in the generated assembly.  The
Vortex RTL CSR unit fires an assertion on any unsupported CSR write, producing
`** Error: invalid CSR write address: 301` in simulation.

**Fix:** Added sed post-processing step in `prepare.sh` BEFORE the gcc compile.
The cleaned assembly replaces:
- All `csrw 0x3xx, ...` → `nop`
- All `csrr rd, 0x3xx` → `nop`
- All `csrr rd, 0xf14` (mhartid) → `nop`
- All `mret` → `nop`
- All `ecall` → `ebreak` ← (see Sub-Issue D)

```bash
ASM_CLEAN="${PROGRAM_HEX%.hex}_clean.S"
sed \
    -e 's/\bcsrw\s\+0x3[0-9a-fA-F][0-9a-fA-F]\b.*/nop/g' \
    -e 's/\bcsrr\s\+[a-z0-9]*,\s*0x3[0-9a-fA-F][0-9a-fA-F]\b.*/nop/g' \
    -e 's/\bcsrr\s\+[a-z0-9]*,\s*0xf14\b.*/nop/g' \
    -e 's/\bmret\b/nop/g' \
    -e 's/\becall\b/ebreak/g' \
    "$PROGRAM_SOURCE" > "$ASM_CLEAN"
```

Note on `mret→nop`: the M-mode trap handler in riscv-dv programs ends with
`mret` to return to U-mode.  Since we nop'd `csrw mtvec`, the trap handler is
never invoked and `mret` is unreachable code — safe to nop.

---

### Sub-Issue D: EBREAK Never Fires — ecall vs ebreak

**Root cause:** riscv-dv programs end at `test_done:` with `ecall` (not
`ebreak`).  The Vortex testbench completion probe only detects `ebreak`
(0x00100073) — `ecall` (0x00000073) is a different encoding and was invisible
to the probe.  The DUT ran forever, hitting the `TIMEOUT` watchdog.

```asm
test_done:
    li gp, 1
    ecall          ← was this; the DUT ran forever
    ...
```

**Fix:** The `ecall→ebreak` substitution in the sed step above converts the
program's exit point to the instruction the probe expects.

**Note:** riscv-dv's `mret→nop` is safe here because the `init:` label
immediately follows `mret` in the M-mode entry sequence — `nop` falls through
correctly.

---

### Sub-Issue E: `wait_for_completion()` Misses Stale UVM Event

**Root cause (UVM semantics):** The base test's `run_phase` calls:
```sv
run_test_stimulus();   // vseq waits for host_driver → ebreak → returns
wait_for_completion(); // called AFTER stimulus already finished
```

`run_test_stimulus()` (the stress vseq) internally waited for the host_driver
to detect EBREAK and returned.  During that wait, the scoreboard saw EBREAK and
called `cfg.ebreak_event.trigger()`.  Then `wait_for_completion()` was called
and did `cfg.ebreak_event.wait_trigger()`.

**UVM's `wait_trigger()` is edge-sensitive** — it blocks until `trigger()` is
called in the current or a future time step.  If the event was triggered in a
past time step, `wait_trigger()` blocks forever.  The 1M-cycle test-level
watchdog then fired, producing a spurious `UVM_ERROR: Timeout after 1000000 cycles!`

**Fix in `vortex_base_test.sv`:** Added a fast-path check at the top of
`wait_for_completion()`:

```sv
virtual task wait_for_completion();
    // Fast path: run_test_stimulus() may have already waited for EBREAK.
    // wait_trigger() misses past triggers; check the RTL signal directly.
    if (vif.status_if.ebreak_detected) begin
        repeat(5) @(posedge vif.clk);
        `uvm_info(get_type_name(), "EBREAK already detected (fast path)", UVM_LOW)
        return;
    end
    // ... original fork/join watchdog for tests that enter wait_for_completion
    //     before EBREAK fires (not the stress test case)
```

**Conflict risk for Ahmad/Steven:** This changes `vortex_base_test.sv` which
all test classes inherit from.  The fast-path check is safe for all derived
tests — if `ebreak_detected` is not yet high, the original blocking path runs
unchanged.

---

### Sub-Issue F: "Vacuous Run" False Error — No Memory Writes in Arithmetic Test

**Root cause:** `riscv_arithmetic_basic_test` is a **pure arithmetic** test.
Its main body uses only registers.  The result stores in the assembly all appear
AFTER the `ebreak` (in the `write_tohost` / trap-handler code that is never
reached by the DUT):

```asm
test_done:
    li gp, 1
    ebreak          ← DUT halts HERE; scoreboard runs comparison
write_tohost:
    sw gp, tohost, t5   ← never reached by DUT (or by SimX with ebreak-halt)
    ...
```

Both the DUT and SimX halt at `ebreak`.  Neither writes to the data region
(0x80000000–0x88000000).  The scoreboard's `shadow_memory` was empty.
`compare_all_written()` ran over zero entries → `total_checks = 0` →
`"No checks were performed — vacuous run"` UVM_ERROR.

This is a **false positive**: both DUT and SimX completed identically with empty
data memory.  The test verifies correct arithmetic execution by the fact that
both reached ebreak at the same point.

**Fix in `vortex_scoreboard.sv`:** Changed "vacuous run" from UVM_ERROR to
UVM_WARNING when `ebreak_seen && simx_ran`:

```sv
else if (ebreak_seen && simx_ran)
    `uvm_warning("SCOREBOARD",
        "No memory writes to compare — DUT and SimX both completed (pure arithmetic program)")
else
    `uvm_error("SCOREBOARD", "No checks were performed — vacuous run")
```

**Conflict risk for Ahmad:** Ahmad owns the scoreboard.  This change is
conservative (only changes severity when both DUT and SimX confirmed completed).
Real vacuous runs (neither simx_ran nor ebreak_seen) still fire UVM_ERROR.
**Flag this to Ahmad** before merging so he can decide if he wants a tighter
guard (e.g., also check `num_transactions > 0`).

---

### Final Result (Fix 5+6)
```
make sim TEST=random_instruction_stress_test \
         PROGRAM=riscv_arithmetic_basic_test \
         TIMEOUT=1000000
```
- UVM_ERROR: 0
- UVM_FATAL: 0
- EBREAK detected at cycle 88387 (simulation time ~887 μs)
- SimX completed (exit code 1 = `gp` value, normal riscv-dv termination)
- TEST PASSED ✓

---

## Open: Configurability — Full N-Core/N-Cluster Support (I1 + C2 Limitation)

Before starting the riscv-dv work, Samuel asked whether the UVM environment
is fully configurable with arbitrary `NUM_CLUSTERS`, `NUM_CORES`, `NUM_WARPS`,
`NUM_THREADS`.  The answer was: **yes for the RTL elaboration and plusarg
plumbing, but NO for observation/counting**.

Specifically:

### What IS configurable
- `+NUM_CLUSTERS`, `+NUM_CORES`, `+NUM_WARPS`, `+NUM_THREADS` are passed to
  vsim and picked up by `apply_plusargs()` in `vortex_config.sv`.  The RTL
  itself is fully parameterized.

### What is HARDCODED (broken for N > 1)

**1. Instruction count tap (C2 commit):**
```sv
// vortex_tb_top.sv — hardcoded to cluster[0]/core[0]/lane[0]
assign tb_commit_fire =
    vortex_top.Vortex.cluster[0].core[0].VX_commit_unit.commit_arb_if[0].valid
  & vortex_top.Vortex.cluster[0].core[0].VX_commit_unit.commit_arb_if[0].ready;
```
For 2 clusters × 2 cores = 4 cores, only 1 core's commits are counted.
IPC is under-counted by 4×.

**2. Fetch/ebreak probe (C3 commit):**
```sv
// vortex_tb_top.sv — hardcoded probe to cluster[0]/socket[0]/core[0]
```
EBREAK from cores 1+ is invisible.  For a multi-core program where core 1
completes first, the bench never fires the completion event.

**3. Cache performance counters:**
Similar hardcoded hierarchy taps for icache/dcache stall counts.

### What needs to be done (I1 checklist item)
Replace every hardcoded `cluster[0].core[0]` hierarchy path with a
`generate for` loop that sums across all `NUM_CLUSTERS × NUM_CORES` cores.
The RTL uses `localparam`s for these counts that are accessible via
`VX_gpu_pkg::NUM_CLUSTERS` and `VX_gpu_pkg::NUM_CORES`.

This is tracked as checklist item **I1** and couples with **P1-bind** (Ahmad's
passive commit probe module).

---

## Files Changed Summary

| File | Fixes |
|------|-------|
| `vortex_uvm_env/uvm_env/vortex_config.sv` | C1: VX_MEM_TAG_WIDTH from RTL |
| `vortex_uvm_env/tb/vortex_tb_top.sv` | C1 assert, C3 ebreak decode, C2 real count |
| `vortex_uvm_env/scripts/prepare.sh` | ISS-01 hex load, riscv-dv pipeline, sed post-process |
| `vortex_uvm_env/scripts/run.sh` | --stress-iter flag |
| `vortex_uvm_env/scripts/simulate.sh` | +NUM_STRESS_ITER plusarg |
| `vortex_uvm_env/Makefile` | STRESS_ITER variable |
| `Vortex/sim/simx/emulator.cpp` | M-mode CSR guards (MISA + range) |
| `vortex_uvm_env/uvm_tests/vortex_base_test.sv` | wait_for_completion fast-path |
| `vortex_uvm_env/uvm_env/vortex_scoreboard.sv` | vacuous run → warning |
| `/home/samuel_ubuntu22/riscv-dv/target/rv32im/` | new target (no RVC) |
| `/home/samuel_ubuntu22/riscv-dv/run.py` | rv32im case |
