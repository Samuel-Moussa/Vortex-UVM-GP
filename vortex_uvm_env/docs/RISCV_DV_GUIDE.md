# riscv-dv Setup & Usage Guide

How to install the **riscv-dv** constrained-random generator, point our project at
it, and run randomized instruction tests against the Vortex DUT (compared to SimX).

> [!NOTE]
> You only do **Part 1 (install)** once per machine. After that, running a
> randomized test is a single `make` command — the whole generate → sanitize →
> compile → hex → simulate pipeline is automated by `scripts/prepare.sh`.

---

## Prerequisites

Already required for the normal UVM flow, so you likely have them:

- **QuestaSim 2021.2_1** (on `PATH`, `vsim` works)
- **RISC-V toolchain** — `riscv64-unknown-elf-gcc` / `-objcopy` on `PATH`
  (check: `riscv64-unknown-elf-gcc --version`)
- **Python 3** with `pip3`

---

## Part 1 — Install riscv-dv (one time)

```bash
# 1. Clone the ChipsAlliance generator (default location our scripts look for)
git clone https://github.com/chipsalliance/riscv-dv.git ~/riscv-dv

# 2. Install its Python dependencies
cd ~/riscv-dv
pip3 install -r requirements.txt

# 3. Smoke-test the generator (rv32im, no compressed instrs — matches our DUT)
python3 run.py --test=riscv_arithmetic_basic_test \
               --simulator=questa --target=rv32im \
               --iterations=1 --steps=gen
```

If step 3 produces `out_*/asm_test/riscv_arithmetic_basic_test_0.S`, you're set.

### Custom install location (optional)

Our scripts default to `~/riscv-dv`. If you cloned elsewhere, export this in your
shell profile (`~/.bashrc`) so every `make` picks it up:

```bash
export RISCV_DV_HOME=/path/to/your/riscv-dv
```

> [!IMPORTANT]
> Use **`--target=rv32im`**, never `rv32imc`. SimX has no 16-bit RVC decoder and
> will crash on compressed instructions (see `docs/fixes/fix_08`). Our scripts
> already pass `rv32im` for you — this only matters if you invoke `run.py` by hand.

---

## Part 2 — Run a randomized test in our project

All commands run from **`vortex_uvm_env/`**. The trigger is simple: any
`PROGRAM=` value starting with **`riscv_`** routes through the riscv-dv pipeline
(`scripts/prepare.sh:275`).

### Basic run (reuses a cached random program)

```bash
make sim TEST=random_instruction_stress_test \
         PROGRAM=riscv_arithmetic_basic_test \
         TIMEOUT=200000
```

### Available profiles

| Profile (`PROGRAM=`)             | What it generates           | SimX-safe? |
|----------------------------------|-----------------------------|------------|
| `riscv_arithmetic_basic_test`    | arithmetic only, no ld/st/br | ✅ yes (our golden one) |
| `riscv_loop_test`                | loops + branches            | ✅ yes |
| `riscv_jump_stress_test`         | jump-heavy                  | ✅ yes |
| `riscv_rand_instr_test`          | full random (traps, `mret`) | ❌ run **without** SimX compare |

> [!IMPORTANT]
> Profiles that use privileged instructions (traps / `mret`) make SimX SIGABRT.
> Only the ✅ profiles are valid for end-state comparison against SimX.

---

## Part 3 — Controlling the randomization

### Fresh random stream (new seed each run)

By default the scripts **reuse** the newest pre-generated `.S` so reruns are
deterministic. To force a brand-new random program:

```bash
make sim TEST=random_instruction_stress_test \
         PROGRAM=riscv_arithmetic_basic_test \
         RISCV_DV_REGEN=1
```

`RISCV_DV_REGEN=1` re-invokes `run.py ... --steps=gen` (`prepare.sh:289`).

### Multiple back-to-back streams in one simulation

```bash
make sim TEST=random_instruction_stress_test \
         PROGRAM=riscv_arithmetic_basic_test \
         STRESS_ITER=8
```

`STRESS_ITER` → `+NUM_STRESS_ITER` plusarg read by the stress test
(`scripts/simulate.sh:60`).

### Combine with config knobs

The usual topology knobs apply to riscv-dv runs too:

```bash
make sim TEST=random_instruction_stress_test \
         PROGRAM=riscv_arithmetic_basic_test \
         CLUSTERS=1 CORES=1 WARPS=4 THREADS=4 \
         RISCV_DV_REGEN=1 STRESS_ITER=4 TIMEOUT=300000
```

---

## What the pipeline does for you (under the hood)

When `PROGRAM=riscv_*`, `scripts/prepare.sh` automatically:

1. **Finds or generates** the assembly — reuses newest
   `$RISCV_DV_HOME/out_*/asm_test/<name>_0.S`, or runs `run.py --steps=gen`
   (`prepare.sh:288–321`).
2. **Sanitizes** the `.S` for our DUT (`prepare.sh:388–394`):
   - strips machine-mode CSRs (`csrw/csrr 0x3xx`, `0xf14`) → `nop`
   - `mret` → `nop`
   - `ecall` → `ebreak` (so the TB sees `0x00100073` and detects completion)
3. **Compiles** `.S → ELF` with
   `riscv64-unknown-elf-gcc -march=rv32im_zicsr_zifencei -mabi=ilp32`
   (`prepare.sh:401–409`).
4. **Converts** ELF → hex and remaps the load address for the TB.
5. **Simulates** and compares DUT end-state vs SimX.

No manual generate/assemble/objcopy steps — just the `make sim` command.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| `riscv-dv not found at ~/riscv-dv` | Not installed, or wrong path — set `export RISCV_DV_HOME=...` |
| `Generated assembly not found` | `run.py` gen failed — check `results/<run>/logs/riscv_dv_gen.log` |
| SimX SIGABRT / crash | Used a privileged profile (e.g. `riscv_rand_instr_test`) or `rv32imc`. Use a ✅ profile, `rv32im` only |
| UVM_WARNING "vacuous run" | Pure-arithmetic profile wrote nothing to data regions — ISA stress is valid, but it isn't proving memory equivalence (see `docs/fixes/fix_12`) |
| `riscv64-unknown-elf-gcc: not found` | RISC-V toolchain not on `PATH` |

---

## References

- Generator: https://github.com/chipsalliance/riscv-dv
- Pipeline source: `scripts/prepare.sh` (riscv-dv case at line 275)
- Stress test class: `uvm_tests/random_instruction_stress_test.sv`
- Related fix docs: `docs/fixes/fix_06`–`fix_12` (the 6 root causes fixed to get
  riscv-dv passing end-to-end)
