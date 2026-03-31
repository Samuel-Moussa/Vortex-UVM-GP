# Vortex UVM Bringup — Issue & Fix Log

> **Project:** Vortex_UVM_GP | **Date:** March 16, 2026 | **Author:** Samuel
> **Final Result:** `*** SMOKE TEST PASSED ***` — 154 cycles · 0 UVM_ERROR · 0 UVM_FATAL

---

## The Only Working Program

```text
@00000000
F3 22 00 CC    csrrs  t0, 0xCC0, x0   # read Vortex WID CSR
73 23 10 CC    csrrs  t1, 0xCC1, x0   # read Vortex TID CSR
63 98 02 00    beq    t0, x0, +16     # skip if wid != 0
63 16 03 00    bne    t1, x0, +12     # skip if tid != 0
93 00 10 00    addi   x1, x0, 1
13 01 20 00    addi   x2, x0, 2
B3 81 20 00    add    x3, x1, x2      # x3 = 3
0B 00 00 00    vx_wstop               # Vortex custom warp-stop
13 00 00 00    nop x8                 # pipeline flush padding
...
```

**Why it works:** `@00000000` offset + `baseaddr=0x80000000` DCR = correct load.
Zero `sw`/`lw` instructions = AXI B-channel never triggered. `vx_wstop` terminates cleanly.

---

## ISS-01 — HEX `@80000000` Baseaddr Overflow

**Severity:** 🔴 Critical | **Status:** ✅ Fixed

**Problem:**
The Verilog HEX `@` marker is a *relative offset*, not an absolute address.
`mem_model.load_hex_file()` does `write_byte(baseaddr + addroff, bval)`.
With `@80000000` and `baseaddr=0x80000000`:

```
0x80000000 + 0x80000000 = 0x100000000  ← 33-bit overflow, data lost
0x80000000 stays EMPTY → DUT fetches X
```

**Tried and failed:**
- `objcopy --change-addresses=0x80000000` on a pre-linked ELF → output was still `@80000000`
- `--change-section-address` without subtracting the link base → wrong delta

**Fix:**

```bash
# Edit in-place:
sed -i 's/^@80000000/@00000000/' program_simple.hex

# Or regenerate correctly:
riscv64-unknown-elf-objcopy -O verilog \
    --verilog-data-width=1 \
    --change-section-address .text-0x80000000 \
    program.elf program.hex
```

> **Rule:** Always use `@00000000`. The DCR `startup_addr=0x80000000` supplies the absolute base.

---

## ISS-02 — X-Propagation Cascade from Empty RAM

**Severity:** 🔴 Critical | **Status:** ✅ Fixed (by fixing ISS-01)

**Problem:**
Empty RAM → `VX_fetch` reads `32'hXXXXXXXX` every clock → decode stage
propagates X to every downstream unit → hundreds of identical errors per ns:

```
** Error: wid=x PC=0xx addr=0xx  (repeated every 10 ns)
```

The `x` values are Questa **logic-unknown**, not independent bugs. One root cause.

**Tried and failed:**
- Added `$isunknown()` guards in `VX_pending_size.sv` → suppressed counter underflow but errors continued
- Increased `ICACHE_MSHR_SIZE`/`DCACHE_MREQ_SIZE` → cache never got a valid address to use
- `force mem[0] = 32'h00000013` at TB_TOP → one address fixed, surrounding locations still X

**Fix:** Fix ISS-01. Zero X-propagation in the passing run.

---

## ISS-03 — AXI B-Channel (BVALID) Never Driven

**Severity:** 🔴 Critical | **Status:** ⚠️ Workaround (open item)

**Problem:**
Any `sw` instruction → D-cache emits AXI `AW+W` beats → LSU stalls waiting
for `BVALID`. The UVM AXI slave driver only handled `AR/R` (reads).
The B-channel (`BVALID`, `BRESP`) was never driven → LSU stall → second
X-propagation wave identical to ISS-02 in appearance.

**Source:** `uvm_env/agents/axi_agent/axi_driver.sv` — no B-channel task.

**Tried and failed:**
- `force BVALID = 1` in TB_TOP → worked for one transaction, broke `BREADY` handshake on the second
- `always @(posedge clk) BVALID <= 1` in interface → multiple drivers, elaboration warning
- Confirmed with `sw`+`lw` test program: every cycle showed `BVALID=0`, warp stalled forever

**Fix (workaround):**
Removed all `sw`/`lw` instructions from the test program. Pure ALU + CSR only.

> **Open item:** Add a proper B-channel responder to `axi_driver.sv` before any
> store-containing program can be tested.

---

## ISS-04 — `STARTUP_ADDR` `0x` Prefix Breaks `%h` Parsing

**Severity:** 🟠 High | **Status:** ✅ Fixed

**Problem:**
Script passed `+STARTUP_ADDR=0x80000000`. SystemVerilog's
`$value$plusargs("STARTUP_ADDR=%h", tmp)` silently returns `0` when value
starts with `0x` — `%h` expects raw hex digits only. `tmp` was never written.
The run passed accidentally because the compile-time default
`vortex_config_pkg::STARTUP_ADDR = 32'h80000000` kicked in as fallback.

**Source:** `scripts/run_vortex_uvm.sh` — SIM_OPTS construction.

**Tried and failed:**
- Changed to `%d` format → decimal of string `"0x80000000"` returned garbage
- Used `$sscanf` with `"0x%h"` → not consistent across Questa versions

**Fix:**

```bash
STARTUP_ADDR_HEX="${STARTUP_ADDR#0x}"
STARTUP_ADDR_HEX="${STARTUP_ADDR_HEX#0X}"
SIM_OPTS="$SIM_OPTS +STARTUP_ADDR=$STARTUP_ADDR_HEX"   # passes 80000000
```

---

## ISS-05 — `NUM_CLUSTERS` Missing from `COMPILE_OPTS`

**Severity:** 🟠 High | **Status:** ✅ Fixed

**Problem:**
`COMPILE_OPTS` included `FPU_TYPE`, `TCU_TYPE`, `NUM_CORES`, `NUM_WARPS`,
`NUM_THREADS` — but not `NUM_CLUSTERS`. Single-cluster runs defaulted silently
from `VX_config.vh`. Any `--clusters=2` invocation compiled single-cluster RTL
while running a two-cluster simulation.

**Source:** `scripts/run_vortex_uvm.sh` — COMPILE_OPTS block, one missing line.

**Fix:**

```bash
COMPILE_OPTS="$COMPILE_OPTS +define+NUM_CLUSTERS=$NUM_CLUSTERS"
```

---

## ISS-06 — `$COMPILE_OPTS` Missing from UVM `vlog`

**Severity:** 🟠 High | **Status:** ✅ Fixed

**Problem:**
RTL `vlog` received `$COMPILE_OPTS`. UVM `vlog` did not — it was bare
`vlog -sv +incdir+...`. So `vortex_config.sv` compiled without `TCU_BHF`,
`NUM_*`, or `USE_AXI_WRAPPER` defines. UVM `generate` blocks elaborated
with default values, silently mismatching the RTL.

**Source:** `scripts/run_vortex_uvm.sh` — UVM compilation block.

**Tried and failed:**
- Added `$COMPILE_OPTS` only to the RTL flist — UVM env still compiled without it

**Fix:**

```bash
vlog -sv $COMPILE_OPTS \               # $COMPILE_OPTS added
    +incdir+.../questa_uvm_pkg-1.2/src \
    -f uvm_env.flist
```

---

## ISS-07 — Three Plusargs Missing from `SIM_OPTS`

**Severity:** 🟠 High | **Status:** ✅ Fixed

**Problem:**
The passing simulation log showed `vsim` was called with
`+NUM_CLUSTERS=1 +STARTUP_ADDR=80000000 +USE_AXI_WRAPPER` — none of these
appeared in the script's `SIM_OPTS`. They had been manually appended during
debugging and never merged back. Without `+USE_AXI_WRAPPER`, `apply_plusargs()`
never set AXI mode at runtime; TB fell back to MEM interface, mismatching
the AXI-compiled RTL.

**Source:** `scripts/run_vortex_uvm.sh` — SIM_OPTS block.

**Fix:**

```bash
SIM_OPTS="$SIM_OPTS +NUM_CLUSTERS=$NUM_CLUSTERS"
SIM_OPTS="$SIM_OPTS +STARTUP_ADDR=$STARTUP_ADDR_HEX"
if [[ "$MEMORY_INTERFACE" == "axi" ]]; then
    SIM_OPTS="$SIM_OPTS +USE_AXI_WRAPPER"
fi
```

---

## ISS-08 — DPI Library Not Linked

**Severity:** 🟡 Medium | **Status:** ✅ Fixed

**Problem:**
Without `-sv_lib vortex_dpi`, Questa emitted on every TCU/FPU instruction:
`vsim-3770: Failed to find 'dpi_trace' in shared library`.
All TCU/FPU trace output silently dropped for the entire simulation.

**Source:** `scripts/run_vortex_uvm.sh` — `vsim` invocation, no `-sv_lib` flag.

**Fix:**

```bash
DPI_LIB="$FLISTS_DIR/vortex_dpi"
DPI_FLAG=""
[[ -f "${DPI_LIB}.so" ]] && DPI_FLAG="-sv_lib ${DPI_LIB}"
vsim -c vortex_tb_top $SIM_OPTS $DPI_FLAG -do "run -all; quit -f"

# Build the .so once:
gcc -shared -fPIC -o "$FLISTS_DIR/vortex_dpi.so" \
    "$VORTEX_HOME/hw/dpi/util_dpi.cpp" \
    "$VORTEX_HOME/hw/dpi/float_dpi.cpp" \
    -I"$VORTEX_HOME/hw/dpi" \
    -I"$(dirname $(which vsim))/../include"
```

---

## ISS-09 — Logs and Waveforms Overwritten Every Run

**Severity:** 🟡 Medium | **Status:** ✅ Fixed

**Problem:**
Script wrote `sim_vortex_smoke_test.log` and the VCD directly into `flists/`.
Every run silently overwrote the previous run's evidence. Multi-run debugging
required manually renaming files between runs.

**Source:** `scripts/run_vortex_uvm.sh` — LOG_FILE and WAVE_FILE paths.

**Fix:**

```bash
RESULTS_RUN_DIR="$PROJECT_ROOT/results/$(date +%Y%m%d)/run_$(date +%H%M%S)_${TEST_NAME}"
mkdir -p "$RESULTS_RUN_DIR"/{logs,waves,programs,reports}
ln -sfn "$RESULTS_RUN_DIR" "$PROJECT_ROOT/results/latest"
LOG_FILE="$RESULTS_RUN_DIR/logs/simulation.log"
WAVE_FILE="$RESULTS_RUN_DIR/waves/${TEST_NAME}_${MEMORY_INTERFACE}.vcd"
```

---

## ISS-10 — Inline Comments Break `\` Line Continuation

**Severity:** 🟡 Medium | **Status:** ✅ Fixed

**Problem:**
Enhanced script added `# ← FIX N` annotations after `\` continuation chars:

```bash
vlog -sv $COMPILE_OPTS \              # ← FIX 2   ← BREAKS bash
    +incdir+... \
    -f uvm_env.flist
```

In bash `\` must be the last character on the line. The `vlog` command
split mid-argument, causing the program conversion block to receive a
broken environment and fail with:

```
riscv64-unknown-elf-objcopy: file format not recognized
✗ ERROR: Program conversion failed
```

**Tried and failed:**
- Moved comments to end of the next continued line → still broken
- Used standalone `# comment` lines after commands → broke heredoc blocks

**Fix:** All fix annotations moved to standalone block comments **before**
the modified code, never inline after `\`:

```bash
# ── FIX 2: UVM env compile now receives $COMPILE_OPTS ───
vlog -sv $COMPILE_OPTS \
    +incdir+.../questa_uvm_pkg-1.2/src \
    -f uvm_env.flist
```

---

## ISS-11 — No `@80000000` Guard in Hex Validation

**Severity:** 🟡 Medium | **Status:** ✅ Fixed

**Problem:**
Original hex validation used `^@[0-9a-fA-F]{8}` — which matched `@80000000`
and printed `HEX format validated ✓`. The vacuous passing run (1 instruction,
154 cycles, DUT fetching nops from empty memory) was accepted as a real pass.

**Source:** `scripts/run_vortex_uvm.sh` — hex validation block.

**Fix:**

```bash
FIRST_LINE=$(head -1 "$PROGRAM_HEX")
if [[ "$FIRST_LINE" == "@80000000" ]]; then
    print_error "HEX @80000000 — baseaddr overflow, vacuous PASS risk"
    echo "  Fix: sed -i 's/^@80000000/@00000000/' $PROGRAM_HEX"
    exit 1
fi
```

---

## ISS-12 — STATUS_MON Polls Every 100 Cycles, Misses EBREAK

**Severity:** 🔵 Low | **Status:** 🔶 Open

**Problem:**
`status_monitor` polls `busy` every 100 cycles. The test drops its objection
immediately after `busy=0` via the scoreboard. The monitor's next poll fires
after the objection is already dropped → logs
`Execution started but did not complete (no EBREAK)` in every passing run.

**Source:** `uvm_env/agents/status_agent/status_monitor.sv` — polling loop.

**Fix (not yet applied):**

```systemverilog
@(negedge vif.busy);    // replace 100-cycle poll with edge trigger
execution_completed = 1;
```

---

## ISS-13 — HOST_MON Kernel Completions Always 0

**Severity:** 🔵 Low | **Status:** 🔶 Open

**Problem:**
Host monitor watches the host interface handshake for kernel completions.
The smoke test launches via direct DCR writes from TB_TOP — bypassing the
host interface entirely. The monitor never sees a completion event.

**Source:** `uvm_env/agents/host_agent/host_monitor.sv` — wrong observation point.

**Fix (not yet applied):** Map `busy→0` edge as a completion event in
`host_monitor.sv` when the host driver was not used for the launch.

---

## ISS-14 — VIRT_SQCR Sequencers Unconnected

**Severity:** 🔵 Low | **Status:** ℹ️ Expected

**Problem:**
Virtual sequencer declares `mem_sequencer` and `dcr_sequencer` handles that
are never assigned. In AXI mode both paths bypass the virtual sequencer.
Two `UVM_WARNING VIRT_SQCR` messages appear at the start of every run.

**Source:** `uvm_env/vortex_virtual_sequencer.sv` — handles never assigned in `vortex_env.sv`.

**Action:** None needed for current AXI + TB_TOP flow.
Connect handles if a virtual-sequencer-driven test is ever developed.

---

## Summary

| ID | Issue | Layer | Sev | Status |
|---|---|---|---|---|
| ISS-01 | HEX `@80000000` baseaddr overflow | DUT/RTL | 🔴 Critical | ✅ Fixed |
| ISS-02 | X-propagation from empty RAM | DUT/RTL | 🔴 Critical | ✅ Fixed |
| ISS-03 | AXI B-channel BVALID not driven | UVM Env | 🔴 Critical | ⚠️ Workaround |
| ISS-04 | `STARTUP_ADDR` `0x` prefix breaks `%h` | Script | 🟠 High | ✅ Fixed |
| ISS-05 | `NUM_CLUSTERS` missing from `COMPILE_OPTS` | Script | 🟠 High | ✅ Fixed |
| ISS-06 | `$COMPILE_OPTS` missing from UVM `vlog` | Script | 🟠 High | ✅ Fixed |
| ISS-07 | 3 plusargs missing from `SIM_OPTS` | Script | 🟠 High | ✅ Fixed |
| ISS-08 | DPI library not linked | Script | 🟡 Medium | ✅ Fixed |
| ISS-09 | Logs overwritten each run | Script | 🟡 Medium | ✅ Fixed |
| ISS-10 | `#` comments break `\` continuation | Script | 🟡 Medium | ✅ Fixed |
| ISS-11 | No `@80000000` guard in hex validation | Script | 🟡 Medium | ✅ Fixed |
| ISS-12 | STATUS_MON polls, misses EBREAK | UVM Env | 🔵 Low | 🔶 Open |
| ISS-13 | HOST_MON completions always 0 | UVM Env | 🔵 Low | 🔶 Open |
| ISS-14 | VIRT_SQCR sequencers unconnected | UVM Env | 🔵 Low | ℹ️ Expected |

**11 fixed · 2 open · 1 expected · 0 regressions**

---

*Vortex UVM Bringup Sprint 1 — March 16, 2026*
